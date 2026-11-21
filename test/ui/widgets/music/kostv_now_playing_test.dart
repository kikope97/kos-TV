import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/playback/stremfin_stream_resolver.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing_capsule.dart';
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

  final _ended = StreamController<void>.broadcast();

  @override
  Stream<void> get sessionEndedStream => _ended.stream;

  int pauses = 0;

  @override
  Future<void> pause() async => pauses++;

  final repeated = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get repeatedStream => repeated.stream;

  final bringup = StreamController<PlaybackBringupState>.broadcast(sync: true);
  PlaybackBringupState current = const PlaybackBringupState.idle();

  void setBringup(PlaybackBringupState state) {
    current = state;
    bringup.add(state);
  }

  @override
  Stream<PlaybackBringupState> get bringupStateStream => bringup.stream;

  @override
  PlaybackBringupState get bringupState => current;

  @override
  Stream<void> get playBlockedStream => const Stream<void>.empty();

  final picked = <int>[];
  int resumes = 0;

  @override
  Future<void> playFromQueue(int index) async => picked.add(index);

  @override
  Future<void> resume() async => resumes++;

  int stops = 0;

  @override
  Future<void> stop({bool userInitiated = true}) async {
    stops++;
    queueService.clear();
  }

  @override
  PlayerBackend? backend = _Backend();

  final backends = StreamController<PlayerBackend>.broadcast(sync: true);

  @override
  Stream<PlayerBackend> get backendChangedStream => backends.stream;
}

class _Backend extends Fake implements PlayerBackend {
  final volumes = <double>[];

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
}

AggregatedItem _item(String id, String type) => AggregatedItem(
  id: id,
  serverId: 'casa',
  rawData: {
    'Id': id,
    'Name': 'Verano',
    'Type': type,
    if (type == 'Audio') 'MediaType': 'Audio',
    'Artists': ['Lola Brisa'],
  },
);

