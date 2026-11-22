import 'dart:async';

import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:playback_core/playback_core.dart' show PlaybackManager;
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/kostv_music_away.dart';
import '../../../data/services/kostv_music_catalog.dart';
import '../../../data/services/kostv_music_dislikes.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../playback/kostv_stream_playback.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_now_playing.dart';
import '../../widgets/music/design/kostv_music_design.dart';
import '../../widgets/music/kostv_stream_play.dart';
import '../../widgets/music/music_navigation.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_music_album_play.dart';
import 'kostv_music_album_screen.dart' show KostvMusicButton;
import 'kostv_music_actions.dart';
import 'kostv_music_away_actions.dart' show kostvAwaySayNothingToPlay;
import 'kostv_music_home_parts.dart';
import 'kostv_music_links.dart';
import 'kostv_music_widgets.dart';
import '../../../util/kostv_browser_menu.dart';

/// Kos TV: who is in a mix, from the artists that weigh most in it
/// ([names], the plugin's `Because`): «Con X», «Con X y Y» or «Con X, Y y
/// más». Null without any (a plugin from before them).
///
/// Kos TV: in Spanish «e» rather than «y» before a name that starts with
/// the «i» sound («Con Lola e Isabel»; not «hie»: «y Hielo»).
String? kostvMusicBecause(AppLocalizations l10n, List<String> names) =>
    switch (names) {
      [] => null,
      [final first] => l10n.kostvMusicBecauseOne(first),
      [final first, final second] when kostvTakesE(second) =>
        l10n.kostvMusicBecauseTwoE(first, second),
      [final first, final second] => l10n.kostvMusicBecauseTwo(first, second),
      [final first, final second, ...] => l10n.kostvMusicBecauseMore(
        first,
        second,
      ),
    };

/// Kos TV: whether the Spanish «y» before [word] becomes «e»: it starts
/// with «i» or «hi» (accented or not), but not with «hie» («y hierro»).
bool kostvTakesE(String word) {
  final w = word.trimLeft().toLowerCase();
  if (w.startsWith('hie')) return false;
  return w.startsWith('i') ||
      w.startsWith('í') ||
      w.startsWith('hi') ||
      w.startsWith('hí');
}

/// Kos TV: Music, a page of its own as the music apps open: a big search
/// at the top (only music: what is at home and, under it, what can be asked
/// for), the charts right under it, and then what goes with what the person
/// listens to: their albums of late, mixes of their artists, more of the one
/// they listen to most, the chart of their genre, what the house asked for
/// and what arrived. Not a wall of posters: covers, lists and mixes.
///
/// Kos TV: in the music design (`docs/diseno-musica/README.md`, phase 4):
/// the title with the search at its right (a button on the phone) and the
/// tabs «Para ti · Tus listas · Artistas · Álbumes» under it; «Para ti» opens
/// with «Sigue escuchando» and then every section it had, in the same order,
/// as big cards, mix cards and clean columns of songs.
class KostvMusicScreen extends StatefulWidget {
  const KostvMusicScreen({super.key});

  @override
  State<KostvMusicScreen> createState() => _KostvMusicScreenState();
}

