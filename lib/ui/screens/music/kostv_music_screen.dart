import 'dart:async';

import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:playback_core/playback_core.dart' show PlaybackManager;
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/kostv_music_dislikes.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_now_playing.dart';
import '../../widgets/music/music_navigation.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_music_actions.dart';
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
    // Kos TV: back to the app in another time of day: its mix.
    _lifecycle = AppLifecycleListener(onResume: _checkMomentSlot);
    // Kos TV: what the person doesn't want to hear leaves the rows that
    // play by themselves at once (and comes back with «Deshacer»).
    KostvMusicDislikesStore.instance.addListener(_dislikesChanged);
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
      _favorites = await _music.favoriteSongs();
      _refresh();
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _refreshing?.cancel();
    _momentTurn?.cancel();
    _lifecycle?.dispose();
    KostvMusicDislikesStore.instance.removeListener(_dislikesChanged);
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
      part(() async => _favorites = await _music.favoriteSongs()),
      part(() async => _playlists = await _music.playlists()),
      part(() async => _newAtHome = await _music.newAlbums()),
      part(() async => _taste = await _tasteLoad),
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
  Future<void> _loadStremfin(
    StremfinService stremfin, {
    required bool remembered,
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
        }
        if (!mounted) return;
        apply();
        _refresh();
      } catch (e) {
        if (!remembered) {
          _failed = true;
          debugPrint('[Music] $name failed: $e');
        }
      }
    }

    Future<StremfinChartPage> chart(String id, {String? country}) =>
        stremfin.musicChart(id, country: country, remembered: remembered);

    await Future.wait([
      part('top', () async {
        final page = await chart('top-songs');
        return () => _topSongs = page;
      }),
      part('latino', () async {
        final page = await chart('latino-songs');
        return () => _latino = page;
      }),
      part('albums', () async {
        final page = await chart('top-albums');
        return () => _topAlbums = page;
      }),
      part('requested', () async {
        final found = await stremfin.musicRequested(remembered: remembered);
        return () => _requested = found;
      }),
      part('mexico', () async {
        final page = await chart('top-songs', country: 'MX');
        return () => _mexico = page;
      }),
      part('usa', () async {
        final page = await chart('top-songs', country: 'US');
        return () => _unitedStates = page;
      }),
      part('releases', () async {
        final found = await stremfin.musicReleases(remembered: remembered);
        return () => _releases = found;
      }),
      part(_discoveryNote, () async {
        if (!remembered) return _weeklyDiscovery(stremfin);
        final found = await _keptDiscovery(stremfin);
        if (found == null) return () {};
        return () {
          _discovery = found;
          _discoveryWeek = kostvIsoWeek(DateTime.now());
        };
      }),
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

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey.isUpKey) {
      _toMenu();
      return KeyEventResult.handled;
    }
    if (event.logicalKey.isDownKey) {
      // The first stop, if something has it now; otherwise the nearest
      // thing down there.
      if (_firstStopShown && _firstStop.context?.mounted == true) {
        _firstStop.requestFocus();
      } else {
        node.focusInDirection(TraversalDirection.down);
      }
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
    // Music sounding (an audiobook's queue isn't one to add songs to).
    final musicPlaying = KostvNowPlaying.instance.item?.type == 'Audio';
    if (choice == 0 || !musicPlaying) {
      await playMusicTracks(context, mix.items, source: source, picked: false);
      return;
    }
    final queue = GetIt.instance<PlaybackManager>().queueService;
    kostvTellMusicSource(() => _client, source, mix.items);
    if (choice == 1) {
      // Right after the song sounding, in the mix's order, as one change.
      queue.insertAllNext(mix.items);
      kostvMusicSay(context, l10n.kostvMusicMixAddedNext);
    } else {
      queue.addItems(mix.items);
      kostvMusicSay(context, l10n.kostvMusicMixAddedLast);
    }
  });

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

  @override
  Widget build(BuildContext context) {
    _keepFocusInView();
    _firstStopShown = false;
    final insets = calendarChromeInsets(context);
    final phone = KostvMusicSizes.phone;
    final bottom =
        MediaQuery.paddingOf(context).bottom +
        (phone && NavigationLayout.usesBottomNavbar ? 110 : 40);
    final searching = _query.isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: NavigationLayout(
        activeRoute: Destinations.kostvMusic,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A faint glow of Music's colour from the top.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.6, -1.2),
                  radius: 1.3,
                  colors: [Color(0x33FA2D55), Color(0x00000000)],
                ),
              ),
            ),
            CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    insets.left,
                    insets.top + (phone ? 4 : 8),
                    insets.right,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(child: _header(context)),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 26)),
                if (searching)
                  ..._results(context, insets)
                else
                  ..._sections(context, insets),
                SliverToBoxAdapter(child: SizedBox(height: bottom)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.kostvMusic,
          style: theme.textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: phone ? 34 : 44,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          // Only the field follows its focus (not the whole page).
          child: ListenableBuilder(
            listenable: _searchFocus,
            builder: (context, _) => _searchField(context),
          ),
        ),
        // With the remote the songs' menu is hidden behind a long press: it
        // is said once, quietly.
        if (PlatformDetection.isTV) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.touch_app_rounded,
                size: 18,
                color: kostvMusicGrey,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).kostvMusicMenuHint,
                style: const TextStyle(color: kostvMusicGrey, fontSize: 14),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    // Taller with the TV's or phone's own larger text.
    final grown = MediaQuery.textScalerOf(context).scale(20) - 20;
    final height = (phone ? 50.0 : 60.0) + (grown > 0 ? grown : 0);
    final focused = _searchFocus.hasFocus;
    const fill = Color(0xFF1C1C1E);
    final icon = Icon(
      Icons.search_rounded,
      color: focused ? Colors.white : kostvMusicGrey,
      size: phone ? 24 : 28,
    );
    final textStyle = TextStyle(color: Colors.white, fontSize: phone ? 17 : 20);
    final hintStyle = TextStyle(
      color: kostvMusicGrey,
      fontSize: phone ? 17 : 20,
    );
    if (PlatformDetection.isTV) {
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
            borderRadius: 14,
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
      borderRadius: AppRadius.circular(14),
      borderSide: BorderSide.none,
    );
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
          cursorColor: kostvMusicColor,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.kostvMusicSearchHint,
            hintStyle: hintStyle,
            filled: true,
            fillColor: fill,
            prefixIcon: icon,
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(
                      Icons.cancel_rounded,
                      color: kostvMusicGrey,
                    ),
                    onPressed: _search.clear,
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.circular(14),
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

    final parts = <Widget>[];
    // Each section keeps who it is as others arrive around it, so the one
    // being looked at is never rebuilt as another (and the focus with it).
    void add(String id, Widget? part) {
      if (part == null) return;
      parts
        ..add(KeyedSubtree(key: ValueKey('music-$id'), child: part))
        ..add(SizedBox(key: ValueKey('music-$id-gap'), height: 34));
    }

    add(
      'top',
      _chartSongs(
        context,
        _topSongs,
        l10n.kostvMusicTopSongs,
        l10n.kostvMusicTopSongsWhy,
        insets,
        firstNode('top', _topSongs?.songs.isNotEmpty ?? false),
      ),
    );
    add(
      'latino',
      _chartSongs(
        context,
        _latino,
        l10n.kostvMusicTopLatino,
        l10n.kostvMusicChartSoldWhy,
        insets,
        firstNode('latino', _latino?.songs.isNotEmpty ?? false),
      ),
    );
    add(
      'recent',
      _recentShelf(context, insets, firstNode('recent', _recent.isNotEmpty)),
    );
    // Kos TV: what the plugin works out from what the person listens to
    // replaces the rows that did its job before, only when it answers.
    final plugin = kostvMusicPluginRows(
      mixes: _shownMixes,
      discovery: _shownDiscovery,
      moment: _shownMoment,
    );
    // The mix of the time of day right under what was played lately: both
    // are about what to put on now, before the rows that stay the same all
    // day.
    if (plugin.moment) {
      add('moment', _momentShelf(context, insets, firstNode('moment', true)));
    } else if (_momentHeld) {
      add('moment', _momentPlace(context, insets));
    }
    add('favorites', _favoritesShelf(context, insets));
    add('playlists', _playlistsShelf(context, insets));
    // The same section either way, so the page doesn't jump when the daily
    // mixes take the place of «Tus mezclas».
    add(
      'mixes',
      plugin.dailyMixes
          ? _dailyMixShelf(context, insets, firstNode('mixes', true))
          : _mixShelf(
              context,
              insets,
              firstNode('mixes', _taste.artists.isNotEmpty),
            ),
    );
    // «Para ti»: a row for each «Porque escuchas a …», then its songs.
    final forYou = _shownForYou;
    if (forYou != null) {
      final byReason = <String, List<StremfinAlbum>>{};
      for (final album in forYou.albums) {
        byReason.putIfAbsent(album.reason ?? '', () => []).add(album);
      }
      for (final entry in byReason.entries.take(3)) {
        add(
          'foryou-reason-${entry.key}',
          _albumShelf(
            context,
            entry.key.isEmpty ? l10n.kostvMusicForYouAlbums : entry.key,
            l10n.kostvMusicForYouWhy,
            entry.value,
            insets,
          ),
        );
      }
    }
    // Kos TV: «Descubrimiento semanal» in the place of «Canciones para ti»
    // when the plugin gives it; the «Porque escuchas a …» rows stay.
    if (plugin.discovery) {
      add(
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
      );
    } else if (forYou != null) {
      add(
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
      );
    }
    add(
      'your-news',
      _albumShelf(
        context,
        l10n.kostvMusicNewFromYours,
        l10n.kostvMusicNewFromYoursWhy,
        _shownYourNews,
        insets,
      ),
    );
    add(
      'albums',
      _chartAlbums(context, _topAlbums, l10n.kostvMusicTopAlbums, insets),
    );
    add(
      'mexico',
      _chartSongs(
        context,
        _mexico,
        l10n.kostvMusicTopCountry(l10n.kostvMusicMexico),
        l10n.kostvMusicTopCountryWhy(l10n.kostvMusicMexico),
        insets,
        null,
      ),
    );
    final moreOf = _moreOf;
    if (moreOf != null) {
      add(
        'more-of',
        _albumShelf(
          context,
          l10n.kostvMusicMoreOf(moreOf.name),
          l10n.kostvMusicMoreOfWhy(moreOf.name),
          moreOf.albums,
          insets,
        ),
      );
    }
    final genre = _genreChart;
    if (genre != null) {
      add(
        'genre',
        _chartSongs(
          context,
          genre,
          l10n.kostvMusicTopGenre(
            _genreName(l10n, genre.chart.id.replaceFirst('-songs', '')) ??
                genre.chart.name
                    .split('·')
                    .first
                    .replaceFirst('Top ', '')
                    .trim(),
          ),
          l10n.kostvMusicChartSoldWhy,
          insets,
          null,
        ),
      );
    }
    add(
      'usa',
      _chartSongs(
        context,
        _unitedStates,
        l10n.kostvMusicTopCountry(l10n.kostvMusicUnitedStates),
        l10n.kostvMusicTopCountryWhy(l10n.kostvMusicUnitedStates),
        insets,
        null,
      ),
    );
    add(
      'releases',
      _albumShelf(context, l10n.kostvMusicReleases, null, _releases, insets),
    );
    add(
      'requested',
      _albumShelf(context, l10n.kostvMusicRequested, null, _requested, insets),
    );
    if (_newAtHome.isNotEmpty) {
      add(
        'new-at-home',
        KostvMusicShelf(
          title: l10n.kostvMusicNewAtHome,
          insets: insets,
          children: [
            for (final album in _newAtHome)
              KostvMusicAlbumTile(
                title: album.name,
                subtitle: album.albumArtist,
                cover: kostvMusicImageOf(album),
                onTap: () => openMusicItem(context, album),
              ),
          ],
        ),
      );
    }
    if (parts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(insets.left, 40, insets.right, 0),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator(color: kostvMusicColor)
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
                width: KostvMusicSizes.songColumn(context),
                child: Column(
                  children: [
                    for (
                      var i = column * perColumn;
                      i < songs.length && i < (column + 1) * perColumn;
                      i++
                    )
                      KostvMusicSongRow(
                        title: songs[i].name,
                        artist: [
                          ...songs[i].artists.take(2),
                          ?songs[i].album,
                        ].join(' · '),
                        artistLinks: _homeSongLinks(context, songs[i]),
                        cover: kostvMusicImageOf(songs[i]),
                        atHome: true,
                        onTap: () => unawaited(
                          kostvMusicOnce(
                            () => playMusicTracks(
                              context,
                              songs,
                              startIndex: i,
                              source: KostvMusicSource.favorites,
                            ),
                          ),
                        ),
                        onLongPress: () => unawaited(
                          showKostvMusicSongMenu(
                            context,
                            item: songs[i],
                            source: KostvMusicSource.favorites,
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

  /// «Tus listas»: the person's playlists in Jellyfin.
  Widget? _playlistsShelf(BuildContext context, EdgeInsets insets) {
    if (_playlists.isEmpty) return null;
    final l10n = AppLocalizations.of(context);
    return KostvMusicShelf(
      title: l10n.kostvMusicPlaylists,
      subtitle: l10n.kostvMusicPlaylistsWhy,
      insets: insets,
      children: [
        for (final list in _playlists)
          KostvMusicAlbumTile(
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
    if (songs.isEmpty) return null;
    // Kos TV: the discovery's albums as the page knows them now, rather
    // than as they were when the week's songs were picked.
    final known = fresh ? _knownAlbums() : const <String, StremfinAlbum>{};
    StremfinAlbum? albumOf(StremfinSong song) =>
        known[song.albumDeezerId] ?? song.album;
    const perColumn = 4;
    final columns = (songs.length / perColumn).ceil();
    final phone = KostvMusicSizes.phone;
    final rowHeight = _songRowHeight(context, phone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KostvMusicHeading(
          title: title,
          subtitle: why,
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
                width: KostvMusicSizes.songColumn(context),
                child: Column(
                  children: [
                    for (
                      var i = column * perColumn;
                      i < songs.length && i < (column + 1) * perColumn;
                      i++
                    )
                      KostvMusicSongRow(
                        focusNode: i == 0 ? firstNode : null,
                        onKey: i % perColumn == 0 && firstNode != null
                            ? _upToSearch
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
                        badge: switch (albumOf(songs[i])) {
                          final album? => kostvMusicBadgeOf(album),
                          null => KostvMusicBadge.none,
                        },
                        onTap: () => unawaited(
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
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _chartAlbums(
    BuildContext context,
    StremfinChartPage? page,
    String title,
    EdgeInsets insets,
  ) {
    final albums = page?.albums ?? const <StremfinAlbum>[];
    if (albums.isEmpty) return null;
    return KostvMusicShelf(
      title: title,
      subtitle: AppLocalizations.of(context).kostvMusicTopSongsWhy,
      insets: insets,
      children: [
        for (final album in albums.take(30))
          KostvMusicAlbumTile(
            title: album.title,
            subtitle: album.artist,
            cover: album.cover,
            rank: album.rank,
            badge: kostvMusicBadgeOf(album),
            onTap: () => unawaited(openKostvStremfinAlbum(context, album)),
          ),
      ],
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
      children: [
        for (final album in albums.take(30))
          KostvMusicAlbumTile(
            title: album.title,
            subtitle: [
              ?album.artist,
              if (album.year != null) '${album.year}',
            ].join(' · '),
            cover: album.cover,
            badge: kostvMusicBadgeOf(album),
            onTap: () => unawaited(openKostvStremfinAlbum(context, album)),
          ),
      ],
    );
  }

  Widget? _recentShelf(
    BuildContext context,
    EdgeInsets insets,
    FocusNode? firstNode,
  ) {
    if (_recent.isEmpty) return null;
    return KostvMusicShelf(
      title: AppLocalizations.of(context).kostvMusicRecent,
      insets: insets,
      children: [
        for (final (i, album) in _recent.indexed)
          KostvMusicAlbumTile(
            focusNode: i == 0 ? firstNode : null,
            onKey: i == 0 && firstNode != null ? _upToSearch : null,
            title: album.name,
            subtitle: album.albumArtist,
            cover: kostvMusicImageOf(album),
            onTap: () => openMusicItem(context, album),
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
    final size = KostvMusicSizes.cover;
    return KostvMusicShelf(
      title: l10n.kostvMusicMixes,
      subtitle: l10n.kostvMusicMixesWhy,
      insets: insets,
      children: [
        for (final (i, artist) in artists.indexed)
          KostvMusicAlbumTile(
            focusNode: i == 0 ? firstNode : null,
            onKey: i == 0 && firstNode != null ? _upToSearch : null,
            title: artist.name,
            subtitle: l10n.kostvMusicMixLabel,
            art: KostvMusicMixArt(
              name: artist.name,
              index: i,
              size: size - 6,
              picture: _client.imageApi.getPrimaryImageUrl(
                artist.id,
                maxWidth: 400,
              ),
            ),
            onTap: () => unawaited(_playMix(artist.id)),
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
    final size = KostvMusicSizes.cover;
    return KostvMusicShelf(
      title: l10n.kostvMusicDailyMixes,
      subtitle: l10n.kostvMusicDailyMixesWhy,
      insets: insets,
      // Kos TV: room for the second line of «Con X, Y y más».
      height: mixes.any((m) => m.because.isNotEmpty)
          ? KostvMusicSizes.cover + 82
          : null,
      children: [
        for (final (i, mix) in mixes.indexed)
          () {
            final title = l10n.kostvMusicDailyMix(i + 1);
            return KostvMusicAlbumTile(
              key: ValueKey('daily-mix-${mix.id}'),
              focusNode: i == 0 ? firstNode : null,
              onKey: i == 0 && firstNode != null ? _upToSearch : null,
              title: title,
              subtitle: kostvMusicBecause(l10n, mix.because) ?? mix.genre,
              // Kos TV: «Con X, Y y más» may take two lines.
              subtitleLines: 2,
              art: KostvDailyMixArt(
                number: i + 1,
                size: size - 6,
                pictures: _mixPictures(mix),
              ),
              onTap: () => unawaited(
                kostvMusicOnce(
                  () => playMusicTracks(
                    context,
                    mix.items,
                    source: KostvMusicSource.mix(mix.id),
                    picked: false,
                  ),
                ),
              ),
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
                width: KostvMusicSizes.songColumn(context),
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
                            ? _upToSearch
                            : null,
                        title: songs[i].name,
                        artist: [
                          ...songs[i].artists.take(2),
                          ?songs[i].album,
                        ].join(' · '),
                        artistLinks: _homeSongLinks(context, songs[i]),
                        cover: kostvMusicImageOf(songs[i]),
                        atHome: true,
                        onTap: () => unawaited(
                          kostvMusicOnce(
                            () => playMusicTracks(
                              context,
                              songs,
                              startIndex: i,
                              source: source,
                            ),
                          ),
                        ),
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

  // --------------------------------------------------------------- results

  List<Widget> _results(BuildContext context, EdgeInsets insets) {
    final l10n = AppLocalizations.of(context);
    final atHome = _atHome;
    final toAsk = _toAsk;
    final askable = [
      for (final album in toAsk?.albums ?? const <StremfinAlbum>[])
        if (!album.inJellyfin) album,
    ];
    final askSongs = [
      for (final song in toAsk?.songs ?? const <StremfinSong>[])
        if (!song.inJellyfin) song,
    ];
    final artistsAway = toAsk?.artists ?? const <StremfinArtist>[];
    final parts = <Widget>[];
    // Keyed, as the page's sections: the service's answer arriving after
    // the home server's doesn't rebuild what the person is on.
    void add(String id, Widget part) => parts
      ..add(KeyedSubtree(key: ValueKey('search-$id'), child: part))
      ..add(SizedBox(key: ValueKey('search-$id-gap'), height: 30));
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

    // Artists: those at home first, then the service's.
    final artistTiles = <Widget>[
      for (final artist in atHome?.artists ?? const <AggregatedItem>[])
        KostvMusicAlbumTile(
          circle: true,
          size: KostvMusicSizes.artist,
          title: artist.name,
          cover: kostvMusicImageOf(artist),
          onTap: () => openMusicItem(context, artist),
        ),
      for (final artist in artistsAway)
        if (!(atHome?.artists.any(
              (a) => a.name.toLowerCase() == artist.name.toLowerCase(),
            ) ??
            false))
          KostvMusicAlbumTile(
            circle: true,
            size: KostvMusicSizes.artist,
            title: artist.name,
            cover: artist.picture,
            onTap: () => openKostvMusicArtist(context, artist),
          ),
    ];
    if (artistTiles.isNotEmpty) {
      final node = firstNode('search-artists');
      if (node != null && artistTiles.first is KostvMusicAlbumTile) {
        final tile = artistTiles.first as KostvMusicAlbumTile;
        artistTiles[0] = KostvMusicAlbumTile(
          focusNode: node,
          onKey: _upToSearch,
          circle: true,
          size: tile.size,
          title: tile.title,
          cover: tile.cover,
          onTap: tile.onTap,
        );
      }
      add(
        'artists',
        KostvMusicShelf(
          title: l10n.kostvMusicArtists,
          insets: insets,
          height: KostvMusicSizes.artist + 40,
          children: artistTiles,
        ),
      );
    }

    // Songs: at home (they play), then the ones to ask for.
    final homeSongs = (atHome?.songs ?? const <AggregatedItem>[])
        .take(6)
        .toList();
    final songsAway = askSongs.take(6).toList();
    if (homeSongs.isNotEmpty || songsAway.isNotEmpty) {
      final node = firstNode('search-songs');
      var index = 0;
      Widget row({
        required String id,
        required String title,
        required String artist,
        required List<List<KostvMusicLink>> artistLinks,
        required String? cover,
        required bool atHome,
        bool explicit = false,
        required VoidCallback onTap,
        required VoidCallback onMenu,
      }) {
        final first = index++ == 0;
        return KostvMusicSongRow(
          key: ValueKey('search-song-$id'),
          focusNode: first ? node : null,
          onKey: first && node != null ? _upToSearch : null,
          title: title,
          artist: artist,
          artistLinks: artistLinks,
          cover: cover,
          atHome: atHome,
          explicit: explicit,
          onTap: onTap,
          onLongPress: onMenu,
        );
      }

      add(
        'songs',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KostvMusicHeading(
              title: l10n.kostvMusicSongs,
              padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 8),
            ),
            Padding(
              padding: EdgeInsets.only(left: insets.left, right: insets.right),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: FocusTraversalGroup(
                    child: Column(
                      children: [
                        for (final song in homeSongs)
                          row(
                            id: song.id,
                            title: song.name,
                            artist: [
                              ...song.artists.take(2),
                              ?song.album,
                            ].join(' · '),
                            artistLinks: _homeSongLinks(context, song),
                            cover: kostvMusicImageOf(song),
                            atHome: true,
                            onTap: () => unawaited(
                              playMusicTrack(
                                context,
                                song,
                                source: KostvMusicSource.search,
                              ),
                            ),
                            onMenu: () => unawaited(
                              showKostvMusicSongMenu(
                                context,
                                item: song,
                                source: KostvMusicSource.search,
                              ),
                            ),
                          ),
                        for (final song in songsAway)
                          row(
                            id: song.deezerId ?? song.title,
                            title: song.title,
                            artist: [
                              ?song.artist,
                              ?song.albumTitle,
                            ].join(' · '),
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
                            explicit: song.explicit,
                            onTap: () => unawaited(
                              openKostvMusicSong(
                                context,
                                song,
                                source: KostvMusicSource.search,
                              ),
                            ),
                            onMenu: () => unawaited(
                              showKostvMusicSongMenu(
                                context,
                                song: song,
                                source: KostvMusicSource.search,
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
        ),
      );
    }

    final homeAlbums = atHome?.albums ?? const <AggregatedItem>[];
    if (homeAlbums.isNotEmpty) {
      add(
        'albums-at-home',
        KostvMusicShelf(
          title: l10n.kostvMusicAlbumsAtHome,
          insets: insets,
          children: [
            for (final album in homeAlbums)
              KostvMusicAlbumTile(
                title: album.name,
                subtitle: album.albumArtist,
                cover: kostvMusicImageOf(album),
                onTap: () => openMusicItem(context, album),
              ),
          ],
        ),
      );
    }
    if (askable.isNotEmpty) {
      add(
        'to-ask',
        KostvMusicShelf(
          title: l10n.kostvMusicToAsk,
          subtitle: l10n.kostvMusicToAskWhy,
          insets: insets,
          children: [
            for (final album in askable)
              KostvMusicAlbumTile(
                title: album.title,
                subtitle: [
                  ?album.artist,
                  switch (album.kind) {
                    StremfinAlbumKind.ep => l10n.kostvMusicKindEp,
                    StremfinAlbumKind.single => l10n.kostvMusicKindSingle,
                    _ => album.year?.toString(),
                  },
                ].whereType<String>().join(' · '),
                cover: album.cover,
                badge: kostvMusicBadgeOf(album),
                onTap: () => openKostvMusicAlbum(context, album),
              ),
          ],
        ),
      );
    }
    if (parts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(insets.left, 30, insets.right, 0),
            child: _searching
                ? const Center(
                    child: CircularProgressIndicator(color: kostvMusicColor),
                  )
                : Text(
                    l10n.kostvMusicNoResults(_query),
                    style: const TextStyle(color: kostvMusicGrey, fontSize: 17),
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
