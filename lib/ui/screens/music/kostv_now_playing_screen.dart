import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/models/lyrics.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/kostv_music_away.dart';
import '../../../data/services/kostv_music_dislikes.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../data/services/stremfin/kostv_stream_song.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/app_router.dart';
import '../../navigation/destinations.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_now_playing.dart';
import '../../widgets/music/kostv_now_playing_capsule.dart'
    show KostvEqualizerBars;
import '../../widgets/music/design/kostv_music_design.dart';
import '../../widgets/music/kostv_queue_moves.dart';
import '../../widgets/offline_aware_image.dart';
import '../../widgets/player_volume_control.dart' show volumeIconFor;
import '../playback/audiobook_player_view.dart';
import 'kostv_music_links.dart';
import 'kostv_music_actions.dart' show kostvHomeArtistNamed, kostvMusicSay;
import '../../widgets/music/kostv_stream_play.dart'
    show kostvStationFor, kostvStationWantsRadio;
import 'kostv_music_away_actions.dart';
import 'kostv_music_dislike.dart';
import 'kostv_song_love.dart';
import 'kostv_stream_widgets.dart';

/// Kos TV: «Reproduciendo», the music player. Its background takes the
/// colours of the cover; the cover breathes with the music (smaller while
/// paused); and it has three views: the cover, the lyrics, sung along line
/// by line, and what comes next, where autoplay carries on with similar
/// songs from home. On the TV, left alone a while, it turns into a quiet
/// screen of the cover and the lyrics.
class KostvNowPlayingScreen extends StatefulWidget {
  const KostvNowPlayingScreen({super.key});

  /// Tests: where the player sends the person, instead of the app's router.
  @visibleForTesting
  static ValueChanged<String>? debugOpen;

  @override
  State<KostvNowPlayingScreen> createState() => _KostvNowPlayingScreenState();
}

enum _View { cover, lyrics, queue }

enum _QueueAction { playNow, up, down, remove }

class _KostvNowPlayingScreenState extends State<KostvNowPlayingScreen> {
  final _manager = GetIt.instance<PlaybackManager>();
  final _music = KostvNowPlaying.instance;
  final _subs = <StreamSubscription<dynamic>>[];
  final _playFocus = FocusNode(debugLabel: 'NowPlayingPlay');

  /// Kos TV: «Pedir el álbum» of the line of a song heard in streaming: one
  /// node whatever it says, so asking (it turns into «Pedido») keeps the
  /// remote on it.
  final _streamFocus = FocusNode(debugLabel: 'NowPlayingAskAlbum');
  final _ambientFocus = FocusNode(debugLabel: 'NowPlayingAmbient');
  final _lyricsButtonFocus = FocusNode(debugLabel: 'NowPlayingLyrics');
  // Kos TV: ♥ and «No me gusta», which a song that isn't at home may not
  // have: the remote on them goes to play/pause when they go.
  final _favoriteFocus = FocusNode(debugLabel: 'NowPlayingFavorite');
  final _dislikeFocus = FocusNode(debugLabel: 'NowPlayingDislike');
  // Kos TV: around the lyrics or the queue at the side, to know whether the
  // remote was in there when what it was on went away.
  final _panelFocus = FocusNode(
    debugLabel: 'NowPlayingPanel',
    canRequestFocus: false,
    skipTraversal: true,
  );
  // Kos TV: around the rows of «A continuación», for the remote to land on
  // the next row when the one it was on starts playing and leaves the list.
  final _queueRowsFocus = FocusNode(
    debugLabel: 'NowPlayingQueueRows',
    canRequestFocus: false,
    skipTraversal: true,
  );
  // Kos TV: the stops of those rows, by place (see [_QueuePanel.rowFocus]).
  final _queueRowNodes = <FocusNode>[];
  // Kos TV: the place the remote goes to once a song picked from its menu
  // has moved, gone or started.
  int? _queueFocusAt;

