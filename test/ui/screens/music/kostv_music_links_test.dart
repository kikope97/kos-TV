import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/screens/music/kostv_music_links.dart';
import 'package:moonfin/ui/screens/music/kostv_music_widgets.dart';
import 'package:moonfin/ui/screens/music/kostv_now_playing_screen.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';

class _Manager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();

  @override
  bool get isOfflinePlayback => false;

  @override
  Map<String, dynamic>? get currentOfflineMetadata => null;

  @override
  Stream<void> get sessionEndedStream => const Stream<void>.empty();

  @override
  Stream<void> get repeatedStream => const Stream<void>.empty();

  @override
  Stream<PlaybackBringupState> get bringupStateStream =>
      const Stream<PlaybackBringupState>.empty();

  @override
  PlaybackBringupState get bringupState => const PlaybackBringupState.idle();

  @override
  Stream<void> get playBlockedStream => const Stream<void>.empty();

  @override
  Stream<PlayerBackend> get backendChangedStream =>
      const Stream<PlayerBackend>.empty();

  @override
  PlayerBackend? get backend => null;
}

AggregatedItem _duet() => AggregatedItem(
  id: 'song',
  serverId: 'casa',
  rawData: {
    'Id': 'song',
    'Name': 'Canción a dúo',
    'Type': 'Audio',
    'MediaType': 'Audio',
    'Artists': ['Lola Brisa', 'Pepe Mar'],
    'ArtistItems': [
      {'Name': 'Lola Brisa', 'Id': 'lola'},
      {'Name': 'Pepe Mar', 'Id': 'pepe'},
    ],
    'AlbumArtists': [
      {'Name': 'Lola Brisa', 'Id': 'lola'},
    ],
    'Album': 'Verano',
    'AlbumId': 'verano',
  },
);

