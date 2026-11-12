import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../../l10n/current_app_localizations.dart';
import '../../util/accent_folding.dart';
import '../models/aggregated_item.dart';
import '../repositories/multi_server_repository.dart';
import '../repositories/search_repository.dart';
import '../services/plugin_sync_service.dart';
import '../services/stremfin/stremfin_client.dart';
import '../services/stremfin/stremfin_models.dart';
import '../services/stremfin/stremfin_service.dart';
import '../utils/blocked_ratings.dart';

class SearchResultGroup {
  final String title;
  final List<String> itemTypes;
  final List<AggregatedItem> items;

  const SearchResultGroup({
    required this.title,
    required this.itemTypes,
    this.items = const [],
  });

  SearchResultGroup copyWith({List<AggregatedItem>? items}) =>
      SearchResultGroup(title: title, itemTypes: itemTypes, items: items ?? this.items);
}

/// A single retro game that matched the query. Games live behind the Moonbase
/// plugin rather than the normal /Items search, so they carry their owning
/// [libraryId] (which [GameSummary] itself does not expose) for navigation.
class GameSearchResult {
  final String libraryId;
  final GameSummary game;

  const GameSearchResult({required this.libraryId, required this.game});
}

/// The library items Moonbase's natural-language search found.
class SmartSearchResults {
  final List<AggregatedItem> items;

  const SmartSearchResults({this.items = const []});

  static const empty = SmartSearchResults();

  bool get isEmpty => items.isEmpty;

  /// A server still building its first index answers with Ready false.
  factory SmartSearchResults.fromJson(
    Map<String, dynamic> json, {
    required String serverId,
  }) {
    if (json['Ready'] != true) return empty;
    final items = [
      for (final raw in (json['Items'] as List? ?? const []).whereType<Map>())
        raw.cast<String, dynamic>(),
    ];
    return SmartSearchResults(
      items: withoutBlockedItems([
        for (final data in items)
          if (!kostvIsMusic(data))
            AggregatedItem(
              id: data['Id']?.toString() ?? '',
              serverId: serverId,
              rawData: data,
            ),
      ]),
    );
  }
}

enum SearchState { idle, loading, ready, error }

class SearchViewModel extends ChangeNotifier {
  final SearchRepository _searchRepository;
  final MediaServerClient _client;
  final String? _scopedParentId;
  // Only set when search should cover every signed-in server.
  final MultiServerRepository? _multiServerRepository;
  final PluginSyncService? _pluginSync;

  /// Kos TV: the requests service, for «Para solicitar», when the person may
  /// use it.
  final StremfinService? _requests;

  SearchViewModel(
    this._searchRepository,
    this._client, {
    String? scopedParentId,
    MultiServerRepository? multiServerRepository,
    PluginSyncService? pluginSync,
    this._requests,
  }) : _multiServerRepository = multiServerRepository,
       _pluginSync = pluginSync,
       _scopedParentId =
           (scopedParentId != null && scopedParentId.isNotEmpty)
               ? scopedParentId
               : null {
    _requests?.listsRevision.addListener(_onRequestsChanged);
  }

  ImageApi imageApiFor(AggregatedItem item) =>
      _multiServerRepository?.getImageApiForServer(item.serverId) ??
      _client.imageApi;

  Map<String, String> _serverNames = const {};

  /// The server [item] came from, or null when only one server was searched.
  String? serverNameFor(AggregatedItem item) => _serverNames[item.serverId];

  SearchState _state = SearchState.idle;
  SearchState get state => _state;

  String _query = '';
  String get query => _query;

  List<SearchResultGroup> _results = const [];
  List<SearchResultGroup> get results => _results;

  List<GameSearchResult> _gameResults = const [];
  List<GameSearchResult> get gameResults => _gameResults;

  SmartSearchResults _smartResults = SmartSearchResults.empty;
  SmartSearchResults get smartResults => _smartResults;
  // The query [_smartResults] answered, so searching it again (on submit after
  // the debounce already ran) keeps the rows up until the new answer lands.
  String _smartQuery = '';

