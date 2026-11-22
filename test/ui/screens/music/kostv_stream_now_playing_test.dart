import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/playback/kostv_stream_playback.dart';
import 'package:moonfin/playback/stremfin_stream_resolver.dart';
import 'package:moonfin/ui/screens/music/kostv_now_playing_screen.dart';
import 'package:moonfin/ui/screens/music/kostv_stream_widgets.dart';
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

  final bringup = StreamController<PlaybackBringupState>.broadcast(sync: true);
  PlaybackBringupState current = const PlaybackBringupState.idle();

  void fail(String itemId) {
    current = PlaybackBringupState(
      phase: PlaybackBringupPhase.failed,
      itemId: itemId,
    );
    bringup.add(current);
  }

  @override
  Stream<PlaybackBringupState> get bringupStateStream => bringup.stream;

  @override
  PlaybackBringupState get bringupState => current;

  int nexts = 0;
  final picked = <int>[];

  @override
  Future<void> nextInQueue() async {
    nexts++;
    queueService.next(manual: true);
  }

  @override
  Future<void> playFromQueue(int index) async => picked.add(index);

  @override
  Stream<void> get playBlockedStream => const Stream<void>.empty();

  @override
  Stream<PlayerBackend> get backendChangedStream =>
      const Stream<PlayerBackend>.empty();

  @override
  PlayerBackend? get backend => null;
}

AggregatedItem _stream(String id) => kostvStreamItem(
  deezerId: id,
  title: 'Canción $id',
  serverId: 'casa',
  artist: 'Lola Brisa',
  album: 'Disco',
  durationSeconds: 200,
  albumDeezerId: 'al$id',
);

AggregatedItem _home(String id) => AggregatedItem(
  id: id,
  serverId: 'casa',
  rawData: {
    'Id': id,
    'Name': 'Canción $id',
    'Type': 'Audio',
    'MediaType': 'Audio',
    'Artists': ['Lola Brisa'],
  },
);

