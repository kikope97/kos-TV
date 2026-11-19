import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/screens/route_not_found_screen.dart';

void main() {
  testWidgets('an address with no page says so in Spanish and leads Home', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/no-such-page',
      routes: [
        GoRoute(
          path: Destinations.home,
          builder: (context, state) => const Text('home page'),
        ),
      ],
      errorBuilder: (context, state) => const RouteNotFoundScreen(),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Esta página no existe'), findsOneWidget);
    expect(find.text('Page Not Found'), findsNothing);

    await tester.tap(find.text('Ir a Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('home page'), findsOneWidget);
  });
}
