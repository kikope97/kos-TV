import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';

/// A backend whose position and errors the test drives.
class _TestBackend extends Fake implements PlayerBackend {
  final positions = StreamController<Duration>.broadcast(sync: true);
  final errors = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  bool playing = false;
  Duration currentPosition = Duration.zero;
  final seeks = <Duration>[];

  @override
  Duration get position => currentPosition;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  Duration get buffer => Duration.zero;

  @override
  bool get isPlaying => playing;

  @override
  bool get playWhenReady => playing;

  @override
  double get playbackSpeed => 1.0;

  @override
  bool get isBuffering => false;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get bufferStream => const Stream<Duration>.empty();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();

  @override
  Stream<bool> get completedStream => const Stream<bool>.empty();

  @override
  Stream<Map<String, dynamic>>? get errorStream => errors.stream;

  @override
  bool get supportsRuntimeTrackSelection => false;

  @override
  bool get supportsDirectPlayAudioSwitch => false;

  @override
  bool get canRenderBitmapSubtitles => false;

  @override
  bool get requiresStartupMediaReadyCheck => false;

  @override
  bool get nativelyHandlesStartPosition => true;

  @override
  Map<String, dynamic> getDeviceProfile({
    bool useProgressiveTranscode = false,
  }) => <String, dynamic>{};

  @override
  Future<void> play(
    dynamic mediaItem, {
    Duration startPosition = Duration.zero,
  }) async {
    currentPosition = startPosition;
    playing = true;
  }

  @override
  Future<void> seekTo(Duration position) async => seeks.add(position);

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> resume() async => playing = true;

  @override
  Future<void> stop() async => playing = false;

  @override
  Future<void> setSubtitleRendererMode(SubtitleRendererMode mode) async {}

  @override
  Future<void> waitForTracksReady() async {}

  @override
  void dispose() {}
}

class _TestResolver extends MediaStreamResolver {
  @override
  Future<StreamResolutionResult> resolve(
    dynamic mediaItem, {
    Map<String, dynamic>? deviceProfile,
    int? maxStreamingBitrate,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startTimeTicks,
    String? mediaSourceId,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
  }) async => const StreamResolutionResult(
    streamUrl: 'https://example.test/stream',
    mediaSourceId: 'source',
    playSessionId: 'session',
    playMethod: StreamPlayMethod.directPlay,
  );
}

/// Notes what each report carried.
class _TestService extends Fake implements PlayerService {
  final starts = <PlaybackQueueModes?>[];
  final progress = <({Duration position, PlaybackQueueModes? modes})>[];
  final stops = <({Duration position, bool failed})>[];

  @override
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    PlaybackQueueModes? queueModes,
  }) async => starts.add(queueModes);

  @override
  Future<void> onPlaybackProgress(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool isPaused = false,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? volumeLevel,
    bool? isMuted,
    PlaybackQueueModes? queueModes,
  }) async => progress.add((position: position, modes: queueModes));

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
    bool failed = false,
  }) async => stops.add((position: position, failed: failed));

  @override
  Future<void> closeLiveStream(String liveStreamId) async {}

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {}

  @override
  void dispose() {}
}

void main() {
  late _TestBackend backend;
  late _TestService service;
  late PlaybackManager manager;

  setUp(() {
    backend = _TestBackend();
    service = _TestService();
    manager = PlaybackManager()
      ..setBackend(backend)
      ..setResolver(_TestResolver())
      ..setPlayerService(service);
  });

  tearDown(() => manager.dispose());

  const song = <String, dynamic>{
    'Id': 'song',
    'Type': 'Audio',
    'MediaType': 'Audio',
  };
  const episode = <String, dynamic>{'Id': 'episode', 'Type': 'Episode'};

  Future<void> play(Map<String, dynamic> item) => manager.playItems(<dynamic>[
    item,
    {...item, 'Id': '${item['Id']}-2'},
  ]);

  void failPlaying() => backend.errors.add(<String, dynamic>{
    'event': 'playerError',
    'kind': 'decoder',
    'recoverable': false,
    'message': 'cannot decode',
  });

  group('repeat and shuffle', () {
    testWidgets('music reports carry the queue\'s modes, as they change', (
      tester,
    ) async {
      await play(song);
      expect(
        service.starts.single,
        const PlaybackQueueModes(repeatMode: RepeatMode.none, shuffled: false),
      );

      manager
        ..toggleRepeat()
        ..toggleShuffle();
      await tester.pump(const Duration(seconds: 5));
      expect(
        service.progress.last.modes,
        const PlaybackQueueModes(
          repeatMode: RepeatMode.repeatAll,
          shuffled: true,
        ),
      );
      await manager.stop();
    });

    testWidgets('a video\'s reports don\'t carry them', (tester) async {
      await play(episode);
      expect(service.starts.single, isNull);
      await tester.pump(const Duration(seconds: 5));
      expect(service.progress.last.modes, isNull);
      await manager.stop();
    });
  });

  group('a failure', () {
    test('a song that fails is stopped as failed, where it was', () async {
      await play(song);
      backend.positions.add(const Duration(seconds: 42));
      failPlaying();
      await pumpEventQueue();
      await manager.stop();
      expect(service.stops.first.failed, isTrue);
      expect(service.stops.first.position, const Duration(seconds: 42));
    });

    test('the next one after it is not', () async {
      await play(song);
      failPlaying();
      await pumpEventQueue();
      await manager.nextInQueue();
      await manager.stop();
      expect(service.stops.map((stop) => stop.failed), [true, false]);
    });

    test('a song stopped by the person is not', () async {
      await play(song);
      backend.positions.add(const Duration(seconds: 10));
      await manager.stop();
      expect(service.stops.single.failed, isFalse);
      expect(service.stops.single.position, const Duration(seconds: 10));
    });

    test('a video that fails is stopped as before, without it (the server '
        'would drop its resume point)', () async {
      await play(episode);
      failPlaying();
      await pumpEventQueue();
      await manager.stop();
      expect(service.stops.first.failed, isFalse);
    });
  });

  group('a seek', () {
    test('in a song is reported at once, where it landed', () async {
      await play(song);
      backend.positions.add(const Duration(seconds: 60));
      await manager.seekTo(const Duration(seconds: 55));
      expect(backend.seeks, [const Duration(seconds: 55)]);
      expect(service.progress.single.position, const Duration(seconds: 55));
      await manager.stop();
    });

    test('in a video waits for the next tick, as before', () async {
      await play(episode);
      await manager.seekTo(const Duration(minutes: 5));
      expect(service.progress, isEmpty);
      await manager.stop();
    });
  });
}