class _KostvMusicScreenState extends State<KostvMusicScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'kostvMusicSearch');
  final _searchTvField = GlobalKey<CustomTVTextFieldState>();
  final _firstStop = FocusNode(debugLabel: 'kostvMusicFirst');

  /// Kos TV: the search's «Lo mejor» ▶ and first song: the remote goes
  /// from the card to its ▶ and on to the songs at its side.
  final _topPlay = FocusNode(debugLabel: 'kostvMusicTopPlay');
  final _firstSong = FocusNode(debugLabel: 'kostvMusicFirstSong');

  /// Kos TV: the tabs of the home, the one shown and the remote's node of
  /// each.
  KostvMusicTab _tab = KostvMusicTab.forYou;
  final _tabNodes = {
    for (final tab in KostvMusicTab.values)
      tab: FocusNode(debugLabel: 'kostvMusicTab-${tab.name}'),
  };

  /// Kos TV: the search's box keeps its state as it moves (from the
  /// title's side to the top of the results).
  final _searchBox = GlobalKey(debugLabel: 'kostvMusicSearchBox');

  /// Kos TV: on the phone the search is a button: the field shows while
  /// this is on.
  bool _searchOpen = false;

  /// Kos TV: what the search shows (the phone's and the web's pills).
  KostvMusicFilter _filter = KostvMusicFilter.all;

  /// Kos TV: the «Artistas» and «Álbumes» tabs: by name, or what was played
  /// lately first (the default).
  bool _byName = false;
  final _sortNodes = {
    false: FocusNode(debugLabel: 'kostvMusicSortRecent'),
    true: FocusNode(debugLabel: 'kostvMusicSortName'),
  };

  /// Kos TV: what is at home for the tabs, read the first time one opens:
  /// a page at a time by name (the next one as the grid comes near its end),
  /// and what was played lately on its own (first in «Escuchado hace poco
  /// primero», whichever page it is on).
  List<AggregatedItem>? _libraryAlbums;
  List<AggregatedItem>? _libraryArtists;
  List<AggregatedItem> _recentAlbums = const [];
  List<AggregatedItem> _recentArtists = const [];
  List<String> _recentAlbumIds = const [];
  List<String> _recentArtistIds = const [];
  bool _albumsMore = false;
  bool _artistsMore = false;
  bool _albumsPaging = false;
  bool _artistsPaging = false;
  bool _libraryLoading = false;
  bool _libraryFailed = false;

  /// Kos TV: the person's playlists couldn't be read (not «no tienes»).
  bool _playlistsFailed = false;

  /// The section [_firstStop] is in.
  String? _firstOwner;
  Timer? _debounce;

  late final KostvMusicService _music = KostvMusicService(
    GetIt.instance<MediaServerClient>(),
  );

  /// The requests service, when it lets the person in.
  StremfinService? _stremfin;

  // What the page shows, each as it comes.
  StremfinChartPage? _topSongs;
  StremfinChartPage? _latino;
  StremfinChartPage? _topAlbums;
  StremfinChartPage? _genreChart;
  StremfinChartPage? _mexico;
  StremfinChartPage? _unitedStates;

  /// Kos TV: «Listas de éxitos»: the list picked (null: the one it opens
  /// with, [kostvDefaultChart]) and the remote's node of each pill.
  KostvChartList? _chartPick;
  final _chartNodes = {
    for (final list in KostvChartList.values)
      list: FocusNode(debugLabel: 'kostvMusicChart-${list.name}'),
  };

  /// Kos TV: the lists of «Listas de éxitos» that are only asked of the
  /// service when picked (what was kept of them on the device shows at
  /// once): the opening asks for no more than before.
  static const _lazyCharts = {
    KostvChartList.mexico: 'mexico',
    KostvChartList.usa: 'usa',
    KostvChartList.albums: 'albums',
  };
  final _chartsAsked = <String>{};

  /// Kos TV: the service's parts whose last asking failed.
  final _partFailed = <String>{};

  /// Kos TV: the person's taste was read (so a new listener is known).
  bool _tasteKnown = false;

  /// «Para ti», from the requests service, and what is new of the person's
  /// artists.
  StremfinRecommendations? _forYou;
  List<StremfinAlbum> _yourNews = const [];
  List<AggregatedItem> _recent = const [];

  /// The person's ♥ songs and playlists, Jellyfin's own.
  List<AggregatedItem> _favorites = const [];
  List<AggregatedItem> _playlists = const [];
  List<AggregatedItem> _newAtHome = const [];
  KostvMusicTaste _taste = const KostvMusicTaste();
  ({String name, List<StremfinAlbum> albums})? _moreOf;

  /// Kos TV: what the server plugin works out from what the person listens
  /// to: their daily mixes, the mix of the time of day and the week's
  /// discovery. Null while (or when) the plugin doesn't answer: the page
  /// then shows what it showed before them.
  KostvDailyMixes? _dailyMixes;
  KostvMusicMoment? _moment;
  List<StremfinSong>? _discovery;

  /// Kos TV: the week [_discovery] is of, as kept or as the plugin said.
  String? _discoveryWeek;

  /// Kos TV: what the person doesn't want to hear, and the rows that play
  /// by themselves as shown, without it (what came is kept whole, so
  /// «Deshacer» brings it back at once).
  KostvMusicDislikes get _dislikes =>
      KostvMusicDislikesStore.instance.of(_client);
  KostvDailyMixes? get _shownMixes =>
      _dailyMixes == null ? null : _dislikes.mixesIn(_dailyMixes!);
  KostvMusicMoment? get _shownMoment =>
      _moment == null ? null : _dislikes.momentIn(_moment!);
  List<StremfinSong>? get _shownDiscovery =>
      _discovery == null ? null : _dislikes.stremfinSongsIn(_discovery!);
  StremfinRecommendations? get _shownForYou =>
      _forYou == null ? null : _dislikes.recommendationsIn(_forYou!);
  List<StremfinAlbum> get _shownYourNews =>
      _dislikes.stremfinAlbumsIn(_yourNews);

  /// Kos TV: a daily mix's genre and who is in it, for its menu.
  static String? _mixSubtitle(AppLocalizations l10n, KostvDailyMix mix) {
    final parts = [?mix.genre, ?kostvMusicBecause(l10n, mix.because)];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Kos TV: the slot of the day (by this device's clock) the moment's mix
  /// was last asked for: when the page is still open as another one starts,
  /// it is asked again.
  String? _momentAskedFor;
  Timer? _momentTurn;
  AppLifecycleListener? _lifecycle;

  /// Kos TV: the person had a moment's row last time (of another time of
  /// day, so not shown): its place is kept while today's is asked for, so
  /// the page doesn't jump when it lands.
  bool _momentHeld = false;

  /// Kos TV: the plugin answered (or failed) for the moment's mix at least
  /// once: what was kept no longer holds a place for it.
  bool _momentLanded = false;

  /// Kos TV: the plugin failed the last time the moment's mix was asked.
  bool _momentFailed = false;
  List<StremfinAlbum> _requested = const [];
  List<StremfinAlbum> _releases = const [];
  bool _loading = true;

  /// Something failed to load (not just came back empty).
  bool _failed = false;

  /// The service said the person may not use it: what it answered last time
  /// no longer comes in.
  bool _stremfinGone = false;

  /// Whether [_firstStop] was handed to something in the last build (a node
  /// keeps its old context after it is taken away).
  bool _firstStopShown = false;

  final _scroll = ScrollController();
  Timer? _refreshing;

  // The search.
  String _query = '';
  KostvMusicAtHome? _atHome;
  StremfinMusicSearch? _toAsk;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQuery);
    kostvMusicFavoritesChanged.addListener(_reloadFavorites);
    // With a mouse, the right click is the songs' menu, not the browser's.
    kostvHoldBrowserMenu();
    // Kos TV: «Qué música enseñar», as the person has it now.
    kostvRefreshMusicCatalog();
    // Kos TV: back to the app in another time of day: its mix.
    _lifecycle = AppLifecycleListener(onResume: _checkMomentSlot);
    // Kos TV: what the person doesn't want to hear leaves the rows that
    // play by themselves at once (and comes back with «Deshacer»).
    KostvMusicDislikesStore.instance.addListener(_dislikesChanged);
    // Kos TV: «Qué música enseñar» changed: the rows play (or not) at once.
    KostvMusicCatalog.instance.addListener(_refresh);
    unawaited(_stremfinReady);
  }

  /// One rebuild for the parts that land close together, rather than one
  /// each (a slow TV rebuilds the whole page every time).
  void _refresh() {
    _refreshing ??= Timer(const Duration(milliseconds: 60), () {
      _refreshing = null;
      if (mounted) setState(() {});
    });
  }

  void _dislikesChanged() {
    _keepMomentFocus();
    _refresh();
  }

  /// Kos TV: the moment row's songs as last built, each with its row's
  /// node, and those nodes, one per song (the mix's own entries).
  List<({AggregatedItem song, FocusNode node})> _momentRows = const [];
  final _momentNodes = Map<AggregatedItem, FocusNode>.identity();

  FocusNode _momentNode(AggregatedItem song) => _momentNodes.putIfAbsent(
    song,
    () => FocusNode(debugLabel: 'kostvMoment-${song.id}'),
  );

  /// Kos TV: the nodes of songs no longer in the moment's mix (another one
  /// came), once their rows are gone.
  void _pruneMomentNodes() {
    final all = Set<AggregatedItem>.identity()
      ..addAll(_moment?.items ?? const []);
    final gone = [
      for (final song in _momentNodes.keys)
        if (!all.contains(song)) song,
    ];
    if (gone.isEmpty) return;
    final nodes = [for (final song in gone) _momentNodes.remove(song)!];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in nodes) {
        node.dispose();
      }
    });
  }

  /// Kos TV: the moment's song the remote is on (or comes back to, from
  /// its menu) is about to leave the row («No me gusta», its artist): the
  /// remote goes to the one taking its place (or the one before it), as in
  /// «Lo que no quieres oír», before the row goes, so it isn't lost and
  /// «Deshacer»'s notice gives it back there.
  void _keepMomentFocus() {
    final rows = _momentRows;
    final at = rows.indexWhere(
      (r) => r.node.hasFocus || r.node.enclosingScope?.focusedChild == r.node,
    );
    if (at < 0) return;
    final shown = Set<AggregatedItem>.identity()
      ..addAll(_shownMoment?.items ?? const []);
    if (shown.contains(rows[at].song)) return;
    // The page's first stop moves on to the new first row by itself.
    if (!identical(rows[at].node, _momentNodes[rows[at].song])) return;
    final staying = [
      for (final (i, r) in rows.indexed)
        if (shown.contains(r.song)) (i: i, row: r),
    ];
    if (staying.isEmpty) return;
    final next = staying.where((s) => s.i > at).firstOrNull ?? staying.last;
    // The one that will be first takes the page's first stop with it.
    final firstStop = rows.first.node;
    final becomesFirst =
        identical(next, staying.first) &&
        !identical(firstStop, _momentNodes[rows.first.song]);
    (becomesFirst ? firstStop : next.row.node).requestFocus();
  }

  Future<void> _reloadFavorites() async {
    try {
      _favorites = await _favoriteSongs();
      _refresh();
    } catch (_) {}
  }

  /// Kos TV: «Tus favoritas»: the home server's ♥ with those of songs that
  /// aren't at home (the server plugin's), by date.
  Future<List<AggregatedItem>> _favoriteSongs() async {
    final client = GetIt.instance.isRegistered<MediaServerClient>()
        ? GetIt.instance<MediaServerClient>()
        : null;
    final store = KostvMusicAwayStore.instance;
    final away = client == null
        ? Future.value(const <KostvAwayFavorite>[])
        : store
              .load(client)
              .timeout(const Duration(seconds: 4))
              .catchError((Object _) => store.favoritesOf(client));
    final home = await _music.favoriteSongs();
    if (client == null) return home;
    return kostvMergeFavorites(
      home,
      await away,
      serverId: client.baseUrl,
      hideExplicit: kostvAwayHidesExplicit(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _refreshing?.cancel();
    _momentTurn?.cancel();
    _lifecycle?.dispose();
    KostvMusicDislikesStore.instance.removeListener(_dislikesChanged);
    KostvMusicCatalog.instance.removeListener(_refresh);
    kostvPrefetchCancel();
    for (final node in _momentNodes.values) {
      node.dispose();
    }
    kostvMusicFavoritesChanged.removeListener(_reloadFavorites);
    _listening?.musicRequestsRevision.removeListener(_onMusicRequested);
    kostvReleaseBrowserMenu();
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _firstStop.dispose();
    for (final node in [
      ..._tabNodes.values,
      ..._sortNodes.values,
      ..._chartNodes.values,
      _topPlay,
      _firstSong,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  /// The requests service when the person may use it; [denied] when it
  /// said they may not (not when it couldn't be asked: then what it said
  /// last time stays on the page).
  Future<({StremfinService? service, bool denied})> _allowedStremfin() async {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) {
      return (service: null, denied: true);
    }
    final stremfin = getIt<StremfinService>();
    if (!stremfin.isConfigured) return (service: null, denied: true);
    if (!stremfin.isAllowed) {
      try {
        await stremfin.refreshAccess();
      } catch (_) {
        return (service: null, denied: false);
      }
    }
    if (stremfin.isAllowed) return (service: stremfin, denied: false);
    // Kos TV: held back only because the service didn't answer (no network,
    // switched off): it didn't say no, so what it said last time stays.
    return (service: null, denied: !stremfin.accessUnanswered);
  }

  /// Whether the service lets the person in, for a search typed before the
  /// page knew.
  late final Future<StremfinService?> _stremfinReady = _load();

  /// The requests service as it is, without asking whether the person may
  /// use it: for what it answered last time, which needs no call.
  StremfinService? _rememberedStremfin() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) return null;
    final stremfin = getIt<StremfinService>();
    return stremfin.isConfigured ? stremfin : null;
  }

  /// The parts that came from the service just now: what it answered last
  /// time no longer replaces them.
  final _fresh = <String>{};

  late final Future<KostvMusicTaste> _tasteLoad = kostvLoadMusicTaste(
    _plugin,
    _client,
    fallback: _music.taste,
    dislikes: () => KostvMusicDislikesStore.instance.load(_client),
  );

  /// Loads every part on its own, each shown as soon as it is there: first
  /// what the service answered last time, kept on the device (the page opens
  /// at once with it), then its answer now, which replaces it.
  Future<StremfinService?> _load() async {
    final remembered = _rememberedStremfin();
    if (remembered != null) {
      unawaited(_loadStremfin(remembered, remembered: true));
    }
    Future<void> part(Future<void> Function() load) async {
      try {
        await load();
      } catch (e) {
        _failed = true;
        debugPrint('[Music] A part failed: $e');
      }
      _refresh();
    }

    final home = Future.wait([
      part(() async => _recent = await _music.recentAlbums()),
      part(() async => _favorites = await _favoriteSongs()),
      part(_loadPlaylists),
      part(() async => _newAtHome = await _music.newAlbums()),
      part(() async {
        _taste = await _tasteLoad;
        _tasteKnown = true;
      }),
      _loadPluginRows(),
    ]);
    final access = await _allowedStremfin();
    final stremfin = _stremfin = access.service;
    if (access.denied && mounted) {
      // Not allowed any more: nothing of what it said last time stays.
      setState(_forgetStremfin);
    } else if (stremfin == null) {
      // Kos TV: it couldn't be asked: that is a failure, not an empty page.
      _failed = true;
    }
    if (stremfin != null && mounted) {
      // Kos TV: an album asked for from a page over this one: the service's
      // parts are read again, so it shows as asked for here too.
      stremfin.musicRequestsRevision.addListener(_onMusicRequested);
      _listening = stremfin;
    }
    unawaited(() async {
      await Future.wait([
        home,
        if (stremfin != null) _loadStremfin(stremfin, remembered: false),
      ]);
      if (mounted) setState(() => _loading = false);
    }());
    return stremfin;
  }

  StremfinService? _listening;

  void _onMusicRequested() {
    final stremfin = _stremfin;
    if (!mounted || stremfin == null) return;
    unawaited(_loadStremfin(stremfin, remembered: false));
  }

  void _forgetStremfin() {
    _stremfinGone = true;
    _topSongs = _latino = _topAlbums = _genreChart = null;
    _mexico = _unitedStates = null;
    _forYou = null;
    _moreOf = null;
    _discovery = null;
    _yourNews = _requested = _releases = const [];
  }

  // Kos TV: the notes the plugin's rows are kept under on the device, with
  // the requests service's answers.
  static const _mixesNote = 'daily-mixes';
  static const _momentNote = 'moment';
  static const _discoveryNote = 'discovery';

  KostvMusicPlugin get _plugin => KostvMusicPlugin.instance;

  /// Kos TV: who the page is loading for. The server's client is the same
  /// for everyone on it (its user and token change under it when the person
  /// switches), so an answer that lands after a switch is dropped.
  ({String? user, String? token}) _whoNow() =>
      (user: _client.userId, token: _client.accessToken);

  /// Whether the page is still there and still for [who].
  bool _stillFor(({String? user, String? token}) who) =>
      mounted && _whoNow() == who;

  /// Kos TV: the daily mixes and the mix of the time of day, from the
  /// server plugin: first what was kept on the device last time (only
  /// today's mixes, only this time of day's mix), then its answer now,
  /// which replaces it. Without the plugin's routes the page stays as
  /// before («Tus mezclas»); when the plugin fails, what is shown stays.
  Future<void> _loadPluginRows() async {
    final client = _client;
    final who = _whoNow();
    final kept = _rememberedStremfin();
    if (kept != null) {
      unawaited(() async {
        try {
          final now = DateTime.now();
          final mixes = kostvKeptMixes(
            await kept.rememberedMusicNote(_mixesNote),
            client.baseUrl,
            now: now,
          );
          final moment = KostvMusicMoment.fromJson(
            await kept.rememberedMusicNote(_momentNote),
            client.baseUrl,
          );
          if (!_stillFor(who)) return;
          if (mixes != null && !_fresh.contains(_mixesNote)) {
            _dailyMixes = mixes;
          }
          if (moment != null && !_fresh.contains(_momentNote)) {
            // Another time of day's mix isn't this one; it only keeps its
            // place.
            if (moment.slot == kostvMusicSlotAt(now)) {
              _moment = moment;
            } else if (!_momentLanded) {
              _momentHeld = moment.shows;
            }
          }
          _refresh();
        } catch (_) {}
      }());
    }
    await Future.wait([
      () async {
        final answer = await _plugin.mixes(client);
        if (!_stillFor(who)) return;
        // Not answered: what is shown (and kept) stays.
        if (answer.failed) return;
        _fresh.add(_mixesNote);
        final mixes = answer.value;
        _dailyMixes = mixes;
        // Without the route, nothing kept shows next time either.
        kept?.keepMusicNote(
          _mixesNote,
          (mixes ?? const KostvDailyMixes()).toJson(),
        );
        _refresh();
      }(),
      _loadMoment(),
    ]);
  }

  /// Kos TV: the mix of the time of day, now. Asked again when the page is
  /// still open as another time of day starts ([_checkMomentSlot]).
  Future<void> _loadMoment() async {
    final client = _client;
    final who = _whoNow();
    final kept = _rememberedStremfin();
    final slot = kostvMusicSlotAt(DateTime.now());
    _momentAskedFor = slot;
    _scheduleMomentTurn();
    final answer = await _plugin.moment(client);
    if (!_stillFor(who)) return;
    _momentLanded = true;
    _momentHeld = false;
    if (answer.failed) {
      // What is shown stays; asked again at the next turn or return.
      _momentFailed = true;
      _refresh();
      return;
    }
    _momentFailed = false;
    _fresh.add(_momentNote);
    final moment = answer.value;
    _moment = moment;
    kept?.keepMusicNote(
      _momentNote,
      (moment ?? KostvMusicMoment(slot: slot, ready: false)).toJson(),
    );
    _refresh();
  }

  /// Kos TV: the next start of a time of day (6:00, 12:00, 20:00), a minute
  /// after it so the plugin's clock is there too.
  void _scheduleMomentTurn() {
    _momentTurn?.cancel();
    final now = DateTime.now();
    final starts = [
      for (final day in [0, 1])
        for (final hour in [6, 12, 20])
          DateTime(now.year, now.month, now.day + day, hour, 1),
    ];
    final next = starts.firstWhere((at) => at.isAfter(now));
    _momentTurn = Timer(next.difference(now), _checkMomentSlot);
  }

  /// Kos TV: the page is open (or back) in another time of day than the
  /// one its mix was asked for: that one's.
  void _checkMomentSlot() {
    if (!mounted || _momentAskedFor == null) return;
    if (!_momentFailed && kostvMusicSlotAt(DateTime.now()) == _momentAskedFor) {
      _scheduleMomentTurn();
      return;
    }
    unawaited(_loadMoment());
  }

  /// Kos TV: the week's discovery: the songs the plugin kept for this week
  /// or, the first time this week, those of the requests service's radio of
  /// the plugin's artists, topped up with its recommendations (only these
  /// with a service from before the radio; [kostvLoadWeeklyDiscovery]),
  /// without what the person isn't shown. Gives what
  /// applies it to the page: no songs when the plugin has none to give (the
  /// page then shows «Canciones para ti»). Throws when the plugin or the
  /// service failed: what is shown stays.
  Future<void Function()> _weeklyDiscovery(StremfinService stremfin) async {
    final who = _whoNow();
    final found = await kostvLoadWeeklyDiscovery(
      _plugin,
      _client,
      recommend: stremfin.musicRecommendations,
      radio: stremfin.musicRadio,
      clean: stremfin.cleanMusicSongs,
      wanted: () => mounted,
      onWeek: (week) {
        // Another week's list: it goes, even if the service fails now.
        if (_discoveryWeek == null || _discoveryWeek == week) return;
        stremfin.keepMusicNote(_discoveryNote, kostvDiscoveryNote(week, []));
        _discoveryWeek = null;
        _discovery = null;
        _refresh();
      },
    );
    if (found == null || !_stillFor(who)) return () {};
    final songs = found.songs;
    // Kept as it is now: with none, nothing old shows next time.
    stremfin.keepMusicNote(
      _discoveryNote,
      kostvDiscoveryNote(found.week, songs ?? const []),
    );
    return () {
      _discovery = songs;
      _discoveryWeek = found.week;
    };
  }

  /// Kos TV: what was kept of the week's discovery on the device, only when
  /// it is this week's, without what the person isn't shown now.
  Future<List<StremfinSong>?> _keptDiscovery(StremfinService stremfin) async {
    final kept = kostvKeptDiscovery(
      await stremfin.rememberedMusicNote(_discoveryNote),
      now: DateTime.now(),
    );
    return kept == null ? null : stremfin.cleanMusicSongs(kept);
  }

  /// The service's parts, now or as it answered last time ([remembered]).
  /// Kos TV: [only] those named (a list of «Listas de éxitos» picked).
  Future<void> _loadStremfin(
    StremfinService stremfin, {
    required bool remembered,
    Set<String>? only,
  }) async {
    Future<void> part(
      String name,
      Future<void Function()> Function() load,
    ) async {
      try {
        final apply = await load();
        if (remembered) {
          if (_fresh.contains(name) || _stremfinGone) return;
        } else {
          _fresh.add(name);
          _partFailed.remove(name);
        }
        if (!mounted) return;
        apply();
        _refresh();
      } catch (e) {
        if (!remembered) {
          _failed = true;
          _partFailed.add(name);
          debugPrint('[Music] $name failed: $e');
          _refresh();
        }
      }
    }

    // Kos TV: a part asked now: all of them (but the lists of «Listas de
    // éxitos» not picked yet, of which only what was kept is read), or
    // only those of [only].
    bool wants(String name) {
      if (only != null) return only.contains(name);
      if (remembered || !_lazyCharts.containsValue(name)) return true;
      return _chartsAsked.contains(name);
    }

    Future<StremfinChartPage> chart(String id, {String? country}) =>
        stremfin.musicChart(id, country: country, remembered: remembered);

    await Future.wait([
      if (wants('top'))
        part('top', () async {
          final page = await chart('top-songs');
          return () => _topSongs = page;
        }),
      if (wants('latino'))
        part('latino', () async {
          final page = await chart('latino-songs');
          return () => _latino = page;
        }),
      if (wants('albums'))
        part('albums', () async {
          final page = await chart('top-albums');
          return () => _topAlbums = page;
        }),
      if (wants('requested'))
        part('requested', () async {
          final found = await stremfin.musicRequested(remembered: remembered);
          return () => _requested = found;
        }),
      if (wants('mexico'))
        part('mexico', () async {
          final page = await chart('top-songs', country: 'MX');
          return () => _mexico = page;
        }),
      if (wants('usa'))
        part('usa', () async {
          final page = await chart('top-songs', country: 'US');
          return () => _unitedStates = page;
        }),
      if (wants('releases'))
        part('releases', () async {
          final found = await stremfin.musicReleases(remembered: remembered);
          return () => _releases = found;
        }),
      if (wants(_discoveryNote))
        part(_discoveryNote, () async {
          if (!remembered) return _weeklyDiscovery(stremfin);
          final found = await _keptDiscovery(stremfin);
          if (found == null) return () {};
          return () {
            _discovery = found;
            _discoveryWeek = kostvIsoWeek(DateTime.now());
          };
        }),
      if (only == null)
        () async {
          // What was asked last time, so the rows that go with the person's
          // taste don't wait for it to be worked out again; now, the real one.
          final who = _whoNow();
          KostvMusicTaste? taste;
          // Kos TV: whether the taste now is really known (it didn't fail).
          var known = true;
          if (remembered) {
            taste = KostvMusicTaste.fromJson(
              await stremfin.rememberedMusicNote('taste'),
            );
          } else {
            try {
              taste = await _tasteLoad;
            } catch (_) {
              taste = const KostvMusicTaste();
              known = false;
            }
          }
          // Kos TV: not kept for whoever the session is now, if it changed.
          if (taste == null || !_stillFor(who)) return;
          if (!remembered) stremfin.keepMusicNote('taste', taste.toJson());
          await _loadForTaste(stremfin, taste, part, remembered, known: known);
        }(),
    ]);
  }

  /// What depends on the person's taste: the chart of their genre, more of
  /// the artist they listen to most, «Para ti» and their artists' news.
  Future<void> _loadForTaste(
    StremfinService stremfin,
    KostvMusicTaste taste,
    Future<void> Function(String, Future<void Function()> Function()) part,
    bool remembered, {
    bool known = true,
  }) async {
    final genre = taste.chartGenre;
    final artist = taste.artists.firstOrNull;
    final artists = [for (final a in taste.artists.take(6)) a.name];
    // Kos TV: with the person's taste now really known, a part that no
    // longer goes with it goes, rather than what was kept last time
    // staying for good (another genre, no artist any more). If it couldn't
    // be read, what was kept stays.
    final settle = !remembered && known;
    void drop(String name, void Function() clear) {
      _fresh.add(name);
      if (!mounted) return;
      clear();
      _refresh();
    }

    if (settle) {
      if (genre == null || genre == 'latino') {
        drop('genre', () => _genreChart = null);
      }
      if (artist == null) drop('more-of', () => _moreOf = null);
      if (artists.isEmpty) {
        drop('for-you', () => _forYou = null);
        drop('your-news', () => _yourNews = const []);
      }
    }
    await Future.wait([
      if (genre != null && genre != 'latino')
        part('genre', () async {
          final page = await stremfin.musicChart(
            '$genre-songs',
            remembered: remembered,
          );
          return () => _genreChart = page;
        }),
      if (artist != null)
        part('more-of', () async {
          final found = await stremfin.musicSearch(
            artist.name,
            keep: true,
            remembered: remembered,
          );
          final match = found.artists.firstOrNull;
          if (match == null) return () => _moreOf = null;
          final detail = await stremfin.musicArtist(
            match.deezerId,
            keep: true,
            remembered: remembered,
          );
          return () => _moreOf = detail.albums.isEmpty
              ? null
              : (name: detail.artist.name, albums: detail.albums);
        }),
      // «Para ti»: what goes with the artists and genres the person listens
      // to most, and then what is new of those artists.
      if (artists.isNotEmpty)
        () async {
          final genres = <String>{
            for (final g in taste.genres) ?kostvChartGenreOf(g),
          }.take(3).toList();
          StremfinRecommendations? found;
          await part('for-you', () async {
            final answer = await stremfin.musicRecommendations(
              artists,
              genres: genres,
              remembered: remembered,
            );
            found = answer;
            return () => _forYou = answer;
          });
          final ids = <String>[
            for (final seed
                in found?.seeds ?? const <({String name, String? deezerId})>[])
              ?seed.deezerId,
          ];
          if (ids.isEmpty) {
            // «Para ti» answered with none of their artists: no news.
            if (settle && found != null) {
              drop('your-news', () => _yourNews = const []);
            }
            return;
          }
          await part('your-news', () async {
            final news = await stremfin.musicArtistReleases(
              ids,
              remembered: remembered,
            );
            return () => _yourNews = news;
          });
        }(),
    ]);
  }

  // ---------------------------------------------------------------- search

  void _onQuery() {
    final query = _search.text.trim();
    // Typed and taken back before it ran: nothing is searched.
    _debounce?.cancel();
    if (query == _query) return;
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      // Kos TV: a search from scratch shows everything again.
      if (query.isEmpty) _filter = KostvMusicFilter.all;
      _query = query;
      _atHome = null;
      _toAsk = null;
      _searching = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    // Kos TV: what is at home is searched at once; only «Para pedir» waits
    // for the page to know whether the service lets the person in.
    final atHome = _music
        .search(query)
        .then((found) {
          if (mounted && _query == query) setState(() => _atHome = found);
        })
        .catchError((Object _) {
          if (mounted && _query == query) {
            setState(() => _atHome = const KostvMusicAtHome());
          }
        });
    Future<void> toAsk() async {
      // Typed before the page knew whether the service lets the person in.
      final stremfin = _stremfin ?? await _stremfinReady;
      if (stremfin == null || !mounted || _query != query) return;
      await stremfin
          .musicSearch(query)
          .then((found) {
            if (mounted && _query == query) setState(() => _toAsk = found);
          })
          .catchError((Object _) {});
    }

    await Future.wait([atHome, toAsk()]);
    if (mounted && _query == query) setState(() => _searching = false);
  }

  // ----------------------------------------------------------------- moves

  void _toMenu() => NavigationLayout.focusNavbarNotifier.value?.call();

  /// Kos TV: the first stop of what is under the header, if something has
  /// it now; otherwise the nearest thing down from [node].
  void _toFirstStop(FocusNode? node) {
    if (_firstStopShown && _firstStop.context?.mounted == true) {
      _firstStop.requestFocus();
    } else {
      node?.focusInDirection(TraversalDirection.down);
    }
  }

  /// Kos TV: the remote to the tab shown, with the page at its top.
  void _toTabs() {
    _tabNodes[_tab]!.requestFocus();
    _scrollToTop();
  }

  void _scrollToTop() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    unawaited(
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Kos TV: a tab picked (OK, a tap or a click).
  void _selectTab(KostvMusicTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if ((tab == KostvMusicTab.artists || tab == KostvMusicTab.albums) &&
        (_libraryAlbums == null || _libraryFailed)) {
      unawaited(_loadLibrary());
    }
    if (_scroll.hasClients && _scroll.offset > 0) _scroll.jumpTo(0);
  }

  /// Kos TV: the arrows on a tab: up (or right from the last one) to the
  /// search, down to what the tab shows.
  KeyEventResult _onTabKey(KostvMusicTab tab, KeyEvent event) {
    final key = event.logicalKey;
    final searchShown = _searchFocus.context?.mounted == true;
    if (key.isUpKey) {
      if (searchShown) {
        _searchFocus.requestFocus();
      } else {
        _toMenu();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        tab == KostvMusicTab.values.last &&
        searchShown) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      // Kos TV: in «Artistas» and «Álbumes», the order picked first.
      final sort = _sortNodes[_byName]!;
      if ((_tab == KostvMusicTab.artists || _tab == KostvMusicTab.albums) &&
          sort.context?.mounted == true) {
        sort.requestFocus();
      } else {
        _toFirstStop(_tabNodes[tab]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Kos TV: the albums and artists at home, and what was played lately,
  /// for the «Artistas» and «Álbumes» tabs.
  Future<void> _loadLibrary() async {
    if (_libraryLoading) return;
    final who = _whoNow();
    setState(() {
      _libraryLoading = true;
      _libraryFailed = false;
    });
    try {
      final found = await Future.wait<Object>([
        _music.albumsPage(),
        _music.artistsPage(),
        _music.recentAlbums(max: 40),
        _music.recentArtistIds(),
      ]);
      final recentArtistIds = found[3] as List<String>;
      final recentArtists = await _music.artistsById(recentArtistIds);
      if (!_stillFor(who)) return;
      final albums = found[0] as KostvMusicLibraryPage;
      final artists = found[1] as KostvMusicLibraryPage;
      _libraryAlbums = albums.items;
      _albumsMore = albums.more;
      _libraryArtists = artists.items;
      _artistsMore = artists.more;
      _recentAlbums = found[2] as List<AggregatedItem>;
      _recentAlbumIds = [for (final album in _recentAlbums) album.id];
      _recentArtists = recentArtists;
      _recentArtistIds = recentArtistIds;
    } catch (e) {
      debugPrint('[Music] The library failed: $e');
      _libraryFailed = true;
    } finally {
      _libraryLoading = false;
      if (mounted) setState(() {});
    }
  }

  /// Kos TV: the next page of the «Artistas» ([artists]) or «Álbumes» tab,
  /// when the grid comes near the end of what it has. A page that fails is
  /// asked for again the next time.
  Future<void> _loadMoreLibrary({required bool artists}) async {
    final have = artists ? _libraryArtists : _libraryAlbums;
    if (have == null) return;
    if (artists
        ? (!_artistsMore || _artistsPaging)
        : (!_albumsMore || _albumsPaging)) {
      return;
    }
    final who = _whoNow();
    if (artists) {
      _artistsPaging = true;
    } else {
      _albumsPaging = true;
    }
    try {
      final page = artists
          ? await _music.artistsPage(start: have.length)
          : await _music.albumsPage(start: have.length);
      if (!_stillFor(who)) return;
      final seen = {for (final item in have) item.id};
      final more = [
        ...have,
        for (final item in page.items)
          if (seen.add(item.id)) item,
      ];
      setState(() {
        if (artists) {
          _libraryArtists = more;
          _artistsMore = page.more;
        } else {
          _libraryAlbums = more;
          _albumsMore = page.more;
        }
      });
    } catch (e) {
      debugPrint('[Music] The next page of the library failed: $e');
    } finally {
      if (artists) {
        _artistsPaging = false;
      } else {
        _albumsPaging = false;
      }
    }
  }

  /// Kos TV: the person's playlists, for «Tus listas» (and its shelf); a
  /// failure is told as one, not as «no tienes listas».
  Future<void> _loadPlaylists() async {
    try {
      _playlists = await _music.playlists(limit: 200);
      _playlistsFailed = false;
    } catch (_) {
      _playlistsFailed = true;
      rethrow;
    }
  }

  /// Kos TV: «Reintentar» on «Tus listas».
  Future<void> _retryPlaylists() async {
    final who = _whoNow();
    try {
      await _loadPlaylists();
    } catch (e) {
      debugPrint('[Music] The playlists failed again: $e');
    }
    if (_stillFor(who)) _refresh();
  }

  /// Kos TV: «Nueva lista»: asks its name, makes it and shows it among the
  /// person's playlists.
  Future<void> _newPlaylist() => kostvMusicOnce(() async {
    final l10n = AppLocalizations.of(context);
    final id = await showKostvNewPlaylist(context, _client);
    if (id == null || !mounted) return;
    kostvMusicSay(context, l10n.kostvMusicListMade);
    // Kos TV: if it can't be read again, «Tus listas» says so and offers
    // «Reintentar» (the list was made all the same).
    await _retryPlaylists();
  });

  /// Kos TV: the phone's search button: the field, ready to type.
  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  /// Kos TV: the phone's ✕: the search goes, and the tabs come back.
  void _closeSearch() {
    _debounce?.cancel();
    _search.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchOpen = false;
      _query = '';
      _atHome = null;
      _toAsk = null;
      _searching = false;
      _filter = KostvMusicFilter.all;
    });
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey.isUpKey) {
      _toMenu();
      return KeyEventResult.handled;
    }
    if (event.logicalKey.isDownKey) {
      // Kos TV: with nothing typed, the tabs under the title; otherwise the
      // first stop of the results.
      if (_query.isEmpty && !KostvMusicSizes.phone) {
        _toTabs();
      } else {
        _toFirstStop(node);
      }
      return KeyEventResult.handled;
    }
    // Kos TV: on the TV, left from the search (at the title's right) goes
    // to the tabs.
    if (PlatformDetection.isTV &&
        _query.isEmpty &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _toTabs();
      return KeyEventResult.handled;
    }
    if (PlatformDetection.isTV &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select)) {
      _searchTvField.currentState?.openKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Kos TV: up from the first line of a tab: its tabs.
  KeyEventResult _upToTabs(KeyEvent event) {
    if (event.logicalKey.isUpKey) {
      _toTabs();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Up from the first line of the page: the search.
  KeyEventResult _upToSearch(KeyEvent event) {
    if (event.logicalKey.isUpKey) {
      _searchFocus.requestFocus();
      // The search is at the very top: the page goes up to it.
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------- opening

  MediaServerClient get _client => GetIt.instance<MediaServerClient>();

  Future<void> _playMix(String artistId) => kostvMusicOnce(() async {
    final songs = await _music
        .mix(artistId)
        .catchError((Object _) => <AggregatedItem>[]);
    if (!mounted || songs.isEmpty) return;
    // Kos TV: no song of it was picked: it doesn't start with one the
    // person doesn't want to hear.
    await playMusicTracks(
      context,
      songs,
      source: KostvMusicSource.radio,
      picked: false,
    );
  });

  /// Kos TV: a daily mix's menu: play it, next or at the end of the queue.
  Future<void> _dailyMixMenu(
    KostvDailyMix mix,
    String title,
  ) => kostvMusicOnce(() async {
    final l10n = AppLocalizations.of(context);
    final choice = await showKostvMusicMenu<int>(
      context,
      title: title,
      subtitle: _mixSubtitle(l10n, mix),
      entries: [
        KostvMenuEntry(0, Icons.play_arrow_rounded, l10n.play),
        KostvMenuEntry(1, Icons.playlist_play_rounded, l10n.kostvMusicPlayNext),
        KostvMenuEntry(2, Icons.queue_music_rounded, l10n.kostvMusicPlayLast),
      ],
    );
    if (choice == null || !mounted) return;
    final source = KostvMusicSource.mix(mix.id);
    // Kos TV: with «Toda la música», its songs that aren't at home too.
    final items = await _mixItems(mix);
    if (!mounted) return;
    // Music sounding (an audiobook's queue isn't one to add songs to).
    final musicPlaying = KostvNowPlaying.instance.item?.type == 'Audio';
    if (choice == 0 || !musicPlaying) {
      await playMusicTracks(context, items, source: source, picked: false);
      return;
    }
    final queue = GetIt.instance<PlaybackManager>().queueService;
    kostvTellMusicSource(() => _client, source, items);
    if (choice == 1) {
      // Right after the song sounding, in the mix's order, as one change.
      queue.insertAllNext(items);
      kostvMusicSay(context, l10n.kostvMusicMixAddedNext);
    } else {
      queue.addItems(items);
      kostvMusicSay(context, l10n.kostvMusicMixAddedLast);
    }
  });

  /// Kos TV: a daily mix's songs to play: with «Toda la música», about a
  /// quarter that aren't at home spread through it (the same all day), with
  /// the short wait while they are picked the first time.
  Future<List<AggregatedItem>> _mixItems(KostvDailyMix mix) => _withExtras(
    mixId: mix.id,
    items: mix.items,
    because: mix.because,
    day: _dailyMixes?.day,
  );

  Future<List<AggregatedItem>> _withExtras({
    required String mixId,
    required List<AggregatedItem> items,
    required List<String> because,
    String? day,
  }) async {
    if (!kostvMusicCatalogAll() || because.isEmpty) return items;
    final closeLoading = showMusicLoading(context);
    try {
      return await kostvMixQueue(
        mixId: mixId,
        items: items,
        because: because,
        day: day,
      );
    } finally {
      closeLoading();
    }
  }

  /// Kos TV: the moment's mix from its song [index], with its songs that
  /// aren't at home in «Toda la música» (from the same song on).
  Future<void> _playMoment(KostvMusicMoment moment, int index, String source) =>
      kostvMusicOnce(() async {
        final songs = moment.items;
        final items = await _withExtras(
          mixId: source,
          items: songs,
          because: moment.because,
          // Kos TV: the night's mix keeps its songs past midnight.
          day: kostvMomentDay(),
        );
        if (!mounted) return;
        final picked = songs[index.clamp(0, songs.length - 1)];
        final start = items.indexWhere((s) => identical(s, picked));
        await playMusicTracks(
          context,
          items,
          startIndex: start < 0 ? index : start,
          source: source,
        );
      });

  /// Kos TV: [songs] of a list played as one queue from [index], or all of
  /// it shuffled («Toda la música»).
  /// Kos TV: not [picked] from the header's «Reproducir»: no song of it was
  /// chosen, so it doesn't start with one the person doesn't want to hear.
  void _playList(
    List<StremfinSong> songs,
    String source, {
    int index = 0,
    bool shuffle = false,
    bool picked = true,
  }) => unawaited(
    playKostvSongList(
      context,
      songs,
      index: index,
      source: source,
      shuffle: shuffle,
      picked: picked && !shuffle,
    ),
  );

  /// Kos TV: a song the remote's focus or the mouse rests on: asked for in
  /// advance after a couple of seconds, when it would sound through the
  /// service («Toda la música»).
  void Function(bool)? _restOn(StremfinSong song) {
    if (!kostvMusicCatalogAll() || song.atHome || !kostvSongPlayable(song)) {
      return null;
    }
    return (resting) =>
        resting ? kostvPrefetchSoon(song) : kostvPrefetchCancel();
  }

  // ------------------------------------------------------------------ build

  /// Sections arrive while the person is already moving down the page: one
  /// that lands above moves what they are on further down, so it is brought
  /// back into view, only as far as needed.
  void _keepFocusInView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchFocus.hasFocus) return;
      // With a mouse or touch the page stays where the person left it.
      if (!InputModeTracker.showFocusVisuals(context, true)) return;
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null || !focused.mounted) return;
      if (focused.findAncestorStateOfType<_KostvMusicScreenState>() != this) {
        return;
      }
      kostvMusicRevealVertically(focused, null, true);
    });
  }

  /// Kos TV: the page's margins: the design's (64 on the TV, 56 on the
  /// web) with the menu at the top; with it at the side, past its rail.
  EdgeInsets _insets(BuildContext context) {
    final base = calendarChromeInsets(context);
    if (KostvMusicSizes.phone) return base;
    final side = base.left > 60;
    return EdgeInsets.only(
      top: base.top,
      left: side ? base.left + 24 : KostvMusicTokens.margin,
      right: side ? base.right : KostvMusicTokens.margin,
    );
  }

  @override
  Widget build(BuildContext context) {
    _keepFocusInView();
    _firstStopShown = false;
    final insets = _insets(context);
    final phone = KostvMusicSizes.phone;
    final bottom =
        MediaQuery.paddingOf(context).bottom +
        (phone && NavigationLayout.usesBottomNavbar ? 110 : 40);
    final searching = _query.isNotEmpty;
    final List<Widget> content;
    if (searching) {
      content = _results(context, insets);
    } else {
      content = switch (_tab) {
        KostvMusicTab.forYou => _sections(context, insets),
        KostvMusicTab.lists => _listsTab(context, insets),
        KostvMusicTab.artists => _libraryTab(context, insets, artists: true),
        KostvMusicTab.albums => _libraryTab(context, insets, artists: false),
      };
    }
    return PopScope(
      // Kos TV: on the phone, back with the search open closes it first.
      canPop: !(phone && _searchOpen),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && phone && _searchOpen) _closeSearch();
      },
      child: Scaffold(
        backgroundColor: KostvMusicTokens.background,
        body: NavigationLayout(
          activeRoute: Destinations.kostvMusic,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Kos TV: a faint glow of the brand's violet from the top.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.7, -1.1),
                    radius: 1.2,
                    colors: [Color(0x388F6BFF), Color(0x008F6BFF)],
                  ),
                ),
              ),
              CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      insets.left,
                      insets.top + (phone ? 4 : 10),
                      insets.right,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(child: _header(context)),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: phone ? 18 : 26)),
                  ...content,
                  SliverToBoxAdapter(child: SizedBox(height: bottom)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kos TV: the page's top: «Música» with the search at its right (a round
  /// button on the phone) and the tabs under it; while searching, only the
  /// search (and, on the phone and the web, the filters).
  Widget _header(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    final tv = PlatformDetection.isTV;
    final searching = _query.isNotEmpty || (phone && _searchOpen);
    final field = KeyedSubtree(
      key: _searchBox,
      // Only the field follows its focus (not the whole page).
      child: ListenableBuilder(
        listenable: _searchFocus,
        builder: (context, _) => _searchField(context),
      ),
    );
    final filters = !tv && _query.isNotEmpty
        ? Padding(
            padding: EdgeInsets.only(top: phone ? 12 : 16),
            child: KostvMusicChoiceRow<KostvMusicFilter>(
              values: KostvMusicFilter.values,
              selected: _filter,
              solid: true,
              label: (f) => kostvMusicFilterLabel(l10n, f),
              onSelect: (f) => setState(() => _filter = f),
            ),
          )
        : null;
    if (searching) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phone || tv)
            field
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: field,
            ),
          ?filters,
        ],
      );
    }
    final title = Text(
      l10n.kostvMusic,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: KostvMusicType.title(phone ? 34 : KostvMusicTokens.pageTitle)
          .copyWith(letterSpacing: -0.5),
    );
    final tabs = KostvMusicChoiceRow<KostvMusicTab>(
      values: KostvMusicTab.values,
      selected: _tab,
      nodes: _tabNodes,
      size: tv ? KostvPillSize.m : KostvPillSize.s,
      label: (tab) => kostvMusicTabLabel(l10n, tab),
      onSelect: _selectTab,
      onKey: _onTabKey,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: title),
            if (phone)
              Tooltip(
                message: l10n.search,
                child: KostvMusicPressable(
                  onTap: _openSearch,
                  centerVertically: false,
                  builder: (context, lit) =>
                      KostvRoundIcon(icon: Icons.search_rounded, lit: lit),
                ),
              )
            else
              SizedBox(width: tv ? 380 : 420, child: field),
          ],
        ),
        SizedBox(height: phone ? 14 : 18),
        Row(
          children: [
            Flexible(child: tabs),
            // With the remote the songs' menu is hidden behind a long
            // press: it is said once, quietly.
            if (tv) ...[
              const SizedBox(width: 24),
              const Icon(
                Icons.touch_app_rounded,
                size: 16,
                color: KostvMusicTokens.dim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.kostvMusicMenuHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KostvMusicTokens.dim,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    final tv = PlatformDetection.isTV;
    final searching = _query.isNotEmpty;
    // Taller with the TV's or phone's own larger text.
    final grown = MediaQuery.textScalerOf(context).scale(16) - 16;
    final height =
        (phone ? 44.0 : (searching ? 50.0 : 46.0)) + (grown > 0 ? grown : 0);
    final focused = _searchFocus.hasFocus;
    // Kos TV: the design's search: a pill of glass, lighter while typing.
    final fill = KostvMusicTokens.glass(focused || searching ? 0.12 : 0.08);
    final icon = Icon(
      Icons.search_rounded,
      color: focused || searching
          ? KostvMusicTokens.ink
          : KostvMusicTokens.muted,
      size: phone ? 20 : 22,
    );
    final fontSize = phone ? 16.0 : (searching && tv ? 20.0 : 16.0);
    final textStyle = TextStyle(
      color: KostvMusicTokens.ink,
      fontSize: fontSize,
    );
    final hintStyle = TextStyle(
      color: KostvMusicTokens.muted,
      fontSize: fontSize,
    );
    if (tv) {
      return Focus(
        focusNode: _searchFocus,
        onKeyEvent: _onSearchKey,
        child: SizedBox(
          height: height,
          child: CustomTVTextField(
            key: _searchTvField,
            controller: _search,
            isFocused: focused,
            hint: l10n.kostvMusicSearchHint,
            textStyle: textStyle,
            hintStyle: hintStyle,
            prefixIcon: icon,
            filled: true,
            fillColor: fill,
            borderRadius: height / 2,
            borderColor: Colors.transparent,
            focusedBorderColor: Colors.white,
            borderWidth: 0,
            focusedBorderWidth: 3,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 4,
            ),
            popParentOnKeyboardClose: false,
          ),
        ),
      );
    }
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
    );
    // Kos TV: on the phone the ✕ closes the search (back to the tabs);
    // elsewhere it clears what was typed.
    final clear = phone
        ? IconButton(
            tooltip: l10n.kostvMusicSearchClose,
            icon: const Icon(
              Icons.close_rounded,
              color: KostvMusicTokens.muted,
              size: 20,
            ),
            onPressed: _closeSearch,
          )
        : (_search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.clear,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: KostvMusicTokens.muted,
                    size: 20,
                  ),
                  onPressed: _search.clear,
                ));
    return Focus(
      onKeyEvent: _onSearchKey,
      skipTraversal: true,
      canRequestFocus: false,
      child: SizedBox(
        height: height,
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          style: textStyle,
          cursorColor: KostvMusicTokens.ink,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.kostvMusicSearchHint,
            hintStyle: hintStyle,
            filled: true,
            fillColor: fill,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: icon,
            ),
            suffixIcon: clear,
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: const BorderSide(color: Colors.white54, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- sections

  List<Widget> _sections(BuildContext context, EdgeInsets insets) {
    final l10n = AppLocalizations.of(context);
    // The first stop (where the search field's down arrow lands) goes to the
    // first section there is, but stays where it is while the person is on
    // it: sections that arrive later above don't pull them away.
    final keep = _firstStop.hasFocus ? _firstOwner : null;
    var first = true;
    FocusNode? firstNode(String id, bool shows) {
      if (!shows) return null;
      if (keep != null && id != keep) return null;
      if (keep == null) {
        if (!first) return null;
        first = false;
        _firstOwner = id;
      }
      _firstStopShown = true;
      return _firstStop;
    }

    // Kos TV: each place of «Para ti» ([kostvForYouOrder]) and how to build
    // its sections; built in that order, so the first stop goes to the
    // first one there is.
    final quick = _keepListening(context);
    final plugin = kostvMusicPluginRows(
      mixes: _shownMixes,
      discovery: _shownDiscovery,
      moment: _shownMoment,
    );
    final forYou = _shownForYou;
    final places = <String, List<(String, Widget?)> Function()>{
      // «Sigue escuchando» at the top: the albums played lately with the
      // favourites, a mix and a playlist; the albums that don't fit stay
      // in «Escuchado hace poco», further down.
      'quick': () => [
        (
          'quick',
          _quickShelf(
            context,
            quick.picks,
            firstNode('quick', quick.picks.isNotEmpty),
          ),
        ),
      ],
      // What the plugin works out from what the person listens to replaces
      // the rows that did its job before, only when it answers. The mix of
      // the time of day first: it is about what to put on now.
      'moment': () => [
        if (plugin.moment)
          ('moment', _momentShelf(context, insets, firstNode('moment', true)))
        else if (_momentHeld)
          ('moment', _momentPlace(context, insets)),
      ],
      // The same section either way, so the page doesn't jump when the
      // daily mixes take the place of «Tus mezclas».
      'mixes': () => [
        (
          'mixes',
          plugin.dailyMixes
              ? _dailyMixShelf(context, insets, firstNode('mixes', true))
              : _mixShelf(
                  context,
                  insets,
                  firstNode('mixes', _taste.artists.isNotEmpty),
                ),
        ),
      ],
      // Kos TV: «Listas de éxitos»: the charts in one section, a pill for
      // each list.
      'charts': () => [('charts', _chartsSection(context, insets, firstNode))],
      // «Porque escuchas a …»: a row for each of the person's artists.
      'because': () => [
        if (forYou != null)
          for (final row in kostvBecauseRows(
            forYou.albums,
            (album) => album.reason,
            [
              for (final seed in forYou.seeds) seed.name,
              for (final artist in _taste.artists) artist.name,
            ],
          ))
            (
              'foryou-reason-${row.artist ?? row.reason ?? ''}',
              _albumShelf(
                context,
                row.artist != null
                    ? l10n.kostvMusicBecauseListen(row.artist!)
                    : row.reason ?? l10n.kostvMusicForYouAlbums,
                l10n.kostvMusicForYouWhy,
                row.items,
                insets,
              ),
            ),
      ],
      'radios': () => [('radios', _radioShelf(context, insets))],
      // Kos TV: «Descubrimiento semanal» in the place of «Canciones para
      // ti» when the plugin gives it.
      'discovery': () => [
        if (plugin.discovery)
          (
            'foryou-songs',
            _chartSongs(
              context,
              null,
              l10n.kostvMusicDiscovery,
              l10n.kostvMusicDiscoveryWhy,
              insets,
              null,
              songs: _shownDiscovery,
              ranked: false,
              source: KostvMusicSource.discovery,
              fresh: true,
            ),
          ),
      ],
      'your-news': () => [
        (
          'your-news',
          _albumShelf(
            context,
            l10n.kostvMusicNewFromYours,
            l10n.kostvMusicNewFromYoursWhy,
            _shownYourNews,
            insets,
          ),
        ),
      ],
      'more-of': () => [
        if (_moreOf case final moreOf?)
          (
            'more-of',
            _albumShelf(
              context,
              l10n.kostvMusicMoreOf(moreOf.name),
              l10n.kostvMusicMoreOfWhy(moreOf.name),
              moreOf.albums,
              insets,
            ),
          ),
      ],
      'foryou-songs': () => [
        if (!plugin.discovery && forYou != null)
          (
            'foryou-songs',
            _chartSongs(
              context,
              null,
              l10n.kostvMusicForYouSongs,
              l10n.kostvMusicForYouWhy,
              insets,
              null,
              songs: forYou.songs,
              ranked: false,
              source: KostvMusicSource.other,
            ),
          ),
      ],
      'new-at-home': () => [('new-at-home', _newAtHomeShelf(context, insets))],
      'recent': () {
        final rest = _recent.skip(quick.albumsUsed).toList();
        return [
          (
            'recent',
            _recentShelf(
              context,
              rest,
              insets,
              firstNode('recent', rest.isNotEmpty),
            ),
          ),
        ];
      },
      'favorites': () => [('favorites', _favoritesShelf(context, insets))],
      'playlists': () => [('playlists', _playlistsShelf(context, insets))],
      'releases': () => [
        (
          'releases',
          _albumShelf(
            context,
            l10n.kostvMusicReleases,
            null,
            _releases,
            insets,
          ),
        ),
      ],
      'requested': () => [
        (
          'requested',
          _albumShelf(
            context,
            l10n.kostvMusicRequested,
            null,
            _requested,
            insets,
          ),
        ),
      ],
    };

    final parts = <Widget>[];
    // Each section keeps who it is as others arrive around it, so the one
    // being looked at is never rebuilt as another (and the focus with it).
    void add(String id, Widget? part) {
      if (part == null) return;
      parts
        ..add(KeyedSubtree(key: ValueKey('music-$id'), child: part))
        ..add(SizedBox(key: ValueKey('music-$id-gap'), height: 34));
    }

    // Kos TV: someone who hasn't listened to anything yet gets the charts
    // right after «Sigue escuchando», so the page isn't empty.
    final newListener = _tasteKnown && _taste.isEmpty && _recent.isEmpty;
    for (final place in kostvForYouOrder(newListener: newListener)) {
      for (final (id, part) in places[place]!()) {
        add(id, part);
      }
    }
    if (parts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(insets.left, 40, insets.right, 0),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator(
                      color: KostvMusicTokens.violet,
                    )
                  : Text(
                      _failed
                          ? l10n.kostvMusicUnavailable
                          : l10n.kostvMusicEmptyListening,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kostvMusicGrey),
                    ),
            ),
          ),
        ),
      ];
    }
    // All built, not as they scroll into sight: a section pushed down by
    // one arriving above is kept, and with it the focus the person had in
    // it (a lazy list dropped it, and the page went back to the top).
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: parts,
        ),
      ),
    ];
  }

  /// «Nuevo en casa»: the albums that arrived at home lately.
  Widget? _newAtHomeShelf(BuildContext context, EdgeInsets insets) {
    if (_newAtHome.isEmpty) return null;
    return KostvMusicShelf(
      title: AppLocalizations.of(context).kostvMusicNewAtHome,
      insets: insets,
      height: _shelfHeight(),
      children: [
        for (final album in _newAtHome)
          KostvMusicAlbumTile(
            size: KostvMusicTokens.card,
            title: album.name,
            subtitle: album.albumArtist,
            cover: kostvMusicImageOf(album),
            onTap: () => openMusicItem(context, album),
            onPlay: () => unawaited(playKostvHomeAlbum(context, album)),
          ),
      ],
    );
  }

  /// Kos TV: «Radios de tus artistas»: a station for each of the artists
  /// the person listens to most, as «Crear emisora» makes one (without
  /// what they don't want to hear; with «Solo la de casa», only what is at
  /// home).
  Widget? _radioShelf(BuildContext context, EdgeInsets insets) {
    final artists = _taste.artists.take(6).toList();
    if (artists.isEmpty) return null;
    final l10n = AppLocalizations.of(context);
    final size = KostvMusicTokens.card;
    return KostvMusicShelf(
      title: l10n.kostvMusicArtistRadios,
      subtitle: l10n.kostvMusicArtistRadiosWhy,
      insets: insets,
      height: _shelfHeight(),
      children: [
        for (final (i, artist) in artists.indexed)
          KostvMusicAlbumTile(
            key: ValueKey('artist-radio-${artist.id}'),
            size: size,
            title: l10n.kostvMusicRadioOf(artist.name),
            art: KostvArtistRadioArt(
              name: artist.name,
              index: i,
              size: size,
              picture: _client.imageApi.getPrimaryImageUrl(
                artist.id,
                maxWidth: 400,
              ),
            ),
            onTap: () => _playArtistRadio(artist),
            onPlay: () => _playArtistRadio(artist),
          ),
      ],
    );
  }

  void _playArtistRadio(({String id, String name}) artist) => unawaited(
    kostvMusicOnce(
      () => playKostvHomeArtistStation(
        context,
        artistId: artist.id,
        name: artist.name,
      ),
    ),
  );

  /// Kos TV: the lists of «Listas de éxitos» there are, in the pills'
  /// order: the person's own first (their genre's, or Latino), then
  /// España and the rest. Those asked for only when picked are there
  /// while the service can be asked, before anything of them is known.
  List<KostvChartList> _chartLists() {
    bool songs(StremfinChartPage? page) => page?.songs.isNotEmpty ?? false;
    bool lazy(StremfinChartPage? page, bool Function(StremfinChartPage) has) =>
        page == null ? _stremfin != null : has(page);
    final latinoFirst = _firstGenre() == 'latino';
    return [
      if (latinoFirst && songs(_latino)) KostvChartList.latino,
      if (songs(_genreChart)) KostvChartList.genre,
      if (songs(_topSongs)) KostvChartList.spain,
      if (!latinoFirst && songs(_latino)) KostvChartList.latino,
      if (lazy(_mexico, (p) => p.songs.isNotEmpty)) KostvChartList.mexico,
      if (lazy(_unitedStates, (p) => p.songs.isNotEmpty)) KostvChartList.usa,
      if (lazy(_topAlbums, (p) => p.albums.isNotEmpty)) KostvChartList.albums,
    ];
  }

  /// Kos TV: the charts' genre of the genre the person listens to most.
  String? _firstGenre() {
    final genre = _taste.genres.firstOrNull;
    return genre == null ? null : kostvChartGenreOf(genre);
  }

  StremfinChartPage? _chartPage(KostvChartList list) => switch (list) {
    KostvChartList.genre => _genreChart,
    KostvChartList.spain => _topSongs,
    KostvChartList.latino => _latino,
    KostvChartList.mexico => _mexico,
    KostvChartList.usa => _unitedStates,
    KostvChartList.albums => _topAlbums,
  };

  String _chartLabel(AppLocalizations l10n, KostvChartList list) =>
      switch (list) {
        KostvChartList.genre => _genreLabel(l10n, _genreChart),
        KostvChartList.spain => l10n.kostvMusicChartSpain,
        KostvChartList.latino => l10n.kostvMusicChartLatino,
        KostvChartList.mexico => l10n.kostvMusicMexico,
        KostvChartList.usa => l10n.kostvMusicChartUsa,
        KostvChartList.albums => l10n.kostvMusicTabAlbums,
      };

  /// The name of the genre of the chart of the person's genre («Pop»).
  String _genreLabel(AppLocalizations l10n, StremfinChartPage? genre) {
    if (genre == null) return '';
    return _genreName(l10n, genre.chart.id.replaceFirst('-songs', '')) ??
        genre.chart.name.split('·').first.replaceFirst('Top ', '').trim();
  }

  /// The «why» of each list, as each top said it.
  String _chartWhy(AppLocalizations l10n, KostvChartList list) =>
      switch (list) {
        KostvChartList.spain ||
        KostvChartList.albums => l10n.kostvMusicTopSongsWhy,
        KostvChartList.genre ||
        KostvChartList.latino => l10n.kostvMusicChartSoldWhy,
        KostvChartList.mexico => l10n.kostvMusicTopCountryWhy(
          l10n.kostvMusicMexico,
        ),
        KostvChartList.usa => l10n.kostvMusicTopCountryWhy(
          l10n.kostvMusicUnitedStates,
        ),
      };

  /// Kos TV: a list of «Listas de éxitos» picked (OK, a tap or a click):
  /// one asked for only when picked is asked now (again, if it failed).
  void _pickChart(KostvChartList list) {
    if (list != _chartPick) setState(() => _chartPick = list);
    _askChart(list);
  }

  /// Kos TV: [list] asked of the service now, if it is one asked only when
  /// shown and it wasn't yet (or it failed).
  void _askChart(KostvChartList list) {
    final name = _lazyCharts[list];
    if (name == null) return;
    if (_chartsAsked.contains(name) && !_partFailed.contains(name)) return;
    _chartsAsked.add(name);
    final stremfin = _stremfin;
    if (stremfin == null) return;
    setState(() => _partFailed.remove(name));
    unawaited(_loadStremfin(stremfin, remembered: false, only: {name}));
  }

  /// Kos TV: «Listas de éxitos»: España, Latino, the chart of the person's
  /// genre, México, EE. UU. and the albums of the moment in one section,
  /// with a pill for each (the person's own picked at first): the list
  /// picked in columns of songs (or the albums in cards), with its «why»,
  /// «Reproducir» and «Aleatorio». With the remote, the pills are reached
  /// from above, OK picks one and down goes to its songs.
  Widget? _chartsSection(
    BuildContext context,
    EdgeInsets insets,
    FocusNode? Function(String id, bool shows) firstNodeOf,
  ) {
    final lists = _chartLists();
    final shown = lists.contains(_chartPick)
        ? _chartPick!
        : kostvDefaultChart(firstGenre: _firstGenre(), available: lists);
    if (shown == null) return null;
    final l10n = AppLocalizations.of(context);
    final firstNode = firstNodeOf('charts', true);
    final title = l10n.kostvMusicCharts;
    final why = _chartWhy(l10n, shown);
    final pills = lists.length < 2
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(insets.left, 2, insets.right, 14),
            child: KostvMusicChoiceRow<KostvChartList>(
              key: const ValueKey('kostvMusicCharts'),
              values: lists,
              selected: shown,
              label: (list) => _chartLabel(l10n, list),
              onSelect: _pickChart,
              nodes: {
                for (final (i, list) in lists.indexed)
                  list: i == 0 && firstNode != null
                      ? firstNode
                      : _chartNodes[list]!,
              },
              // Kos TV: up from the pills of the page's first section, the
              // tabs.
              onKey: firstNode == null ? null : (_, event) => _upToTabs(event),
            ),
          );
    final page = _chartPage(shown);
    final lazy = _lazyCharts[shown];
    // Kos TV: one asked only when picked that is shown without being picked
    // (the only lists there are): asked now.
    if (lazy != null && page == null && !_chartsAsked.contains(lazy)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askChart(shown);
      });
    }
    Widget heading = KostvMusicHeading(
      title: title,
      subtitle: why,
      padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 10),
    );
    Widget? rows;
    if (page != null && shown == KostvChartList.albums) {
      rows = _chartAlbumRow(context, page, insets);
    } else if (page != null) {
      final parts = _songColumnsParts(
        context,
        page.songs,
        title,
        why,
        insets,
        null,
        true,
        KostvMusicSource.charts,
        false,
        upToTabs: firstNode != null,
      );
      if (parts != null) {
        heading = parts.heading;
        rows = parts.rows;
      }
    }
    // Kos TV: a list picked that is still coming (or that failed, or came
    // empty): its place, with the pills to pick another.
    if (rows == null) {
      final failed = lazy == null || page != null || _partFailed.contains(lazy);
      rows = SizedBox(
        height: _songRowHeight(context, KostvMusicSizes.phone) * 4 + 8,
        child: Center(
          child: failed
              ? Text(
                  l10n.kostvMusicUnavailable,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kostvMusicGrey),
                )
              : const CircularProgressIndicator(color: KostvMusicTokens.violet),
        ),
      );
    }
    // The heading and the pills stay where they are as the list changes
    // (the remote stays on the pill picked); the list's own songs are new.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        pills ?? const SizedBox.shrink(),
        KeyedSubtree(key: ValueKey('chart-${shown.name}'), child: rows),
      ],
    );
  }

  /// «Tus favoritas»: the ♥ songs, in columns of four like the charts; a
  /// song plays them all from it.
  Widget? _favoritesShelf(BuildContext context, EdgeInsets insets) {
    final songs = _favorites;
    if (songs.isEmpty) return null;
    final l10n = AppLocalizations.of(context);
    const perColumn = 4;
    final columns = (songs.length / perColumn).ceil();
    final rowHeight = _songRowHeight(context, KostvMusicSizes.phone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KostvMusicHeading(
          title: l10n.kostvMusicFavorites,
          subtitle: l10n.kostvMusicFavoritesWhy,
          padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 10),
        ),
        SizedBox(
          height: rowHeight * perColumn + 8,
          child: FocusTraversalGroup(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: insets.left, right: insets.right),
              itemCount: columns,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (context, column) => SizedBox(
                width: kostvMusicSongColumn(context),
                child: Column(
                  children: [
                    for (
                      var i = column * perColumn;
                      i < songs.length && i < (column + 1) * perColumn;
                      i++
                    )
                      Opacity(
                        // Kos TV: one that isn't at home, with «Solo la de
                        // casa»: in grey (it doesn't sound).
                        opacity: kostvAwayPlayable(songs[i]) ? 1 : 0.45,
                        child: KostvMusicSongRow(
                          title: songs[i].name,
                          artist: [
                            ...songs[i].artists.take(2),
                            ?songs[i].album,
                          ].join(' · '),
                          artistLinks: _homeSongLinks(context, songs[i]),
                          cover: kostvMusicImageOf(songs[i]),
                          // Kos TV: one that isn't at home looks the same
                          // (with «Solo la de casa» it is greyed out).
                          atHome: true,
                          duration: songs[i].runtime?.inSeconds,
                          soundingId: songs[i].id,
                          onTap: () => _playFavorites(i),
                          onLongPress: () => unawaited(
                            showKostvMusicSongMenu(
                              context,
                              item: songs[i],
                              source: KostvMusicSource.favorites,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Kos TV: «Tus favoritas» played from its song [index] (one that isn't
  /// at home with «Solo la de casa» doesn't sound: it says so).
  void _playFavorites(int index, {bool picked = true}) => unawaited(
    kostvMusicOnce(() async {
      final songs = _favorites;
      if (songs.isEmpty) return;
      final i = index.clamp(0, songs.length - 1);
      if (picked && !kostvAwayPlayable(songs[i])) {
        kostvMusicSay(context, AppLocalizations.of(context).kostvAwayHomeOnly);
        return;
      }
      final play = kostvPlaylistToPlay(songs, startIndex: i);
      if (play.tracks.isEmpty) {
        // Kos TV: none of them sounds («Solo la de casa» and none at home):
        // said, rather than nothing happening.
        kostvAwaySayNothingToPlay(context, songs);
        return;
      }
      await playMusicTracks(
        context,
        play.tracks,
        startIndex: play.startIndex,
        source: KostvMusicSource.favorites,
        picked: picked,
      );
    }),
  );

  /// Kos TV: the height of a shelf of the design's cards with their two
  /// lines (and [extra] for a third).
  double _shelfHeight([double extra = 0]) => KostvMusicTokens.card + 64 + extra;

  /// Kos TV: the ▶ of a card of the requests service's album (see
  /// [playKostvStremfinAlbum]): at home from home, otherwise (with «Toda la
  /// música») through the service. With «Solo la de casa», only one at home
  /// has it.
  VoidCallback? _albumPlay(StremfinAlbum album) =>
      kostvStremfinAlbumPlays(album)
      ? () => unawaited(playKostvStremfinAlbum(context, album))
      : null;

  /// Kos TV: a daily mix played in its order (with «Toda la música», its
  /// songs that aren't at home too).
  void _playDailyMix(KostvDailyMix mix) => unawaited(
    kostvMusicOnce(() async {
      final items = await _mixItems(mix);
      if (!mounted) return;
      await playMusicTracks(
        context,
        items,
        source: KostvMusicSource.mix(mix.id),
        picked: false,
      );
    }),
  );

  /// Kos TV: what «Sigue escuchando» shows: the albums played lately with
  /// «Tus favoritas», the first mix and the latest playlist between them
  /// ([kostvKeepListening]); and how many albums it took.
  ({List<_Quick> picks, int albumsUsed}) _keepListening(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    final art = KostvMusicTokens.tileHeight;
    final albums = [
      for (final album in _recent)
        _Quick(
          id: 'album-${album.id}',
          title: album.name,
          subtitle: album.albumArtist == null || album.albumArtist!.isEmpty
              ? l10n.kostvMusicKindAlbum
              : l10n.kostvMusicQuickAlbum(album.albumArtist!),
          cover: kostvMusicImageOf(album),
          onTap: () => openMusicItem(context, album),
        ),
    ];
    final favorites = _favorites.isEmpty
        ? null
        : _Quick(
            id: 'favorites',
            title: l10n.kostvMusicFavorites,
            subtitle: l10n.kostvMusicQuickList(
              l10n.kostvMusicTracks(_favorites.length),
            ),
            art: KostvFavoritesArt(size: art),
            onTap: () => _playFavorites(0, picked: false),
          );
    _Quick? mix;
    final plugin = kostvMusicPluginRows(
      mixes: _shownMixes,
      discovery: _shownDiscovery,
      moment: _shownMoment,
    );
    final daily = _shownMixes?.mixes ?? const <KostvDailyMix>[];
    if (plugin.dailyMixes && daily.isNotEmpty) {
      final first = daily.first;
      final title = l10n.kostvMusicDailyMix(1);
      mix = _Quick(
        id: 'mix-${first.id}',
        title: title,
        subtitle: kostvMusicBecause(l10n, first.because) ?? first.genre,
        art: KostvMiniMixArt(
          size: art,
          index: 0,
          picture: _mixPictures(first).firstOrNull,
        ),
        onTap: () => _playDailyMix(first),
        onLongPress: () => unawaited(_dailyMixMenu(first, title)),
      );
    } else if (!plugin.dailyMixes && _taste.artists.isNotEmpty) {
      final artist = _taste.artists.first;
      mix = _Quick(
        id: 'mix-${artist.id}',
        title: artist.name,
        subtitle: l10n.kostvMusicMixLabel,
        art: KostvMiniMixArt(
          size: art,
          index: 0,
          picture: _client.imageApi.getPrimaryImageUrl(
            artist.id,
            maxWidth: 200,
          ),
        ),
        onTap: () => unawaited(_playMix(artist.id)),
      );
    }
    final list = _playlists.firstOrNull;
    final playlist = list == null
        ? null
        : _Quick(
            id: 'list-${list.id}',
            title: list.name,
            subtitle: list.childCount == null
                ? l10n.kostvMusicQuickListAlone
                : l10n.kostvMusicQuickList(
                    l10n.kostvMusicTracks(list.childCount!),
                  ),
            cover: kostvMusicImageOf(list),
            onTap: () => openMusicItem(context, list),
          );
    return kostvKeepListening(
      albums: albums,
      favorites: favorites,
      mix: mix,
      playlist: playlist,
      count: phone ? 6 : 8,
    );
  }

  /// Kos TV: «Sigue escuchando»: its accesses in a grid of four columns
  /// (two on the phone).
  Widget? _quickShelf(
    BuildContext context,
    List<_Quick> picks,
    FocusNode? firstNode,
  ) {
    if (picks.isEmpty) return null;
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    final insets = _insets(context);
    final columns = phone ? 2 : 4;
    final gap = phone ? 8.0 : 16.0;
    return Padding(
      padding: EdgeInsets.only(left: insets.left, right: insets.right),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!phone)
            KostvMusicHeading(
              title: l10n.kostvMusicKeepListening,
              padding: const EdgeInsets.only(bottom: 14),
            ),
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - gap * (columns - 1)) / columns;
              return FocusTraversalGroup(
                child: Wrap(
                  spacing: gap,
                  runSpacing: phone ? 8 : 12,
                  children: [
                    for (final (i, pick) in picks.indexed)
                      KostvMusicQuickTile(
                        key: ValueKey('quick-${pick.id}'),
                        width: width,
                        focusNode: i == 0 ? firstNode : null,
                        onKey: i == 0 && firstNode != null ? _upToTabs : null,
                        title: pick.title,
                        // On the phone, only the name (the design's).
                        subtitle: phone ? null : pick.subtitle,
                        cover: pick.cover,
                        art: pick.art,
                        onTap: pick.onTap,
                        onLongPress: pick.onLongPress,
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// «Tus listas»: the person's playlists in Jellyfin.
  Widget? _playlistsShelf(BuildContext context, EdgeInsets insets) {
    if (_playlists.isEmpty) return null;
    final l10n = AppLocalizations.of(context);
    return KostvMusicShelf(
      title: l10n.kostvMusicPlaylists,
      subtitle: l10n.kostvMusicPlaylistsWhy,
      insets: insets,
      height: _shelfHeight(),
      children: [
        for (final list in _playlists)
          KostvMusicAlbumTile(
            size: KostvMusicTokens.card,
            title: list.name,
            subtitle: list.childCount == null
                ? null
                : l10n.kostvMusicTracks(list.childCount!),
            cover: kostvMusicImageOf(list),
            onTap: () => openMusicItem(context, list),
          ),
      ],
    );
  }

  static String? _genreName(AppLocalizations l10n, String? id) => switch (id) {
    'hiphop' => l10n.kostvMusicGenreHiphop,
    'rnb' => l10n.kostvMusicGenreRnb,
    'reggae' => l10n.kostvMusicGenreReggae,
    'bandas-sonoras' => l10n.kostvMusicGenreSoundtracks,
    'electronica' => l10n.kostvMusicGenreElectronic,
    'dance' => l10n.kostvMusicGenreDance,
    'alternativa' => l10n.kostvMusicGenreAlternative,
    'rock' => l10n.kostvMusicGenreRock,
    'pop' => l10n.kostvMusicGenrePop,
    _ => null,
  };

  /// A chart of songs as Apple Music shows its top songs: columns of four
  /// numbered rows, sideways.
  Widget? _chartSongs(
    BuildContext context,
    StremfinChartPage? page,
    String title,
    String why,
    EdgeInsets insets,
    FocusNode? firstNode, {
    List<StremfinSong>? songs,
    bool ranked = true,
    String source = KostvMusicSource.charts,
    bool fresh = false,
  }) {
    final list = songs ?? page?.songs ?? const <StremfinSong>[];
    return _songColumns(
      context,
      list,
      title,
      why,
      insets,
      firstNode,
      ranked,
      source,
      fresh,
    );
  }

  /// Kos TV: a song of the week's discovery, which may have been picked
  /// days ago: what the service says of it now (whether it is at home, a
  /// preview that hasn't expired), for it to open (or its menu) as a
  /// chart's. As it was when it is at home or can't be asked.
  Future<StremfinSong?> _songNow(StremfinSong song) async {
    final stremfin = _stremfin;
    final id = song.deezerId;
    if (stremfin == null || id == null || !_needsNow(song)) return song;
    return (await stremfin.musicSong(id)).song;
  }

  /// Whether [_songNow] has anything to ask of [song]: one that isn't at
  /// home, which the service knows.
  bool _needsNow(StremfinSong song) =>
      _stremfin != null &&
      song.deezerId != null &&
      !song.inJellyfin &&
      song.jellyfinId == null;

  /// Kos TV: the albums the page knows now, by their Deezer id, with what
  /// the service says of them (asked for, on their way): the week's
  /// discovery, picked days ago, shows its marks from them.
  Map<String, StremfinAlbum> _knownAlbums() {
    final known = <String, StremfinAlbum>{};
    void addAll(Iterable<StremfinAlbum?> albums) {
      for (final album in albums) {
        final id = album?.deezerId;
        if (id != null) known[id] = album!;
      }
    }

    for (final chart in [
      _topSongs,
      _latino,
      _mexico,
      _unitedStates,
      _genreChart,
    ]) {
      addAll([for (final song in chart?.songs ?? const []) song.album]);
    }
    addAll(_topAlbums?.albums ?? const []);
    addAll(_forYou?.albums ?? const []);
    addAll(_moreOf?.albums ?? const []);
    addAll(_yourNews);
    addAll(_releases);
    // Last: what the house asked for says it best.
    addAll(_requested);
    return known;
  }

  Widget? _songColumns(
    BuildContext context,
    List<StremfinSong> songs,
    String title,
    String why,
    EdgeInsets insets,
    FocusNode? firstNode,
    bool ranked,
    String source,
    bool fresh,
  ) {
    final parts = _songColumnsParts(
      context,
      songs,
      title,
      why,
      insets,
      firstNode,
      ranked,
      source,
      fresh,
    );
    if (parts == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [parts.heading, parts.rows],
    );
  }

  /// Kos TV: a list of songs in columns: its heading (with «Reproducir» and
  /// «Aleatorio») and its columns, apart, for «Listas de éxitos» to put its
  /// pills between them. [upToTabs]: up from the heading's buttons, the
  /// tabs (the page's first section).
  ({Widget heading, Widget rows})? _songColumnsParts(
    BuildContext context,
    List<StremfinSong> songs,
    String title,
    String why,
    EdgeInsets insets,
    FocusNode? firstNode,
    bool ranked,
    String source,
    bool fresh, {
    bool upToTabs = false,
  }) {
    // Kos TV: with «Toda la música» every song plays (through the requests
    // service those that aren't at home), the list whole from its heading;
    // nothing explicit that isn't at home for someone with a limit.
    final all = kostvMusicCatalogAll();
    if (all) {
      songs = [
        for (final song in songs)
          if (_shows(song)) song,
      ];
    }
    if (songs.isEmpty) return null;
    final list = songs;
    // Kos TV: the discovery's albums as the page knows them now, rather
    // than as they were when the week's songs were picked.
    final known = fresh ? _knownAlbums() : const <String, StremfinAlbum>{};
    StremfinAlbum? albumOf(StremfinSong song) =>
        known[song.albumDeezerId] ?? song.album;
    const perColumn = 4;
    final columns = (songs.length / perColumn).ceil();
    final phone = KostvMusicSizes.phone;
    final rowHeight = _songRowHeight(context, phone);
    final l10n = AppLocalizations.of(context);
    final playable = all && songs.any(kostvSongPlayable);
    // Kos TV: the discovery's card, as big as the page's cards (and never
    // taller than its columns).
    final cardSide = KostvMusicTokens.card.clamp(
      0.0,
      rowHeight * perColumn - 8,
    );
    // Kos TV: the discovery's card plays it all: with «Solo la de casa»,
    // only when some of it is at home (what it plays then); with none, no
    // card that would only say it can't, as the heading has no «Reproducir»
    // either.
    final cardPlays =
        playable ||
        songs.any(
          (song) => song.inJellyfin || (albumOf(song)?.inJellyfin ?? false),
        );
    final lead = source == KostvMusicSource.discovery && cardPlays
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              button: true,
              label: '$title. ${l10n.play}',
              excludeSemantics: true,
              child: KostvMusicPressable(
                key: const ValueKey('discovery-card'),
                focusNode: firstNode,
                onKey: firstNode != null ? _upToTabs : null,
                onTap: () => _playList(list, source, picked: false),
                builder: (context, lit) => KostvFocusFrame(
                  lit: lit,
                  child: Stack(
                    children: [
                      KostvDiscoveryArt(size: cardSide),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: AnimatedOpacity(
                          opacity: lit ? 1 : 0,
                          duration: KostvMusicTokens.focusDuration,
                          child: const KostvPlayFace(diameter: 44),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : null;
    // Kos TV: up from the heading's buttons of the first list, the tabs.
    final headingKey = firstNode != null || upToTabs ? _upToTabs : null;
    return (
      heading: KostvMusicHeading(
        title: title,
        subtitle: why,
        padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 10),
        actions: [
          if (playable) ...[
            KostvMusicRowAction(
              icon: Icons.play_arrow_rounded,
              label: l10n.play,
              primary: true,
              onKey: headingKey,
              onTap: () => _playList(list, source, picked: false),
            ),
            if (songs.length > 2)
              KostvMusicRowAction(
                icon: Icons.shuffle_rounded,
                label: l10n.shuffle,
                onKey: headingKey,
                onTap: () => _playList(list, source, shuffle: true),
              ),
          ],
        ],
      ),
      rows: SizedBox(
        height: rowHeight * perColumn + 8,
        child: FocusTraversalGroup(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.only(left: insets.left, right: insets.right),
            // Kos TV: «Descubrimiento semanal» opens with its own card,
            // which plays it all.
            itemCount: columns + (lead == null ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(width: 18),
            itemBuilder: (context, at) {
              if (lead != null && at == 0) return lead;
              final column = lead == null ? at : at - 1;
              return SizedBox(
                width: kostvMusicSongColumn(context),
                child: Column(
                  children: [
                    for (
                      var i = column * perColumn;
                      i < songs.length && i < (column + 1) * perColumn;
                      i++
                    )
                      KostvMusicSongRow(
                        focusNode: i == 0 && lead == null ? firstNode : null,
                        // Kos TV: with the heading's buttons, up from the
                        // first line goes to them, and from them to the
                        // search.
                        onKey:
                            i % perColumn == 0 && firstNode != null && !playable
                            ? _upToTabs
                            : null,
                        title: songs[i].title,
                        artist: songs[i].artist,
                        artistLinks: [
                          [
                            ?kostvStremfinArtistLink(
                              context,
                              songs[i].artist,
                              songs[i].artistDeezerId,
                            ),
                          ],
                        ],
                        cover: songs[i].cover,
                        rank: ranked ? songs[i].rank ?? i + 1 : null,
                        atHome:
                            songs[i].inJellyfin ||
                            (albumOf(songs[i])?.inJellyfin ?? false),
                        away: all && kostvSongPlayable(songs[i]),
                        badge: all
                            ? KostvMusicBadge.none
                            : switch (albumOf(songs[i])) {
                                final album? => kostvMusicBadgeOf(album),
                                null => KostvMusicBadge.none,
                              },
                        trailing: _noAsk(all, songs[i], albumOf(songs[i])),
                        duration: songs[i].duration,
                        soundingId: kostvSongSoundingId(songs[i]),
                        onRest: _restOn(songs[i]),
                        onTap: () => all && kostvSongPlayable(songs[i])
                            ? _playList(list, source, index: i)
                            : unawaited(
                                openKostvMusicSong(
                                  context,
                                  songs[i],
                                  source: source,
                                  refresh: fresh && _needsNow(songs[i])
                                      ? _songNow
                                      : null,
                                ),
                              ),
                        onLongPress: () => unawaited(
                          showKostvMusicSongMenu(
                            context,
                            song: songs[i],
                            source: source,
                            refresh: fresh && _needsNow(songs[i])
                                ? _songNow
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Kos TV: whether [song] shows with «Toda la música»: what is explicit
  /// and not at home isn't for someone with a limit.
  bool _shows(StremfinSong song) =>
      song.atHome || !song.explicit || !(_stremfin?.hidesExplicitMusic ?? true);

  /// Kos TV: with «Toda la música», a song that can't sound (Deezer
  /// doesn't have it): no «Pedir» at its end, its album's mark instead (a
  /// tap opens it, to ask for it there).
  Widget? _noAsk(bool all, StremfinSong song, StremfinAlbum? album) {
    if (!all || song.atHome || (album?.inJellyfin ?? false)) return null;
    if (kostvSongPlayable(song)) return null;
    return const Icon(Icons.album_outlined, color: kostvMusicGrey, size: 22);
  }

  /// Kos TV: an album's mark on its cover: none with «Toda la música»
  /// (asking for it is on its page).
  KostvMusicBadge _badgeOf(StremfinAlbum album) =>
      kostvMusicCatalogAll() ? KostvMusicBadge.none : kostvMusicBadgeOf(album);

  /// Kos TV: the cards of the albums of the moment («Listas de éxitos»,
  /// «Álbumes»), as a shelf's row (its heading is the section's).
  Widget? _chartAlbumRow(
    BuildContext context,
    StremfinChartPage page,
    EdgeInsets insets,
  ) {
    final albums = page.albums;
    if (albums.isEmpty) return null;
    // The lines under the covers grow with the device's text size, as a
    // shelf's do.
    final grown = MediaQuery.textScalerOf(context).scale(40) - 40;
    return SizedBox(
      height: _shelfHeight() + (grown > 0 ? grown : 0),
      child: FocusTraversalGroup(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.only(
            left: insets.left,
            right: insets.right,
            top: 6,
          ),
          itemCount: albums.length.clamp(0, 30),
          separatorBuilder: (_, _) => SizedBox(width: KostvMusicSizes.gap),
          itemBuilder: (context, i) {
            final album = albums[i];
            return KostvMusicAlbumTile(
              size: KostvMusicTokens.card,
              title: album.title,
              subtitle: album.artist,
              cover: album.cover,
              rank: album.rank,
              badge: _badgeOf(album),
              onTap: () => unawaited(openKostvStremfinAlbum(context, album)),
              onPlay: _albumPlay(album),
            );
          },
        ),
      ),
    );
  }

  Widget? _albumShelf(
    BuildContext context,
    String title,
    String? why,
    List<StremfinAlbum> albums,
    EdgeInsets insets,
  ) {
    if (albums.isEmpty) return null;
    return KostvMusicShelf(
      title: title,
      subtitle: why,
      insets: insets,
      height: _shelfHeight(),
      children: [
        for (final album in albums.take(30))
          KostvMusicAlbumTile(
            size: KostvMusicTokens.card,
            title: album.title,
            subtitle: [
              ?album.artist,
              if (album.year != null) '${album.year}',
            ].join(' · '),
            cover: album.cover,
            badge: _badgeOf(album),
            onTap: () => unawaited(openKostvStremfinAlbum(context, album)),
            onPlay: _albumPlay(album),
          ),
      ],
    );
  }

  Widget? _recentShelf(
    BuildContext context,
    List<AggregatedItem> albums,
    EdgeInsets insets,
    FocusNode? firstNode,
  ) {
    if (albums.isEmpty) return null;
    return KostvMusicShelf(
      title: AppLocalizations.of(context).kostvMusicRecent,
      insets: insets,
      height: _shelfHeight(),
      children: [
        for (final (i, album) in albums.indexed)
          KostvMusicAlbumTile(
            size: KostvMusicTokens.card,
            focusNode: i == 0 ? firstNode : null,
            onKey: i == 0 && firstNode != null ? _upToTabs : null,
            title: album.name,
            subtitle: album.albumArtist,
            cover: kostvMusicImageOf(album),
            onTap: () => openMusicItem(context, album),
            onPlay: () => unawaited(playKostvHomeAlbum(context, album)),
          ),
      ],
    );
  }

  Widget? _mixShelf(
    BuildContext context,
    EdgeInsets insets,
    FocusNode? firstNode,
  ) {
    final artists = _taste.artists.take(6).toList();
    if (artists.isEmpty) return null;
    final l10n = AppLocalizations.of(context);
    final size = KostvMusicTokens.card;
    return KostvMusicShelf(
      title: l10n.kostvMusicMixes,
      subtitle: l10n.kostvMusicMixesWhy,
      insets: insets,
      height: _shelfHeight(),
      children: [
        for (final (i, artist) in artists.indexed)
          KostvMusicAlbumTile(
            size: size,
            focusNode: i == 0 ? firstNode : null,
            onKey: i == 0 && firstNode != null ? _upToTabs : null,
            title: artist.name,
            subtitle: l10n.kostvMusicMixLabel,
            art: KostvMusicMixArt(
              name: artist.name,
              index: i,
              size: size,
              picture: _client.imageApi.getPrimaryImageUrl(
                artist.id,
                maxWidth: 400,
              ),
            ),
            onTap: () => unawaited(_playMix(artist.id)),
            onPlay: () => unawaited(_playMix(artist.id)),
          ),
      ],
    );
  }

  /// Kos TV: «Tus mixes diarios»: square covers, each the colour of its mix
  /// with three of its artists; one plays the mix in its order, and its
  /// menu puts it next or at the end of the queue.
  Widget? _dailyMixShelf(
    BuildContext context,
    EdgeInsets insets,
    FocusNode? firstNode,
  ) {
    final mixes = _shownMixes?.mixes ?? const <KostvDailyMix>[];
    if (mixes.isEmpty) return null;
    final l10n = AppLocalizations.of(context);
    final size = KostvMusicTokens.card;
    return KostvMusicShelf(
      title: l10n.kostvMusicDailyMixes,
      subtitle: l10n.kostvMusicDailyMixesWhy,
      insets: insets,
      // Kos TV: room for the second line of «Con X, Y y más».
      height: _shelfHeight(mixes.any((m) => m.because.isNotEmpty) ? 18 : 0),
      children: [
        for (final (i, mix) in mixes.indexed)
          () {
            final title = l10n.kostvMusicDailyMix(i + 1);
            return KostvMusicAlbumTile(
              key: ValueKey('daily-mix-${mix.id}'),
              size: size,
              focusNode: i == 0 ? firstNode : null,
              onKey: i == 0 && firstNode != null ? _upToTabs : null,
              title: title,
              subtitle: kostvMusicBecause(l10n, mix.because) ?? mix.genre,
              // Kos TV: «Con X, Y y más» may take two lines.
              subtitleLines: 2,
              art: KostvDailyMixArt(
                number: i + 1,
                size: size,
                pictures: _mixPictures(mix),
              ),
              // Kos TV: with «Toda la música», its songs that aren't at
              // home too; the card's ▶ plays it as well.
              onTap: () => _playDailyMix(mix),
              onPlay: () => _playDailyMix(mix),
              onLongPress: () => unawaited(_dailyMixMenu(mix, title)),
            );
          }(),
      ],
    );
  }

  /// The pictures of a mix's cover: its artists', or its songs' covers when
  /// they have none.
  List<String> _mixPictures(KostvDailyMix mix) {
    final pictures = <String>[];
    for (final artist in mix.artists) {
      final tag = artist.primaryImageTag;
      if (tag == null) continue;
      pictures.add(
        _client.imageApi.getPrimaryImageUrl(artist.id, maxWidth: 400, tag: tag),
      );
      if (pictures.length == 3) return pictures;
    }
    for (final song in mix.items) {
      final cover = kostvMusicImageOf(song);
      if (cover != null && !pictures.contains(cover)) pictures.add(cover);
      if (pictures.length == 3) break;
    }
    return pictures;
  }

  static String _momentTitle(AppLocalizations l10n, String slot) =>
      switch (slot) {
        'manana' => l10n.kostvMusicMomentMorning,
        'tarde' => l10n.kostvMusicMomentAfternoon,
        _ => l10n.kostvMusicMomentNight,
      };

  /// Kos TV: the room the moment's row takes, empty, while it is asked for
  /// (the person had one last time): nothing moves when it lands.
  Widget _momentPlace(BuildContext context, EdgeInsets insets) {
    final l10n = AppLocalizations.of(context);
    final rowHeight = _songRowHeight(context, KostvMusicSizes.phone);
    return ExcludeFocus(
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: Opacity(
            opacity: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KostvMusicHeading(
                  title: _momentTitle(l10n, kostvMusicSlotAt(DateTime.now())),
                  subtitle: l10n.kostvMusicMomentWhy,
                  padding: EdgeInsets.fromLTRB(
                    insets.left,
                    0,
                    insets.right,
                    10,
                  ),
                ),
                SizedBox(height: rowHeight * 4 + 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Kos TV: «Para esta mañana», «tarde» or «noche»: the mix of the time of
  /// day, in columns of songs; one plays them all in their order from it.
  Widget? _momentShelf(
    BuildContext context,
    EdgeInsets insets,
    FocusNode? firstNode,
  ) {
    final moment = _shownMoment;
    if (moment == null || !moment.shows) return null;
    final songs = moment.items;
    final l10n = AppLocalizations.of(context);
    final title = _momentTitle(l10n, moment.slot);
    final source = KostvMusicSource.moment(moment.slot);
    const perColumn = 4;
    final columns = (songs.length / perColumn).ceil();
    final rowHeight = _songRowHeight(context, KostvMusicSizes.phone);
    // Kos TV: each song keeps its own row and node (keyed), so one leaving
    // («No me gusta») hands the remote to its neighbour (see
    // [_keepMomentFocus]) rather than to nothing.
    // (A song twice, which the plugin doesn't send, would share them: then
    // as before, without.)
    final distinct =
        (Set<AggregatedItem>.identity()..addAll(songs)).length == songs.length;
    FocusNode? nodeAt(int i) => i == 0 && firstNode != null
        ? firstNode
        : distinct
        ? _momentNode(songs[i])
        : null;
    _momentRows = [
      if (distinct)
        for (final (i, song) in songs.indexed) (song: song, node: nodeAt(i)!),
    ];
    _pruneMomentNodes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KostvMusicHeading(
          title: title,
          subtitle:
              kostvMusicBecause(l10n, moment.because) ??
              l10n.kostvMusicMomentWhy,
          padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 10),
        ),
        SizedBox(
          height: rowHeight * perColumn + 8,
          child: FocusTraversalGroup(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: insets.left, right: insets.right),
              itemCount: columns,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (context, column) => SizedBox(
                width: kostvMusicSongColumn(context),
                child: Column(
                  children: [
                    for (
                      var i = column * perColumn;
                      i < songs.length && i < (column + 1) * perColumn;
                      i++
                    )
                      KostvMusicSongRow(
                        key: distinct ? ObjectKey(songs[i]) : null,
                        focusNode: nodeAt(i),
                        onKey: i % perColumn == 0 && firstNode != null
                            ? _upToTabs
                            : null,
                        title: songs[i].name,
                        artist: [
                          ...songs[i].artists.take(2),
                          ?songs[i].album,
                        ].join(' · '),
                        artistLinks: _homeSongLinks(context, songs[i]),
                        cover: kostvMusicImageOf(songs[i]),
                        atHome: true,
                        duration: songs[i].runtime?.inSeconds,
                        soundingId: songs[i].id,
                        onTap: () => unawaited(_playMoment(moment, i, source)),
                        onLongPress: () => unawaited(
                          showKostvMusicSongMenu(
                            context,
                            item: songs[i],
                            source: source,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ tabs

  /// Kos TV: a message under the tabs (loading, nothing, a failure).
  List<Widget> _tabNote(EdgeInsets insets, Widget child) => [
    SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(insets.left, 30, insets.right, 0),
        child: child,
      ),
    ),
  ];

  /// Kos TV: «Canción · Artista» under a song that is the top result, or
  /// just «Canción» when it has no artist.
  static String _songKind(AppLocalizations l10n, String? artist) =>
      artist == null || artist.trim().isEmpty
      ? l10n.kostvMusicKindSongAlone
      : l10n.kostvMusicKindSong(artist);

  /// Kos TV: how many cards before the end of what the «Artistas» and
  /// «Álbumes» tabs have the next page is asked for.
  static const _libraryAhead = 24;

  /// Kos TV: a tab's note of a failure with its «Reintentar» (for the remote
  /// too, with [focusNode] when it is the page's first stop).
  Widget _retryNote(
    String text,
    Future<void> Function() retry, {
    FocusNode? focusNode,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, style: _noteStyle),
      const SizedBox(height: 14),
      KostvMusicButton(
        key: const ValueKey('kostv-music-tab-retry'),
        icon: Icons.refresh_rounded,
        label: AppLocalizations.of(context).retry,
        focusNode: focusNode,
        onTap: () => unawaited(retry()),
      ),
    ],
  );

  static const _noteStyle = TextStyle(
    color: KostvMusicTokens.muted,
    fontSize: 16,
  );

  /// Kos TV: [count] cards in a grid as wide as the page, built as they
  /// come into sight (a house has many albums), the first one being the
  /// page's first stop when [firstNode] says so.
  Widget _cardGrid(
    EdgeInsets insets, {
    required int count,
    required Widget Function(int index, double size) card,
    bool circles = false,
  }) {
    final phone = KostvMusicSizes.phone;
    final grown = MediaQuery.textScalerOf(context).scale(40) - 40;
    return SliverPadding(
      padding: EdgeInsets.only(left: insets.left, right: insets.right),
      sliver: SliverLayoutBuilder(
        builder: (context, box) {
          final grid = kostvGridOf(box.crossAxisExtent);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: grid.count,
              crossAxisSpacing: KostvMusicTokens.shelfGap,
              mainAxisSpacing: phone ? 14 : 22,
              mainAxisExtent:
                  grid.size + (circles ? 58 : 62) + (grown > 0 ? grown : 0),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => Align(
                alignment: Alignment.topCenter,
                child: card(i, grid.size),
              ),
              childCount: count,
            ),
          );
        },
      ),
    );
  }

  /// Kos TV: «Tus listas»: «Nueva lista» first and then the person's
  /// playlists, the latest first.
  List<Widget> _listsTab(BuildContext context, EdgeInsets insets) {
    final l10n = AppLocalizations.of(context);
    _firstStopShown = true;
    final lists = _playlists;
    return [
      _cardGrid(
        insets,
        count: lists.length + 1,
        card: (i, size) {
          if (i == 0) {
            return KostvNewListCard(
              key: const ValueKey('new-list'),
              size: size,
              focusNode: _firstStop,
              onKey: _upToTabs,
              onTap: () => unawaited(_newPlaylist()),
            );
          }
          final list = lists[i - 1];
          return KostvMusicAlbumTile(
            key: ValueKey('list-${list.id}'),
            size: size,
            title: list.name,
            subtitle: list.childCount == null
                ? null
                : l10n.kostvMusicTracks(list.childCount!),
            cover: kostvMusicImageOf(list),
            onTap: () => openMusicItem(context, list),
          );
        },
      ),
      if (_playlistsFailed)
        ..._tabNote(
          insets,
          _retryNote(l10n.kostvMusicListsFailed, _retryPlaylists),
        )
      else if (lists.isEmpty && !_loading)
        ..._tabNote(insets, Text(l10n.kostvMusicNoLists, style: _noteStyle)),
    ];
  }

  /// Kos TV: «Artistas» or «Álbumes»: what is at home, what was played
  /// lately first (or by name, «A–Z»).
  List<Widget> _libraryTab(
    BuildContext context,
    EdgeInsets insets, {
    required bool artists,
  }) {
    final l10n = AppLocalizations.of(context);
    final all = artists ? _libraryArtists : _libraryAlbums;
    if (all == null) {
      if (!_libraryLoading && !_libraryFailed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadLibrary());
        });
      }
      if (_libraryFailed) _firstStopShown = true;
      return _tabNote(
        insets,
        _libraryFailed
            ? _retryNote(
                l10n.kostvMusicUnavailable,
                _loadLibrary,
                focusNode: _firstStop,
              )
            : const Center(
                child: CircularProgressIndicator(
                  color: KostvMusicTokens.violet,
                ),
              ),
      );
    }
    // Kos TV: what was played lately first even when it is on a page not
    // read yet (it was read on its own).
    final items = _byName
        ? all
        : kostvRecentFirst(artists ? _recentArtistIds : _recentAlbumIds, [
            ...(artists ? _recentArtists : _recentAlbums),
            ...all,
          ], (item) => item.id);
    final more = artists ? _artistsMore : _albumsMore;
    final sort = Padding(
      padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 20),
      child: KostvMusicChoiceRow<bool>(
        values: const [false, true],
        selected: _byName,
        // The order picked is where the remote lands from the tabs.
        nodes: _sortNodes,
        label: (byName) =>
            byName ? l10n.kostvMusicSortAz : l10n.kostvMusicSortRecent,
        onSelect: (byName) => setState(() => _byName = byName),
        onKey: (_, event) => _upToTabs(event),
      ),
    );
    return [
      SliverToBoxAdapter(child: sort),
      if (items.isEmpty)
        ..._tabNote(
          insets,
          Text(
            artists ? l10n.kostvMusicNoArtists : l10n.kostvMusicNoAlbums,
            style: _noteStyle,
          ),
        )
      else
        _cardGrid(
          insets,
          count: items.length,
          circles: artists,
          card: (i, size) {
            // Kos TV: near the end of what it has (scrolling, or the remote
            // going down), the next page.
            if (more && i >= items.length - _libraryAhead) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(_loadMoreLibrary(artists: artists));
              });
            }
            final item = items[i];
            return KostvMusicAlbumTile(
              key: ValueKey('library-${item.id}'),
              size: size,
              circle: artists,
              title: item.name,
              subtitle: artists ? null : item.albumArtist,
              cover: kostvMusicImageOf(item),
              onTap: () => openMusicItem(context, item),
              onPlay: artists
                  ? null
                  : () => unawaited(playKostvHomeAlbum(context, item)),
            );
          },
        ),
    ];
  }

  // --------------------------------------------------------------- results

  /// Kos TV: the search's results in the music design: «Lo mejor» in a big
  /// card with the songs at its side (under it on the phone), then the
  /// artists, the albums and the playlists. What is at home comes first and
  /// what isn't is mixed in and looks the same; with «Solo la de casa» it
  /// keeps its request's state and the albums to ask for stay apart, as
  /// before. On the phone and the web, the filters show one kind only.
  List<Widget> _results(BuildContext context, EdgeInsets insets) {
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    final tv = PlatformDetection.isTV;
    final filter = tv ? KostvMusicFilter.all : _filter;
    final atHome = _atHome;
    final toAsk = _toAsk;
    // Kos TV: with «Toda la música» the songs that aren't at home play, and
    // the albums have no «Pedir» (asking for them is on their page).
    final all = kostvMusicCatalogAll();
    final askable = [
      for (final album in toAsk?.albums ?? const <StremfinAlbum>[])
        if (!album.inJellyfin) album,
    ];
    final askSongs = [
      for (final song in toAsk?.songs ?? const <StremfinSong>[])
        if (!song.inJellyfin) song,
    ];
    final homeArtists = atHome?.artists ?? const <AggregatedItem>[];
    final artistsAway = [
      for (final artist in toAsk?.artists ?? const <StremfinArtist>[])
        if (!homeArtists.any(
          (a) => a.name.toLowerCase() == artist.name.toLowerCase(),
        ))
          artist,
    ];
    final homeAlbums = atHome?.albums ?? const <AggregatedItem>[];
    final homeSongs = atHome?.songs ?? const <AggregatedItem>[];
    final lists = atHome?.playlists ?? const <AggregatedItem>[];
    final parts = <Widget>[];
    // Keyed, as the page's sections: the service's answer arriving after
    // the home server's doesn't rebuild what the person is on.
    void add(String id, Widget part) => parts
      ..add(KeyedSubtree(key: ValueKey('search-$id'), child: part))
      ..add(SizedBox(key: ValueKey('search-$id-gap'), height: phone ? 22 : 30));
    final keep = _firstStop.hasFocus ? _firstOwner : null;
    var first = true;
    FocusNode? firstNode(String id) {
      if (keep != null && id != keep) return null;
      if (keep == null) {
        if (!first) return null;
        first = false;
        _firstOwner = id;
      }
      _firstStopShown = true;
      return _firstStop;
    }

    Widget heading(String title) => KostvMusicHeading(
      title: title,
      padding: const EdgeInsets.only(bottom: 12),
    );

    // ---- the cards
    final artistSize = tv ? 120.0 : (phone ? 104.0 : 160.0);
    final albumSize = tv ? 120.0 : KostvMusicTokens.card;
    Widget artistTile(Object artist, double size) => switch (artist) {
      final AggregatedItem a => KostvMusicAlbumTile(
        key: ValueKey('search-artist-${a.id}'),
        circle: true,
        size: size,
        title: a.name,
        subtitle: l10n.kostvMusicKindArtist,
        cover: kostvMusicImageOf(a),
        onTap: () => openMusicItem(context, a),
      ),
      final StremfinArtist a => KostvMusicAlbumTile(
        key: ValueKey('search-artist-away-${a.name}'),
        circle: true,
        size: size,
        title: a.name,
        subtitle: l10n.kostvMusicKindArtist,
        cover: a.picture,
        onTap: () => openKostvMusicArtist(context, a),
      ),
      _ => const SizedBox.shrink(),
    };
    Widget albumTile(Object album, double size) => switch (album) {
      final AggregatedItem a => KostvMusicAlbumTile(
        key: ValueKey('search-album-${a.id}'),
        size: size,
        title: a.name,
        subtitle: [
          ?a.albumArtist,
          if (a.productionYear != null) '${a.productionYear}',
        ].join(' · '),
        cover: kostvMusicImageOf(a),
        onTap: () => openMusicItem(context, a),
        onPlay: () => unawaited(playKostvHomeAlbum(context, a)),
      ),
      final StremfinAlbum a => KostvMusicAlbumTile(
        key: ValueKey('search-album-away-${a.deezerId ?? a.title}'),
        size: size,
        title: a.title,
        subtitle: [
          ?a.artist,
          switch (a.kind) {
            StremfinAlbumKind.ep => l10n.kostvMusicKindEp,
            StremfinAlbumKind.single => l10n.kostvMusicKindSingle,
            _ => a.year?.toString(),
          },
        ].whereType<String>().join(' · '),
        cover: a.cover,
        badge: _badgeOf(a),
        onTap: () => openKostvMusicAlbum(context, a),
        onPlay: _albumPlay(a),
      ),
      _ => const SizedBox.shrink(),
    };
    Widget listTile(AggregatedItem list, double size) => KostvMusicAlbumTile(
      key: ValueKey('search-list-${list.id}'),
      size: size,
      title: list.name,
      subtitle: list.childCount == null
          ? null
          : l10n.kostvMusicTracks(list.childCount!),
      cover: kostvMusicImageOf(list),
      onTap: () => openMusicItem(context, list),
    );
    final artistItems = <Object>[...homeArtists, ...artistsAway];
    // With «Toda la música», the albums that aren't at home are mixed in;
    // with «Solo la de casa», they stay apart, to ask for.
    final albumItems = <Object>[...homeAlbums, if (all) ...askable];

    // ---- the songs: at home (they play), then those that aren't.
    var rowIndex = 0;
    Widget row({
      required String id,
      required String title,
      required String artist,
      required List<List<KostvMusicLink>> artistLinks,
      required String? cover,
      required bool atHome,
      required FocusNode? node,
      bool explicit = false,
      bool away = false,
      Widget? trailing,
      int? duration,
      String? soundingId,
      ValueChanged<bool>? onRest,
      required VoidCallback onTap,
      required VoidCallback onMenu,
    }) {
      final isFirst = rowIndex++ == 0;
      return KostvMusicSongRow(
        key: ValueKey('search-song-$id'),
        focusNode: isFirst ? node ?? _firstSong : null,
        onKey: isFirst && node != null ? _upToSearch : null,
        title: title,
        artist: artist,
        artistLinks: artistLinks,
        cover: cover,
        atHome: atHome,
        away: away,
        trailing: trailing,
        duration: duration,
        soundingId: soundingId,
        onRest: onRest,
        explicit: explicit,
        onTap: onTap,
        onLongPress: onMenu,
      );
    }

    void playHomeSong(AggregatedItem song) => unawaited(
      playMusicTrack(context, song, source: KostvMusicSource.search),
    );
    void openAwaySong(StremfinSong song) => unawaited(
      openKostvMusicSong(context, song, source: KostvMusicSource.search),
    );
    List<Widget> songRows(FocusNode? node, {int? max}) {
      rowIndex = 0;
      final rows = <Widget>[
        for (final song in homeSongs)
          row(
            id: song.id,
            node: node,
            title: song.name,
            artist: [...song.artists.take(2), ?song.album].join(' · '),
            artistLinks: _homeSongLinks(context, song),
            cover: kostvMusicImageOf(song),
            atHome: true,
            duration: song.runtime?.inSeconds,
            soundingId: song.id,
            onTap: () => playHomeSong(song),
            onMenu: () => unawaited(
              showKostvMusicSongMenu(
                context,
                item: song,
                source: KostvMusicSource.search,
              ),
            ),
          ),
        for (final song in askSongs)
          row(
            id: song.deezerId ?? song.title,
            node: node,
            title: song.title,
            artist: [?song.artist, ?song.albumTitle].join(' · '),
            artistLinks: [
              [
                ?kostvStremfinArtistLink(
                  context,
                  song.artist,
                  song.artistDeezerId,
                ),
              ],
              [?kostvStremfinAlbumLink(context, song)],
            ],
            cover: song.cover,
            atHome: false,
            away: all && kostvSongPlayable(song),
            trailing: _noAsk(all, song, song.album),
            duration: song.duration,
            soundingId: kostvSongSoundingId(song),
            onRest: _restOn(song),
            explicit: song.explicit,
            onTap: () => openAwaySong(song),
            onMenu: () => unawaited(
              showKostvMusicSongMenu(
                context,
                song: song,
                source: KostvMusicSource.search,
              ),
            ),
          ),
      ];
      return max == null ? rows : rows.take(max).toList();
    }

    final songCount = homeSongs.length + askSongs.length;

    // ---- «Lo mejor»
    final top = kostvTopResult<Object>(_query, [
      for (final a in homeAlbums)
        KostvTopCandidate(KostvTopKind.album, a.name, a),
      for (final a in homeArtists)
        KostvTopCandidate(KostvTopKind.artist, a.name, a),
      for (final s in homeSongs)
        KostvTopCandidate(KostvTopKind.song, s.name, s),
      for (final l in lists) KostvTopCandidate(KostvTopKind.list, l.name, l),
      for (final a in askable)
        KostvTopCandidate(KostvTopKind.album, a.title, a),
      for (final a in artistsAway)
        KostvTopCandidate(KostvTopKind.artist, a.name, a),
      for (final s in askSongs)
        KostvTopCandidate(KostvTopKind.song, s.title, s),
    ]);
    // Kos TV: on the TV, right from the card to its ▶ and from it to the
    // first song (beside it); up to the search.
    bool songsBeside() =>
        !phone && songCount > 0 && _firstSong.context?.mounted == true;
    KeyEventResult cardKey(KeyEvent event) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (_topPlay.context?.mounted == true) {
          _topPlay.requestFocus();
          return KeyEventResult.handled;
        }
        if (songsBeside()) {
          _firstSong.requestFocus();
          return KeyEventResult.handled;
        }
      }
      return _upToSearch(event);
    }

    KeyEventResult playKey(KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight && songsBeside()) {
        _firstSong.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey.isUpKey) {
        _firstStop.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    Widget? topCard(FocusNode? node) {
      if (top == null) return null;
      final item = top.item;
      final onKey = node != null ? cardKey : null;
      return switch (item) {
        final AggregatedItem a when top.kind == KostvTopKind.artist =>
          KostvTopResultCard(
            focusNode: node,
            onKey: onKey,
            playFocusNode: _topPlay,
            playOnKey: playKey,
            title: a.name,
            subtitle: l10n.kostvMusicKindArtist,
            cover: kostvMusicImageOf(a),
            circle: true,
            onTap: () => openMusicItem(context, a),
            onPlay: () => unawaited(playKostvStation(context, a)),
          ),
        final AggregatedItem a when top.kind == KostvTopKind.album =>
          KostvTopResultCard(
            focusNode: node,
            onKey: onKey,
            playFocusNode: _topPlay,
            playOnKey: playKey,
            title: a.name,
            subtitle: [
              l10n.kostvMusicKindAlbum,
              ?a.albumArtist,
              if (a.productionYear != null) '${a.productionYear}',
            ].join(' · '),
            cover: kostvMusicImageOf(a),
            onTap: () => openMusicItem(context, a),
            onPlay: () => unawaited(playKostvHomeAlbum(context, a)),
          ),
        final AggregatedItem a when top.kind == KostvTopKind.list =>
          KostvTopResultCard(
            focusNode: node,
            onKey: onKey,
            playFocusNode: _topPlay,
            playOnKey: playKey,
            title: a.name,
            subtitle: a.childCount == null
                ? l10n.kostvMusicQuickListAlone
                : l10n.kostvMusicQuickList(
                    l10n.kostvMusicTracks(a.childCount!),
                  ),
            cover: kostvMusicImageOf(a),
            onTap: () => openMusicItem(context, a),
          ),
        final AggregatedItem s => KostvTopResultCard(
          focusNode: node,
          onKey: onKey,
          playFocusNode: _topPlay,
          playOnKey: playKey,
          title: s.name,
          subtitle: _songKind(l10n, [...s.artists.take(2)].join(', ')),
          cover: kostvMusicImageOf(s),
          onTap: () => playHomeSong(s),
          onPlay: () => playHomeSong(s),
          onLongPress: () => unawaited(
            showKostvMusicSongMenu(
              context,
              item: s,
              source: KostvMusicSource.search,
            ),
          ),
        ),
        final StremfinArtist a => KostvTopResultCard(
          focusNode: node,
          onKey: onKey,
          playFocusNode: _topPlay,
          playOnKey: playKey,
          title: a.name,
          subtitle: l10n.kostvMusicKindArtist,
          cover: a.picture,
          circle: true,
          onTap: () => openKostvMusicArtist(context, a),
          onPlay: all
              ? () => unawaited(playKostvArtistStation(context, a))
              : null,
        ),
        final StremfinAlbum a => KostvTopResultCard(
          focusNode: node,
          onKey: onKey,
          playFocusNode: _topPlay,
          playOnKey: playKey,
          title: a.title,
          subtitle: [
            l10n.kostvMusicKindAlbum,
            ?a.artist,
            if (a.year != null) '${a.year}',
          ].join(' · '),
          cover: a.cover,
          onTap: () => openKostvMusicAlbum(context, a),
          onPlay: _albumPlay(a),
        ),
        final StremfinSong s => KostvTopResultCard(
          focusNode: node,
          onKey: onKey,
          playFocusNode: _topPlay,
          playOnKey: playKey,
          title: s.title,
          subtitle: _songKind(l10n, s.artist),
          cover: s.cover,
          onTap: () => openAwaySong(s),
          onPlay: all && kostvSongPlayable(s) ? () => openAwaySong(s) : null,
          onLongPress: () => unawaited(
            showKostvMusicSongMenu(
              context,
              song: s,
              source: KostvMusicSource.search,
            ),
          ),
        ),
        _ => null,
      };
    }

    // A shelf of [tiles] under [title].
    void shelf(
      String id,
      String title,
      List<Widget> tiles,
      double height, {
      String? subtitle,
    }) {
      if (tiles.isEmpty) return;
      final node = firstNode('search-$id');
      // The page's first stop on the first card, with up to the search.
      final first = tiles.first;
      if (node != null && first is KostvMusicAlbumTile) {
        tiles = [
          KostvMusicAlbumTile(
            key: first.key,
            focusNode: node,
            onKey: _upToSearch,
            circle: first.circle,
            size: first.size,
            title: first.title,
            subtitle: first.subtitle,
            cover: first.cover,
            badge: first.badge,
            onTap: first.onTap,
            onPlay: first.onPlay,
          ),
          ...tiles.skip(1),
        ];
      }
      add(
        id,
        KostvMusicShelf(
          title: title,
          subtitle: subtitle,
          insets: insets,
          height: height,
          children: tiles,
        ),
      );
    }

    // A grid of cards (a filter's), as wide as the page.
    void grid(String id, List<Widget Function(double size)> cards) {
      if (cards.isEmpty) return;
      add(
        id,
        Padding(
          padding: EdgeInsets.only(left: insets.left, right: insets.right),
          child: LayoutBuilder(
            builder: (context, box) {
              final size = kostvGridOf(box.maxWidth).size;
              return FocusTraversalGroup(
                child: Wrap(
                  spacing: KostvMusicTokens.shelfGap,
                  runSpacing: phone ? 14 : 22,
                  children: [for (final card in cards) card(size)],
                ),
              );
            },
          ),
        ),
      );
    }

    double cardShelf(double size) => size + 64;
    switch (filter) {
      case KostvMusicFilter.songs:
        if (songCount > 0) {
          final node = firstNode('search-songs');
          add(
            'songs',
            Padding(
              padding: EdgeInsets.only(left: insets.left, right: insets.right),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: FocusTraversalGroup(
                    child: Column(children: songRows(node)),
                  ),
                ),
              ),
            ),
          );
        }
      case KostvMusicFilter.albums:
        grid('albums', [
          for (final album in [...homeAlbums, ...askable])
            (size) => albumTile(album, size),
        ]);
      case KostvMusicFilter.artists:
        grid('artists', [
          for (final artist in artistItems) (size) => artistTile(artist, size),
        ]);
      case KostvMusicFilter.lists:
        grid('lists', [
          for (final list in lists) (size) => listTile(list, size),
        ]);
      case KostvMusicFilter.all:
        final topNode = top == null ? null : firstNode('search-top');
        final best = topCard(topNode);
        final songNode = best == null && songCount > 0
            ? firstNode('search-songs')
            : null;
        // On the TV every song (it has no filters); elsewhere the first
        // four, with «Canciones» for the rest.
        final rows = songRows(songNode, max: tv ? null : 4);
        if (!phone && best != null && rows.isNotEmpty) {
          add(
            'top',
            Padding(
              padding: EdgeInsets.only(left: insets.left, right: insets.right),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: tv ? 400 : 440,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [heading(l10n.kostvMusicTopResult), best],
                    ),
                  ),
                  const SizedBox(width: 40),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading(l10n.kostvMusicSongs),
                        FocusTraversalGroup(child: Column(children: rows)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          if (best != null) {
            add(
              'top',
              Padding(
                padding: EdgeInsets.only(
                  left: insets.left,
                  right: insets.right,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: phone ? double.infinity : 440,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [heading(l10n.kostvMusicTopResult), best],
                    ),
                  ),
                ),
              ),
            );
          }
          if (rows.isNotEmpty) {
            add(
              'songs',
              Padding(
                padding: EdgeInsets.only(
                  left: insets.left,
                  right: insets.right,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading(l10n.kostvMusicSongs),
                        FocusTraversalGroup(child: Column(children: rows)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        }
        if (tv) {
          // Kos TV: on the TV, as the design: one shelf of artists and
          // albums.
          shelf('artists-albums', l10n.kostvMusicArtistsAndAlbums, [
            for (final artist in artistItems) artistTile(artist, artistSize),
            for (final album in albumItems) albumTile(album, albumSize),
          ], cardShelf(albumSize));
        } else {
          shelf('artists', l10n.kostvMusicArtists, [
            for (final artist in artistItems) artistTile(artist, artistSize),
          ], cardShelf(artistSize));
          shelf('albums', l10n.kostvMusicTabAlbums, [
            for (final album in albumItems) albumTile(album, albumSize),
          ], cardShelf(albumSize));
        }
        shelf('lists', l10n.kostvMusicFilterLists, [
          for (final list in lists) listTile(list, albumSize),
        ], cardShelf(albumSize));
        // Kos TV: with «Solo la de casa» what isn't at home doesn't play:
        // its albums stay apart, to ask for, as before.
        if (!all) {
          shelf(
            'to-ask',
            l10n.kostvMusicToAsk,
            [for (final album in askable) albumTile(album, albumSize)],
            cardShelf(albumSize),
            subtitle: l10n.kostvMusicToAskWhy,
          );
        }
    }
    if (parts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(insets.left, 30, insets.right, 0),
            child: _searching
                ? const Center(
                    child: CircularProgressIndicator(
                      color: KostvMusicTokens.violet,
                    ),
                  )
                : Text(l10n.kostvMusicNoResults(_query), style: _noteStyle),
          ),
        ),
      ];
    }
    // All built, not as they scroll into sight: a section pushed down by
    // one arriving above is kept, and with it the focus the person had in
    // it (a lazy list dropped it, and the page went back to the top).
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: parts,
        ),
      ),
    ];
  }
}

/// The height of a song's line in the columns of songs, grown with the
/// TV's or phone's own text size: its two lines of text get taller.
double _songRowHeight(BuildContext context, bool phone) =>
    kostvMusicSongRowHeight(context, phone);

/// Kos TV: the line of one of the home server's songs in a list, «Artista,
/// Otra · Álbum», with each name opening its page.
List<List<KostvMusicLink>> _homeSongLinks(
  BuildContext context,
  AggregatedItem song,
) {
  void open(String location) => unawaited(context.push(location));
  return [
    kostvHomeArtistLinks(song, open: open, limit: 2),
    [?kostvHomeAlbumLink(song, open: open)],
  ];
}

/// Kos TV: an access of «Sigue escuchando».
class _Quick {
  const _Quick({
    required this.id,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.cover,
    this.art,
    this.onLongPress,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? cover;
  final Widget? art;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
}
