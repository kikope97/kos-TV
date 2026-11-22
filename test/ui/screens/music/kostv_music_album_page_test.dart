import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/music/kostv_music_page.dart';
import 'package:moonfin/ui/widgets/music/design/kostv_music_design.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:moonfin/util/focus/input_mode_tracker.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: InputModeTracker(child: Scaffold(body: child)),
);

/// [count] songs, the first [focus] given its node.
List<Widget> _rows(int count, {List<FocusNode> nodes = const []}) => [
  for (var i = 0; i < count; i++)
    KostvSongRow(
      key: ValueKey('row$i'),
      focusNode: i < nodes.length ? nodes[i] : null,
      number: '${i + 1}',
      title: 'Canción ${i + 1}',
      duration: '3:0$i',
      onTap: () {},
    ),
];

KostvAlbumPage _page({
  int songs = 10,
  bool away = false,
  List<FocusNode> nodes = const [],
  FocusNode? play,
}) => KostvAlbumPage(
  cover: null,
  kicker: 'Álbum · 2026',
  title: 'Faroles',
  phoneMeta: 'Álbum · 2026 · 10 canciones · 33 min',
  artist: (form) => KostvAlbumArtistLine(
    form: form,
    meta: form == KostvPageForm.phone ? null : '10 canciones · 33 min',
    name: (style) => Text('Los Faroleros', style: style),
  ),
  play: (diameter) => KostvPlayButton(
    focusNode: play,
    diameter: diameter,
    tooltip: 'Reproducir',
    onTap: () {},
  ),
  shuffle: (diameter) => KostvRoundButton(
    icon: Icons.shuffle_rounded,
    tooltip: 'Aleatorio',
    diameter: diameter,
    onTap: () {},
  ),
  more: (diameter) => KostvRoundButton(
    icon: Icons.more_horiz_rounded,
    tooltip: 'Más',
    diameter: diameter,
    onTap: () {},
  ),
  note: away
      ? (compact) => KostvAwayNote(
          lead: 'Este disco no está en casa: suena en streaming.',
          rest: 'Pídelo para tenerlo en casa con más calidad.',
          compact: compact,
          action: const KostvMusicPill(label: 'Pedir el álbum'),
        )
      : null,
  tracks: _rows(songs, nodes: nodes),
);

