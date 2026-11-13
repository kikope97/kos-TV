import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import '../../../preference/user_preferences.dart';
import '../../../util/parental_filter.dart';
import '../../utils/blocked_ratings.dart';
import 'kostv_age_gate.dart';
import 'stremfin_client.dart';
import 'stremfin_inbox.dart';
import 'stremfin_models.dart';

/// Kos TV: whether the person may use Discover, as the requests service last
/// said.
enum StremfinAccess { unknown, allowed, denied }

/// Kos TV: the requests service (Stremfin) for the rest of the app: who may
/// use it (asked when someone signs in and when the app comes back to the
/// front) and the platform lists, kept for a while so moving between
/// platforms doesn't ask again.
class StremfinService extends ChangeNotifier {
  StremfinService(
    this._client, {
    Future<KostvAgeLimit> Function()? ageLimit,
    @visibleForTesting ParentalFilter Function()? parental,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting bool watchLifecycle = true,
  }) : _readAgeLimit = ageLimit,
       _parental = parental ?? (() => activeParentalFilter),
       _clock = clock ?? DateTime.now {
    if (watchLifecycle) {
      _lifecycle = AppLifecycleListener(
        onResume: () => unawaited(refreshAccess()),
        onShow: () => inbox.setForeground(true),
        onHide: () => inbox.setForeground(false),
      );
    }
  }

  final StremfinClient _client;
  final DateTime Function() _clock;

  /// Kos TV: reads the person's age limit from their home server account
  /// (null: nothing limited, as in tests).
  final Future<KostvAgeLimit> Function()? _readAgeLimit;

  /// The device's own parental control.
  final ParentalFilter Function() _parental;

  /// The person's age limit, once read; null until then.
  KostvAgeLimit? _ageLimit;
  AppLifecycleListener? _lifecycle;

  /// How long a list stays fresh. The service itself keeps them for minutes
  /// to an hour, so asking more often brings nothing new.
  static const listLifetime = Duration(minutes: 15);

  /// When to ask again after the service couldn't answer.
  static const _retryDelay = Duration(minutes: 2);

  StremfinAccess _access = StremfinAccess.unknown;
  StremfinMe? _me;
  Future<void>? _checking;
  Timer? _retry;
  String? _checkedFor;

  /// Bumped when the person changes, so a list asked for before doesn't land
  /// in the next person's memory.
  int _generation = 0;
  List<StremfinPlatform>? _platforms;
  final Map<String, ({DateTime at, List<StremfinTitle> items})> _lists = {};
  final Map<String, Future<List<StremfinTitle>>> _loading = {};

  /// Searches already made, a while: searching the same again (going back
  /// to the search, typing a letter and taking it back) costs nothing.
  final Map<String, ({DateTime at, StremfinSearchPage page})> _searches = {};
  final Map<String, Future<StremfinSearchPage>> _searching = {};
  static const searchLifetime = Duration(minutes: 10);
  static const _searchesKept = 40;

  /// The last word on each title (asked for, arrived…), for what shows a
  /// title outside the lists, like the search.
  final Map<String, StremfinTitle> _latest = {};

  bool get isConfigured => _client.isConfigured;

  /// Kos TV: whether [title] may be shown to the signed-in person, by their
  /// age limit and the device's parental control (see [kostvAgeAllows]).
  /// Everything the service hands out goes through here: Discover, the
  /// search and a title's page.
  bool allows(StremfinTitle title) {
    final limit = _readAgeLimit == null ? KostvAgeLimit.none : _ageLimit;
    // Not read yet: nothing can be shown safely.
    if (limit == null) return false;
    return kostvAgeAllows(title, limit: limit, parental: _parental());
  }

  /// Whether some titles may be hidden from this person, so lists are read
  /// longer to stay full.
  bool get _limited =>
      (_ageLimit != null && _ageLimit != KostvAgeLimit.none) ||
      _parental().isActive;

