import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:playback_core/playback_core.dart';

String _idOf(dynamic item) =>
    item is Map ? item['Id'] as String : (item as AggregatedItem).id;

/// A player that can queue the next song (like Media3 does), driven by hand:
/// the test moves the position, ends the song or moves on to the queued one.
class _GaplessBackend extends Fake implements PlayerBackend, GaplessCapable {
  final _position = StreamController<Duration>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _transitioned = StreamController<void>.broadcast();
  final _dropped = StreamController<bool>.broadcast();
  final List<String> playedUrls = <String>[];
  final List<Map<dynamic, dynamic>> playedPayloads = <Map<dynamic, dynamic>>[];
  final List<Map<dynamic, dynamic>> preloaded = <Map<dynamic, dynamic>>[];
  int stopCalls = 0;
  int cancelCalls = 0;
  bool takesPreload = true;
  bool playing = false;
  Duration currentPosition = Duration.zero;
  Duration reportedDuration = const Duration(minutes: 3);

  void moveTo(Duration position) {
    currentPosition = position;
    _position.add(position);
  }

  void end() {
    currentPosition = reportedDuration;
    playing = false;
    _completed.add(true);
  }

  /// What Media3 does when the queued song starts by itself.
  void moveOnToQueued({Duration length = const Duration(minutes: 4)}) {
    currentPosition = Duration.zero;
    reportedDuration = length;
    _transitioned.add(null);
  }

  /// What Media3 does when it lets the queued song go by itself.
  void dropQueued({required bool failed}) => _dropped.add(failed);

  @override
  bool get canPreloadNext => true;

  @override
  Future<bool> preloadNext(dynamic mediaItem) async {
    if (!takesPreload) return false;
    preloaded.add(mediaItem as Map);
    return true;
  }

  @override
  Future<void> cancelPreload() async => cancelCalls++;

  @override
  Stream<void> get transitionedStream => _transitioned.stream;

  @override
  Stream<bool> get nextDroppedStream => _dropped.stream;

  @override
  Duration get position => currentPosition;
  @override
  Duration get duration => reportedDuration;
  @override
  Duration get buffer => Duration.zero;
  @override
  bool get isPlaying => playing;
  @override
  bool get isBuffering => false;
  @override
  bool? get playWhenReady => playing;
  @override
  double get playbackSpeed => 1.0;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();
  @override
  Stream<Duration> get bufferStream => const Stream<Duration>.empty();
  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();
  @override
  Stream<bool> get bufferingStream => const Stream<bool>.empty();
  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Stream<Map<String, dynamic>>? get errorStream => null;
  @override
  bool get supportsRuntimeTrackSelection => false;
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
    playedUrls.add((mediaItem as Map)['url'] as String);
    playedPayloads.add(mediaItem);
    currentPosition = startPosition;
    reportedDuration = const Duration(minutes: 3);
    playing = true;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {
    stopCalls++;
    playing = false;
  }

  @override
  Future<void> setSubtitleRendererMode(SubtitleRendererMode mode) async {}
  @override
  void dispose() {}
}

class _Resolver extends MediaStreamResolver {
  final List<String> asked = <String>[];

  /// Answers for these ids wait on their completer.
  final Map<String, Completer<void>> holds = <String, Completer<void>>{};
  final Map<String, StreamPlayMethod> methods = <String, StreamPlayMethod>{};

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
  }) async {
    final id = _idOf(mediaItem);
    asked.add(id);
    final n = asked.length;
    await holds[id]?.future;
    return StreamResolutionResult(
      streamUrl: 'https://example.test/$id',
      mediaSourceId: 'source-$id',
      playSessionId: 'session-$id-$n',
      playMethod: methods[id] ?? StreamPlayMethod.directPlay,
      mediaType: 'audio',
      mediaStreams: const [],
    );
  }
}

class _Service implements PlayerService {
  final List<String> events = <String>[];
  final Map<String, Duration> stoppedAt = <String, Duration>{};
  final List<String> stoppedTranscodes = <String>[];

