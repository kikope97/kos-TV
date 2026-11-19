import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:moonfin/ui/screens/detail/person_filmography_failed.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _ImageApi extends Mock implements ImageApi {}

class _Tmdb extends Mock implements TmdbRepository {}

class _PluginSyncService extends Mock implements PluginSyncService {}

/// Kos TV: a person whose titles couldn't be read says so, with a retry the
/// remote can reach, rather than a page with no filmography and no word.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Client client;
  late _ItemsApi itemsApi;
  late bool fail;

  setUp(() async {
    await GetIt.instance.reset();
    userDataSync.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    final pluginSync = _PluginSyncService();
    when(() => pluginSync.tmdbPersonLinksAvailable).thenReturn(false);
    GetIt.instance.registerSingleton<PluginSyncService>(pluginSync);

    client = _Client();
    itemsApi = _ItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(_ImageApi());
    when(() => client.baseUrl).thenReturn('http://server');
    when(
      () => itemsApi.getItem(
        'person-1',
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer(
      (_) async => {'Id': 'person-1', 'Type': 'Person', 'Name': 'Ana'},
    );
    fail = true;
    when(
      () => itemsApi.getItems(
        personIds: any(named: 'personIds'),
        includeItemTypes: any(named: 'includeItemTypes'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((invocation) async {
      if (fail) throw Exception('connection dropped');
      final types =
          invocation.namedArguments[#includeItemTypes] as List<String>;
      return {
        'Items': [
          if (types.contains('Movie'))
            {'Id': 'm1', 'Type': 'Movie', 'Name': 'La película'},
        ],
      };
    });
  });

  tearDown(() async {
    userDataSync.reset();
    await GetIt.instance.reset();
  });

  ItemDetailViewModel createViewModel() {
    final tmdb = _Tmdb();
    when(() => tmdb.getPersonAccounts(any())).thenAnswer((_) async => null);
    return ItemDetailViewModel(
      itemId: 'person-1',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, tmdb),
      tmdbRepository: tmdb,
    );
  }

  test('the error stays up while it tries again, and goes once in', () async {
    final vm = createViewModel();
    addTearDown(vm.dispose);
    await vm.load();
    // The filmography is read after the page is up, not awaited by load().
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(vm.filmographyFailed, isTrue);
    expect(showsFilmographyFailure(vm), isTrue);

    // Failing again: never cleared on the way, so the button stays put.
    final seen = <bool>[];
    void listener() => seen.add(vm.filmographyFailed);
    vm.addListener(listener);
    await vm.retryFilmography();
    expect(seen, everyElement(isTrue));
    expect(vm.filmographyFailed, isTrue);

    fail = false;
    await vm.retryFilmography();
    vm.removeListener(listener);
    expect(vm.filmographyFailed, isFalse);
    expect(showsFilmographyFailure(vm), isFalse);
    expect(vm.filmographyMovies.map((i) => i.id), ['m1']);
  });

  testWidgets('Retry with the remote reads the titles and hands the focus on', (
    tester,
  ) async {
    final vm = createViewModel();
    addTearDown(vm.dispose);
    await tester.runAsync(vm.load);
    final retryNode = FocusNode();
    addTearDown(retryNode.dispose);
    final after = FocusNode();
    addTearDown(after.dispose);
    var recovered = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: vm,
            builder: (context, _) => Column(
              children: [
                if (showsFilmographyFailure(vm))
                  PersonFilmographyFailed(
                    viewModel: vm,
                    focusNode: retryNode,
                    onRecovered: () {
                      recovered++;
                      after.requestFocus();
                    },
                  )
                else
                  Focus(focusNode: after, child: const Text('La película')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final l10n = lookupAppLocalizations(const Locale('es'));
    expect(find.text(l10n.failedToLoad), findsOneWidget);
    expect(find.text(l10n.retry), findsOneWidget);

    retryNode.requestFocus();
    await tester.pump();
    expect(retryNode.hasFocus, isTrue);

    fail = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.failedToLoad), findsNothing);
    expect(find.text('La película'), findsOneWidget);
    expect(recovered, 1);
    expect(after.hasFocus, isTrue);
  });

  testWidgets('a tap tries again too', (tester) async {
    final vm = createViewModel();
    addTearDown(vm.dispose);
    await tester.runAsync(vm.load);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: vm,
            builder: (context, _) => showsFilmographyFailure(vm)
                ? PersonFilmographyFailed(viewModel: vm)
                : const Text('done'),
          ),
        ),
      ),
    );
    await tester.pump();

    fail = false;
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.retry));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.text('done'), findsOneWidget);
  });
}
