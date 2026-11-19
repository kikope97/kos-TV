import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/horizontal_scroll_section.dart';
import 'package:moonfin/util/platform_detection.dart';

void main() {
  setUp(() {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
  });

  tearDown(() {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
  });

  Future<void> pump(
    WidgetTester tester, {
    required String title,
    bool showControls = true,
    double rowWidth = 2000,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HorizontalScrollSection(
            title: title,
            showControls: showControls,
            contentSpacing: 12,
            builder: (context, controller) => SizedBox(
              height: 80,
              child: ListView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                children: [SizedBox(key: const Key('row'), width: rowWidth)],
              ),
            ),
          ),
        ),
      ),
    );
    // The arrows read the row once it has been laid out.
    await tester.pump();
  }

  Finder chevrons() => find.byIcon(Icons.chevron_right);

  testWidgets('a titled section keeps its title and its chevrons on desktop', (
    tester,
  ) async {
    await pump(tester, title: 'Recommendations');

    expect(find.text('Recommendations'), findsOneWidget);
    expect(chevrons(), findsOneWidget);
  });

  testWidgets('an untitled section still shows the chevrons on desktop', (
    tester,
  ) async {
    await pump(tester, title: '');

    expect(chevrons(), findsOneWidget);
  });

  testWidgets(
    'on phone layout, chevrons are hidden and untitled sections have no header',
    (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.phone);
      await pump(tester, title: '');

      expect(chevrons(), findsNothing);
      expect(find.byType(Spacer), findsNothing);
      expect(tester.getSize(find.byType(HorizontalScrollSection)).height, 80);
    },
  );

  testWidgets('a titled section without chevrons keeps their header height', (
    tester,
  ) async {
    double rowTop() => tester.getTopLeft(find.byKey(const Key('row'))).dy;

    await pump(tester, title: 'Next Up');
    final withChevrons = rowTop();

    await pump(tester, title: 'Next Up', showControls: false);
    expect(rowTop(), withChevrons);
    expect(
      tester
          .widgetList<Visibility>(
            find.ancestor(of: chevrons(), matching: find.byType(Visibility)),
          )
          .map((v) => v.visible),
      contains(false),
    );
  });

  testWidgets('an untitled section with no controls has no header at all', (
    tester,
  ) async {
    // What a TV build gets. There is nothing to put in a header, so neither
    // the header nor the gap that separates it from the row is built.
    await pump(tester, title: '', showControls: false);

    expect(chevrons(), findsNothing);
    // The Spacer only exists to push chevrons right, so its absence is how
    // "no header was built" reads from the outside.
    expect(find.byType(Spacer), findsNothing);
    // 80 is the row on its own: no header, and no contentSpacing above it.
    expect(tester.getSize(find.byType(HorizontalScrollSection)).height, 80);
  });

  testWidgets('the chevrons scroll the row they were given', (tester) async {
    await pump(tester, title: '');
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(controller.offset, 0);

    await tester.tap(chevrons());
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });

  bool arrowsShown(WidgetTester tester) => tester
      .widgetList<Visibility>(
        find.ancestor(of: chevrons(), matching: find.byType(Visibility)),
      )
      .every((v) => v.visible);

  IconButton arrow(WidgetTester tester, IconData icon) => tester.widget(
    find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
  );

  testWidgets('a row whose cards all fit shows no arrows, keeping the header', (
    tester,
  ) async {
    double rowTop() => tester.getTopLeft(find.byKey(const Key('row'))).dy;

    await pump(tester, title: 'Películas');
    final withArrows = rowTop();
    expect(arrowsShown(tester), isTrue);

    await pump(tester, title: 'Películas', rowWidth: 200);
    expect(arrowsShown(tester), isFalse);
    expect(rowTop(), withArrows);
  });

  testWidgets('the arrow pointing past the end the row is at is greyed out', (
    tester,
  ) async {
    await pump(tester, title: 'Películas');
    expect(arrow(tester, Icons.chevron_left).onPressed, isNull);
    expect(arrow(tester, Icons.chevron_right).onPressed, isNotNull);

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(arrow(tester, Icons.chevron_left).onPressed, isNotNull);
    expect(arrow(tester, Icons.chevron_right).onPressed, isNull);

    controller.jumpTo(300);
    await tester.pump();
    expect(arrow(tester, Icons.chevron_left).onPressed, isNotNull);
    expect(arrow(tester, Icons.chevron_right).onPressed, isNotNull);
  });

  testWidgets('arrows appear once a row grows past its width', (tester) async {
    await pump(tester, title: 'Películas', rowWidth: 200);
    expect(arrowsShown(tester), isFalse);

    await pump(tester, title: 'Películas', rowWidth: 3000);
    expect(arrowsShown(tester), isTrue);
  });
}