/// Kos TV: «Reproduciendo» with a song that isn't at home: «Preparando la
/// canción…» while its sound is got ready, the line with «Pedir el álbum»,
/// no ♥ nor lyrics, and (the music design) no mark in the queue.
void main() {
  late _Manager manager;

  setUp(() {
    StremfinStreamResolver.debugReset();
    KostvStreamPlayback.instance.debugReset();
    manager = _Manager();
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
    manager.queueService.setQueue([_stream('1'), _home('h'), _stream('2')]);
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    StremfinStreamResolver.debugReset();
    KostvNowPlaying.instance.debugReset();
    KostvStreamPlayback.instance.debugReset();
    await GetIt.instance.reset();
  });

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
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
    await tester.pump(const Duration(milliseconds: 500));
  }

  String? focusedText() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return null;
    final texts = <String>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text && widget.data != null) texts.add(widget.data!);
      element.visitChildElements(visit);
    }

    (focused as Element).visitChildElements(visit);
    return texts.join(' ');
  }

  testWidgets('on the TV: «Preparando…» only after a moment, after 20 s '
      '«Está tardando…», the line, and the remote reaches «Pedir el álbum»', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    StremfinStreamResolver.preparing.value = 'stremfin:1';
    await open(tester, const Size(1920, 1080));
    // Kos TV: the music design: no flash of it for a song that starts at
    // once (it shows after 1.5 s).
    expect(find.text('Preparando la canción…'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Preparando la canción…'), findsOneWidget);
    // Calm: it doesn't say it isn't at home (the line does).
    expect(find.textContaining('No está en casa'), findsNothing);
    expect(find.byType(KostvPulse), findsOneWidget);
    await tester.pump(const Duration(seconds: 21));
    expect(find.text('Está tardando más de lo normal'), findsOneWidget);
    StremfinStreamResolver.preparing.value = null;
    await tester.pumpAndSettle();
    expect(find.text('Preparando la canción…'), findsNothing);
    expect(find.text('Suena en streaming · no está en casa'), findsOneWidget);
    expect(find.text('Pedir el álbum'), findsOneWidget);
    // Calm: no cloud anywhere.
    expect(find.byIcon(Icons.cloud_outlined), findsNothing);
    // ♥ and the lyrics are the home server's.
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.byIcon(Icons.notes_rounded), findsNothing);
    // From play/pause up to the pill's button.
    for (var i = 0; i < 4 && !(focusedText() ?? '').contains('Pedir'); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
    }
    expect(focusedText(), contains('Pedir el álbum'));
  });

  testWidgets('on the phone: the line, and the queue doesn\'t mark the songs '
      'that aren\'t at home', (tester) async {
    await open(tester, const Size(393, 852));
    await tester.pumpAndSettle();
    // Kos TV: the phone's shorter line.
    expect(find.text('En streaming · no está en casa'), findsOneWidget);
    expect(find.text('Pedir el álbum'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.byIcon(Icons.notes_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.queue_music_rounded));
    await tester.pumpAndSettle();
    // Kos TV: the phone's queue comes up in a sheet.
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('Canción h'), findsOneWidget);
    expect(find.text('Canción 2'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsNothing);
    expect(find.byTooltip('No está en casa'), findsNothing);
  });

  testWidgets('a song at home has none of it', (tester) async {
    manager.queueService.setQueue([_home('h'), _stream('2')]);
    await open(tester, const Size(1440, 900));
    await tester.pumpAndSettle();
    expect(find.text('Suena en streaming · no está en casa'), findsNothing);
    expect(find.byIcon(Icons.notes_rounded), findsOneWidget);
  });

  testWidgets('Kos TV: on the computer the queue stays open at the side, with '
      'its tabs, the song sounding and «Vaciar»', (tester) async {
    manager.queueService.setQueue([_home('h'), _stream('2'), _home('h3')]);
    await open(tester, const Size(1440, 900));
    await tester.pumpAndSettle();
    expect(find.text('Cola'), findsOneWidget);
    expect(find.text('Letra'), findsOneWidget);
    expect(find.text('SONANDO'), findsOneWidget);
    expect(find.text('A CONTINUACIÓN'), findsOneWidget);
    // The song sounding is in the panel (and the player's title).
    expect(find.text('Canción h'), findsNWidgets(2));
    expect(find.text('Canción 2'), findsOneWidget);
    expect(find.text('Canción h3'), findsOneWidget);
    await tester.tap(find.text('Vaciar'));
    await tester.pumpAndSettle();
    expect(manager.queueService.items.length, 1);
    expect(find.text('Canción 2'), findsNothing);
    expect(find.text('No hay más canciones en la cola'), findsOneWidget);
    expect(find.text('Vaciar'), findsNothing);
  });

  testWidgets('turned out to be at home: the home server\'s song takes its '
      'place in the queue', (tester) async {
    await open(tester, const Size(1440, 900));
    await tester.pumpAndSettle();
    StremfinStreamResolver.noteAtHome(
      manager.queueService.currentItem as AggregatedItem,
      _home('j1'),
    );
    await tester.pumpAndSettle();
    expect((manager.queueService.currentItem as AggregatedItem).id, 'j1');
    expect(find.text('Suena en streaming · no está en casa'), findsNothing);
  });

  group('a song that can\'t start', () {
    test('nobody can listen to it (404): on to the next one', () {
      final music = KostvNowPlaying.instance..ensureStarted();
      StremfinStreamResolver.failures['stremfin:1'] =
          KostvStreamFailure.notFound;
      manager.fail('stremfin:1');
      expect(manager.nexts, 1);
      expect((music.item)!.id, 'h');
      expect(music.failed, isFalse);
    });

    test('the service not answering (503): it stays, to try later', () {
      final music = KostvNowPlaying.instance..ensureStarted();
      StremfinStreamResolver.failures['stremfin:1'] =
          KostvStreamFailure.unavailable;
      manager.fail('stremfin:1');
      expect(manager.nexts, 0);
      expect(music.failed, isTrue);
    });

    test('the player couldn\'t open its sound: asked for again once', () {
      final music = KostvNowPlaying.instance..ensureStarted();
      manager.fail('stremfin:1');
      expect(manager.picked, [0]);
      expect(music.failed, isFalse);
      manager.fail('stremfin:1');
      expect(manager.picked, [0]);
      expect(music.failed, isTrue);
    });
  });

  testWidgets('Kos TV: on the TV, the remote on «Pedir el álbum» when the '
      'next song is at home (the line goes) goes to play/pause', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    manager.queueService.setQueue([_stream('1'), _home('h')]);
    await open(tester, const Size(1920, 1080));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4 && !(focusedText() ?? '').contains('Pedir'); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'NowPlayingAskAlbum',
    );
    manager.queueService.next(manual: true);
    await tester.pumpAndSettle();
    expect(find.text('Pedir el álbum'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'NowPlayingPlay');
  });

  testWidgets('Kos TV: on the TV, the remote on ♥ when the next song (one '
      'that isn\'t at home, without ♥) comes goes to play/pause', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    manager.queueService.setQueue([_home('h'), _stream('2')]);
    await open(tester, const Size(1920, 1080));
    await tester.pumpAndSettle();
    final heart = find.byIcon(Icons.favorite_border_rounded);
    expect(heart, findsOneWidget);
    // Through the queue's button first: Flutter alone would send it back
    // there.
    Focus.of(tester.element(find.byIcon(Icons.queue_music_rounded)))
        .requestFocus();
    await tester.pump();
    Focus.of(tester.element(heart)).requestFocus();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'NowPlayingFavorite',
    );
    manager.queueService.next(manual: true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'NowPlayingPlay');
  });

  testWidgets('Kos TV: on the TV, the remote on a line of the lyrics when a '
      'song that isn\'t at home comes goes to play/pause, and doesn\'t jump to '
      '«Letra» when one at home comes back', (tester) async {
    PlatformDetection.setTvMode(true);
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('kostv_lyrics'),
    );
    addTearDown(() => tester.runAsync(() => dir!.delete(recursive: true)));
    final file = File('${dir!.path}/lyrics.json');
    await tester.runAsync(
      () => file.writeAsString(
        jsonEncode({
          'Lyrics': [
            for (var i = 0; i < 4; i++) {'Text': 'Línea $i', 'Start': 0},
          ],
        }),
      ),
    );
    AggregatedItem withLyrics(String id) {
      final song = _home(id);
      return AggregatedItem(
        id: id,
        serverId: song.serverId,
        rawData: {...song.rawData, '_localLyricsPath': file.path},
      );
    }

    manager.queueService.setQueue([
      withLyrics('h'),
      _stream('2'),
      withLyrics('h2'),
    ]);
    // Opened for real, for the song's lyrics to be read from the file.
    await tester.runAsync(() async {
      await open(tester, const Size(1920, 1080));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.notes_rounded));
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Línea 1'))).requestFocus();
    await tester.pump();
    expect(find.text('Línea 1'), findsOneWidget);
    // The next one isn't at home: no lyrics, no «Letra».
    manager.queueService.next(manual: true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notes_rounded), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'NowPlayingPlay');
    // One at home again: «Letra» is back, and the remote stays where it is.
    manager.queueService.next(manual: true);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notes_rounded), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'NowPlayingPlay');
  });
}
