import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';

import 'fake_stremfin_adapter.dart';

/// Kos TV: «Toda la música»: what the requests service says of a song that
/// isn't at home (`listen_ready`, 8.35 `listen`, 8.37 `prefetch`) and the
/// out-of-home songs the queue plays.
void main() {
  StremfinClient clientWith(
    FakeStremfinAdapter adapter, {
    String base = 'https://requests.example.org/api/v1',
  }) => StremfinClient(
    dio: Dio()..httpClientAdapter = adapter,
    baseUrl: base,
    token: () => 'token',
  );

  group('the service: songs that can be heard', () {
    test('listen_ready on songs and deezer_id, listen_ready and '
        'album_jellyfin_id on an album\'s songs', () {
      final song = StremfinSong.fromJson({
        'deezer_id': 3135556,
        'title': 'Harder',
        'listen_ready': true,
      })!;
      expect(song.listenReady, isTrue);
      expect(StremfinSong.fromJson({'title': 'x'})!.listenReady, isFalse);
      final detail = StremfinAlbumDetail.fromJson({
        'deezer_id': '302127',
        'title': 'Discovery',
        'can_request': true,
        'songs': [
          {
            'deezer_id': '3135553',
            'position': 1,
            'title': 'One More Time',
            'in_jellyfin': true,
            'jellyfin_id': 'j1',
            'album_jellyfin_id': 'ja',
            'listen_ready': false,
          },
          {
            'deezer_id': '3135554',
            'position': 2,
            'title': 'Aerodynamic',
            'in_jellyfin': false,
            'listen_ready': true,
          },
          {'position': 3, 'title': 'No id'},
        ],
      })!;
      expect(detail.songs[0].deezerId, '3135553');
      expect(detail.songs[0].albumJellyfinId, 'ja');
      expect(detail.songs[0].atHome, isTrue);
      expect(detail.songs[1].listenReady, isTrue);
      expect(detail.songs[1].atHome, isFalse);
      expect(detail.songs[2].deezerId, isNull);
    });

    test(
      'listen: its address, type and expiry, with a minute to wait',
      () async {
        final adapter = FakeStremfinAdapter(
          (path, _) => path == '/music/songs/3135556/listen'
              ? (
                  status: 200,
                  body: {
                    'deezer_id': '3135556',
                    'title': 'Harder',
                    'duration': 224,
                    'in_jellyfin': false,
                    'jellyfin_id': null,
                    'url': '/api/v1/music/listen?k=abc',
                    'type': 'audio/mp4',
                    'expires_at': '2026-11-22T08:30:00+01:00',
                    'ready': true,
                    'size': 3567407,
                  },
                  headers: const <String, String>{},
                )
              : (status: 404, body: null, headers: const <String, String>{}),
        );
        final listen = await clientWith(adapter).musicListen('3135556');
        expect(listen.url, '/api/v1/music/listen?k=abc');
        expect(listen.type, 'audio/mp4');
        expect(listen.ready, isTrue);
        expect(listen.size, 3567407);
        expect(listen.expiresAt!.toUtc(), DateTime.utc(2026, 11, 22, 7, 30));
        expect(
          adapter.calls.single.receiveTimeout,
          StremfinClient.listenTimeout,
        );
        expect(StremfinClient.listenTimeout, const Duration(seconds: 60));
      },
    );

    test('listen: 404, 503 and 429 come as what they are', () async {
      for (final (status, code) in [
        (404, 'not_found'),
        (503, 'source_unavailable'),
        (429, 'too_many_requests'),
      ]) {
        final adapter = FakeStremfinAdapter(
          (_, _) => (
            status: status,
            body: {
              'error': {'code': code, 'message': 'No.'},
            },
            headers: {'retry-after': '7'},
          ),
        );
        try {
          await clientWith(adapter).musicListen('1');
          fail('$status should fail');
        } on StremfinException catch (e) {
          expect(e.status, status);
          expect(e.code, code);
          expect(e.isNotFound, status == 404);
          expect(e.isRateLimited, status == 429);
          expect(e.retryAfter, const Duration(seconds: 7));
        }
      }
    });

    test('prefetch: a POST, and its state', () async {
      final adapter = FakeStremfinAdapter.withMethod(
        (method, path, _) => (
          status: 200,
          body: {
            'deezer_id': '9',
            'state': path.contains('/9/') ? 'queued' : 'in_jellyfin',
            'paused': 'youtube',
            'paused_until': '2026-11-21T20:00:00Z',
          },
          headers: const <String, String>{},
        ),
      );
      final client = clientWith(adapter);
      final queued = await client.musicPrefetch('9');
      expect(adapter.calls.single.method, 'POST');
      expect(adapter.calls.single.uri.path, '/api/v1/music/songs/9/prefetch');
      expect(queued.state, StremfinPrefetchState.queued);
      expect(queued.paused, 'youtube');
      expect(queued.pausedUntil, DateTime.utc(2026, 11, 21, 20));
      expect(
        (await client.musicPrefetch('8')).state,
        StremfinPrefetchState.inJellyfin,
      );
      for (final (raw, state) in [
        ('ready', StremfinPrefetchState.ready),
        ('downloading', StremfinPrefetchState.downloading),
        ('unavailable', StremfinPrefetchState.unavailable),
        ('later', StremfinPrefetchState.unknown),
      ]) {
        expect(StremfinPrefetchState.parse(raw), state);
      }
    });

    test('the player\'s address: the service\'s origin in front, also by '
        'the web container\'s /stremfin', () {
      final direct = clientWith(FakeStremfinAdapter((_, _) => throw 0));
      expect(
        direct.listenAddress('/api/v1/music/listen?k=abc'),
        'https://requests.example.org/api/v1/music/listen?k=abc',
      );
      final web = clientWith(
        FakeStremfinAdapter((_, _) => throw 0),
        base: StremfinClient.apiBaseFor(
          '/stremfin',
          site: Uri.parse('https://tv.example.org/#/musica'),
        )!,
      );
      expect(
        web.listenAddress('/api/v1/music/listen?k=abc'),
        'https://tv.example.org/stremfin/api/v1/music/listen?k=abc',
      );
      expect(
        web.listenAddress('https://cdn.example.org/a.m4a'),
        'https://cdn.example.org/a.m4a',
      );
      expect(web.listenAddress(''), isNull);
    });
  });

  group('the out-of-home songs of the queue', () {
    const server = 'https://casa.example';
    final song = StremfinSong(
      title: 'Aerodynamic',
      deezerId: '3135554',
      artist: 'Daft Punk',
      artistDeezerId: '27',
      duration: 207,
      cover: 'https://cdn.example/cover.jpg',
      albumTitle: 'Discovery',
      albumDeezerId: '302127',
      explicit: true,
      listenReady: true,
    );

    test('an ordinary song with an id of its own and what the service '
        'knows of it', () {
      final item = kostvStreamItemFromSong(song, serverId: server)!;
      expect(item.id, 'stremfin:3135554');
      expect(item.serverId, server);
      expect(item.type, 'Audio');
      expect(item.isAudioLike, isTrue);
      expect(item.name, 'Aerodynamic');
      expect(item.artists, ['Daft Punk']);
      expect(item.album, 'Discovery');
      expect(item.runtime, const Duration(seconds: 207));
      expect(isKostvStream(item), isTrue);
      final info = KostvStreamInfo.of(item)!;
      expect(info.deezerId, '3135554');
      expect(info.cover, 'https://cdn.example/cover.jpg');
      expect(info.albumDeezerId, '302127');
      expect(info.artistDeezerId, '27');
      expect(info.explicit, isTrue);
      expect(info.listenReady, isTrue);
      expect(
        isKostvStream(
          const AggregatedItem(id: 'abc', serverId: server, rawData: {}),
        ),
        isFalse,
      );
      expect(isKostvStreamId('stremfin:'), isFalse);
      expect(
        kostvStreamItemFromSong(
          const StremfinSong(title: 'Chart'),
          serverId: server,
        ),
        isNull,
      );
    });

    test('an album\'s song takes the album\'s cover, name and artist', () {
      const album = StremfinAlbum(
        title: 'Discovery',
        deezerId: '302127',
        artist: 'Daft Punk',
        cover: 'https://cdn.example/d.jpg',
      );
      const track = StremfinAlbumTrack(
        title: 'Digital Love',
        deezerId: '3',
        duration: 301,
      );
      final item = kostvStreamItemFromTrack(
        track,
        album,
        serverId: server,
        artistDeezerId: '27',
      )!;
      expect(item.artists, ['Daft Punk']);
      expect(item.albumArtist, 'Daft Punk');
      expect(KostvStreamInfo.of(item)!.cover, 'https://cdn.example/d.jpg');
      expect(KostvStreamInfo.of(item)!.albumDeezerId, '302127');
    });

    test('8.38\'s rule: at home from home, else with a Deezer id through '
        'the service, else not at all', () {
      expect(
        kostvSongWay(inJellyfin: true, jellyfinId: 'j', deezerId: '1'),
        KostvSongWay.home,
      );
      expect(
        kostvSongWay(inJellyfin: false, deezerId: '1'),
        KostvSongWay.stream,
      );
      expect(kostvSongWay(inJellyfin: false), KostvSongWay.none);
      expect(kostvStreamAllowed(explicit: true, hideExplicit: true), isFalse);
      expect(kostvStreamAllowed(explicit: true, hideExplicit: false), isTrue);
    });

    test('a mixed queue: home songs asked for in one go, the rest through '
        'the service, in order; what can\'t sound is left out', () async {
      AggregatedItem home(String id) => AggregatedItem(
        id: id,
        serverId: server,
        rawData: {'Id': id, 'Name': id, 'Type': 'Audio'},
      );
      final asked = <List<String>>[];
      final songs = [
        KostvQueueSong.ofSong(
          const StremfinSong(
            title: 'A',
            deezerId: '1',
            inJellyfin: true,
            jellyfinId: 'ja',
          ),
          serverId: server,
        ),
        KostvQueueSong.ofSong(
          const StremfinSong(title: 'Chart only'),
          serverId: server,
        ),
        KostvQueueSong.ofSong(
          const StremfinSong(title: 'Explicit', deezerId: '3', explicit: true),
          serverId: server,
        ),
        KostvQueueSong.ofSong(
          const StremfinSong(title: 'B', deezerId: '4'),
          serverId: server,
        ),
        // Kos TV: at home, but the home server doesn't give it (gone, or
        // kept from the person by its parental control): left out.
        KostvQueueSong.ofSong(
          const StremfinSong(
            title: 'C',
            deezerId: '5',
            inJellyfin: true,
            jellyfinId: 'gone',
          ),
          serverId: server,
        ),
      ];
      final queue = await kostvQueueOf(
        songs,
        startIndex: 1,
        hideExplicit: true,
        homeItems: (ids) async {
          asked.add(ids);
          return [home('ja')];
        },
      );
      expect(asked, [
        ['ja', 'gone'],
      ]);
      expect(queue.items.map((i) => i.id), ['ja', 'stremfin:4']);
      // The one picked couldn't sound: the next one that can.
      expect(queue.startIndex, 1);
      // The home server not answering at all: through the service, only
      // when asked to (all the music, no limit).
      final grown = await kostvQueueOf(
        songs,
        startIndex: 2,
        hideExplicit: false,
        homeItems: (_) async => throw StateError('offline'),
        streamWhenHomeFails: true,
      );
      expect(grown.items.map((i) => i.id), [
        'stremfin:1',
        'stremfin:3',
        'stremfin:4',
        'stremfin:5',
      ]);
      expect(grown.startIndex, 1);
      final kept = await kostvQueueOf(
        songs,
        hideExplicit: false,
        homeItems: (_) async => throw StateError('offline'),
      );
      expect(kept.items.map((i) => i.id), ['stremfin:3', 'stremfin:4']);
    });

    test('an album\'s songs say nothing of explicit: with a limit, those '
        'that aren\'t at home don\'t sound', () async {
      const album = StremfinAlbum(title: 'Disco', deezerId: '9');
      const away = StremfinAlbumTrack(title: 'Fuera', deezerId: '1');
      const home = StremfinAlbumTrack(
        title: 'Casa',
        deezerId: '2',
        inJellyfin: true,
        jellyfinId: 'jh',
      );
      Future<List<String>> queue({required bool limit}) async =>
          (await kostvQueueOf(
            [
              for (final track in const [away, home])
                KostvQueueSong.ofTrack(
                  track,
                  album,
                  serverId: server,
                  explicit: limit,
                ),
            ],
            hideExplicit: limit,
            homeItems: (ids) async => [
              for (final id in ids)
                AggregatedItem(
                  id: id,
                  serverId: server,
                  rawData: {'Id': id, 'Name': id, 'Type': 'Audio'},
                ),
            ],
          )).items.map((i) => i.id).toList();
      expect(await queue(limit: true), ['jh']);
      expect(await queue(limit: false), ['stremfin:1', 'jh']);
    });
  });
}
