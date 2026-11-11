import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/search_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/viewmodels/search_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockItemsApi extends Mock implements ItemsApi {}

class _MockPluginSync extends Mock implements PluginSyncService {}

Map<String, dynamic> _answer(List<String> itemIds) => {
  'Ready': true,
  'Items': [
    for (final id in itemIds) {'Id': id, 'Name': id, 'Type': 'Movie'},
  ],
};

void main() {
  group('SmartSearchResults.fromJson', () {
    test('reads library items', () {
      final results = SmartSearchResults.fromJson({
        'Ready': true,
        'Items': [
          {
            'Id': 'a1',
            'Name': 'The Mask',
            'Type': 'Movie',
            'ProductionYear': 1994,
            'ImageTags': {'Primary': 'tag'},
            'UserData': {'Played': true},
          },
          {'Id': 'p1', 'Name': 'Jim Carrey', 'Type': 'Person'},
        ],
      }, serverId: 'http://jf');

      expect([for (final i in results.items) i.type], ['Movie', 'Person']);
      expect(results.items.first.serverId, 'http://jf');
      expect(results.items.first.productionYear, 1994);
      expect(results.items.first.isPlayed, isTrue);
    });

    test('a server still building its index gives nothing', () {
      final results = SmartSearchResults.fromJson({
        'Ready': false,
        'Items': <Object>[],
      }, serverId: 'http://jf');

      expect(results.isEmpty, isTrue);
    });

    // The server may still send titles from outside the library; the app
    // leaves them out.
    test('leaves out titles from outside the library', () {
      final results = SmartSearchResults.fromJson({
        'Ready': true,
        'Items': <Object>[],
        'Seerr': [
          {'id': 1, 'mediaType': 'movie', 'title': 'Jumanji'},
        ],
      }, serverId: 'http://jf');

      expect(results.isEmpty, isTrue);
    });
  });

  group('SearchViewModel smart search', () {
    late _MockClient client;
    late _MockItemsApi itemsApi;
    late _MockPluginSync pluginSync;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
      client = _MockClient();
      itemsApi = _MockItemsApi();
      pluginSync = _MockPluginSync();
      when(() => client.itemsApi).thenReturn(itemsApi);
      when(() => client.gamesApi).thenReturn(null);
      when(() => client.baseUrl).thenReturn('http://jf');
      when(() => client.serverType).thenReturn(ServerType.jellyfin);
      when(() => pluginSync.smartSearchEnabled).thenReturn(true);
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
            {'Id': 'm1', 'Type': 'Movie', 'Name': 'm1'},
          ],
        },
      );
    });

    tearDown(() => GetIt.instance.reset());

    Completer<Map<String, dynamic>?> smartFor(String query) {
      final answer = Completer<Map<String, dynamic>?>();
      when(
        () => pluginSync.fetchSmartSearch(client, query),
      ).thenAnswer((_) => answer.future);
      return answer;
    }

    SearchViewModel newViewModel() => SearchViewModel(
      SearchRepository(client),
      client,
      pluginSync: pluginSync,
    );

    test('a slow answer fills in after the normal results are up', () {
      fakeAsync((async) {
        final answer = smartFor('jim carey mask');
        final vm = newViewModel();

        vm.searchImmediate('jim carey mask');
        async.elapse(const Duration(seconds: 2));

        expect(vm.state, SearchState.ready);
        expect(vm.smartResults.isEmpty, isTrue);

        answer.complete(_answer(['s1']));
        async.flushMicrotasks();

        expect(vm.smartResults.items.single.id, 's1');
        vm.dispose();
      });
    });

    test('an answer for an older query is ignored', () {
      fakeAsync((async) {
        final oldAnswer = smartFor('jim carey mask');
        smartFor('tom hanks island').complete(_answer(['s2']));
        final vm = newViewModel();

        vm.searchImmediate('jim carey mask');
        async.elapse(const Duration(seconds: 2));
        vm.searchImmediate('tom hanks island');
        async.elapse(const Duration(seconds: 2));
        oldAnswer.complete(_answer(['s1']));
        async.flushMicrotasks();

        expect(vm.smartResults.items.single.id, 's2');
        vm.dispose();
      });
    });

    test('a single word never asks the server', () {
      fakeAsync((async) {
        final vm = newViewModel();

        vm.searchImmediate('jumanji');
        async.elapse(const Duration(seconds: 2));

        expect(vm.state, SearchState.ready);
        verifyNever(() => pluginSync.fetchSmartSearch(client, any()));
        vm.dispose();
      });
    });
  });
}
