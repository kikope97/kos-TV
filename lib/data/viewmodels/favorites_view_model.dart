import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart' hide ImageType;

import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../util/network_errors.dart';
import '../models/aggregated_item.dart';
import '../services/blocked_content_gate.dart';
import '../services/moonbase_endpoint.dart';
import '../services/user_data_sync.dart';
import '../utils/blocked_ratings.dart';

enum FavoritesState { loading, ready, error }

/// The favourites, one row per kind.
///
/// Kos TV: the page is always rows. The grid view, the image type and
/// poster size, the focused item's extra ratings and Silo's watchlist went
/// with the pages that used them.
class FavoritesViewModel extends ChangeNotifier {
  final MediaServerClient _client;
  final UserPreferences _prefs;

  static const _rowLimit = 30;
  static const _prefKey = 'favorites';
  static const _browseFields =
      'Type,UserData,CommunityRating,OfficialRating,RunTimeTicks,ProductionYear,Status,ImageTags,BackdropImageTags,ParentBackdropItemId,ParentBackdropImageTags,CriticRating,MediaStreams';

  static const List<FavoriteTypeFilter> rowTypes = [
    FavoriteTypeFilter.movie,
    FavoriteTypeFilter.series,
    FavoriteTypeFilter.episode,
    FavoriteTypeFilter.collection,
    FavoriteTypeFilter.person,
    FavoriteTypeFilter.musicVideo,
    FavoriteTypeFilter.musicArtist,
    FavoriteTypeFilter.musicAlbum,
    FavoriteTypeFilter.audio,
  ];

  FavoritesState _state = FavoritesState.loading;
  FavoritesState get state => _state;

  Map<FavoriteTypeFilter, List<AggregatedItem>> _rowItems = {};
  Map<FavoriteTypeFilter, List<AggregatedItem>> get rowItems => _rowItems;

  late LibrarySortBy _sortBy;
  LibrarySortBy get sortBy => _sortBy;

  /// Kos TV: whether the favourites go by when they were marked (kept by
  /// the server plugin) rather than by [sortBy].
  late bool _byMarked;
  bool get byMarked => _byMarked && markedAvailable;

  /// Whether the server plugin keeps when favourites were marked.
  bool get markedAvailable =>
      _prefs.get(UserPreferences.kostvFavoritesAvailable);

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  late SortDirection _sortDirection;
  SortDirection get sortDirection => _sortDirection;

  Object? _error;
  Object? get error => _error;
  bool _isNetworkError = false;
  bool get isNetworkError => _isNetworkError;

  /// Rows are paged from what the server handed over rather than from what is
  /// on screen, because a page thinned by the ratings filter would otherwise
  /// rewind the cursor and ask for rows it already has.
  ///
  /// Kos TV: counted as the row was when read, the favourites taken off
  /// since included; [loadMoreForType] works out where the server's list
  /// now goes on.
  final Map<FavoriteTypeFilter, int> _rowFetchedCounts = {};

  final Map<FavoriteTypeFilter, int> _rowTotalCounts = {};
  final Set<FavoriteTypeFilter> _inFlightPagingRowTypes = {};

  /// Total number of favorites of [type] on the server, used for tab labels.
  /// Falls back to the number of items already loaded when unknown.
  int rowTotalCount(FavoriteTypeFilter type) =>
      _rowTotalCounts[type] ?? (_rowItems[type]?.length ?? 0);

  FavoritesViewModel({
    required MediaServerClient client,
    required UserPreferences prefs,
  }) : _client = client,
       _prefs = prefs {
    _sortBy = _prefs.get(UserPreferences.librarySortBy(_prefKey));
    _sortDirection = _prefs.get(UserPreferences.librarySortDirection(_prefKey));
    _byMarked = _prefs.get(UserPreferences.kostvFavoritesByMarked);
    userDataSync.addListener(_onUserDataChanged);
  }

  /// Repaints the watched ticks in place when something here is played or
  /// unfavourited, on this device or another one.
  void _onUserDataChanged() {
    var changed = false;

    Map<FavoriteTypeFilter, List<AggregatedItem>>? rows;
    _rowItems.forEach((type, items) {
      final patched = userDataSync.applyAll(items);
      if (identical(patched, items)) return;
      rows ??= Map.of(_rowItems);
      rows![type] = patched;
    });
    if (rows != null) {
      _rowItems = rows!;
      changed = true;
    }

    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _dio.close();
    userDataSync.removeListener(_onUserDataChanged);
    super.dispose();
  }

  /// Rows whose request failed in the last load.
  int _failedRows = 0;

  /// Kos TV: the rows whose last read failed, so a page of one row isn't
  /// thrown away because another row failed at the same time.
  final Set<FavoriteTypeFilter> _failedTypes = {};

  /// Kos TV: which load the answers belong to. A load started after them
  /// (the order changed twice quickly) wins, whichever answer comes last.
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    _state = FavoritesState.loading;
    _failedRows = 0;
    _failedTypes.clear();
    _rowItems = {};
    _rowTotalCounts.clear();
    _rowFetchedCounts.clear();
    notifyListeners();

