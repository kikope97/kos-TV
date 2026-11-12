import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import '../../../preference/user_preferences.dart';
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
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting bool watchLifecycle = true,
  }) : _clock = clock ?? DateTime.now {
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
    _generation++;
    _retry?.cancel();
    _lists.clear();
    _loading.clear();
    _searches.clear();
    _searching.clear();
    _latest.clear();
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
  Future<List<StremfinTitle>> top({
    required String platform,
    required StremfinTitleType type,
    required StremfinTopList list,
    bool refresh = false,
  }) {
    final key = '$platform/${type.apiValue}/${list.apiValue}';
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
        .top(platform: platform, type: type, list: list)
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
  }) => _lists['$platform/${type.apiValue}/${list.apiValue}']?.items;

  /// Films and series that aren't on the home server and match [query], for
  /// the search's «Para solicitar». From memory while it is fresh.
  Future<StremfinSearchPage> search(String query, {String? cursor}) {
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

  /// Whether a film can be downloaded now and how fast.
  Future<StremfinAvailability> movieAvailability(int tmdbId) =>
      _client.movieAvailability(tmdbId);

  /// A series' page, season by season.
  Future<StremfinSeriesDetail> series(int tmdbId) async {
    final detail = await _client.series(tmdbId);
    noteSeries(detail);
    return detail;
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
  }) async {
    try {
      final result = await _client.createRequest(
        type: type,
        tmdbId: tmdbId,
        season: season,
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
