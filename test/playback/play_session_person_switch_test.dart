import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:playback_core/playback_core.dart';
import 'package:playback_jellyfin/playback_jellyfin.dart';
import 'package:server_core/server_core.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockPlaybackApi extends Mock implements PlaybackApi {}

void main() {
  late _MockClient client;
  late _MockPlaybackApi playback;
  late String token;
  late List<String?> stopTokens;
  late List<String?> progressTokens;

  const item = {'Id': 'film', 'Type': 'Movie', 'MediaType': 'Video'};
  const resolution = StreamResolutionResult(
    streamUrl: 'https://server.invalid/film',
    mediaSourceId: 'source',
    playSessionId: 'session-a',
    playMethod: StreamPlayMethod.directPlay,
  );

  setUp(() {
    client = _MockClient();
    playback = _MockPlaybackApi();
    token = 'token-a';
    stopTokens = [];
    progressTokens = [];
    when(() => client.playbackApi).thenReturn(playback);
    when(() => client.accessToken).thenAnswer((_) => token);
    when(() => client.baseUrl).thenReturn('https://server.invalid');
    when(() => playback.reportPlaybackStart(any())).thenAnswer((_) async {});
    when(() => playback.reportPlaybackProgress(any())).thenAnswer((_) async {
      progressTokens.add(token);
    });
    when(() => playback.reportPlaybackStopped(any())).thenAnswer((_) async {
      stopTokens.add(token);
    });
  });

  test(
    'a stop after the person changed is not sent as the new person',
    () async {
      final service = PlaySessionService(client);
      await service.onPlaybackStart(item, resolution);
      await service.onPlaybackStop(
        item,
        resolution,
        const Duration(minutes: 3),
      );

      // The switch swaps the shared client's token, then the late second
      // stop for the same session arrives.
      token = 'token-b';
      await service.onPlaybackStop(
        item,
        resolution,
        const Duration(minutes: 3),
      );
      await service.onPlaybackProgress(
        item,
        resolution,
        const Duration(minutes: 3),
      );

      expect(stopTokens, ['token-a']);
      expect(progressTokens, isEmpty);
    },
  );

  test('the same person keeps reporting as before', () async {
    final service = PlaySessionService(client);
    await service.onPlaybackStart(item, resolution);
    await service.onPlaybackProgress(
      item,
      resolution,
      const Duration(minutes: 1),
    );
    await service.onPlaybackStop(item, resolution, const Duration(minutes: 2));
    await service.onPlaybackStop(item, resolution, const Duration(minutes: 2));

    expect(progressTokens, ['token-a']);
    expect(stopTokens, ['token-a', 'token-a']);
  });

  test('a session the service never started still reports', () async {
    final service = PlaySessionService(client);
    token = 'token-b';
    await service.onPlaybackStop(item, resolution, const Duration(minutes: 2));

    expect(stopTokens, ['token-b']);
  });
}