  _View _view = _View.cover;
  LyricsData? _lyrics;
  String? _lyricsFor;
  // Kos TV: the new song's lyrics are on their way. Not the same as having
  // none: the panel and the button stay until the answer says so.
  bool _lyricsLoading = false;
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
      _queue.queueChangedStream.listen((_) => _queueChanged()),
      _manager.sessionEndedStream.listen((_) => _leave()),
    ]);
    _lastId = _music.item?.id;
    unawaited(_loadLyrics());
    // Kos TV: «No me gusta» next to ♥, when the server plugin keeps it.
    KostvMusicDislikesStore.instance.addListener(_rebuild);
    unawaited(kostvMusicDislikesReady(_music.item));
    // Kos TV: the ♥ of songs that aren't at home, kept by the plugin.
    KostvMusicAwayStore.instance.addListener(_rebuild);
    unawaited(kostvAwayReady(_music.item));
    // Kos TV: a ♥ given from the floating player or a menu shows here too.
    kostvSongLoveChanged.addListener(_rebuild);
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
    KostvMusicDislikesStore.instance.removeListener(_rebuild);
    KostvMusicAwayStore.instance.removeListener(_rebuild);
    kostvSongLoveChanged.removeListener(_rebuild);
    for (final sub in _subs) {
      sub.cancel();
    }
    _idle?.cancel();
    _gone?.cancel();
    if (_tv) HardwareKeyboard.instance.removeHandler(_onAnyKey);
    _playFocus.dispose();
    _streamFocus.dispose();
    _ambientFocus.dispose();
    _lyricsButtonFocus.dispose();
    _favoriteFocus.dispose();
    _dislikeFocus.dispose();
    _panelFocus.dispose();
    _queueRowsFocus.dispose();
    for (final node in _queueRowNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Kos TV: a song of «A continuación» picked with the remote (or the first
  /// one starting by itself) leaves the list, and its row the remote was on
  /// with it: the remote goes to the row that takes its place at the top, or
  /// to play/pause with nothing left.
  void _queueChanged() {
    final had = _tv && _queueRowsFocus.hasFocus;
    final target = _queueFocusAt;
    _queueFocusAt = null;
    _rebuild();
    if (_tv && target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _view != _View.queue) return;
        final count = kostvUpcoming(_queue).length;
        if (count == 0) {
          _playFocus.requestFocus();
          return;
        }
        final node = _queueRowFocus(target.clamp(0, count - 1));
        (node.context != null ? node : _playFocus).requestFocus();
      });
      return;
    }
    if (!had) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _queueRowsFocus.hasFocus || _view != _View.queue) return;
      final rows = _queueRowsFocus.traversalDescendants.where(
        (node) => node.canRequestFocus,
      );
      (rows.isEmpty ? _playFocus : rows.first).requestFocus();
    });
  }

  FocusNode _queueRowFocus(int position) {
    while (_queueRowNodes.length <= position) {
      _queueRowNodes.add(
        FocusNode(debugLabel: 'NowPlayingQueueRow${_queueRowNodes.length}'),
      );
    }
    return _queueRowNodes[position];
  }

  /// Kos TV: OK on a song of «A continuación» with the remote: play it now,
  /// move it a place up or down, or take it out of the queue. The remote
  /// follows it when it moves, stays on its place when it goes (on the one
  /// after it, or the one before when it was the last) and goes to the top
  /// when it starts.
  Future<void> _queueMenu(AggregatedItem song) async {
    final l10n = AppLocalizations.of(context);
    final at = kostvUpcomingPosition(_queue, song);
    if (at == null) return;
    final count = kostvUpcoming(_queue).length;
    final choice = await showKostvMusicMenu<_QueueAction>(
      context,
      title: song.name,
      subtitle: _music.artistOf(song),
      entries: [
        KostvMenuEntry(
          _QueueAction.playNow,
          Icons.play_arrow_rounded,
          l10n.kostvQueuePlayNow,
        ),
        if (at > 0)
          KostvMenuEntry(
            _QueueAction.up,
            Icons.arrow_upward_rounded,
            l10n.kostvQueueMoveUp,
          ),
        if (at < count - 1)
          KostvMenuEntry(
            _QueueAction.down,
            Icons.arrow_downward_rounded,
            l10n.kostvQueueMoveDown,
          ),
        KostvMenuEntry(
          _QueueAction.remove,
          Icons.remove_circle_outline_rounded,
          l10n.kostvPlayerRemove,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    // Found again: the songs may have moved on while the menu was open.
    final now = kostvUpcomingPosition(_queue, song);
    if (now == null) return;
    switch (choice) {
      case _QueueAction.playNow:
        _queueFocusAt = 0;
        _music.noteChosen();
        unawaited(_manager.playFromQueue(_upcomingIndex(now)));
      case _QueueAction.up:
      case _QueueAction.down:
        _queueFocusAt = now + (choice == _QueueAction.up ? -1 : 1);
        if (kostvMoveUpcoming(_queue, song, up: choice == _QueueAction.up) ==
            null) {
          _queueFocusAt = null;
        }
      case _QueueAction.remove:
        _queueFocusAt = now;
        if (kostvRemoveUpcoming(_queue, song) == null) _queueFocusAt = null;
    }
  }

  int _upcomingIndex(int position) => kostvUpcoming(_queue)[position].index;

  Timer? _gone;

  void _changed() {
    final id = _music.item?.id;
    if (id != _lastId) {
      _lastId = id;
      // The last song's lyrics don't go on over the new one.
      _lyrics = null;
      // Kos TV: asked again even for the same song back after a moment with
      // none (a station started from the one sounding).
      _lyricsFor = null;
      _lyricsLoading = id != null;
      // A line of the old lyrics had the remote: it goes back to Letra rather
      // than to nobody. Kos TV: a song that isn't at home has no Letra (its
      // button leaves the row), so to play/pause; and never to a node that has
      // left the tree, which Flutter would keep pending and jump to later.
      if (_tv && _view == _View.lyrics && _panelFocus.hasFocus) {
        final away = isKostvStream(_music.item);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!away && kostvFocusInTree(_lyricsButtonFocus)) {
            _lyricsButtonFocus.requestFocus();
          } else if (kostvFocusInTree(_playFocus)) {
            _playFocus.requestFocus();
          }
        });
      }
      unawaited(_loadLyrics());
      // Kos TV: ♥, «Letra» or «No me gusta» had the remote and the new song
      // (one that isn't at home) has none: to play/pause, rather than
      // wherever Flutter would send it.
      final song = _music.item;
      if (isKostvStream(song)) unawaited(kostvAwayReady(song));
      if (_tv &&
          ((song != null &&
                  isKostvStream(song) &&
                  ((_favoriteFocus.hasFocus && !kostvAwayCanKeep(song)) ||
                      _lyricsButtonFocus.hasFocus ||
                      (_dislikeFocus.hasFocus && _dislikeOf(song) == null))) ||
              // Kos TV: «Pedir el álbum» had it and the new song is at home
              // (the line goes).
              (_streamFocus.hasFocus && !isKostvStream(song)))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _playFocus.canRequestFocus) _playFocus.requestFocus();
        });
      }
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
    _popToHere();
    if (context.canPop()) context.pop();
  }

  /// Kos TV: closes whatever is open over the player (its «···», the timer,
  /// «Añadir a una lista»), so the pop after it takes the player away and
  /// not just the menu, leaving a black page behind.
  void _popToHere() {
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent || !route.isActive) return;
    Navigator.of(context).popUntil((r) => r == route);
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
      // Kos TV: a song that isn't at home has no lyrics of the home server.
      if (isKostvStream(item)) throw const _NoLyrics();
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
    // Kos TV: Letra goes dark now, so the remote on it moves to play/pause
    // rather than wherever Flutter would send it.
    final refocus = found.isEmpty && _lyricsButtonFocus.hasFocus;
    setState(() {
      _lyrics = found;
      _lyricsLoading = false;
      if (found.isEmpty && _view == _View.lyrics) _view = _View.cover;
    });
    if (refocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playFocus.requestFocus();
      });
    }
  }

  bool get _hasLyrics =>
      !isKostvStream(_music.item) &&
      ((_lyrics?.isNotEmpty ?? false) || _lyricsLoading);

  /// The lyrics panel: empty while the song's are on their way.
  Widget _lyricsPanel({bool big = false}) => KostvLyricsPanel(
    lyrics: _lyrics?.isNotEmpty == true ? _lyrics! : LyricsData.empty,
    big: big,
  );

  void _show(_View view) {
    // Kos TV: on the computer the panel stays open: its tabs only change.
    setState(() => _view = _docked || _view != view ? view : _View.cover);
  }

  /// Kos TV: «Vaciar»: every song to come goes, as one change, with a few
  /// seconds to take it back («Deshacer», as «No me gusta»). With the remote
  /// on the button (gone with them), to play/pause.
  void _clearQueue() {
    final queue = _queue;
    final cleared = kostvClearUpcoming(queue);
    if (cleared.gone.isEmpty) return;
    kostvMusicOfferUndo(
      context,
      message: AppLocalizations.of(context)
          .kostvPlayerQueueCleared(cleared.gone.length),
      orElse: _playFocus,
      // Kos TV: what autoplay brought to the emptied queue meanwhile goes:
      // the queue is as it was.
      undo: () => kostvPutBackUpcoming(
        queue,
        cleared,
        addedBySelf: (item) =>
            item is AggregatedItem &&
            KostvNowPlaying.instance.autoplayItems.contains(item) &&
            !cleared.gone.any((gone) => identical(gone, item)),
      ),
    );
    if (_tv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && kostvFocusInTree(_playFocus)) _playFocus.requestFocus();
      });
    }
  }

  /// Kos TV: the phone's queue, in a sheet over the player.
  Future<void> _openQueueSheet() async {
    final height = MediaQuery.sizeOf(context).height;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: height < 700 ? 0.85 : 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) => DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF15141B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: _LiveQueue(
                  builder: (context) => _QueuePanel(
                    scrollController: controller,
                    onMenu: _queueMenu,
                    onClear: _clearQueue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Actions ---

  // Kos TV: the ♥ is the same everywhere the song shows (see
  // kostv_song_love.dart): the home server's, or the plugin's for one that
  // isn't at home.
  bool _isFavorite(AggregatedItem item) => kostvSongLoved(item);

  bool _hasFavorite(AggregatedItem item) => kostvSongCanLove(item);

  Future<void> _toggleFavorite(AggregatedItem item) =>
      kostvToggleSongLove(context, item);

  /// Kos TV: «No me gusta» of the song sounding, when the server plugin
  /// keeps it (not with what is downloaded): it skips to the next one. On
  /// one already on the list (put on by hand), it takes it off.
  VoidCallback? _dislikeOf(AggregatedItem item) {
    if (_manager.isOfflinePlayback || item.type != 'Audio') return null;
    // Kos TV: one that isn't at home goes by its Deezer id (the plugin's
    // `Songs`), with the same «Deshacer».
    if (!kostvMusicCanDislike(item)) return null;
    return () {
      if (kostvMusicDisliked(item.id, item)) {
        unawaited(kostvUndislike(context, id: item.id, name: item.name));
      } else {
        _direction = 1;
        unawaited(kostvDislikeSong(context, item, orElse: _playFocus));
      }
    };
  }

  /// Kos TV: whether «No me pongas a este artista» is offered from [item]:
  /// its artist at home goes by the home id, which a plugin from before
  /// «Toda la música» keeps too (unlike a song that isn't at home).
  bool _canDislikeArtist(AggregatedItem item) =>
      !_manager.isOfflinePlayback &&
      item.type == 'Audio' &&
      kostvMusicCanDislike(isKostvStream(item) ? null : item);

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

  /// Kos TV: the song's artists, each opening their page (not with what is
  /// downloaded: the pages are the server's).
  List<KostvMusicLink> _artistLinks(AggregatedItem item) {
    final links = kostvHomeArtistLinks(item, open: _goTo);
    if (!_manager.isOfflinePlayback) return links;
    return [for (final link in links) KostvMusicLink(link.name)];
  }

  /// Kos TV: the song's album, opening its page.
  KostvMusicLink? _albumLink(AggregatedItem item) {
    final link = kostvHomeAlbumLink(item, open: _goTo);
    if (link == null || !_manager.isOfflinePlayback) return link;
    return KostvMusicLink(link.name);
  }

  /// Leaves the player for one of the app's pages, where the floating
  /// player takes over.
  void _goTo(String location) {
    _popToHere();
    if (context.canPop()) context.pop();
    final open = KostvNowPlayingScreen.debugOpen;
    if (open != null) {
      open(location);
      return;
    }
    unawaited(appRouter.push(location));
  }

  Future<void> _showMore(AggregatedItem item) async {
    final l10n = AppLocalizations.of(context);
    final albumId = item.albumId;
    final artistId = _artistId(item);
    // Kos TV: a song that isn't at home has none of the home server's own
    // (its album, its artist, a playlist, its mix).
    final offline = _manager.isOfflinePlayback || isKostvStream(item);
    final sleepAt = _music.sleepAt;
    // Kos TV: «No me pongas a …», when the server plugin keeps it: the
    // song's own artist, not its album's (a compilation's song isn't by
    // «Various Artists»), as the plugin leaves them out.
    // Kos TV: of one that isn't at home, its artist at home by name (what
    // plays by itself is the home server's), looked for a moment at most.
    final stream = KostvStreamInfo.of(item);
    var songArtist = kostvMusicSongArtist(item);
    if (stream != null && _canDislikeArtist(item)) {
      final name = item.artists.firstOrNull ?? item.albumArtist;
      if (name != null) {
        try {
          final home = await kostvHomeArtistNamed(name)
              .timeout(const Duration(seconds: 2));
          if (home != null) songArtist = (id: home.id, name: home.name);
        } catch (_) {}
      }
      if (!mounted) return;
    }
    final artistToDislike =
        _canDislikeArtist(item) &&
            songArtist != null &&
            !kostvMusicDisliked(songArtist.id, item)
        ? songArtist
        : null;
    final choice = await _showMenu<String>(
      title: item.name,
      entries: [
        // Kos TV: one that isn't at home: its album's and its artist's
        // pages of the requests service.
        if (stream?.albumDeezerId != null)
          KostvMenuEntry(
            'streamAlbum',
            Icons.album_rounded,
            l10n.kostvPlayerGoToAlbum,
          ),
        if (stream?.artistDeezerId != null)
          KostvMenuEntry(
            'streamArtist',
            Icons.person_rounded,
            l10n.kostvPlayerGoToArtist,
          ),
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
        // Kos TV: one that isn't at home too, when the plugin keeps it.
        if (!offline || (!_manager.isOfflinePlayback && kostvAwayCanKeep(item)))
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
        if (!offline || (stream != null && !_manager.isOfflinePlayback))
          KostvMenuEntry('radio', Icons.radio_rounded, l10n.kostvMusicRadio),
        if (artistToDislike != null)
          KostvMenuEntry(
            'dislikeArtist',
            Icons.person_off_outlined,
            l10n.kostvMusicDislikeArtistNamed(artistToDislike.name),
          ),
        KostvMenuEntry('stop', Icons.stop_circle_rounded, l10n.kostvPlayerStop),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'album':
        _goTo(Destinations.item(albumId!));
      case 'artist':
        _goTo(Destinations.item(artistId!));
      case 'streamAlbum':
        _goTo(Destinations.kostvMusicAlbumOf(stream!.albumDeezerId!));
      case 'streamArtist':
        _goTo(Destinations.kostvMusicArtistOf(stream!.artistDeezerId!));
      case 'playlist' when stream != null:
        await kostvAwayAddToPlaylist(context, item);
      case 'playlist':
        await AddToPlaylistDialog.show(
          context,
          itemIds: [item.id],
          serverId: item.serverId,
          songs: kostvPlaylistSongsOf(item),
        );
      case 'sleep':
        await _showSleep();
      case 'radio':
        final client =
            GetIt.instance<MediaServerClientFactory>().getClientIfExists(
              item.serverId,
            ) ??
            GetIt.instance<MediaServerClient>();
        // Kos TV: with «Toda la música» (or of one that isn't at home), the
        // requests service's radio of its artists too, mixed in turns.
        final mix = kostvStationWantsRadio(item)
            ? await kostvStationFor(
                item,
                client: client,
              ).catchError((Object _) => const <AggregatedItem>[])
            : await KostvMusicService(client)
                  .mix(item.id)
                  .catchError((Object _) => const <AggregatedItem>[]);
        if (!mounted) return;
        if (mix.isEmpty) {
          if (kostvStationWantsRadio(item)) {
            kostvMusicSay(context, l10n.kostvStreamStationEmpty);
          }
          return;
        }
        KostvNowPlaying.instance.noteChosen();
        // Kos TV: without what the person doesn't want to hear.
        final queue = kostvMusicLeaveOut(
          KostvMusicDislikesStore.instance.of(kostvMusicClientOf(item)),
          [
            item,
            for (final other in mix)
              if (other.id != item.id) other,
          ],
        ).tracks;
        KostvNowPlaying.instance.noteQueueSource(KostvMusicSource.radio, queue);
        kostvTellMusicSource(
          () =>
              GetIt.instance<MediaServerClientFactory>().getClientIfExists(
                item.serverId,
              ) ??
              GetIt.instance<MediaServerClient>(),
          KostvMusicSource.radio,
          queue,
        );
        await _manager.playItems(queue);
      case 'dislikeArtist':
        await kostvDislikeArtist(
          context,
          id: artistToDislike!.id,
          name: artistToDislike.name,
          from: item,
        );
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

  /// Kos TV: on a wide computer screen, the queue and the lyrics stay open
  /// in a panel at the side (the music design's «ordenador_reproductor_cola»).
  bool _docked = false;

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
    _docked = !_tv && wide && size.width >= 1100 && size.height >= 600;

    Widget body = item == null
        ? const SizedBox.shrink()
        : _docked
        ? _desktop(item, size)
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
      backgroundColor: KostvMusicTokens.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(upright: !wide),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            child: KeyedSubtree(key: ValueKey(_ambient), child: body),
          ),
        ],
      ),
    );
    return PopScope(
      // Back leaves the quiet screen, then the lyrics or the queue, then
      // the player (on the computer, whose panel stays open, the player).
      canPop: !_ambient && (_view == _View.cover || _docked),
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

  // --- The pieces every layout has ---

  /// Kos TV: the cover, breathing with the music and gently beating while
  /// the sound of a song that isn't at home is got ready.
  Widget _cover(AggregatedItem item, double size) => KostvPulse(
    active: _music.preparingShown,
    child: _CoverArt(
      item: item,
      size: size,
      playing: _music.playing || _music.preparing,
      direction: _direction,
    ),
  );

  /// Kos TV: the stops of the player's own pieces ([KostvStreamPill]'s,
  /// the names' links), so the remote stays in the player.
  /// Kos TV: the stop of the streaming line's «Pedir el álbum»: still a
  /// stop of the remote once asked («Pedido», «De camino», with nothing to
  /// do), so the remote stays on it rather than being let go.
  Widget _stop(
    VoidCallback? onTap,
    Widget Function(BuildContext context, bool lit) builder,
  ) => _Stop(
    onTap: onTap,
    focusNode: _streamFocus,
    focusable: _tv,
    builder: builder,
  );

  /// «Preparando la canción…», where the times are while it shows.
  Widget? _preparingNote(double scale, {bool big = false}) =>
      _music.preparingShown
      ? KostvPreparingNote(
          slow: _music.preparingSlow,
          big: big,
          centred: false,
          scale: scale,
        )
      : null;

  Widget _heart(
    AggregatedItem item, {
    required double size,
    bool glass = false,
  }) {
    final l10n = AppLocalizations.of(context);
    final loved = _isFavorite(item);
    return _PlayerIcon(
      icon: loved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      tooltip: loved ? l10n.kostvPlayerUnfavorite : l10n.kostvPlayerFavorite,
      size: size,
      glass: glass,
      color: loved ? KostvMusicTokens.pink : null,
      focusNode: _favoriteFocus,
      onTap: () => unawaited(_toggleFavorite(item)),
    );
  }

  Widget? _dislike(
    AggregatedItem item, {
    required double size,
    bool glass = false,
  }) {
    final onDislike = _dislikeOf(item);
    if (onDislike == null) return null;
    final l10n = AppLocalizations.of(context);
    final disliked = kostvMusicDisliked(item.id, item);
    return _PlayerIcon(
      icon: disliked ? Icons.thumb_down_rounded : Icons.thumb_down_outlined,
      tooltip: disliked ? l10n.kostvMusicUndislike : l10n.kostvMusicDislike,
      size: size,
      glass: glass,
      active: disliked,
      focusNode: _dislikeFocus,
      onTap: onDislike,
    );
  }

  _Transport _transport({
    required double play,
    required double skip,
    required double side,
    double? gap,
  }) => _Transport(
    state: _state,
    playing: _music.playing,
    playFocus: _playFocus,
    onPrevious: _previous,
    onNext: _next,
    play: play,
    skip: skip,
    side: side,
    gap: gap,
  );

  Widget _lyricsButton({required double size, bool glass = false}) =>
      _PlayerIcon(
        icon: Icons.notes_rounded,
        tooltip: AppLocalizations.of(context).kostvPlayerLyrics,
        size: size,
        glass: glass,
        active: _view == _View.lyrics,
        enabled: _hasLyrics,
        focusNode: _lyricsButtonFocus,
        onTap: () => _show(_View.lyrics),
      );

  Widget _queueButton({
    required double size,
    bool glass = false,
    VoidCallback? onTap,
  }) => _PlayerIcon(
    icon: Icons.queue_music_rounded,
    tooltip: AppLocalizations.of(context).kostvPlayerQueue,
    size: size,
    glass: glass,
    active: _view == _View.queue,
    onTap: onTap ?? () => _show(_View.queue),
  );

  Widget _moreButton(
    AggregatedItem item, {
    required double size,
    bool glass = false,
  }) => _PlayerIcon(
    icon: Icons.more_horiz_rounded,
    tooltip: AppLocalizations.of(context).kostvPlayerMore,
    size: size,
    glass: glass,
    onTap: () => _showMore(item),
  );

  Widget _hideButton({required double size, bool glass = false}) => _PlayerIcon(
    icon: Icons.keyboard_arrow_down_rounded,
    tooltip: AppLocalizations.of(context).kostvPlayerHide,
    size: size,
    glass: glass,
    onTap: () => context.pop(),
  );

  Widget _queuePanel({bool big = false, double scale = 1}) => _QueuePanel(
    big: big,
    scale: scale,
    // Kos TV: the remote's stops only on the TV (the computer's rows go by
    // the mouse and touch).
    rowsFocus: _tv ? _queueRowsFocus : null,
    rowFocus: _queueRowFocus,
    onRemote: _queueMenu,
    onMenu: _queueMenu,
    onClear: _clearQueue,
  );

  /// The lyrics or the queue at the side, on a card of dark glass.
  Widget _panelCard(Widget child, double s, {Widget? header}) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.32),
      borderRadius: BorderRadius.circular(20 * s),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(12 * s, 20 * s, 12 * s, 8 * s),
      child: Focus(
        focusNode: _panelFocus,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?header,
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );

  /// Scaled down to fit (a short window, a phone on its side), never cut.
  Widget _fit(Widget child, {Alignment alignment = Alignment.centerLeft}) =>
      LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: SizedBox(width: constraints.maxWidth, child: child),
        ),
      );

  // --- The TV, and a phone or a window on its side ---

  /// The cover on the left and the song on the right, «A continuación» and
  /// the round buttons along the bottom (the music design's
  /// «tele_reproductor»). With the lyrics or the queue, those take the right
  /// and the song goes under a smaller cover.
  Widget _wide(AggregatedItem item, Size size) {
    final s =
        (_tv
                ? size.height / 720
                : math.min(size.height / 720, size.width / 1280))
            .clamp(0.55, 3.0);
    final panel = switch (_view) {
      _View.lyrics when _hasLyrics => _lyricsPanel(big: _tv),
      _View.queue => _queuePanel(big: _tv, scale: _tv ? s : 1),
      _ => null,
    };
    final info = _info(item, s, compact: panel != null);
    final top = LayoutBuilder(
      builder: (context, constraints) {
        if (panel == null) {
          final cover = math.min(400 * s, constraints.maxHeight);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cover(item, cover),
              SizedBox(width: 64 * s),
              Expanded(
                child: SizedBox(height: cover, child: _fit(info)),
              ),
            ],
          );
        }
        final cover = math.min(190 * s, constraints.maxHeight * 0.34);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: _fit(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cover(item, cover),
                    SizedBox(height: 24 * s),
                    info,
                  ],
                ),
              ),
            ),
            SizedBox(width: 48 * s),
            Expanded(flex: 6, child: _panelCard(panel, s)),
          ],
        );
      },
    );
    final ownVolume = KostvNowPlaying.hasOwnVolume;
    final gap = SizedBox(width: 14 * s);
    final bottom = SizedBox(
      height: 52 * s,
      child: Row(
        children: [
          Expanded(child: _UpNext(scale: s)),
          if (ownVolume) ...[
            _MusicVolume(volume: _music.volume, onChanged: _music.setVolume),
            gap,
          ],
          if (_hasFavorite(item)) ...[
            _heart(item, size: 22 * s, glass: true),
            gap,
          ],
          if (_dislike(item, size: 22 * s, glass: true)
              case final dislike?) ...[
            dislike,
            gap,
          ],
          // Kos TV: no lyrics for a song that isn't at home.
          if (!isKostvStream(item)) ...[
            _lyricsButton(size: 22 * s, glass: true),
            gap,
          ],
          _queueButton(size: 22 * s, glass: true),
          gap,
          _moreButton(item, size: 22 * s, glass: true),
        ],
      ),
    );
    return SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(96 * s, 88 * s, 96 * s, 36 * s),
            child: Column(
              children: [
                Expanded(child: top),
                SizedBox(height: 20 * s),
                bottom,
              ],
            ),
          ),
          if (!_tv)
            Positioned(
              top: 24 * s,
              left: 32 * s,
              child: _hideButton(size: 22 * s, glass: true),
            ),
        ],
      ),
    );
  }

  /// The song: «Sonando», its title, its artists and album, the line of one
  /// that isn't at home, the progress and the controls.
  Widget _info(AggregatedItem item, double s, {bool compact = false}) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Kicker(l10n.kostvPlayerSounding, size: 13 * s),
        SizedBox(height: 8 * s),
        _TitleBlock(
          item: item,
          titleSize: (compact ? 44 : 64) * s,
          lineSize: (compact ? 20 : 24) * s,
          gap: 8 * s,
          artists: _artistLinks(item),
          album: _albumLink(item),
        ),
        if (isKostvStream(item)) ...[
          SizedBox(height: 20 * s),
          KostvStreamPill(item: item, big: true, scale: s, stop: _stop),
        ],
        SizedBox(height: (compact ? 26 : 34) * s),
        _Scrubber(scale: s, note: _preparingNote(s, big: true)),
        SizedBox(height: 20 * s),
        Center(
          child: _transport(
            play: 84 * s,
            skip: 40 * s,
            side: 28 * s,
            gap: 34 * s,
          ),
        ),
      ],
    );
  }

  // --- The computer ---

  /// The cover and the song on the left, the queue and the lyrics in a panel
  /// on the right (the music design's «ordenador_reproductor_cola»).
  Widget _desktop(AggregatedItem item, Size size) {
    final l10n = AppLocalizations.of(context);
    final s = math.min(size.height / 900, size.width / 1440).clamp(0.7, 1.6);
    final stream = isKostvStream(item);
    final lyrics = _view == _View.lyrics && _hasLyrics;
    final dislike = _dislike(item, size: 24 * s);
    final left = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cover(item, 440 * s),
        SizedBox(height: 30 * s),
        Row(
          children: [
            Expanded(
              child: _TitleBlock(
                item: item,
                titleSize: 40 * s,
                lineSize: 19 * s,
                gap: 4 * s,
                maxLines: 1,
                artists: _artistLinks(item),
                album: _albumLink(item),
              ),
            ),
            ?dislike,
            if (_hasFavorite(item)) _heart(item, size: 28 * s),
          ],
        ),
        if (stream) ...[
          SizedBox(height: 14 * s),
          KostvStreamPill(item: item, big: true, scale: 0.9 * s, stop: _stop),
        ],
        SizedBox(height: 22 * s),
        _Scrubber(scale: s, note: _preparingNote(s)),
        SizedBox(height: 10 * s),
        _transport(play: 70 * s, skip: 36 * s, side: 24 * s),
        if (KostvNowPlaying.hasOwnVolume) ...[
          SizedBox(height: 14 * s),
          Center(
            child: _MusicVolume(
              volume: _music.volume,
              onChanged: _music.setVolume,
            ),
          ),
        ],
      ],
    );
    final tabs = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * s),
      child: Row(
        children: [
          _Tab(
            icon: Icons.queue_music_rounded,
            label: l10n.kostvPlayerQueueTab,
            on: !lyrics,
            scale: s,
            onTap: () => _show(_View.queue),
          ),
          if (!stream) ...[
            SizedBox(width: 8 * s),
            _Tab(
              icon: Icons.notes_rounded,
              label: l10n.kostvPlayerLyrics,
              on: lyrics,
              scale: s,
              onTap: _hasLyrics ? () => _show(_View.lyrics) : null,
            ),
          ],
        ],
      ),
    );
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            left: 96 * s,
            top: 92 * s,
            bottom: 24 * s,
            width: 440 * s,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(width: 440 * s, child: left),
            ),
          ),
          Positioned(
            top: 24 * s,
            left: 32 * s,
            child: Row(
              children: [
                _hideButton(size: 22 * s, glass: true),
                SizedBox(width: 12 * s),
                _moreButton(item, size: 22 * s, glass: true),
              ],
            ),
          ),
          Positioned(
            right: 32 * s,
            top: 32 * s,
            bottom: 32 * s,
            width: 520 * s,
            child: _panelCard(
              lyrics ? _lyricsPanel() : _queuePanel(),
              s,
              header: Padding(
                padding: EdgeInsets.only(bottom: 8 * s),
                child: tabs,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- The phone upright ---

  /// The cover big at the top, the song and the controls under it (the
  /// music design's «movil_reproductor»). The lyrics take the cover's place;
  /// the queue comes up in a sheet.
  Widget _phone(AggregatedItem item, Size size) {
    final l10n = AppLocalizations.of(context);
    final padding = MediaQuery.paddingOf(context);
    final stream = isKostvStream(item);
    final lyrics = _view == _View.lyrics && _hasLyrics;
    final album = _albumLink(item);
    final dislike = _dislike(item, size: 24);

    final top = Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Row(
        children: [
          _hideButton(size: 30),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Kicker(
                  album == null
                      ? l10n.kostvNowPlaying
                      : l10n.kostvPlayerPlayingFrom,
                  size: 11,
                ),
                if (album != null) ...[
                  const SizedBox(height: 2),
                  _Stop(
                    onTap: album.onTap,
                    builder: (context, lit) => Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: KostvMusicTokens.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: lit && album.opens
                            ? TextDecoration.underline
                            : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _moreButton(item, size: 26),
        ],
      ),
    );

    final Widget middle = lyrics
        ? _lyricsPanel()
        : LayoutBuilder(
            builder: (context, constraints) => Center(
              child: GestureDetector(
                // Sideways on the cover, the next song or the one before.
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -250) _next();
                  if (v > 250) _previous();
                },
                child: _cover(
                  item,
                  math.max(
                    120.0,
                    math.min(
                      constraints.maxWidth - 48,
                      constraints.maxHeight - 24,
                    ),
                  ),
                ),
              ),
            ),
          );

    return GestureDetector(
      // Down from the top, back to the floating player.
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 500 && !lyrics) context.pop();
      },
      child: Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
        child: Column(
          children: [
            top,
            Expanded(child: middle),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _TitleBlock(
                          item: item,
                          titleSize: 28,
                          lineSize: 17,
                          gap: 4,
                          maxLines: 1,
                          artists: _artistLinks(item),
                        ),
                      ),
                      if (_hasFavorite(item)) _heart(item, size: 28),
                    ],
                  ),
                  if (stream) ...[
                    const SizedBox(height: 14),
                    KostvStreamPill(item: item, short: true, stop: _stop),
                  ],
                  const SizedBox(height: 20),
                  _Scrubber(note: _preparingNote(1)),
                  const SizedBox(height: 12),
                  _transport(play: 76, skip: 40, side: 26),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      ?dislike,
                      const Spacer(),
                      // Kos TV: no lyrics for a song that isn't at home.
                      if (!stream) ...[
                        _lyricsButton(size: 24),
                        const SizedBox(width: 16),
                      ],
                      _queueButton(size: 26, onTap: _openQueueSheet),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kos TV: no lyrics to look for.
class _NoLyrics implements Exception {
  const _NoLyrics();
}

// --- The background ---

/// The cover's colours across the screen, as the music design's player
/// has them: on the TV and the computer, the cover's colour from the top
/// left and its darker one from the bottom right over Music's dark; on the
/// phone, from the top down. Only gradients: nothing to work out on every
/// frame of a slow TV.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.upright});

  final bool upright;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ValueListenableBuilder<KostvCoverColors>(
      valueListenable: KostvNowPlaying.instance.colors,
      builder: (context, colors, _) {
        // The brighter of the cover's colours, as it is seen on it.
        final light = Color.lerp(colors.top, colors.accent, 0.35)!;
        const duration = Duration(milliseconds: 900);
        final layers = upright
            ? [
                AnimatedContainer(
                  duration: duration,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        light.withValues(alpha: 0.8),
                        colors.bottom,
                        const Color(0xFF060A14),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ]
            : [
                AnimatedContainer(
                  duration: duration,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.8, -0.6),
                      radius: 1.0,
                      colors: [
                        light.withValues(alpha: 0.85),
                        light.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: duration,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.8, 1),
                      radius: 1.0,
                      colors: [
                        colors.bottom,
                        colors.bottom.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ];
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF07090C)),
            ...layers,
            // Calmer, so the white letters read on any cover.
            ColoredBox(
              color: Colors.black.withValues(alpha: upright ? 0.2 : 0.22),
            ),
          ],
        );
      },
    ),
  );
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
    scale: playing ? 1 : 0.88,
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
          borderRadius: BorderRadius.circular(size * 0.04),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: playing ? 0.55 : 0.35),
              blurRadius: playing ? size * 0.22 : size * 0.1,
              offset: Offset(0, playing ? size * 0.1 : size * 0.04),
            ),
          ],
        ),
        child: _CoverThumb(item: item, size: size, radius: size * 0.04),
      ),
    ),
  );
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.item, required this.size, this.radius});

  final AggregatedItem item;
  final double size;
  final double? radius;

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
      borderRadius: BorderRadius.circular(radius ?? size * 0.035 + 4),
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

