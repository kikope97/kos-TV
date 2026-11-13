import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/models/lyrics.dart';
import '../../../data/repositories/item_mutation_repository.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/app_router.dart';
import '../../navigation/destinations.dart';
import '../../widgets/baked_blur_image.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_now_playing.dart';
import '../../widgets/music/kostv_now_playing_capsule.dart'
    show KostvEqualizerBars;
import '../../widgets/offline_aware_image.dart';
import '../playback/audiobook_player_view.dart';
import 'kostv_music_widgets.dart' show kostvMusicColor;

/// Kos TV: «Reproduciendo», the music player. Its background takes the
/// colours of the cover; the cover breathes with the music (smaller while
/// paused); and it has three views: the cover, the lyrics, sung along line
/// by line, and what comes next, where autoplay carries on with similar
/// songs from home. On the TV, left alone a while, it turns into a quiet
/// screen of the cover and the lyrics.
class KostvNowPlayingScreen extends StatefulWidget {
  const KostvNowPlayingScreen({super.key});

  @override
  State<KostvNowPlayingScreen> createState() => _KostvNowPlayingScreenState();
}

enum _View { cover, lyrics, queue }

class _KostvNowPlayingScreenState extends State<KostvNowPlayingScreen> {
  final _manager = GetIt.instance<PlaybackManager>();
  final _music = KostvNowPlaying.instance;
  final _subs = <StreamSubscription<dynamic>>[];
  final _playFocus = FocusNode(debugLabel: 'NowPlayingPlay');
  final _ambientFocus = FocusNode(debugLabel: 'NowPlayingAmbient');

  _View _view = _View.cover;
  LyricsData? _lyrics;
  String? _lyricsFor;
  bool? _favorite;
  String? _favoriteFor;
  bool _leaving = false;

  // Which way the cover slides when the song changes.
  int _direction = 1;
  String? _lastId;

  // The TV's quiet screen, after a while without the remote.
  bool _ambient = false;
  Timer? _idle;

  QueueService get _queue => _manager.queueService;
  PlayerState get _state => _manager.state;
  bool get _tv => PlatformDetection.isTV;

