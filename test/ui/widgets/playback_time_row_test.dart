import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/playback/playback_time_row.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double width,
    String left = '',
    String center = '',
    String right = '',
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PlaybackTimeRow(
              left: left,
              center: center,
              right: right,
              bold: true,
            ),
          ),
        ),
      ),
    ),
  );

  bool cut(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines;

  // Kos TV: on a phone the end time got a third of the row and lost its
  // minutes («Ends at 21:…») with nothing beside it.
  testWidgets('gives a long end label the room its empty neighbours leave', (
    tester,
  ) async {
    await pump(tester, width: 297, right: 'Termina a las 21:13');
    expect(cut(tester, 'Termina a las 21:13'), isFalse);
    expect(
      tester.getSize(find.text('Termina a las 21:13')).height,
      lessThan(20),
    );
    expect(
      tester.getRect(find.text('Termina a las 21:13')).right,
      closeTo(tester.getRect(find.byType(PlaybackTimeRow)).right, 0.5),
    );
  });

  testWidgets('shares the row by how much each end says', (tester) async {
    await pump(tester, width: 297, left: '0:04', right: 'Termina a las 21:13');
    expect(cut(tester, 'Termina a las 21:13'), isFalse);
    expect(cut(tester, '0:04'), isFalse);
    final row = tester.getRect(find.byType(PlaybackTimeRow));
    expect(tester.getRect(find.text('0:04')).left, closeTo(row.left, 0.5));
    expect(
      tester.getRect(find.text('Termina a las 21:13')).right,
      closeTo(row.right, 0.5),
    );
  });

  testWidgets('wraps rather than cutting the time when even that is short', (
    tester,
  ) async {
    await pump(tester, width: 200, left: '0:04', right: 'Termina a las 21:13');
    expect(cut(tester, 'Termina a las 21:13'), isFalse);
    expect(
      tester.getSize(find.text('Termina a las 21:13')).height,
      greaterThan(20),
    );
  });

  testWidgets('keeps a center label in the middle', (tester) async {
    await pump(
      tester,
      width: 300,
      left: '0:04',
      center: '-5:52',
      right: '44:00',
    );
    expect(
      tester.getRect(find.text('-5:52')).center.dx,
      closeTo(tester.getRect(find.byType(PlaybackTimeRow)).center.dx, 0.5),
    );
  });
}
