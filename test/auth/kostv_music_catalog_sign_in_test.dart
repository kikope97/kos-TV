import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';

// Kos TV: «Qué música enseñar» is read as the person signs in only where
// Music can be looked at.
void main() {
  test('read with a screen, a way to the server and no kids mode', () {
    expect(
      kostvReadsMusicCatalogAtSignIn(
        headless: false,
        canReachServer: true,
        kidsMode: false,
      ),
      isTrue,
    );
  });

  test('not without a screen, without the server, nor in kids mode', () {
    for (final (headless, reach, kids) in [
      (true, true, false),
      (false, false, false),
      (false, true, true),
    ]) {
      expect(
        kostvReadsMusicCatalogAtSignIn(
          headless: headless,
          canReachServer: reach,
          kidsMode: kids,
        ),
        isFalse,
      );
    }
  });
}
