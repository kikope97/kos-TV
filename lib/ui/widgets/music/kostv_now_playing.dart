import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music_away.dart';
import '../../../data/services/kostv_music_dislikes.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../data/services/stremfin/kostv_stream_radio.dart'
    show KostvStreamRadio, kostvSongKey;
import '../../../data/services/stremfin/kostv_stream_song.dart';
import '../../../l10n/app_localizations.dart';
import '../../../playback/kostv_stream_playback.dart';
import '../../../playback/stremfin_stream_resolver.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/audio_artwork_url.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/app_router.dart';
import '../../screens/playback/osd_buttons.dart'
    show playerVolumeIgnoredByBrowser;
import '../floating_notification.dart';
import 'design/kostv_artwork_colors.dart';
import 'kostv_now_playing_web_session.dart';
import 'kostv_stream_play.dart'
    show kostvPluginStationFor, kostvSongStation, kostvStationWantsRadio;

/// Kos TV: the music sounding in the app, for the floating player and the
/// «Reproduciendo» page: which song, whether it plays, and the colours of
/// its cover.
class KostvNowPlaying extends ChangeNotifier {
  KostvNowPlaying._();

  static final instance = KostvNowPlaying._();

  final _subs = <StreamSubscription<dynamic>>[];
  bool _started = false;
  String? _itemId;
  bool _playing = false;

  PlaybackManager? get _manager =>
      GetIt.instance.isRegistered<PlaybackManager>()
      ? GetIt.instance<PlaybackManager>()
      : null;

  /// Listens to the app's player, once it exists.
  void ensureStarted() {
    if (_started) return;
    final manager = _manager;
    if (manager == null) return;
    _started = true;
    try {
      // Kos TV: «Al acabar la canción» stops at the end of this song, so the
      // next one isn't queued to follow it with no gap.
      manager.preloadVeto = () => _sleepAfterSong;
    } catch (_) {
      // A stand-in player (the tests') without it.
    }
    _subs.addAll([
      manager.state.playingStream.listen((_) => _changed()),
      manager.queueService.queueChangedStream.listen((_) => _changed()),
    ]);
    try {
      // The queue played to its end: the music is over (otherwise the
      // floating player would stay with the last song and dead buttons).
      _subs.add(
        manager.sessionEndedStream.listen((_) {
          final ended = item;
          if (ended != null && ended.type == 'Audio') {
            unawaited(manager.stop(userInitiated: false));
          }
        }),
      );
    } catch (_) {
      // A stand-in player (the tests') without it.
    }
    try {
      // Kos TV: a song that couldn't start is told, with a way to try again.
      _subs.add(manager.bringupStateStream.listen(_bringupChanged));
      // The browser (Safari on the iPhone) wants a tap to start it.
      _subs.add(manager.playBlockedStream.listen((_) => _tellBlocked()));
    } catch (_) {
      // A stand-in player (the tests') without it.
    }
    try {
      // Kos TV: with repeat-one the song starts over with the same id, which
      // [_changed] can't tell from it going on.
      _subs.add(manager.repeatedStream.listen((_) => _songRepeated()));
    } catch (_) {
      // A stand-in player (the tests') without it.
    }
    try {
      // Kos TV: the music's own volume goes to a new player too.
      _subs.add(manager.backendChangedStream.listen((_) => _applyVolume()));
    } catch (_) {
      // A stand-in player (the tests') without it.
    }
    // Kos TV: the songs that aren't at home: what is prepared, asked ahead
    // and heard of them, and those that turn out to be at home.
    _subs.add(StremfinStreamResolver.arrivals.listen(_atHome));
    StremfinStreamResolver.preparing.addListener(_preparingChanged);
    if (StremfinStreamResolver.preparing.value != null) _preparingChanged();
    try {
      KostvStreamPlayback.instance.attachTo(
        manager,
        source: () => _queueSource ?? KostvMusicSource.other,
      );
    } catch (_) {
      // A stand-in player (the tests') without it.
    }
    // Kos TV: on the web, the browser's lock screen and media keys.
    attachKostvWebMediaSession(this);
    // Often started while a menu is being built: what it finds is told
    // after that, not in the middle of the build.
    scheduleMicrotask(_changed);
  }