/// Kos TV: a small heading in capitals («SONANDO», «A CONTINUACIÓN»).
class _Kicker extends StatelessWidget {
  const _Kicker(this.text, {required this.size, this.color});

  final String text;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: color ?? Colors.white.withValues(alpha: 0.7),
      fontSize: size,
      fontWeight: FontWeight.w500,
      letterSpacing: size * 0.08,
      height: 1.2,
    ),
  );
}

/// The song's title in the brand's letters (Outfit) and, under it, its
/// artists (and its album), each opening its page.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.item,
    required this.titleSize,
    required this.lineSize,
    this.gap = 6,
    this.maxLines = 2,
    this.centered = false,
    this.artists = const [],
    this.album,
  });

  final AggregatedItem item;
  final double titleSize;
  final double lineSize;
  final double gap;
  final int maxLines;
  final bool centered;

  /// Kos TV: the song's artists and its album, each opening its page (a
  /// tap, a click, or a stop of the remote with OK).
  final List<KostvMusicLink> artists;
  final KostvMusicLink? album;

  @override
  Widget build(BuildContext context) {
    final artist = KostvNowPlaying.instance.artistOf(item);
    final albumName = item.album;
    final secondLine = [
      if (artist.isNotEmpty) artist,
      if (album != null && albumName != null && albumName.isNotEmpty) albumName,
    ].join(' · ');
    final align = centered ? TextAlign.center : TextAlign.start;
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.75),
      fontSize: lineSize,
      fontWeight: FontWeight.w400,
      height: 1.2,
    );
    final links = [
      artists,
      if (album case final a?) [a],
    ];
    final artistText = links.any((group) => group.any((link) => link.opens))
        ? KostvMusicLinkButtons(
            groups: links,
            style: style,
            centred: centered,
            oneLine: true,
            look: KostvMusicLinkLook.player,
            stop: (onTap, builder) => _Stop(onTap: onTap, builder: builder),
          )
        : Text(
            secondLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: style,
          );
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.name,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: KostvMusicType.title(titleSize).copyWith(height: 1.08),
        ),
        if (secondLine.isNotEmpty) ...[
          // The buttons' own room makes up the gap above them.
          SizedBox(height: artistText is Text ? gap : math.max(0, gap - 4)),
          artistText,
        ],
      ],
    );
  }
}

