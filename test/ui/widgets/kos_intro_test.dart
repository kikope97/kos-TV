import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/kos_intro.dart';

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
