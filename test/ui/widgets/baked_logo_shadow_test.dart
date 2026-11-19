import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/baked_blur_image.dart';
import 'package:moonfin/ui/widgets/baked_logo_shadow.dart';

// 40x20 opaque white: a logo that fills its box.
Future<MemoryImage> _logo() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 40, 20),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(40, 20);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return MemoryImage(png!.buffer.asUint8List());
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
}

Future<ui.Image> _paintedImage(WidgetTester tester) async =>
    tester.widget<RawImage>(find.byType(RawImage)).image!;

Future<(int, int, int, int)> _pixel(
  WidgetTester tester,
  ui.Image image,
  int x,
  int y,
) async {
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final i = (y * image.width + x) * 4;
  return (
    bytes.getUint8(i),
    bytes.getUint8(i + 1),
    bytes.getUint8(i + 2),
    bytes.getUint8(i + 3),
  );
}

void main() {
  testWidgets('the shadow is baked once, tinted, with room to spread', (
    tester,
  ) async {
    final logo = (await tester.runAsync(_logo))!;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1),
        child: Center(
          child: SizedBox(
            width: 80,
            height: 40,
            child: BakedLogoShadow(
              image: logo,
              color: const Color(0xFF000000),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    final baked = await _paintedImage(tester);
    // The box (80x40) plus 3 sigma of room on each side.
    expect((baked.width, baked.height), (98, 58));
    // In the middle of the logo: tinted black, fully there.
    final middle = await _pixel(tester, baked, 49, 29);
    expect(middle.$1, lessThan(10));
    expect(middle.$4, greaterThan(240));
    // Past the logo's edge, the blur spreads out and fades.
    final spread = await _pixel(tester, baked, 7, 29);
    expect(spread.$4, inExclusiveRange(0, 200));
    expect((await _pixel(tester, baked, 0, 0)).$4, lessThan(20));

    // Painted where the live blur was: the box, grown by the room.
    final painted = tester.getRect(find.byType(RawImage));
    final box = tester.getRect(find.byType(BakedLogoShadow));
    expect(painted, box.inflate(9));
  });

  testWidgets('a logo that fails shows the fallback', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 80,
          height: 40,
          child: BakedLogoShadow(
            image: MemoryImage(Uint8List.fromList([1, 2, 3])),
            color: const Color(0xFF000000),
            fallback: const Text('Título'),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Título'), findsOneWidget);
  });

  testWidgets('a blurred picture can be baked through a colour filter', (
    tester,
  ) async {
    final logo = (await tester.runAsync(_logo))!;
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 40,
          height: 20,
          child: BakedBlurImage(
            image: logo,
            sigma: 1,
            colorFilter: const ColorFilter.mode(
              Color(0xFF000000),
              BlendMode.srcATop,
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    final baked = await _paintedImage(tester);
    final middle = await _pixel(tester, baked, 20, 10);
    expect(middle.$1, lessThan(10));
  });
}
