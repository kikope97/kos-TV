import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';

/// A backend that records the repeat mode it is told and lets the test end
/// the item.
class _TestBackend extends Fake implements PlayerBackend {
  final completed = StreamController<bool>.broadcast(sync: true);
  final List<RepeatMode> repeatModes = <RepeatMode>[];
  Duration currentPosition = Duration.zero;
  bool playing = true;

  @override
  Duration get position => currentPosition;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  bool get isPlaying => playing;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get bufferStream => const Stream<Duration>.empty();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get completedStream => completed.stream;

  @override
  Stream<Map<String, dynamic>>? get errorStream => null;

  @override
  Future<void> seekTo(Duration position) async {
    currentPosition = position;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  // Not on [PlayerBackend]: the manager calls it dynamically, as it does on
  // the Media3 backend.
  Future<void> setRepeatMode(RepeatMode mode) async {
    repeatModes.add(mode);
  }
}

Map<String, dynamic> _song(String id) => {'Id': id, 'Type': 'Audio'};

void main() {
  late _TestBackend backend;
  late PlaybackManager manager;

  setUp(() {
    backend = _TestBackend();
    manager = PlaybackManager()..setBackend(backend);
  });

  group('QueueService.next', () {
    test('repeat-one holds an item that ended by itself', () {
      final queue = QueueService()
        ..setQueue(['a', 'b'])
        ..toggleRepeat();
      queue.toggleRepeat();
      expect(queue.repeatMode, RepeatMode.repeatOne);

      expect(queue.next(), isTrue);
      expect(queue.currentIndex, 0);
    });

    test('a manual skip moves on with repeat-one', () {
      final queue = QueueService()
        ..setQueue(['a', 'b'])
        ..toggleRepeat();
      queue.toggleRepeat();

      expect(queue.next(manual: true), isTrue);
      expect(queue.currentIndex, 1);
      expect(
        queue.next(manual: true),
        isFalse,
        reason: 'repeat-one only wraps round like repeat-all would',
      );
    });
  });

  test('next with repeat-one goes to the next song', () async {
    manager.queueService.setQueue([_song('a'), _song('b'), _song('c')]);
    manager.toggleRepeat();
    manager.toggleRepeat();
    expect(manager.state.repeatMode, RepeatMode.repeatOne);

    await manager.next().catchError((_) {});

    expect(manager.queueService.currentIndex, 1);
  });

  test(
    'skipping the last song with repeat-one ends rather than repeats',
    () async {
      manager.queueService.setQueue([_song('a'), _song('b')], startIndex: 1);
      manager.toggleRepeat();
      manager.toggleRepeat();
      manager.state.setDuration(const Duration(minutes: 3));
      var ended = 0;
      final sub = manager.sessionEndedStream.listen((_) => ended++);

      await manager.next().catchError((_) {});
      manager.state.setPosition(const Duration(minutes: 3));
      backend.completed.add(true);
      await pumpEventQueue();

      expect(ended, 1);
      expect(manager.queueService.currentIndex, 1);
      await sub.cancel();
    },
  );

  test('stopping clears the shown shuffle and repeat with the queue', () async {
    manager.queueService.setQueue([_song('a'), _song('b'), _song('c')]);
    manager.toggleShuffle();
    manager.toggleRepeat();
    expect(manager.state.isShuffled, isTrue);
    expect(manager.state.repeatMode, RepeatMode.repeatAll);

    await manager.stop();

    expect(manager.state.isShuffled, isFalse);
    expect(manager.state.repeatMode, RepeatMode.none);
    expect(backend.repeatModes.last, RepeatMode.none);
  });

  test('a new album starts unshuffled, and the button says so', () async {
    manager.queueService.setQueue([_song('a'), _song('b'), _song('c')]);
    manager.toggleShuffle();
    expect(manager.state.isShuffled, isTrue);

    await manager.playItems([_song('x'), _song('y')]).catchError((_) {});

    expect(manager.queueService.isShuffled, isFalse);
    expect(manager.state.isShuffled, isFalse);
  });

  test('a new album turns repeat off, and the button says so', () async {
    manager.queueService.setQueue([_song('a'), _song('b')]);
    manager.toggleRepeat();

    await manager.playItems([_song('x'), _song('y')]).catchError((_) {});

    expect(manager.queueService.repeatMode, RepeatMode.none);
    expect(manager.state.repeatMode, RepeatMode.none);
  });

  test('a film started with repeat on does not repeat', () async {
    manager.queueService.setQueue([_song('a'), _song('b')]);
    manager.toggleRepeat();

    await manager
        .playItems([
          {'Id': 'film', 'Type': 'Movie'},
        ])
        .catchError((_) {});

    expect(manager.queueService.repeatMode, RepeatMode.none);
    expect(manager.state.repeatMode, RepeatMode.none);
    expect(backend.repeatModes.last, RepeatMode.none);
  });
}