/// Kos TV: «A continuación» at the bottom of the TV's player: the next
/// song's cover, title and artist. Not a stop: the queue's button opens
/// the whole list.
class _UpNext extends StatelessWidget {
  const _UpNext({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final queue = GetIt.instance<PlaybackManager>().queueService;
    final next = kostvUpcoming(queue).firstOrNull?.item;
    if (next == null) return const SizedBox.shrink();
    final s = scale;
    final artist = KostvNowPlaying.instance.artistOf(next);
    return Row(
      children: [
        _CoverThumb(item: next, size: 40 * s, radius: 6 * s),
        SizedBox(width: 12 * s),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Kicker(
                AppLocalizations.of(context).kostvPlayerQueue,
                size: 12 * s,
                color: KostvMusicTokens.dim,
              ),
              SizedBox(height: 2 * s),
              Text(
                artist.isEmpty ? next.name : '${next.name} · $artist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KostvMusicType.body(15 * s),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- The progress ---

/// How far the song has gone, in the brand's gradient, to drag or tap
/// anywhere along; with the remote, left and right move ten seconds. While
/// a song that isn't at home is got ready, [note] stands where the times are.
class _Scrubber extends StatefulWidget {
  const _Scrubber({this.scale = 1, this.note});

  final double scale;
  final Widget? note;

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
    final k = widget.scale;
    final focused = InputModeTracker.showFocusVisuals(context, _focused);
    final lit = _dragging != null || _hovered || focused;
    final total = _duration;
    final at = Duration(milliseconds: (_value * total.inMilliseconds).round());
    final left = total - at;
    final timeStyle = TextStyle(
      color: KostvMusicTokens.muted,
      fontSize: 13 * k,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final track = (lit ? 7.0 : 5.0) * k;
    final knob = (focused ? 20.0 : (lit ? 15.0 : 13.0)) * k;
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
            final width = constraints.maxWidth;
            double fractionAt(Offset local) =>
                (local.dx / width).clamp(0.0, 1.0);
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
                    height: 22 * k,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: track,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(track),
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        // What has sounded, in the brand's gradient.
                        SizedBox(
                          width: width * _value,
                          height: track,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(track),
                              gradient: KostvMusicTokens.gradient,
                            ),
                          ),
                        ),
                        Positioned(
                          left: width * _value - knob / 2,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: knob,
                            height: knob,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: KostvMusicTokens.ink,
                              boxShadow: [
                                BoxShadow(
                                  color: focused
                                      ? KostvMusicTokens.violet.withValues(
                                          alpha: 0.8,
                                        )
                                      : Colors.black.withValues(alpha: 0.3),
                                  blurRadius: focused ? 18 : 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 4 * k),
                  SizedBox(
                    height: 18 * k,
                    child: widget.note != null
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: widget.note,
                          )
                        : Row(
                            children: [
                              Text(_time(at), style: timeStyle),
                              const Spacer(),
                              Text(
                                '-${_time(left.isNegative ? Duration.zero : left)}',
                                style: timeStyle,
                              ),
                            ],
                          ),
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

/// The same, for a Music piece that asks first ([KostvPlayButton],
/// [KostvSongRow]): from the stop that has the focus.
KeyEventResult _moveFocusFromHere(KeyEvent event) {
  final node = FocusManager.instance.primaryFocus;
  return node == null ? KeyEventResult.ignored : _moveFocus(node, event);
}

// --- Buttons ---

/// A stop of the remote, a tap and a click.
class _Stop extends StatefulWidget {
  const _Stop({
    required this.builder,
    required this.onTap,
    this.focusNode,
    this.tooltip,
    this.reveal = true,
    this.focusable,
  });

  /// Kos TV: whether the remote can stop on it; by default, when it does
  /// something ([onTap]).
  final bool? focusable;

  /// Whether the focus brings it into view in the list it is in. Kos TV: the
  /// synced lyrics bring their lines into view themselves.
  final bool reveal;

  final Widget Function(BuildContext context, bool lit) builder;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
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
      canRequestFocus: widget.focusable ?? widget.onTap != null,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f || !widget.reveal) return;
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

/// Kos TV: one of the player's icon buttons, in the music design's way:
/// bare (the controls, the phone's) or in a round of glass ([glass], the
/// TV's and the computer's). With the remote's focus or the mouse, white
/// with a black icon and a little bigger. [active] (shuffle or repeat on,
/// the lyrics open) lights it with a dot under it, or a brighter glass.
class _PlayerIcon extends StatelessWidget {
  const _PlayerIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 24,
    this.glass = false,
    this.active = false,
    this.enabled = true,
    this.color,
    this.focusNode,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Of the icon; its round is about twice as big.
  final double size;
  final bool glass;
  final bool active;
  final bool enabled;
  final Color? color;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final diameter = size * (glass ? 2.18 : 1.75);
    return _Stop(
      tooltip: tooltip,
      focusNode: focusNode,
      onTap: enabled ? onTap : null,
      builder: (context, lit) {
        final ink = !enabled
            ? Colors.white.withValues(alpha: 0.28)
            : lit
            ? KostvMusicTokens.background
            : color ??
                  (glass || active
                      ? KostvMusicTokens.ink
                      : KostvMusicTokens.ink.withValues(alpha: 0.75));
        final background = lit
            ? KostvMusicTokens.ink
            : glass
            ? KostvMusicTokens.glass(active ? 0.24 : 0.10)
            : Colors.transparent;
        return AnimatedScale(
          scale: lit ? 1.1 : 1,
          duration: KostvMusicTokens.focusDuration,
          curve: KostvMusicTokens.focusCurve,
          child: SizedBox.square(
            dimension: diameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: KostvMusicTokens.focusDuration,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: background,
                    boxShadow: lit
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 24,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                ),
                Icon(icon, size: size, color: ink),
                if (active && !glass)
                  Positioned(
                    bottom: diameter * 0.04,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: lit
                            ? KostvMusicTokens.background
                            : KostvMusicTokens.ink,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shuffle, the song before, play/pause (the brand's one play button), the
/// next song and repeat: centred [gap] apart, or spread along the width.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.state,
    required this.playing,
    required this.playFocus,
    required this.onPrevious,
    required this.onNext,
    required this.play,
    required this.skip,
    required this.side,
    this.gap,
  });

  final PlayerState state;
  final bool playing;
  final FocusNode playFocus;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// The play button's diameter, the skips' icons' and shuffle's and
  /// repeat's.
  final double play;
  final double skip;
  final double side;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = GetIt.instance<PlaybackManager>();
    final repeat = state.repeatMode;
    final children = [
      _PlayerIcon(
        icon: Icons.shuffle_rounded,
        tooltip: l10n.shuffle,
        active: state.isShuffled,
        size: side,
        onTap: manager.toggleShuffle,
      ),
      _PlayerIcon(
        icon: Icons.skip_previous_rounded,
        tooltip: l10n.kostvPlayerPrevious,
        color: KostvMusicTokens.ink,
        size: skip,
        onTap: onPrevious,
      ),
      KostvPlayButton(
        diameter: play,
        pause: playing,
        tooltip: playing ? l10n.pause : l10n.play,
        focusNode: playFocus,
        autofocus: true,
        onKey: _moveFocusFromHere,
        onTap: KostvNowPlaying.instance.playPause,
      ),
      _PlayerIcon(
        icon: Icons.skip_next_rounded,
        tooltip: l10n.next,
        color: KostvMusicTokens.ink,
        size: skip,
        onTap: onNext,
      ),
      _PlayerIcon(
        icon: repeat == RepeatMode.repeatOne
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
        tooltip: repeat == RepeatMode.repeatOne
            ? l10n.kostvPlayerRepeatOne
            : l10n.kostvPlayerRepeat,
        active: repeat != RepeatMode.none,
        size: side,
        onTap: manager.toggleRepeat,
      ),
    ];
    final gap = this.gap;
    if (gap == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: children,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) SizedBox(width: gap),
          child,
        ],
      ],
    );
  }
}

/// Kos TV: a tab of the computer's panel («Cola», «Letra»): white while it
/// is the one shown.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.scale = 1,
  });

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback? onTap;
  final double scale;

  @override
  Widget build(BuildContext context) => _Stop(
    onTap: onTap,
    builder: (context, lit) {
      final k = scale;
      final white = on || lit;
      final ink = white
          ? KostvMusicTokens.background
          : (onTap == null
                ? Colors.white.withValues(alpha: 0.3)
                : KostvMusicTokens.muted);
      return AnimatedContainer(
        duration: KostvMusicTokens.focusDuration,
        height: 32 * k,
        padding: EdgeInsets.symmetric(horizontal: 14 * k),
        decoration: BoxDecoration(
          color: on
              ? KostvMusicTokens.ink
              : lit
              ? KostvMusicTokens.ink.withValues(alpha: 0.85)
              : KostvMusicTokens.glass(0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16 * k, color: ink),
            SizedBox(width: 8 * k),
            Text(
              label,
              style: TextStyle(
                color: ink,
                fontSize: 13 * k,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Kos TV: rebuilds the queue in the phone's sheet (a page of its own,
/// which the player's rebuilds don't reach) as the queue changes.
class _LiveQueue extends StatefulWidget {
  const _LiveQueue({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_LiveQueue> createState() => _LiveQueueState();
}

class _LiveQueueState extends State<_LiveQueue> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = GetIt.instance<PlaybackManager>().queueService.queueChangedStream
        .listen((_) => _changed());
    KostvNowPlaying.instance.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    KostvNowPlaying.instance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

// --- Lyrics ---

/// The lyrics, sung along: the line sounding big and bright, the ones to
/// come dimmed and the ones gone dimmer still, and the page following the
/// song with the line sounding a third of the way down. A line picked jumps
/// there, and the page follows from it.
///
/// Kos TV: every line is built (lyrics are a few dozen lines), so the one
/// sounding can always be found and brought into view, however far down it
/// is. Moving the lyrics by hand (a finger, the mouse wheel, the remote along
/// the lines) stops the following for a few seconds after the last move;
/// meanwhile «Volver a la línea actual» brings it back at once (off the TV,
/// where the remote picks a line instead).
@visibleForTesting
class KostvLyricsPanel extends StatefulWidget {
  const KostvLyricsPanel({super.key, required this.lyrics, this.big = false});

  final LyricsData lyrics;
  final bool big;

  /// How long the following waits after the last move by hand.
  static const holdFor = Duration(seconds: 4);

  @override
  State<KostvLyricsPanel> createState() => _KostvLyricsPanelState();
}

class _KostvLyricsPanelState extends State<KostvLyricsPanel> {
  final _manager = GetIt.instance<PlaybackManager>();
  StreamSubscription<Duration>? _sub;
  final _scroll = ScrollController();
  late List<GlobalKey> _keys;
  late List<FocusNode> _nodes;
  int _active = -1;

  // Moved by hand: the page stops following until [_resume] fires.
  bool _held = false;
  Timer? _resume;

  // The line the panel itself is sending the remote to, so its arrival
  // isn't taken for a move by hand.
  int? _focusTarget;

  // The line just picked, until the player has got there.
  ({int index, DateTime until})? _picked;

  @override
  void initState() {
    super.initState();
    _makeLines();
    _listen();
  }

  @override
  void didUpdateWidget(KostvLyricsPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.lyrics, widget.lyrics)) {
      // The old lines' stops go once the new ones have taken their place.
      final gone = _nodes;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in gone) {
          node.dispose();
        }
      });
      _makeLines();
      _active = -1;
      _held = false;
      _resume?.cancel();
      _resume = null;
      _focusTarget = null;
      _picked = null;
      _sub?.cancel();
      _sub = null;
      _listen();
    }
  }

  void _makeLines() {
    final count = widget.lyrics.lines.length;
    _keys = List.generate(count, (_) => GlobalKey());
    _nodes = [
      for (var i = 0; i < count; i++)
        FocusNode(debugLabel: 'LyricsLine$i')
          ..addListener(() => _lineFocusChanged(i)),
    ];
  }

  void _listen() {
    if (!widget.lyrics.isSynced) return;
    // Straight to the line sounding, with no scrolling to it.
    _active = _indexAt(_manager.state.position);
    _follow(jump: true);
    _sub = _manager.state.positionStream.listen(_update);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _resume?.cancel();
    _scroll.dispose();
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  int _indexAt(Duration position) {
    final lines = widget.lyrics.lines;
    for (var i = lines.length - 1; i >= 0; i--) {
      if (position >= lines[i].start) return i;
    }
    return -1;
  }

  void _update(Duration position) {
    if (!mounted) return;
    final index = _indexAt(position);
    // A line just picked: a position from before the jump doesn't take the
    // page back for a moment.
    final picked = _picked;
    if (picked != null) {
      if (DateTime.now().isBefore(picked.until) && index != picked.index) {
        return;
      }
      _picked = null;
    }
    if (index == _active) return;
    setState(() => _active = index);
    _follow();
  }

  /// Brings the line sounding a third of the way down, unless the person is
  /// moving the lyrics. With the remote on a line, it moves along with it.
  void _follow({bool jump = false}) {
    if (_held || !widget.lyrics.isSynced || !mounted) return;
    final index = _active < 0 ? 0 : _active;
    if (index >= _nodes.length) return;
    final focused = _nodes.indexWhere((node) => node.hasPrimaryFocus);
    if (focused >= 0 && focused != index) {
      _focusTarget = index;
      _nodes[index].requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _held || !_scroll.hasClients) return;
      final box = _keys[index].currentContext?.findRenderObject();
      if (box == null || !box.attached) return;
      unawaited(
        _scroll.position.ensureVisible(
          box,
          alignment: 0.35,
          duration: jump ? Duration.zero : const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  /// Moved by hand: the following waits until a while after the last move.
  void _hold() {
    if (!widget.lyrics.isSynced) return;
    _resume?.cancel();
    _resume = Timer(KostvLyricsPanel.holdFor, _release);
    if (!_held) setState(() => _held = true);
  }

  /// Back to following the song, from the line sounding now.
  void _release() {
    _resume?.cancel();
    _resume = null;
    if (!mounted) return;
    if (_held) setState(() => _held = false);
    _follow();
  }

  void _lineFocusChanged(int index) {
    if (!mounted || !_nodes[index].hasPrimaryFocus) return;
    if (_focusTarget == index) {
      _focusTarget = null;
      return;
    }
    _focusTarget = null;
    if (!widget.lyrics.isSynced) return;
    // The remote moved along the lines: the page shows the one it is on.
    _hold();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final box = _keys[index].currentContext?.findRenderObject();
      if (box == null || !box.attached) return;
      unawaited(
        _scroll.position.ensureVisible(
          box,
          alignment: 0.4,
          duration: const Duration(milliseconds: 200),
        ),
      );
    });
  }

  void _seekTo(int index) {
    final start = widget.lyrics.lines[index].start;
    unawaited(_manager.seekTo(start));
    // The page follows from the line picked, at once.
    _picked = (
      index: index,
      until: DateTime.now().add(const Duration(milliseconds: 1500)),
    );
    _held = false;
    _resume?.cancel();
    _resume = null;
    setState(() => _active = index);
    _follow();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final synced = widget.lyrics.isSynced;
    final size = widget.big ? 38.0 : 28.0;
    final list = SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.sizeOf(context).height * 0.25,
        horizontal: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              key: _keys[i],
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _line(i, synced: synced, size: size),
            ),
        ],
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
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
            child: Listener(
              // The mouse wheel (and a trackpad) moves the lyrics by hand.
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) _hold();
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // A finger or the wheel, not the page following the song.
                  if (notification is UserScrollNotification ||
                      (notification is ScrollUpdateNotification &&
                          notification.dragDetails != null)) {
                    _hold();
                  }
                  return false;
                },
                child: list,
              ),
            ),
          ),
        ),
        if (_held && synced && !PlatformDetection.isTV)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(child: _BackToLine(onTap: _release)),
          ),
      ],
    );
  }