  /// Stop reports for these ids wait on their completer.
  final Map<String, Completer<void>> stopHolds = <String, Completer<void>>{};

  @override
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    PlaybackQueueModes? queueModes,
  }) async {
    events.add('start:${_idOf(mediaItem)}');
  }

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
  }) async {}

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
    bool failed = false,
  }) async {
    final id = _idOf(mediaItem);
    events.add('stop:$id');
    stoppedAt[id] = position;
    await stopHolds[id]?.future;
  }

  @override
  Future<void> closeLiveStream(String liveStreamId) async {}

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {
    stoppedTranscodes.add(resolution.playSessionId ?? '');
  }

  @override
  void dispose() {}
}

Map<String, dynamic> _song(String id) => {'Id': id, 'Type': 'Audio'};

void main() {
  late _GaplessBackend backend;
  late _Resolver resolver;
  late _Service service;
  late PlaybackManager manager;
  late DateTime now;

  setUp(() {
    backend = _GaplessBackend();
    resolver = _Resolver();
    service = _Service();
    now = DateTime(2026, 11, 21, 12);
    manager = PlaybackManager()
      ..clock = (() => now)
      ..setBackend(backend)
      ..setResolver(resolver)
      ..setPlayerService(service);
  });

  tearDown(() async {
    await manager.stop();
  });

  Future<void> at(Duration position) async {
    now = now.add(const Duration(seconds: 1));
    backend.moveTo(position);
    await pumpEventQueue();
  }

  Future<void> playAlbum([List<Map<String, dynamic>>? songs]) async {
    await manager.playItems(songs ?? [_song('a'), _song('b'), _song('c')]);
    now = now.add(const Duration(minutes: 2));
  }

  test('the next song is prepared 25 s before the end, not before', () async {
    await playAlbum();

    await at(const Duration(minutes: 2, seconds: 34));
    expect(resolver.asked, ['a']);

    await at(const Duration(minutes: 2, seconds: 36));
    expect(resolver.asked, ['a', 'b']);
    expect(backend.preloaded.single['url'], 'https://example.test/b');
    expect(backend.preloaded.single['mediaType'], 'audio');
    expect(backend.preloaded.single['gaplessAudio'], isTrue);

    // Once only.
    await at(const Duration(minutes: 2, seconds: 40));
    expect(resolver.asked, ['a', 'b']);
  });

  test(
    'moving on with no gap reports the song before as played to its '
    'length, then the start of the next, without stopping the player',
    () async {
      await playAlbum();
      await at(const Duration(minutes: 2, seconds: 40));
      await at(const Duration(minutes: 2, seconds: 59));
      final stopsBefore = backend.stopCalls;

      backend.moveOnToQueued();
      await pumpEventQueue();

      expect(service.events, ['start:a', 'stop:a', 'start:b']);
      expect(service.stoppedAt['a'], const Duration(minutes: 3));
      expect(manager.queueService.currentIndex, 1);
      expect(manager.state.position, Duration.zero);
      expect(manager.state.duration, const Duration(minutes: 4));
      expect(backend.stopCalls, stopsBefore);
      expect(backend.playedUrls, ['https://example.test/a']);
      expect(resolver.asked, ['a', 'b']);
      expect(manager.bringupState.phase, PlaybackBringupPhase.ready);

      // And the one after it is prepared in turn.
      await at(const Duration(minutes: 3, seconds: 40));
      expect(resolver.asked, ['a', 'b', 'c']);
    },
  );

  test('a queue change takes the prepared song back and prepares the new '
      'next one', () async {
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(backend.preloaded, hasLength(1));

    manager.queueService.insertNext(_song('x'));
    await pumpEventQueue();
    expect(backend.cancelCalls, 1);

    await at(const Duration(minutes: 2, seconds: 41));
    expect(resolver.asked, ['a', 'b', 'x']);
    expect(backend.preloaded.last['url'], 'https://example.test/x');

    backend.moveOnToQueued();
    await pumpEventQueue();
    expect(manager.queueService.currentItem['Id'], 'x');
  });

  test('a discarded conversion is stopped on the server', () async {
    resolver.methods['b'] = StreamPlayMethod.transcode;
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    // A server conversion isn't queued in the player.
    expect(backend.preloaded, isEmpty);

    manager.queueService.removeAt(1);
    await pumpEventQueue();
    expect(service.stoppedTranscodes, ['session-b-2']);
  });

  test('nothing is prepared with repeat-one', () async {
    await playAlbum();
    manager.toggleRepeat();
    manager.toggleRepeat();
    expect(manager.state.repeatMode, RepeatMode.repeatOne);

    await at(const Duration(minutes: 2, seconds: 50));
    expect(resolver.asked, ['a']);
    expect(backend.preloaded, isEmpty);
  });

  test('repeat-one turned on takes a prepared song back', () async {
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(backend.preloaded, hasLength(1));

    manager.toggleRepeat();
    manager.toggleRepeat();
    await pumpEventQueue();
    expect(backend.cancelCalls, 1);
  });

  test('nothing is prepared with «al acabar la canción», and turning it on '
      'takes a prepared song back', () async {
    var sleepsAfterSong = true;
    manager.preloadVeto = () => sleepsAfterSong;
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(resolver.asked, ['a']);

    sleepsAfterSong = false;
    await at(const Duration(minutes: 2, seconds: 41));
    expect(backend.preloaded, hasLength(1));

    sleepsAfterSong = true;
    await at(const Duration(minutes: 2, seconds: 42));
    expect(backend.cancelCalls, 1);
  });

  test('nothing is prepared while SyncPlay drives the queue', () async {
    await playAlbum();
    manager.setTransportInterceptor((action, {position}) async => false);
    await at(const Duration(minutes: 2, seconds: 40));
    expect(resolver.asked, ['a']);
  });

  test('a next song not ready at the end starts the usual way, from the '
      'answer already on its way', () async {
    final hold = Completer<void>();
    resolver.holds['b'] = hold;
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(resolver.asked, ['a', 'b']);

    manager.state.setPosition(const Duration(minutes: 3));
    backend.end();
    await pumpEventQueue();
    expect(service.events, ['start:a', 'stop:a']);

    hold.complete();
    await pumpEventQueue();
    expect(backend.playedUrls, [
      'https://example.test/a',
      'https://example.test/b',
    ]);
    // Not asked again.
    expect(resolver.asked, ['a', 'b']);
    expect(backend.preloaded, isEmpty);
    expect(service.events.last, 'start:b');
  });

  test('a player that can not queue it still starts the next song from its '
      'early answer', () async {
    backend.takesPreload = false;
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(resolver.asked, ['a', 'b']);

    manager.state.setPosition(const Duration(minutes: 3));
    backend.end();
    await pumpEventQueue();

    expect(backend.playedUrls.last, 'https://example.test/b');
    expect(resolver.asked, ['a', 'b']);
    expect(manager.queueService.currentIndex, 1);
  });

  test('a skip to the prepared song uses its answer too', () async {
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));

    await manager.nextInQueue();
    await pumpEventQueue();

    expect(backend.playedUrls.last, 'https://example.test/b');
    expect(resolver.asked, ['a', 'b']);
  });

  test('a skip elsewhere drops the prepared song', () async {
    await manager.playItems([
      _song('a'),
      _song('b'),
      _song('c'),
    ], startIndex: 1);
    now = now.add(const Duration(minutes: 2));
    await at(const Duration(minutes: 2, seconds: 40));
    expect(backend.preloaded.single['url'], 'https://example.test/c');

    await manager.previousInQueue();
    await pumpEventQueue();

    expect(backend.cancelCalls, 1);
    expect(manager.queueService.currentIndex, 0);
    expect(backend.playedUrls.last, 'https://example.test/a');
  });

  test('a player moving on after its queued song was taken back reports the '
      'song before as played and starts the queue\'s next one', () async {
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    manager.queueService.insertNext(_song('x'));
    await pumpEventQueue();
    expect(backend.cancelCalls, 1);

    // The cancel came too late: the player already moved on to b.
    backend.moveOnToQueued();
    await pumpEventQueue();

    expect(service.stoppedAt['a'], const Duration(minutes: 3));
    expect(manager.queueService.currentItem['Id'], 'x');
    expect(backend.playedUrls.last, 'https://example.test/x');
  });

  test('video is left as it was', () async {
    await playAlbum([
      {'Id': 'e1', 'Type': 'Episode'},
      {'Id': 'e2', 'Type': 'Episode'},
    ]);
    await at(const Duration(minutes: 2, seconds: 50));
    expect(resolver.asked, ['e1']);
    expect(backend.preloaded, isEmpty);
  });

  // Kos TV: the player letting the queued song go by itself.
  test('a queued song the player could not load starts the usual way at the '
      'end, resolved afresh, and is not queued again', () async {
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(backend.preloaded, hasLength(1));

    backend.dropQueued(failed: true);
    await pumpEventQueue();
    await at(const Duration(minutes: 2, seconds: 45));
    expect(backend.preloaded, hasLength(1));
    expect(backend.cancelCalls, 0);

    manager.state.setPosition(const Duration(minutes: 3));
    backend.end();
    await pumpEventQueue();
    expect(backend.playedUrls.last, 'https://example.test/b');
    expect(resolver.asked, ['a', 'b', 'b']);
    expect(manager.queueService.currentIndex, 1);
  });

  test('a queued song the player let go when it opened the song again is '
      'queued again on the next tick, from what was resolved', () async {
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(backend.preloaded, hasLength(1));

    backend.dropQueued(failed: false);
    await pumpEventQueue();
    expect(backend.cancelCalls, 0);
    await at(const Duration(minutes: 2, seconds: 41));
    expect(backend.preloaded, hasLength(2));
    expect(backend.preloaded.last['url'], 'https://example.test/b');
    // Kos TV: not asked again; the answer it had still holds.
    expect(resolver.asked, ['a', 'b']);

    // Once only.
    await at(const Duration(minutes: 2, seconds: 42));
    expect(backend.preloaded, hasLength(2));

    backend.moveOnToQueued();
    await pumpEventQueue();
    expect(manager.queueService.currentIndex, 1);
    expect(backend.playedUrls, ['https://example.test/a']);
  });

  test('a song whose file is shorter than its listed length goes on to the '
      'next one, reported as played to its end', () async {
    AggregatedItem song(String id) => AggregatedItem(
      id: id,
      serverId: 'casa',
      rawData: {
        'Id': id,
        'Type': 'Audio',
        'MediaType': 'Audio',
        // 3:20 listed; the file (the player's) lasts 3:00.
        'RunTimeTicks': 2000000000,
      },
    );
    backend.takesPreload = false;
    await manager.playItems([song('a'), song('b')]);
    now = now.add(const Duration(minutes: 2));

    manager.state.setPosition(const Duration(minutes: 3));
    backend.end();
    await pumpEventQueue();

    expect(manager.queueService.currentIndex, 1);
    expect(backend.playedUrls.last, 'https://example.test/b');
    expect(service.stoppedAt['a'], const Duration(seconds: 200));
  });

  test('a video whose file ends early still stays where it is', () async {
    AggregatedItem episode(String id) => AggregatedItem(
      id: id,
      serverId: 'casa',
      rawData: {'Id': id, 'Type': 'Episode', 'RunTimeTicks': 2000000000},
    );
    await manager.playItems([episode('e1'), episode('e2')]);
    now = now.add(const Duration(minutes: 2));

    manager.state.setPosition(const Duration(minutes: 3));
    backend.end();
    await pumpEventQueue();

    expect(manager.queueService.currentIndex, 0);
  });

  test('a queued song the player could not load is told to the app, to '
      'forget its address', () async {
    final failed = <String>[];
    manager.onQueuedNextFailed = (item, resolution) =>
        failed.add('${_idOf(item)} ${resolution?.streamUrl}');
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));

    backend.dropQueued(failed: true);
    await pumpEventQueue();
    expect(failed, ['b https://example.test/b']);
  });

  test('a queued song the player only let go is not told as failed', () async {
    final failed = <String>[];
    manager.onQueuedNextFailed = (item, resolution) => failed.add('$item');
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));

    backend.dropQueued(failed: false);
    await pumpEventQueue();
    expect(failed, isEmpty);
  });

  test('the start of the song reached with no gap waits for the stop of the '
      'one before', () async {
    final hold = Completer<void>();
    service.stopHolds['a'] = hold;
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    await at(const Duration(minutes: 2, seconds: 59));

    backend.moveOnToQueued();
    await pumpEventQueue();
    expect(service.events, ['start:a', 'stop:a']);
    expect(manager.queueService.currentIndex, 1);
    expect(manager.bringupState.phase, PlaybackBringupPhase.ready);

    hold.complete();
    await pumpEventQueue();
    expect(service.events, ['start:a', 'stop:a', 'start:b']);
  });

  test('a stop report that never answers holds the start back only a '
      'moment', () async {
    service.stopHolds['a'] = Completer<void>();
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));

    backend.moveOnToQueued();
    await pumpEventQueue();
    expect(service.events, ['start:a', 'stop:a']);

    await Future<void>.delayed(
      PlaybackManager.gaplessStartReportWait +
          const Duration(milliseconds: 200),
    );
    expect(service.events, ['start:a', 'stop:a', 'start:b']);
  });

  test('«al acabar la canción» turned on after the next song was queued '
      'stops the move with no gap: it goes the usual way', () async {
    var sleepsAfterSong = false;
    manager.preloadVeto = () => sleepsAfterSong;
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(backend.preloaded, hasLength(1));

    // Turned on between two ticks, and the player moves on right then.
    sleepsAfterSong = true;
    backend.moveOnToQueued();
    await pumpEventQueue();

    // The queue's next one is opened the usual way (where the app pauses),
    // not taken from the player as if nothing held it.
    expect(manager.queueService.currentIndex, 1);
    expect(backend.playedUrls.last, 'https://example.test/b');
    expect(service.stoppedAt['a'], const Duration(minutes: 3));
  });

  test('repeat-one turned on right as the player moves on plays the song '
      'again', () async {
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(backend.preloaded, hasLength(1));

    manager.toggleRepeat();
    manager.toggleRepeat();
    backend.moveOnToQueued();
    await pumpEventQueue();

    expect(manager.queueService.currentIndex, 0);
    expect(backend.playedUrls.last, 'https://example.test/a');
  });

  test('SyncPlay taking over drops a queued song at once', () async {
    await playAlbum();
    await at(const Duration(minutes: 2, seconds: 40));
    expect(backend.preloaded, hasLength(1));

    manager.setTransportInterceptor((action, {position}) async => false);
    await pumpEventQueue();
    expect(backend.cancelCalls, 1);
  });

  test('an audiobook of type Audio never takes the gapless path', () async {
    manager.gaplessEligible = (item) => _idOf(item) != 'book1';
    await playAlbum([_song('book1'), _song('book2')]);
    expect(backend.playedPayloads.single.containsKey('gaplessAudio'), isFalse);

    await at(const Duration(minutes: 2, seconds: 50));
    expect(resolver.asked, ['book1']);
    expect(backend.preloaded, isEmpty);
  });

  test('music still asks for gapless audio when it opens', () async {
    manager.gaplessEligible = (item) => true;
    await playAlbum();
    expect(backend.playedPayloads.single['gaplessAudio'], isTrue);
  });
}
