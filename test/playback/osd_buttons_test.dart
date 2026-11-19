import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/playback/osd_buttons.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The tvOS OSD is drawn natively and can't read the preferences itself, so the
// arrangement reaches it as this list of ids. Getting the list wrong is the
// whole setting going missing on that platform.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserPreferences prefs;

  setUp(() async {
    PlatformDetection.setTvMode(true);
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
  });

  tearDown(() => PlatformDetection.setTvMode(false));

  test('keeps only subtitles, language and episodes on the row by default '
      '(Kos TV: the rest waits in «Más»)', () async {
    expect(visibleOsdButtonIds(prefs), [
      OsdButton.syncPlay.id,
      OsdButton.subtitles.id,
      OsdButton.audio.id,
      OsdButton.episodes.id,
    ]);
  });

  test('offers every button a TV can draw and no others', () async {
    await prefs.set(UserPreferences.hiddenOsdButtonsTv, '');
    expect(visibleOsdButtonIds(prefs), [
      OsdButton.syncPlay.id,
      OsdButton.favorite.id,
      OsdButton.speed.id,
      OsdButton.chapters.id,
      OsdButton.subtitles.id,
      OsdButton.audio.id,
      OsdButton.episodes.id,
      OsdButton.castAndCrew.id,
      OsdButton.quality.id,
      OsdButton.zoom.id,
      OsdButton.info.id,
    ]);
  });

  test('drops the buttons switched off for this kind of device', () async {
    await prefs.set(UserPreferences.hiddenOsdButtonsTv, 'favorite,speed');

    final visible = visibleOsdButtonIds(prefs);
    expect(visible, isNot(contains(OsdButton.favorite.id)));
    expect(visible, isNot(contains(OsdButton.speed.id)));
    expect(visible, contains(OsdButton.subtitles.id));
  });

  test('leaves the phone list to phones', () async {
    await prefs.set(UserPreferences.hiddenOsdButtonsMobile, 'subtitles');

    expect(visibleOsdButtonIds(prefs), contains(OsdButton.subtitles.id));
  });

  test(
    'follows the order the user arranged, carrying the rest along',
    () async {
      await prefs.set(UserPreferences.osdButtonOrderTv, 'info,subtitles');
      await prefs.set(UserPreferences.hiddenOsdButtonsTv, 'favorite,speed');

      expect(visibleOsdButtonIds(prefs), [
        // Never placed and declared before anything that was, so they stay put.
        OsdButton.syncPlay.id,
        OsdButton.chapters.id,
        OsdButton.info.id,
        OsdButton.subtitles.id,
        // These follow the button they were declared after.
        OsdButton.audio.id,
        OsdButton.episodes.id,
        OsdButton.castAndCrew.id,
        OsdButton.quality.id,
        OsdButton.zoom.id,
      ]);
    },
  );

  group('osdButtonRow', () {
    Future<List<double>> lefts(WidgetTester tester, {bool? grouped}) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 700,
              child: osdButtonRow(
                buttons: [
                  for (var i = 0; i < 3; i++)
                    SizedBox(key: ValueKey(i), width: 56, height: 56),
                ],
                extent: 56,
                landscape: true,
                grouped: grouped,
              ),
            ),
          ),
        ),
      );
      final row = tester.getRect(find.byType(Row)).left;
      return [
        for (var i = 0; i < 3; i++)
          tester.getRect(find.byKey(ValueKey(i))).left - row,
      ];
    }

    tearDown(
      () => PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic),
    );

    testWidgets('packs the buttons together at the end on a wide screen '
        '(Kos TV: not spread over a whole computer window)', (tester) async {
      PlatformDetection.setTvMode(false);
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      expect(await lefts(tester), [700 - 168, 700 - 112, 700 - 56]);
    });

    testWidgets('packs them at the end on a TV', (tester) async {
      expect(await lefts(tester), [700 - 168, 700 - 112, 700 - 56]);
    });

    testWidgets('keeps them spread on a phone', (tester) async {
      PlatformDetection.setTvMode(false);
      PlatformDetection.setInterfaceLayout(InterfaceLayout.phone);
      final spread = await lefts(tester);
      expect(spread.first, greaterThan(100));
      expect(spread[1] - spread[0], greaterThan(150));
      expect(await lefts(tester, grouped: true), [
        700 - 168,
        700 - 112,
        700 - 56,
      ]);
    });
  });
}
