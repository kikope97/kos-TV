import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/navigation_layout.dart';
import 'package:moonfin/ui/widgets/top_toolbar.dart';
import 'package:moonfin/util/platform_detection.dart';

import 'bottom_nav/bottom_nav_fakes.dart';

final _shade = find.byKey(const ValueKey('kostvToolbarScrollShade'));
final _pill = find.byKey(const ValueKey('kostvToolbarPill'));

Widget _page({ScrollController? controller}) => ListView(
  controller: controller,
  children: [
    SizedBox(
      height: 150,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < 30; i++)
            SizedBox(width: 100, child: Text('card $i')),
        ],
      ),
    ),
    for (var i = 0; i < 80; i++) SizedBox(height: 60, child: Text('row $i')),
  ],
);

/// How visible the TV's pill is (its AnimatedOpacity).
double _pillOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(of: _pill, matching: find.byType(AnimatedOpacity)).first,
    )
    .opacity;

void main() {
  setUp(setUpBottomNav);
  tearDown(tearDownBottomNav);

  void computer(WidgetTester tester) {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  void tv(WidgetTester tester) {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('shade behind the computer\'s top bar', () {
    testWidgets('comes in once the page scrolls under the bar and goes at '
        'the top', (tester) async {
      computer(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        bottomNavApp(child: _page(controller: controller)),
      );
      await tester.pump();
      expect(_shade, findsNothing);

      await tester.drag(find.text('row 5'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(_shade, findsOneWidget);

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_shade, findsNothing);
    });

    testWidgets('a row of cards scrolling sideways leaves it out', (
      tester,
    ) async {
      computer(tester);
      await tester.pumpWidget(bottomNavApp(child: _page()));
      await tester.pump();

      await tester.drag(find.text('card 1'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(_shade, findsNothing);
    });

    testWidgets('stays out without the menu on screen', (tester) async {
      computer(tester);
      await tester.pumpWidget(bottomNavApp(chrome: false, child: _page()));
      await tester.pump();

      await tester.drag(find.text('row 5'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(_shade, findsNothing);
      expect(NavigationLayout.trailerHidesChrome, isFalse);
    });
  });

  // Kos TV: on the TV, scrolled down the page, the bar gathers into a small
  // pill (the avatar and the page's name); with the focus in the bar (Back
  // or Up) it is whole again.
  group('the TV\'s pill', () {
    testWidgets('the bar gathers into it while the page is scrolled', (
      tester,
    ) async {
      tv(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        bottomNavApp(child: _page(controller: controller)),
      );
      await tester.pump();
      expect(_pillOpacity(tester), 0);
      expect(find.text('Home'), findsWidgets);

      controller.jumpTo(600);
      await tester.pumpAndSettle();
      expect(_pillOpacity(tester), 1);
      // No shade on the TV: the pill carries its own glass.
      expect(_shade, findsNothing);

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_pillOpacity(tester), 0);
    });

    testWidgets('the focus in the bar brings it whole, on its page\'s tab', (
      tester,
    ) async {
      tv(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        bottomNavApp(child: _page(controller: controller)),
      );
      await tester.pump();
      controller.jumpTo(600);
      await tester.pumpAndSettle();
      expect(_pillOpacity(tester), 1);

      // What Back (or Up from the first row) does.
      expect(NavigationLayout.focusNavbar(), isTrue);
      await tester.pumpAndSettle();
      expect(TopToolbar.isFocusedNotifier.value, isTrue);
      expect(_pillOpacity(tester), 0);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TopToolbarHome',
      );
    });

    testWidgets('a page that keeps its menu never gathers it', (
      tester,
    ) async {
      tv(tester);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NavigationLayout(
              activeRoute: '/home',
              pinTopToolbar: true,
              child: _page(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      controller.jumpTo(600);
      await tester.pumpAndSettle();
      expect(_pillOpacity(tester), 0);
    });
  });
}
