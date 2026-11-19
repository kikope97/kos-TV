import 'package:flutter/material.dart';
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
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/kostv/kostv_episodes_section.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _ImageApi extends Mock implements ImageApi {}

class _PluginSyncService extends Mock implements PluginSyncService {}

/// Kos TV: a series whose episodes couldn't be read offers to try again,
/// rather than leaving the page without them.
void main() {
  late _Client client;
  late _ItemsApi itemsApi;
  late UserPreferences prefs;

  setUp(() async {
    await GetIt.instance.reset();
    userDataSync.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
    GetIt.instance.registerSingleton<PluginSyncService>(_PluginSyncService());

    client = _Client();
    itemsApi = _ItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(_ImageApi());
    when(() => client.baseUrl).thenReturn('http://server');
    when(
      () => itemsApi.getItem(
        'series-1',
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer(
      (_) async => {'Id': 'series-1', 'Type': 'Series', 'Name': 'Serie'},
    );
  });

  tearDown(() async {
    userDataSync.reset();
    await GetIt.instance.reset();
  });

  testWidgets('a failed read shows the error and Retry brings the episodes', (
    tester,
  ) async {
    var fail = true;
    when(() => itemsApi.getEpisodes('series-1', fields: any(named: 'fields')))
        .thenAnswer((_) async {
          if (fail) throw Exception('connection dropped');
          return {
            'Items': [
              {
                'Id': 'e1',
                'Type': 'Episode',
                'Name': 'Piloto',
                'SeriesId': 'series-1',
                'ParentIndexNumber': 1,
                'IndexNumber': 1,
              },
            ],
          };
        });
    final tmdb = TmdbRepository(client);
    final vm = ItemDetailViewModel(
      itemId: 'series-1',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, tmdb),
      tmdbRepository: tmdb,
    );
    addTearDown(vm.dispose);
    await tester.runAsync(vm.load);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => KostvEpisodesSection(
                viewModel: vm,
                prefs: prefs,
                landscape: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final l10n = lookupAppLocalizations(const Locale('es'));
    expect(find.text(l10n.errorLoadingEpisodes), findsOneWidget);

    fail = false;
    await tester.tap(find.text(l10n.retry));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.errorLoadingEpisodes), findsNothing);
    expect(find.text('Piloto'), findsOneWidget);
  });
}