  /// How many titles a Discover list shows.
  static const listShown = 20;
  StremfinAccess get access => _access;
  bool get isAllowed => _access == StremfinAccess.allowed;

  /// What the service last said of the signed-in person: whether what they
  /// ask for waits for an answer, and whether they are at their limit.
  StremfinMe? get me => _me;

  /// Bumped whenever a title on a list kept in memory changes (it was asked
  /// for, it arrived…), so Discover can show it as it stands.
  final ValueNotifier<int> listsRevision = ValueNotifier(0);

  /// The person's own requests, for the requests tray.
  late final StremfinInbox inbox = StremfinInbox(_client);

  /// Asks the service who the signed-in person is. Not reaching it keeps
  /// what it said last and tries again a little later; a refusal hides
  /// Discover but never signs anyone out of the app.
  Future<void> refreshAccess() {
    if (!_client.isConfigured) return Future.value();
    return _checking ??= _checkAccess().whenComplete(() => _checking = null);
  }

  Future<void> _checkAccess() async {
    _retry?.cancel();
    if (_disposed) return;
    // Kos TV: the person's age limit first, from their home server account.
    // Without it nothing can be shown safely, so it counts as the service
    // not answering; once known, a failed read keeps what was known.
    final readAgeLimit = _readAgeLimit;
    if (readAgeLimit != null) {
      try {
        final limit = await readAgeLimit();
        if (_disposed) return;
        if (limit != _ageLimit) {
          _ageLimit = limit;
          listsRevision.value++;
          notifyListeners();
        }
      } catch (_) {
        if (_disposed) return;
        if (_ageLimit == null) {
          if (_access == StremfinAccess.unknown) {
            _setAccess(StremfinAccess.denied);
          }
          _retry = Timer(_retryDelay, () => unawaited(refreshAccess()));
          return;
        }
      }
    }
    try {
      final me = await _client.me();
      if (_disposed) return;
      final before = _me;
      _me = me;
      final access = me.canDiscover
          ? StremfinAccess.allowed
          : StremfinAccess.denied;
      if (access == _access &&
          (before?.atLimit != me.atLimit || before?.mode != me.mode)) {
        // The same access, but reaching or leaving their limit changes what
        // a title's page offers.
        notifyListeners();
      }
      _setAccess(access);
    } on StremfinException catch (e) {
      if (e.isNoAccess) {
        _setAccess(StremfinAccess.denied);
      } else {
        // Switched off, home server not answering, no network: hidden until
        // it answers, if it never has.
        if (_access == StremfinAccess.unknown) {
          _setAccess(StremfinAccess.denied);
        }
        if (_disposed) return;
        _retry = Timer(
          e.retryAfter ?? _retryDelay,
          () => unawaited(refreshAccess()),
        );
      }
    }
  }

  void _setAccess(StremfinAccess access) {
    if (_disposed) return;
    // Their requests, while the service lets them in.
    inbox.setEnabled(access == StremfinAccess.allowed);
    if (_access == access) return;
    _access = access;
    notifyListeners();
  }

  /// Someone else signed in, or nobody is: forget what was known.
  void onUserChanged(String? userId) {
    if (userId == _checkedFor) return;
    _checkedFor = userId;
    _forget();
  }

  /// The service moved (the home server's plugin gave another address, or
  /// none): what the old one said doesn't count, so ask the new one.
  void onAddressChanged() {
    if (_disposed) return;
    _platforms = null;
    _forget();
  }

  void _forget() {
    final userId = _checkedFor;
    _ageLimit = null;
    _generation++;
    _retry?.cancel();
    _lists.clear();
    _loading.clear();
    _searches.clear();
    _searching.clear();
    _latest.clear();
    // Kos TV: what Music kept is the last person's (their requests, their
    // «Para ti»): none of it is shown to the next one.
    _charts = null;
    _chartPages.clear();
    _recommended.clear();
    // On the device it is kept for one person only (see
    // StremfinMusicMemory); signed out, it goes.
    if (userId == null) unawaited(_client.musicMemory?.clear());
    _me = null;
    inbox.setUser(userId);
    _setAccess(StremfinAccess.unknown);
    if (userId != null) unawaited(refreshAccess());
  }

