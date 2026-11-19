import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/detail_page.dart';

/// A page with one row of three cards, each sending its keys to [rowKeys].
class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with DetailPage<_Page> {
  final cards = List.generate(3, (i) => FocusNode(debugLabel: 'card-$i'));

  @override
  ItemDetailViewModel get pageViewModel => throw UnimplementedError();

  @override
  UserPreferences get pagePrefs => throw UnimplementedError();

  @override
  ValueChanged<bool>? get pageNavbarToggle => null;

  @override
  void moveUp(FocusNode node) {}

  @override
  void moveDown(FocusNode node) {}

  @override
  void dispose() {
    for (final node in cards) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = rowKeys(cards.first, cards.length);
    return Row(
      children: [
        for (final (index, node) in cards.indexed)
          Focus(
            focusNode: node,
            onKeyEvent: (_, event) => keys(index, event),
            child: const SizedBox(width: 100, height: 100),
          ),
      ],
    );
  }
}

/// Kos TV: Left and Right move along a detail page's rows by themselves. On
/// the web the app's shortcuts scroll the row with them instead, which left
/// focus on a card that slid under the frame's edge.
void main() {
  // Shortcuts that do nothing with the arrows, as the web's scroll does
  // nothing for focus.
  Future<_PageState> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              DoNothingAndStopPropagationIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              DoNothingAndStopPropagationIntent(),
        },
        builder: (_, _) => const _Page(),
      ),
    );
    return tester.state<_PageState>(find.byType(_Page));
  }

  testWidgets('Right and Left move focus along the row', (tester) async {
    final page = await pump(tester);
    page.cards.first.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(page.cards[1].hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(page.cards[2].hasPrimaryFocus, isTrue);

    // The last card keeps focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(page.cards[2].hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(page.cards[1].hasPrimaryFocus, isTrue);
  });

  testWidgets('Left off the first card is left to the app', (tester) async {
    final page = await pump(tester);
    page.cards.first.requestFocus();
    await tester.pump();

    final keys = page.rowKeys(page.cards.first, page.cards.length);
    expect(
      keys(
        0,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowLeft,
          logicalKey: LogicalKeyboardKey.arrowLeft,
          timeStamp: Duration.zero,
        ),
      ),
      KeyEventResult.ignored,
    );
  });
}
