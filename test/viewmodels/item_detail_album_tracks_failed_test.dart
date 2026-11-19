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

/// Kos TV: an album whose songs fail to load says so, and reads them again.
void main() {
  late _Client client;
  late _ItemsApi itemsApi;
  var fail = true;

  setUp(() async {
    fail = true;
    await GetIt.instance.reset();
    userDataSync.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    GetIt.instance.registerSingleton<PluginSyncService>(_PluginSyncService());

    client = _Client();
    itemsApi = _ItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.baseUrl).thenReturn('http://server');
    when(
      () => itemsApi.getItem(
        'album-1',
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer(
      (_) async => {'Id': 'album-1', 'Type': 'MusicAlbum', 'Name': 'Brisa'},
    );
    when(
      () => itemsApi.getItems(
        parentId: 'album-1',
        includeItemTypes: any(named: 'includeItemTypes'),
        sortBy: any(named: 'sortBy'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((_) async {
      if (fail) throw Exception('no network');
      return {
        'Items': [
          {'Id': 'song-1', 'Type': 'Audio', 'Name': 'Verano'},
        ],
      };
    });
  });

  tearDown(() async {
    userDataSync.reset();
    await GetIt.instance.reset();
  });

  test('the songs failing is told apart from an empty album', () async {
    final vm = ItemDetailViewModel(
      itemId: 'album-1',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, TmdbRepository(client)),
      tmdbRepository: TmdbRepository(client),
    );
    addTearDown(vm.dispose);
    await vm.load();
    // The songs come after the page itself.
    await pumpEventQueue();
    expect(vm.tracks, isEmpty);
    expect(vm.tracksFailed, isTrue);

    fail = false;
    await vm.retryTracks();
    expect(vm.tracksFailed, isFalse);
    expect(vm.tracks.single.id, 'song-1');
  });
}
