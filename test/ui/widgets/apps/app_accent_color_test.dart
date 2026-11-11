import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/installed_apps_service.dart';
import 'package:moonfin/ui/widgets/apps/app_accent_color.dart';

/// [count] pixels of each colour, opaque unless given with alpha.
Uint8List _pixels(Map<Color, int> colors) {
  final out = <int>[];
  colors.forEach((color, count) {
    for (var i = 0; i < count; i++) {
      out.addAll([
        (color.r * 255).round(),
        (color.g * 255).round(),
        (color.b * 255).round(),
        (color.a * 255).round(),
      ]);
    }
  });
  return Uint8List.fromList(out);
}

double _hue(Color c) => HSVColor.fromColor(c).hue;

void main() {
  test('a red logo on black reads as red, not black', () {
    final color = accentFromRgba(
      _pixels({const Color(0xFF141414): 900, const Color(0xFFE50914): 100}),
    );
    expect(color, isNotNull);
    final hue = _hue(color!);
    expect(hue < 15 || hue > 345, isTrue, reason: 'hue $hue');
  });

  test('blue and purple read as blue', () {
    final color = accentFromRgba(
      _pixels({
        const Color(0xFF101018): 600,
        const Color(0xFF00A4DC): 200,
        const Color(0xFF7B52C9): 120,
      }),
    );
    expect(color, isNotNull);
    expect(_hue(color!), inInclusiveRange(180, 220));
  });

  test('orange on white reads as orange', () {
    final color = accentFromRgba(
      _pixels({Colors.white: 500, const Color(0xFFFF5500): 500}),
    );
    expect(color, isNotNull);
    expect(_hue(color!), inInclusiveRange(10, 35));
  });

  test('greys, or a few stray coloured pixels, have no colour', () {
    expect(
      accentFromRgba(_pixels({Colors.black: 700, Colors.white: 300})),
      isNull,
    );
    expect(
      accentFromRgba(_pixels({Colors.black: 995, const Color(0xFFFF0000): 5})),
      isNull,
    );
    expect(accentFromRgba(_pixels({const Color(0x00FF0000): 100})), isNull);
  });

  test('a dark colour is brightened so it shows on a dark screen', () {
    final color = accentFromRgba(_pixels({const Color(0xFF3A0008): 100}));
    expect(color, isNotNull);
    expect(HSLColor.fromColor(color!).lightness, greaterThanOrEqualTo(0.47));
  });

  testWidgets('reads the colour from the app banner, once', (tester) async {
    AppAccentColors.clearForTesting();
    final png = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 64, 36),
        Paint()..color = const Color(0xFF0F0F0F),
      );
      canvas.drawRect(
        const Rect.fromLTWH(16, 8, 32, 20),
        Paint()..color = const Color(0xFF1ED760),
      );
      final image = await recorder.endRecording().toImage(64, 36);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final app = InstalledApp(
      packageName: 'com.example.green',
      label: 'Green',
      art: png,
      isBanner: true,
    );
    expect(AppAccentColors.isKnown(app), isFalse);
    final color = await tester.runAsync(() => AppAccentColors.of(app));
    expect(color, isNotNull);
    expect(_hue(color!), inInclusiveRange(120, 160));
    expect(AppAccentColors.isKnown(app), isTrue);
    expect(AppAccentColors.cached(app), color);
  });
}
