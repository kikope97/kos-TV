import 'package:flutter/foundation.dart' show SynchronousFuture;
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

  group('Kos TV: a card\'s ▶ with a finger', () {
    setUp(() => InputModeTracker.touchInUse.value = false);
    tearDown(() {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
      InputModeTracker.touchInUse.value = false;
    });

    double playOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byType(KostvPlayFace),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    testWidgets('on the phone the ▶ stays on it, smaller, and a tap on it '
        'plays; the rest of the card opens', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.phone);
      var opened = 0;
      var played = 0;
      await tester.pumpWidget(
        _app(
          KostvMusicAlbumTile(
            title: 'Faroles',
            size: 150,
            onTap: () => opened++,
            onPlay: () => played++,
          ),
        ),
      );
      expect(playOpacity(tester), 1);
      expect(tester.getSize(find.byType(KostvPlayFace)).width, 30);
      await tester.tap(find.byType(KostvPlayFace));
      expect((opened, played), (0, 1));
      await tester.tap(find.text('Faroles'));
      expect((opened, played), (1, 1));
    });

    testWidgets('on the phone, a card that only opens has no ▶', (
      tester,
    ) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.phone);
      await tester.pumpWidget(
        _app(KostvMusicAlbumTile(title: 'Faroles', size: 150, onTap: () {})),
      );
      expect(playOpacity(tester), 0);
    });

    testWidgets('on the web, a finger on the screen shows it; the mouse '
        'hides it again', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      var played = 0;
      await tester.pumpWidget(
        _app(
          KostvMusicAlbumTile(
            title: 'Faroles',
            size: 190,
            onTap: () {},
            onPlay: () => played++,
          ),
        ),
      );
      expect(playOpacity(tester), 0);
      // A finger anywhere (here on the title, which opens it).
      await tester.tap(find.text('Faroles'));
      await tester.pumpAndSettle();
      expect(InputModeTracker.touchInUse.value, isTrue);
      expect(playOpacity(tester), 1);
      await tester.tap(find.byType(KostvPlayFace));
      expect(played, 1);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(InputModeTracker.touchInUse.value, isFalse);
      expect(playOpacity(tester), 0);
    });

    testWidgets('on the TV OK opens it, and its menu (OK held down) has '
        '«Reproducir»', (tester) async {
      PlatformDetection.setTvMode(true);
      var opened = 0;
      var played = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _app(
          KostvMusicAlbumTile(
            title: 'Faroles',
            size: 172,
            focusNode: node,
            onTap: () => opened++,
            onPlay: () => played++,
          ),
        ),
      );
      node.requestFocus();
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Faroles'));
      await tester.pumpAndSettle();
      expect(find.text('Reproducir'), findsOneWidget);
      await tester.tap(find.text('Reproducir'));
      await tester.pumpAndSettle();
      expect((opened, played), (0, 1));
    });
  });

  group('Kos TV: a row follows only its own song', () {
    tearDown(KostvNowPlaying.instance.debugReset);

    testWidgets('another song starting doesn\'t redraw it; its own does', (
      tester,
    ) async {
      final music = KostvNowPlaying.instance..debugReset();
      music.sounding.value = (id: null, playing: false);
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              KostvSongRow(title: 'Calle', soundingId: 'a', onTap: () {}),
              KostvSongRow(title: 'Luna', soundingId: 'b', onTap: () {}),
            ],
          ),
        ),
      );
      KostvSongRowFace face(String title) => tester.widget<KostvSongRowFace>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(KostvSongRowFace),
        ),
      );
      final luna = face('Luna');
      music.sounding.value = (id: 'a', playing: true);
      await tester.pump();
      expect(face('Calle').sound, KostvSongSound.playing);
      expect(identical(face('Luna'), luna), isTrue, reason: 'not redrawn');
      music.sounding.value = (id: 'a', playing: false);
      await tester.pump();
      expect(face('Calle').sound, KostvSongSound.paused);
      expect(identical(face('Luna'), luna), isTrue);
      music.sounding.value = (id: 'b', playing: true);
      await tester.pump();
      expect(face('Calle').sound, KostvSongSound.none);
      expect(face('Luna').sound, KostvSongSound.playing);
    });

    testWidgets('«⋯» always at hand where it is asked to be (the phone\'s '
        'queue)', (tester) async {
      var menu = 0;
      await tester.pumpWidget(
        _app(
          KostvSongRow(
            title: 'Calle',
            onTap: () {},
            onMenu: () => menu++,
            menuAlways: true,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      expect(menu, 1);
    });
  });

  group('Kos TV: a cover\'s colours, by the picture', () {
    tearDown(KostvArtworkColors.debugReset);

    test('a home server\'s picture is read small, the same for every size', () {
      const big =
          'https://casa.example/Items/al1/Images/Primary?maxWidth=600&tag=t1&quality=90';
      const player =
          'https://casa.example/Items/al1/Images/Primary?maxHeight=96&tag=t1&quality=90';
      final small = KostvArtworkColors.smallUrl(big);
      expect(small, KostvArtworkColors.smallUrl(player));
      expect(Uri.parse(small).queryParameters, {
        'maxHeight': '96',
        'quality': '90',
        'tag': 't1',
      });
      const colors = KostvCoverColors(
        top: Color(0xFF36E58C),
        bottom: Color(0xFF0C2B5E),
        accent: Color(0xFF36E58C),
      );
      // Known from the player's: the album's page has it at once.
      KostvArtworkColors.debugPut(player, colors);
      expect(KostvArtworkColors.cached(big), colors);
    });

    test('a Deezer picture at its small copy; any other as it is', () {
      expect(
        KostvArtworkColors.smallUrl(
          'https://cdn-images.dzcdn.net/images/cover/abc/1000x1000-000000-80-0-0.jpg',
        ),
        'https://cdn-images.dzcdn.net/images/cover/abc/120x120-000000-80-0-0.jpg',
      );
      expect(
        KostvArtworkColors.smallUrl('https://covers.example.org/a.jpg'),
        'https://covers.example.org/a.jpg',
      );
    });

    test('one that couldn\'t be read isn\'t waited for again for a while', () {
      KostvArtworkColors.debugFail('https://covers.example.org/a.jpg');
      final colors = KostvArtworkColors.of('https://covers.example.org/a.jpg');
      expect(colors, isA<SynchronousFuture<KostvCoverColors>>());
      expect(
        KostvArtworkColors.cached('https://covers.example.org/a.jpg'),
        isNull,
      );
    });
  });
}