  @override
  void initState() {
    super.initState();
    _music
      ..ensureStarted()
      ..addListener(_changed);
    _subs.addAll([
      _state.repeatModeStream.listen((_) => _rebuild()),
      _state.shuffleStream.listen((_) => _rebuild()),
      _queue.queueChangedStream.listen((_) => _rebuild()),
      _manager.sessionEndedStream.listen((_) => _leave()),
    ]);
    _lastId = _music.item?.id;
    unawaited(_loadLyrics());
    // The page opens on play/pause (the app would hand the remote the
    // first thing on it, the progress bar).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tv) _playFocus.requestFocus();
    });
    if (_tv) {
      HardwareKeyboard.instance.addHandler(_onAnyKey);
      _restartIdle();
    }
  }

  @override
  void dispose() {
    _music.removeListener(_changed);
    for (final sub in _subs) {
      sub.cancel();
    }
    _idle?.cancel();
    _gone?.cancel();
    if (_tv) HardwareKeyboard.instance.removeHandler(_onAnyKey);
    _playFocus.dispose();
    _ambientFocus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Timer? _gone;

  void _changed() {
    final id = _music.item?.id;
    if (id != _lastId) {
      _lastId = id;
      // The last song's lyrics don't go on over the new one.
      _lyrics = null;
      unawaited(_loadLyrics());
    }
    // Nothing sounds any more (stopped from the notification, the queue
    // ended…): the page goes, after a moment in case it is still starting.
    _gone?.cancel();
    if (id == null) {
      _gone = Timer(const Duration(milliseconds: 1500), () {
        if (_music.item == null) _leave();
      });
    }
    _rebuild();
  }

  void _leave() {
    if (_leaving || !mounted) return;
    _leaving = true;
    if (context.canPop()) context.pop();
  }

  // --- The TV's quiet screen ---

  bool _onAnyKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // The quiet screen keeps the remote, so the key that wakes it does
    // nothing else (Back doesn't leave the player).
    if (_ambient) {
      _wakeUp();
    } else {
      _restartIdle();
    }
    return false;
  }

  /// Any key brings the player back from the quiet screen, and only that.
  void _wakeUp() {
    _restartIdle();
    if (!_ambient) return;
    setState(() => _ambient = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocus.requestFocus();
    });
  }

  void _restartIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 45), () {
      // Only with the player in front: not under its menu or a dialog.
      if (!mounted || !_music.playing) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) {
        // A menu is open on top: it is tried again later.
        _restartIdle();
        return;
      }
      setState(() => _ambient = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ambient) _ambientFocus.requestFocus();
      });
    });
  }

  // --- Lyrics ---

  Future<void> _loadLyrics() async {
    final item = _music.item;
    if (item == null || item.id == _lyricsFor) return;
    _lyricsFor = item.id;
    LyricsData found = LyricsData.empty;
    try {
      final path = item.rawData['_localLyricsPath'] as String?;
      if (path != null && !kIsWeb && File(path).existsSync()) {
        found = LyricsData.fromJson(
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>,
        );
      } else if (!_manager.isOfflinePlayback) {
        final client =
            GetIt.instance<MediaServerClientFactory>().getClientIfExists(
              item.serverId,
            ) ??
            GetIt.instance<MediaServerClient>();
        found = LyricsData.fromJson(await client.itemsApi.getLyrics(item.id));
      }
    } catch (_) {}
    if (!mounted || _lyricsFor != item.id) return;
    setState(() {
      _lyrics = found;
      if (found.isEmpty && _view == _View.lyrics) _view = _View.cover;
    });
  }

  bool get _hasLyrics => _lyrics?.isNotEmpty ?? false;

  void _show(_View view) {
    setState(() => _view = _view == view ? _View.cover : view);
  }

  // --- Actions ---

  bool _isFavorite(AggregatedItem item) => _favoriteFor == item.id
      ? (_favorite ?? item.isFavorite)
      : item.isFavorite;

  Future<void> _toggleFavorite(AggregatedItem item) async {
    final was = _isFavorite(item);
    setState(() {
      _favoriteFor = item.id;
      _favorite = !was;
    });
    try {
      await GetIt.instance<ItemMutationRepository>().setFavorite(
        item.id,
        isFavorite: !was,
      );
    } catch (_) {
      if (mounted) setState(() => _favorite = was);
    }
  }

  void _next() {
    _direction = 1;
    _music.next();
  }

  void _previous() {
    _direction = -1;
    _music.previous();
  }

  String? _artistId(AggregatedItem item) {
    for (final key in const ['AlbumArtists', 'ArtistItems']) {
      final list = item.rawData[key];
      if (list is List && list.isNotEmpty && list.first is Map) {
        final id = (list.first as Map)['Id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  /// Leaves the player for one of the app's pages, where the floating
  /// player takes over.
  void _goTo(String location) {
    if (context.canPop()) context.pop();
    unawaited(appRouter.push(location));
  }

  Future<void> _showMore(AggregatedItem item) async {
    final l10n = AppLocalizations.of(context);
    final albumId = item.albumId;
    final artistId = _artistId(item);
    final offline = _manager.isOfflinePlayback;
    final sleepAt = _music.sleepAt;
    final choice = await _showMenu<String>(
      title: item.name,
      entries: [
        if (albumId != null && !offline)
          KostvMenuEntry(
            'album',
            Icons.album_rounded,
            l10n.kostvPlayerGoToAlbum,
          ),
        if (artistId != null && !offline)
          KostvMenuEntry(
            'artist',
            Icons.person_rounded,
            l10n.kostvPlayerGoToArtist,
          ),
        if (!offline)
          KostvMenuEntry(
            'playlist',
            Icons.playlist_add_rounded,
            l10n.kostvPlayerAddToPlaylist,
          ),
        KostvMenuEntry(
          'sleep',
          Icons.bedtime_rounded,
          _music.sleepsAfterSong
              ? l10n.kostvPlayerSleepEndOfSong
              : sleepAt == null
              ? l10n.kostvPlayerSleep
              : l10n.kostvPlayerSleepLeft(
                  (sleepAt.difference(DateTime.now()).inSeconds / 60).ceil(),
                ),
        ),
        if (!offline)
          KostvMenuEntry('radio', Icons.radio_rounded, l10n.kostvMusicRadio),
        KostvMenuEntry('stop', Icons.stop_circle_rounded, l10n.kostvPlayerStop),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'album':
        _goTo(Destinations.item(albumId!));
      case 'artist':
        _goTo(Destinations.item(artistId!));
      case 'playlist':
        await AddToPlaylistDialog.show(
          context,
          itemIds: [item.id],
          serverId: item.serverId,
        );
      case 'sleep':
        await _showSleep();
      case 'radio':
        final mix = await KostvMusicService(
          GetIt.instance<MediaServerClientFactory>().getClientIfExists(
                item.serverId,
              ) ??
              GetIt.instance<MediaServerClient>(),
        ).mix(item.id).catchError((Object _) => const <AggregatedItem>[]);
        if (!mounted || mix.isEmpty) return;
        await _manager.playItems([
          item,
          for (final other in mix)
            if (other.id != item.id) other,
        ]);
      case 'stop':
        _music.close();
        _leave();
    }
  }

  Future<void> _showSleep() async {
    final l10n = AppLocalizations.of(context);
    final choice = await _showMenu<Duration>(
      title: l10n.kostvPlayerSleep,
      entries: [
        KostvMenuEntry(
          Duration.zero,
          Icons.timer_off_rounded,
          l10n.kostvPlayerSleepOff,
        ),
        for (final minutes in const [15, 30, 45])
          KostvMenuEntry(
            Duration(minutes: minutes),
            Icons.timer_rounded,
            l10n.kostvPlayerSleepMinutes(minutes),
          ),
        KostvMenuEntry(
          const Duration(hours: 1),
          Icons.timer_rounded,
          l10n.kostvPlayerSleepHour,
        ),
        KostvMenuEntry(
          const Duration(microseconds: 1),
          Icons.music_off_rounded,
          l10n.kostvPlayerSleepEndOfSong,
        ),
      ],
    );
    if (choice == null) return;
    if (choice == const Duration(microseconds: 1)) {
      _music.sleepAfterSong();
    } else {
      _music.setSleep(choice == Duration.zero ? null : choice);
    }
  }

  Future<T?> _showMenu<T>({
    required String title,
    required List<KostvMenuEntry<T>> entries,
  }) => showKostvMusicMenu<T>(context, title: title, entries: entries);

  // --- Building ---

  @override
  Widget build(BuildContext context) {
    final isAudiobookRoute =
        GoRouterState.of(context).uri.queryParameters['isAudiobook'] == 'true';
    final item = _music.item;
    if (isAudiobookRoute || (item != null && item.isAudiobook)) {
      return const AudiobookPlayerView();
    }
    final size = MediaQuery.sizeOf(context);
    final wide =
        _tv || PlatformDetection.useDesktopUi || size.width > size.height;

    Widget body = item == null
        ? const SizedBox.shrink()
        : wide
        ? _wide(item, size)
        : _phone(item, size);
    if (_ambient && item != null) {
      body = Focus(
        focusNode: _ambientFocus,
        autofocus: true,
        // Every key is the quiet screen's while it shows.
        onKeyEvent: (_, _) => KeyEventResult.handled,
        child: _AmbientScreen(item: item, lyrics: _lyrics),
      );
    }

    final page = Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(item: item),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            child: KeyedSubtree(key: ValueKey(_ambient), child: body),
          ),
        ],
      ),
    );
    return PopScope(
      // Back leaves the quiet screen, then the lyrics or the queue, then
      // the player.
      canPop: !_ambient && _view == _View.cover,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_ambient) {
          _wakeUp();
        } else {
          setState(() => _view = _View.cover);
        }
      },
      child: page,
    );
  }

  /// The TV, the computer and a phone on its side: the cover and the
  /// controls on one side, the lyrics or the queue on the other.
  Widget _wide(AggregatedItem item, Size size) {
    final panel = switch (_view) {
      _View.lyrics when _hasLyrics => _LyricsPanel(lyrics: _lyrics!, big: _tv),
      _View.queue => _QueuePanel(big: _tv),
      _ => null,
    };
    final height = size.height;
    // The cover takes what the titles and the controls leave.
    final room = height * 0.9 - (_tv ? 360 : 320);
    final coverSize = room.clamp(150.0, panel == null ? 560.0 : 460.0);
    final controls = SizedBox(
      width: (coverSize * 1.25).clamp(320.0, 620.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CoverArt(
            item: item,
            size: coverSize,
            playing: _music.playing,
            direction: _direction,
          ),
          SizedBox(height: height * 0.045),
          _TitleBlock(
            item: item,
            big: _tv,
            centered: true,
            onArtist: _artistId(item) == null || _manager.isOfflinePlayback
                ? null
                : () => _goTo(Destinations.item(_artistId(item)!)),
          ),
          SizedBox(height: height * 0.03),
          const _Scrubber(),
          SizedBox(height: height * 0.02),
          _Transport(
            state: _state,
            playing: _music.playing,
            playFocus: _playFocus,
            onPrevious: _previous,
            onNext: _next,
            big: _tv,
          ),
          SizedBox(height: height * 0.025),
          _ActionsRow(
            favorite: _isFavorite(item),
            onFavorite: _manager.isOfflinePlayback
                ? null
                : () => _toggleFavorite(item),
            view: _view,
            hasLyrics: _hasLyrics,
            onLyrics: () => _show(_View.lyrics),
            onQueue: () => _show(_View.queue),
            onMore: () => _showMore(item),
          ),
        ],
      ),
    );

    return SafeArea(
      child: Stack(
        children: [
          if (!_tv)
            Positioned(
              top: 12,
              left: 16,
              child: _RoundButton(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: AppLocalizations.of(context).kostvPlayerHide,
                onTap: () => context.pop(),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: size.width * 0.05,
              vertical: height * 0.05,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: panel == null ? 1 : 5,
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: controls),
                  ),
                ),
                if (panel != null) ...[
                  SizedBox(width: size.width * 0.04),
                  Expanded(flex: 6, child: panel),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The phone upright: the big cover, or the lyrics or the queue in its
  /// place under a small header; the controls always at the bottom.
  Widget _phone(AggregatedItem item, Size size) {
    final l10n = AppLocalizations.of(context);
    final padding = MediaQuery.paddingOf(context);
    final panel = switch (_view) {
      _View.lyrics when _hasLyrics => _LyricsPanel(lyrics: _lyrics!),
      _View.queue => const _QueuePanel(),
      _ => null,
    };
    final coverSize = (size.width - 56).clamp(160.0, size.height * 0.46);

    final top = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          _RoundButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: l10n.kostvPlayerHide,
            onTap: () => context.pop(),
          ),
          Expanded(
            child: Text(
              l10n.kostvNowPlaying,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          _RoundButton(
            icon: Icons.more_horiz_rounded,
            tooltip: l10n.kostvPlayerMore,
            onTap: () => _showMore(item),
          ),
        ],
      ),
    );

    final Widget middle = panel == null
        ? Center(
            child: GestureDetector(
              // Sideways on the cover, the next song or the one before.
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -250) _next();
                if (v > 250) _previous();
              },
              child: _CoverArt(
                item: item,
                size: coverSize,
                playing: _music.playing,
                direction: _direction,
              ),
            ),
          )
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Row(
                  children: [
                    _CoverThumb(item: item, size: 56),
                    const SizedBox(width: 14),
                    Expanded(child: _TitleBlock(item: item, small: true)),
                  ],
                ),
              ),
              Expanded(child: panel),
            ],
          );

    return GestureDetector(
      // Down from the top, back to the floating player.
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 500 && panel == null) context.pop();
      },
      child: Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: Column(
          children: [
            top,
            Expanded(child: middle),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
              child: Column(
                children: [
                  if (panel == null)
                    Row(
                      children: [
                        Expanded(
                          child: _TitleBlock(
                            item: item,
                            onArtist:
                                _artistId(item) == null ||
                                    _manager.isOfflinePlayback
                                ? null
                                : () => _goTo(
                                    Destinations.item(_artistId(item)!),
                                  ),
                          ),
                        ),
                        if (!_manager.isOfflinePlayback)
                          _IconToggle(
                            icon: _isFavorite(item)
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            tooltip: _isFavorite(item)
                                ? l10n.kostvPlayerUnfavorite
                                : l10n.kostvPlayerFavorite,
                            lit: _isFavorite(item),
                            onTap: () => _toggleFavorite(item),
                          ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  const _Scrubber(),
                  const SizedBox(height: 6),
                  _Transport(
                    state: _state,
                    playing: _music.playing,
                    playFocus: _playFocus,
                    onPrevious: _previous,
                    onNext: _next,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _IconToggle(
                        icon: Icons.lyrics_rounded,
                        tooltip: l10n.kostvPlayerLyrics,
                        lit: _view == _View.lyrics,
                        enabled: _hasLyrics,
                        onTap: () => _show(_View.lyrics),
                      ),
                      const Spacer(),
                      _IconToggle(
                        icon: Icons.queue_music_rounded,
                        tooltip: l10n.kostvPlayerQueue,
                        lit: _view == _View.queue,
                        onTap: () => _show(_View.queue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- The background ---

/// The cover's colours, and the cover itself blurred into them.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.item});

  final AggregatedItem? item;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    final image = item == null ? null : _coverImage(item, 300);
    return RepaintBoundary(
      child: ValueListenableBuilder<KostvCoverColors>(
        valueListenable: KostvNowPlaying.instance.colors,
        builder: (context, colors, _) => Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 900),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.top, colors.bottom],
                ),
              ),
            ),
            if (image != null)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 900),
                child: Opacity(
                  key: ValueKey(item!.id),
                  opacity: 0.38,
                  // On the TV, a tiny copy of the cover, stretched: as soft
                  // as a blur and nothing to work out on every frame (a
                  // slow TV repainted a full-screen blur at every tick).
                  // Elsewhere, the blur (the web's covers don't shrink).
                  child: PlatformDetection.isTV
                      ? Transform.scale(
                          scale: 1.3,
                          child: Image(
                            image: ResizeImage(image, width: 12, height: 12),
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        )
                      : Transform.scale(
                          scale: 1.5,
                          // Blurred once when the cover loads, not again on
                          // every frame of the progress bar or the lyrics.
                          child: BakedBlurImage(image: image, sigma: 70),
                        ),
                ),
              ),
            // Darker at the bottom, where the controls are.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether a downloaded cover is there, asked once per file (not on every
/// rebuild of every row).
final _localCovers = <String, bool>{};

ImageProvider? _coverImage(AggregatedItem item, int maxHeight) {
  final local = item.rawData['_localPosterPath'];
  if (local is String &&
      !kIsWeb &&
      _localCovers.putIfAbsent(local, () => File(local).existsSync())) {
    return FileImage(File(local));
  }
  final url = KostvNowPlaying.instance.artUrl(item, maxHeight: maxHeight);
  return url == null ? null : offlineAwareImageProvider(url);
}

// --- The cover ---

/// The big cover: full while the music sounds, a little smaller while
/// paused, and sliding in from the side the person went.
class _CoverArt extends StatelessWidget {
  const _CoverArt({
    required this.item,
    required this.size,
    required this.playing,
    required this.direction,
  });

  final AggregatedItem item;
  final double size;
  final bool playing;
  final int direction;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: playing ? 1 : 0.84,
    duration: const Duration(milliseconds: 520),
    curve: playing ? Curves.easeOutBack : Curves.easeOutCubic,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(item.id);
        final from = (incoming ? 0.35 : -0.35) * direction;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: Offset(from, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: DecoratedBox(
        key: ValueKey(item.id),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.035 + 6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: playing ? 0.5 : 0.3),
              blurRadius: playing ? 50 : 24,
              offset: Offset(0, playing ? 24 : 10),
            ),
          ],
        ),
        child: _CoverThumb(item: item, size: size),
      ),
    ),
  );
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.item, required this.size});

  final AggregatedItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = _coverImage(item, size > 200 ? 800 : 200);
    final placeholder = ColoredBox(
      color: Colors.white.withValues(alpha: 0.08),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.4,
        color: Colors.white.withValues(alpha: 0.5),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.035 + 4),
      child: SizedBox(
        width: size,
        height: size,
        child: image == null
            ? placeholder
            : Image(
                image: image,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

// --- Titles ---

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.item,
    this.big = false,
    this.small = false,
    this.centered = false,
    this.onArtist,
  });

  final AggregatedItem item;
  final bool big;
  final bool small;
  final bool centered;
  final VoidCallback? onArtist;

  @override
  Widget build(BuildContext context) {
    final artist = KostvNowPlaying.instance.artistOf(item);
    final album = item.album;
    final secondLine = [
      if (artist.isNotEmpty) artist,
      if (!small && album != null && album.isNotEmpty) album,
    ].join(' · ');
    final align = centered ? TextAlign.center : TextAlign.start;
    final artistText = Text(
      secondLine,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: TextStyle(
        color: small
            ? Colors.white.withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.72),
        fontSize: big ? 20 : (small ? 13.5 : 16),
        fontWeight: FontWeight.w500,
      ),
    );
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.name,
          maxLines: small ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
            color: Colors.white,
            fontSize: big ? 32 : (small ? 16 : 22),
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.2,
          ),
        ),
        if (secondLine.isNotEmpty) ...[
          SizedBox(height: small ? 2 : 6),
          if (onArtist == null || PlatformDetection.isTV)
            artistText
          else
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: onArtist, child: artistText),
            ),
        ],
      ],
    );
  }
}

