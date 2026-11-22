import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/music/kostv_music_widgets.dart';
import 'package:moonfin/ui/widgets/music/design/kostv_music_design.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing_capsule.dart';
import 'package:moonfin/util/focus/input_mode_tracker.dart';
import 'package:moonfin/util/platform_detection.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: InputModeTracker(
    child: Scaffold(
      body: Center(child: SizedBox(width: 520, child: child)),
    ),
  ),
);

/// The white frame of the remote's focus, if any is drawn.
Finder _frame() => find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      ((w.decoration as BoxDecoration).border?.top.color ==
              KostvMusicTokens.ink &&
          (w.decoration as BoxDecoration).border?.top.width == 3),
);

/// Kos TV: the music design's shared pieces (`docs/diseno-musica`).
void main() {
  tearDown(() => PlatformDetection.setTvMode(false));

  group('the play button', () {
    testWidgets('four sizes, the brand\'s gradient and a black icon', (
      tester,
    ) async {
      expect(KostvPlaySize.values.map((s) => s.diameter), [
        84.0,
        64.0,
        44.0,
        32.0,
      ]);
      await tester.pumpWidget(
        _app(const Align(child: KostvPlayButton(size: KostvPlaySize.album))),
      );
      expect(tester.getSize(find.byType(KostvPlayFace)), const Size(64, 64));
      final circle = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(KostvPlayFace),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (circle.decoration as BoxDecoration).gradient,
        KostvMusicTokens.gradient,
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded));
      expect(icon.color, KostvMusicTokens.background);
      await tester.pumpWidget(_app(const KostvPlayButton(pause: true)));
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });

    testWidgets('with the remote: a white frame and bigger; OK plays', (
      tester,
    ) async {
      PlatformDetection.setTvMode(true);
      var played = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _app(
          KostvPlayButton(
            tooltip: 'Reproducir',
            focusNode: node,
            onTap: () => played++,
          ),
        ),
      );
      expect(_frame(), findsNothing);
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(_frame(), findsOneWidget);
      final scale = tester.widget<AnimatedScale>(
        find
            .descendant(
              of: find.byType(KostvPlayFace),
              matching: find.byType(AnimatedScale),
            )
            .first,
      );
      expect(scale.scale, greaterThan(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(played, 1);
      await tester.tap(find.byTooltip('Reproducir'));
      expect(played, 2);
    });
  });

  group('a song\'s row', () {
    Future<FocusNode> row(
      WidgetTester tester, {
      KostvSongSound sound = KostvSongSound.none,
      String? number = '7',
      VoidCallback? onMenu,
      VoidCallback? onTap,
    }) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _app(
          KostvSongRow(
            focusNode: node,
            title: 'Calle',
            subtitle: 'Los Faroleros',
            number: number,
            duration: kostvSongLength(189),
            sound: sound,
            onMenu: onMenu,
            onTap: onTap ?? () {},
          ),
        ),
      );
      return node;
    }

    testWidgets('number, title, artist and time; no button of its own', (
      tester,
    ) async {
      await row(tester, onMenu: () {});
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Calle'), findsOneWidget);
      expect(find.text('Los Faroleros'), findsOneWidget);
      expect(find.text('3:09'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.byType(KostvPlayButton), findsNothing);
      // «⋯» only with the focus or the mouse.
      expect(find.byIcon(Icons.more_horiz_rounded).hitTestable(), findsNothing);
    });

    testWidgets('on the TV, the focus turns the number into ▶ and shows «⋯» '
        'with the white frame; OK plays it', (tester) async {
      PlatformDetection.setTvMode(true);
      var played = 0;
      final node = await row(tester, onMenu: () {}, onTap: () => played++);
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(find.text('7'), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      final more = tester.widget<Visibility>(
        find.ancestor(
          of: find.byIcon(Icons.more_horiz_rounded),
          matching: find.byType(Visibility),
        ),
      );
      expect(more.visible, isTrue);
      final box = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(KostvSongRowFace),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final border = (box.decoration! as BoxDecoration).border!;
      expect(border.top.color, KostvMusicTokens.ink);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(played, 1);
    });

    testWidgets('with the mouse over it, ▶ and «⋯», and «⋯» opens its menu', (
      tester,
    ) async {
      var menus = 0;
      var played = 0;
      await row(tester, onMenu: () => menus++, onTap: () => played++);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Calle')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      expect((menus, played), (1, 0));
      await tester.tap(find.text('Calle'));
      expect((menus, played), (1, 1));
    });

    testWidgets('the song that sounds: the equalizer instead of its number', (
      tester,
    ) async {
      await row(tester, sound: KostvSongSound.playing);
      expect(find.text('7'), findsNothing);
      final bars = tester.widget<KostvEqualizerBars>(
        find.byType(KostvEqualizerBars),
      );
      expect(bars.playing, isTrue);
      expect(bars.gradient, KostvMusicTokens.gradient);
      // Paused, the bars stand still.
      await row(tester, sound: KostvSongSound.paused);
      expect(
        tester
            .widget<KostvEqualizerBars>(find.byType(KostvEqualizerBars))
            .playing,
        isFalse,
      );
    });

    testWidgets('follows the player by its id', (tester) async {
      KostvNowPlaying.instance.debugReset();
      await tester.pumpWidget(
        _app(KostvSongRow(title: 'Calle', soundingId: 'x', onTap: () {})),
      );
      // Nothing sounds: no equalizer.
      expect(find.byType(KostvEqualizerBars), findsNothing);
    });

    testWidgets('a list\'s row (KostvMusicSongRow) is this row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          KostvMusicSongRow(
            title: 'Calle',
            artist: 'Los Faroleros',
            rank: 3,
            duration: 180,
            atHome: true,
            onTap: () {},
          ),
        ),
      );
      expect(find.byType(KostvSongRow), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('3:00'), findsOneWidget);
    });
  });

  group('a card', () {
    testWidgets('with the focus on the TV: the white frame, 7 % bigger and '
        'its play button; OK opens it', (tester) async {
      PlatformDetection.setTvMode(true);
      var opened = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _app(
          KostvMusicAlbumTile(
            title: 'Faroles',
            subtitle: 'Los Faroleros',
            size: 172,
            focusNode: node,
            onTap: () => opened++,
          ),
        ),
      );
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.byType(KostvPlayFace),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(opacity(), 0);
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      final frame = tester.widget<KostvFocusFrame>(
        find.byType(KostvFocusFrame),
      );
      expect(frame.lit, isTrue);
      expect(frame.scale, KostvMusicTokens.focusScale);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(opened, 1);
    });

    testWidgets('with the mouse, its ▶ plays and the rest opens it', (
      tester,
    ) async {
      var opened = 0;
      var played = 0;
      await tester.pumpWidget(
        _app(
          KostvMusicAlbumTile(
            title: 'Faroles',
            size: 172,
            onTap: () => opened++,
            onPlay: () => played++,
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(KostvMusicCover)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(KostvPlayFace));
      expect((opened, played), (0, 1));
      await tester.tap(find.text('Faroles'));
      expect((opened, played), (1, 1));
    });

    testWidgets('an artist\'s circle has no play button', (tester) async {
      await tester.pumpWidget(
        _app(
          KostvMusicAlbumTile(title: 'Lola Brisa', circle: true, onTap: () {}),
        ),
      );
      expect(find.byType(KostvPlayFace), findsNothing);
    });
  });

  testWidgets('a quick access and a shelf\'s heading', (tester) async {
    var opened = 0;
    var played = 0;
    await tester.pumpWidget(
      _app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KostvShelfHeader(
              title: 'Top España',
              subtitle: 'Lo más escuchado',
              onPlay: () => played++,
              playTooltip: 'Reproducir',
            ),
            KostvMusicQuickTile(
              title: 'Faroles',
              subtitle: 'Álbum · Los Faroleros',
              width: 268,
              onTap: () => opened++,
            ),
          ],
        ),
      ),
    );
    final title = tester.widget<Text>(find.text('Top España'));
    expect(title.style?.fontFamily, KostvMusicType.titleFamily);
    await tester.tap(find.byTooltip('Reproducir'));
    await tester.tap(find.text('Faroles'));
    expect((opened, played), (1, 1));
    expect(
      tester.getSize(find.byType(KostvMusicQuickTile)).height,
      KostvMusicTokens.tileHeight,
    );
  });

  group('a cover\'s colours', () {
    tearDown(KostvArtworkColors.debugReset);

    test('kept per picture and given at once once known', () async {
      const colors = KostvCoverColors(
        top: Color(0xFF36E58C),
        bottom: Color(0xFF0C2B5E),
        accent: Color(0xFF36E58C),
      );
      expect(KostvArtworkColors.cached('a'), isNull);
      KostvArtworkColors.debugPut('a', colors);
      expect(KostvArtworkColors.cached('a'), colors);
      expect(await KostvArtworkColors.of('a'), colors);
    });

    test('a page\'s wash goes from the colour to Music\'s dark', () {
      final wash = KostvArtworkColors.wash(const Color(0xFF36E58C));
      expect(wash.color, KostvMusicTokens.background);
      expect(wash.gradient, isA<RadialGradient>());
    });
  });
}