  /// The platform buttons, in the service's order. Falls back to the usual
  /// four.
  Future<List<StremfinPlatform>> platforms() async {
    final known = _platforms;
    if (known != null) return known;
    try {
      final read = await _client.platforms();
      if (read.isNotEmpty) return _platforms = read;
    } on StremfinException {
      // The usual four below.
    }
    return StremfinPlatform.defaults;
  }

  /// A list, from memory while it is fresh. With [refresh] it is asked again.
  /// Only what the person may see (see [allows]), at most [listShown].
  Future<List<StremfinTitle>> top({
    required String platform,
    required StremfinTitleType type,
    required StremfinTopList list,
    bool refresh = false,
  }) => _topRead(
    platform: platform,
    type: type,
    list: list,
    refresh: refresh,
  ).then(_shownList);

  List<StremfinTitle> _shownList(List<StremfinTitle> items) =>
      items.where(allows).take(listShown).toList();

  /// Someone who may not see everything gets longer lists, so theirs stay
  /// full: as long as the service gives (a platform's most watched, 20).
  int? _topLimit(String platform, StremfinTopList list) {
    if (!_limited) return null;
    return platform != StremfinPlatform.allId && list == StremfinTopList.popular
        ? 20
        : 40;
  }

  String _topKey(
    String platform,
    StremfinTitleType type,
    StremfinTopList list,
  ) =>
      '$platform/${type.apiValue}/${list.apiValue}'
      '/${_topLimit(platform, list) ?? ''}';

  Future<List<StremfinTitle>> _topRead({
    required String platform,
    required StremfinTitleType type,
    required StremfinTopList list,
    bool refresh = false,
  }) {
    final key = _topKey(platform, type, list);
    final kept = _lists[key];
    if (!refresh &&
        kept != null &&
        _clock().difference(kept.at) < listLifetime) {
      return Future.value(kept.items);
    }
    final pending = _loading[key];
    if (pending != null) return pending;
    final generation = _generation;
    final future = _client
        .top(
          platform: platform,
          type: type,
          list: list,
          limit: _topLimit(platform, list),
        )
        .then((items) {
          if (generation == _generation) {
            _lists[key] = (at: _clock(), items: items);
          }
          return items;
        })
        .whenComplete(() {
          if (generation == _generation) _loading.remove(key);
        });
    return _loading[key] = future;
  }

  /// Reads Discover's first page (every platform together) ahead of time,
  /// while the opening plays, so it opens already filled. Quietly does nothing
  /// for someone the service doesn't let in.
  Future<void> prefetch() async {
    await refreshAccess();
    if (!isAllowed) return;
    await Future.wait([
      platforms(),
      for (final type in StremfinTitleType.values)
        for (final list in StremfinTopList.values)
          top(
            platform: StremfinPlatform.allId,
            type: type,
            list: list,
          ).then<void>((_) {}, onError: (_) {}),
    ]);
  }

  /// A list as it was last read, however old, to show while it's asked again.
  List<StremfinTitle>? keptList({
    required String platform,
    required StremfinTitleType type,
    required StremfinTopList list,
  }) {
    final items = _lists[_topKey(platform, type, list)]?.items;
    return items == null ? null : _shownList(items);
  }

  /// Films and series that aren't on the home server and match [query], for
  /// the search's «Para solicitar». From memory while it is fresh.
  ///
  /// Kos TV: only what the person may see (see [allows]). A page left empty
  /// by that reads on, a couple of pages at most, so the search doesn't
  /// stall on a page of titles they can't see.
  Future<StremfinSearchPage> search(String query, {String? cursor}) async {
    var page = await _searchRead(query, cursor: cursor);
    var items = page.items.where(allows).toList();
    for (
      var hops = 0;
      items.isEmpty && page.nextCursor != null && hops < 2;
      hops++
    ) {
      page = await _searchRead(query, cursor: page.nextCursor);
      items = page.items.where(allows).toList();
    }
    return StremfinSearchPage(items: items, nextCursor: page.nextCursor);
  }

