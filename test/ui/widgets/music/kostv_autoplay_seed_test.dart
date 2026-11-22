import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

const _server = 'https://casa.example';

class _Manager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();

  @override
  bool get isOfflinePlayback => false;

  @override
  Map<String, dynamic>? get currentOfflineMetadata => null;
}

class _Factory extends Fake implements MediaServerClientFactory {
  _Factory(this.client);

  final MediaServerClient client;

  @override
  MediaServerClient? getClientIfExists(String serverId) => client;
}

/// The server plugin's `Station`: [count] songs at home for any seed,
/// noting the seeds it was asked with.
class _Plugin implements HttpClientAdapter {
  _Plugin(this.count, {this.firstCount, this.firstSource});

  final int count;

  /// The first answer, when it differs (the plugin's quick one).
  final int? firstCount;
  final String? firstSource;
  final seeds = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.uri.path.endsWith('/Music/Station')) {
      return ResponseBody.fromString('', 404);
    }
    seeds.add(options.uri.queryParameters['seed']);
    final first = seeds.length == 1 && firstCount != null;
    final count = first ? firstCount! : this.count;
    return ResponseBody.fromString(
      jsonEncode({
        'Items': [
          for (var i = 0; i < count; i++)
            {'Card': _song('st$i', artist: 'a${i % 5}').rawData},
        ],
        'Source': first ? (firstSource ?? 'listenbrainz') : 'listenbrainz',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AggregatedItem _song(String id, {String artist = 'a1', String? type}) =>
    AggregatedItem(
      id: id,
      serverId: _server,
      rawData: {
        'Id': id,
        'Name': 'Canción $id',
        'Type': type ?? 'Audio',
        'MediaType': 'Audio',
        'AlbumArtists': [
          {'Id': artist, 'Name': 'Artista $artist'},
        ],
      },
    );

/// Kos TV: the endless play (∞) goes on from the last song the person
/// chose, not from what it added itself (`docs/musica-radio.md` 3.2).
void main() {
  final music = KostvNowPlaying.instance;

  group('the song it goes on from', () {
    test('the last one the person chose, not what came by itself', () {
      final chosen = _song('a');
      final auto = [_song('x1'), _song('x2')];
      expect(
        KostvNowPlaying.autoplaySeedOf(
          [chosen, ...auto],
          cameByItself: auto.contains,
          current: auto.last,
        ),
        same(chosen),
      );
    });

    test('a song added by hand after the ∞\'s is the new one', () {
      final chosen = _song('a');
      final added = _song('mine');
      final auto = [_song('x1'), _song('x2'), _song('x3')];
      expect(
        KostvNowPlaying.autoplaySeedOf(
          [chosen, auto[0], auto[1], added, auto[2]],
          cameByItself: auto.contains,
          current: auto[2],
        ),
        same(added),
      );
    });

    test(
      'all of it came by itself (a station): the song it was put on with',
      () {
        final queue = [_song('seed'), _song('s1'), _song('s2')];
        expect(
          KostvNowPlaying.autoplaySeedOf(
            queue,
            cameByItself: (_) => true,
            start: queue.first,
            current: queue.last,
          ),
          same(queue.first),
        );
        // Without a start known, the one sounding.
        expect(
          KostvNowPlaying.autoplaySeedOf(
            queue,
            cameByItself: (_) => true,
            current: queue.last,
          ),
          same(queue.last),
        );
      },
    );

    test('never an audiobook or a video', () {
      final chosen = _song('a');
      expect(
        KostvNowPlaying.autoplaySeedOf([
          chosen,
          _song('book', type: 'AudioBook'),
        ], cameByItself: (_) => false),
        same(chosen),
      );
    });

    test('the queue keeps the song it was put on with', () {
      final tracks = [_song('t0'), _song('t1'), _song('t2')];
      music.noteQueueSource(KostvMusicSource.radio, tracks, startIndex: 1);
      expect(music.debugQueueStart, same(tracks[1]));
      music.noteQueueSource(KostvMusicSource.album, const []);
      expect(music.debugQueueStart, isNull);
      music.debugReset();
    });
  });

  group('asking for more', () {
    late _Manager manager;
    late _Plugin routes;

    setUp(() {
      manager = _Manager();
      final client =
          JellyfinMediaServerClient(
              baseUrl: _server,
              deviceInfo: const DeviceInfo(
                id: 'device',
                name: 'Device',
                appName: 'kOS TV',
                appVersion: '1.0.0',
              ),
            )
            ..accessToken = 'token'
            ..userId = 'ana';
      GetIt.instance
        ..registerSingleton<PlaybackManager>(manager)
        ..registerSingleton<MediaServerClient>(client)
        ..registerSingleton<MediaServerClientFactory>(_Factory(client));
      routes = _Plugin(30);
      KostvMusicPlugin.instance = KostvMusicPlugin(
        dio: Dio()..httpClientAdapter = routes,
      );
    });

    tearDown(() async {
      music.debugReset();
      KostvMusicPlugin.instance = KostvMusicPlugin();
      await GetIt.instance.reset();
    });

    List<String> ids() => [
      for (final s in manager.queueService.items) (s as AggregatedItem).id,
    ];

    test(
      'always around the song the person chose, and nothing twice',
      () async {
        final chosen = _song('chosen', artist: 'z');
        music.noteQueueSource(KostvMusicSource.album, [chosen]);
        manager.queueService.setQueue([chosen]);
        await music.debugAutoplay();
        expect(routes.seeds, ['chosen']);
        expect(ids(), hasLength(26));
        // Now on one the ∞ added, near the end: asked again, still around
        // the one the person chose, with only what isn't in the queue yet.
        manager.queueService.jumpTo(24);
        await music.debugAutoplay();
        expect(routes.seeds, ['chosen', 'chosen']);
        expect(ids(), hasLength(31));
        expect(ids().toSet(), hasLength(31));
        // Once for each song sounding.
        await music.debugAutoplay();
        expect(routes.seeds, hasLength(2));
      },
    );

    test('a station the plugin gave in part is completed later, without '
        'repeating', () async {
      routes = _Plugin(12, firstCount: 4, firstSource: 'fallback');
      KostvMusicPlugin.instance = KostvMusicPlugin(
        dio: Dio()..httpClientAdapter = routes,
      );
      final chosen = _song('chosen', artist: 'z');
      music.noteQueueSource(KostvMusicSource.album, [chosen]);
      manager.queueService.setQueue([chosen]);
      await music.debugAutoplay();
      expect(ids(), hasLength(5));
      await music.debugCompleteStation(chosen, byAutoplay: true);
      expect(routes.seeds, ['chosen', 'chosen']);
      expect(ids(), hasLength(13));
      expect(ids().toSet(), hasLength(13));
      final added = manager.queueService.items.skip(5).cast<AggregatedItem>();
      expect(added.every(music.autoplayItems.contains), isTrue);
      // Another queue meanwhile: nothing is added to it.
      final other = _song('other', artist: 'y');
      music.noteQueueSource(KostvMusicSource.album, [other]);
      manager.queueService.setQueue([other]);
      await music.debugCompleteStation(chosen);
      expect(ids(), ['other']);
    });
  });
}
