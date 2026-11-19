import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screensaver/screensaver_controller.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the banner on Home puts on one trailer after another by itself,
/// with nobody in front of the TV. The screensaver and the sleep count from
/// the last press of the remote, not from the last trailer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserPreferences prefs;
  late PlaybackManager manager;

  setUp(() async {
    PlatformDetection.setTvMode(true);
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    await prefs.set(UserPreferences.screensaverTimeout, ScreensaverTimeout.m5);
    manager = PlaybackManager();
  });

  tearDown(() {
    PlatformDetection.setTvMode(false);
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    manager.dispose();
  });

  /// Two minutes of trailer, five seconds of slide, over and over.
  void cycleTrailers(
    FakeAsync async,
    ScreensaverController controller, {
    required Duration forAtLeast,
    bool Function()? until,
  }) {
    var elapsed = Duration.zero;
    while (elapsed < forAtLeast && !(until?.call() ?? false)) {
      controller.setMediaBarTrailerActive(true);
      async.elapse(const Duration(minutes: 2));
      controller.setMediaBarTrailerActive(false);
      async.elapse(const Duration(seconds: 5));
      elapsed += const Duration(minutes: 2, seconds: 5);
    }
  }

  test('the screensaver comes once a trailer ends past the wait', () {
    fakeAsync((async) {
      final controller = ScreensaverController(prefs, manager);
      cycleTrailers(
        async,
        controller,
        forAtLeast: const Duration(minutes: 30),
        until: () => controller.visible.value,
      );
      expect(controller.visible.value, isTrue);
      controller.dispose();
    });
  });

  test('never while a trailer plays', () {
    fakeAsync((async) {
      final controller = ScreensaverController(prefs, manager);
      controller.setMediaBarTrailerActive(true);
      async.elapse(const Duration(minutes: 6));
      expect(controller.visible.value, isFalse);

      controller.setMediaBarTrailerActive(false);
      async.elapse(const Duration(milliseconds: 1));
      expect(controller.visible.value, isTrue);
      controller.dispose();
    });
  });

  test('a press of the remote still starts the wait over', () {
    fakeAsync((async) {
      final controller = ScreensaverController(prefs, manager);
      async.elapse(const Duration(minutes: 4));
      controller.notifyInteraction();
      controller.setMediaBarTrailerActive(true);
      async.elapse(const Duration(seconds: 30));
      controller.setMediaBarTrailerActive(false);
      // Four and a half minutes are left from the press, not five from the
      // trailer.
      async.elapse(const Duration(minutes: 4, seconds: 20));
      expect(controller.visible.value, isFalse);
      async.elapse(const Duration(seconds: 20));
      expect(controller.visible.value, isTrue);
      controller.dispose();
    });
  });

  test('the TV goes to sleep with trailers going on', () async {
    await prefs.set(UserPreferences.sleepAfterIdle, 30);
    fakeAsync((async) {
      var exited = false;
      final controller = ScreensaverController(prefs, manager)
        ..exitApp = () async => exited = true;
      cycleTrailers(async, controller, forAtLeast: const Duration(minutes: 31));
      expect(exited, isTrue);
      controller.dispose();
    });
  });

  group('with the screensaver off', () {
    setUp(() => prefs.set(UserPreferences.screensaverEnabled, false));

    test('a banner trailer lets the screen go a while after the last '
        'press, and holds it again with the next', () {
      fakeAsync((async) {
        final controller = ScreensaverController(prefs, manager);
        controller.setMediaBarTrailerActive(true);
        expect(controller.holdsScreenOn, isTrue);

        async.elapse(ScreensaverController.bannerTrailerHoldsScreenFor);
        expect(controller.holdsScreenOn, isFalse);

        controller.notifyInteraction();
        expect(controller.holdsScreenOn, isTrue);
        controller.dispose();
      });
    });

    test('a card preview, started by the person, holds it as before', () {
      fakeAsync((async) {
        final controller = ScreensaverController(prefs, manager);
        controller.setHomePreviewActive(true);
        async.elapse(const Duration(hours: 1));
        expect(controller.holdsScreenOn, isTrue);
        controller.dispose();
      });
    });
  });

  test('on a phone, a touch counts as being there', () {
    PlatformDetection.setTvMode(false);
    PlatformDetection.setInterfaceLayout(InterfaceLayout.phone);
    fakeAsync((async) {
      final controller = ScreensaverController(prefs, manager);
      controller.setMediaBarTrailerActive(true);
      async.elapse(ScreensaverController.bannerTrailerHoldsScreenFor);
      expect(controller.holdsScreenOn, isFalse);

      GestureBinding.instance.handlePointerEvent(
        const PointerDownEvent(position: Offset(10, 10)),
      );
      GestureBinding.instance.handlePointerEvent(
        const PointerUpEvent(position: Offset(10, 10)),
      );
      expect(controller.holdsScreenOn, isTrue);
      controller.dispose();
    });
  });
}
