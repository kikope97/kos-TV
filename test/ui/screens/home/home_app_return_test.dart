import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/home/home_app_return.dart';

/// Kos TV: coming back to the app reloads Home only after it was away.
void main() {
  test('back from the background, Home loads again', () {
    final appReturn = HomeAppReturn();
    expect(
      [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].map(appReturn.reloadsAt),
      [false, false, false, false, false, true],
    );
  });

  test('the notification shade or a system dialog reloads nothing', () {
    final appReturn = HomeAppReturn();
    expect(appReturn.reloadsAt(AppLifecycleState.inactive), isFalse);
    expect(appReturn.reloadsAt(AppLifecycleState.resumed), isFalse);
  });

  test('a web page hidden and shown again loads again, once', () {
    final appReturn = HomeAppReturn();
    appReturn.reloadsAt(AppLifecycleState.hidden);
    expect(appReturn.reloadsAt(AppLifecycleState.resumed), isTrue);
    expect(appReturn.reloadsAt(AppLifecycleState.resumed), isFalse);
  });
}