  // All games across every game library, fetched once per session and filtered
  // client-side since the plugin exposes no search endpoint.
  Future<List<GameSearchResult>>? _allGamesFuture;

  Object? _error;
  Object? get error => _error;

  // -------------------------------------------- Kos TV: «Para solicitar»

  /// Films and series that aren't at home and match the search, from the
  /// requests service, as they stand now.
  List<StremfinTitle> get requestable {
    final requests = _requests;
    if (requests == null) return _requestable;
    return [for (final title in _requestable) requests.latest(title)];
  }

  List<StremfinTitle> _requestable = const [];
  String? _requestableCursor;
  String _requestableQuery = '';
  bool _requestableLoading = false;

  /// Waiting for the person to stop typing before asking.
  bool _requestableWaiting = false;
  int _requestableRun = 0;
  Timer? _requestableTimer;

  /// There are more to read.
  bool get requestableHasMore => _requestableCursor != null;

  /// Asking, or about to.
  bool get requestableSearching => _requestableLoading || _requestableWaiting;

  bool get requestableLoading => _requestableLoading;

  /// The service's search is one of its costly calls (thirty a minute): it
  /// is asked once the person stops typing a while, or presses Search.
  static const requestableDelay = Duration(seconds: 1);
  static const requestableMinLength = 2;

  /// Pages read on when they only had what is at home and more after them.
  static const _requestableReadOn = 3;

  Timer? _debounceTimer;

  static const _debounceMs = 600;
  static const _resultLimit = 24;
  static const _globalFetchLimit = 240;
  // Some servers answer a people search far slower than everything else, so
  // the rest of the results only wait a moment for it and it's dropped if it
  // takes too long.
  static const _peopleGrace = Duration(seconds: 1);
  static const _peopleTimeout = Duration(seconds: 10);
  static const _smartTimeout = Duration(seconds: 10);

  // Counts searches, so people that answer late only fill in their own search.
  int _searchRun = 0;

  static List<SearchResultGroup> _bookSearchGroups() {
    final l10n = currentAppLocalizations();
    return [
      SearchResultGroup(title: l10n.books, itemTypes: const ['Book']),
      SearchResultGroup(title: l10n.audiobooks, itemTypes: const ['AudioBook']),
    ];
  }

  static List<SearchResultGroup> _searchGroups() {
    final l10n = currentAppLocalizations();
    return [
      SearchResultGroup(title: l10n.books, itemTypes: const ['Book']),
      SearchResultGroup(title: l10n.audiobooks, itemTypes: const ['AudioBook']),
      SearchResultGroup(title: l10n.movies, itemTypes: const ['Movie']),
      SearchResultGroup(title: l10n.series, itemTypes: const ['Series']),
      SearchResultGroup(title: l10n.seasons, itemTypes: const ['Season']),
      SearchResultGroup(title: l10n.episodes, itemTypes: const ['Episode']),
      SearchResultGroup(title: l10n.videos, itemTypes: const ['Video']),
      SearchResultGroup(title: l10n.trailers, itemTypes: const ['Trailer']),
      SearchResultGroup(title: l10n.programs, itemTypes: const ['Program']),
      SearchResultGroup(
        title: l10n.channels,
        itemTypes: const ['LiveTvChannel', 'TvChannel'],
      ),
      SearchResultGroup(title: l10n.playlists, itemTypes: const ['Playlist']),
      SearchResultGroup(title: l10n.photoAlbums, itemTypes: const ['PhotoAlbum']),
      SearchResultGroup(title: l10n.photos, itemTypes: const ['Photo']),
      SearchResultGroup(title: l10n.collections, itemTypes: const ['BoxSet']),
      SearchResultGroup(title: l10n.people, itemTypes: const ['Person']),
      SearchResultGroup(
        title: l10n.folders,
        itemTypes: const ['Folder', 'CollectionFolder', 'UserView'],
      ),
    ];
  }

