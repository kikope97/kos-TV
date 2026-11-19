import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/user_data_sync.dart';
import 'package:moonfin/data/viewmodels/favorites_view_model.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The favourite films as the server has them now, in its order.
class _Favorites implements ItemsApi {
  _Favorites(this.films);

  final List<String> films;
  final starts = <int>[];

  @override
  Future<Map<String, dynamic>> getItems({
    bool? serverWide,
    String? parentId,
    List<String>? ids,
    List<String>? includeItemTypes,
    List<String>? excludeItemTypes,
    String? sortBy,
    String? sortOrder,
    int? startIndex,
    int? limit,
    bool? recursive,
    String? searchTerm,
    String? fields,
    List<String>? personIds,
    List<String>? artistIds,
    List<String>? filters,
    List<String>? seriesStatus,
    String? nameStartsWith,
    String? nameLessThan,
    List<String>? genreIds,
    List<String>? genres,
    bool? isFavorite,
    bool? collapseBoxSetItems,
    bool? enableTotalRecordCount,
    String? enableImageTypes,
    int? imageTypeLimit,
    List<String>? tags,
    List<String>? studios,
    DateTime? minPremiereDate,
    String? maxOfficialRating,
    bool? hasParentalRating,
    String? anyProviderIdEquals,
    List<String>? officialRatings,
    List<int>? years,
    List<String>? videoTypes,
    List<String>? audioLanguages,
    List<String>? subtitleLanguages,
    bool? hasSubtitles,
    bool? hasTrailer,
    bool? hasSpecialFeature,
    bool? hasThemeSong,
    bool? hasThemeVideo,
    bool? isHd,
    bool? is4K,
    bool? is3D,
  }) async {
    if (includeItemTypes == null || !includeItemTypes.contains('Movie')) {
      return {'Items': const <dynamic>[], 'TotalRecordCount': 0};
    }
    final start = startIndex ?? 0;
    starts.add(start);
    return {
      'TotalRecordCount': films.length,
      'Items': [
        for (final id in films.skip(start).take(limit ?? 30))
          {
            'Id': id,
            'Name': id,
            'Type': 'Movie',
            'UserData': {'IsFavorite': true},
          },
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements MediaServerClient {
  _Client(this.itemsApi);

  @override
  final ItemsApi itemsApi;

  @override
  String get baseUrl => 'http://server';

  @override
  String? get userId => 'user';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late UserPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
  });

  tearDown(userDataSync.reset);

  List<String> shown(FavoritesViewModel vm) => [
    for (final item in vm.rowItems[FavoriteTypeFilter.movie]!)
      if (item.isFavorite) item.id,
  ];

  // Kos TV: the next page started where the row had read up to, on a
  // server list that had already lost the one taken off: the film after
  // the page never showed.
  test('a favourite taken off before the next page skips nothing', () async {
    final server = _Favorites([for (var i = 0; i < 45; i++) 'f$i']);
    final vm = FavoritesViewModel(client: _Client(server), prefs: prefs);
    addTearDown(vm.dispose);
    await vm.load();
    expect(shown(vm), hasLength(30));
    expect(vm.rowTotalCount(FavoriteTypeFilter.movie), 45);

    // Taken off from the card's menu: the server and the row learn of it.
    server.films.remove('f5');
    userDataSync.publish('f5', {'IsFavorite': false});

    await vm.loadMoreForType(FavoriteTypeFilter.movie);
    expect(server.starts.last, 29);
    expect(shown(vm), [
      for (var i = 0; i < 45; i++)
        if (i != 5) 'f$i',
    ]);
    // Nothing more to read, and the count is what is left.
    expect(vm.rowTotalCount(FavoriteTypeFilter.movie), 45);
    await vm.loadMoreForType(FavoriteTypeFilter.movie);
    expect(server.starts, hasLength(2));
  });

  test('one marked meanwhile, newest first, comes in once', () async {
    final server = _Favorites([for (var i = 0; i < 45; i++) 'f$i']);
    final vm = FavoritesViewModel(client: _Client(server), prefs: prefs);
    addTearDown(vm.dispose);
    await vm.load();

    // Marked on another device: first in the server's list, so the next
    // page brings again the last one already shown.
    server.films.insert(0, 'new');

    await vm.loadMoreForType(FavoriteTypeFilter.movie);
    final ids = shown(vm);
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, containsAll([for (var i = 0; i < 45; i++) 'f$i']));
  });
}
