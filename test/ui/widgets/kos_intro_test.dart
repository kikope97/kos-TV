import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/kos_intro.dart';
import 'package:moonfin/ui/widgets/overlay_sheet.dart';

void main() {
  const channel = MethodChannel('org.moonfin.androidtv/platform');
  final calls = <String>[];

  /// The device's side of the sound: [allowed] is whether it may sound, and
  /// the player takes [startsAfter] to start.
  void device({bool allowed = false, Duration startsAfter = Duration.zero}) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'introSoundAllowed':
              return allowed;
            case 'introSoundPlay':
              await Future<void>.delayed(startsAfter);
              return true;
          }
          return null;
        });
  }

  setUp(device);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  /// Lets the intro ask for its sound and start.
  Future<void> started(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('it runs its length and then says it is done, once', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: KosIntro(onFinished: () => finished++)),
    );
    // Where no sound can play, the picture starts on its own.
    await started(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(finished, 0);
    await tester.pump(KosIntro.duration);
    await tester.pump(const Duration(seconds: 1));
    expect(finished, 1);
  });

  testWidgets('any key skips it', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: KosIntro(onFinished: () => finished++)),
    );
    await started(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(finished, 1);
    await tester.pump(KosIntro.duration);
    expect(finished, 1);
  });

  testWidgets('a tap skips it', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: KosIntro(onFinished: () => finished++)),
    );
    await started(tester);
    await tester.tap(find.byType(KosIntro));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('with animations turned off it is done at once', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: KosIntro(key: UniqueKey(), onFinished: () => finished++),
        ),
      ),
    );
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('a message under it stays on show after the end', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KosIntro(
          onFinished: () => finished++,
          footer: const Text('Sin conexión'),
        ),
      ),
    );
    await started(tester);
    await tester.pump(KosIntro.duration);
    await tester.pump(const Duration(seconds: 1));
    expect(finished, 1);
    expect(find.text('Sin conexión'), findsOneWidget);
    // Still drawing: the logo is kept up for the message.
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('the picture starts when the sound does, and a skip stops it', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    device(allowed: true, startsAfter: const Duration(milliseconds: 400));
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: KosIntro(onFinished: () => finished++)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // The sound hasn't started: nothing is moving yet.
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(calls, ['introSoundAllowed', 'introSoundPlay']);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(finished, 1);
    expect(calls.last, 'introSoundStop');
    debugDefaultTargetPlatformOverride = null;
  });

  KosIntroPainter painterOf(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byType(KosIntro),
                  matching: find.byType(CustomPaint),
                ),
              )
              .painter!
          as KosIntroPainter;

  testWidgets('Back skips it and goes no further, only while it plays', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: KosIntro(onFinished: () => finished++)),
    );
    await started(tester);
    // The remote's Back, the phone's back gesture and Escape all ask the
    // app's back handlers first, before its exit prompt.
    expect(InlineBackInterceptor.handleBack(), isTrue);
    expect(finished, 1);
    // Over, it no longer takes Back.
    expect(InlineBackInterceptor.handleBack(), isFalse);
    await tester.pump(KosIntro.duration);
  });

  testWidgets('it says when it has faded to black, once', (tester) async {
    var fadedOut = 0;
    await tester.pumpWidget(
      MaterialApp(home: KosIntro(onFadedOut: () => fadedOut++)),
    );
    await started(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(fadedOut, 0);
    await tester.pump(KosIntro.duration);
    await tester.pump(const Duration(seconds: 1));
    expect(fadedOut, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a message after the end brings the logo back where it was, '
      'and it stays once the message goes', (tester) async {
    var fadedOut = 0;
    Widget intro({Widget? footer}) => MaterialApp(
      home: KosIntro(onFadedOut: () => fadedOut++, footer: footer),
    );
    await tester.pumpWidget(intro());
    await started(tester);
    await tester.pump(KosIntro.duration);
    await tester.pump(const Duration(seconds: 1));
    expect(fadedOut, 1);
    final end = painterOf(tester).seconds.value;
    expect(end, greaterThanOrEqualTo(KosIntro.duration.inMilliseconds / 1000));

    await tester.pumpWidget(intro(footer: const Text('Sin conexión')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    // It carries on from the end instead of pressing the power button again.
    expect(painterOf(tester).seconds.value, greaterThan(end));
    expect(painterOf(tester).fades!.value, isFalse);

    // Retry pressed: the message goes, the logo stays while it retries.
    await tester.pumpWidget(intro());
    await tester.pump(const Duration(milliseconds: 100));
    expect(painterOf(tester).fades!.value, isFalse);
    expect(fadedOut, 1);
  });

  testWidgets('the sound stops when the app leaves the screen', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    device(allowed: true);
    await tester.pumpWidget(const MaterialApp(home: KosIntro()));
    await started(tester);
    expect(calls, ['introSoundAllowed', 'introSoundPlay']);
    // The TV's Home button.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(calls.last, 'introSoundStop');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(KosIntro.duration);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a device that never answers about the sound holds it up '
      'for a moment only', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    device(allowed: true, startsAfter: const Duration(minutes: 1));
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(home: KosIntro(onFinished: () => finished++)),
    );
    await tester.pump(KosIntro.soundWait + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(KosIntro.duration);
    expect(finished, 1);
    await tester.pump(const Duration(minutes: 1));
    debugDefaultTargetPlatformOverride = null;
  });
}
