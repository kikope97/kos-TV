import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/l10n/app_localizations.dart';
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
  bool get isOfflinePlayback => true;

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

  final picked = <int>[];

  @override
  Future<void> playFromQueue(int index) async {
    picked.add(index);
    queueService.jumpTo(index);
  }
}

AggregatedItem _song(String id) => AggregatedItem(
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

/// Kos TV: «A continuación» with the remote. OK on a song opens its menu;
/// the remote follows the song as it moves and stays on its place as it
/// goes.
void main() {
  late _Manager manager;
  late List<AggregatedItem> songs;

  setUp(() {
    PlatformDetection.setTvMode(true);
    manager = _Manager();
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
    songs = [
      for (final id in ['a', 'b', 'c', 'd']) _song(id),
    ];
    manager.queueService.setQueue(songs);
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    KostvNowPlaying.instance.debugReset();
    await GetIt.instance.reset();
  });

  List<String> upcoming() => [
    for (final item in manager.queueService.items.skip(
      manager.queueService.currentIndex + 1,
    ))
      (item as AggregatedItem).id,
  ];

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  String? focusedSong() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return null;
    final texts = <String>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Text && (widget.data ?? '').startsWith('Canción ')) {
        texts.add(widget.data!);
      }
      element.visitChildElements(visit);
    }

    (focused as Element).visitChildElements(visit);
    return texts.isEmpty ? null : texts.first;
  }

  Future<void> openQueue(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
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
    await tester.tap(find.byIcon(Icons.queue_music_rounded));
    await tester.pumpAndSettle();
    // Into the list, on its first song, as the remote would, and OK.
    Focus.of(tester.element(find.text('Canción b'))).requestFocus();
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.select);
  }

  testWidgets('OK opens the menu, and the remote follows the song moved', (
    tester,
  ) async {
    await openQueue(tester);
    // OK opened the first song's menu; nothing played.
    expect(find.text('Reproducir ahora'), findsOneWidget);
    expect(find.text('Subir'), findsNothing, reason: 'it is the first');
    expect(find.text('Bajar'), findsOneWidget);
    expect(manager.picked, isEmpty);

    await tester.tap(find.text('Bajar'));
    await tester.pumpAndSettle();
    expect(upcoming(), ['c', 'b', 'd']);
    expect(focusedSong(), 'Canción b');

    // With the remote now: OK, then down to «Subir» and OK.
    await key(tester, LogicalKeyboardKey.select);
    expect(find.text('Subir'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.select);
    expect(upcoming(), ['b', 'c', 'd']);
    expect(focusedSong(), 'Canción b');
  });

  testWidgets('taking a song away leaves the remote on its place', (
    tester,
  ) async {
    await openQueue(tester);
    await tester.tap(find.text('Quitar de la cola'));
    await tester.pumpAndSettle();
    expect(upcoming(), ['c', 'd']);
    expect(focusedSong(), 'Canción c');

    // The last one: the remote goes to the one before.
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedSong(), 'Canción d');
    await key(tester, LogicalKeyboardKey.select);
    await tester.tap(find.text('Quitar de la cola'));
    await tester.pumpAndSettle();
    expect(upcoming(), ['c']);
    expect(focusedSong(), 'Canción c');
  });

  testWidgets('«Reproducir ahora» plays it, and the remote goes to the top', (
    tester,
  ) async {
    await openQueue(tester);
    // Closed with Back: the remote is back on its song.
    await key(tester, LogicalKeyboardKey.escape);
    expect(find.text('Reproducir ahora'), findsNothing);
    expect(focusedSong(), 'Canción b');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedSong(), 'Canción c');
    await key(tester, LogicalKeyboardKey.select);
    await tester.tap(find.text('Reproducir ahora'));
    await tester.pumpAndSettle();
    expect(manager.picked, [2]);
    expect(upcoming(), ['d']);
    expect(focusedSong(), 'Canción d');
  });

  testWidgets('a song gone while its menu was open is left alone', (
    tester,
  ) async {
    await openQueue(tester);
    manager.queueService.jumpTo(1);
    await tester.pump();
    await tester.tap(find.text('Quitar de la cola'));
    await tester.pumpAndSettle();
    expect(upcoming(), ['c', 'd']);
  });
}
