import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
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
