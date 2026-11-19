import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/navigation_layout.dart';
import 'package:moonfin/ui/widgets/top_toolbar.dart';
import 'package:moonfin/util/platform_detection.dart';

import 'bottom_nav/bottom_nav_fakes.dart';

final _fade = find.byKey(const ValueKey('toolbarPillFade'));
final _shade = find.byKey(const ValueKey('kostvToolbarScrollShade'));

Widget _pill({required double width, required int buttons}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: 44,
        child: ToolbarPillScroll(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < buttons; i++)
                SizedBox(width: 48, child: Text('b$i')),
            ],
          ),
        ),
      ),
    ),
  ),
);

ToolbarPillScrollState _pillState(WidgetTester tester) =>
    tester.state<ToolbarPillScrollState>(find.byType(ToolbarPillScroll));

ScrollPosition _pillPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(ToolbarPillScroll),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

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

void main() {
  group('menu buttons that do not fit', () {
    testWidgets('nothing fades when every button is in view', (tester) async {
      await tester.pumpWidget(_pill(width: 400, buttons: 5));
      await tester.pump();
      expect(_fade, findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
    });

    testWidgets('the edge with buttons beyond it fades, and follows the '
        'scroll', (tester) async {
      await tester.pumpWidget(_pill(width: 200, buttons: 10));
      await tester.pump();
      expect(_fade, findsOneWidget);
      expect(_pillState(tester).hiddenBefore, isFalse);
      expect(_pillState(tester).hiddenAfter, isTrue);

      await tester.drag(find.text('b1'), const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(_pillState(tester).hiddenBefore, isTrue);
      expect(_pillState(tester).hiddenAfter, isTrue);

      final position = _pillPosition(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(_pillState(tester).hiddenBefore, isTrue);
      expect(_pillState(tester).hiddenAfter, isFalse);
      expect(_fade, findsOneWidget);
    });

    testWidgets('a mouse wheel turning up and down scrolls them sideways', (
      tester,
    ) async {
      await tester.pumpWidget(_pill(width: 200, buttons: 10));
      await tester.pump();
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        mouse.hover(tester.getCenter(find.byType(ToolbarPillScroll))),
      );
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
      await tester.pump();
      expect(_pillPosition(tester).pixels, 120);
      expect(_pillState(tester).hiddenBefore, isTrue);
    });

    testWidgets('a mouse can drag them', (tester) async {
      await tester.pumpWidget(_pill(width: 200, buttons: 10));
      await tester.pump();
      await tester.drag(
        find.text('b1'),
        const Offset(-100, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(_pillPosition(tester).pixels, greaterThan(0));
    });
  });

  group('shade behind the top bar', () {
    setUp(() async {
      final prefs = (await setUpBottomNav()).prefs;
      await prefs.set(UserPreferences.navbarPosition, NavbarPosition.top);
    });

    tearDown(tearDownBottomNav);

    testWidgets('comes in once the page scrolls under the bar and goes at '
        'the top', (tester) async {
      usePhoneView(tester);
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
      usePhoneView(tester);
      await tester.pumpWidget(bottomNavApp(child: _page()));
      await tester.pump();

      await tester.drag(find.text('card 1'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(_shade, findsNothing);
    });

    testWidgets('not on the TV, where the bar slides away instead', (
      tester,
    ) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(bottomNavApp(child: _page()));
      await tester.pump();

      await tester.drag(find.text('row 5'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(_shade, findsNothing);
      expect(find.byType(TopToolbar), findsOneWidget);
    });

    testWidgets('stays out without the menu on screen', (tester) async {
      usePhoneView(tester);
      await tester.pumpWidget(bottomNavApp(chrome: false, child: _page()));
      await tester.pump();

      await tester.drag(find.text('row 5'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(_shade, findsNothing);
      expect(NavigationLayout.trailerHidesChrome, isFalse);
    });
  });
}
