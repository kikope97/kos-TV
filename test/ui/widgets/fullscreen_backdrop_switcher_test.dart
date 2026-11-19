import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/fullscreen_backdrop_switcher.dart';
import 'package:moonfin/ui/widgets/image_source.dart';

import '../../support/artwork_fixture.dart';

void main() {
  group('decode bound', _decodeTests);

  Widget app(String? imageUrl) {
    return MaterialApp(
      home: FullscreenBackdropSwitcher(
        imageUrl: imageUrl,
        duration: const Duration(milliseconds: 800),
        imageBuilder: (url) => Text(url),
      ),
    );
  }

  testWidgets('does not restart the backdrop fade during rapid changes', (
    tester,
  ) async {
    await tester.pumpWidget(app('a'));

    await tester.pumpWidget(app('b'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pumpWidget(app('c'));

    final fadeFinder = find.descendant(
      of: find.byType(FullscreenBackdropSwitcher),
      matching: find.byType(FadeTransition),
    );

    // The incoming layer is the last one; the one under it stays opaque.
    final fade = tester.widget<FadeTransition>(fadeFinder.last);

    expect(
      fade.opacity.value,
      greaterThan(0),
      reason: 'rapid changes should not restart the active fade from zero',
    );
  });

  testWidgets('clears all backdrop layers immediately when URL becomes null', (
    tester,
  ) async {
    await tester.pumpWidget(app('a'));

    await tester.pumpWidget(app('b'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(app('c'));

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);

    await tester.pumpWidget(app(null));

    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsNothing);
    expect(find.text('c'), findsNothing);

    final fadeFinder = find.descendant(
      of: find.byType(FullscreenBackdropSwitcher),
      matching: find.byType(FadeTransition),
    );

    expect(fadeFinder, findsNothing);
  });

  testWidgets('drops stale pending backdrop when focus returns to incoming', (
    tester,
  ) async {
    await tester.pumpWidget(app('a'));

    await tester.pumpWidget(app('b'));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.pumpWidget(app('a'));

    await tester.pumpWidget(app('b'));

    await tester.pumpAndSettle();

    expect(find.text('b'), findsOneWidget);
    expect(find.text('a'), findsNothing);
  });

  testWidgets('keeps the incoming backdrop when its fade ends', (tester) async {
    var created = 0;
    Widget counted(String? url) => MaterialApp(
      home: FullscreenBackdropSwitcher(
        imageUrl: url,
        duration: const Duration(milliseconds: 300),
        imageBuilder: (url) =>
            _CountedLayer(label: url, onCreate: () => created++),
      ),
    );

    await tester.pumpWidget(counted('a'));
    expect(created, 1);

    await tester.pumpWidget(counted('b'));
    await tester.pump();
    expect(created, 2);

    await tester.pumpAndSettle();
    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsOneWidget);
    expect(
      created,
      2,
      reason: 'the finished fade must not build the new backdrop again',
    );
  });

  testWidgets('holds the old backdrop until the new one has painted', (
    tester,
  ) async {
    final image = await tester.runAsync(() => createTestImage());
    final loaded = <String>{'a'};
    Widget layered(String? url) => MaterialApp(
      home: FullscreenBackdropSwitcher(
        imageUrl: url,
        duration: const Duration(milliseconds: 300),
        imageBuilder: (url) => Stack(
          children: [
            Text(url),
            RawImage(image: loaded.contains(url) ? image : null),
          ],
        ),
      ),
    );

    await tester.pumpWidget(layered('a'));
    await tester.pumpWidget(layered('b'));
    await tester.pumpAndSettle();

    expect(
      find.text('a'),
      findsOneWidget,
      reason: 'b has not loaded, so a stays underneath it',
    );
    expect(find.text('b'), findsOneWidget);

    loaded.add('b');
    await tester.pumpWidget(layered('b'));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsOneWidget);
    image?.dispose();
  });
}

class _CountedLayer extends StatefulWidget {
  final String label;
  final VoidCallback onCreate;

  const _CountedLayer({required this.label, required this.onCreate});

  @override
  State<_CountedLayer> createState() => _CountedLayerState();
}

class _CountedLayerState extends State<_CountedLayer> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

void _decodeTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final imageCache = PaintingBinding.instance.imageCache;
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moonfin-switcher');
    final png = await writeTestPng(temp, width: 1920, height: 1080);
    CachedNetworkImageProvider.defaultCacheManager = FakeArtworkCacheManager(
      png,
    );
    imageCache.clear();
    ArtworkDecode.resetRememberedBounds();
  });

  tearDown(() async {
    imageCache.clear();
    await temp.delete(recursive: true);
  });

  testWidgets('the default image path decodes a portrait cover at full width', (
    tester,
  ) async {
    // A 390 by 844 phone at 2x. A bound taken from the box width alone would
    // be 780 pixels for a backdrop that paints about 3000 wide.
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const url = 'http://server/Items/1/Images/Backdrop/0?maxWidth=1920';
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FullscreenBackdropSwitcher(
            imageUrl: url,
            duration: Duration(milliseconds: 300),
          ),
        ),
      );
      for (var i = 0; i < 25 && imageCache.currentSize == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
      final key = await ArtworkDecode.provider(
        url,
        width: 1920,
      ).obtainKey(ImageConfiguration.empty);
      expect(imageCache.containsKey(key), isTrue);
      expect(imageCache.currentSize, 1);
    });
  });
}
