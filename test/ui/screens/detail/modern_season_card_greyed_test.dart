import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/detail/modern/widgets/season_card.dart';
import 'package:moonfin/ui/widgets/focus/focusable_wrapper.dart';

// Kos TV: a season the home server lacks was greyed by a filter around the
// whole card, which greyed the focus frame too and cost a layer per card.

void main() {
  Widget app(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  SeasonCard card({required bool greyed}) => SeasonCard(
    title: 'Season 3',
    subtitle: 'Not at home',
    imageUrl: null,
    isFallbackImage: true,
    landscape: true,
    onTap: () {},
    greyed: greyed,
  );

  testWidgets('a greyed season keeps the focus frame out of the filter', (
    tester,
  ) async {
    await tester.pumpWidget(app(card(greyed: true)));

    expect(find.byType(ColorFiltered), findsNothing);
    expect(
      find.descendant(
        of: find.byType(FocusableWrapper),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color.a > 0.4 && w.color.a < 0.5,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a season at home is drawn as before', (tester) async {
    await tester.pumpWidget(app(card(greyed: false)));

    expect(find.byType(ColorFiltered), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color.a > 0.4 && w.color.a < 0.5,
      ),
      findsNothing,
    );
  });
}
