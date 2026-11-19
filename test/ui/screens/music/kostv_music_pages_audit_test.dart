import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/ui/screens/music/kostv_music_actions.dart';
import 'package:moonfin/ui/screens/music/kostv_music_widgets.dart';
import 'package:moonfin/ui/widgets/music/music_navigation.dart';

/// Kos TV: what the audit of the Music pages found, fixed.
void main() {
  testWidgets('Back during the wait closes only the wait, never the page '
      'under it', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Text('Inicio')),
        routes: {
          '/musica': (context) {
            pageContext = context;
            return const Scaffold(body: Text('Música'));
          },
        },
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/musica');
    await tester.pumpAndSettle();

    final close = showMusicLoading(pageContext);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Back, because it takes long: the wait goes.
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Música'), findsOneWidget);

    // The music is ready: nothing else is closed in its place.
    close();
    await tester.pumpAndSettle();
    expect(find.text('Música'), findsOneWidget);
  });

  testWidgets('the wait goes once the music is ready', (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('Música'));
          },
        ),
      ),
    );
    final close = showMusicLoading(pageContext);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    close();
    close();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Música'), findsOneWidget);
  });

  test('a download that failed isn\'t on its way', () {
    StremfinAlbum withPhase(String phase) => StremfinAlbum.fromJson({
      'title': 'Brisa',
      'download': {'phase': phase},
    })!;
    expect(kostvMusicBadgeOf(withPhase('failed')), KostvMusicBadge.failed);
    expect(
      kostvMusicBadgeOf(withPhase('downloading')),
      KostvMusicBadge.onItsWay,
    );
  });

  // Kos TV: an album's page opened on a TV: the focus on its main button
  // (in the header) keeps the page at its top, with the menu and the cover
  // in sight; a song further down still comes to the middle.
  for (final fromTop in [true, false]) {
    testWidgets(
      'a header button with the focus ${fromTop ? 'keeps the page at its top' : 'comes to the middle'}',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final song = FocusNode();
        addTearDown(song.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                controller: controller,
                children: [
                  const SizedBox(height: 420),
                  KostvMusicPressable(
                    autofocus: true,
                    revealFromTop: fromTop,
                    onTap: () {},
                    builder: (_, _) => const SizedBox(height: 60),
                  ),
                  for (var i = 0; i < 20; i++)
                    KostvMusicPressable(
                      focusNode: i == 4 ? song : null,
                      onTap: () {},
                      builder: (_, _) => const SizedBox(height: 60),
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (fromTop) {
          expect(controller.offset, 0);
        } else {
          expect(controller.offset, greaterThan(0));
        }

        // A song further down comes to the middle either way.
        song.requestFocus();
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(200));
      },
    );
  }
}