  void searchDebounced(String query) {
    final trimmed = query.trim();
    if (trimmed == _query) return;
    _query = trimmed;

    _debounceTimer?.cancel();

    if (trimmed.isEmpty) {
      _results = const [];
      _gameResults = const [];
      _smartResults = SmartSearchResults.empty;
      _smartQuery = '';
      _state = SearchState.idle;
      _askRequestable('', now: true);
      notifyListeners();
      return;
    }

    _state = SearchState.loading;
    _askRequestable(trimmed, now: false);
    notifyListeners();

    _debounceTimer = Timer(
      const Duration(milliseconds: _debounceMs),
      () => _executeSearch(trimmed),
    );
  }

  void searchImmediate(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _query = trimmed;
    _debounceTimer?.cancel();
    _state = SearchState.loading;
    _askRequestable(trimmed, now: true);
    notifyListeners();
    _executeSearch(trimmed);
  }

  bool _wantsRequestable(String query) =>
      _requests != null &&
      _scopedParentId == null &&
      query.length >= requestableMinLength &&
      !query.toLowerCase().startsWith('studio:');

  /// Asks the requests service for [query], [now] or once typing rests.
  void _askRequestable(String query, {required bool now}) {
    _requestableTimer?.cancel();
    // Already asked (Search pressed after the pause): what came stays.
    if (query == _requestableQuery &&
        (_requestable.isNotEmpty || _requestableLoading)) {
      _requestableWaiting = false;
      return;
    }
    _requestableRun++;
    _requestable = const [];
    _requestableCursor = null;
    _requestableQuery = '';
    _requestableLoading = false;
    _requestableWaiting = _wantsRequestable(query);
    if (!_requestableWaiting) return;
    if (now) {
      unawaited(_readRequestable(query));
    } else {
      _requestableTimer = Timer(
        requestableDelay,
        () => unawaited(_readRequestable(query)),
      );
    }
  }

  /// The next page of «Para solicitar», when there is one.
  void loadMoreRequestable() {
    final cursor = _requestableCursor;
    if (_requestableLoading || cursor == null || _requestableQuery.isEmpty) {
      return;
    }
    unawaited(_readRequestable(_requestableQuery, cursor: cursor));
  }

  Future<void> _readRequestable(String query, {String? cursor}) async {
    final requests = _requests;
    final run = _requestableRun;
    // Searching right as the app opens: who the person is may still be on
    // its way.
    if (requests != null && requests.access == StremfinAccess.unknown) {
      await requests.refreshAccess();
      if (run != _requestableRun) return;
    }
    _requestableWaiting = false;
    if (requests == null || !requests.isAllowed) {
      notifyListeners();
      return;
    }
    _requestableQuery = query;
    _requestableLoading = true;
    notifyListeners();
    final found = <StremfinTitle>[];
    var next = cursor;
    try {
      for (var read = 0; read < _requestableReadOn; read++) {
        final page = await requests.search(query, cursor: next);
        if (run != _requestableRun) return;
        found.addAll(page.items);
        next = page.nextCursor;
        if (found.isNotEmpty || next == null) break;
      }
    } on StremfinException {
      // Busy or unreachable: the section stays out of the way.
      next = null;
    }
    if (run != _requestableRun) return;
    final seen = {for (final title in _requestable) _titleKey(title)};
    _requestable = [
      ..._requestable,
      for (final title in found)
        if (seen.add(_titleKey(title))) title,
    ];
    _requestableCursor = next;
    _requestableLoading = false;
    notifyListeners();
  }

  static String _titleKey(StremfinTitle title) =>
      '${title.type.apiValue}:${title.tmdbId}';

  /// A title was asked for or arrived meanwhile: its card shows it.
  void _onRequestsChanged() {
    if (_requestable.isNotEmpty) notifyListeners();
  }