  Widget _line(int i, {required bool synced, required double size}) {
    final line = widget.lyrics.lines[i];
    final active = synced && i == _active;
    final past = synced && i < _active;
    final text = line.text.trim().isEmpty ? '♪' : line.text;
    return _Stop(
      focusNode: _nodes[i],
      // Kos TV: a synced line the remote is on is brought into view by the
      // panel itself, which knows whether it moved there by hand.
      reveal: !synced,
      // Unsynced lyrics are still lines to move along with the remote, to
      // read them all; a synced one jumps there.
      onTap: synced ? () => _seekTo(i) : () {},
      builder: (context, lit) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        // Kos TV: the music design's focus: a soft glass and a white edge.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: lit ? KostvMusicTokens.glass(0.10) : Colors.transparent,
          border: PlatformDetection.isTV
              ? Border.all(
                  color: lit ? KostvMusicTokens.ink : Colors.transparent,
                  width: 2,
                )
              : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 320),
          // Kos TV: in the brand's letters, as the player's title.
          style: TextStyle(
            fontFamily: KostvMusicType.titleFamily,
            fontSize: synced ? size : size * 0.72,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: !synced
                ? Colors.white.withValues(alpha: 0.9)
                : active
                ? Colors.white
                // Kos TV: the lines gone a little dimmer than those to come.
                : past
                ? Colors.white.withValues(alpha: 0.26)
                : Colors.white.withValues(alpha: 0.4),
          ),
          child: Text(text),
        ),
      ),
    );
  }
}