// --- The progress ---

/// How far the song has gone, to drag or tap anywhere along; with the remote,
/// left and right move ten seconds.
class _Scrubber extends StatefulWidget {
  const _Scrubber();

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  final _manager = GetIt.instance<PlaybackManager>();
  final _subs = <StreamSubscription<dynamic>>[];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragging;
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    final state = _manager.state;
    _position = state.position;
    _duration = state.duration;
    _subs.addAll([
      state.positionStream.listen((p) {
        if (!mounted || _dragging != null) return;
        // Only when something shown changes: the second on the clock, or
        // the bar by about half a pixel (some players tell the position
        // many times a second).
        final total = _duration.inMilliseconds;
        final moved = (p - _position).inMilliseconds.abs();
        if (p.inSeconds == _position.inSeconds &&
            total > 0 &&
            moved * 1600 < total) {
          return;
        }
        setState(() => _position = p);
      }),
      state.durationStream.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    ]);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  double get _value {
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return _dragging ?? (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _seekTo(double fraction) {
    final total = _duration.inMilliseconds;
    if (total <= 0) return;
    unawaited(
      _manager.seekTo(Duration(milliseconds: (fraction * total).round())),
    );
  }

  String _time(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final lit =
        _dragging != null ||
        _hovered ||
        InputModeTracker.showFocusVisuals(context, _focused);
    final total = _duration;
    final at = Duration(milliseconds: (_value * total.inMilliseconds).round());
    final left = total - at;
    final timeStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.6),
      fontSize: PlatformDetection.isTV ? 15 : 12,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key.isLeftKey || key.isRightKey) {
          final total = _duration.inMilliseconds;
          if (total > 0) {
            final step = 10000 / total * (key.isLeftKey ? -1 : 1);
            _seekTo((_value + step).clamp(0.0, 1.0));
          }
          return KeyEventResult.handled;
        }
        return _moveFocus(node, event);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: LayoutBuilder(
          builder: (context, constraints) {
            double fractionAt(Offset local) =>
                (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _seekTo(fractionAt(d.localPosition)),
              onHorizontalDragStart: (d) =>
                  setState(() => _dragging = fractionAt(d.localPosition)),
              onHorizontalDragUpdate: (d) =>
                  setState(() => _dragging = fractionAt(d.localPosition)),
              onHorizontalDragEnd: (_) {
                final to = _dragging;
                setState(() => _dragging = null);
                if (to != null) _seekTo(to);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 22,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: lit ? 9 : 5,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: _value,
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: Colors.white.withValues(
                                    alpha: lit ? 1 : 0.85,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // The knob, while it is touched, pointed or chosen.
                        if (lit)
                          Align(
                            alignment: Alignment(_value * 2 - 1, 0),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: PlatformDetection.isTV
                                    ? Border.all(
                                        color: kostvMusicColor,
                                        width: 3,
                                      )
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Text(_time(at), style: timeStyle),
                      const Spacer(),
                      Text(
                        '-${_time(left.isNegative ? Duration.zero : left)}',
                        style: timeStyle,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The remote's arrows, to the nearest stop that way; never out of the
/// player.
KeyEventResult _moveFocus(FocusNode node, KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final direction = switch (event.logicalKey) {
    LogicalKeyboardKey.arrowUp => TraversalDirection.up,
    LogicalKeyboardKey.arrowDown => TraversalDirection.down,
    LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
    LogicalKeyboardKey.arrowRight => TraversalDirection.right,
    _ => null,
  };
  if (direction == null) return KeyEventResult.ignored;
  node.focusInDirection(direction);
  return KeyEventResult.handled;
}

// --- Buttons ---

/// A stop of the remote, a tap and a click.
class _Stop extends StatefulWidget {
  const _Stop({
    super.key,
    required this.builder,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
  });

  final Widget Function(BuildContext context, bool lit) builder;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? tooltip;

  @override
  State<_Stop> createState() => _StopState();
}

class _StopState extends State<_Stop> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lit =
        InputModeTracker.showFocusVisuals(context, _focused) || _hovered;
    Widget child = Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.onTap != null,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final box = context.findRenderObject();
          if (box is! RenderBox || !box.hasSize) return;
          unawaited(
            Scrollable.maybeOf(context)?.position.ensureVisible(
              box,
              alignment: 0.4,
              duration: const Duration(milliseconds: 200),
            ),
          );
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return _moveFocus(node, event);
      },
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.builder(context, lit),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null && !PlatformDetection.isTV) {
      child = Tooltip(message: tooltip, child: child);
    }
    return Semantics(button: true, label: tooltip, child: child);
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 44,
    this.iconSize = 28,
    this.lit = false,
    this.enabled = true,
    this.filled = false,
    this.focusNode,
    this.autofocus = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool lit;
  final bool enabled;
  final bool filled;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => _Stop(
    tooltip: tooltip,
    focusNode: focusNode,
    autofocus: autofocus,
    onTap: enabled ? onTap : null,
    builder: (context, focused) {
      final color = !enabled
          ? Colors.white.withValues(alpha: 0.25)
          : filled
          ? Colors.black
          : lit
          ? kostvMusicColor
          : Colors.white;
      return AnimatedScale(
        scale: focused ? 1.12 : 1,
        duration: const Duration(milliseconds: 160),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? Colors.white
                : focused
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.transparent,
            // With the remote, the button it is on stands out clearly.
            border: Border.all(
              color: focused && PlatformDetection.isTV
                  ? kostvMusicColor
                  : Colors.transparent,
              width: 3,
            ),
            boxShadow: filled && focused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.35),
                      blurRadius: 24,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: iconSize, color: color),
        ),
      );
    },
  );
}

/// A small toggle: lit in the music colour when on.
class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.icon,
    required this.tooltip,
    required this.lit,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final bool lit;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _RoundButton(
    icon: icon,
    tooltip: tooltip,
    onTap: onTap,
    lit: lit,
    enabled: enabled,
    size: PlatformDetection.isTV ? 52 : 44,
    iconSize: PlatformDetection.isTV ? 26 : 24,
  );
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.state,
    required this.playing,
    required this.playFocus,
    required this.onPrevious,
    required this.onNext,
    this.big = false,
  });

