import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/discover/kostv_requests_tray.dart';
import 'package:moonfin/ui/widgets/kostv_requests_tray_button.dart';
import 'package:moonfin/util/platform_detection.dart';

import '../../widgets/bottom_nav/bottom_nav_fakes.dart';
import 'fake_stremfin_life.dart';

/// Kos TV: the requests tray: the person's own requests, what is new, what
/// is under way and what finished; and its button beside the avatar.
void main() {
  late FakeStremfinLife fake;
  late StremfinService service;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> start(WidgetTester tester, {required bool phone}) async {
    await setUpBottomNav();
    PlatformDetection.setInterfaceLayout(
      phone ? InterfaceLayout.phone : InterfaceLayout.tv,
    );
    if (phone) {
      usePhoneView(tester);
    } else {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    service = fake.service();
    GetIt.instance.registerSingleton<StremfinService>(service);
    service.onUserChanged('kiko');
  }

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Future<void> openTray(WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showKostvRequestsTray(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('abrir'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  /// Takes everything down, then the service and its timers.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    service.dispose();
  }

  setUp(() => fake = FakeStremfinLife(mode: 'review'));
  tearDown(tearDownBottomNav);

  testWidgets('TV: news, under way and finished, and opening sees the news', (
    tester,
  ) async {
    // Two of theirs from before: one arrived, one waiting for an answer.
    fake.answer('POST', '/requests', {'type': 'movie', 'tmdb_id': 920});
    fake.complete(fake.requests.keys.last);
    fake.answer('POST', '/requests', {
      'type': 'series',
      'tmdb_id': 1396,
      'season': 2,
    });
    await start(tester, phone: false);
    await settle(tester);
    expect(service.inbox.newsCount, 0, reason: 'what was there before');

    // Meanwhile the administrator accepts the season.
    fake.approve(fake.requests.keys.last);
    service.inbox.sync();
    await settle(tester);
    expect(service.inbox.newsCount, 1);

    await openTray(tester);
    expect(find.text('Peticiones'), findsOneWidget);
    expect(find.text('NOVEDADES'), findsOneWidget);
    expect(find.text('TERMINADAS'), findsOneWidget);
    expect(find.text('Aceptada: empieza en seguida'), findsOneWidget);
    expect(find.text('¡Ya está aquí!'), findsOneWidget);
    // Seen, though still shown as news while the tray is open.
    expect(service.inbox.newsCount, 0);
    expect(find.text('NOVEDADES'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('empty: says so and offers Discover', (tester) async {
    await start(tester, phone: false);
    await openTray(tester);
    expect(find.text('Aún no has solicitado nada'), findsOneWidget);
    expect(find.text('Ir a Descubrir'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('phone: a page of its own, and taking one back', (tester) async {
    await start(tester, phone: true);
    await settle(tester);
    service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
    await settle(tester);

    await openTray(tester);
    expect(find.text('EN MARCHA'), findsOneWidget);
    expect(find.text('Pendiente de aprobación'), findsOneWidget);
    await tester.tap(find.text('Retirar'));
    await settle(tester);
    await tester.tap(find.text('Retirar petición'));
    await settle(tester);
    expect(fake.requests, isEmpty);
    expect(find.text('Aún no has solicitado nada'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the button: hidden with nothing going on, out when revealed '
      'or when something is under way', (tester) async {
    await start(tester, phone: false);
    await settle(tester);
    Widget slot({required bool revealed}) => app(
      KostvRequestsTraySlot(
        revealed: revealed,
        builder: (_) => KostvRequestsTrayButton(size: 40, onPressed: () {}),
      ),
    );

    await tester.pumpWidget(slot(revealed: false));
    await settle(tester);
    expect(find.byType(KostvRequestsTrayButton), findsNothing);

    await tester.pumpWidget(slot(revealed: true));
    await settle(tester);
    expect(find.byType(KostvRequestsTrayButton), findsOneWidget);

    // Something under way: out without being revealed, with its ring.
    service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
    await tester.pumpWidget(slot(revealed: false));
    await settle(tester);
    expect(find.byType(KostvRequestsTrayButton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await finish(tester);
  });
}
