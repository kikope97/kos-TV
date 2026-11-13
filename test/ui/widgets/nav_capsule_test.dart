import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/navigation/menu_preview.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';
import 'package:moonfin/ui/widgets/nav_capsule.dart';

/// Three buttons under a capsule; [active] says which one wants it.
class _Bar extends StatelessWidget {
  const _Bar({required this.active, this.covers});

  final int? active;
  final Map<int, List<double>>? covers;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: NavCapsule(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                NavCapsuleTarget(
                  key: ValueKey(i),
                  active: active == i,
                  builder: (context, cover) {
                    covers?.putIfAbsent(i, () => []).add(cover);
                    return SizedBox(width: 100, height: 40, child: Text('$i'));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

NavCapsuleState _capsule(WidgetTester tester) =>
    tester.state<NavCapsuleState>(find.byType(NavCapsule));

void main() {
  group('NavCapsule', () {
    testWidgets('hidden until a button takes it', (tester) async {
      await tester.pumpWidget(const _Bar(active: null));
      await tester.pumpAndSettle();
      expect(_capsule(tester).rect, isNull);
      expect(_capsule(tester).engaged, isFalse);
    });

    testWidgets('settles on the button that takes it', (tester) async {
      await tester.pumpWidget(const _Bar(active: 0));
      await tester.pumpAndSettle();
      final capsule = _capsule(tester);
      expect(capsule.engaged, isTrue);
      expect(capsule.opacity, 1);
      expect(capsule.rect, const Rect.fromLTWH(0, 0, 100, 40));
    });

    testWidgets('glides to the next one, stretching on the way', (
      tester,
    ) async {
      await tester.pumpWidget(const _Bar(active: 0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const _Bar(active: 2));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 50));
      final moving = _capsule(tester).rect!;
      // On its way: the leading edge ahead of the trailing one by more than a
      // button, as a drop stretches.
      expect(moving.left, greaterThan(0));
      expect(moving.right, lessThan(300));
      expect(moving.width, greaterThan(100));
      await tester.pumpAndSettle();
      expect(_capsule(tester).rect, const Rect.fromLTWH(200, 0, 100, 40));
    });

    testWidgets('fades when nothing wants it', (tester) async {
      await tester.pumpWidget(const _Bar(active: 1));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const _Bar(active: null));
      await tester.pumpAndSettle();
      expect(_capsule(tester).rect, isNull);
      expect(_capsule(tester).engaged, isFalse);
    });

    testWidgets('builds each button plain and dark', (tester) async {
      final covers = <int, List<double>>{};
      await tester.pumpWidget(_Bar(active: 0, covers: covers));
      await tester.pumpAndSettle();
      expect(covers[0], containsAll(<double>[0, 1]));
      // The dark look of a button it isn't on is cut away entirely.
      expect(
        _capsule(tester).shapeOver(tester.element(find.text('2').first)),
        isNull,
      );
      expect(
        _capsule(tester).shapeOver(tester.element(find.text('0').first)),
        isNotNull,
      );
    });

    testWidgets('appears in place when asked to snap', (tester) async {
      NavCapsule.snapNextFrame();
      await tester.pumpWidget(const _Bar(active: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_capsule(tester).rect, const Rect.fromLTWH(100, 0, 100, 40));
      expect(_capsule(tester).opacity, 1);
      NavCapsule.endSnapping();
      await tester.pumpAndSettle();
    });
  });

  group('MenuPreview.movedAlong', () {
    testWidgets('sideways keys move along the top bar, up and down the side '
        'bar', (tester) async {
      MenuPreview.track();
      await tester.pumpWidget(const SizedBox());
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(MenuPreview.movedAlong(Axis.horizontal), isTrue);
      expect(MenuPreview.movedAlong(Axis.vertical), isFalse);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowDown);
      expect(MenuPreview.movedAlong(Axis.horizontal), isFalse);
      expect(MenuPreview.movedAlong(Axis.vertical), isTrue);
    });

    test('nothing is held before a page is shown', () {
      expect(MenuPreview.holding, isFalse);
      expect(MenuPreview.arriving.value, isNull);
    });
  });

  group('Destinations.menuPages', () {
    test('the pages the menu opens', () {
      expect(Destinations.isMenuPage(Destinations.home), isTrue);
      expect(Destinations.isMenuPage(Destinations.search), isTrue);
      expect(Destinations.isMenuPage(Destinations.myList), isTrue);
      expect(Destinations.isMenuPage('/item/abc'), isFalse);
      expect(Destinations.isMenuPage(null), isFalse);
    });
  });

  group('HomeViewModel.withRewatchRow', () {
    const a = HomeRow(id: 'a', title: 'A', rowType: HomeRowType.latestMedia);
    const rewatch = HomeRow(
      id: 'kostvRec_rewatch',
      title: 'Tus favoritos para volver a ver',
      rowType: HomeRowType.latestMedia,
    );
    const shuffle = HomeRow(
      id: 'kostv_shuffle',
      title: 'Aleatorio',
      rowType: HomeRowType.latestMedia,
    );

    test('goes last, just above Shuffle', () {
      final rows = HomeViewModel.withShuffleRow(
        HomeViewModel.withRewatchRow([a], rewatch),
        shuffle,
        hasRows: true,
      );
      expect(rows.map((r) => r.id), ['a', 'kostvRec_rewatch', 'kostv_shuffle']);
    });

    test('never alone on an empty Home', () {
      expect(HomeViewModel.withRewatchRow([], rewatch), isEmpty);
      expect(HomeViewModel.withRewatchRow([a], null), [a]);
    });
  });

  group('HomeViewModel.withShuffleRow', () {
    const a = HomeRow(id: 'a', title: 'A', rowType: HomeRowType.latestMedia);
    const shuffle = HomeRow(
      id: 'kostv_shuffle',
      title: 'Aleatorio',
      rowType: HomeRowType.latestMedia,
    );

    test('closes Home', () {
      expect(
        HomeViewModel.withShuffleRow([a], shuffle, hasRows: true).last.id,
        'kostv_shuffle',
      );
    });

    test('waits for something above it', () {
      expect(
        HomeViewModel.withShuffleRow([], shuffle, hasRows: false),
        isEmpty,
      );
    });

    test('nothing to add without it', () {
      expect(HomeViewModel.withShuffleRow([a], null, hasRows: true), [a]);
    });
  });
}
