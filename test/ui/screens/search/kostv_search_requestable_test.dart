import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/data/repositories/search_repository.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/recent_searches_store.dart';
import 'package:moonfin/data/services/server_messages_service.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/screens/search/search_screen.dart';
import 'package:moonfin/ui/widgets/navigation_layout.dart';
import 'package:moonfin/util/game_library.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/stremfin/fake_stremfin_adapter.dart';

// The search screen renders inside the navigation chrome, so the whole
// chrome's dependency set has to be standing.
class _FakeUserRepository extends Fake implements UserRepository {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> get currentUserStream => const Stream.empty();
}

class _FakeUserViewsRepository extends ChangeNotifier
    implements UserViewsRepository {
  @override
  Future<List<AggregatedLibrary>> getUserViews() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePluginSyncService extends ChangeNotifier
    implements PluginSyncService {
  @override
  bool get calendarAvailable => false;

  @override
  bool get smartSearchEnabled => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGameLibraryRegistry extends Fake implements GameLibraryRegistry {
  @override
  Future<void> refresh() async {}
}

class _FakePlaybackManager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();
}

class _FakeClientFactory extends Fake implements MediaServerClientFactory {}

class _FakeServerMessages extends ChangeNotifier
    implements ServerMessagesService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockClient extends Mock implements MediaServerClient {}

class _MockImageApi extends Mock implements ImageApi {}

/// What the home server has for any search: [items], and no people.
class _FakeItemsApi extends Fake implements ItemsApi {
  List<Map<String, dynamic>> items = const [];

  @override
  Future<Map<String, dynamic>> getPersons({
    required String searchTerm,
    int? limit,
    String? fields,
    String? enableImageTypes,
  }) async => {'Items': <Object>[]};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future.value(<String, dynamic>{'Items': items});
}

/// Kos TV: the search's «Para solicitar»: what isn't at home, grey, after
/// what is, and opening its page to request it.
void main() {
  late _FakeItemsApi itemsApi;
  late StremfinService requests;
  late List<Map<String, String>> searches;
  late String? nextCursor;

  Map<String, Object?> title(int id, String name, {String type = 'movie'}) => {
    'type': type,
    'tmdb_id': id,
    'title': name,
    'year': 2026,
    'poster': null,
    'library': {'status': 'missing', 'in_jellyfin': false},
    'request': null,
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = PreferenceStore();
    await store.init();
    itemsApi = _FakeItemsApi();
    searches = [];
    nextCursor = null;

    final client = _MockClient();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.imageApi).thenReturn(_MockImageApi());
    when(() => client.gamesApi).thenReturn(null);
    when(() => client.baseUrl).thenReturn('http://jf');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);

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
        final query = adapter.lastQuery;
        searches.add(query);
        final more = query['cursor'] != null;
        return (
          status: 200,
          body: {
            'items': more
                ? [title(3, 'Cumbres de hielo')]
                : [
                    title(1, 'Cumbres'),
                    title(2, 'Cumbres borrascosas', type: 'series'),
                  ],
            'next_cursor': more ? null : nextCursor,
          },
          headers: const {},
        );
      }
      return (status: 404, body: null, headers: const {});
    });
    requests = StremfinService(
      StremfinClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://requests.example.org/api/v1',
        token: () => 'token',
      ),
      watchLifecycle: false,
    );

    final getIt = GetIt.instance;
    getIt.registerSingleton<PreferenceStore>(store);
    getIt.registerSingleton<UserPreferences>(UserPreferences(store));
    // The app starts in Spanish; these finders read the English strings.
    await getIt<UserPreferences>().set(UserPreferences.languageOverride, 'en');
    getIt.registerSingleton<UserRepository>(_FakeUserRepository());
    getIt.registerSingleton<UserViewsRepository>(_FakeUserViewsRepository());
    getIt.registerSingleton<PluginSyncService>(_FakePluginSyncService());
    getIt.registerSingleton<GameLibraryRegistry>(_FakeGameLibraryRegistry());
    getIt.registerSingleton<PlaybackManager>(_FakePlaybackManager());
    getIt.registerSingleton<MediaServerClientFactory>(_FakeClientFactory());
    getIt.registerSingleton<ServerMessagesService>(_FakeServerMessages());
    getIt.registerSingleton<MediaServerClient>(client);
    getIt.registerSingleton<SearchRepository>(SearchRepository(client));
    getIt.registerSingleton<RecentSearchesStore>(RecentSearchesStore(store));
    getIt.registerSingleton<StremfinService>(requests);
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
  });

  tearDown(() async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    NavigationLayout.chromeFocusRoots.clear();
    await GetIt.instance.reset();
  });

  /// The TV field's cursor keeps blinking, so this never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> search(WidgetTester tester, String query) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    requests.onUserChanged('kiko');
    final router = GoRouter(
      initialLocation: Destinations.search,
      routes: [
        GoRoute(
          path: Destinations.search,
          builder: (_, _) => SearchScreen(initialQuery: query),
        ),
        GoRoute(
          path: Destinations.kostvRequest,
          builder: (_, state) => Scaffold(
            body: Text(
              'request ${state.pathParameters['type']} '
              '${state.pathParameters['tmdbId']}',
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    requests.dispose();
  }

  testWidgets('what is at home first, then what can be requested, grey', (
    tester,
  ) async {
    itemsApi.items = [
      {'Id': 'm1', 'Name': 'Cumbres (en casa)', 'Type': 'Movie'},
      {'Id': 'al1', 'Name': 'Cumbres (disco)', 'Type': 'MusicAlbum'},
    ];
    await search(tester, 'cumbres');

    expect(searches.single['only'], 'missing');
    expect(find.text('Cumbres (en casa)'), findsWidgets);
    expect(find.text('Available to request'), findsOneWidget);
    expect(find.text('Available to request: 2'), findsOneWidget);
    expect(find.text('Cumbres borrascosas'), findsWidgets);
    double top(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(top('Available to request'), greaterThan(top('Movies')));
    // No music.
    expect(find.text('Cumbres (disco)'), findsNothing);
    expect(find.textContaining('Albums'), findsNothing);

    // Its page, to request it.
    await tester.tap(find.text('Cumbres borrascosas').first);
    await settle(tester);
    expect(find.text('request series 2'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('nothing at home: said so, over what can be requested', (
    tester,
  ) async {
    itemsApi.items = const [];
    await search(tester, 'cumbres');
    expect(
      find.text("It isn't at home, but you can request it"),
      findsOneWidget,
    );
    expect(find.text('Cumbres'), findsWidgets);
    expect(find.textContaining('No results'), findsNothing);
    await finish(tester);
  });

  testWidgets('more is read from the last card', (tester) async {
    itemsApi.items = const [];
    nextCursor = '2.19';
    await search(tester, 'cumbres');
    expect(find.text('Available to request: 2+'), findsOneWidget);
    await tester.tap(find.text('More results'));
    await settle(tester);
    expect(searches.last['cursor'], '2.19');
    expect(find.text('Cumbres de hielo'), findsWidgets);
    expect(find.text('More results'), findsNothing);
    await finish(tester);
  });

  testWidgets('TV: down from what is at home reaches what can be requested', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    itemsApi.items = [
      {'Id': 'm1', 'Name': 'Cumbres (en casa)', 'Type': 'Movie'},
    ];
    await search(tester, 'cumbres');
    FocusNode cardNode(String title) =>
        Focus.of(tester.element(find.text(title).first));
    cardNode('Cumbres (en casa)').requestFocus();
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle(tester);
    expect(FocusManager.instance.primaryFocus, cardNode('Cumbres'));
    await finish(tester);
  });

  testWidgets('kids mode: nothing is asked of the requests service', (
    tester,
  ) async {
    await GetIt.instance<UserPreferences>().set(
      UserPreferences.kidsModeEnabled,
      true,
    );
    itemsApi.items = [
      {'Id': 'm1', 'Name': 'Cumbres (en casa)', 'Type': 'Movie'},
    ];
    await search(tester, 'cumbres');
    expect(searches, isEmpty);
    expect(find.text('Available to request'), findsNothing);
    await finish(tester);
  });
}