  /// Forgets the player it listened to, for the tests' new one.
  @visibleForTesting
  void debugReset() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _started = false;
    _itemId = null;
    _playing = false;
    setSleep(null);
    _sleepAfterSong = false;
    _failedId = null;
    _failureCheck?.cancel();
    _failureCheck = null;
    _volume = null;
    _volumeOn = null;
    _volumeAt = null;
    _persistVolume?.cancel();
    _persistVolume = null;
    autoplayItems.clear();
    automaticItems.clear();
    _queueStart = null;
    _stationLater?.cancel();
    _stationLater = null;
    _queueGeneration++;
    _autoplaySeed = null;
    _autoplayRetry?.cancel();
    _autoplayRetry = null;
    StremfinStreamResolver.preparing.removeListener(_preparingChanged);
    _slowPreparing?.cancel();
    _slowPreparing = null;
    _preparingSlow = false;
    _showPreparing?.cancel();
    _showPreparing = null;
    _preparingShown = false;
    _preparingId = null;
    _streamRetried.clear();
    _queueSource = null;
  }

  void _changed() {
    unawaited(_maybeAutoplay());
    // Kos TV: set again for each new song, whatever the player did before.
    if (this.item?.id != _itemId) _volumeOn = null;
    _applyVolume();
    final item = this.item;
    final playing = _manager?.state.isPlaying ?? false;
    if (item?.id == _itemId && playing == _playing) return;
    if (item?.id != _itemId) {
      final before = _itemId;
      _itemId = item?.id;
      _loadColors(item);
      // Kos TV: the new song may be the one being prepared (ahead, or now).
      _reviewPreparing();
      if (item == null) {
        // Nothing sounds any more: what went with it goes too.
        setSleep(null);
        _sleepAfterSong = false;
        _autoplaySeed = null;
        autoplayItems.clear();
        automaticItems.clear();
        _queueStart = null;
        _stationLater?.cancel();
        _stationLater = null;
        _queueGeneration++;
      } else if (_sleepAfterSong && before != null && !_personChose()) {
        // «Al acabar la canción»: the next one doesn't go on. One the person
        // chose (skipped to, or another album put on) isn't the song ending:
        // the timer goes on to it.
        _sleepAfterSong = false;
        unawaited(_manager?.pause());
      }
      _choseAt = null;
    }
    _playing = playing;
    notifyListeners();
  }

  /// The song ended by itself and started over (repeat-one): for «Al acabar
  /// la canción» that is the end of it.
  void _songRepeated() {
    if (!_sleepAfterSong || item == null) return;
    _sleepAfterSong = false;
    unawaited(_manager?.pause());
    notifyListeners();
  }

  /// The song (or audiobook) sounding, or null when there is none.
  AggregatedItem? get item {
    final manager = _manager;
    final raw = manager?.queueService.currentItem;
    if (raw is AggregatedItem) return raw.isAudioLike ? raw : null;
    // What was downloaded plays from what was kept of it.
    if (raw == null || manager == null) return null;
    final meta = manager.currentOfflineMetadata;
    if (meta == null) return null;
    final found = AggregatedItem(
      id: meta['Id']?.toString() ?? '$raw',
      serverId: meta['ServerId']?.toString() ?? '',
      rawData: meta,
    );
    return found.isAudioLike ? found : null;
  }

  bool get playing => _manager?.state.isPlaying ?? false;

  /// Kos TV: the id of the song sounding and whether it plays, apart from
  /// everything else that changes here («preparando», autoplay, the
  /// colours…): a song's row follows only this, and only redraws when its
  /// own song starts or stops sounding (a page has many rows).
  final sounding = ValueNotifier<({String? id, bool playing})>((
    id: null,
    playing: false,
  ));

  @override
  void notifyListeners() {
    sounding.value = (id: item?.id, playing: playing);
    super.notifyListeners();
  }

  PlayerState? get state => _manager?.state;

  String? artUrl(AggregatedItem item, {int maxHeight = 300}) {
    // Kos TV: one that isn't at home has Deezer's cover.
    if (isKostvStream(item)) return KostvStreamInfo.of(item)?.cover;
    if (!GetIt.instance.isRegistered<MediaServerClientFactory>()) return null;
    return audioArtUrl(
      item,
      clientFactory: GetIt.instance<MediaServerClientFactory>(),
      maxHeight: maxHeight,
    );
  }

  String artistOf(AggregatedItem item) => item.artists.isNotEmpty
      ? item.artists.join(', ')
      : item.albumArtist ?? '';

  void playPause() {
    final manager = _manager;
    if (manager == null) return;
    // Kos TV: a song that couldn't start has nothing to resume: ⏯ tries it
    // again (the TV's way to, where the notice has no button).
    if (failed) {
      retry();
      return;
    }
    unawaited(manager.state.isPlaying ? manager.pause() : manager.resume());
  }

  // --- A song that couldn't start ---

  String? _failedId;
  Timer? _failureCheck;

  /// The song sounding couldn't start (the server didn't answer, a format
  /// that won't play…).
  bool get failed => _failedId != null && _failedId == item?.id;

  void _bringupChanged(PlaybackBringupState state) {
    if (state.phase != PlaybackBringupPhase.failed) {
      // Kos TV: one that isn't at home that did start may be asked for
      // again another time.
      if (state.phase == PlaybackBringupPhase.ready) {
        _streamRetried.remove(state.itemId);
      }
      // Another go at it (a retry, the next song) clears it.
      if (state.phase.isInProgress ||
          state.phase == PlaybackBringupPhase.ready) {
        _failureCheck?.cancel();
        _failureCheck = null;
        if (_failedId != null) {
          _failedId = null;
          notifyListeners();
        }
      }
      return;
    }
    final song = item;
    if (song == null || song.type != 'Audio') return;
    if (!_startOf(state.itemId, song)) return;
    // Kos TV: one that isn't at home says why, in its own words.
    if (isKostvStream(song)) {
      _streamFailed(song);
      return;
    }
    // The player may still get there another way (the server converting
    // it): only told if it is still failed a moment later.
    _failureCheck?.cancel();
    _failureCheck = Timer(const Duration(milliseconds: 1500), () {
      _failureCheck = null;
      final manager = _manager;
      if (manager == null || item?.id != song.id) return;
      if (manager.bringupState.phase != PlaybackBringupPhase.failed) return;
      if (manager.state.isPlaying) return;
      _failedId = song.id;
      notifyListeners();
      _tellFailure(song);
    });
  }

  /// Kos TV: whether this song's own failed start is being told by the
  /// player (with its retry), so whoever asked to play it doesn't tell it a
  /// second time.
  bool tellsStartFailure() {
    final manager = _manager;
    final song = item;
    if (manager == null || song == null || song.type != 'Audio') return false;
    final state = manager.bringupState;
    if (state.phase != PlaybackBringupPhase.failed) return false;
    return _startOf(state.itemId, song);
  }

  /// Kos TV: whether the start the player tells of ([itemId]) is [song]'s:
  /// its own, or that of the out-of-home song it was before it turned out
  /// to be at home (the player still names the start by that one).
  bool _startOf(String? itemId, AggregatedItem song) =>
      itemId == null ||
      itemId == song.id ||
      (isKostvStreamId(itemId) &&
          StremfinStreamResolver.atHome[itemId]?.id == song.id);

  void _tellFailure(AggregatedItem song) {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    final tv = PlatformDetection.useLeanbackUi;
    FloatingNotification.show(
      context,
      l10n.kostvMusicPlayFailed(song.name),
      tv ? l10n.kostvMusicPlayFailedTvHint : l10n.kostvMusicPlayFailedHint,
      null,
      icon: Icons.music_off_rounded,
      actions: tv ? const [] : [(l10n.retry, retry)],
    );
  }

  // --- Songs that aren't at home ---

  /// The out-of-home songs already tried again once after the player
  /// couldn't open their sound (its address may have stopped working).
  final _streamRetried = <String>{};

  /// Kos TV: an out-of-home song couldn't start. One nobody can listen to
  /// (404) is said and skipped; with the service not answering (503, no
  /// network) it is said, to try later; one whose sound the player couldn't
  /// open is asked for again once, then told as any other.
  void _streamFailed(AggregatedItem song) {
    final failure = StremfinStreamResolver.failures[song.id];
    final manager = _manager;
    if (failure == null) {
      final deezerId = kostvStreamDeezerId(song);
      if (deezerId != null && _streamRetried.add(song.id) && manager != null) {
        StremfinStreamResolver.forget(deezerId);
        final index = manager.queueService.currentIndex;
        if (index >= 0) {
          unawaited(manager.playFromQueue(index).catchError((_) {}));
          return;
        }
      }
      _failedId = song.id;
      notifyListeners();
      _tellFailure(song);
      return;
    }
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    final l10n = context != null && context.mounted
        ? AppLocalizations.of(context)
        : null;
    if (failure == KostvStreamFailure.notFound) {
      if (context != null && l10n != null) {
        FloatingNotification.show(
          context,
          l10n.kostvStreamCantListen,
          song.name,
          null,
          icon: Icons.music_off_rounded,
        );
      }
      if (manager != null && manager.queueService.hasNext) {
        noteChosen();
        unawaited(manager.nextInQueue().catchError((_) {}));
      } else {
        _failedId = song.id;
        notifyListeners();
      }
      return;
    }
    _failedId = song.id;
    notifyListeners();
    if (context != null && l10n != null) {
      FloatingNotification.show(
        context,
        l10n.kostvStreamUnavailableNow,
        song.name,
        null,
        icon: Icons.cloud_off_rounded,
        actions: PlatformDetection.useLeanbackUi
            ? const []
            : [(l10n.retry, retry)],
      );
    }
  }

  Timer? _slowPreparing;
  bool _preparingSlow = false;

  /// How long «Preparando la canción…» waits before it says it is taking
  /// longer than usual.
  static const slowPreparing = Duration(seconds: 20);

  /// Kos TV: the song sounding isn't at home and its sound is being prepared
  /// (the service is getting it): «Preparando la canción…».
  bool get preparing {
    final song = item;
    return song != null && StremfinStreamResolver.preparing.value == song.id;
  }

  /// Kos TV: [preparing] has gone on for [slowPreparing].
  bool get preparingSlow => preparing && _preparingSlow;

  /// Kos TV: how long [preparing] lasts before the player and the floating
  /// player say so (the music design: no flash of «Preparando…» for a song
  /// that starts at once).
  static const preparingShowsAfter = Duration(milliseconds: 1500);

  Timer? _showPreparing;
  bool _preparingShown = false;

  /// Kos TV: [preparing] has gone on for [preparingShowsAfter]: what shows
  /// «Preparando la canción…» (and the cover's gentle beat).
  bool get preparingShown => preparing && _preparingShown;

  /// Kos TV: the song sounding whose sound [_slowPreparing] times, if any.
  String? _preparingId;

  /// Kos TV: only the song sounding counts: the next one prepared ahead
  /// neither starts the wait for «tardando» nor redraws anything.
  void _preparingChanged() {
    if (_reviewPreparing()) notifyListeners();
  }

  /// Times [preparing] again when it changed; true when it did.
  bool _reviewPreparing() {
    final id = preparing ? item?.id : null;
    if (id == _preparingId) return false;
    _preparingId = id;
    _slowPreparing?.cancel();
    _slowPreparing = null;
    _preparingSlow = false;
    _showPreparing?.cancel();
    _showPreparing = null;
    _preparingShown = false;
    if (id != null) {
      _showPreparing = Timer(preparingShowsAfter, () {
        _showPreparing = null;
        _preparingShown = true;
        notifyListeners();
      });
      _slowPreparing = Timer(slowPreparing, () {
        _slowPreparing = null;
        _preparingSlow = true;
        notifyListeners();
      });
    }
    return true;
  }

  /// Kos TV: an out-of-home song turned out to be at home: the home
  /// server's takes its place in the queue (its ♥, its lyrics, its
  /// reports), with what was known of it (autoplay's, come by itself).
  void _atHome(KostvStreamAtHome found) {
    // Kos TV: the server plugin moves it into the person's playlists and ♥
    // (told once for each song this session).
    final deezerId = kostvStreamDeezerId(found.stream);
    final client = _clientOf(found.home);
    final store = KostvMusicAwayStore.instance;
    // Kos TV: with the person's ♥ given while it wasn't at home, it shows
    // on the home one at once (read before the plugin made it Jellyfin's).
    final loved = deezerId != null && store.isFavorite(client, deezerId);
    if (deezerId != null) {
      unawaited(store.arrived(client, deezerId, found.home.id));
    }
    final manager = _manager;
    if (manager == null) return;
    final queue = manager.queueService;
    final items = queue.items;
    final rawData = loved
        ? _withFavorite(found.home.rawData)
        : found.home.rawData;
    for (var i = 0; i < items.length; i++) {
      final entry = items[i];
      if (entry is! AggregatedItem || entry.id != found.stream.id) continue;
      final home = AggregatedItem(
        id: found.home.id,
        serverId: found.home.serverId,
        rawData: rawData,
      );
      if (autoplayItems.remove(entry)) autoplayItems.add(home);
      if (automaticItems.remove(entry)) automaticItems.add(home);
      if (identical(_queueStart, entry)) _queueStart = home;
      // The song sounding changing its id isn't the person choosing another
      // one, nor the last one ending («Al acabar la canción»).
      if (i == queue.currentIndex) _itemId = home.id;
      queue.replaceAt(i, home);
    }
  }

  /// Kos TV: [rawData] of a song with the person's ♥.
  static Map<String, dynamic> _withFavorite(Map<String, dynamic> rawData) {
    final data = rawData['UserData'];
    return {
      ...rawData,
      'UserData': {
        if (data is Map) ...data.cast<String, dynamic>(),
        'IsFavorite': true,
      },
    };
  }

  /// Kos TV: the client of [item]'s server (the one signed in otherwise).
  static MediaServerClient? _clientOf(AggregatedItem item) {
    try {
      final getIt = GetIt.instance;
      if (getIt.isRegistered<MediaServerClientFactory>()) {
        final client = getIt<MediaServerClientFactory>().getClientIfExists(
          item.serverId,
        );
        if (client != null) return client;
      }
      return getIt.isRegistered<MediaServerClient>()
          ? getIt<MediaServerClient>()
          : null;
    } catch (_) {
      return null;
    }
  }

  void _tellBlocked() {
    final song = item;
    if (song == null) return;
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    FloatingNotification.show(
      context,
      l10n.kostvMusicTapToPlay,
      l10n.kostvMusicTapToPlayHint,
      null,
      icon: Icons.play_circle_outline_rounded,
      actions: [(l10n.play, () => unawaited(_manager?.resume()))],
    );
  }

  /// Tries the song that couldn't start again.
  void retry() {
    final manager = _manager;
    if (manager == null) return;
    _failedId = null;
    notifyListeners();
    noteChosen();
    final index = manager.queueService.currentIndex;
    if (index < 0) return;
    unawaited(manager.playFromQueue(index).catchError((_) {}));
  }

  void next() {
    noteChosen();
    unawaited(_manager?.next());
  }

  void previous() {
    noteChosen();
    unawaited(_manager?.previous());
  }

  /// The song about to sound is the person's choice, not the one before
  /// ending.
  ///
  /// Kos TV: only for a little while. A choice that didn't change the song
  /// (back to the start of it, radio from the one sounding) mustn't count
  /// when it ends later on its own.
  DateTime? _choseAt;
  static const _choiceLasts = Duration(seconds: 10);
  bool _personChose() {
    final at = _choseAt;
    return at != null && DateTime.now().difference(at) < _choiceLasts;
  }

  void noteChosen() => _choseAt = DateTime.now();

  /// The ✕: the music stops and the floating player goes away.
  void close() {
    setSleep(null);
    _sleepAfterSong = false;
    unawaited(_manager?.stop());
  }

  // --- The music's own volume (the web on a computer) ---

  /// Kos TV: whether the music has its own volume, apart from the videos':
  /// only on the web on a computer. Safari on an iPhone or an iPad ignores
  /// it, and the TV and the phone use the device's own volume.
  static bool get hasOwnVolume =>
      debugHasOwnVolume ??
      (kIsWeb &&
          !playerVolumeIgnoredByBrowser &&
          PlatformDetection.useDesktopUi);

  @visibleForTesting
  static bool? debugHasOwnVolume;

  UserPreferences? get _prefs => GetIt.instance.isRegistered<UserPreferences>()
      ? GetIt.instance<UserPreferences>()
      : null;

  double? _volume;

  /// The music's volume, in percent, kept between visits.
  double get volume =>
      _volume ??= (_prefs?.get(UserPreferences.kostvMusicVolume) ?? 100.0)
          .clamp(0.0, 100.0)
          .toDouble();

  // The level last left in which player, so it is set again only when
  // either changes (a video in between leaves its own level in the player).
  PlayerBackend? _volumeOn;
  double? _volumeAt;
  Timer? _persistVolume;

  /// Kos TV: sets the music's volume (from the slider of «Reproduciendo»)
  /// and keeps it, a moment after the last change.
  void setVolume(double level) {
    if (!hasOwnVolume) return;
    final clamped = level.clamp(0.0, 100.0).toDouble();
    if (clamped == volume) return;
    _volume = clamped;
    _applyVolume();
    _persistVolume?.cancel();
    _persistVolume = Timer(const Duration(milliseconds: 400), () {
      _persistVolume = null;
      unawaited(_prefs?.set(UserPreferences.kostvMusicVolume, clamped));
    });
    notifyListeners();
  }

  /// Puts the music's volume on the player while a song sounds; with no
  /// song (a video, or nothing) it is left alone and set again on the next.
  void _applyVolume() {
    if (!hasOwnVolume) return;
    final song = item;
    if (song == null || song.isAudiobook) {
      _volumeOn = null;
      _volumeAt = null;
      return;
    }
    final backend = _manager?.backend;
    if (backend == null) return;
    final level = volume;
    if (identical(backend, _volumeOn) && _volumeAt == level) return;
    _volumeOn = backend;
    _volumeAt = level;
    unawaited(backend.setVolume(level));
  }

  /// Kos TV: Kids Mode went on: a song sounding stops and the floating
  /// player and «Reproduciendo» go with it. An audiobook goes on.
  void stopForKidsMode() {
    final song = item;
    if (song == null || song.isAudiobook) return;
    close();
  }

  // --- The sleep timer ---

  Timer? _sleep;

  /// When the music will pause by itself, or null.
  DateTime? get sleepAt => _sleepAt;
  DateTime? _sleepAt;

  /// Pauses the music in [after], or never with null. It goes on with the
  /// player's page closed.
  void setSleep(Duration? after) {
    _sleep?.cancel();
    _sleep = null;
    _sleepAt = null;
    if (after != null && after > Duration.zero) {
      _sleepAt = DateTime.now().add(after);
      _sleep = Timer(after, () {
        _sleep = null;
        _sleepAt = null;
        // Only music: a film started meanwhile isn't the timer's.
        if (item != null) unawaited(_manager?.pause());
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// «Al acabar la canción»: it pauses when this song ends, wherever the
  /// person moves in it.
  bool _sleepAfterSong = false;
  bool get sleepsAfterSong => _sleepAfterSong;

  void sleepAfterSong() {
    setSleep(null);
    _sleepAfterSong = true;
    notifyListeners();
  }

  /// What is left of the song sounding.
  Duration get leftOfSong {
    final state = _manager?.state;
    if (state == null) return Duration.zero;
    final left = state.duration - state.position;
    return left.isNegative ? Duration.zero : left;
  }

  // --- Autoplay (∞) ---

  bool get autoplay =>
      !GetIt.instance.isRegistered<UserPreferences>() ||
      GetIt.instance<UserPreferences>().get(UserPreferences.kostvMusicAutoplay);

  set autoplay(bool on) {
    GetIt.instance<UserPreferences>().set(
      UserPreferences.kostvMusicAutoplay,
      on,
    );
    notifyListeners();
    if (on) unawaited(_maybeAutoplay());
  }

  bool _autoplayBusy = false;
  String? _autoplaySeed;

  /// Kos TV: asks again once the radio has rested, after neither it nor
  /// the home server's mix answered (nothing else may wake it before the
  /// queue ends).
  Timer? _autoplayRetry;

  /// The songs autoplay added to the queue, to show them apart.
  ///
  /// Kos TV: the queue's own entries (by identity, not by id), so a queue
  /// put on somewhere else (an album's page, the favourites, the library)
  /// with the same songs doesn't take them as autoplay's.
  final autoplayItems = Set<AggregatedItem>.identity();

  /// Kos TV: the songs of the queue that came by themselves (a radio, a
  /// mix, the discovery): with [autoplayItems], what «No me pongas a este
  /// artista» takes out of what is still to play. By identity as well: the
  /// queue's entries, which another queue doesn't share.
  final automaticItems = Set<AggregatedItem>.identity();

  /// Kos TV: where the queue came from ([KostvMusicSource]), for what is
  /// told of the songs that aren't at home.
  String? _queueSource;

  /// Kos TV: whether the queue's [song] came by itself (see
  /// [automaticItems]).
  bool cameByItself(AggregatedItem song) =>
      autoplayItems.contains(song) || automaticItems.contains(song);

  /// Kos TV: the song the queue was put on with (the one picked, or the
  /// first of what plays by itself): what the endless play goes on from
  /// when all of the queue came by itself ([autoplaySeedOf]).
  AggregatedItem? _queueStart;

  @visibleForTesting
  AggregatedItem? get debugQueueStart => _queueStart;

  /// Kos TV: [tracks] were put on from [source] ([KostvMusicSource]),
  /// starting at [startIndex]: kept when they came by themselves; another
  /// queue of the person's choosing isn't.
  void noteQueueSource(
    String source,
    List<AggregatedItem> tracks, {
    int startIndex = 0,
  }) {
    _queueSource = source;
    automaticItems.clear();
    autoplayItems.clear();
    // Kos TV: another queue: the last one's station isn't completed (also
    // when it is being asked for right now).
    _stationLater?.cancel();
    _stationLater = null;
    _queueGeneration++;
    _queueStart = tracks.isEmpty
        ? null
        : tracks[startIndex.clamp(0, tracks.length - 1)];
    if (KostvMusicSource.automatic(source)) automaticItems.addAll(tracks);
  }

  /// Kos TV: the song the endless play (∞) goes on from
  /// (`docs/musica-radio.md` 3.2): the last song in [queue] the person
  /// chose (put on or added by hand: not come by itself, [cameByItself]),
  /// never one the ∞ (or a station) added, so it doesn't drift from what
  /// they wanted. When all of it came by itself (a station, a mix), the
  /// song it was put on with ([start]); without one, [current].
  @visibleForTesting
  static AggregatedItem? autoplaySeedOf(
    List<Object?> queue, {
    required bool Function(AggregatedItem song) cameByItself,
    AggregatedItem? start,
    AggregatedItem? current,
  }) {
    bool music(AggregatedItem song) =>
        song.type == 'Audio' && !song.isAudiobook;
    for (final entry in queue.reversed) {
      if (entry is AggregatedItem && music(entry) && !cameByItself(entry)) {
        return entry;
      }
    }
    if (start != null && music(start)) return start;
    return current;
  }

  /// Kos TV: takes out of what is still to play (after the song sounding;
  /// with the whole queue on repeat, before it too) the songs [out] says,
  /// only those that came by themselves with [onlyAutomatic]. Gives what
  /// went, for [putBack].
  KostvLeftOut leaveOutUpcoming(
    bool Function(AggregatedItem song) out, {
    bool onlyAutomatic = false,
  }) {
    final manager = _manager;
    if (manager == null) return const KostvLeftOut._();
    final queue = manager.queueService;
    final items = queue.items;
    final current = queue.currentIndex;
    final sounding = queue.currentItem;
    // With repeat-all the songs before it come round again.
    final first = queue.repeatMode == RepeatMode.repeatAll ? 0 : current + 1;
    final gone = <({int index, AggregatedItem song})>[];
    for (var i = items.length - 1; i >= first; i--) {
      if (i == current) continue;
      final song = items[i];
      if (song is! AggregatedItem || !out(song)) continue;
      if (onlyAutomatic && !cameByItself(song)) continue;
      queue.removeAt(i);
      gone.add((index: i, song: song));
    }
    return KostvLeftOut._(gone: gone.reversed.toList(), sounding: sounding);
  }

  /// Kos TV: the next song, if [id] is the one sounding («No me gusta» on
  /// it): straight to it, not to the song's next chapter first. Gives what
  /// [putBack] needs to go back to it (null when it wasn't sounding).
  KostvSkipped? skipIfSounding(String id) {
    if (item?.id != id) return null;
    final queue = _manager?.queueService;
    final skipped = (song: queue?.currentItem, next: queue?.peekNext);
    noteChosen();
    unawaited(_manager?.nextInQueue());
    return skipped;
  }

  /// Kos TV: «Deshacer» of a «No me gusta»: what [left] took out goes back
  /// where it was and, if [skipped] (the song that was sounding) was skipped
  /// and the person is still on the one after it, back to it. Nothing when
  /// the queue was put on anew since.
  void putBack(KostvLeftOut left, {KostvSkipped? skipped}) {
    final manager = _manager;
    if (manager == null) return;
    final queue = manager.queueService;
    bool inQueue(Object? entry) =>
        entry != null && queue.items.any((e) => identical(e, entry));
    if (left.sounding != null && !inQueue(left.sounding)) return;
    for (final (:index, :song) in left.gone) {
      queue.insertAt(index, song);
    }
    final song = skipped?.song;
    if (song == null || !inQueue(song)) return;
    final next = skipped!.next;
    if (next != null && !identical(queue.currentItem, next)) return;
    final at = queue.items.indexWhere((e) => identical(e, song));
    if (at < 0) return;
    noteChosen();
    unawaited(manager.playFromQueue(at).catchError((_) {}));
  }

  @visibleForTesting
  Future<void> debugAutoplay() => _maybeAutoplay();

  /// Kos TV: completes a station the server plugin gave in part
  /// ([kostvPluginStationFor]'s `onPartial`).
  Timer? _stationLater;

  /// How long the plugin is given to work the whole station out.
  @visibleForTesting
  static Duration stationLaterAfter = const Duration(seconds: 75);

  /// Kos TV: once more, this long after, when it still wasn't whole then
  /// (the plugin may take up to a minute and a half).
  @visibleForTesting
  static Duration stationLastTryAfter = const Duration(seconds: 45);

  /// Kos TV: which queue it is: another one put on (or none) changes it,
  /// so what was asked for the one before isn't added to it.
  int _queueGeneration = 0;

  /// Kos TV: the plugin answered the station of [seed] with only its first
  /// songs (`Source: fallback`) while it works the whole one out (up to a
  /// minute and a half): asked again once, a while later, quietly, and
  /// what wasn't in the queue goes at its end, as songs that came by
  /// themselves (the ∞'s with [byAutoplay]). Nothing when the queue
  /// changed meanwhile (another one put on, the seed no longer in it, or
  /// the ∞ turned off for its own). Kos TV: when it still isn't whole then,
  /// once more a while later ([stationLastTryAfter]).
  void completeStationLater(AggregatedItem seed, {bool byAutoplay = false}) =>
      _completeLater(seed, byAutoplay, stationLaterAfter, lastTry: false);

  void _completeLater(
    AggregatedItem seed,
    bool byAutoplay,
    Duration after, {
    required bool lastTry,
  }) {
    _stationLater?.cancel();
    final generation = _queueGeneration;
    _stationLater = Timer(after, () {
      _stationLater = null;
      unawaited(
        _completeStation(
          seed,
          byAutoplay,
          generation,
          lastTry: lastTry,
        ).catchError((Object _) {}),
      );
    });
  }

  @visibleForTesting
  Future<void> debugCompleteStation(
    AggregatedItem seed, {
    bool byAutoplay = false,
    bool lastTry = true,
  }) => _completeStation(seed, byAutoplay, _queueGeneration, lastTry: lastTry);

  @visibleForTesting
  bool get debugCompletingLater => _stationLater != null;

  Future<void> _completeStation(
    AggregatedItem seed,
    bool byAutoplay,
    int generation, {
    required bool lastTry,
  }) async {
    final manager = _manager;
    if (manager == null) return;
    final queue = manager.queueService;
    bool stillThere() =>
        generation == _queueGeneration &&
        (!byAutoplay || autoplay) &&
        queue.items.any((e) => e is AggregatedItem && e.id == seed.id);
    if (!stillThere()) return;
    final client =
        GetIt.instance<MediaServerClientFactory>().getClientIfExists(
          seed.serverId,
        ) ??
        GetIt.instance<MediaServerClient>();
    final dislikes = await KostvMusicDislikesStore.instance
        .load(client)
        .catchError((Object _) => KostvMusicDislikes.empty);
    final songs = queue.items.whereType<AggregatedItem>().toList();
    var partial = false;
    final more = await kostvPluginStationFor(
      seed,
      client: client,
      dislikes: dislikes,
      skip: {...songs.map((e) => e.id), seed.id},
      skipKeys: {...songs.map(kostvSongKey), kostvSongKey(seed)},
      onPartial: () => partial = true,
    );
    if (!stillThere()) return;
    // Kos TV: still being worked out: what came goes in, and once more.
    if (partial && !lastTry) {
      _completeLater(seed, byAutoplay, stationLastTryAfter, lastTry: true);
    }
    if (more == null || more.isEmpty) return;
    // What was put in the queue meanwhile isn't put again.
    final now = queue.items.whereType<AggregatedItem>();
    final ids = {...now.map((e) => e.id)};
    final keys = {...now.map(kostvSongKey)};
    final added = [
      for (final song in more)
        if (ids.add(song.id) && keys.add(kostvSongKey(song))) song,
    ];
    if (added.isEmpty) return;
    (byAutoplay ? autoplayItems : automaticItems).addAll(added);
    queue.addItems(added);
  }

  /// Near the end of the queue (and with nothing on repeat), similar songs
  /// are added after it, so the music goes on by itself. Whether the
  /// player's page is open or not.
  ///
  /// Kos TV: asked once for each song sounding near the end, around the
  /// last song the person chose ([autoplaySeedOf]), not the one sounding
  /// (which the ∞ itself may have added): the server plugin's station of
  /// it when it has one, otherwise as before (`kostvSongStation`). Nothing
  /// already in the queue comes again, so each time it is asked it gives
  /// what wasn't added yet.
  Future<void> _maybeAutoplay() async {
    if (_autoplayBusy) return;
    final current = item;
    if (current == null || current.isAudiobook || current.type != 'Audio') {
      return;
    }
    if (_autoplaySeed == current.id || !autoplay) return;
    final manager = _manager;
    if (manager == null) return;
    final queue = manager.queueService;
    try {
      if (manager.isOfflinePlayback) return;
      if (queue.repeatMode != RepeatMode.none) return;
      if (queue.items.length - 1 - queue.currentIndex > 2) return;
    } catch (_) {
      return;
    }
    final items = queue.items;
    _autoplayBusy = true;
    _autoplaySeed = current.id;
    _autoplayRetry?.cancel();
    _autoplayRetry = null;
    final seed =
        autoplaySeedOf(
          items,
          cameByItself: cameByItself,
          start: _queueStart,
          current: current,
        ) ??
        current;
    var radio = false;
    try {
      final client =
          GetIt.instance<MediaServerClientFactory>().getClientIfExists(
            seed.serverId,
          ) ??
          GetIt.instance<MediaServerClient>();
      // Kos TV: asked again once the radio has rested when it goes through
      // it too.
      radio = kostvStationWantsRadio(seed);
      final songs = items.whereType<AggregatedItem>();
      var partial = false;
      final station = await kostvSongStation(
        seed,
        onPartial: () => partial = true,
        skip: {...songs.map((e) => e.id), seed.id},
        // Kos TV: nor the same song in its other version (at home or not).
        skipKeys: {...songs.map(kostvSongKey), kostvSongKey(seed)},
        homeLimit: 25,
        client: client,
        // Kos TV: when the song radio of the seed has nothing left, that of
        // the song sounding (`docs/musica-radio.md`, «Orden de las
        // fuentes»).
        then: current,
      );
      // Kos TV: nor what went into the queue while it was asked (a station
      // being completed meanwhile).
      final now = queue.items.whereType<AggregatedItem>();
      final inQueue = {...now.map((e) => e.id)};
      final keysInQueue = {...now.map(kostvSongKey)};
      final added = [
        for (final song in station)
          if (inQueue.add(song.id) && keysInQueue.add(kostvSongKey(song))) song,
      ].take(25).toList();
      // Still the same song, and the person didn't change their mind.
      if (added.isNotEmpty && autoplay && item?.id == current.id) {
        autoplayItems.addAll(added);
        queue.addItems(added);
        if (partial) completeStationLater(seed, byAutoplay: true);
      }
    } catch (_) {
      _autoplaySeed = null;
      if (radio) {
        _autoplayRetry = Timer(
          KostvStreamRadio.quiet + const Duration(seconds: 5),
          () {
            _autoplayRetry = null;
            unawaited(_maybeAutoplay());
          },
        );
      }
    } finally {
      _autoplayBusy = false;
      // The song changed while it was asked: asked again for the new one.
      if (item?.id != current.id) unawaited(_maybeAutoplay());
    }
  }

  // --- The cover's colours ---

  /// The colours of the cover sounding (kOS TV pink until they are known).
  final colors = ValueNotifier<KostvCoverColors>(KostvCoverColors.fallback);

  Future<void> _loadColors(AggregatedItem? item) async {
    if (item == null) return;
    final url = artUrl(item, maxHeight: 96);
    if (url == null) {
      colors.value = KostvCoverColors.fallback;
      return;
    }
    // Kos TV: Music's shared cache of covers' colours (the album's and
    // the artist's pages use it too).
    final cached = KostvArtworkColors.cached(url);
    if (cached != null) {
      colors.value = cached;
      return;
    }
    try {
      final found = await KostvArtworkColors.of(url);
      if (_itemId == item.id) colors.value = found;
    } catch (_) {
      if (_itemId == item.id) colors.value = KostvCoverColors.fallback;
    }
  }
}

/// The colours a cover gives the music player: two for its background and
/// one to stand out on it.
@immutable
class KostvCoverColors {
  const KostvCoverColors({
    required this.top,
    required this.bottom,
    required this.accent,
  });

  static const fallback = KostvCoverColors(
    top: Color(0xFF5C1426),
    bottom: Color(0xFF1A0A12),
    accent: Color(0xFFFA2D55),
  );

  /// Near the top of the background.
  final Color top;

  /// Near its bottom, darker.
  final Color bottom;

  /// For the progress and what is lit on the background.
  final Color accent;

  /// From the cover itself, taken small so it costs nothing.
  static Future<KostvCoverColors> of(ImageProvider image) async {
    final scheme = await ColorScheme.fromImageProvider(
      provider: ResizeImage(image, width: 48, height: 48),
      brightness: Brightness.dark,
    ).timeout(const Duration(seconds: 6));
    return KostvCoverColors(
      top: Color.lerp(scheme.primaryContainer, scheme.primary, 0.15)!,
      bottom: Color.lerp(scheme.tertiaryContainer, Colors.black, 0.55)!,
      accent: scheme.primary,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KostvCoverColors &&
      other.top == top &&
      other.bottom == bottom &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(top, bottom, accent);
}

/// Kos TV: what [KostvNowPlaying.leaveOutUpcoming] took out of the queue,
/// for «Deshacer» to put it back where it was.
class KostvLeftOut {
  const KostvLeftOut._({this.gone = const [], this.sounding});

  /// Each one with its place in the queue as it was, in the queue's order.
  final List<({int index, AggregatedItem song})> gone;

  /// The queue's entry sounding then: without it in the queue any more,
  /// it is another queue, and nothing is put back.
  final Object? sounding;

  int get length => gone.length;
}

/// Kos TV: the song [KostvNowPlaying.skipIfSounding] skipped and the one it
/// went on to (the queue's entries), for «Deshacer» to go back to it.
typedef KostvSkipped = ({Object? song, Object? next});

/// Which page is on top, so the floating player knows when to step aside:
/// over a player, a dialog or a sheet, and where the mobile bottom bar
/// shows its own.
class KostvNowPlayingRouteObserver extends NavigatorObserver {
  KostvNowPlayingRouteObserver._();

  static final instance = KostvNowPlayingRouteObserver._();

  final _stack = <Route<dynamic>>[];

  /// Bumps whenever the top changes.
  final changes = ValueNotifier<int>(0);

  Route<dynamic>? get _top => _stack.isEmpty ? null : _stack.last;

  /// The pages that draw the bottom bar, with its own player in it.
  final _withBottomBar = <Route<dynamic>>{};

  void _update() => changes.value++;

  /// Whether a dialog, a sheet or a menu is open on top.
  bool get popupOnTop => _top is PopupRoute;

  /// Whether the page on top shows the bottom bar's own player.
  bool get bottomBarOnTop {
    final route = _top;
    return route != null && _withBottomBar.contains(route);
  }

  void setBottomBar(Route<dynamic>? route, bool shows) {
    if (route == null) return;
    final changed = shows
        ? _withBottomBar.add(route)
        : _withBottomBar.remove(route);
    if (changed) {
      // The floating player reads it while the frame is being built.
      WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _withBottomBar.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _withBottomBar.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (oldRoute != null) _withBottomBar.remove(oldRoute);
    if (newRoute != null) {
      if (at >= 0) {
        _stack[at] = newRoute;
      } else {
        _stack.add(newRoute);
      }
    } else if (at >= 0) {
      _stack.removeAt(at);
    }
    _update();
  }
}
