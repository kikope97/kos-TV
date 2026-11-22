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
    bool Function()? kidsMode,
    Listenable? kidsModeChanges,
  }) : _readAgeLimit = ageLimit,
       _parental = parental ?? (() => activeParentalFilter),
       _clock = clock ?? DateTime.now,
       _kidsMode = kidsMode,
       _kidsModeChanges = kidsModeChanges {
    if (watchLifecycle) {
      _lifecycle = AppLifecycleListener(
        onResume: () => unawaited(refreshAccess()),
        onShow: () => inbox.setForeground(true),
        onHide: () {
          inbox.setForeground(false);
          // Kos TV: not asked again from behind another app (coming back
          // to the front asks anyway).
          _retry?.cancel();
        },
      );
    }
    // Kos TV: in kids mode the tray isn't shown, so it isn't kept up to
    // date either; leaving it, it is asked again.
    if (kidsMode != null) {
      inbox.setKidsMode(kidsMode());
      kidsModeChanges?.addListener(_onKidsModeChanged);
    }
  }

  /// Kos TV: whether the device is in kids mode, and what tells when it
  /// changes.
  final bool Function()? _kidsMode;
  final Listenable? _kidsModeChanges;

  void _onKidsModeChanged() {
    final kidsMode = _kidsMode;
    if (kidsMode != null && !_disposed) inbox.setKidsMode(kidsMode());
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

  /// Kos TV: the session (its fingerprint) the service last turned down as
  /// signed out (401): signing in again as the same person brings another,
  /// which is asked about then (the same one is never asked again in a
  /// loop, as the service asks).
  String? _signedOutSession;

  /// Bumped when the person changes, so a list asked for before doesn't land
  /// in the next person's memory.
  int _generation = 0;

  /// Kos TV: bumped whenever what was known of the person is forgotten
  /// (another person, or the service moved), for what keeps the service's
  /// answers elsewhere (see KostvSeriesGaps).
  int get generation => _generation;
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

  /// Kos TV: the person is held back only because the service hasn't
  /// answered yet (no network, switched off, their age limit unread), not
  /// because it said no: what it said last time may still be shown.
  bool get accessUnanswered =>
      _access == StremfinAccess.denied && _deniedUnanswered;
  bool _deniedUnanswered = false;

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
    final running = _checking;
    if (running != null) return running;
    late final Future<void> check;
    check = _checkAccess().whenComplete(() {
      if (identical(_checking, check)) _checking = null;
    });
    return _checking = check;
  }

  Future<void> _checkAccess() async {
    _retry?.cancel();
    if (_disposed) return;
    // Kos TV: another person signed in meanwhile: what this check finds is
    // the last one's (their age limit!) and is thrown away.
    final generation = _generation;
    bool stale() => _disposed || generation != _generation;
    // Kos TV: the person's age limit first, from their home server account.
    // Without it nothing can be shown safely, so it counts as the service
    // not answering; once known, a failed read keeps what was known.
    final readAgeLimit = _readAgeLimit;
    if (readAgeLimit != null) {
      try {
        final limit = await readAgeLimit();
        if (stale()) return;
        if (limit != _ageLimit) {
          _ageLimit = limit;
          listsRevision.value++;
          notifyListeners();
        }
      } catch (_) {
        if (stale()) return;
        if (_ageLimit == null) {
          if (_access == StremfinAccess.unknown) {
            _deniedUnanswered = true;
            _setAccess(StremfinAccess.denied);
          }
          _retry = Timer(_retryDelay, () => unawaited(refreshAccess()));
          return;
        }
      }
    }
    try {
      final me = await _client.me();
      if (stale()) return;
      _signedOutSession = null;
      final before = _me;
      _me = me;
      final access = me.canDiscover
          ? StremfinAccess.allowed
          : StremfinAccess.denied;
      _deniedUnanswered = false;
      if (access == _access &&
          (before?.atLimit != me.atLimit || before?.mode != me.mode)) {
        // The same access, but reaching or leaving their limit changes what
        // a title's page offers.
        notifyListeners();
      }
      _setAccess(access);
    } on StremfinException catch (e) {
      if (stale()) return;
      if (e.isNoAccess) {
        _signedOutSession = e.status == 401 ? _client.sessionScope : null;
        _deniedUnanswered = false;
        _setAccess(StremfinAccess.denied);
      } else {
        // Switched off, home server not answering, no network: hidden until
        // it answers, if it never has.
        if (_access == StremfinAccess.unknown) {
          _deniedUnanswered = true;
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
    if (userId == _checkedFor) {
      // Kos TV: the same person signed in again after the service said
      // their session was no good: the new one is asked about.
      final signedOut = _signedOutSession;
      if (userId != null &&
          signedOut != null &&
          signedOut != _client.sessionScope) {
        _signedOutSession = null;
        unawaited(refreshAccess());
      }
      return;
    }
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
    // A check under way is the last person's: the next one starts afresh.
    _checking = null;
    _lists.clear();
    _loading.clear();
    _searches.clear();
    _searching.clear();
    _latest.clear();
    _signedOutSession = null;
    // Kos TV: a trailer read under way, or a refusal just checked, was the
    // last person's: the next one is asked afresh (the trailers found stay:
    // they are the same for everyone).
    _trailersLoading.clear();
    _trailersAccessCheckedAt = null;
    _availability.clear();
    _recommending.clear();
    _radioLoading.clear();
    // Kos TV: what Music kept is the last person's (their requests, their
    // «Para ti»): none of it is shown to the next one.
    _chartPages.clear();
    _recommended.clear();
    _radios.clear();
    _musicKept.clear();
    _musicLoading.clear();
    // On the device it is kept for one person only (see
    // StremfinMusicMemory); signed out, it goes.
    if (userId == null) unawaited(_client.musicMemory?.clear());
    _me = null;
    _deniedUnanswered = false;
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

  final Map<String, ({DateTime at, StremfinChartPage page})> _chartPages = {};

  /// How long a chart is kept here: the service refreshes them every few
  /// hours.
  static const _chartFor = Duration(minutes: 30);

  /// One chart's places, kept for half an hour. Kos TV: without what the
  /// person isn't shown ([cleanMusicSongs]).
  Future<StremfinChartPage> musicChart(
    String id, {
    String? country,
    bool remembered = false,
  }) async => _cleanChart(
    await _musicChart(id, country: country, remembered: remembered),
  );

  Future<StremfinChartPage> _musicChart(
    String id, {
    String? country,
    bool remembered = false,
  }) async {
    if (remembered) {
      return _client.musicChart(id, country: country, remembered: true);
    }
    final key = country == null ? id : '$country:$id';
    final kept = _chartPages[key];
    if (kept != null && DateTime.now().difference(kept.at) < _chartFor) {
      return kept.page;
    }
    // Kos TV: kept only for the person it was read for: another one signed
    // in meanwhile doesn't get it as theirs.
    final generation = _generation;
    final page = await _client.musicChart(id, country: country);
    if (generation == _generation) {
      _chartPages[key] = (at: DateTime.now(), page: page);
    }
    return page;
  }

  final Map<String, ({DateTime at, StremfinRecommendations found})>
  _recommended = {};

  /// Kos TV: «Para ti» being read, shared: the service allows few a minute.
  final Map<String, Future<StremfinRecommendations>> _recommending = {};

  /// «Para ti» for [artists]: the service keeps it an hour and allows few
  /// calls, so it is kept here as long. Kos TV: without what the person
  /// isn't shown ([cleanMusicSongs]).
  Future<StremfinRecommendations> musicRecommendations(
    List<String> artists, {
    List<String> genres = const [],
    bool remembered = false,
  }) async => _cleanRecommendations(
    await _musicRecommendations(
      artists,
      genres: genres,
      remembered: remembered,
    ),
  );

  Future<StremfinRecommendations> _musicRecommendations(
    List<String> artists, {
    List<String> genres = const [],
    bool remembered = false,
  }) async {
    final artistIds = await _artistIdsOf(artists, remembered: remembered);
    if (remembered) {
      return _client.musicRecommendations(
        artists,
        artistIds: artistIds,
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
    final pending = _recommending[key];
    if (pending != null) return pending;
    // Kos TV: kept only for the person it was read for.
    final generation = _generation;
    late final Future<StremfinRecommendations> future;
    future = _client
        .musicRecommendations(artists, artistIds: artistIds, genres: genres)
        .then((found) {
          if (generation == _generation) {
            _recommended[key] = (at: DateTime.now(), found: found);
          }
          return found;
        })
        .whenComplete(() {
          if (identical(_recommending[key], future)) _recommending.remove(key);
        });
    return _recommending[key] = future;
  }

  final Map<String, ({DateTime at, StremfinRadio found})> _radios = {};

  /// Kos TV: the radio being read, shared: it counts in the same few a
  /// minute as «Para ti».
  final Map<String, Future<StremfinRadio>> _radioLoading = {};

  /// Kos TV: when the service was last seen without the radio (a 404: one
  /// from before 1.93.0). Left alone that long, like the server plugin's
  /// missing routes, so updating it shows without restarting the app.
  DateTime? _radioMissingAt;
  static const _radioMissingFor = Duration(minutes: 30);

  /// Kos TV: «Descubrimiento semanal»: songs of Deezer's radio of [artists]
  /// (see [StremfinClient.musicRadio]). The service keeps the list an hour
  /// and allows few calls, so it is kept here as long. A service without it
  /// answers 404 (a [StremfinException] with that status), remembered for a
  /// while without asking again.
  ///
  /// Kos TV: [deezerArtistIds] are artists already known by Deezer's id (a
  /// song's that isn't at home, for its radio), asked for by it.
  Future<StremfinRadio> musicRadio(
    List<String> artists, {
    List<String> deezerArtistIds = const [],
    String? only,
    bool excludeSeedArtists = false,
    int? limit,
    bool remembered = false,
  }) async {
    final missingAt = _radioMissingAt;
    if (missingAt != null &&
        _clock().difference(missingAt) < _radioMissingFor) {
      throw const StremfinException(code: 'not_found', status: 404);
    }
    final artistIds = [
      ...deezerArtistIds,
      ...await _artistIdsOf(artists, remembered: remembered),
    ];
    Future<StremfinRadio> read({bool remembered = false}) => _client
        .musicRadio(
          artists,
          artistIds: artistIds,
          only: only,
          excludeSeedArtists: excludeSeedArtists,
          limit: limit,
          remembered: remembered,
        )
        .then(
          (found) {
            if (!remembered) _radioMissingAt = null;
            return found;
          },
          onError: (Object e, StackTrace stack) {
            if (e is StremfinException && e.status == 404) {
              _radioMissingAt = _clock();
            }
            Error.throwWithStackTrace(e, stack);
          },
        );
    if (remembered) return _cleanRadio(await read(remembered: true));
    final key =
        '${artists.join(',')}|${deezerArtistIds.join(',')}|$only|'
        '$excludeSeedArtists|$limit';
    final kept = _radios[key];
    if (kept != null &&
        _clock().difference(kept.at) < const Duration(hours: 1)) {
      return _cleanRadio(kept.found);
    }
    final pending = _radioLoading[key];
    if (pending != null) return _cleanRadio(await pending);
    // Kos TV: kept only for the person it was read for.
    final generation = _generation;
    late final Future<StremfinRadio> future;
    future = read()
        .then((found) {
          if (generation == _generation) {
            _radios[key] = (at: _clock(), found: found);
          }
          return found;
        })
        .whenComplete(() {
          if (identical(_radioLoading[key], future)) {
            _radioLoading.remove(key);
          }
        });
    _radioLoading[key] = future;
    return _cleanRadio(await future);
  }

  /// Kos TV: Deezer's id of each artist whose name has a comma in it («Tyler,
  /// The Creator»), which can't go among the names (see
  /// [StremfinClient.musicRecommendations]). Found by their name once and
  /// kept on the device with the Music page's answers; with [remembered],
  /// only what was kept (no call).
  final Map<String, String?> _artistIds = {};
  Future<void>? _artistIdsLoaded;
  static const _artistIdsNote = 'artist-ids';

  Future<List<String>> _artistIdsOf(
    List<String> artists, {
    bool remembered = false,
  }) async {
    final named = [
      for (final name in artists.take(10))
        if (name.contains(',')) name,
    ];
    if (named.isEmpty) return const [];
    await (_artistIdsLoaded ??= () async {
      try {
        final kept = await _client.rememberedMusicNote(_artistIdsNote);
        if (kept is Map) {
          for (final entry in kept.entries) {
            _artistIds.putIfAbsent(
              '${entry.key}',
              () => entry.value?.toString(),
            );
          }
        }
      } catch (_) {}
    }());
    var found = false;
    for (final name in named) {
      final key = name.toLowerCase();
      if (_artistIds.containsKey(key) || remembered) continue;
      try {
        final search = await _client.musicSearch(name, limit: 5);
        _artistIds[key] = search.artists
            .where((a) => a.name.toLowerCase() == key)
            .firstOrNull
            ?.deezerId;
        found = true;
      } on StremfinException {
        // Left out this time; asked again next time.
      }
    }
    if (found) _client.keepMusicNote(_artistIdsNote, Map.of(_artistIds));
    return [for (final name in named) ?_artistIds[name.toLowerCase()]];
  }

  /// Kos TV: the Music page's other answers (what the house asked for, the
  /// releases, more of the person's artist and their artists' news), kept
  /// a few minutes: the page is made anew each time it opens, and some of
  /// them are among the calls the service allows few of a minute.
  final Map<String, ({DateTime at, Object found})> _musicKept = {};
  final Map<String, Future<Object>> _musicLoading = {};
  static const _musicKeptFor = Duration(minutes: 10);

  /// [read] kept as [key] for [_musicKeptFor], only for the person it was
  /// read for, and shared while it is being read.
  Future<T> _musicKeep<T extends Object>(
    String key,
    Future<T> Function() read,
  ) {
    final kept = _musicKept[key];
    if (kept != null && _clock().difference(kept.at) < _musicKeptFor) {
      return Future.value(kept.found as T);
    }
    final pending = _musicLoading[key];
    if (pending != null) return pending.then((found) => found as T);
    final generation = _generation;
    late final Future<T> future;
    future = read()
        .then((found) {
          if (generation == _generation) {
            _musicKept[key] = (at: _clock(), found: found);
          }
          return found;
        })
        .whenComplete(() {
          if (identical(_musicLoading[key], future)) _musicLoading.remove(key);
        });
    _musicLoading[key] = future;
    return future;
  }

  /// The latest records of the artists [deezerIds].
  Future<List<StremfinAlbum>> musicArtistReleases(
    List<String> deezerIds, {
    bool remembered = false,
  }) => remembered
      ? _client.musicArtistReleases(deezerIds, remembered: true)
      : _musicKeep(
          'artist-releases:${deezerIds.join(',')}',
          () => _client.musicArtistReleases(deezerIds),
        );

  /// Music matching [query]: what the home server has and what it hasn't.
  /// What the Music page asks itself ([keep]) is kept a few minutes; what
  /// the person types is asked each time.
  ///
  /// Kos TV: without what the person isn't shown ([cleanMusicSongs]).
  Future<StremfinMusicSearch> musicSearch(
    String query, {
    bool keep = false,
    bool remembered = false,
  }) async => _cleanSearch(
    await _musicSearch(query, keep: keep, remembered: remembered),
  );

  Future<StremfinMusicSearch> _musicSearch(
    String query, {
    bool keep = false,
    bool remembered = false,
  }) => keep && !remembered
      ? _musicKeep(
          'search:${query.toLowerCase()}',
          () => _client.musicSearch(query, limit: 30, keep: true),
        )
      : _client.musicSearch(
          query,
          limit: 30,
          keep: keep,
          remembered: remembered,
        );

  Future<StremfinAlbumDetail> musicAlbum(String deezerId) =>
      _client.musicAlbum(deezerId);

  /// Kos TV: «Escuchar mientras llega»: where to hear a song that isn't at
  /// home (see [StremfinClient.musicListen]).
  Future<StremfinListen> musicListen(String deezerId) =>
      _client.musicListen(deezerId);

  /// Kos TV: a song that may sound soon, asked for in advance (see
  /// [StremfinClient.musicPrefetch]).
  Future<StremfinPrefetch> musicPrefetch(String deezerId) =>
      _client.musicPrefetch(deezerId);

  /// Kos TV: the radio of the song [deezerId] (see
  /// [StremfinClient.musicSongRadio]), without the songs the person isn't
  /// shown ([cleanMusicSongs]).
  Future<StremfinSongRadio> musicSongRadio(
    String deezerId, {
    String? only,
    int? limit,
  }) async {
    final found = await _client.musicSongRadio(
      deezerId,
      only: only,
      limit: limit,
    );
    return StremfinSongRadio(
      seed: found.seed,
      only: found.only,
      songs: cleanMusicSongs(found.songs),
      failed: found.failed,
    );
  }

  /// Kos TV: Deezer's song of each of [songs] (see
  /// [StremfinClient.musicSongsMatch]).
  Future<StremfinSongMatch> musicSongsMatch(
    List<({String title, String artist, String? isrc})> songs,
  ) => _client.musicSongsMatch(songs);

  /// Kos TV: the service's version as it last said (`/me`), or null.
  String? get serverVersion => _me?.serverVersion;

  /// Kos TV: the player's address for a [musicListen] `url`.
  String? musicListenAddress(String url) => _client.listenAddress(url);

  /// Kos TV: a song's page: whether it is at home now, its preview and the
  /// album to ask for to have it. An explicit one the person isn't shown
  /// ([cleanMusicSongs]) comes without its preview.
  Future<StremfinSongDetail> musicSong(String deezerId) async {
    final detail = await _client.musicSong(deezerId);
    if (kostvMusicSongAllowed(detail.song, hideExplicit: hidesExplicitMusic)) {
      return detail;
    }
    return StremfinSongDetail(
      song: detail.song.withoutPreview(),
      album: detail.album,
      albumInstead: detail.albumInstead,
      ask: detail.ask,
    );
  }

  /// An artist's page. What the Music page asks itself ([keep]) is kept a
  /// few minutes; the artist's own page asks each time.
  ///
  /// Kos TV: without the top songs the person isn't shown
  /// ([cleanMusicSongs]).
  Future<StremfinArtistDetail> musicArtist(
    String deezerId, {
    bool keep = false,
    bool remembered = false,
  }) async => _cleanArtist(
    await _musicArtist(deezerId, keep: keep, remembered: remembered),
  );

  Future<StremfinArtistDetail> _musicArtist(
    String deezerId, {
    bool keep = false,
    bool remembered = false,
  }) => keep && !remembered
      ? _musicKeep(
          'artist:$deezerId',
          () => _client.musicArtist(deezerId, keep: true),
        )
      : _client.musicArtist(deezerId, keep: keep, remembered: remembered);

  /// The Music page's own notes, kept with its answers on the device.
  void keepMusicNote(String name, Object value) =>
      _client.keepMusicNote(name, value);

  Future<Object?> rememberedMusicNote(String name) =>
      _client.rememberedMusicNote(name);

  /// What the house asked for most lately.
  Future<List<StremfinAlbum>> musicRequested({bool remembered = false}) =>
      remembered
      ? _client.musicRequested(limit: 20, remembered: true)
      : _musicKeep('requested', () => _client.musicRequested(limit: 20));

  /// The latest records of the artists the house follows.
  Future<List<StremfinAlbum>> musicReleases({bool remembered = false}) =>
      remembered
      ? _client.musicReleases(remembered: true)
      : _musicKeep('releases', _client.musicReleases);

  /// Kos TV: whether the requests service's explicit songs are hidden from
  /// the person now ([kostvMusicHidesExplicit]): their age limit (not read
  /// yet counts as one), this device's parental control or kids mode. Read
  /// on every answer, so switching person or turning one of them on or off
  /// applies at the next.
  bool get hidesExplicitMusic => kostvMusicHidesExplicit(
    limit: _readAgeLimit == null ? KostvAgeLimit.none : _ageLimit,
    parental: _parental(),
    kidsMode: _kidsMode?.call() ?? false,
  );

  /// Kos TV: whether the person's age limit is known (read from their
  /// account, or there is none to read): [hidesExplicitMusic] counts one
  /// not read yet as a limit.
  bool get musicAgeLimitKnown => _readAgeLimit == null || _ageLimit != null;

  /// Kos TV: [songs] without those the person isn't shown (explicit and not
  /// at home, see [kostvMusicSongAllowed]). Every music answer of the
  /// service goes through here, kept ones included.
  List<StremfinSong> cleanMusicSongs(List<StremfinSong> songs) =>
      kostvCleanMusicSongs(songs, hideExplicit: hidesExplicitMusic);

  StremfinChartPage _cleanChart(StremfinChartPage page) => StremfinChartPage(
    chart: page.chart,
    songs: cleanMusicSongs(page.songs),
    albums: page.albums,
  );

  StremfinRecommendations _cleanRecommendations(
    StremfinRecommendations found,
  ) => StremfinRecommendations(
    seeds: found.seeds,
    albums: found.albums,
    songs: cleanMusicSongs(found.songs),
  );

  StremfinRadio _cleanRadio(StremfinRadio found) => StremfinRadio(
    seeds: found.seeds,
    only: found.only,
    excludeSeedArtists: found.excludeSeedArtists,
    songs: cleanMusicSongs(found.songs),
    skipped: found.skipped,
    failed: found.failed,
  );

  StremfinMusicSearch _cleanSearch(StremfinMusicSearch found) =>
      StremfinMusicSearch(
        artists: found.artists,
        songs: cleanMusicSongs(found.songs),
        albums: found.albums,
        nextCursor: found.nextCursor,
      );

  StremfinArtistDetail _cleanArtist(StremfinArtistDetail found) =>
      StremfinArtistDetail(
        artist: found.artist,
        albums: found.albums,
        topSongs: cleanMusicSongs(found.topSongs),
        related: found.related,
        have: found.have,
        total: found.total,
      );

  /// Kos TV: bumped when the person asked for an album, so the Music page
  /// under the album's page shows it as asked for.
  final ValueNotifier<int> musicRequestsRevision = ValueNotifier(0);

  /// Asks for an album (a single's whole album, when it has one). The
  /// charts kept here are forgotten, since what they say of it changes.
  Future<StremfinRequestResult> createMusicRequest(String deezerId) async {
    try {
      final result = await _client.createMusicRequest(deezerId);
      final made = result.request;
      // Kos TV: what they asked for (or joined) is theirs.
      if (made != null) inbox.note(made, seen: true, own: true);
      // What the lists said of it changed («Pedir» → «Pedido»).
      _chartPages.clear();
      _recommended.clear();
      _radios.clear();
      _musicKept.clear();
      _musicLoading.clear();
      musicRequestsRevision.value++;
      return result;
    } finally {
      unawaited(refreshAccess());
    }
  }

  /// Kos TV: films' availability, as long as the service keeps it, and
  /// the ones being asked, shared.
  final Map<int, ({DateTime at, Future<StremfinAvailability> found})>
  _availability = {};
  static const availabilityLifetime = Duration(minutes: 10);

  /// Whether a film can be downloaded now and how fast. Kos TV: the service
  /// takes seconds to answer, so a film's page may ask for it along with
  /// the page itself and again once it knows it needs it: both get the same
  /// answer, asked once. A failed one isn't kept.
  Future<StremfinAvailability> movieAvailability(int tmdbId) {
    final kept = _availability[tmdbId];
    if (kept != null && _clock().difference(kept.at) < availabilityLifetime) {
      return kept.found;
    }
    final found = _client.movieAvailability(tmdbId);
    _availability[tmdbId] = (at: _clock(), found: found);
    found.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_availability[tmdbId]?.found, found)) {
          _availability.remove(tmdbId);
        }
      },
    );
    return found;
  }

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

  /// Kos TV: when a title's trailers last made the service be asked again
  /// whether the person is let in. Not let in, the banner would otherwise
  /// ask twice more for every slide it shows.
  DateTime? _trailersAccessCheckedAt;

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
    if (!isConfigured) return Future.value(const <StremfinTrailer>[]);
    // Kos TV: known to be refused and checked lately: answered at once,
    // before anything is kept as under way (see below).
    final checked = _trailersAccessCheckedAt;
    if (!isAllowed &&
        _access == StremfinAccess.denied &&
        checked != null &&
        DateTime.now().difference(checked) < trailersRetryAfter) {
      return Future.value(const <StremfinTrailer>[]);
    }
    final pending = _trailersLoading[key];
    if (pending != null) return pending;
    // Kos TV: kept before it can finish and let go only by itself, so one
    // that finished at once never stays behind with its answer.
    late final Future<List<StremfinTrailer>> future;
    future = _readTrailers(key, type, tmdbId).whenComplete(() {
      if (identical(_trailersLoading[key], future)) {
        _trailersLoading.remove(key);
      }
    });
    return _trailersLoading[key] = future;
  }

  Future<List<StremfinTrailer>> _readTrailers(
    String key,
    StremfinTitleType type,
    int tmdbId,
  ) async {
    try {
      if (!isAllowed) {
        // Kos TV: not known yet, it is asked now, so the first trailers
        // don't miss out; known to be refused, at most every so often (see
        // [trailers]).
        _trailersAccessCheckedAt = DateTime.now();
        // Kos TV: no longer than the trailers themselves may take, so a
        // service that doesn't answer doesn't hold up the trailer button.
        // The check carries on by itself.
        await refreshAccess().timeout(trailersTimeout);
        if (!isAllowed) return const <StremfinTrailer>[];
      }
      final read = await _client
          .trailers(type, tmdbId)
          .timeout(trailersTimeout);
      _trailersFailedAt = null;
      return _trailers[key] = read;
    } on StremfinException catch (e) {
      // A title it doesn't know is an answer, not a failure. Kos TV: kept
      // for the session as any other answer, so it isn't asked again on
      // every turn of the banner.
      if (e.status == 404) return _trailers[key] = const <StremfinTrailer>[];
      _trailersFailedAt = DateTime.now();
      return const <StremfinTrailer>[];
    } catch (_) {
      _trailersFailedAt = DateTime.now();
      return const <StremfinTrailer>[];
    }
  }

  /// One request as its page shows it, so the tray doesn't count what the
  /// person has just seen there as news. Kos TV: a page may show someone
  /// else's request; the tray only takes the person's own (see
  /// [StremfinInbox.note]).
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
      // Kos TV: what they asked for (or joined) is theirs.
      if (made != null) inbox.note(made, seen: true, own: true);
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
    final key = _titleKey(title);
    final before = _latest[key];
    _latest[key] = title;
    var inLists = false;
    var changed = before != null && _standing(before) != _standing(title);
    for (final entry in _lists.entries.toList()) {
      final items = entry.value.items;
      final index = items.indexWhere(
        (t) => t.type == title.type && t.tmdbId == title.tmdbId,
      );
      if (index < 0) continue;
      inLists = true;
      final now = apply(items[index]);
      if (_standing(now) == _standing(items[index])) continue;
      changed = true;
      _lists[entry.key] = (
        at: entry.value.at,
        items: [...items]..[index] = now,
      );
    }
    // Only when it changes something: a title read again as it was (the
    // spotlight's, as the focus rests on each card) mustn't rebuild every
    // row. One the lists don't have, first seen, the search may show.
    if (changed || (before == null && !inLists)) listsRevision.value++;
  }

  /// What a card shows of where a title stands: at home, on its way, asked
  /// for by whom.
  static String _standing(StremfinTitle t) {
    final l = t.library;
    final r = t.request;
    return [
      l.status.name,
      l.inLibrary,
      l.itemId,
      l.downloading,
      l.season,
      l.seasonEpisodesHave,
      l.seasonEpisodes,
      r?.id,
      r?.status,
      r?.statusLabel,
      r?.mine,
      r?.season,
      r?.episode,
      r?.direct,
      r?.requesters.join(','),
    ].join('|');
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _kidsModeChanges?.removeListener(_onKidsModeChanged);
    _lifecycle?.dispose();
    listsRevision.dispose();
    musicRequestsRevision.dispose();
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