  Future<StremfinSearchPage> _searchRead(String query, {String? cursor}) {
    final key = '${query.toLowerCase()}|${cursor ?? ''}';
    final kept = _searches[key];
    if (kept != null && _clock().difference(kept.at) < searchLifetime) {
      return Future.value(kept.page);
    }
    final pending = _searching[key];
    if (pending != null) return pending;
    final generation = _generation;
    final future = _client
        .search(query, cursor: cursor)
        .then((page) {
          if (generation == _generation) {
            if (_searches.length >= _searchesKept) {
              _searches.remove(_searches.keys.first);
            }
            _searches[key] = (at: _clock(), page: page);
          }
          return page;
        })
        // A block, not an arrow: the arrow would hand back the future being
        // removed, and the search would wait on itself.
        .whenComplete(() {
          _searching.remove(key);
        });
    return _searching[key] = future;
  }

  /// [title] as last heard of: the home server and its request as they
  /// stand now, keeping what its list or search said of it.
  StremfinTitle latest(StremfinTitle title) {
    final known = _latest[_titleKey(title)];
    if (known == null) return title;
    return title.copyWith(library: known.library, request: () => known.request);
  }

  static String _titleKey(StremfinTitle title) =>
      '${title.type.apiValue}:${title.tmdbId}';

  /// A film's page. What it says of the home server and the requests is
  /// the reliable answer, so the lists in memory take it too.
  Future<StremfinMovieDetail> movie(int tmdbId) async {
    final detail = await _client.movie(tmdbId);
    noteTitle(detail.title);
    return detail;
  }

  // ------------------------------------------------------------ Kos TV: music

  List<StremfinChart>? _charts;
  final Map<String, ({DateTime at, StremfinChartPage page})> _chartPages = {};

  /// How long a chart is kept here: the service refreshes them every few
  /// hours.
  static const _chartFor = Duration(minutes: 30);

  /// The charts there are; their list doesn't change, so it is kept.
  Future<List<StremfinChart>> musicCharts() async =>
      _charts ??= await _client.musicCharts();

  /// One chart's places, kept for half an hour.
  Future<StremfinChartPage> musicChart(
    String id, {
    bool fresh = false,
    String? country,
    bool remembered = false,
  }) async {
    if (remembered) {
      return _client.musicChart(id, country: country, remembered: true);
    }
    final key = country == null ? id : '$country:$id';
    final kept = _chartPages[key];
    if (!fresh &&
        kept != null &&
        DateTime.now().difference(kept.at) < _chartFor) {
      return kept.page;
    }
    final page = await _client.musicChart(id, country: country);
    _chartPages[key] = (at: DateTime.now(), page: page);
    return page;
  }

  final Map<String, ({DateTime at, StremfinRecommendations found})>
  _recommended = {};

  /// «Para ti» for [artists]: the service keeps it an hour and allows few
  /// calls, so it is kept here as long.
  Future<StremfinRecommendations> musicRecommendations(
    List<String> artists, {
    List<String> genres = const [],
    bool remembered = false,
  }) async {
    if (remembered) {
      return _client.musicRecommendations(
        artists,
        genres: genres,
        remembered: true,
      );
    }
    final key = '${artists.join(',')}|${genres.join(',')}';
    final kept = _recommended[key];
    if (kept != null &&
        DateTime.now().difference(kept.at) < const Duration(hours: 1)) {
      return kept.found;
    }
    final found = await _client.musicRecommendations(artists, genres: genres);
    _recommended[key] = (at: DateTime.now(), found: found);
    return found;
  }