/// Kos TV: the music design's album page (`docs/diseno-musica`, phase 2):
/// the same pieces on the TV (two columns of songs), a computer (a table)
/// and a phone (one under the other, the note in a card).
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    KostvArtworkColors.debugReset();
    await GetIt.instance.reset();
  });

  void screen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('on the TV, the songs go in two columns: down the first, '
      'then the second, and the remote goes across', (tester) async {
    PlatformDetection.setTvMode(true);
    screen(tester, const Size(1280, 720));
    final nodes = [for (var i = 0; i < 10; i++) FocusNode(debugLabel: '$i')];
    addTearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });
    await tester.pumpWidget(_app(_page(nodes: nodes)));
    await tester.pump();
    final first = tester.getTopLeft(find.byKey(const ValueKey('row0')));
    final sixth = tester.getTopLeft(find.byKey(const ValueKey('row5')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('row1')));
    // 6 is beside 1, 2 under 1.
    expect(sixth.dy, closeTo(first.dy, 1));
    expect(sixth.dx, greaterThan(first.dx + 300));
    expect(second.dy, greaterThan(first.dy));
    expect(second.dx, closeTo(first.dx, 1));
    // No table heading on the TV.
    expect(find.text('TÍTULO'), findsNothing);
    nodes[0].requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(nodes[5].hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(nodes[1].hasFocus, isTrue);
  });

  testWidgets('on the TV the note goes under the buttons, beside the cover', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    screen(tester, const Size(1280, 720));
    await tester.pumpWidget(_app(_page(away: true)));
    await tester.pump();
    final note = tester.getRect(find.byType(KostvAwayNote));
    final play = tester.getRect(find.byType(KostvPlayFace));
    expect(note.top, greaterThan(play.bottom));
    expect(note.left, closeTo(play.left, 2));
    expect(find.text('Pedir el álbum'), findsOneWidget);
    // The play button is the album's (68 on the TV), the round ones 50.
    expect(play.width, 68);
    expect(
      tester.getSize(find.byType(KostvRoundIcon).first),
      const Size(50, 50),
    );
  });

  testWidgets('on a computer, a table of one column with its heading', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
    screen(tester, const Size(1440, 900));
    await tester.pumpWidget(_app(_page(away: true)));
    await tester.pump();
    expect(find.text('TÍTULO'), findsOneWidget);
    expect(find.text('DURACIÓN'), findsOneWidget);
    final first = tester.getTopLeft(find.byKey(const ValueKey('row0')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('row1')));
    expect(second.dx, closeTo(first.dx, 1));
    expect(second.dy, greaterThan(first.dy));
    // The note under the whole header, before the songs.
    final note = tester.getRect(find.byType(KostvAwayNote));
    final cover = tester.getRect(find.byType(KostvPlayFace));
    expect(note.top, greaterThan(cover.bottom));
    expect(note.bottom, lessThan(first.dy));
  });

  testWidgets('on a phone, one column and the note in a card, its button '
      'under the words', (tester) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.phone);
    screen(tester, const Size(393, 852));
    await tester.pumpWidget(_app(_page(away: true)));
    await tester.pump();
    expect(find.text('TÍTULO'), findsNothing);
    expect(find.text('Álbum · 2026 · 10 canciones · 33 min'), findsOneWidget);
    final note = find.byType(KostvAwayNote);
    expect(tester.widget<KostvAwayNote>(note).compact, isTrue);
    final words = tester.getRect(
      find.textContaining('Este disco no está en casa', findRichText: true),
    );
    final ask = tester.getRect(find.text('Pedir el álbum'));
    expect(ask.top, greaterThan(words.bottom));
    // The play button at the right, 56.
    final play = tester.getRect(find.byType(KostvPlayFace));
    expect(play.width, 56);
    expect(play.right, greaterThan(300));
  });

  testWidgets('an album at home has no note at all', (tester) async {
    screen(tester, const Size(1440, 900));
    await tester.pumpWidget(_app(_page()));
    await tester.pump();
    expect(find.byType(KostvAwayNote), findsNothing);
    expect(find.textContaining('streaming', findRichText: true), findsNothing);
  });

  testWidgets('the page takes its cover\'s colour, kept per picture', (
    tester,
  ) async {
    const url = 'https://covers.example.org/faroles.jpg';
    KostvArtworkColors.debugPut(
      url,
      const KostvCoverColors(
        top: Color(0xFF0E6B4A),
        bottom: Color(0xFF06261A),
        accent: Color(0xFF3FE08F),
      ),
    );
    await tester.pumpWidget(
      _app(const KostvArtworkWash(url: url, child: SizedBox.expand())),
    );
    final washed = find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient is RadialGradient,
    );
    expect(washed, findsOneWidget);
    // Unknown picture: plain dark, nothing asked meanwhile in the frame.
    await tester.pumpWidget(
      _app(const KostvArtworkWash(url: null, child: SizedBox.expand())),
    );
    expect(washed, findsNothing);
  });

  testWidgets('an artist\'s top: «ARTISTA», the name and the buttons', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    screen(tester, const Size(1280, 720));
    await tester.pumpWidget(
      _app(
        ListView(
          children: [
            KostvArtistHero(
              name: 'Lola Brisa',
              kicker: 'Artista',
              meta: '3 álbumes',
              play: (diameter) =>
                  KostvPlayButton(diameter: diameter, onTap: () {}),
              pill: (size) => KostvPillButton(
                label: 'Crear emisora',
                icon: Icons.radio_rounded,
                size: size,
                onTap: () {},
              ),
              round: [
                (diameter) => KostvRoundButton(
                  icon: Icons.shuffle_rounded,
                  tooltip: 'Aleatorio',
                  diameter: diameter,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(find.text('ARTISTA'), findsOneWidget);
    expect(find.text('Lola Brisa'), findsOneWidget);
    expect(find.text('Crear emisora'), findsOneWidget);
    expect(tester.getSize(find.byType(KostvPlayFace)), const Size(64, 64));
    final name = tester.widget<Text>(find.text('Lola Brisa'));
    expect(name.style?.fontFamily, KostvMusicType.titleFamily);
  });
}