/// «Volver a la línea actual», while the lyrics were moved by hand.
class _BackToLine extends StatelessWidget {
  const _BackToLine({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).kostvLyricsBackToLine;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.vertical_align_center_rounded,
                  color: Colors.black,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- The music's own volume ---

/// Kos TV: the music's own volume on the web on a computer: the speaker
/// mutes and brings back the level it had, and the slider sets it.
class _MusicVolume extends StatefulWidget {
  const _MusicVolume({required this.volume, required this.onChanged});

  /// From 0 to 100.
  final double volume;
  final ValueChanged<double> onChanged;

  @override
  State<_MusicVolume> createState() => _MusicVolumeState();
}

class _MusicVolumeState extends State<_MusicVolume> {
  double _beforeMute = 100;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final volume = widget.volume;
    final muted = volume <= 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: muted ? l10n.unmute : l10n.mute,
          icon: Icon(
            volumeIconFor(volume / 100),
            color: Colors.white.withValues(alpha: 0.8),
          ),
          onPressed: () {
            if (muted) {
              widget.onChanged(_beforeMute > 0 ? _beforeMute : 100);
            } else {
              _beforeMute = volume;
              widget.onChanged(0);
            }
          },
        ),
        SizedBox(
          width: 220,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: volume.clamp(0.0, 100.0),
              max: 100,
              semanticFormatterCallback: (value) =>
                  '${l10n.kostvPlayerVolume}: ${value.round()} %',
              onChanged: widget.onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// --- What comes next ---

/// What comes next, in Music's rows: autoplay (to go on with similar songs
/// from home when the queue runs out), the song sounding, and the songs to
/// come, to play, move and take away, with «Vaciar». The same rows whether
/// a song is at home or not (the music design: the queue doesn't say).
class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    this.big = false,
    this.scale = 1,
    this.rowsFocus,
    this.rowFocus,
    this.onRemote,
    this.onMenu,
    this.onClear,
    this.scrollController,
  });

