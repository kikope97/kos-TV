import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/settings/settings_more_section.dart';

/// Kos TV: settings in two levels. The technical ones wait behind «Más
/// ajustes» at the end of each screen.
void main() {
  Widget screen({SettingsMoreController? controller}) {
    final list = Builder(
      builder: (context) => ListView(
        children: [
          const ListTile(title: Text('Idioma')),
          ...settingsMore(
            context,
            id: 'general',
            summary: 'Reloj de 24 horas, rendimiento…',
            children: const [
              ListTile(title: Text('Formato de fecha')),
              ListTile(title: Text('Rendimiento')),
            ],
          ),
        ],
      ),
    );
    return MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: controller == null
            ? list
            : SettingsMoreScope(controller: controller, child: list),
      ),
    );
  }

  testWidgets('a screen on its own shows everything, with no fold', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    expect(find.text('Formato de fecha'), findsOneWidget);
    expect(find.text('Más ajustes'), findsNothing);
  });

  testWidgets('in Settings the technical ones wait behind «Más ajustes»', (
    tester,
  ) async {
    final controller = SettingsMoreController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller: controller));

    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Más ajustes'), findsOneWidget);
    expect(find.text('Reloj de 24 horas, rendimiento…'), findsOneWidget);
    expect(find.text('Formato de fecha'), findsNothing);

    await tester.tap(find.text('Más ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Formato de fecha'), findsOneWidget);
    expect(find.text('Rendimiento'), findsOneWidget);
    expect(find.text('Menos ajustes'), findsOneWidget);
    expect(controller.isOpen('general'), isTrue);

    await tester.tap(find.text('Menos ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Formato de fecha'), findsNothing);
    expect(controller.isOpen('general'), isFalse);
  });

  testWidgets('with the remote, OK opens it and the focus stays on the row', (
    tester,
  ) async {
    final controller = SettingsMoreController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller: controller));

    final row = find.ancestor(
      of: find.text('Más ajustes'),
      matching: find.byType(ListTile),
    );
    final focus = Focus.of(tester.element(find.text('Más ajustes')));
    focus.requestFocus();
    await tester.pump();
    expect(row, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Formato de fecha'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<SettingsMoreTile>(),
      isNotNull,
    );
  });

  test('the search opens every fold; one closed by hand stays closed', () {
    final controller = SettingsMoreController();
    addTearDown(controller.dispose);
    expect(controller.isOpen('general'), isFalse);

    controller.openAll();
    expect(controller.isOpen('general'), isTrue);
    expect(controller.isOpen('playback.audio'), isTrue);

    controller.setOpen('general', false);
    expect(controller.isOpen('general'), isFalse);
    expect(controller.isOpen('playback.audio'), isTrue);
  });
}
