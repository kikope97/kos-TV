import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/settings/settings_app_bar.dart';
import 'package:moonfin/util/platform_detection.dart';

// Kos TV: a TV's Settings title sits flush, with no empty back-button slot
// before it, as a desktop's does on a screen with nowhere to go back to.
void main() {
  tearDown(
    () => PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic),
  );

  Future<double> titleLeft(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            appBar: buildSettingsAppBar(
              context,
              const Text('Account'),
              leading: const Icon(Icons.close),
            ),
          ),
        ),
      ),
    );
    return tester.getTopLeft(find.text('Account')).dx;
  }

  testWidgets('a TV keeps no leading slot', (tester) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    final left = await titleLeft(tester);
    expect(find.byIcon(Icons.close), findsNothing);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.leading, isNull);
    expect(appBar.automaticallyImplyLeading, isFalse);
    // Only the toolbar's own spacing before the title.
    expect(left, lessThanOrEqualTo(NavigationToolbar.kMiddleSpacing));
  });

  testWidgets('a desktop still shows the leading it is given', (tester) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
    await titleLeft(tester);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
