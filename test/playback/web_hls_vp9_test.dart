import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/device_profile_builder.dart';

void main() {
  bool offers({
    bool supportsVp9 = true,
    bool isIOS = false,
    bool canPlayNativeHls = false,
    bool supportsVp9InMse = false,
  }) => DeviceProfileBuilder.offersVp9InWebHls(
    supportsVp9: supportsVp9,
    isIOS: isIOS,
    canPlayNativeHls: canPlayNativeHls,
    supportsVp9InMse: supportsVp9InMse,
  );

  test('a desktop or Android browser keeps VP9 in HLS', () {
    expect(offers(), isTrue);
  });

  test('a browser without VP9 is never offered it', () {
    expect(offers(supportsVp9: false), isFalse);
  });

  test('an iPhone on Safari\'s own HLS is not offered VP9 in HLS', () {
    expect(
      offers(isIOS: true, canPlayNativeHls: true, supportsVp9InMse: true),
      isFalse,
    );
  });

  test('an iOS browser on hls.js needs MediaSource to take VP9', () {
    expect(offers(isIOS: true), isFalse);
    expect(offers(isIOS: true, supportsVp9InMse: true), isTrue);
  });
}
