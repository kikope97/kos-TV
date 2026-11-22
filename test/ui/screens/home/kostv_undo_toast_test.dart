import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('offering to try again, with no seconds shown', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKostvUndoToast(
                context,
                message: 'No se han podido cargar tus recomendaciones',
                undoLabel: 'Reintentar',
                icon: Icons.refresh_rounded,
                countdown: false,
                duration: const Duration(seconds: 10),
                onUndo: () => calls.add('retry'),
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

    expect(find.text('10'), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(calls, ['retry']);
    expect(find.text('Reintentar'), findsNothing);
  });

  // Kos TV: on a narrow screen the button goes under the text, which is
  // then read whole («Añadida a tus favoritas. ¿Pedir el álbum…?»).
  for (final (width, narrow) in [
    (360.0, true),
    (412.0, true),
    (1280.0, false),
  ]) {
    testWidgets('${width.toInt()} wide: the button '
        '${narrow ? 'under' : 'beside'} the text', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showKostvUndoToast(
                  context,
                  message:
                      'Añadida a tus favoritas. ¿Pedir el álbum para tenerla '
                      'en casa?',
                  undoLabel: 'Pedir álbum',
                  icon: Icons.album_rounded,
                  duration: const Duration(seconds: 8),
                  onUndo: () {},
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
      final text = find.textContaining('Añadida a tus favoritas');
      final textBox = tester.getRect(text);
      final buttonBox = tester.getRect(find.text('Pedir álbum'));
      if (narrow) {
        expect(buttonBox.top, greaterThanOrEqualTo(textBox.bottom));
        // The whole width for the text, and a line more. (The test font is
        // far wider than the app's, so the lines it takes aren't counted.)
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.maxLines, 3);
        expect(textBox.width, greaterThan(width - 120));
      } else {
        expect(buttonBox.left, greaterThanOrEqualTo(textBox.right));
        expect(tester.renderObject<RenderParagraph>(text).maxLines, 2);
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
    });
  }
}
