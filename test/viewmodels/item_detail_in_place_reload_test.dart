import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/user_data_sync.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _PluginSyncService extends Mock implements PluginSyncService {}

/// Kos TV: reading a page again in place (another version, back from the
/// player) and the refreshes that keep it up to date.
void main() {
  setUpAll(() => registerFallbackValue(_Client()));

  late _Client client;
  late _ItemsApi itemsApi;
  late _PluginSyncService pluginSync;

  setUp(() async {
    await GetIt.instance.reset();
    userDataSync.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    pluginSync = _PluginSyncService();
    GetIt.instance.registerSingleton<PluginSyncService>(pluginSync);
    when(() => pluginSync.collectionOrderSupported(any())).thenReturn(false);

    client = _Client();
    itemsApi = _ItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.baseUrl).thenReturn('http://server');
    when(() => itemsApi.getSpecialFeatures(any())).thenAnswer((_) async => []);
  });

  tearDown(() async {
    userDataSync.reset();
    await GetIt.instance.reset();
  });

  ItemDetailViewModel viewModel(String id) {
    final tmdb = TmdbRepository(client);
    final vm = ItemDetailViewModel(
      itemId: id,
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, tmdb),
      tmdbRepository: tmdb,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  void answerUserData(
    Future<Map<String, dynamic>> Function(List<String> ids) answer,
  ) {
    when(
      () => itemsApi.getItems(
        ids: any(named: 'ids'),
        fields: 'UserData',
        recursive: any(named: 'recursive'),
        limit: any(named: 'limit'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
      ),
    ).thenAnswer((call) => answer(call.namedArguments[#ids] as List<String>));
  }

  int userDataRequests() => verify(
    () => itemsApi.getItems(
      ids: any(named: 'ids'),
      fields: 'UserData',
      recursive: any(named: 'recursive'),
      limit: any(named: 'limit'),
      enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
    ),
  ).callCount;

  group('a movie read again', () {
    late Map<String?, Completer<Map<String, dynamic>>> answers;

    setUp(() {
      answers = {};
      when(
        () => itemsApi.getItem(
          'movie-1',
          mediaSourceId: any(named: 'mediaSourceId'),
        ),
      ).thenAnswer((call) {
        final version = call.namedArguments[#mediaSourceId] as String?;
        final pending = answers[version];
        if (pending != null) return pending.future;
        return Future.value({
          'Id': 'movie-1',
          'Type': 'Movie',
          'Name': 'Version ${version ?? 'default'}',
        });
      });
    });

    test(
      'another version stays on the page and asks nothing else again',
      () async {
        final vm = viewModel('movie-1');
        await vm.load();
        await settle();
        verify(() => itemsApi.getSpecialFeatures('movie-1')).called(1);

        final states = <ItemDetailState>[];
        vm.addListener(() => states.add(vm.state));
        await vm.load(mediaSourceId: 'b');
        await settle();

        expect(states, isNot(contains(ItemDetailState.loading)));
        expect(vm.state, ItemDetailState.ready);
        expect(vm.item?.name, 'Version b');
        verifyNever(() => itemsApi.getSpecialFeatures('movie-1'));
      },
    );

    test('two versions picked in a row end on the second, however the '
        'answers arrive', () async {
      final vm = viewModel('movie-1');
      await vm.load();
      await settle();

      final slow = answers['a'] = Completer<Map<String, dynamic>>();
      final first = vm.load(mediaSourceId: 'a');
      await vm.load(mediaSourceId: 'b');
      expect(vm.item?.name, 'Version b');

      slow.complete({'Id': 'movie-1', 'Type': 'Movie', 'Name': 'Version a'});
      await first;
      expect(vm.item?.name, 'Version b');
    });

    test('back from the player: the title read again in place', () async {
      answerUserData((_) async => {'Items': []});
      final vm = viewModel('movie-1');
      await vm.load();
      await settle();
      clearInteractions(itemsApi);

      final states = <ItemDetailState>[];
      vm.addListener(() => states.add(vm.state));
      await vm.refreshAfterPlayback();

      expect(states, isNot(contains(ItemDetailState.loading)));
      verify(
        () => itemsApi.getItem(
          'movie-1',
          mediaSourceId: any(named: 'mediaSourceId'),
        ),
      ).called(1);
      expect(userDataRequests(), 1);
      verifyNever(() => itemsApi.getSpecialFeatures(any()));
    });

    test(
      "a change to something this page doesn't show costs no request",
      () async {
        answerUserData((_) async => {'Items': []});
        final vm = viewModel('movie-1');
        await vm.load();
        await settle();

        userDataSync.publish('somewhere-else', {'IsFavorite': true});
        await vm.syncUserDataIfStale();
        verifyNever(
          () => itemsApi.getItems(
            ids: any(named: 'ids'),
            fields: 'UserData',
            recursive: any(named: 'recursive'),
            limit: any(named: 'limit'),
            enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
          ),
        );

        userDataSync.publish('movie-1', {'IsFavorite': true});
        await vm.syncUserDataIfStale();
        expect(userDataRequests(), 1);
      },
    );

    test('a refresh that failed is tried again the next time', () async {
      var fail = true;
      answerUserData((_) async {
        if (fail) throw Exception('connection dropped');
        return {'Items': []};
      });
      final vm = viewModel('movie-1');
      await vm.load();
      await settle();

      userDataSync.publish('movie-1', {'IsFavorite': true});
      await vm.syncUserDataIfStale();
      fail = false;
      await vm.syncUserDataIfStale();
      // Asked again, and done once it worked.
      await vm.syncUserDataIfStale();
      expect(userDataRequests(), 2);
    });
  });

  group('a season', () {
    setUp(() {
      when(
        () => itemsApi.getItem(
          'season-1',
          mediaSourceId: any(named: 'mediaSourceId'),
        ),
      ).thenAnswer(
        (_) async => {
          'Id': 'season-1',
          'Type': 'Season',
          'SeriesId': 'series-1',
        },
      );
    });

    Map<String, dynamic> episode(String id, int index) => {
      'Id': id,
      'Type': 'Episode',
      'SeriesId': 'series-1',
      'SeasonId': 'season-1',
      'ParentIndexNumber': 1,
      'IndexNumber': index,
    };

    test('back from the player its episodes show what was watched', () async {
      when(
        () => itemsApi.getEpisodes(
          'series-1',
          seasonId: 'season-1',
          fields: any(named: 'fields'),
        ),
      ).thenAnswer(
        (_) async => {
          'Items': [episode('e1', 1), episode('e2', 2)],
        },
      );
      answerUserData(
        (ids) async => {
          'Items': [
            if (ids.contains('e1'))
              {
                'Id': 'e1',
                'UserData': {'Played': true, 'PlaybackPositionTicks': 0},
              },
          ],
        },
      );
      final vm = viewModel('season-1');
      await vm.load();
      await settle();
      expect(vm.episodes.first.isPlayed, isFalse);

      await vm.refreshAfterPlayback();

      expect(vm.state, ItemDetailState.ready);
      expect(vm.episodes.first.isPlayed, isTrue);
    });

    test(
      'episodes that failed to load say so and can be asked again',
      () async {
        var fail = true;
        when(
          () => itemsApi.getEpisodes(
            'series-1',
            seasonId: 'season-1',
            fields: any(named: 'fields'),
          ),
        ).thenAnswer((_) async {
          if (fail) throw Exception('connection dropped');
          return {
            'Items': [episode('e1', 1)],
          };
        });
        final vm = viewModel('season-1');
        await vm.load();
        await settle();
        expect(vm.episodesFailed, isTrue);
        expect(vm.episodesLoaded, isTrue);

        fail = false;
        await vm.retryEpisodes();

        expect(vm.episodesFailed, isFalse);
        expect(vm.episodes.single.id, 'e1');
      },
    );
  });

  test("asking for a series' episodes while they're on the way waits for "
      'them', () async {
    when(
      () => itemsApi.getItem(
        'series-1',
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer((_) async => {'Id': 'series-1', 'Type': 'Series'});
    final episodes = Completer<Map<String, dynamic>>();
    when(() => itemsApi.getEpisodes('series-1', fields: any(named: 'fields')))
        .thenAnswer((_) => episodes.future);
    final vm = viewModel('series-1');
    await vm.load();

    final first = vm.loadAllSeriesEpisodes();
    var secondDone = false;
    final second = vm.loadAllSeriesEpisodes().then((_) => secondDone = true);
    await settle();
    expect(secondDone, isFalse);

    episodes.complete({
      'Items': [
        {'Id': 'e1', 'Type': 'Episode', 'ParentIndexNumber': 1},
      ],
    });
    await Future.wait([first, second]);
    expect(vm.seriesEpisodesLoaded, isTrue);
    verify(() => itemsApi.getEpisodes('series-1', fields: any(named: 'fields')))
        .called(1);
  });

  test('an order picked while the collection is scanned waits for that scan '
      'and stands over the saved one', () async {
    when(
      () => itemsApi.getItem(
        'boxset-1',
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer((_) async => {'Id': 'boxset-1', 'Type': 'BoxSet'});
    when(
      () => itemsApi.getItems(
        parentId: 'boxset-1',
        startIndex: 0,
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((_) async => {'Items': [], 'TotalRecordCount': 0});
    when(() => pluginSync.collectionOrderSupported(any())).thenReturn(true);
    when(() => pluginSync.fetchCustomCollectionOrder(any(), 'boxset-1'))
        .thenAnswer((_) async => ['m-b', 'm-a']);
    final scan = Completer<Map<String, dynamic>>();
    when(
      () => itemsApi.getItems(
        parentId: 'boxset-1',
        limit: 2000,
        fields: 'BasicSyncInfo',
      ),
    ).thenAnswer((_) => scan.future);
    when(
      () => itemsApi.getItems(
        ids: any(named: 'ids'),
        fields: 'PrimaryImageAspectRatio,BasicSyncInfo,People,Overview',
      ),
    ).thenAnswer((_) async => {'Items': []});

    final vm = viewModel('boxset-1');
    await vm.load();
    await settle();

    final picked = vm.setCollectionSort(CollectionSortOption.alphabetical);
    await settle();
    scan.complete({
      'Items': [
        {'Id': 'm-b', 'Type': 'Movie', 'Name': 'Beta'},
        {'Id': 'm-a', 'Type': 'Movie', 'Name': 'Alpha'},
      ],
    });
    await picked;
    await settle();

    verify(
      () => itemsApi.getItems(
        parentId: 'boxset-1',
        limit: 2000,
        fields: 'BasicSyncInfo',
      ),
    ).called(1);
    expect(vm.collectionSort, CollectionSortOption.alphabetical);
    expect(vm.flattenedIds, ['m-a', 'm-b']);
  });
}