  final PlayerState state;
  final bool playing;
  final FocusNode playFocus;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = GetIt.instance<PlaybackManager>();
    final repeat = state.repeatMode;
    final scale = big ? 1.15 : 1.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _RoundButton(
          icon: Icons.shuffle_rounded,
          tooltip: l10n.shuffle,
          lit: state.isShuffled,
          size: 46 * scale,
          iconSize: 24 * scale,
          onTap: manager.toggleShuffle,
        ),
        _RoundButton(
          icon: Icons.skip_previous_rounded,
          tooltip: l10n.kostvPlayerPrevious,
          size: 60 * scale,
          iconSize: 44 * scale,
          onTap: onPrevious,
        ),
        _RoundButton(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: playing ? l10n.pause : l10n.play,
          filled: true,
          size: 76 * scale,
          iconSize: 44 * scale,
          focusNode: playFocus,
          autofocus: true,
          onTap: KostvNowPlaying.instance.playPause,
        ),
        _RoundButton(
          icon: Icons.skip_next_rounded,
          tooltip: l10n.next,
          size: 60 * scale,
          iconSize: 44 * scale,
          onTap: onNext,
        ),
        _RoundButton(
          icon: repeat == RepeatMode.repeatOne
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          tooltip: repeat == RepeatMode.repeatOne
              ? l10n.kostvPlayerRepeatOne
              : l10n.kostvPlayerRepeat,
          lit: repeat != RepeatMode.none,
          size: 46 * scale,
          iconSize: 24 * scale,
          onTap: manager.toggleRepeat,
        ),
      ],
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.favorite,
    required this.onFavorite,
    required this.view,
    required this.hasLyrics,
    required this.onLyrics,
    required this.onQueue,
    required this.onMore,
  });

  final bool favorite;
  final VoidCallback? onFavorite;
  final _View view;
  final bool hasLyrics;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (onFavorite != null)
          _IconToggle(
            icon: favorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            tooltip: favorite
                ? l10n.kostvPlayerUnfavorite
                : l10n.kostvPlayerFavorite,
            lit: favorite,
            onTap: onFavorite!,
          ),
        const SizedBox(width: 18),
        _IconToggle(
          icon: Icons.lyrics_rounded,
          tooltip: l10n.kostvPlayerLyrics,
          lit: view == _View.lyrics,
          enabled: hasLyrics,
          onTap: onLyrics,
        ),
        const SizedBox(width: 18),
        _IconToggle(
          icon: Icons.queue_music_rounded,
          tooltip: l10n.kostvPlayerQueue,
          lit: view == _View.queue,
          onTap: onQueue,
        ),
        const SizedBox(width: 18),
        _IconToggle(
          icon: Icons.more_horiz_rounded,
          tooltip: l10n.kostvPlayerMore,
          lit: false,
          onTap: onMore,
        ),
      ],
    );
  }
}