/// Kos TV: the artists' and the album's names open their pages, each its
/// own, in the player and in the Music lists; on the TV, with the remote.
void main() {
  tearDown(() async {
    PlatformDetection.setTvMode(false);
    KostvNowPlayingScreen.debugOpen = null;
    KostvNowPlaying.instance.debugReset();
    await GetIt.instance.reset();
  });

  group('the names of a song', () {
    test('each artist opens their own page, and the album its own', () {
      final opened = <String>[];
      final artists = kostvHomeArtistLinks(_duet(), open: opened.add);
      expect(artists.map((link) => link.name), ['Lola Brisa', 'Pepe Mar']);
      for (final link in artists) {
        link.onTap!();
      }
      kostvHomeAlbumLink(_duet(), open: opened.add)!.onTap!();
      expect(opened, [
        Destinations.item('lola', serverId: 'casa'),
        Destinations.item('pepe', serverId: 'casa'),
        Destinations.item('verano', serverId: 'casa'),
      ]);
    });

    test(
      'an album\'s artists are its own; «Varios artistas» opens nothing',
      () {
        final album = AggregatedItem(
          id: 'mix',
          serverId: 'casa',
          rawData: {
            'Id': 'mix',
            'Type': 'MusicAlbum',
            'AlbumArtist': 'Various Artists',
            'AlbumArtists': [
              {'Name': 'Various Artists', 'Id': 'va'},
            ],
          },
        );
        final links = kostvHomeArtistLinks(
          album,
          albumArtists: true,
          open: (_) => fail('it opens nothing'),
        );
        expect(links.single.name, 'Various Artists');
        expect(links.single.opens, isFalse);
        expect(kostvMusicIsVarious('Varios artistas'), isTrue);
        expect(kostvMusicIsVarious('Vanesa Martín'), isFalse);
      },
    );

    test('an artist the server gives no id for is only shown', () {
      final song = AggregatedItem(
        id: 's',
        serverId: 'casa',
        rawData: {
          'Id': 's',
          'Type': 'Audio',
          'Artists': ['Nadie'],
        },
      );
      final links = kostvHomeArtistLinks(song, open: (_) {});
      expect(links.single.opens, isFalse);
      expect(kostvHomeAlbumLink(song, open: (_) {}), isNull);
    });
  });

  group('a row of a list', () {
    Future<List<String>> pumpRow(WidgetTester tester) async {
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: KostvMusicSongRow(
                title: 'Canción a dúo',
                artist: 'Lola Brisa, Pepe Mar · Verano',
                artistLinks: [
                  kostvHomeArtistLinks(_duet(), open: events.add),
                  [kostvHomeAlbumLink(_duet(), open: events.add)!],
                ],
                atHome: true,
                onTap: () => events.add('play'),
              ),
            ),
          ),
        ),
      );
      return events;
    }

    Offset nameIn(WidgetTester tester, String name) {
      final rich = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText() == 'Lola Brisa, Pepe Mar · Verano',
      );
      final paragraph = tester.renderObject<RenderParagraph>(rich);
      final text = paragraph.text.toPlainText();
      final start = text.indexOf(name);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + name.length),
      );
      return paragraph.localToGlobal(boxes.first.toRect().center);
    }

    testWidgets('a name opens its page; the rest of the row plays', (
      tester,
    ) async {
      final events = await pumpRow(tester);
      await tester.tapAt(nameIn(tester, 'Pepe Mar'));
      await tester.tapAt(nameIn(tester, 'Verano'));
      await tester.tap(find.text('Canción a dúo'));
      expect(events, [
        Destinations.item('pepe', serverId: 'casa'),
        Destinations.item('verano', serverId: 'casa'),
        'play',
      ]);
    });

    testWidgets('on the TV the row stays one stop: OK plays', (tester) async {
      PlatformDetection.setTvMode(true);
      final events = await pumpRow(tester);
      expect(find.text('Lola Brisa, Pepe Mar · Verano'), findsOneWidget);
      Focus.of(tester.element(find.text('Canción a dúo'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(events, ['play']);
    });
  });

  group('«Reproduciendo»', () {
    late List<String> opened;

    Future<void> openPlayer(WidgetTester tester, {required bool tv}) async {
      PlatformDetection.setTvMode(tv);
      final manager = _Manager();
      GetIt.instance.registerSingleton<PlaybackManager>(manager);
      manager.queueService.setQueue([_duet()]);
      opened = [];
      KostvNowPlayingScreen.debugOpen = opened.add;
      tester.view.physicalSize = tv
          ? const Size(1920, 1080)
          : const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const KostvNowPlayingScreen()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
    }

    String? focusedText() {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) return null;
      String? found;
      void visit(Element element) {
        final widget = element.widget;
        if (found == null && widget is Text && widget.data != null) {
          found = widget.data;
        }
        element.visitChildElements(visit);
      }

      (focused as Element).visitChildElements(visit);
      return found;
    }

    Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    testWidgets('on the TV, the remote goes up to each name and OK opens it', (
      tester,
    ) async {
      await openPlayer(tester, tv: true);
      // The player opens on play/pause; up, the progress bar, then the names.
      await key(tester, LogicalKeyboardKey.arrowUp);
      await key(tester, LogicalKeyboardKey.arrowUp);
      for (var i = 0; i < 4; i++) {
        await key(tester, LogicalKeyboardKey.arrowLeft);
      }
      expect(focusedText(), 'Lola Brisa');
      await key(tester, LogicalKeyboardKey.select);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedText(), 'Pepe Mar');
      await key(tester, LogicalKeyboardKey.select);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedText(), 'Verano');
      await key(tester, LogicalKeyboardKey.select);
      expect(opened, [
        Destinations.item('lola', serverId: 'casa'),
        Destinations.item('pepe', serverId: 'casa'),
        Destinations.item('verano', serverId: 'casa'),
      ]);

      // Down goes back to the controls as before.
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedText(), isNull, reason: 'the play button has no text');
    });

    testWidgets('on a phone, a tap on a name opens it', (tester) async {
      await openPlayer(tester, tv: false);
      await tester.tap(find.text('Pepe Mar'));
      await tester.tap(find.text('Verano'));
      expect(opened, [
        Destinations.item('pepe', serverId: 'casa'),
        Destinations.item('verano', serverId: 'casa'),
      ]);
    });
  });

  testWidgets('an album page\'s artist is a stop of the remote too', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: KostvMusicLinkButtons(
              groups: [kostvHomeArtistLinks(_duet(), open: opened.add)],
              style: const TextStyle(color: kostvMusicColor, fontSize: 22),
              centred: true,
            ),
          ),
        ),
      ),
    );
    Focus.of(tester.element(find.text('Pepe Mar'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(opened, [Destinations.item('pepe', serverId: 'casa')]);
  });
}
