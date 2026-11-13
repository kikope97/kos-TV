import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/audio_artwork_url.dart';

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
  }

  void _changed() {
    unawaited(_maybeAutoplay());
    final item = this.item;
    final playing = _manager?.state.isPlaying ?? false;
    if (item?.id == _itemId && playing == _playing) return;
    if (item?.id != _itemId) {
      final before = _itemId;
      _itemId = item?.id;
      _loadColors(item);
      if (item == null) {
        // Nothing sounds any more: what went with it goes too.
        setSleep(null);
        _sleepAfterSong = false;
        _autoplaySeed = null;
        autoplayIds.clear();
      } else if (_sleepAfterSong && before != null) {
        // «Al acabar la canción»: the next one doesn't go on.
        _sleepAfterSong = false;
        unawaited(_manager?.pause());
      }
    }
    _playing = playing;
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

  PlayerState? get state => _manager?.state;

  String? artUrl(AggregatedItem item, {int maxHeight = 300}) {
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
    unawaited(manager.state.isPlaying ? manager.pause() : manager.resume());
  }

  void next() => unawaited(_manager?.next());

  void previous() => unawaited(_manager?.previous());

  /// The ✕: the music stops and the floating player goes away.
  void close() {
    setSleep(null);
    _sleepAfterSong = false;
    unawaited(_manager?.stop());
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

  /// The songs autoplay added to the queue, to show them apart.
  final autoplayIds = <String>{};

  /// Near the end of the queue (and with nothing on repeat), similar songs
  /// from home are added after it, so the music goes on by itself. Whether
  /// the player's page is open or not.
  Future<void> _maybeAutoplay() async {
    if (_autoplayBusy) return;
    final seed = item;
    if (seed == null || seed.isAudiobook || seed.type != 'Audio') return;
    if (_autoplaySeed == seed.id || !autoplay) return;
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
    _autoplaySeed = seed.id;
    try {
      final client =
          GetIt.instance<MediaServerClientFactory>().getClientIfExists(
            seed.serverId,
          ) ??
          GetIt.instance<MediaServerClient>();
      final data = await client.instantMixApi.getInstantMix(seed.id, limit: 25);
      final known = items.whereType<AggregatedItem>().map((e) => e.id).toSet();
      final added = <AggregatedItem>[];
      for (final raw in (data['Items'] as List?) ?? const []) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final id = map['Id']?.toString();
        if (id == null || !known.add(id)) continue;
        added.add(
          AggregatedItem(
            id: id,
            serverId: map['ServerId']?.toString() ?? seed.serverId,
            rawData: map,
          ),
        );
      }
      // Still the same song, and the person didn't change their mind.
      if (added.isNotEmpty && autoplay && item?.id == seed.id) {
        autoplayIds.addAll(added.map((e) => e.id));
        queue.addItems(added);
      }
    } catch (_) {
      _autoplaySeed = null;
    } finally {
      _autoplayBusy = false;
      // The song changed while it was asked: asked again for the new one.
      if (item?.id != seed.id) unawaited(_maybeAutoplay());
    }
  }

  // --- The cover's colours ---

  /// The colours of the cover sounding (kOS TV pink until they are known).
  final colors = ValueNotifier<KostvCoverColors>(KostvCoverColors.fallback);
  final _colorCache = <String, KostvCoverColors>{};

  Future<void> _loadColors(AggregatedItem? item) async {
    if (item == null) return;
    final url = artUrl(item, maxHeight: 96);
    if (url == null) {
      colors.value = KostvCoverColors.fallback;
      return;
    }
    final cached = _colorCache[url];
    if (cached != null) {
      colors.value = cached;
      return;
    }
    try {
      final found = await KostvCoverColors.of(NetworkImage(url));
      _colorCache[url] = found;
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
