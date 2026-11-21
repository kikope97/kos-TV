import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../data/models/aggregated_item.dart';
import '../data/services/kostv_music_plugin.dart';
import '../data/services/stremfin/kostv_stream_song.dart';
import '../data/services/stremfin/stremfin_client.dart';
import '../data/services/stremfin/stremfin_models.dart';
import '../data/services/stremfin/stremfin_service.dart';
import 'stremfin_stream_resolver.dart';

/// Kos TV: what goes with the songs that aren't at home while the queue
/// plays them (`docs/musica-toda-la-musica.md` §3 and §7):
///
/// - **Asking ahead** («Adelantar sin pasarse»): once the song sounding is
///   halfway through (or has 90 s left, whichever comes first), the next one
///   of the queue (the one that really sounds next, shuffled or not) is
///   asked for in advance if it isn't at home nor ready, or, when that one
///   needs nothing, the one after it. Never more, never the whole list.
///   Asked again whenever what comes next changes. One the service can't
///   have (`unavailable`) leaves the queue before it is reached.
/// - **Telling the server plugin** what was heard of each (`stream_listen`),
///   for what it learns, as the home server tells it of what is at home.
/// - [prefetchSoon], for the pages: a song the person rests on a moment.
class KostvStreamPlayback {
  KostvStreamPlayback({
    Future<StremfinPrefetch> Function(String deezerId)? prefetch,
    Future<bool> Function(KostvStreamListen listen)? report,
    @visibleForTesting Duration endWait = const Duration(milliseconds: 700),
    @visibleForTesting DateTime Function()? now,
  }) : _prefetch = prefetch ?? _servicePrefetch,
       _report = report ?? _pluginReport,
       _endWait = endWait,
       _now = now ?? DateTime.now;

  /// The app's own.
  static KostvStreamPlayback instance = KostvStreamPlayback();

  final Future<StremfinPrefetch> Function(String deezerId) _prefetch;
  final Future<bool> Function(KostvStreamListen listen) _report;
  final Duration _endWait;
  final DateTime Function() _now;

  QueueService? _queue;
  Duration Function() _duration = () => Duration.zero;
  bool Function() _playing = () => false;
  bool Function() _restarting = () => false;
  String Function() _source = () => KostvMusicSource.other;
  final _subs = <StreamSubscription<dynamic>>[];

  /// The deezer ids asked for in advance this session (asked once each):
  /// those the service answered, ready or not, or said it can't have.
  final _asked = <String>{};

  /// Kos TV: those being asked for now. One that fails (too many calls, no
  /// network) isn't kept as asked: it is asked for again later.
  final _asking = <String>{};

  /// Those the service has ready (they start at once).
  final _ready = <String>{};

  // The song sounding: its id, whether what comes after it was asked for,
  // and how much of it has been heard (the player's own progress, not where
  // it is: a jump forward doesn't count as heard).
  String? _currentId;
  bool _halfway = false;
  double _heard = 0;
  Duration? _lastPosition;

  /// Listens to [queue] and to the player's [positions], for the songs
  /// that aren't at home it plays. [duration] is the song's length as the
  /// player knows it, [playing] whether it sounds, [source] where the queue
  /// came from ([KostvMusicSource]), [restarting] whether the player is
  /// opening a song (again). Again with another queue, the one before is let
  /// go.
  void attach({
    required QueueService queue,
    required Stream<Duration> positions,
    required Duration Function() duration,
    required bool Function() playing,
    String Function()? source,
    bool Function()? restarting,
  }) {
    detach();
    _queue = queue;
    _duration = duration;
    _playing = playing;
    _restarting = restarting ?? () => false;
    if (source != null) _source = source;
    _subs
      ..add(positions.listen(onProgress))
      ..add(queue.queueChangedStream.listen((_) => onQueueChanged()));
    onQueueChanged();
  }

  /// The app's player.
  void attachTo(PlaybackManager manager, {String Function()? source}) => attach(
    queue: manager.queueService,
    positions: manager.state.positionStream,
    duration: () => manager.state.duration,
    playing: () => manager.state.isPlaying,
    source: source,
    restarting: () => manager.bringupState.phase.isInProgress,
  );