  /// The TV's sizes.
  final bool big;
  final double scale;
  final FocusNode? rowsFocus;

  /// Kos TV: on the TV, each row's stop by its place in the list, so the
  /// remote stays on a place (and lights it) while the songs move under it.
  final FocusNode Function(int position)? rowFocus;

  /// Kos TV: OK on a row with the remote opens its menu (play it now, move
  /// it up or down, take it away) instead of playing it straight away.
  final void Function(AggregatedItem song)? onRemote;

  /// Kos TV: the same menu with touch (a long press) and the mouse («⋯» or
  /// a right click), where a tap plays the song.
  final void Function(AggregatedItem song)? onMenu;

  /// «Vaciar».
  final VoidCallback? onClear;

  /// The phone's sheet's, which it is dragged by.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = GetIt.instance<PlaybackManager>();
    final music = KostvNowPlaying.instance;
    final queue = manager.queueService;
    final upcoming = kostvUpcoming(queue);
    final touch = !PlatformDetection.isTV;
    final mobile = PlatformDetection.useMobileUi;
    final k = big ? scale : 1.0;
    final textSize = big ? 16 * k : 15.0;
    final coverSize = big ? 48 * k : 48.0;
    final current = music.item;

    Widget kicker(String text, {Widget? trailing}) => Padding(
      padding: EdgeInsets.fromLTRB(12, 18 * k, 8, 8 * k),
      child: Row(
        children: [
          Expanded(
            child: _Kicker(
              text,
              size: 13 * k,
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
          ?trailing,
        ],
      ),
    );

    final autoplay = _Stop(
      onTap: () => music.autoplay = !music.autoplay,
      builder: (context, lit) => AnimatedContainer(
        duration: KostvMusicTokens.focusDuration,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.fromLTRB(12, 8 * k, 6, 8 * k),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KostvMusicTokens.radiusRow),
          color: lit
              ? KostvMusicTokens.glass(0.13)
              : KostvMusicTokens.glass(0.05),
          border: Border.all(
            color: lit && !touch ? KostvMusicTokens.ink : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.all_inclusive_rounded,
              color: music.autoplay
                  ? KostvMusicTokens.ink
                  : KostvMusicTokens.muted,
              size: 22 * k,
            ),
            SizedBox(width: 12 * k),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.kostvPlayerAutoplay,
                    style: KostvMusicType.body(textSize - 1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.kostvPlayerAutoplayHint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: KostvMusicType.muted(textSize - 3),
                  ),
                ],
              ),
            ),
            IgnorePointer(
              child: Switch(
                value: music.autoplay,
                activeThumbColor: KostvMusicTokens.ink,
                activeTrackColor: KostvMusicTokens.violet,
                onChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );

    final sounding = current == null
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: KostvSongRowFace(
              lit: false,
              sound: music.playing
                  ? KostvSongSound.playing
                  : KostvSongSound.paused,
              title: current.name,
              subtitle: music.artistOf(current),
              coverArt: _CoverThumb(
                item: current,
                size: coverSize,
                radius: KostvMusicTokens.radiusSmallCover,
              ),
              showCover: true,
              coverSize: coverSize,
              textSize: textSize,
              duration: kostvSongLength(current.runtime?.inSeconds),
            ),
          );

