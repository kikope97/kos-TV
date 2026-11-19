import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/search_repository.dart';
import 'package:moonfin/data/services/user_data_sync.dart';
import 'package:moonfin/data/viewmodels/search_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockItemsApi extends Mock implements ItemsApi {}

void main() {
  late _MockClient client;
  late _MockItemsApi itemsApi;

  /// The item searches asked, by the types they named.
  late List<List<String>?> searches;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    client = _MockClient();
    itemsApi = _MockItemsApi();
    searches = [];
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.gamesApi).thenReturn(null);
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.baseUrl).thenReturn('http://server');
    when(
      () => itemsApi.getPersons(
        searchTerm: any(named: 'searchTerm'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
      ),
    ).thenAnswer((_) async => {'Items': const []});
  });

  tearDown(() async {
    userDataSync.reset();
    await GetIt.instance.reset();
  });

  void items(Map<String, List<String>> idsByType) {
    when(
      () => itemsApi.getItems(
        searchTerm: any(named: 'searchTerm'),
        parentId: any(named: 'parentId'),
        includeItemTypes: any(named: 'includeItemTypes'),
        excludeItemTypes: any(named: 'excludeItemTypes'),
        limit: any(named: 'limit'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
        studios: any(named: 'studios'),
      ),
    ).thenAnswer((invocation) async {
      final types =
          invocation.namedArguments[#includeItemTypes] as List<String>?;
      searches.add(types);
      return {
        'Items': [
          for (final MapEntry(key: type, value: ids) in idsByType.entries)
            if (types == null || types.contains(type))
              for (final id in ids)
                {
                  'Id': id,
                  'Type': type,
                  'Name': id,
                  'UserData': {'Played': false},
                },
        ],
      };
    });
  }

  void library(String collectionType) {
    when(
      () => itemsApi.getItem(
        any(),
        mediaSourceId: any(named: 'mediaSourceId'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((_) async => {'Id': 'lib', 'CollectionType': collectionType});
  }

  List<String> groupTypes(SearchViewModel vm) => [
    for (final group in vm.results) group.itemTypes.first,
  ];

  // Kos TV: «Buscar música» of a music library only looked for books and
  // audiobooks, so it never found anything.
  test('searching a music library finds its albums, artists and songs', () {
    fakeAsync((async) {
      library('music');
      items({
        'MusicAlbum': ['queen-album'],
        'Audio': ['queen-song'],
      });
      when(
        () => itemsApi.getArtists(
          parentId: 'lib',
          userId: any(named: 'userId'),
          sortBy: any(named: 'sortBy'),
          sortOrder: any(named: 'sortOrder'),
          startIndex: any(named: 'startIndex'),
          limit: any(named: 'limit'),
          recursive: any(named: 'recursive'),
          fields: any(named: 'fields'),
          nameStartsWith: any(named: 'nameStartsWith'),
          nameLessThan: any(named: 'nameLessThan'),
          isFavorite: any(named: 'isFavorite'),
        ),
      ).thenAnswer(
        (_) async => {
          'Items': [
            {'Id': 'a1', 'Name': 'Queen'},
            {'Id': 'a2', 'Name': 'Abba'},
          ],
        },
      );
      final vm = SearchViewModel(
        SearchRepository(client),
        client,
        scopedParentId: 'lib',
      );

      vm.searchImmediate('queen');
      async.flushMicrotasks();

      expect(vm.state, SearchState.ready);
      expect(groupTypes(vm), ['MusicAlbum', 'MusicArtist', 'Audio']);
      final artists = vm.results[1].items;
      expect(artists.map((a) => a.id), ['a1']);
      expect(artists.single.type, 'MusicArtist');
      vm.dispose();
    });
  });

  test('searching a book library still looks for books', () {
    fakeAsync((async) {
      library('books');
      items({
        'Book': ['dune'],
        'MusicAlbum': ['dune-album'],
      });
      final vm = SearchViewModel(
        SearchRepository(client),
        client,
        scopedParentId: 'lib',
      );

      vm.searchImmediate('dune');
      async.flushMicrotasks();

      expect(groupTypes(vm), ['Book']);
      vm.dispose();
    });
  });

  // Kos TV: pressing Search on the keyboard once the results were in asked
  // every question again.
  test('Search pressed after the results came asks nothing again', () {
    fakeAsync((async) {
      items({
        'Movie': ['dune'],
      });
      final vm = SearchViewModel(SearchRepository(client), client);
      var updates = 0;
      vm.addListener(() => updates++);

      vm.searchDebounced('dune');
      async.elapse(const Duration(seconds: 2));
      expect(vm.state, SearchState.ready);
      final asked = searches.length;
      final before = updates;

      vm.searchImmediate('dune');
      async.elapse(const Duration(seconds: 2));

      expect(searches, hasLength(asked));
      expect(vm.results.single.items.single.id, 'dune');
      // Still heard, so the screen moves on to the results.
      expect(updates, greaterThan(before));
      vm.dispose();
    });
  });

  test('a result watched meanwhile shows it', () {
    fakeAsync((async) {
      items({
        'Movie': ['dune'],
      });
      final vm = SearchViewModel(SearchRepository(client), client);
      vm.searchImmediate('dune');
      async.flushMicrotasks();
      expect(vm.results.single.items.single.isPlayed, isFalse);

      userDataSync.publish('dune', {'Played': true});

      expect(vm.results.single.items.single.isPlayed, isTrue);
      vm.dispose();
    });
  });
}
