import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/focusable_dialog_row.dart';

/// Kos TV: on the web the app's arrows scroll (Flutter's web shortcuts), so
/// the rows of a dialog move the focus up and down themselves; elsewhere
/// they go on doing what the arrows did.
void main() {
  Widget rows({required bool webArrows, required List<String> tapped}) {
    final list = ListView(
      shrinkWrap: true,
      children: [
        for (final name in ['Uno', 'Dos', 'Tres'])
          FocusableDialogRow(
            label: name,
            autofocus: name == 'Uno',
            onTap: () => tapped.add(name),
          ),
      ],
    );
    return MaterialApp(
      home: Scaffold(
        body: webArrows
            ? Shortcuts(
                // As WidgetsApp sets them up on the web.
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.arrowDown): ScrollIntent(
                    direction: AxisDirection.down,
                  ),
                  SingleActivator(LogicalKeyboardKey.arrowUp): ScrollIntent(
                    direction: AxisDirection.up,
                  ),
                },
                child: list,
              )
            : list,
      ),
    );
  }

  String? focused(WidgetTester tester) {
    for (final name in ['Uno', 'Dos', 'Tres']) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(Focus),
      );
      if (tester
          .widgetList<Focus>(row)
          .any((f) => f.focusNode?.hasPrimaryFocus ?? false)) {
        return name;
      }
    }
    return null;
  }

  for (final web in [true, false]) {
    testWidgets('the arrows go along the rows (${web ? 'web' : 'Android'})', (
      tester,
    ) async {
      final tapped = <String>[];
      await tester.pumpWidget(rows(webArrows: web, tapped: tapped));
      await tester.pump();
      expect(focused(tester), 'Uno');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focused(tester), 'Dos');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focused(tester), 'Tres');
      // At the last one, it stays.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focused(tester), 'Tres');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focused(tester), 'Dos');
      // OK still picks it.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, ['Dos']);
    });
  }
}