  void detach() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _queue = null;
    _currentId = null;
    _halfway = false;
    _heard = 0;
    _lastPosition = null;
    _aheadRetry?.cancel();
    _aheadRetry = null;
  }

  @visibleForTesting
  void debugReset() {
    detach();
    _asked.clear();
    _asking.clear();
    _ready.clear();
    _soon?.cancel();
    _soon = null;
    _resting = false;
    _restedAt = null;
    _started.clear();
    _starts.clear();
  }

  /// Whether [deezerId] was found ready by an ask ahead.
  bool isReady(String deezerId) => _ready.contains(deezerId);

  AggregatedItem? get _current {
    final item = _queue?.currentItem;
    return item is AggregatedItem ? item : null;
  }

  void _follow() {
    final id = _current?.id;
    if (id == _currentId) return;
    _currentId = id;
    _halfway = false;
    _heard = 0;
    _lastPosition = null;
    _aheadRetry?.cancel();
    _aheadRetry = null;
    _aheadRetried = false;
  }

  /// The player's position moved to [position].
  @visibleForTesting
  void onProgress(Duration position) {
    _follow();
    final current = _current;
    if (current == null) return;
    final last = _lastPosition;
    _lastPosition = position;
    if (last != null && _playing()) {
      final step = position - last;
      if (step > Duration.zero && step <= const Duration(milliseconds: 2500)) {
        _heard += step.inMilliseconds / 1000;
      }
    }
    if (_halfway || position <= Duration.zero) return;
    var length = _duration();
    if (length <= Duration.zero) length = current.runtime ?? Duration.zero;
    if (length <= Duration.zero) return;
    final half = position * 2 >= length;
    final nearEnd = length - position <= const Duration(seconds: 90);
    if (!half && !nearEnd) return;
    _halfway = true;
    _askAhead();
  }

  /// The queue changed: what comes next may be another song.
  @visibleForTesting
  void onQueueChanged() {
    _follow();
    if (_halfway) _askAhead();
  }

  /// The next two songs that will sound after the one sounding.
  List<AggregatedItem> _upcoming() {
    final queue = _queue;
    if (queue == null) return const [];
    final items = queue.items;
    final at = queue.currentIndex;
    if (at < 0 || items.isEmpty) return const [];
    final wraps = queue.repeatMode == RepeatMode.repeatAll;
    final out = <AggregatedItem>[];
    for (var step = 1; step <= 2; step++) {
      var i = at + step;
      if (i >= items.length) {
        if (!wraps) break;
        i %= items.length;
      }
      if (i == at) break;
      final item = items[i];
      if (item is AggregatedItem) out.add(item);
    }
    return out;
  }

  bool _needsAsking(AggregatedItem item) {
    final info = KostvStreamInfo.of(item);
    if (info == null) return false;
    if (info.listenReady || _ready.contains(info.deezerId)) return false;
    if (StremfinStreamResolver.atHome.containsKey(item.id)) return false;
    return true;
  }

  // Kos TV: an ask ahead that got no answer (too many calls, no network) is
  // tried once more a while later, while the same song sounds.
  static const _aheadRetryAfter = Duration(seconds: 15);
  Timer? _aheadRetry;
  bool _aheadRetried = false;

  void _askAhead() {
    for (final item in _upcoming()) {
      if (!isKostvStream(item)) continue;
      if (!_needsAsking(item)) continue;
      final deezerId = kostvStreamDeezerId(item)!;
      if (!_asked.contains(deezerId)) unawaited(_askNext(deezerId));
      return;
    }
  }

  Future<void> _askNext(String deezerId) async {
    final sounding = _currentId;
    if (await _ask(deezerId)) return;
    if (_aheadRetried || _aheadRetry != null || _currentId != sounding) {
      return;
    }
    _aheadRetry = Timer(_aheadRetryAfter, () {
      _aheadRetry = null;
      _aheadRetried = true;
      if (_currentId == sounding && _halfway) _askAhead();
    });
  }

  /// Asks the service for [deezerId] in advance. False when it got no
  /// answer (too many calls, no network): that isn't kept as asked.
  Future<bool> _ask(String deezerId) async {
    if (_asked.contains(deezerId) || !_asking.add(deezerId)) return true;
    StremfinPrefetchState state;
    try {
      state = (await _prefetch(deezerId)).state;
    } on StremfinException catch (e) {
      // Not in Deezer, or the service doesn't let anyone listen: it won't
      // sound either.
      if (!e.isNotFound) {
        _asking.remove(deezerId);
        return false;
      }
      state = StremfinPrefetchState.unavailable;
    } catch (_) {
      _asking.remove(deezerId);
      return false;
    }
    _asking.remove(deezerId);
    if (_asked.length > 500) _asked.clear();
    _asked.add(deezerId);
    switch (state) {
      case StremfinPrefetchState.ready:
        _ready.add(deezerId);
      case StremfinPrefetchState.unavailable:
        _dropUpcoming(deezerId);
      default:
        break;
    }
    return true;
  }

  /// Takes [deezerId] out of what is still to sound (not the one sounding:
  /// it says so itself when it fails).
  void _dropUpcoming(String deezerId) {
    final queue = _queue;
    if (queue == null) return;
    for (var i = queue.items.length - 1; i >= 0; i--) {
      if (i == queue.currentIndex) continue;
      if (kostvStreamDeezerId(queue.items[i]) == deezerId) queue.removeAt(i);
    }
  }

  // --- A song the person rests on ---

  Timer? _soon;

  /// Kos TV: at most one song rested on is asked for at a time, and one
  /// every this long (as fast as the service gets them): resting on song
  /// after song doesn't use up what the person may ask for, which the next
  /// song of the queue ([_askAhead], never held back by this) needs.
  static const restGap = Duration(seconds: 10);
  bool _resting = false;
  DateTime? _restedAt;

  /// Kos TV: the song [deezerId] may sound soon (the person rests on it on a
  /// page): once they have stayed [dwell] on it, it is asked for in advance,
  /// unless it is at home or ready already, or was asked for. Another one
  /// meanwhile (passing the songs by) takes its place. See [restGap].
  void prefetchSoon(
    String? deezerId, {
    bool listenReady = false,
    bool atHome = false,
    Duration dwell = const Duration(milliseconds: 2500),
  }) {
    _soon?.cancel();
    _soon = null;
    if (deezerId == null || deezerId.isEmpty) return;
    if (listenReady || atHome) return;
    if (_asked.contains(deezerId) || _ready.contains(deezerId)) return;
    _soon = Timer(dwell, () {
      _soon = null;
      _askRested(deezerId);
    });
  }

  void _askRested(String deezerId) {
    if (_asked.contains(deezerId) ||
        _asking.contains(deezerId) ||
        _ready.contains(deezerId)) {
      return;
    }
    final at = _restedAt;
    final since = at == null ? null : _now().difference(at);
    if (_resting || (since != null && since < restGap)) {
      // Still resting on it: asked for once the one before allows.
      final wait = since != null && since < restGap
          ? restGap - since
          : const Duration(seconds: 2);
      _soon = Timer(wait, () {
        _soon = null;
        _askRested(deezerId);
      });
      return;
    }
    _resting = true;
    _restedAt = _now();
    unawaited(_ask(deezerId).whenComplete(() => _resting = false));
  }

  /// The person left the song before [prefetchSoon]'s wait was over.
  void cancelSoon() {
    _soon?.cancel();
    _soon = null;
  }

  // --- What was heard, for the server plugin ---

  /// Kos TV: the songs that started sounding and haven't stopped: only these
  /// are told when they stop, as the home server only closes a listen it saw
  /// start. One left before it sounded (another song chosen while it was
  /// being prepared, one prepared ahead that never came to sound) has
  /// nothing to tell.
  final _started = <String>{};

  /// How many times each song started, to tell a stop from one opened again.
  final _starts = <String, int>{};

  /// How long the stop of a song still in the queue waits while the player
  /// opens it again (asked again for its sound after an error, another
  /// track) before it is told as a stop.
  static const _reopenWait = Duration(seconds: 30);

  /// Told by the player's reports when a song that isn't at home started.
  void started(dynamic item) {
    if (item is! AggregatedItem || !isKostvStream(item)) return;
    _started.add(item.id);
    if (_starts.length > 200) _starts.clear();
    _starts[item.id] = (_starts[item.id] ?? 0) + 1;
  }

  /// Told by the player's reports when a song that isn't at home stopped,
  /// at [position], and whether it [failed].
  void stopped(dynamic item, Duration position, bool failed) {
    if (item is! AggregatedItem || !isKostvStream(item)) return;
    final info = KostvStreamInfo.of(item)!;
    final heard = _currentId == item.id && _heard > 0
        ? _heard
        : position.inMilliseconds / 1000;
    if (_currentId == item.id) {
      _heard = 0;
      _lastPosition = null;
    }
    // Only what started is told, and once.
    if (!_started.remove(item.id)) return;
    // Nothing heard of one that didn't start: there is nothing to tell.
    if (failed && heard < 1) return;
    var length = item.runtime ?? Duration.zero;
    final player = _duration();
    if (length <= Duration.zero && player > Duration.zero) length = player;
    final source = _source();
    final shuffle = _queue?.isShuffled ?? false;
    void send(String endedBy) => unawaited(
      _report(
        KostvStreamListen(
          deezerId: info.deezerId,
          title: item.name,
          artist: item.artists.isNotEmpty
              ? item.artists.join(', ')
              : item.albumArtist,
          album: item.album,
          genre: item.genres.firstOrNull,
          played: heard,
          duration: length > Duration.zero ? length.inSeconds : null,
          endedBy: endedBy,
          source: source,
          shuffle: shuffle,
        ),
      ).catchError((Object _) => false),
    );
    if (failed) return send('error');
    if (length > Duration.zero &&
        position >= length - const Duration(seconds: 3)) {
      return send('natural');
    }
    // Stopped part way: by going on to another song, or by stopping. The
    // queue says which a moment later (the stop is told before it moves).
    final starts = _starts[item.id] ?? 0;
    final until = _now().add(_reopenWait);
    void settle() {
      final now = _queue?.currentItem;
      if (now == null || _queue == null) return send('stop');
      if (!identical(now, item)) return send('next');
      // Still the same song: opened again, which goes on as one listen with
      // what was heard so far; being opened again; or stopped.
      if ((_starts[item.id] ?? 0) != starts) {
        if (_currentId == item.id) _heard += heard;
        return;
      }
      if (_restarting() && _now().isBefore(until)) {
        Timer(_endWait, settle);
        return;
      }
      send('stop');
    }

    Timer(_endWait, settle);
  }

  static Future<StremfinPrefetch> _servicePrefetch(String deezerId) {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) {
      return Future.error(const StremfinException(code: 'not_configured'));
    }
    return getIt<StremfinService>().musicPrefetch(deezerId);
  }

  static Future<bool> _pluginReport(KostvStreamListen listen) async {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<MediaServerClient>()) return false;
    return KostvMusicPlugin.instance.sendStreamListen(
      getIt<MediaServerClient>(),
      deezerId: listen.deezerId,
      title: listen.title,
      artist: listen.artist,
      album: listen.album,
      genre: listen.genre,
      played: listen.played,
      duration: listen.duration,
      endedBy: listen.endedBy,
      source: listen.source,
      shuffle: listen.shuffle,
    );
  }
}

