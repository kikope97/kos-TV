import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/home/kostv_undo_toast.dart';

/// Kos TV: the notice with a few seconds to take a «not interested» back.
void main() {
  Future<({List<String> calls})> pump(
    WidgetTester tester, {
    bool takeFocus = false,
  }) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKostvUndoToast(
                context,
                message: '«Cars» ya no saldrá en tu Inicio',
                undoLabel: 'Deshacer',
                duration: const Duration(seconds: 5),
                takeFocus: takeFocus,
                onUndo: () => calls.add('undo'),
                onLeave: () => calls.add('leave'),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return (calls: calls);
  }

  testWidgets('counts down and goes by itself', (tester) async {
    final r = await pump(tester);
    expect(find.text('5'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Deshacer'), findsNothing);
    expect(r.calls, isEmpty);
  });

  testWidgets('a tap on Undo takes it back and the notice goes', (
    tester,
  ) async {
    final r = await pump(tester);
    await tester.tap(find.text('Deshacer'));
    await tester.pump();
    expect(r.calls, ['undo']);
    expect(find.text('Deshacer'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(r.calls, ['undo']);
  });

  testWidgets('with a remote, OK takes it back', (tester) async {
    final r = await pump(tester, takeFocus: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(r.calls, ['undo']);
  });

  testWidgets('with a remote, another key goes back to browsing and the '
      'notice stays until its time is up', (tester) async {
    final r = await pump(tester, takeFocus: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(r.calls, ['leave']);
    expect(find.text('Deshacer'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(r.calls, ['leave']);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Deshacer'), findsNothing);
  });
}