// --- Lyrics ---

/// The lyrics, sung along: the line sounding big and bright, the ones gone
/// dimmer, and the page following the song. A line picked jumps there.
class _LyricsPanel extends StatefulWidget {
  const _LyricsPanel({required this.lyrics, this.big = false});

  final LyricsData lyrics;
  final bool big;

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  final _manager = GetIt.instance<PlaybackManager>();
  StreamSubscription<Duration>? _sub;
  final _scroll = ScrollController();
  late List<GlobalKey> _keys;
  int _active = -1;

  // While the person moves along the lines, the page stops following.
  DateTime _heldUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
    if (widget.lyrics.isSynced) {
      _update(_manager.state.position, jump: true);
      _sub = _manager.state.positionStream.listen(_update);
    }
  }

  @override
  void didUpdateWidget(_LyricsPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.lyrics, widget.lyrics)) {
      _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
      _active = -1;
      _sub?.cancel();
      _sub = null;
      if (widget.lyrics.isSynced) {
        _update(_manager.state.position, jump: true);
        _sub = _manager.state.positionStream.listen(_update);
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _update(Duration position, {bool jump = false}) {
    final lines = widget.lyrics.lines;
    var index = -1;
    for (var i = lines.length - 1; i >= 0; i--) {
      if (position >= lines[i].start) {
        index = i;
        break;
      }
    }
    if (index == _active) return;
    setState(() => _active = index);
    if (DateTime.now().isBefore(_heldUntil)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(index, jump));
  }

  void _follow(int index, bool jump, {bool again = true}) {
    if (!mounted) return;
    final target = _keys.elementAtOrNull(index < 0 ? 0 : index);
    final context = target?.currentContext;
    if (context == null) {
      // Far down the list, not built yet: near it first, then to it.
      if (!again || !_scroll.hasClients) return;
      final size = widget.big ? 38.0 : 28.0;
      final position = _scroll.position;
      _scroll.jumpTo(
        (index * (size * 1.25 + 24)).clamp(0.0, position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _follow(index, true, again: false),
      );
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: 0.35,
        duration: jump ? Duration.zero : const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final synced = widget.lyrics.isSynced;
    final size = widget.big ? 38.0 : 28.0;
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0, 0.1, 0.85, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: NotificationListener<UserScrollNotification>(
        onNotification: (_) {
          _heldUntil = DateTime.now().add(const Duration(seconds: 4));
          return false;
        },
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.symmetric(
            vertical: MediaQuery.sizeOf(context).height * 0.25,
            horizontal: 24,
          ),
          itemCount: lines.length,
          itemBuilder: (context, i) {
            final line = lines[i];
            final active = synced && i == _active;
            final past = synced && i < _active;
            final text = line.text.trim().isEmpty ? '♪' : line.text;
            return Padding(
              key: _keys[i],
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _Stop(
                // Unsynced lyrics are still lines to move along with the
                // remote, to read them all; a synced one jumps there.
                onTap: synced
                    ? () => unawaited(_manager.seekTo(line.start))
                    : () {},
                builder: (context, lit) {
                  _heldUntilIfLit(lit);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: lit
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.transparent,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 320),
                      style: TextStyle(
                        fontSize: synced ? size : size * 0.72,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: !synced
                            ? Colors.white.withValues(alpha: 0.9)
                            : active
                            ? Colors.white
                            : past
                            ? Colors.white.withValues(alpha: 0.42)
                            : Colors.white.withValues(alpha: 0.28),
                      ),
                      child: Text(text),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _heldUntilIfLit(bool lit) {
    if (lit) _heldUntil = DateTime.now().add(const Duration(seconds: 4));
  }
}

// --- What comes next ---

/// What comes next: the songs left, to play, move and take away; and
/// autoplay, to go on with similar songs from home when they run out.
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({this.big = false});

  final bool big;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = GetIt.instance<PlaybackManager>();
    final music = KostvNowPlaying.instance;
    final queue = manager.queueService;
    final items = queue.items;
    final start = queue.currentIndex + 1;
    final upcoming = [
      for (var i = start; i < items.length; i++)
        if (items[i] is AggregatedItem)
          (index: i, item: items[i] as AggregatedItem),
    ];
    final touch = !PlatformDetection.isTV;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.kostvPlayerQueue,
              style: TextStyle(
                color: Colors.white,
                fontSize: big ? 28 : 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    final autoplay = Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: _Stop(
        onTap: () => music.autoplay = !music.autoplay,
        builder: (context, lit) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: lit ? 0.16 : 0.08),
          ),
          child: Row(
            children: [
              Icon(
                Icons.all_inclusive_rounded,
                color: music.autoplay ? kostvMusicColor : Colors.white54,
                size: big ? 30 : 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.kostvPlayerAutoplay,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: big ? 19 : 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.kostvPlayerAutoplayHint,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: big ? 15 : 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IgnorePointer(
                child: Switch(
                  value: music.autoplay,
                  activeThumbColor: Colors.white,
                  activeTrackColor: kostvMusicColor,
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget row(({int index, AggregatedItem item}) entry, int position) {
      final item = entry.item;
      final fromAutoplay = music.autoplayIds.contains(item.id);
      final tile = _Stop(
        key: ValueKey('queue-${item.id}-${entry.index}'),
        onTap: () => unawaited(manager.playFromQueue(entry.index)),
        builder: (context, lit) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: lit
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              _CoverThumb(item: item, size: big ? 60 : 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: big ? 19 : 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      music.artistOf(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: big ? 15 : 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (fromAutoplay)
                Tooltip(
                  message: l10n.kostvPlayerAutoplayAdded,
                  child: Icon(
                    Icons.all_inclusive_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              if (touch) ...[
                IconButton(
                  tooltip: l10n.kostvPlayerRemove,
                  onPressed: () => queue.removeAt(entry.index),
                  icon: Icon(
                    Icons.remove_circle_outline_rounded,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                ReorderableDragStartListener(
                  index: position,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      return KeyedSubtree(
        key: ValueKey('q-${item.id}-${entry.index}'),
        child: tile,
      );
    }

    final empty = Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        l10n.kostvPlayerQueueEmpty,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        // Downloaded music has no home server to ask for more.
        if (!manager.isOfflinePlayback) autoplay,
        Expanded(
          child: upcoming.isEmpty
              ? Align(alignment: Alignment.topLeft, child: empty)
              : touch
              ? ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: upcoming.length,
                  proxyDecorator: (child, _, _) =>
                      Material(color: Colors.transparent, child: child),
                  onReorderItem: (from, to) {
                    final a = upcoming[from].index;
                    final b = upcoming[to].index;
                    queue.reorder(a, b > a ? b + 1 : b);
                  },
                  itemBuilder: (context, i) => row(upcoming[i], i),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: upcoming.length,
                  itemBuilder: (context, i) => row(upcoming[i], i),
                ),
        ),
      ],
    );
  }
}

// --- The TV's quiet screen ---

/// Left alone on the TV: the cover big, and the lyrics if the song has
/// them, slowly, with nothing else. Any key brings the player back.
class _AmbientScreen extends StatelessWidget {
  const _AmbientScreen({required this.item, required this.lyrics});

  final AggregatedItem item;
  final LyricsData? lyrics;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final lyrics = this.lyrics;
    final withLyrics = lyrics != null && lyrics.isNotEmpty && lyrics.isSynced;
    final music = KostvNowPlaying.instance;
    final cover = _CoverArt(
      item: item,
      size: size.height * (withLyrics ? 0.5 : 0.56),
      playing: true,
      direction: 1,
    );
    final titles = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KostvEqualizerBars(playing: music.playing, size: 26, animated: false),
        const SizedBox(width: 16),
        Flexible(child: _TitleBlock(item: item, big: true)),
      ],
    );
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.25),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: size.width * 0.07,
          vertical: size.height * 0.09,
        ),
        child: withLyrics
            ? Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cover,
                      SizedBox(height: size.height * 0.05),
                      SizedBox(width: size.height * 0.5, child: titles),
                    ],
                  ),
                  SizedBox(width: size.width * 0.05),
                  Expanded(
                    child: IgnorePointer(
                      child: ExcludeFocus(
                        child: _LyricsPanel(lyrics: lyrics, big: true),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  cover,
                  SizedBox(height: size.height * 0.06),
                  titles,
                ],
              ),
      ),
    );
  }
}