/// Kos TV: one listen of a song that isn't at home, for the server plugin.
@immutable
class KostvStreamListen {
  const KostvStreamListen({
    required this.deezerId,
    required this.title,
    this.artist,
    this.album,
    this.genre,
    required this.played,
    this.duration,
    required this.endedBy,
    required this.source,
    this.shuffle = false,
  });

  final String deezerId;
  final String title;
  final String? artist;
  final String? album;

  /// Kos TV: its album's genre, when the requests service gave it.
  final String? genre;

  /// Seconds heard.
  final double played;

  /// Seconds the song lasts.
  final int? duration;

  /// `natural`, `next`, `stop`, `closed` or `error`.
  final String endedBy;
  final String source;
  final bool shuffle;
}

/// Kos TV: the person rests on [song] on a page (the focus or the mouse on
/// it a couple of seconds, an album's page left open): asked for in advance
/// when it isn't at home nor ready. See [KostvStreamPlayback.prefetchSoon].
void kostvPrefetchSoon(StremfinSong song, {Duration? dwell}) =>
    KostvStreamPlayback.instance.prefetchSoon(
      song.deezerId,
      listenReady: song.listenReady,
      atHome: song.atHome,
      dwell: dwell ?? const Duration(milliseconds: 2500),
    );

/// Kos TV: [kostvPrefetchSoon] of an album's song.
void kostvPrefetchSoonTrack(StremfinAlbumTrack track, {Duration? dwell}) =>
    KostvStreamPlayback.instance.prefetchSoon(
      track.deezerId,
      listenReady: track.listenReady,
      atHome: track.atHome,
      dwell: dwell ?? const Duration(milliseconds: 2500),
    );

/// Kos TV: the person left the song they rested on.
void kostvPrefetchCancel() => KostvStreamPlayback.instance.cancelSoon();

final _probeDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
    followRedirects: true,
    validateStatus: (_) => true,
  ),
);

/// Kos TV: the status the address of an out-of-home song's sound gets now
/// (`HEAD`), for [StremfinStreamResolver]; null when it couldn't be asked.
Future<int?> kostvStreamProbe(String url) async {
  try {
    final response = await _probeDio.head<void>(url);
    return response.statusCode;
  } catch (_) {
    return null;
  }
}