  /// The latest records of the artists [deezerIds].
  Future<List<StremfinAlbum>> musicArtistReleases(
    List<String> deezerIds, {
    bool remembered = false,
  }) => _client.musicArtistReleases(deezerIds, remembered: remembered);

  /// Music matching [query]: what the home server has and what it hasn't.
  Future<StremfinMusicSearch> musicSearch(
    String query, {
    bool keep = false,
    bool remembered = false,
  }) =>
      _client.musicSearch(query, limit: 30, keep: keep, remembered: remembered);

  Future<StremfinAlbumDetail> musicAlbum(String deezerId) =>
      _client.musicAlbum(deezerId);

  Future<StremfinSongDetail> musicSong(String deezerId) =>
      _client.musicSong(deezerId);

  Future<StremfinArtistDetail> musicArtist(
    String deezerId, {
    bool keep = false,
    bool remembered = false,
  }) => _client.musicArtist(deezerId, keep: keep, remembered: remembered);

  /// The Music page's own notes, kept with its answers on the device.
  void keepMusicNote(String name, Object value) =>
      _client.keepMusicNote(name, value);

  Future<Object?> rememberedMusicNote(String name) =>
      _client.rememberedMusicNote(name);

  /// What the house asked for most lately.
  Future<List<StremfinAlbum>> musicRequested({bool remembered = false}) =>
      _client.musicRequested(limit: 20, remembered: remembered);

  /// The latest records of the artists the house follows.
  Future<List<StremfinAlbum>> musicReleases({bool remembered = false}) =>
      _client.musicReleases(remembered: remembered);

  /// Asks for an album (a single's whole album, when it has one). The
  /// charts kept here are forgotten, since what they say of it changes.
  Future<StremfinRequestResult> createMusicRequest(String deezerId) async {
    try {
      final result = await _client.createMusicRequest(deezerId);
      final made = result.request;
      if (made != null) inbox.note(made, seen: true);
      // What the lists said of it changed («Pedir» → «Pedido»).
      _chartPages.clear();
      _recommended.clear();
      return result;
    } finally {
      unawaited(refreshAccess());
    }
  }

  /// Whether a film can be downloaded now and how fast.
  Future<StremfinAvailability> movieAvailability(int tmdbId) =>
      _client.movieAvailability(tmdbId);

  /// A series' page, season by season.
  Future<StremfinSeriesDetail> series(int tmdbId) async {
    final detail = await _client.series(tmdbId);
    noteSeries(detail);
    return detail;
  }

  final Map<String, List<StremfinTrailer>> _trailers = {};
  final Map<String, Future<List<StremfinTrailer>>> _trailersLoading = {};

  /// How long a title's trailers may take: the person is waiting to watch
  /// one, and the home server has its own list to fall back on.
  static const trailersTimeout = Duration(seconds: 4);
  static const trailersRetryAfter = Duration(minutes: 2);
  DateTime? _trailersFailedAt;

  /// A title's trailers, the best first (dubbed into Spain's Spanish before
  /// any other). Empty when it has none, the person isn't let in, or the
  /// service doesn't answer in time: never an error, since whoever asks has
  /// the home server's own to show. Kept for the session.
  Future<List<StremfinTrailer>> trailers(StremfinTitleType type, int tmdbId) {
    final key = '${type.apiValue}:$tmdbId';
    final known = _trailers[key];
    if (known != null) return Future.value(known);
    // A service that just failed isn't made to hold up the next trailer too.
    final failed = _trailersFailedAt;
    if (failed != null &&
        DateTime.now().difference(failed) < trailersRetryAfter) {
      return Future.value(const <StremfinTrailer>[]);
    }
    return _trailersLoading[key] ??= () async {
      try {
        if (!isConfigured) return const <StremfinTrailer>[];
        if (!isAllowed) {
          await refreshAccess();
          if (!isAllowed) return const <StremfinTrailer>[];
        }
        final read = await _client
            .trailers(type, tmdbId)
            .timeout(trailersTimeout);
        _trailersFailedAt = null;
        return _trailers[key] = read;
      } on StremfinException catch (e) {
        // A title it doesn't know is an answer, not a failure.
        if (e.status != 404) _trailersFailedAt = DateTime.now();
        return const <StremfinTrailer>[];
      } catch (_) {
        _trailersFailedAt = DateTime.now();
        return const <StremfinTrailer>[];
      } finally {
        unawaited(_trailersLoading.remove(key));
      }
    }();
  }