/// Kos TV: the music sounding in the app, for the floating player.
void main() {
  late _Manager manager;

  setUp(() {
    manager = _Manager();
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
  });

  tearDown(() {
    KostvNowPlaying.debugHasOwnVolume = null;
    KostvNowPlaying.instance.debugReset();
    return GetIt.instance.reset();
  });

  group('what sounds', () {
    test('a song is the music sounding; a film is not', () {
      final music = KostvNowPlaying.instance;
      manager.queueService.setQueue([_item('s1', 'Audio')]);
      expect(music.item?.id, 's1');
      expect(music.artistOf(music.item!), 'Lola Brisa');
      manager.queueService.setQueue([_item('m1', 'Movie')]);
      expect(music.item, isNull);
      manager.queueService.clear();
      expect(music.item, isNull);
    });

    // Kos TV: «Preparando…» and «Está tardando…» are the song sounding's.
    test('the next song prepared ahead neither redraws nor starts the wait '
        'for «tardando»; it counts from when it sounds', () {
      fakeAsync((async) {
        addTearDown(() => StremfinStreamResolver.preparing.value = null);
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([
          _item('s1', 'Audio'),
          _item('s2', 'Audio'),
        ]);
        async.flushMicrotasks();
        var redraws = 0;
        void redraw() => redraws++;
        music.addListener(redraw);
        addTearDown(() => music.removeListener(redraw));

        StremfinStreamResolver.preparing.value = 's2';
        StremfinStreamResolver.preparing.value = null;
        StremfinStreamResolver.preparing.value = 's2';
        expect(redraws, 0);
        expect(music.preparing, isFalse);
        async.elapse(const Duration(seconds: 15));

        // The song before ended and it isn't ready yet.
        manager.queueService.next();
        async.flushMicrotasks();
        expect(music.preparing, isTrue);
        async.elapse(const Duration(seconds: 10));
        expect(music.preparingSlow, isFalse);
        async.elapse(const Duration(seconds: 11));
        expect(music.preparingSlow, isTrue);
        final before = redraws;
        StremfinStreamResolver.preparing.value = null;
        expect(redraws, before + 1);
        expect(music.preparing, isFalse);
        expect(music.preparingSlow, isFalse);
      });
    });

    test('the sleep timer pauses the music when it is up', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance;
        manager.queueService.setQueue([_item('s1', 'Audio')]);
        music.setSleep(const Duration(minutes: 15));
        expect(music.sleepAt, isNotNull);
        async.elapse(const Duration(minutes: 14));
        expect(manager.pauses, 0);
        async.elapse(const Duration(minutes: 2));
        expect(manager.pauses, 1);
        expect(music.sleepAt, isNull);
      });
    });

    test('with the music closed, the timer goes with it', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([_item('s1', 'Audio')]);
        async.flushMicrotasks();
        music.setSleep(const Duration(minutes: 15));
        manager.queueService.clear();
        async.flushMicrotasks();
        expect(music.sleepAt, isNull);
        async.elapse(const Duration(hours: 1));
        expect(manager.pauses, 0);
      });
    });

    test('«at the end of this song» pauses when the next one starts', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([_item('s1', 'Audio')]);
        async.flushMicrotasks();
        music.sleepAfterSong();
        expect(music.sleepsAfterSong, isTrue);
        expect(manager.pauses, 0);
        manager.queueService.setQueue([_item('s2', 'Audio')]);
        async.flushMicrotasks();
        expect(manager.pauses, 1);
        expect(music.sleepsAfterSong, isFalse);
      });
    });

    // Kos TV: with repeat-one the song starts over with the same id.
    test('«at the end of this song» pauses a song on repeat-one', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([_item('s1', 'Audio')]);
        async.flushMicrotasks();
        music.sleepAfterSong();
        manager.repeated.add(null);
        async.flushMicrotasks();
        expect(manager.pauses, 1);
        expect(music.sleepsAfterSong, isFalse);
      });
    });

    test('a song the person skips to is not paused', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([_item('s1', 'Audio')]);
        async.flushMicrotasks();
        music.sleepAfterSong();
        // What the notification's, the headphones' and the bottom bar's ⏭
        // now say before moving on.
        music.noteChosen();
        manager.queueService.setQueue([_item('s2', 'Audio')]);
        async.flushMicrotasks();
        expect(manager.pauses, 0);
        expect(music.sleepsAfterSong, isTrue);
      });
    });

    test('a timer taken off never pauses it', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance;
        music.setSleep(const Duration(minutes: 15));
        music.setSleep(null);
        async.elapse(const Duration(hours: 1));
        expect(manager.pauses, 0);
      });
    });
  });

  // Kos TV: a song that couldn't start used to leave a paused player whose
  // ⏯ resumed nothing.
  group('a song that cannot start', () {
    test('is marked failed, and ⏯ tries it again', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([
          _item('s1', 'Audio'),
          _item('s2', 'Audio'),
        ], startIndex: 1);
        async.flushMicrotasks();
        manager.setBringup(
          const PlaybackBringupState(
            phase: PlaybackBringupPhase.failed,
            itemId: 's2',
          ),
        );
        expect(music.failed, isFalse, reason: 'it may still recover');
        async.elapse(const Duration(seconds: 2));
        expect(music.failed, isTrue);

        music.playPause();
        expect(manager.picked, [1]);
        expect(manager.resumes, 0);
        expect(music.failed, isFalse);
      });
    });

    test('a recovery in time is not told', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([_item('s1', 'Audio')]);
        async.flushMicrotasks();
        manager.setBringup(
          const PlaybackBringupState(
            phase: PlaybackBringupPhase.failed,
            itemId: 's1',
          ),
        );
        manager.setBringup(
          const PlaybackBringupState(phase: PlaybackBringupPhase.ready),
        );
        async.elapse(const Duration(seconds: 2));
        expect(music.failed, isFalse);
      });
    });

    // Kos TV: the player still names the start by the out-of-home song it
    // was before it turned out to be at home.
    test('one that turned out to be at home while it was prepared is still '
        'told when it fails', () {
      fakeAsync((async) {
        addTearDown(StremfinStreamResolver.debugReset);
        final music = KostvNowPlaying.instance..ensureStarted();
        final home = _item('j7', 'Audio');
        StremfinStreamResolver.atHome['stremfin:7'] = home;
        manager.queueService.setQueue([home]);
        async.flushMicrotasks();
        manager.setBringup(
          const PlaybackBringupState(
            phase: PlaybackBringupPhase.failed,
            itemId: 'stremfin:7',
          ),
        );
        expect(music.tellsStartFailure(), isTrue);
        async.elapse(const Duration(seconds: 2));
        expect(music.failed, isTrue);
        // Another song's start is still not this one's.
        manager.setBringup(
          const PlaybackBringupState(phase: PlaybackBringupPhase.ready),
        );
        manager.setBringup(
          const PlaybackBringupState(
            phase: PlaybackBringupPhase.failed,
            itemId: 'stremfin:8',
          ),
        );
        async.elapse(const Duration(seconds: 2));
        expect(music.failed, isFalse);
      });
    });

    test('a film failing is the video player\'s to tell', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([_item('m1', 'Movie')]);
        async.flushMicrotasks();
        manager.setBringup(
          const PlaybackBringupState(
            phase: PlaybackBringupPhase.failed,
            itemId: 'm1',
          ),
        );
        async.elapse(const Duration(seconds: 2));
        expect(music.failed, isFalse);
      });
    });
  });

  // Kos TV: on the web on a computer the music sounded at the last video's
  // level (the browser's players are shared).
  group('the music\'s own volume', () {
    test('a song gets the music\'s level; a film is left alone', () {
      fakeAsync((async) {
        KostvNowPlaying.debugHasOwnVolume = true;
        final backend = manager.backend! as _Backend;
        KostvNowPlaying.instance.ensureStarted();
        manager.queueService.setQueue([_item('m1', 'Movie')]);
        async.flushMicrotasks();
        expect(backend.volumes, isEmpty);

        manager.queueService.setQueue([_item('s1', 'Audio')]);
        async.flushMicrotasks();
        expect(backend.volumes, [100]);
        // Pausing and going on doesn't set it again for nothing.
        manager.state.setPlaying(true);
        async.flushMicrotasks();
        expect(backend.volumes, [100]);
      });
    });

    test('the slider sets it, and a song after a film gets it back', () {
      fakeAsync((async) {
        KostvNowPlaying.debugHasOwnVolume = true;
        final backend = manager.backend! as _Backend;
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([_item('s1', 'Audio')]);
        async.flushMicrotasks();
        music.setVolume(40);
        expect(music.volume, 40);
        expect(backend.volumes.last, 40);

        // A film in between leaves its own level in the player.
        manager.queueService.setQueue([_item('m1', 'Movie')]);
        async.flushMicrotasks();
        backend.volumes.add(90);
        manager.queueService.setQueue([_item('s2', 'Audio')]);
        async.flushMicrotasks();
        expect(backend.volumes.last, 40);

        // A new player gets it too.
        final other = _Backend();
        manager.backend = other;
        manager.backends.add(other);
        expect(other.volumes, [40]);
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('nowhere else does it touch the player', () {
      fakeAsync((async) {
        KostvNowPlaying.debugHasOwnVolume = false;
        final backend = manager.backend! as _Backend;
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([_item('s1', 'Audio')]);
        async.flushMicrotasks();
        music.setVolume(40);
        expect(backend.volumes, isEmpty);
        expect(music.volume, 100);
      });
    });
  });

  // Kos TV: Kids Mode going on for the person stops the music.
  group('Kids Mode', () {
    test('stops a song', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance..ensureStarted();
        manager.queueService.setQueue([_item('s1', 'Audio')]);
        async.flushMicrotasks();
        music.stopForKidsMode();
        async.flushMicrotasks();
        expect(manager.stops, 1);
        expect(music.item, isNull);
      });
    });

    test('leaves an audiobook and a film alone', () {
      final music = KostvNowPlaying.instance;
      manager.queueService.setQueue([_item('b1', 'AudioBook')]);
      music.stopForKidsMode();
      manager.queueService.setQueue([_item('m1', 'Movie')]);
      music.stopForKidsMode();
      expect(manager.stops, 0);
    });
  });

  group('where the floating player steps aside', () {
    testWidgets('under a dialog, and where the bottom bar has its own', (
      tester,
    ) async {
      final routes = KostvNowPlayingRouteObserver.instance;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [routes],
          home: const SizedBox(),
        ),
      );
      expect(routes.popupOnTop, isFalse);
      expect(routes.bottomBarOnTop, isFalse);

      unawaited(
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => const Text('¿Seguro?'),
        ),
      );
      await tester.pumpAndSettle();
      expect(routes.popupOnTop, isTrue);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(routes.popupOnTop, isFalse);

      final page = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      unawaited(navigator.currentState!.push(page));
      await tester.pumpAndSettle();
      routes.setBottomBar(page, true);
      expect(routes.bottomBarOnTop, isTrue);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(routes.bottomBarOnTop, isFalse);
    });
  });

  testWidgets('the bars dance while it plays and rest while paused', (
    tester,
  ) async {
    // The bars' painter repaints with the turn it is at.
    double turn() {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(KostvEqualizerBars),
          matching: find.byType(CustomPaint),
        ),
      );
      return (paint.painter as dynamic).t.value as double;
    }

    await tester.pumpWidget(
      const Center(child: KostvEqualizerBars(playing: true)),
    );
    final first = turn();
    await tester.pump(const Duration(milliseconds: 300));
    expect(turn(), isNot(first));
    await tester.pumpWidget(
      const Center(child: KostvEqualizerBars(playing: false)),
    );
    final paused = turn();
    await tester.pump(const Duration(milliseconds: 300));
    expect(turn(), paused);

    // Where animations are off (a page underneath), they stay still too.
    await tester.pumpWidget(
      const TickerMode(
        enabled: false,
        child: Center(child: KostvEqualizerBars(playing: true)),
      ),
    );
    final hidden = turn();
    await tester.pump(const Duration(milliseconds: 300));
    expect(turn(), hidden);
  });
}
