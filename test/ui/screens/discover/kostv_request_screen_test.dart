import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/screens/discover/kostv_request_controller.dart';
import 'package:moonfin/ui/screens/discover/kostv_request_screen.dart';
import 'package:moonfin/ui/widgets/navigation_layout.dart';
import 'package:moonfin/util/platform_detection.dart';

import '../../widgets/bottom_nav/bottom_nav_fakes.dart';
import 'fake_stremfin_life.dart';

/// Kos TV: the grey page of a title that isn't on the home server, on a TV,
/// a phone and a computer.
void main() {
  late FakeStremfinLife fake;

  Future<void> open(
    WidgetTester tester, {
    required InterfaceLayout layout,
    required String location,
  }) async {
    final setup = await setUpBottomNav();
    PlatformDetection.setInterfaceLayout(layout);
    final top = layout != InterfaceLayout.phone;
    final position = top ? NavbarPosition.top : NavbarPosition.bottom;
    await setup.prefs.set(UserPreferences.navbarPosition, position);
    NavigationLayout.positionNotifier.value = position;
    if (layout == InterfaceLayout.phone) {
      usePhoneView(tester);
    } else {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final service = fake.service()..onUserChanged('kiko');
    GetIt.instance.registerSingleton<StremfinService>(service);

    final router = GoRouter(
      initialLocation: Destinations.home,
      routes: [
        GoRoute(
          path: Destinations.home,
          builder: (_, _) => const Scaffold(body: Text('home page')),
        ),
        GoRoute(
          path: Destinations.kostvRequest,
          builder: (_, state) => KostvRequestScreen(
            type: StremfinTitleType.fromApi(state.pathParameters['type'])!,
            tmdbId: int.parse(state.pathParameters['tmdbId']!),
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
    router.push(location);
    await settle(tester);
  }

  setUp(() => fake = FakeStremfinLife());
  tearDown(tearDownBottomNav);

  testWidgets(
    'TV: grey, «Solicitar» with ⚡, then the download live, then its page',
    (tester) async {
      await open(
        tester,
        layout: InterfaceLayout.tv,
        location: Destinations.kostvRequestOf('movie', 920),
      );

      expect(find.text('Cars'), findsOneWidget);
      expect(find.text('Solicitar'), findsOneWidget);
      expect(find.text('Rápida'), findsOneWidget);
      // What it would bring, on the strip, and the way ahead.
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('Castellano'), findsOneWidget);
      expect(find.text('9,0 GB'), findsOneWidget);
      expect(find.text('TODAVÍA NO ESTÁ EN CASA'), findsOneWidget);
      expect(find.text('En casa'), findsOneWidget);
      // The art is grey.
      expect(find.byType(ColorFiltered), findsWidgets);

      // OK on the remote: the button has the focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.text('Aceptada: empieza en seguida'), findsOneWidget);
      expect(find.text('Solicitar'), findsNothing);

      final id = fake.requests.keys.single;
      fake.download(id, 42);
      await settle(tester, KostvRequestController.slowInterval);
      expect(find.text('Descargando 42 %'), findsOneWidget);
      expect(find.text('42 %'), findsOneWidget);
      expect(find.text('12,0 MB/s'), findsOneWidget);
      expect(find.text('4 min'), findsOneWidget);

      fake.complete(id);
      await settle(tester, KostvRequestController.quickInterval);
      expect(find.text('¡Ya está aquí!'), findsOneWidget);
      expect(find.text('¡YA ESTÁ AQUÍ!'), findsOneWidget);

      // The colour comes in, then its page on the home server.
      await settle(tester, const Duration(milliseconds: 1500));
      expect(find.text('item cars-item'), findsNothing);
      await settle(tester, const Duration(seconds: 1));
      expect(find.text('item cars-item'), findsOneWidget);
    },
  );

  testWidgets('phone: waiting for approval, and taken back', (tester) async {
    fake.mode = 'review';
    await open(
      tester,
      layout: InterfaceLayout.phone,
      location: Destinations.kostvRequestOf('movie', 920),
    );
    expect(find.text('El administrador tiene que aceptarla'), findsNothing);

    await tester.tap(find.text('Solicitar'));
    await settle(tester);
    expect(find.text('Pendiente de aprobación'), findsOneWidget);
    // Who asked for it, on the strip (the navbar has a «Tú» of its own).
    final requestedBy = find.ancestor(
      of: find.text('SOLICITADA POR'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: requestedBy.first, matching: find.text('Tú')),
      findsOneWidget,
    );
    expect(
      find.text('Petición enviada: el administrador tiene que aceptarla'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Retirar petición'));
    await tester.tap(find.text('Retirar petición'));
    await settle(tester);
    expect(find.text('Solicitar'), findsOneWidget);
    expect(fake.requests, isEmpty);
  });

  testWidgets('computer: a series, season by season', (tester) async {
    await open(
      tester,
      layout: InterfaceLayout.desktop,
      location: Destinations.kostvRequestOf('series', 1396),
    );

    expect(find.text('Marea alta'), findsOneWidget);
    expect(find.text('Solicitar todo lo que falta'), findsOneWidget);
    expect(find.text('Temporada 1'), findsOneWidget);
    expect(find.textContaining('Completa'), findsWidgets);
    expect(find.text('Temporada 3'), findsOneWidget);

    // «Solicitar» on season 2's row.
    final season2 = find.ancestor(
      of: find.text('Temporada 2'),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(
      find.descendant(of: season2.first, matching: find.text('Solicitar')),
    );
    await settle(tester);
    expect(fake.requests.values.single['season'], 2);
    expect(find.text('Aceptada: empieza en seguida'), findsOneWidget);
    // Season 3 can still be asked for, and so can all that's missing.
    expect(find.text('Solicitar todo lo que falta'), findsOneWidget);
  });

  testWidgets('at the limit: says so and the button waits', (tester) async {
    fake.atLimit = true;
    await open(
      tester,
      layout: InterfaceLayout.tv,
      location: Destinations.kostvRequestOf('movie', 920),
    );
    expect(
      find.text(
        'Has hecho todas las peticiones de hoy: mañana podrás pedir más',
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(fake.requests, isEmpty);
  });
}

/// Lets the calls in flight finish, after [wait].
Future<void> settle(
  WidgetTester tester, [
  Duration wait = Duration.zero,
]) async {
  await tester.pump(wait);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
