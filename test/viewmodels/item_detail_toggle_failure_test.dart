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

class _UserLibraryApi extends Mock implements UserLibraryApi {}

class _PluginSyncService extends Mock implements PluginSyncService {}

/// Kos TV: the page's watched and favourite toggles go back to what the
/// server holds when it doesn't take them, and say so.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Client client;
  late _ItemsApi itemsApi;
  late _UserLibraryApi userLibraryApi;
  late Map<String, dynamic> itemData;

  setUp(() async {
    await GetIt.instance.reset();
    userDataSync.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    GetIt.instance.registerSingleton<PluginSyncService>(_PluginSyncService());
    client = _Client();
    itemsApi = _ItemsApi();
    userLibraryApi = _UserLibraryApi();
    itemData = {
      'Id': 'movie-1',
      'Type': 'Movie',
      'UserData': {'Played': false, 'IsFavorite': false},
    };
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.userLibraryApi).thenReturn(userLibraryApi);
    when(() => client.baseUrl).thenReturn('http://server');
    when(
      () => itemsApi.getItem(
        'movie-1',
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer((_) async => Map<String, dynamic>.from(itemData));
  });

  tearDown(() async {
    userDataSync.reset();
    await GetIt.instance.reset();
  });

  ItemDetailViewModel createViewModel() {
    final tmdb = TmdbRepository(client);
    return ItemDetailViewModel(
      itemId: 'movie-1',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, tmdb),
      tmdbRepository: tmdb,
    );
  }

  test('a refused watched mark goes back and is reported', () async {
    final vm = createViewModel();
    addTearDown(vm.dispose);
    await vm.load();
    final failures = <DetailActionFailure>[];
    vm.onActionFailed = failures.add;
    final request = Completer<void>();
    when(() => userLibraryApi.markPlayed('movie-1'))
        .thenAnswer((_) => request.future);

    final toggle = vm.togglePlayed();
    expect(vm.item?.isPlayed, isTrue);
    request.completeError(Exception('HTTP 403'));
    await toggle;

    expect(vm.item?.isPlayed, isFalse);
    expect(failures, [DetailActionFailure.markPlayed]);
  });

  test('a failed unwatched mark says so with its own notice', () async {
    itemData = {
      'Id': 'movie-1',
      'Type': 'Movie',
      'UserData': {'Played': true},
    };
    final vm = createViewModel();
    addTearDown(vm.dispose);
    await vm.load();
    final failures = <DetailActionFailure>[];
    vm.onActionFailed = failures.add;
    when(() => userLibraryApi.unmarkPlayed('movie-1'))
        .thenThrow(Exception('no connection'));

    await vm.togglePlayed();

    expect(vm.item?.isPlayed, isTrue);
    expect(failures, [DetailActionFailure.markUnplayed]);
  });

  test('a second watched tap while one is on its way is ignored', () async {
    final vm = createViewModel();
    addTearDown(vm.dispose);
    await vm.load();
    final request = Completer<void>();
    when(() => userLibraryApi.markPlayed('movie-1'))
        .thenAnswer((_) => request.future);

    final first = vm.togglePlayed();
    await vm.togglePlayed();
    expect(vm.item?.isPlayed, isTrue);
    verifyNever(() => userLibraryApi.unmarkPlayed(any()));

    itemData = {
      'Id': 'movie-1',
      'Type': 'Movie',
      'UserData': {'Played': true},
    };
    request.complete();
    await first;
    expect(vm.item?.isPlayed, isTrue);
  });

  test(
    'a reload failing after the mark went through is not a failure',
    () async {
      final vm = createViewModel();
      addTearDown(vm.dispose);
      await vm.load();
      final failures = <DetailActionFailure>[];
      vm.onActionFailed = failures.add;
      when(() => userLibraryApi.markPlayed('movie-1')).thenAnswer((_) async {});
      when(
        () => itemsApi.getItem(
          'movie-1',
          mediaSourceId: any(named: 'mediaSourceId'),
        ),
      ).thenThrow(Exception('connection dropped'));

      await vm.togglePlayed();

      expect(vm.item?.isPlayed, isTrue);
      expect(failures, isEmpty);
    },
  );

  test('a refused favourite goes back and is reported', () async {
    final vm = createViewModel();
    addTearDown(vm.dispose);
    await vm.load();
    final failures = <DetailActionFailure>[];
    vm.onActionFailed = failures.add;
    when(() => userLibraryApi.markFavorite('movie-1'))
        .thenThrow(Exception('HTTP 401'));

    await vm.toggleFavorite();

    expect(vm.item?.isFavorite, isFalse);
    expect(failures, [DetailActionFailure.favorite]);
  });

  test('a favourite that goes through says nothing', () async {
    final vm = createViewModel();
    addTearDown(vm.dispose);
    await vm.load();
    final failures = <DetailActionFailure>[];
    vm.onActionFailed = failures.add;
    when(() => userLibraryApi.markFavorite('movie-1')).thenAnswer((_) async {});
    itemData = {
      'Id': 'movie-1',
      'Type': 'Movie',
      'UserData': {'IsFavorite': true},
    };

    await vm.toggleFavorite();

    expect(vm.item?.isFavorite, isTrue);
    expect(failures, isEmpty);
  });

  test('a failure after the page closed is still reported', () async {
    final vm = createViewModel();
    await vm.load();
    final failures = <DetailActionFailure>[];
    vm.onActionFailed = failures.add;
    final request = Completer<void>();
    when(() => userLibraryApi.markPlayed('movie-1'))
        .thenAnswer((_) => request.future);

    final toggle = vm.togglePlayed();
    vm.dispose();
    request.completeError(Exception('no connection'));
    await toggle;

    expect(failures, [DetailActionFailure.markPlayed]);
  });
}
