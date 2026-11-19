import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';

/// A backend that lets the test end the item.
class _TestBackend extends Fake implements PlayerBackend {
  final completed = StreamController<bool>.broadcast(sync: true);
  Duration currentPosition = Duration.zero;
  bool playing = true;

  @override
  Duration get position => currentPosition;

  @override
  Duration get duration => const Duration(minutes: 40);

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

  Future<void> setRepeatMode(RepeatMode mode) async {}
}

Map<String, dynamic> _episode(String id) => {'Id': id, 'Type': 'Episode'};

/// Kos TV: with the next-episode card off the queue moves on by itself, and
/// that advance is the automatic one the "still watching?" question counts.
void main() {
  late _TestBackend backend;
  late PlaybackManager manager;
  late int asked;

  setUp(() {
    backend = _TestBackend();
    manager = PlaybackManager()..setBackend(backend);
    asked = 0;
  });

  Future<void> endItem() async {
    manager.state.setDuration(const Duration(minutes: 40));
    manager.state.setPosition(const Duration(minutes: 40));
    backend.completed.add(true);
    await pumpEventQueue();
  }

  test('the queue moving on by itself asks first', () async {
    manager.queueService.setQueue([_episode('a'), _episode('b')]);
    manager.confirmAutoNext = () async {
      asked++;
      return true;
    };

    await endItem();

    expect(asked, 1);
    expect(manager.queueService.currentIndex, 1);
  });

  test('a no stops there, without moving on', () async {
    manager.queueService.setQueue([_episode('a'), _episode('b')]);
    manager.confirmAutoNext = () async {
      asked++;
      return false;
    };

    await endItem();

    expect(asked, 1);
    expect(manager.queueService.currentIndex, 0);
  });

  test('a manual next is not asked about', () async {
    manager.queueService.setQueue([_episode('a'), _episode('b')]);
    manager.confirmAutoNext = () async {
      asked++;
      return true;
    };

    await manager.next().catchError((_) {});

    expect(asked, 0);
    expect(manager.queueService.currentIndex, 1);
  });

  test('skipping the last item runs it out without asking', () async {
    manager.queueService.setQueue([
      _episode('a'),
      _episode('b'),
    ], startIndex: 1);
    manager.state.setDuration(const Duration(minutes: 40));
    manager.confirmAutoNext = () async {
      asked++;
      return true;
    };

    await manager.next().catchError((_) {});
    await endItem();

    expect(asked, 0);
  });

  test('nothing queued after it: nothing to ask about', () async {
    manager.queueService.setQueue([_episode('a')]);
    manager.confirmAutoNext = () async {
      asked++;
      return true;
    };

    await endItem();

    expect(asked, 0);
  });

  test('without a host to ask, it moves on as before', () async {
    manager.queueService.setQueue([_episode('a'), _episode('b')]);

    await endItem();

    expect(manager.queueService.currentIndex, 1);
  });
}