    try {
      final results = await Future.wait(
        rowTypes.map((type) => _fetchRowItems(type, startIndex: 0)),
      );
      if (generation != _generation) return;
      final map = <FavoriteTypeFilter, List<AggregatedItem>>{};
      for (var i = 0; i < rowTypes.length; i++) {
        if (results[i].$1.isNotEmpty) {
          map[rowTypes[i]] = results[i].$1;
          _rowTotalCounts[rowTypes[i]] = results[i].$2;
        }
      }
      _rowItems = map;
      // Kos TV: nothing came and something failed: the server couldn't be
      // asked, which isn't the same as having no favourites.
      if (map.isEmpty && _failedRows > 0) {
        throw StateError('Favourites could not be read');
      }
      _state = FavoritesState.ready;
    } catch (e) {
      if (generation != _generation) return;
      _error = e;
      _isNetworkError = isNetworkException(e);
      _state = FavoritesState.error;
    }
    notifyListeners();
  }

  /// A page of [type] from [startIndex] of the server's list as it is now.
  /// [removed] is how many of the row were taken off since it was read,
  /// added back so [_rowFetchedCounts] goes on counting as the row was.
  Future<(List<AggregatedItem>, int)> _fetchRowItems(
    FavoriteTypeFilter type, {
    int startIndex = 0,
    int removed = 0,
  }) async {
    final generation = _generation;
    if (byMarked) {
      return _fetchByMarked(
        type,
        startIndex: startIndex,
        removed: removed,
        generation: generation,
      );
    }
    try {
      final sortValue = sortValueFor(type, _sortBy);
      final sortOrder = _sortDirection == SortDirection.ascending
          ? 'Ascending'
          : 'Descending';
      Map<String, dynamic> response;
      try {
        response = await _client.itemsApi.getItems(
          sortBy: sortValue,
          sortOrder: sortOrder,
          startIndex: startIndex,
          limit: _rowLimit,
          recursive: true,
          isFavorite: true,
          includeItemTypes: type.itemTypes,
          fields: _browseFields,
        );
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode ?? 0;
        if (statusCode < 500) rethrow;
        final fallbackSort = sortValue.toLowerCase().contains('isfolder')
            ? 'SortName'
            : sortValue;
        response = await _client.itemsApi.getItems(
          sortBy: fallbackSort,
          sortOrder: sortOrder,
          startIndex: startIndex,
          limit: _rowLimit,
          recursive: true,
          isFavorite: true,
          includeItemTypes: type.itemTypes,
          fields: _browseFields,
          enableTotalRecordCount: false,
        );
      }
      final rawItems = (response['Items'] as List?) ?? [];
      final items = rawItems
          .cast<Map<String, dynamic>>()
          .map(
            (raw) => AggregatedItem(
              id: raw['Id']?.toString() ?? '',
              serverId: _client.baseUrl,
              rawData: raw,
            ),
          )
          .toList();
      // Kos TV: only for the load still showing (the order may have changed
      // while it was on its way).
      if (generation == _generation) {
        _rowFetchedCounts[type] = startIndex + removed + rawItems.length;
      }
      final totalCount = response['TotalRecordCount'] as int? ?? items.length;
      return (await _withoutBlocked(type, items), totalCount);
    } catch (_) {
      _failedRows++;
      _failedTypes.add(type);
      return (const <AggregatedItem>[], 0);
    }
  }

  /// Kos TV: favourites of [type] newest marked first (or the other way),
  /// from the server plugin, which keeps when each one was marked.
  Future<(List<AggregatedItem>, int)> _fetchByMarked(
    FavoriteTypeFilter type, {
    required int startIndex,
    required int removed,
    required int generation,
  }) async {
    final types = type.itemTypes;
    if (types == null) return (const <AggregatedItem>[], 0);
    try {
      final ep = await moonbaseEndpoint(_client, _dio);
      if (ep == null) throw StateError('No server plugin');
      final response = await _dio.get<dynamic>(
        '${ep.base}/Moonfin/Kostv/Favorites',
        queryParameters: {
          'types': types.join(','),
          'start': startIndex,
          'limit': _rowLimit,
          'ascending': _sortDirection == SortDirection.ascending,
        },
        options: Options(headers: ep.headers),
      );
      final data = response.data;
      if (data is! Map) throw StateError('Unexpected answer');
      final rawItems = (data['Items'] as List?) ?? const [];
      final items = [
        for (final raw in rawItems.whereType<Map>())
          AggregatedItem(
            id: raw['Id']?.toString() ?? '',
            serverId: _client.baseUrl,
            rawData: raw.cast<String, dynamic>(),
          ),
      ];
      if (generation == _generation) {
        _rowFetchedCounts[type] = startIndex + removed + rawItems.length;
      }
      final total = data['TotalRecordCount'] as int? ?? items.length;
      return (await _withoutBlocked(type, items), total);
    } catch (_) {
      _failedRows++;
      _failedTypes.add(type);
      return (const <AggregatedItem>[], 0);
    }
  }

  /// What parental control lets through. Kos TV: an episode rarely carries
  /// a rating of its own, so it is judged by its series too, as the search
  /// does: a favourite episode of a blocked series shows neither its
  /// picture nor its name.
  static Future<List<AggregatedItem>> _withoutBlocked(
    FavoriteTypeFilter type,
    List<AggregatedItem> items,
  ) {
    final rated = withoutBlockedItems(items);
    return type == FavoriteTypeFilter.episode
        ? withoutBlockedSeriesItems(rated)
        : Future.value(rated);
  }

  /// Kos TV: favourites by when they were marked, newest first unless
  /// [direction] says otherwise.
  Future<void> setByMarked(SortDirection direction) async {
    if (_byMarked && _sortDirection == direction) return;
    _byMarked = true;
    _sortDirection = direction;
    await _prefs.set(UserPreferences.kostvFavoritesByMarked, true);
    await _prefs.set(UserPreferences.librarySortDirection(_prefKey), direction);
    await load();
  }

  /// Kos TV: what [type] is sorted by when [sortBy] is chosen. People have
  /// no premiere, runtime, plays or rating of their own, so they keep to
  /// their names, unless shuffled.
  @visibleForTesting
  static String sortValueFor(FavoriteTypeFilter type, LibrarySortBy sortBy) {
    if (type == FavoriteTypeFilter.person &&
        sortBy != LibrarySortBy.random &&
        sortBy != LibrarySortBy.name &&
        sortBy != LibrarySortBy.dateAdded) {
      return LibrarySortBy.name.apiValue;
    }
    return sortBy.apiValue;
  }

  Future<void> loadMoreForType(FavoriteTypeFilter type) async {
    final items = _rowItems[type];
    if (items == null || items.isEmpty) return;
    final total = _rowTotalCounts[type] ?? 0;
    final fetched = _rowFetchedCounts[type] ?? items.length;
    if (fetched >= total) return;
    if (_inFlightPagingRowTypes.contains(type)) return;

    _inFlightPagingRowTypes.add(type);
    final generation = _generation;
    _failedTypes.remove(type);
    try {
      // Kos TV: the favourites taken off since the row was read (here, in
      // the details or on another device) are no longer in the server's
      // list, which now goes on that much earlier: starting where it read
      // up to would skip as many.
      final removed = items.where((item) => !item.isFavorite).length;
      final (newItems, totalCount) = await _fetchRowItems(
        type,
        startIndex: (fetched - removed).clamp(0, fetched),
        removed: removed,
      );
      // Kos TV: a page of an earlier load (the order changed meanwhile)
      // isn't added to the new one; a page that failed leaves the count
      // as it was, so the next try can still bring the rest.
      if (generation != _generation) return;
      if (_failedTypes.remove(type)) return;
      // Counted as the row was read, as the fetched count is.
      final allCount = totalCount + removed;
      _rowTotalCounts[type] = allCount;

      // Kos TV: one marked meanwhile moves the list the other way, and
      // what was already read comes again: it isn't added twice.
      final current = _rowItems[type] ?? items;
      final seen = {for (final item in current) item.id};
      final fresh = [
        for (final item in newItems)
          if (seen.add(item.id)) item,
      ];
      if (fresh.isNotEmpty) {
        _rowItems[type] = [...current, ...fresh];
        notifyListeners();
      } else if ((_rowFetchedCounts[type] ?? 0) >= allCount) {
        _rowTotalCounts[type] = current.length;
      }
    } catch (_) {
    } finally {
      _inFlightPagingRowTypes.remove(type);
    }
  }

  Future<void> setSortBy(LibrarySortBy value) async {
    if (_sortBy == value) return;
    _sortBy = value;
    await _prefs.set(UserPreferences.librarySortBy(_prefKey), value);
    await load();
  }

  /// Kos TV: both at once, so the rows are read only once.
  Future<void> setSort(LibrarySortBy by, SortDirection direction) async {
    if (!_byMarked && _sortBy == by && _sortDirection == direction) return;
    if (_byMarked) {
      _byMarked = false;
      await _prefs.set(UserPreferences.kostvFavoritesByMarked, false);
    }
    _sortBy = by;
    _sortDirection = direction;
    await _prefs.set(UserPreferences.librarySortBy(_prefKey), by);
    await _prefs.set(UserPreferences.librarySortDirection(_prefKey), direction);
    await load();
  }

  Future<void> setSortDirection(SortDirection value) async {
    if (_sortDirection == value) return;
    _sortDirection = value;
    await _prefs.set(UserPreferences.librarySortDirection(_prefKey), value);
    await load();
  }

  Future<void> toggleSortDirection() => setSortDirection(
    _sortDirection == SortDirection.ascending
        ? SortDirection.descending
        : SortDirection.ascending,
  );
}
