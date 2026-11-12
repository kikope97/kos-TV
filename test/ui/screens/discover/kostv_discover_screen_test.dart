import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/screens/discover/kostv_discover_hero.dart';
import 'package:moonfin/ui/screens/discover/kostv_discover_parts.dart';
import 'package:moonfin/ui/screens/discover/kostv_discover_screen.dart';
import 'package:moonfin/ui/screens/discover/kostv_discover_spotlight.dart';
import 'package:moonfin/ui/widgets/focus/hub_focus_memory.dart';
import 'package:moonfin/ui/widgets/media_card.dart';
import 'package:moonfin/ui/widgets/navigation_layout.dart';
import 'package:moonfin/util/platform_detection.dart';

import '../../../data/services/stremfin/fake_stremfin_adapter.dart';
import '../../widgets/bottom_nav/bottom_nav_fakes.dart';

typedef _Reply = ({int status, Object? body, Map<String, String> headers});

/// Kos TV: Discover: the spotlight over the rows on a TV or a computer, the
/// carousel on a phone, and the posters large enough to read from the sofa.
void main() {
  late StremfinService service;
  late List<String> calls;

  Map<String, Object?> title(
    String type,
    int id,
    String name, {
    int? rank,
    int? season,
    String? platform,
    String? itemId,
    bool partial = false,
    Map<String, Object?>? request,
  }) => {
    'type': type,
    'tmdb_id': id,
    'title': name,
    'year': 2026,
    'poster': 'https://image.tmdb.org/t/p/w342/$id.jpg',
    'backdrop': null,
    'rating': null,
    'rank': rank,
    'season': season,
    'platform': ?platform,
    'library': {
      'status': partial
          ? 'partial'
          : (itemId != null ? 'available' : 'missing'),
      'in_jellyfin': itemId != null,
      'jellyfin_id': itemId,
      'downloading': false,
      if (partial) 'season': 3,
    },
    'request': request,
  };

  final lists = {
    'series/popular': [
      title('series', 1, 'Marea alta', rank: 1),
      title('series', 2, 'Los del quinto', rank: 2, itemId: 'm1'),
    ],
    'series/new': [
      title('series', 3, 'Medianoche', season: 1, platform: 'netflix'),
    ],
    'movie/popular': [
      title('movie', 11, 'El atraco', rank: 1, itemId: 'm4'),
      title('movie', 12, 'Tormenta solar', rank: 2),
    ],
    'movie/new': [
      title(
        'movie',
        13,
        'El regreso',
        request: {'id': 9, 'status': 'pending', 'mine': true},
      ),
    ],
  };

  _Reply answer(String method, String path, Object? sent, Map query) {
    calls.add(path);
    _Reply ok(Object? body) => (status: 200, body: body, headers: const {});
    if (path == '/me') {
      return ok({
        'user': {'name': 'Kiko', 'role': 'member'},
        'access': {'can_request': true, 'mode': 'direct'},
      });
    }
    if (path == '/platforms') {
      return ok({
        'platforms': [
          {'id': 'all', 'name': 'Todas', 'color': null},
          {'id': 'netflix', 'name': 'Netflix', 'color': '#e50914'},
          {'id': 'disney', 'name': 'Disney+', 'color': '#113ccf'},
          {'id': 'prime', 'name': 'Prime Video', 'color': '#00a8e1'},
        ],
      });
    }
    if (path == '/top') {
      return ok({'items': lists['${query['type']}/${query['list']}'] ?? []});
    }
    final movie = RegExp(r'^/movies/(\d+)$').firstMatch(path);
    if (movie != null) {
      final id = int.parse(movie.group(1)!);
      final base = lists.values
          .expand((l) => l)
          .firstWhere((t) => t['tmdb_id'] == id);
      return ok({
        ...base,
        'overview': 'Una tormenta solar deja a oscuras medio planeta.',
        'backdrop': 'https://image.tmdb.org/t/p/w780/$id.jpg',
        'runtime': 112,
        'genres': ['Aventura', 'Drama'],
      });
    }
    return (status: 404, body: null, headers: const {});
  }

  Future<void> open(WidgetTester tester, {required bool phone}) async {
    calls = [];
    KostvSpotlightDetails.clear();
    HubFocusMemory.clearAll();
    final setup = await setUpBottomNav();
    PlatformDetection.setInterfaceLayout(
      phone ? InterfaceLayout.phone : InterfaceLayout.tv,
    );
    final position = phone ? NavbarPosition.bottom : NavbarPosition.top;
    await setup.prefs.set(UserPreferences.navbarPosition, position);
    NavigationLayout.positionNotifier.value = position;
    if (phone) {
      usePhoneView(tester);
    } else {
      // A 1080p TV: the app lays out on 960 × 540.
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }
    late final FakeStremfinAdapter adapter;
    adapter = FakeStremfinAdapter.withMethod(
      (method, path, sent) => answer(method, path, sent, adapter.lastQuery),
    );
    service = StremfinService(
      StremfinClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://requests.example.org/api/v1',
        token: () => 'token',
      ),
      watchLifecycle: false,
    )..onUserChanged('kiko');
    GetIt.instance.registerSingleton<StremfinService>(service);

    final router = GoRouter(
      initialLocation: Destinations.kostvDiscover,
      routes: [
        GoRoute(
          path: Destinations.home,
          builder: (_, _) => const Scaffold(body: Text('home page')),
        ),
        GoRoute(
          path: Destinations.kostvDiscover,
          builder: (_, _) => const KostvDiscoverScreen(),
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
        GoRoute(
          path: Destinations.itemDetail,
          builder: (_, state) =>
              Scaffold(body: Text('item ${state.pathParameters['itemId']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    service.dispose();
  }

  KostvSpotlightText spotlight(WidgetTester tester) => tester
      .widgetList<KostvSpotlightText>(find.byType(KostvSpotlightText))
      .last;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  tearDown(tearDownBottomNav);

  testWidgets('TV: the spotlight shows the first of the first row, then '
      'whatever the focus lands on', (tester) async {
    await open(tester, phone: false);

    expect(spotlight(tester).title.title, 'Marea alta');
    expect(find.text('N.º 1'), findsWidgets);
    expect(find.text('Todavía no está en casa'), findsOneWidget);

    // Down into the rows: the platforms fold away, the spotlight follows.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(spotlight(tester).title.title, 'Los del quinto');
    expect(find.text('En casa'), findsOneWidget);
    final fold = tester.widget<AnimatedAlign>(
      find.ancestor(
        of: find.byType(KostvPlatformPill).first,
        matching: find.byType(AnimatedAlign),
      ),
    );
    expect(fold.heightFactor, 0);

    // A film not at home: once the focus rests, its page brings what it
    // is about.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(spotlight(tester).title.title, 'Tormenta solar');
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(calls.where((c) => c == '/movies/12'), hasLength(1));
    expect(
      find.text('Una tormenta solar deja a oscuras medio planeta.'),
      findsOneWidget,
    );
    expect(find.textContaining('1 h 52 min'), findsOneWidget);
    // A series not at home is never asked for: its page is a costly call.
    expect(calls.where((c) => c.startsWith('/series/')), isEmpty);

    // Back up to the platforms: they unfold and the first is shown again.
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(spotlight(tester).title.title, 'Marea alta');
    await finish(tester);
  });

  testWidgets('TV: posters about three tenths of the screen, about seven '
      'to a row', (tester) async {
    await open(tester, phone: false);
    final card = tester.getSize(find.byType(MediaCard).first);
    // Before, 120 tall on a TV: ten or eleven to a row. Now about seven.
    expect(card.height, greaterThan(150));
    expect(card.width, greaterThan(100));
    final second = tester.getTopLeft(find.byType(MediaCard).at(1));
    final stride =
        second.dx - tester.getTopLeft(find.byType(MediaCard).first).dx;
    expect((960 - 48) / stride, inInclusiveRange(6, 8));
    await finish(tester);
  });

  testWidgets('TV: OK opens a title that isn\'t at home on its page to '
      'request it', (tester) async {
    await open(tester, phone: false);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text('request series 1'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('TV: OK opens a title at home on the home server', (
    tester,
  ) async {
    await open(tester, phone: false);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text('item m1'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('phone: the carousel takes the first of each row', (
    tester,
  ) async {
    await open(tester, phone: true);
    final hero = tester.widget<KostvDiscoverHero>(
      find.byType(KostvDiscoverHero),
    );
    expect(
      [for (final entry in hero.items) entry.title.title],
      [
        'Marea alta',
        'Medianoche',
        'El atraco',
        'El regreso',
        'Los del quinto',
        'Tormenta solar',
      ],
    );
    expect(find.textContaining('SERIES MÁS VISTAS'), findsOneWidget);
    expect(find.byType(KostvSpotlightText), findsNothing);
    await finish(tester);
  });

  group('how a title stands at home', () {
    late AppLocalizations l10n;
    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('es'));
    });

    StremfinTitle parse(Map<String, Object?> raw) =>
        StremfinTitle.fromJson(raw)!;

    test('at home, and missing the season it announces', () {
      final partial = parse(
        title('series', 5, 'Señales', itemId: 'm2', partial: true),
      );
      expect(
        [for (final s in KostvTitleStatus.of(partial, l10n)) s.text],
        ['En casa', 'Falta la T3'],
      );
      expect(KostvTitleStatus.band(partial, l10n)?.text, 'Falta la T3');
    });

    test('at home: a tick and no band', () {
      final home = parse(title('movie', 11, 'El atraco', itemId: 'm4'));
      expect(KostvTitleStatus.of(home, l10n).single.text, 'En casa');
      expect(KostvTitleStatus.band(home, l10n), isNull);
    });

    test('asked for by the person, and not there yet', () {
      final mine = parse(
        title(
          'movie',
          13,
          'El regreso',
          request: {'id': 9, 'status': 'pending', 'mine': true},
        ),
      );
      expect(KostvTitleStatus.band(mine, l10n)?.text, 'Solicitada por ti');
      final missing = parse(title('series', 1, 'Marea alta'));
      expect(
        KostvTitleStatus.of(missing, l10n).single.text,
        'Todavía no está en casa',
      );
      expect(KostvTitleStatus.band(missing, l10n), isNull);
    });
  });

  test('the spotlight asks after films and what is at home, never after '
      'a series that isn\'t', () {
    final series = StremfinTitle.fromJson(title('series', 1, 'Marea alta'))!;
    final movie = StremfinTitle.fromJson(title('movie', 12, 'Tormenta'))!;
    final home = StremfinTitle.fromJson(
      title('series', 2, 'Los del quinto', itemId: 'm1'),
    )!;
    expect(KostvSpotlightDetails.worthAsking(series), isFalse);
    expect(KostvSpotlightDetails.worthAsking(movie), isTrue);
    expect(KostvSpotlightDetails.worthAsking(home), isTrue);
  });
}

/// Lets the lists arrive and the animations end.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
