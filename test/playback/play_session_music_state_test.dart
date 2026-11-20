import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playback_core/playback_core.dart';
import 'package:playback_jellyfin/playback_jellyfin.dart';
import 'package:server_core/server_core.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockPlaybackApi extends Mock implements PlaybackApi {}

/// Kos TV: what Jellyfin is told of the queue's modes and of a failure, so
/// the server plugin can note them with each listen.
void main() {
  late _MockClient client;
  late _MockPlaybackApi playback;
  late List<Map<String, dynamic>> starts;
  late List<Map<String, dynamic>> progress;
  late List<Map<String, dynamic>> stops;

  const song = {'Id': 'song', 'Type': 'Audio', 'MediaType': 'Audio'};
  const resolution = StreamResolutionResult(
    streamUrl: 'https://server.invalid/song',
    mediaSourceId: 'source',
    playSessionId: 'session',
    playMethod: StreamPlayMethod.directPlay,
  );

  setUp(() {
    client = _MockClient();
    playback = _MockPlaybackApi();
    starts = [];
    progress = [];
    stops = [];
    when(() => client.playbackApi).thenReturn(playback);
    when(() => client.accessToken).thenReturn('token');
    when(() => client.baseUrl).thenReturn('https://server.invalid');
    when(() => playback.reportPlaybackStart(any())).thenAnswer(
      (call) async =>
          starts.add(call.positionalArguments.single as Map<String, dynamic>),
    );
    when(() => playback.reportPlaybackProgress(any())).thenAnswer(
      (call) async =>
          progress.add(call.positionalArguments.single as Map<String, dynamic>),
    );
    when(() => playback.reportPlaybackStopped(any())).thenAnswer(
      (call) async =>
          stops.add(call.positionalArguments.single as Map<String, dynamic>),
    );
  });

  test('repeat and shuffle go as Jellyfin names them', () async {
    final service = PlaySessionService(client);
    await service.onPlaybackStart(
      song,
      resolution,
      queueModes: const PlaybackQueueModes(
        repeatMode: RepeatMode.repeatOne,
        shuffled: true,
      ),
    );
    await service.onPlaybackProgress(
      song,
      resolution,
      const Duration(seconds: 30),
      queueModes: const PlaybackQueueModes(
        repeatMode: RepeatMode.repeatAll,
        shuffled: false,
      ),
    );
    await service.onPlaybackProgress(
      song,
      resolution,
      const Duration(seconds: 35),
      queueModes: const PlaybackQueueModes(
        repeatMode: RepeatMode.none,
        shuffled: false,
      ),
    );

    expect(starts.single['RepeatMode'], 'RepeatOne');
    expect(starts.single['PlaybackOrder'], 'Shuffle');
    expect(progress[0]['RepeatMode'], 'RepeatAll');
    expect(progress[0]['PlaybackOrder'], 'Default');
    expect(progress[1]['RepeatMode'], 'RepeatNone');
  });

  test('without modes (a video) the reports are as before', () async {
    final service = PlaySessionService(client);
    await service.onPlaybackStart(song, resolution);
    await service.onPlaybackProgress(song, resolution, Duration.zero);

    expect(starts.single.containsKey('RepeatMode'), isFalse);
    expect(starts.single.containsKey('PlaybackOrder'), isFalse);
    expect(progress.single.containsKey('RepeatMode'), isFalse);
    expect(progress.single.containsKey('PlaybackOrder'), isFalse);
  });

  test('a failed stop says so, with its position; any other has no '
      'Failed', () async {
    final service = PlaySessionService(client);
    await service.onPlaybackStart(song, resolution);
    await service.onPlaybackStop(
      song,
      resolution,
      const Duration(seconds: 12),
      failed: true,
    );
    await service.onPlaybackStop(song, resolution, const Duration(seconds: 12));

    expect(stops[0]['Failed'], isTrue);
    expect(stops[0]['PositionTicks'], 12 * 10000000);
    expect(stops[1].containsKey('Failed'), isFalse);
    expect(stops[1]['PositionTicks'], 12 * 10000000);
  });
}
