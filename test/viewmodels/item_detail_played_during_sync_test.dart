import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
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

class _UserLibraryApi extends Mock implements UserLibraryApi {}

class _PluginSyncService extends Mock implements PluginSyncService {}

/// A server holding one movie.
class _ItemsApi extends Fake implements ItemsApi {
  Map<String, dynamic> userData = {
    'Played': false,
    'IsFavorite': false,
    'PlaybackPositionTicks': 0,
  };

  /// Holds back the answer to the next user data read until completed.
  Completer<void>? nextReadGate;

  int userDataReads = 0;

  @override
  Future<Map<String, dynamic>> getItem(
    String itemId, {
    String? fields,
    String? mediaSourceId,
  }) async => {
    'Id': itemId,
    'Name': 'Movie',
    'Type': 'Movie',
    'UserData': {...userData},
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final named = invocation.namedArguments;
    if (invocation.memberName == #getItems && named[#fields] == 'UserData') {
      userDataReads++;
      // Read when asked, answered when the gate opens.
      final ids = named[#ids] as List<String>? ?? const [];
      final items = [
        for (final id in ids)
          if (id == 'movie-1')
            {
              'Id': id,
              'UserData': {...userData},
            },
      ];
      final answer = {'Items': items, 'TotalRecordCount': items.length};
      final gate = nextReadGate;
      nextReadGate = null;
      return gate == null
          ? Future.value(answer)
          : gate.future.then((_) => answer);
    }
    if (invocation.memberName == #getItems) {
      return Future.value({'Items': const [], 'TotalRecordCount': 0});
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Client client;
  late _ItemsApi itemsApi;
  late _UserLibraryApi userLibraryApi;

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
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.userLibraryApi).thenReturn(userLibraryApi);
    when(() => client.baseUrl).thenReturn('http://server');
    when(() => userLibraryApi.markPlayed(any())).thenAnswer((_) async {
      itemsApi.userData = {...itemsApi.userData, 'Played': true};
    });
    when(() => userLibraryApi.unmarkPlayed(any())).thenAnswer((_) async {
      itemsApi.userData = {...itemsApi.userData, 'Played': false};
    });
  });

  tearDown(() {
    userDataSync.reset();
    return GetIt.instance.reset();
  });

  ItemDetailViewModel moviePage() {
    final tmdbRepository = TmdbRepository(client);
    return ItemDetailViewModel(
      itemId: 'movie-1',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, tmdbRepository),
      tmdbRepository: tmdbRepository,
    );
  }

  /// What Home and the lists show for the movie: the shared cache over the
  /// item as they last read it.
  bool playedElsewhere() => userDataSync
      .apply(
        AggregatedItem(
          id: 'movie-1',
          serverId: 'server',
          rawData: const {
            'Id': 'movie-1',
            'Type': 'Movie',
            'UserData': {'Played': false},
          },
        ),
      )
      .isPlayed;

  test('a read already out when a movie is marked watched is followed by '
      'another, so the shared cache keeps it watched', () async {
    final vm = moviePage();
    await vm.load();
    await pumpEventQueue();
    // Something on the page changed, so a pass reads it back, and its answer
    // (read before the toggle) is slow to arrive.
    userDataSync.publish('movie-1', {'IsFavorite': true});
    final gate = itemsApi.nextReadGate = Completer<void>();
    final earlierPass = vm.syncUserDataIfStale();
    expect(itemsApi.nextReadGate, isNull, reason: 'the read is out');
    final readsBefore = itemsApi.userDataReads;

    final toggle = vm.togglePlayed();
    await pumpEventQueue();
    gate.complete();
    await Future.wait([earlierPass, toggle]);
    await pumpEventQueue();

    expect(itemsApi.userDataReads, readsBefore + 1, reason: 'a second pass');
    expect(vm.item?.isPlayed, isTrue);
    expect(playedElsewhere(), isTrue);
  });

  test('marking a movie watched with no pass out reads nothing more', () async {
    final vm = moviePage();
    await vm.load();
    await pumpEventQueue();
    final readsBefore = itemsApi.userDataReads;

    await vm.togglePlayed();
    await pumpEventQueue();

    expect(itemsApi.userDataReads, readsBefore);
    expect(vm.item?.isPlayed, isTrue);
    expect(playedElsewhere(), isTrue);
  });
}
