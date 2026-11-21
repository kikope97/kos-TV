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
  }) : _prefetch = prefetch ?? _servicePrefetch,
       _report = report ?? _pluginReport,
       _endWait = endWait;

  /// The app's own.
  static KostvStreamPlayback instance = KostvStreamPlayback();

  final Future<StremfinPrefetch> Function(String deezerId) _prefetch;
  final Future<bool> Function(KostvStreamListen listen) _report;
  final Duration _endWait;

  QueueService? _queue;
  Duration Function() _duration = () => Duration.zero;
  bool Function() _playing = () => false;
  String Function() _source = () => KostvMusicSource.other;
  final _subs = <StreamSubscription<dynamic>>[];

  /// The deezer ids asked for in advance this session (asked once each).
  final _asked = <String>{};

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
  /// came from ([KostvMusicSource]). Again with another queue, the one
  /// before is let go.
  void attach({
    required QueueService queue,
    required Stream<Duration> positions,
    required Duration Function() duration,
    required bool Function() playing,
    String Function()? source,
  }) {
    detach();
    _queue = queue;
    _duration = duration;
    _playing = playing;
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
  }

  @visibleForTesting
  void debugReset() {
    detach();
    _asked.clear();
    _ready.clear();
    _soon?.cancel();
    _soon = null;
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

  void _askAhead() {
    for (final item in _upcoming()) {
      if (!isKostvStream(item)) continue;
      if (!_needsAsking(item)) continue;
      final deezerId = kostvStreamDeezerId(item)!;
      if (!_asked.contains(deezerId)) unawaited(_ask(deezerId));
      return;
    }
  }

  Future<void> _ask(String deezerId) async {
    if (_asked.length > 500) _asked.clear();
    _asked.add(deezerId);
    StremfinPrefetchState state;
    try {
      state = (await _prefetch(deezerId)).state;
    } on StremfinException catch (e) {
      // Not in Deezer, or the service doesn't let anyone listen: it won't
      // sound either.
      if (!e.isNotFound) return;
      state = StremfinPrefetchState.unavailable;
    } catch (_) {
      return;
    }
    switch (state) {
      case StremfinPrefetchState.ready:
        _ready.add(deezerId);
      case StremfinPrefetchState.unavailable:
        _dropUpcoming(deezerId);
      default:
        break;
    }
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

  /// Kos TV: the song [deezerId] may sound soon (the person rests on it on a
  /// page): once they have stayed [dwell] on it, it is asked for in advance,
  /// unless it is at home or ready already, or was asked for. Another one
  /// meanwhile (passing the songs by) takes its place.
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
      unawaited(_ask(deezerId));
    });
  }

  /// The person left the song before [prefetchSoon]'s wait was over.
  void cancelSoon() {
    _soon?.cancel();
    _soon = null;
  }

  // --- What was heard, for the server plugin ---

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
    Timer(_endWait, () {
      final now = _queue?.currentItem;
      if (now == null || _queue == null) return send('stop');
      send(identical(now, item) ? 'stop' : 'next');
    });
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