  /// One request as it stands now.
  /// One request as its page shows it, so the tray doesn't count what the
  /// person has just seen there as news.
  Future<StremfinRequest> request(int id) async {
    final read = await _client.request(id);
    inbox.note(read, seen: true);
    return read;
  }

  /// Asks for a film, a season or (with no [season]) all that is missing of
  /// a series. Afterwards it asks again who the person is, since what they
  /// have pending and left for the day has changed.
  Future<StremfinRequestResult> createRequest({
    required StremfinTitleType type,
    required int tmdbId,
    int? season,
    int? episode,
  }) async {
    try {
      final result = await _client.createRequest(
        type: type,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
      );
      final made = result.request;
      if (made != null) inbox.note(made, seen: true);
      return result;
    } finally {
      unawaited(refreshAccess());
    }
  }

  /// Takes back one of theirs that still waits for an answer.
  Future<void> withdrawRequest(int id) async {
    try {
      await _client.withdrawRequest(id);
      inbox.remove(id);
    } finally {
      unawaited(refreshAccess());
    }
  }

  /// [title] as it stands now: every list in memory that holds it shows it
  /// so, keeping its place, season and platform on that list.
  void noteTitle(StremfinTitle title) => _note(title, (kept) {
    return kept.copyWith(library: title.library, request: () => title.request);
  });

  /// A series as its page says it stands. A card that announces a season
  /// («Nuevo · T3») keeps what it says of that season on the home server and
  /// shows the request that covers it.
  void noteSeries(StremfinSeriesDetail detail) => _note(detail.title, (kept) {
    final season = kept.season;
    if (season == null) {
      return kept.copyWith(
        library: detail.title.library,
        request: () => detail.title.request,
      );
    }
    final covering = detail.seasons
        .where((s) => s.number == season)
        .firstOrNull
        ?.request;
    return kept.copyWith(request: () => covering ?? detail.title.request);
  });

  void _note(StremfinTitle title, StremfinTitle Function(StremfinTitle) apply) {
    if (_disposed) return;
    _latest[_titleKey(title)] = title;
    for (final entry in _lists.entries.toList()) {
      final items = entry.value.items;
      final index = items.indexWhere(
        (t) => t.type == title.type && t.tmdbId == title.tmdbId,
      );
      if (index < 0) continue;
      _lists[entry.key] = (
        at: entry.value.at,
        items: [...items]..[index] = apply(items[index]),
      );
    }
    // Always: the search shows titles outside the lists and hears of it too.
    listsRevision.value++;
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _lifecycle?.dispose();
    listsRevision.dispose();
    inbox.dispose();
    super.dispose();
  }
}

/// Kos TV: whether the requests service lets the signed-in person use
/// Discover (before the Settings switch and kids mode are counted).
bool kostvDiscoverAllowed() {
  final getIt = GetIt.instance;
  return getIt.isRegistered<StremfinService>() &&
      getIt<StremfinService>().isAllowed;
}

/// Kos TV: whether the navigation shows the Discover button: a build that
/// knows the requests service, a person it lets in, outside kids mode, while
/// it is turned on in Settings.
bool showKostvDiscoverButton(UserPreferences prefs, {required bool kidsMode}) {
  final getIt = GetIt.instance;
  return !kidsMode &&
      getIt.isRegistered<StremfinService>() &&
      getIt<StremfinService>().isAllowed &&
      prefs.get(UserPreferences.showDiscoverButton);
}
