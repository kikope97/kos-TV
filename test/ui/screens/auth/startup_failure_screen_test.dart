import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/auth/startup_failure_screen.dart';

void main() {
  testWidgets('says startup failed, in Spanish where the device is', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('es', 'ES');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(StartupFailureApp(onRetry: () async {}));
    await tester.pump();
    expect(find.text('No se ha podido abrir kOS TV'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('Moonfin'), findsNothing);
  });

  testWidgets('Retry runs startup again, once at a time, and the remote '
      'reaches it', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    var retries = 0;
    final retry = Completer<void>();
    await tester.pumpWidget(
      StartupFailureApp(
        onRetry: () {
          retries++;
          return retry.future;
        },
      ),
    );
    await tester.pump();
    expect(find.text("kOS TV couldn't open"), findsOneWidget);

    // The button holds the focus from the start, and select presses it.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(retries, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Pressed again while it retries: nothing more.
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(retries, 1);

    retry.complete();
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(retries, 2);
  });
}
