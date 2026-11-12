import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/kos_intro.dart';
import 'package:moonfin/ui/widgets/kos_intro_video.dart';

/// Kos TV: the opening video falls back to the drawn intro where the video
/// can't play, and the start still moves on.
void main() {
  const channel = MethodChannel('org.moonfin.androidtv/platform');
  late List<String> asked;

  setUp(() {
    asked = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          asked.add(call.method);
          return call.method == 'introSoundAllowed' ? false : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('without a video player it plays the drawn intro and finishes', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KosIntroVideo(onFinished: () => finished++)),
      ),
    );
    // media_kit isn't initialized in tests, so no first frame ever comes and
    // the drawn intro takes over once the wait for it runs out.
    await tester.pump();
    await tester.pump(
      KosIntroVideo.firstFrameTimeout + const Duration(milliseconds: 100),
    );
    expect(find.byType(KosIntro), findsOneWidget);
    expect(finished, 0);

    await tester.pump(KosIntro.duration + const Duration(milliseconds: 200));
    expect(finished, 1);
    // On Android it asked whether the phone's ringer lets the intro sound.
    expect(asked, contains('introSoundAllowed'));
    await tester.pumpWidget(const SizedBox());
  });

  test('the video is the one delivered, untouched', () {
    expect(KosIntroVideo.asset, 'assets/intro/kostv_intro.mp4');
    expect(File(KosIntroVideo.asset).existsSync(), isTrue);
    expect(File(KosIntroVideo.asset1080).existsSync(), isTrue);
  });

  test('a screen drawn in 1080p gets the 1080p copy; one drawn in 4K, the 4K '
      'video', () {
    // Almost every TV draws its interface in 1080p, whatever its panel.
    expect(
      KosIntroVideo.assetFor(const Size(1920, 1080)),
      KosIntroVideo.asset1080,
    );
    // Phones, upright or on their side.
    expect(
      KosIntroVideo.assetFor(const Size(1080, 2400)),
      KosIntroVideo.asset1080,
    );
    expect(
      KosIntroVideo.assetFor(const Size(2560, 1440)),
      KosIntroVideo.asset1080,
    );
    expect(KosIntroVideo.assetFor(const Size(3840, 2160)), KosIntroVideo.asset);
  });

  test('a device not keeping up: frames dropped, or the picture behind the '
      'sound', () {
    expect(KosIntroVideo.isStruggling(dropped: 0, behind: 0.02), isFalse);
    expect(KosIntroVideo.isStruggling(dropped: 3, behind: -0.1), isFalse);
    expect(KosIntroVideo.isStruggling(dropped: 20, behind: 0), isTrue);
    expect(KosIntroVideo.isStruggling(dropped: 0, behind: 0.8), isTrue);
    expect(KosIntroVideo.isStruggling(dropped: 0, behind: -0.8), isTrue);
  });
}
