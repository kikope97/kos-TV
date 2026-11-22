import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/discover/kostv_requests_tray.dart';
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

  // Kos TV: on a narrow phone the time goes under a title that wouldn't fit
  // beside it, so the title isn't cut for it; a short one keeps it beside.
  testWidgets('phone: a long title gets the line, the time goes under it', (
    tester,
  ) async {
    // Accepted at once: no «Retirar» at the end of the rows.
    fake = FakeStremfinLife();
    fake.answer('POST', '/requests', {'type': 'movie', 'tmdb_id': 920});
    fake.answer('POST', '/requests', {'type': 'movie', 'tmdb_id': 921});
    final ago = DateTime.now()
        .subtract(const Duration(minutes: 33))
        .toUtc()
        .toIso8601String();
    final ids = fake.requests.keys.toList();
    fake.requests[ids.first]!
      ..['display_title'] = 'Estrenos'
      ..['updated_at'] = ago;
    fake.requests[ids.last]!
      ..['display_title'] = 'Cars'
      ..['updated_at'] = ago;
    await start(tester, phone: true);
    await settle(tester);
    await openTray(tester);

    final long = find.text('Estrenos');
    final short = find.text('Cars');
    final times = find.text('hace 33 min');
    expect(long, findsOneWidget);
    expect(short, findsOneWidget);
    expect(times, findsNWidgets(2));
    // The long title in full, with its time under it.
    expect(
      tester.renderObject<RenderParagraph>(long).didExceedMaxLines,
      isFalse,
    );
    final rows = [
      for (final element in times.evaluate())
        tester.getTopLeft(find.byWidget(element.widget)),
    ];
    final longAt = tester.getTopLeft(long);
    final shortAt = tester.getTopLeft(short);
    Offset near(Offset title) => rows.reduce(
      (a, b) => (a.dy - title.dy).abs() < (b.dy - title.dy).abs() ? a : b,
    );
    expect(near(longAt).dy, greaterThan(longAt.dy + 10));
    expect((near(shortAt).dy - shortAt.dy).abs(), lessThan(10));
    await finish(tester);
  });

  testWidgets('TV: taken back from its button, the focus goes to the row '
      'beside it', (tester) async {
    await start(tester, phone: false);
    await settle(tester);
    service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
    await settle(tester);
    service.createRequest(
      type: StremfinTitleType.series,
      tmdbId: 1396,
      season: 2,
    );
    await settle(tester);

    await openTray(tester);
    final first = FocusManager.instance.primaryFocus!.debugLabel!;
    expect(first, startsWith('tray-'));
    final other = [for (final id in fake.requests.keys) 'tray-$id']
        .singleWhere((label) => label != first);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, '$first-w');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    // The question, with «Retirar petición» ready.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    await settle(tester);
    expect(fake.requests, hasLength(1));
    expect(FocusManager.instance.primaryFocus?.debugLabel, other);
    await finish(tester);
  });
}