  Future<void> _executeSearch(String query) async {
    if (query != _query) return;
    final run = ++_searchRun;

    try {
        final activeGroups = _scopedParentId != null
          ? _bookSearchGroups()
          : _searchGroups();
      final smartFuture = _fetchSmartResults(query);
      final gamesFuture = _scopedParentId != null
          ? Future.value(const <GameSearchResult>[])
          : _fetchGameResults(query);

      final (groups, peopleFuture) = _scopedParentId != null
          ? (
              await Future.wait(
                activeGroups.map((group) async {
                  final items = await _searchRepository.search(
                    query,
                    includeItemTypes: group.itemTypes,
                    parentId: _scopedParentId,
                    limit: _resultLimit,
                  );
                  return group.copyWith(items: items);
                }),
              ),
              Future.value(const <AggregatedItem>[]),
            )
          : await _buildGroupedGlobalResults(query, activeGroups);
      final games = await gamesFuture;

      // With nothing else to show, the results wait for smart search and
      // people instead of coming up empty.
      final hasLibraryResults =
          groups.any((g) => g.items.isNotEmpty) || games.isNotEmpty;
      final smart = hasLibraryResults ? null : await smartFuture;
      final hasOtherResults = hasLibraryResults || !(smart?.isEmpty ?? true);
      final people = hasOtherResults
          ? await peopleFuture
                .then<List<AggregatedItem>?>((found) => found)
                .timeout(_peopleGrace, onTimeout: () => null)
          : await peopleFuture;

      if (query != _query) return;

      _results = _withPeople(groups, people ?? const []);
      _gameResults = games;
      if (smart != null || _smartQuery != query) {
        _smartResults = smart ?? SmartSearchResults.empty;
        _smartQuery = query;
      }
      _state = SearchState.ready;
      if (smart == null) {
        unawaited(
          smartFuture.then((found) {
            if (found.isEmpty || run != _searchRun || query != _query) return;
            _smartResults = found;
            notifyListeners();
          }),
        );
      }
      if (people == null) {
        unawaited(
          peopleFuture.then((found) {
            if (found.isEmpty || run != _searchRun || query != _query) return;
            _results = _withPeople(groups, found);
            notifyListeners();
          }),
        );
      }
    } catch (e) {
      if (query != _query) return;
      _error = e;
      _state = SearchState.error;
    }
    notifyListeners();
  }

  /// Every group in order with the People group left empty, and the people
  /// search that fills it.
  Future<(List<SearchResultGroup>, Future<List<AggregatedItem>>)>
  _buildGroupedGlobalResults(
    String query,
    List<SearchResultGroup> activeGroups,
  ) async {
    // Looked up once before the searches start, so each of them reuses it
    // instead of looking the servers up again.
    final sessions = await _multiServerRepository?.getLoggedInServers();
    _serverNames = sessions != null && sessions.length > 1
        ? {for (final session in sessions) session.server.id: session.server.name}
        : const {};
    final peopleFuture = _searchEachServer(
      (repository) => repository
          .searchPeople(query, limit: _resultLimit)
          .timeout(_peopleTimeout),
      label: 'people search',
    ).then(_interleave).catchError((_) => <AggregatedItem>[]);
    final channelsFuture = _channelMatches(query);
    final perServerItems = await _searchEachServer(
      (repository) => repository.searchGroups(
        query,
        [
          for (final group in activeGroups)
            if (!group.itemTypes.contains('Person') &&
                !group.itemTypes.contains('LiveTvChannel'))
              group.itemTypes,
        ],
        perGroup: _resultLimit,
        limit: _globalFetchLimit,
      ),
      label: 'search',
    );
    final channels = await channelsFuture;

    final grouped = <SearchResultGroup>[];
    for (final group in activeGroups) {
      if (group.itemTypes.contains('Person')) {
        grouped.add(group);
        continue;
      }
      if (group.itemTypes.contains('LiveTvChannel')) {
        grouped.add(group.copyWith(items: channels));
        continue;
      }
      final matched = _interleave([
        for (final items in perServerItems)
          items
              .where(
                (item) =>
                    group.itemTypes.contains(item.type) &&
                    !kostvIsMusic(item.rawData),
              )
              .toList(),
      ]).take(_resultLimit).toList();
      grouped.add(group.copyWith(items: matched));
    }

    return (grouped, peopleFuture);
  }

  /// The groups that have something to show, with [people] in the People
  /// group.
  static List<SearchResultGroup> _withPeople(
    List<SearchResultGroup> groups,
    List<AggregatedItem> people,
  ) => [
    for (final group in groups)
      if (group.itemTypes.contains('Person'))
        group.copyWith(items: people.take(_resultLimit).toList())
      else
        group,
  ].where((g) => g.items.isNotEmpty).toList();

