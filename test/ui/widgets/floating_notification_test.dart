import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/floating_notification.dart';
import 'package:moonfin/util/platform_detection.dart';

void main() {
  // TV can't tap the card, which is the case that used to leave the text with
  // no theme above it.
  testWidgets('the text is themed on TV too', (tester) async {
    PlatformDetection.setTvMode(true);
    addTearDown(() => PlatformDetection.setTvMode(false));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                FloatingNotification.show(context, 'Title', 'Body', () {}),
            child: const Text('show'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    expect(
      find.ancestor(of: find.text('Title'), matching: find.byType(Material)),
      findsWidgets,
    );

    // Let the card time out so no timer is left behind.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  });

  testWidgets('a second notice goes below the first instead of over it', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    FloatingNotification.show(context, 'First', 'One', null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    FloatingNotification.show(context, 'Second', 'Two', null);
    await tester.pump();
    await tester.pumpAndSettle();

    final first = tester.getRect(find.text('First'));
    final second = tester.getRect(find.text('Second'));
    expect(second.top, greaterThan(tester.getRect(find.text('One')).bottom));
    expect(first.top, lessThan(second.top));

    // The first times out; the second stays and moves up into its place.
    await tester.pump(const Duration(seconds: 4, milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.getRect(find.text('Second')).top, first.top);

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });
}
