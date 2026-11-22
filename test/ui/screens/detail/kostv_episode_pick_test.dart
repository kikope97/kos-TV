import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/user_data_sync.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/item_detail_screen.dart';
import 'package:moonfin/ui/screens/detail/kostv/kostv_episodes_section.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _ImageApi extends Mock implements ImageApi {}

class _UserLibraryApi extends Mock implements UserLibraryApi {}

class _PluginSyncService extends Mock implements PluginSyncService {}

class _Mutations extends Mock implements ItemMutationRepository {}

Map<String, dynamic> _episode(String id, int number, {int? positionTicks}) => {
  'Id': id,
  'Type': 'Episode',
  'Name': 'Episodio $number',
  'SeriesId': 'series-1',
  'SeasonId': 'season-1',
  'ParentIndexNumber': 1,
  'IndexNumber': number,
  'RunTimeTicks': 30 * 60 * 10000000,
  'UserData': {'PlaybackPositionTicks': ?positionTicks},
};

/// Kos TV: on a series page an episode plays when picked (OK, a click or a
/// tap), its own page a menu or the ⓘ away; with the remote the focused
/// card wears a white frame.
void main() {
  late _Client client;
  late _ItemsApi itemsApi;
  late UserPreferences prefs;
  final l10n = lookupAppLocalizations(const Locale('es'));

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
    when(() => client.userLibraryApi).thenReturn(_UserLibraryApi());
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.baseUrl).thenReturn('http://server');
    when(
      () => itemsApi.getItem(
        'series-1',
        mediaSourceId: any(named: 'mediaSourceId'),
      ),
    ).thenAnswer(
      (_) async => {'Id': 'series-1', 'Type': 'Series', 'Name': 'Serie'},
    );
    when(() => itemsApi.getEpisodes('series-1', fields: any(named: 'fields')))
        .thenAnswer(
          (_) async => {
            'Items': [
              _episode('e1', 1),
              _episode('e2', 2, positionTicks: 10 * 60 * 10000000),
              _episode('e3', 3),
            ],
          },
        );

    final users = UserRepository()
      ..setCurrentUser(
        PrivateUser(
          id: 'u1',
          name: 'Test',
          serverId: 'server-1',
          accessToken: 'token',
          lastUsed: DateTime(2026),
        ),
      );
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    GetIt.instance.registerSingleton<UserRepository>(users);
    GetIt.instance.registerSingleton<ItemMutationRepository>(_Mutations());
  });

  tearDown(() async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    userDataSync.reset();
    await GetIt.instance.reset();
  });

  Future<ItemDetailViewModel> seriesPage(WidgetTester tester) async {
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
    return vm;
  }

  Future<({List<String> played, GoRouter router, FocusNode top})> pump(
    WidgetTester tester,
    ItemDetailViewModel vm, {
    required bool landscape,
  }) async {
    final played = <String>[];
    final top = FocusNode(debugLabel: 'episodes-top');
    addTearDown(top.dispose);
    final router = GoRouter(
      initialLocation: '/series',
      routes: [
        GoRoute(
          path: '/series',
          builder: (context, state) => Scaffold(
            backgroundColor: Colors.black,
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: vm,
                builder: (context, _) => KostvEpisodesSection(
                  viewModel: vm,
                  prefs: prefs,
                  landscape: landscape,
                  episodesFocusNode: top,
                  onPlayEpisode: (episode) => played.add(episode.id),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/item/:itemId',
          builder: (context, state) =>
              Text('page ${state.pathParameters['itemId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(
      landscape ? const Size(1600, 900) : const Size(400, 900),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pump();
    await tester.pump();
    return (played: played, router: router, top: top);
  }

  void tvMode() {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
  }

  testWidgets('TV: the focused episode wears the white frame, the rest none', (
    tester,
  ) async {
    tvMode();
    final vm = await seriesPage(tester);
    final built = await pump(tester, vm, landscape: true);

    expect(
      find.byKey(const ValueKey('kostv-episode-focus-ring')),
      findsNothing,
    );
    built.top.requestFocus();
    await tester.pumpAndSettle();

    final ring = find.byKey(const ValueKey('kostv-episode-focus-ring'));
    expect(ring, findsOneWidget);
    final box = tester.widget<DecoratedBox>(ring).decoration as BoxDecoration;
    final border = box.border! as Border;
    expect(border.top.color, Colors.white);
    expect(border.top.width, kostvEpisodeRingWidth);

    // It moves with the focus.
    final before = tester.getCenter(ring);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('kostv-episode-focus-ring')),
      findsOneWidget,
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey('kostv-episode-focus-ring')))
          .dx,
      greaterThan(before.dx),
    );
  });

  testWidgets('TV: OK plays the focused episode instead of opening its page', (
    tester,
  ) async {
    tvMode();
    final vm = await seriesPage(tester);
    final built = await pump(tester, vm, landscape: true);
    built.top.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(built.played, hasLength(1));
    expect(find.textContaining('page '), findsNothing);
  });

  testWidgets('TV: the menu key offers the episode page, which opens it', (
    tester,
  ) async {
    tvMode();
    final vm = await seriesPage(tester);
    final built = await pump(tester, vm, landscape: true);
    built.top.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text(l10n.kostvEpisodeInfo), findsOneWidget);

    await tester.tap(find.text(l10n.kostvEpisodeInfo));
    await tester.pumpAndSettle();
    expect(built.played, isEmpty);
    expect(find.textContaining('page e'), findsOneWidget);
  });

  testWidgets('phone: a tap plays, the ⓘ opens the episode page', (
    tester,
  ) async {
    final vm = await seriesPage(tester);
    final built = await pump(tester, vm, landscape: false);

    await tester.tap(find.text('Episodio 2'));
    await tester.pumpAndSettle();
    expect(built.played, ['e2']);

    expect(find.byKey(const ValueKey('kostv-episode-info')), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('kostv-episode-info')).first);
    await tester.pumpAndSettle();
    expect(built.played, ['e2']);
    expect(find.text('page e1'), findsOneWidget);
  });

  testWidgets('phone: a long press offers the episode page too', (
    tester,
  ) async {
    final vm = await seriesPage(tester);
    final built = await pump(tester, vm, landscape: false);

    await tester.longPress(find.text('Episodio 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.kostvEpisodeInfo));
    await tester.pumpAndSettle();
    expect(built.played, isEmpty);
    expect(find.text('page e3'), findsOneWidget);
  });

  testWidgets('mouse: a fainter frame and the ⓘ under the pointer; a click '
      'plays and a right-click offers the page', (tester) async {
    final vm = await seriesPage(tester);
    final built = await pump(tester, vm, landscape: true);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Episodio 2')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('kostv-episode-hover-ring')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('kostv-episode-focus-ring')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('kostv-episode-info')), findsOneWidget);

    await tester.tap(find.text('Episodio 2'));
    await tester.pumpAndSettle();
    expect(built.played, ['e2']);

    await tester.tap(find.text('Episodio 3'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.kostvEpisodeInfo));
    await tester.pumpAndSettle();
    expect(built.played, ['e2']);
    expect(find.text('page e3'), findsOneWidget);
  });

  group('the queue of an episode picked in a list', () {
    test('on a series page it is the episode\'s own season', () {
      expect(
        episodeQueueSeasonId(
          pageType: 'Series',
          pageSeasonId: null,
          episodeSeasonId: 'season-2',
        ),
        'season-2',
      );
    });

    test('on a season or episode page it is the season shown', () {
      for (final type in ['Season', 'Episode']) {
        expect(
          episodeQueueSeasonId(
            pageType: type,
            pageSeasonId: 'season-1',
            episodeSeasonId: 'specials',
          ),
          'season-1',
        );
      }
      expect(
        episodeQueueSeasonId(
          pageType: 'Episode',
          pageSeasonId: null,
          episodeSeasonId: 'season-3',
        ),
        'season-3',
      );
    });
  });
}