  Future<List<List<AggregatedItem>>> _searchEachServer(
    Future<List<AggregatedItem>> Function(SearchRepository repository) search, {
    required String label,
  }) async {
    final multiServer = _multiServerRepository;
    if (multiServer == null) return [await search(_searchRepository)];
    return multiServer.searchEachServer(search, label: label);
  }

  /// Takes one result from each server in turn, so every server keeps its own
  /// ranking and none crowds the others out of a capped group.
  static List<AggregatedItem> _interleave(List<List<AggregatedItem>> perServer) {
    final longest = perServer.fold(0, (most, items) => max(most, items.length));
    return [
      for (var i = 0; i < longest; i++)
        for (final items in perServer)
          if (i < items.length) items[i],
    ];
  }

  // The lineup is fetched once per search session and reused across queries,
  // since /LiveTv/Channels has no search parameter of its own.
  Future<List<AggregatedItem>>? _channelsFuture;

  Future<List<AggregatedItem>> _channelMatches(String query) async {
    // Channels come back wholesale rather than through a search the server
    // answers, so the folding it would have done has to happen here.
    final q = foldForSearch(query.trim());
    if (q.isEmpty || q.startsWith('studio:')) return const [];
    _channelsFuture ??= _searchEachServer(
      (repository) => repository.fetchLiveTvChannels(),
      label: 'channel lineup',
    ).then((perServer) => perServer.expand((channels) => channels).toList());
    try {
      final all = await _channelsFuture!;
      return all
          .where((c) => foldForSearch(c.name).contains(q))
          .take(_resultLimit)
          .toList();
    } catch (_) {
      // A server without Live TV shouldn't break search. Retry next query in
      // case the failure was transient.
      _channelsFuture = null;
      return const [];
    }
  }

  Future<SmartSearchResults> _fetchSmartResults(String query) async {
    final pluginSync = _pluginSync;
    if (pluginSync == null || !pluginSync.smartSearchEnabled) {
      return SmartSearchResults.empty;
    }
    if (_scopedParentId != null || query.toLowerCase().startsWith('studio:')) {
      return SmartSearchResults.empty;
    }
    // A single word is a title or a name, which the normal search handles.
    if (query.split(RegExp(r'\s+')).length < 2) return SmartSearchResults.empty;
    try {
      final data = await pluginSync
          .fetchSmartSearch(_client, query)
          .timeout(_smartTimeout);
      if (data == null) return SmartSearchResults.empty;
      return SmartSearchResults.fromJson(data, serverId: _client.baseUrl);
    } catch (_) {
      return SmartSearchResults.empty;
    }
  }

  Future<List<GameSearchResult>> _fetchGameResults(String query) async {
    // Games have no search endpoint, so the whole set is matched here and the
    // folding is this side's to do.
    final q = foldForSearch(query.trim());
    if (q.isEmpty || q.startsWith('studio:')) return const [];
    final gamesApi = _client.gamesApi;
    if (gamesApi == null) return const [];
    try {
      _allGamesFuture ??= _fetchAllGames(gamesApi);
      final all = await _allGamesFuture!;
      return all
          .where(
            (r) =>
                foldForSearch(r.game.title).contains(q) ||
                foldForSearch(r.game.fileName).contains(q),
          )
          .take(_resultLimit)
          .toList();
    } catch (_) {
      _allGamesFuture = null;
      return const [];
    }
  }

  Future<List<GameSearchResult>> _fetchAllGames(GamesApi gamesApi) async {
    final libraries = await gamesApi.getLibraries();
    final perLibrary = await Future.wait(
      libraries.map((library) async {
        final games = await gamesApi.getGames(library.id);
        return games.map(
          (game) => GameSearchResult(libraryId: library.id, game: game),
        );
      }),
    );
    return perLibrary.expand((results) => results).toList();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _requestableTimer?.cancel();
    _requestableRun++;
    _requests?.listsRevision.removeListener(_onRequestsChanged);
    // Keeps people that answer after the screen closed from landing on it.
    _searchRun++;
    super.dispose();
  }
}
