import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/search_repository.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/data/viewmodels/search_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services/stremfin/fake_stremfin_adapter.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockItemsApi extends Mock implements ItemsApi {}

/// Kos TV: the search's «Para solicitar» (what isn't at home, from the
/// requests service), and no music in the search.
void main() {
  late _MockClient client;
  late _MockItemsApi itemsApi;
  late List<Map<String, String>> searches;
  late List<Map<String, Object?>> found;
  late String? nextCursor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    client = _MockClient();
    itemsApi = _MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.gamesApi).thenReturn(null);
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(
      () => itemsApi.getPersons(
        searchTerm: any(named: 'searchTerm'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
      ),
    ).thenAnswer((_) async => {'Items': <Object>[]});
    searches = [];
    found = [
      {
        'type': 'movie',
        'tmdb_id': 1,
        'title': 'Cumbres',
        'library': {'status': 'missing', 'in_jellyfin': false},
      },
      {
        'type': 'series',
        'tmdb_id': 2,
        'title': 'Cumbres borrascosas',
        'library': {'status': 'missing', 'in_jellyfin': false},
      },
    ];
    nextCursor = null;
  });

  tearDown(() => GetIt.instance.reset());

  void homeHas(List<(String, String, String?)> items) {
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
    ).thenAnswer(
      (_) async => {
        'Items': [
          for (final (id, type, mediaType) in items)
            {'Id': id, 'Type': type, 'Name': id, 'MediaType': ?mediaType},
        ],
      },
    );
  }

  StremfinService requests() {
    late final FakeStremfinAdapter adapter;
    adapter = FakeStremfinAdapter.withMethod((method, path, sent) {
      if (path == '/me') {
        return (
          status: 200,
          body: {
            'user': {'name': 'Kiko'},
            'access': {'can_request': true, 'mode': 'direct'},
          },
          headers: const {},
        );
      }
      if (path == '/search') {
        searches.add(adapter.lastQuery);
        return (
          status: 200,
          body: {'items': found, 'next_cursor': nextCursor},
          headers: const {},
        );
      }
      return (status: 404, body: null, headers: const {});
    });
    return StremfinService(
      StremfinClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://requests.example.org/api/v1',
        token: () => 'token',
      ),
      watchLifecycle: false,
    )..onUserChanged('kiko');
  }

  /// Lets the calls answer.
  void settle(FakeAsync async) {
    for (var i = 0; i < 10; i++) {
      async.elapse(const Duration(milliseconds: 30));
    }
  }

  test('asks once typing rests a second, only for what isn\'t at home', () {
    fakeAsync((async) {
      homeHas([('m1', 'Movie', null)]);
      final service = requests();
      settle(async);
      final vm = SearchViewModel(
        SearchRepository(client),
        client,
        requests: service,
      );

      // Typed letter by letter: nothing asked while it goes on.
      for (final text in ['c', 'cu', 'cum', 'cumb', 'cumbres']) {
        vm.searchDebounced(text);
        async.elapse(const Duration(milliseconds: 300));
      }
      expect(searches, isEmpty);
      expect(vm.requestableSearching, isTrue);

      async.elapse(SearchViewModel.requestableDelay);
      settle(async);
      expect(searches, hasLength(1));
      expect(searches.single['q'], 'cumbres');
      expect(searches.single['only'], 'missing');
      expect(
        [for (final t in vm.requestable) t.title],
        ['Cumbres', 'Cumbres borrascosas'],
      );
      expect(vm.requestableSearching, isFalse);

      // Search pressed afterwards: what came stays, nothing asked again.
      vm.searchImmediate('cumbres');
      settle(async);
      expect(searches, hasLength(1));
      expect(vm.requestable, hasLength(2));

      vm.dispose();
      service.dispose();
    });
  });

  test('a single letter isn\'t asked about, and clearing clears it', () {
    fakeAsync((async) {
      homeHas([]);
      final service = requests();
      settle(async);
      final vm = SearchViewModel(
        SearchRepository(client),
        client,
        requests: service,
      );
      vm.searchImmediate('c');
      settle(async);
      expect(searches, isEmpty);
      expect(vm.requestableSearching, isFalse);

      vm.searchImmediate('cumbres');
      settle(async);
      expect(vm.requestable, hasLength(2));
      vm.searchDebounced('');
      expect(vm.requestable, isEmpty);

      vm.dispose();
      service.dispose();
    });
  });

  test('reads on with the cursor, and nothing twice', () {
    fakeAsync((async) {
      homeHas([]);
      nextCursor = '2.19';
      final service = requests();
      settle(async);
      final vm = SearchViewModel(
        SearchRepository(client),
        client,
        requests: service,
      );
      vm.searchImmediate('cumbres');
      settle(async);
      expect(vm.requestableHasMore, isTrue);

      found = [
        found.last,
        {
          'type': 'movie',
          'tmdb_id': 3,
          'title': 'Cumbres de hielo',
          'library': {'status': 'missing', 'in_jellyfin': false},
        },
      ];
      nextCursor = null;
      vm.loadMoreRequestable();
      settle(async);
      expect(searches.last['cursor'], '2.19');
      expect([for (final t in vm.requestable) t.tmdbId], [1, 2, 3]);
      expect(vm.requestableHasMore, isFalse);

      vm.dispose();
      service.dispose();
    });
  });

  test('a title asked for meanwhile shows as asked for', () {
    fakeAsync((async) {
      homeHas([]);
      final service = requests();
      settle(async);
      final vm = SearchViewModel(
        SearchRepository(client),
        client,
        requests: service,
      );
      vm.searchImmediate('cumbres');
      settle(async);
      var told = 0;
      vm.addListener(() => told++);

      service.noteTitle(
        vm.requestable.first.copyWith(
          request: () =>
              const StremfinRequestRef(id: 9, status: 'pending', mine: true),
        ),
      );
      expect(told, 1);
      expect(vm.requestable.first.request?.mine, isTrue);

      vm.dispose();
      service.dispose();
    });
  });

  test('without the requests service nothing is asked', () {
    fakeAsync((async) {
      homeHas([('m1', 'Movie', null)]);
      final vm = SearchViewModel(SearchRepository(client), client);
      vm.searchImmediate('cumbres');
      settle(async);
      expect(vm.requestable, isEmpty);
      expect(vm.requestableSearching, isFalse);
      vm.dispose();
    });
  });

  test('no music: no songs, albums, artists, music videos or playlists of '
      'songs', () {
    fakeAsync((async) {
      homeHas([
        ('m1', 'Movie', null),
        ('s1', 'Series', null),
        ('a1', 'Audio', null),
        ('al1', 'MusicAlbum', null),
        ('ar1', 'MusicArtist', null),
        ('mv1', 'MusicVideo', null),
        ('pl1', 'Playlist', 'Audio'),
        ('pl2', 'Playlist', 'Video'),
      ]);
      final vm = SearchViewModel(SearchRepository(client), client);
      vm.searchImmediate('cumbres');
      settle(async);
      final ids = [
        for (final group in vm.results)
          for (final item in group.items) item.id,
      ];
      expect(ids, containsAll(['m1', 's1', 'pl2']));
      expect(
        ids,
        isNot(anyOf(contains('a1'), contains('al1'), contains('ar1'))),
      );
      expect(ids, isNot(anyOf(contains('mv1'), contains('pl1'))));
      // And the server isn't asked for them in the first place.
      final excluded =
          verify(
                () => itemsApi.getItems(
                  searchTerm: any(named: 'searchTerm'),
                  parentId: any(named: 'parentId'),
                  includeItemTypes: any(named: 'includeItemTypes'),
                  excludeItemTypes: captureAny(named: 'excludeItemTypes'),
                  limit: any(named: 'limit'),
                  recursive: any(named: 'recursive'),
                  fields: any(named: 'fields'),
                  studios: any(named: 'studios'),
                ),
              ).captured.first
              as List<String>;
      expect(excluded, containsAll(['Audio', 'MusicAlbum', 'MusicArtist']));
      vm.dispose();
    });
  });

  test('smart search leaves music out too', () {
    final results = SmartSearchResults.fromJson({
      'Ready': true,
      'Items': [
        {'Id': 'm1', 'Name': 'Cumbres', 'Type': 'Movie'},
        {'Id': 'a1', 'Name': 'Cumbres', 'Type': 'Audio'},
        {'Id': 'al1', 'Name': 'Cumbres', 'Type': 'MusicAlbum'},
      ],
    }, serverId: 'http://jf');
    expect([for (final i in results.items) i.id], ['m1']);
  });
}