    final clear = onClear == null || upcoming.isEmpty
        ? null
        : _Stop(
            onTap: onClear,
            builder: (context, lit) => AnimatedContainer(
              duration: KostvMusicTokens.focusDuration,
              padding: EdgeInsets.symmetric(
                horizontal: 10 * k,
                vertical: 4 * k,
              ),
              decoration: BoxDecoration(
                color: lit ? KostvMusicTokens.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l10n.kostvPlayerClearQueue,
                style: TextStyle(
                  color: lit
                      ? KostvMusicTokens.background
                      : KostvMusicTokens.muted,
                  fontSize: 13 * k,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Downloaded music has no home server to ask for more.
        if (!manager.isOfflinePlayback) autoplay,
        if (sounding != null) ...[kicker(l10n.kostvPlayerSounding), sounding],
        kicker(l10n.kostvPlayerQueue, trailing: clear),
        if (upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            child: Text(
              l10n.kostvPlayerQueueEmpty,
              style: KostvMusicType.muted(textSize - 1),
            ),
          ),
      ],
    );

    Widget row(({int index, AggregatedItem item}) entry, int position) {
      final item = entry.item;
      final fromAutoplay = music.autoplayItems.contains(item);
      final remote = onRemote;
      final menu = onMenu;
      final marks = <Widget>[
        // Kos TV: the queue doesn't mark the songs that aren't at home
        // (the music design: the player says so when they come); only
        // what autoplay brought.
        if (fromAutoplay)
          Tooltip(
            message: l10n.kostvPlayerAutoplayAdded,
            child: Icon(
              Icons.all_inclusive_rounded,
              size: 16 * k,
              color: KostvMusicTokens.dim,
            ),
          ),
        // Dragged by its handle (Kos TV: with the mouse too, as before: the
        // row held down is its menu).
        if (touch)
          ReorderableDragStartListener(
            index: position,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.drag_handle_rounded,
                size: 20,
                color: KostvMusicTokens.dim,
              ),
            ),
          ),
      ];
      final tile = KostvSongRow(
        title: item.name,
        subtitle: music.artistOf(item),
        coverArt: _CoverThumb(
          item: item,
          size: coverSize,
          radius: KostvMusicTokens.radiusSmallCover,
        ),
        coverSize: coverSize,
        textSize: textSize,
        duration: kostvSongLength(item.runtime?.inSeconds),
        trailing: marks.isEmpty
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: marks),
        focusNode: touch ? null : rowFocus?.call(position),
        onKey: touch ? null : _moveFocusFromHere,
        onTap: !touch && remote != null
            ? () => remote(item)
            : () {
                KostvNowPlaying.instance.noteChosen();
                unawaited(manager.playFromQueue(entry.index));
              },
        onMenu: touch && menu != null ? () => menu(item) : null,
        // Kos TV: on the phone «⋯» stays at hand: its menu is how a song is
        // taken out of the queue (nothing hovers there).
        menuAlways: touch && mobile,
      );
      return KeyedSubtree(
        // Kos TV: on the TV by place, so the row the remote is on keeps its
        // stop (and its light) while a song moves through it.
        key: touch
            ? ValueKey('q-${item.id}-${entry.index}')
            : ValueKey('q-at-$position'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: tile,
        ),
      );
    }

    if (touch) {
      return ReorderableListView.builder(
        scrollController: scrollController,
        buildDefaultDragHandles: false,
        header: header,
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: upcoming.length,
        proxyDecorator: (child, _, _) => Material(
          color: KostvMusicTokens.glass(0.08),
          borderRadius: BorderRadius.circular(KostvMusicTokens.radiusRow),
          child: child,
        ),
        onReorderItem: (from, to) {
          final a = upcoming[from].index;
          final b = upcoming[to].index;
          queue.reorder(a, b > a ? b + 1 : b);
        },
        itemBuilder: (context, i) => row(upcoming[i], i),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: upcoming.isEmpty
              ? const SizedBox.shrink()
              : Focus(
                  focusNode: rowsFocus,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(0, 4 * k, 0, 24),
                    itemCount: upcoming.length,
                    itemBuilder: (context, i) => row(upcoming[i], i),
                  ),
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
    final s = (size.height / 720).clamp(0.55, 3.0);
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
        KostvEqualizerBars(
          playing: music.playing,
          size: 26 * s,
          gradient: KostvMusicTokens.gradient,
        ),
        SizedBox(width: 16 * s),
        Flexible(
          child: _TitleBlock(
            item: item,
            titleSize: 34 * s,
            lineSize: 18 * s,
            gap: 6 * s,
            maxLines: 1,
            centered: !withLyrics,
          ),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.075,
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
                      child: KostvLyricsPanel(lyrics: lyrics, big: true),
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
    );
  }
}
