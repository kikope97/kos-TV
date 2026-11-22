import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_catalog.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/kostv_song_radio.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_radio.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/music/kostv_stream_play.dart'
    show kostvSongRadioStationFor, kostvSongStation;
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _server = 'https://casa.example';

/// The requests service, noting what it was asked.
class _Service implements HttpClientAdapter {
  _Service(this.answer);

  final ({int status, Object? body}) Function(RequestOptions options) answer;
  final asked = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    final (:status, :body) = answer(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The server plugin's `Station` ([station] null: answering 404).
class _Plugin implements HttpClientAdapter {
  _Plugin([this.station]);

  final Object? station;
  final asked = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.uri.path.endsWith('/Music/Station')) {
      return ResponseBody.fromString('', 404);
    }
    asked.add(options.uri.queryParameters['seed']);
    if (station == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromString(
      jsonEncode(station),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _card(String id, String artist) => {
  'Id': id,
  'Name': 'Canción $id',
  'Type': 'Audio',
  'MediaType': 'Audio',
  'Artists': [artist],
  'ArtistItems': [
    {'Id': 'id-$artist', 'Name': artist},
  ],
};

AggregatedItem _home(String id, String artist, {String? isrc}) =>
    AggregatedItem(
      id: id,
      serverId: _server,
      rawData: {
        ..._card(id, artist),
        if (isrc != null) 'ProviderIds': {'ISRC': isrc},
      },
    );

StremfinSong _away(
  String deezerId,
  String artist, {
  bool explicit = false,
  String? jellyfinId,
}) => StremfinSong(
  title: 'Fuera $deezerId',
  deezerId: deezerId,
  artist: artist,
  explicit: explicit,
  inJellyfin: jellyfinId != null,
  jellyfinId: jellyfinId,
);

final _pluginAnswer = {
  'Items': [
    {'Card': _card('p1', 'Nube')},
    {'Card': _card('p2', 'Sol')},
  ],
  'Source': 'listenbrainz',
  'Partial': false,
};

void main() {
  late JellyfinMediaServerClient client;
  late List<String> fetched;
  late List<List<KostvMatchSong>> matched;
  late DateTime now;

  setUp(() {
    client =
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
    fetched = [];
    matched = [];
    now = DateTime(2026, 11, 22, 12);
  });

  tearDown(() async {
    await GetIt.instance.reset();
    KostvMusicPlugin.instance = KostvMusicPlugin();
    KostvStreamRadio.instance = KostvStreamRadio();
    KostvSongRadio.instance = KostvSongRadio();
    KostvMusicCatalog.instance = KostvMusicCatalog();
  });

  KostvSongRadio radioWith(
    Future<StremfinSongRadio> Function(String id) answer, {
    Future<StremfinSongMatch> Function(List<KostvMatchSong>)? match,
    String? version = '1.101.0',
    KostvStreamRadio? shares,
  }) => KostvSongRadio(
    fetch: (id, {only, limit}) {
      fetched.add(id);
      return answer(id);
    },
    match: (songs) {
      matched.add(songs);
      return match?.call(songs) ??
          Future.value(const StremfinSongMatch(songs: [null]));
    },
    version: () => version,
    available: () => true,
    who: () => 'ana',
    clock: () => now,
    shares: shares,
  );

  Future<StremfinSongRadio> fourAway(String id) async => StremfinSongRadio(
    songs: [
      _away('$id-1', 'Rayo'),
      _away('$id-2', 'Rayo'),
      _away('$id-3', 'Sol'),
      _away('$id-4', 'Luna'),
    ],
  );

  KostvMusicPlugin pluginWith(_Plugin routes) =>
      KostvMusicPlugin(dio: Dio()..httpClientAdapter = routes);

  AggregatedItem streamSeed([String id = '42']) => kostvStreamItem(
    deezerId: id,
    title: 'Fuera $id',
    serverId: _server,
    artist: 'Lola',
  );

  group('the service\'s calls', () {
    test(
      'a song\'s radio: its path, only and limit, and the songs with '
      'their whole album; match: up to 50 in order, null and failed',
      () async {
        final service = _Service((options) {
          if (options.uri.path.endsWith('/music/songs/42/radio')) {
            return (
              status: 200,
              body: {
                'seed': {
                  'deezer_id': '42',
                  'title': 'Semilla',
                  'artist': 'Lola',
                },
                'only': 'all',
                'songs': [
                  {
                    'deezer_id': '7',
                    'title': 'Siete',
                    'artist': 'Rayo',
                    'explicit': true,
                    'in_jellyfin': true,
                    'jellyfin_id': 'h7',
                    'album': {
                      'deezer_id': 'a7',
                      'title': 'Disco',
                      'cover': 'https://img.example/7.jpg',
                      'can_request': false,
                    },
                    'reason': 'Se escucha junto a «Semilla»',
                    'source': 'together',
                  },
                ],
                'failed': ['listenbrainz'],
              },
            );
          }
          if (options.uri.path.endsWith('/music/songs/match')) {
            return (
              status: 200,
              body: {
                'songs': [
                  {'deezer_id': '9', 'title': 'Nueve', 'artist': 'Sol'},
                  null,
                  null,
                ],
                'failed': [2],
              },
            );
          }
          return (
            status: 404,
            body: {
              'error': {'code': 'not_found'},
            },
          );
        });
        final stremfin = StremfinClient(
          dio: Dio()..httpClientAdapter = service,
          baseUrl: 'https://requests.example.org/api/v1',
          token: () => 'token',
        );
        final radio = await stremfin.musicSongRadio(
          '42',
          only: 'all',
          limit: 500,
        );
        expect(service.asked.last.uri.queryParameters, {
          'only': 'all',
          'limit': '100',
        });
        expect(
          service.asked.last.receiveTimeout,
          StremfinClient.songRadioTimeout,
        );
        expect(radio.seed!.deezerId, '42');
        expect(radio.failed, ['listenbrainz']);
        final song = radio.songs.single;
        expect(song.jellyfinId, 'h7');
        expect(song.explicit, isTrue);
        expect(song.album!.deezerId, 'a7');
        expect(song.cover, 'https://img.example/7.jpg');

        final match = await stremfin.musicSongsMatch([
          for (var i = 0; i < 60; i++)
            (
              title: 'T$i',
              artist: 'A',
              isrc: i == 0 ? 'ES-ABC-12-34567' : null,
            ),
        ]);
        final body = service.asked.last.data as Map;
        expect(service.asked.last.method, 'POST');
        expect((body['songs'] as List), hasLength(50));
        expect((body['songs'] as List).first, {
          'title': 'T0',
          'artist': 'A',
          'isrc': 'ES-ABC-12-34567',
        });
        expect((body['songs'] as List)[1], {'title': 'T1', 'artist': 'A'});
        expect(match.songs.map((s) => s?.deezerId), ['9', null, null]);
        expect(match.failed, {2});
      },
    );

    test('the service\'s version, from /me', () {
      final me = StremfinMe.fromJson({
        'user': {'role': 'member'},
        'server': {'name': 'Stremfin', 'version': '1.101.0', 'api_version': 1},
      });
      expect(me.serverVersion, '1.101.0');
      expect(kostvServiceAtLeast('1.101.0', '1.101.0'), isTrue);
      expect(kostvServiceAtLeast('1.100.3', '1.101.0'), isFalse);
      expect(kostvServiceAtLeast('2.0', '1.101.0'), isTrue);
      expect(kostvServiceAtLeast(null, '1.101.0'), isNull);
    });
  });

  group('the order of the sources', () {
    test('«Toda la música»: the song\'s radio leads; the plugin isn\'t '
        'asked', () async {
      final plugin = _Plugin(_pluginAnswer);
      KostvMusicPlugin.instance = pluginWith(plugin);
      KostvSongRadio.instance = radioWith(fourAway);
      final station = await kostvSongStation(streamSeed(), client: client);
      expect(fetched, ['42']);
      expect(plugin.asked, isEmpty);
      expect(station.map((e) => e.id), [
        'stremfin:42-1',
        // Not Rayo twice in a row.
        'stremfin:42-3',
        'stremfin:42-2',
        'stremfin:42-4',
      ]);
    });

    test('«Solo la de casa»: the plugin\'s station (away=false), as '
        'before; the song\'s radio isn\'t asked', () async {
      SharedPreferences.setMockInitialValues(const {});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      await prefs.set(UserPreferences.kostvMusicCatalogAll, false);
      KostvMusicCatalog.instance = KostvMusicCatalog(prefs: () => prefs);
      final plugin = _Plugin(_pluginAnswer);
      KostvMusicPlugin.instance = pluginWith(plugin);
      KostvSongRadio.instance = radioWith(fourAway);
      final station = await kostvSongStation(
        _home('seed', 'Lola'),
        client: client,
      );
      expect(fetched, isEmpty);
      expect(matched, isEmpty);
      expect(plugin.asked, ['seed']);
      expect(station.map((e) => e.id), ['p1', 'p2']);
    });

    Future<void> fallsBackOn(
      Object error, {
      String? version = '1.101.0',
    }) async {
      final plugin = _Plugin(_pluginAnswer);
      KostvMusicPlugin.instance = pluginWith(plugin);
      KostvSongRadio.instance = radioWith(
        (_) => Future.error(error),
        version: version,
      );
      final station = await kostvSongStation(streamSeed(), client: client);
      expect(plugin.asked, ['stremfin:42'], reason: '$error');
      expect(station.map((e) => e.id), ['p1', 'p2'], reason: '$error');
    }

    test('the song\'s radio fails: the plugin\'s station, for each '
        'error', () async {
      await fallsBackOn(const StremfinException(code: 'network'));
      await fallsBackOn(
        const StremfinException(code: 'source_unavailable', status: 503),
      );
      await fallsBackOn(
        const StremfinException(code: 'too_many_requests', status: 429),
      );
      await fallsBackOn(
        const StremfinException(code: 'not_found', status: 404),
      );
      await fallsBackOn(
        const StremfinException(code: 'not_found', status: 404),
        version: '1.100.0',
      );
    });

    test('nothing in it can sound for the person: the plugin\'s', () async {
      final plugin = _Plugin(_pluginAnswer);
      KostvMusicPlugin.instance = pluginWith(plugin);
      KostvSongRadio.instance = radioWith(
        (_) async =>
            StremfinSongRadio(songs: [_away('1', 'Rayo', explicit: true)]),
      );
      final station = await kostvSongStation(streamSeed(), client: client);
      expect(fetched, ['42']);
      expect(station.map((e) => e.id), ['p1', 'p2']);
    });

    test('neither: as before (the radio of its artist)', () async {
      KostvMusicPlugin.instance = pluginWith(_Plugin());
      KostvSongRadio.instance = radioWith(
        (_) => Future.error(
          const StremfinException(code: 'source_unavailable', status: 503),
        ),
      );
      final asked = <List<String>>[];
      KostvStreamRadio.instance = KostvStreamRadio(
        fetch: (artists, {artistIds = const [], only, limit}) async {
          asked.add(artistIds);
          return const StremfinRadio(
            songs: [StremfinSong(title: 'Uno', deezerId: '1', artist: 'Rayo')],
          );
        },
        who: () => 'test',
      );
      final seed = kostvStreamItem(
        deezerId: '42',
        title: 'Fuera 42',
        serverId: _server,
        artist: 'Lola',
        artistDeezerId: 'ar1',
      );
      final station = await kostvSongStation(seed, client: client);
      expect(asked.single, ['ar1']);
      expect(station.map((e) => e.id), ['stremfin:1']);
    });
  });

  group('a 404', () {
    test('of a service before it (by its version): not asked again for '
        'any song a while', () async {
      final radio = radioWith(
        (_) => Future.error(
          const StremfinException(code: 'not_found', status: 404),
        ),
        version: '1.100.0',
      );
      // Its version already says it hasn't it: not even asked.
      expect(radio.usable, isFalse);
      await expectLater(
        radio.songs('1'),
        throwsA(isA<KostvSongRadioUnavailable>()),
      );
      expect(fetched, isEmpty);
    });

    test(
      'of a song Deezer doesn\'t have: only that song is left alone',
      () async {
        final radio = radioWith(
          (id) => id == '1'
              ? Future.error(
                  const StremfinException(code: 'not_found', status: 404),
                )
              : fourAway(id),
        );
        await expectLater(radio.songs('1'), throwsA(isA<StremfinException>()));
        await expectLater(
          radio.songs('1'),
          throwsA(isA<KostvSongRadioUnavailable>()),
        );
        expect(radio.usable, isTrue);
        expect(await radio.songs('2'), hasLength(4));
        expect(fetched, ['1', '2']);
        now = now.add(KostvSongRadio.notThereFor);
        await expectLater(radio.songs('1'), throwsA(isA<StremfinException>()));
        expect(fetched, ['1', '2', '1']);
      },
    );

    test('version not known: two songs in a row without one read as a '
        'service before it', () async {
      final radio = radioWith(
        (_) => Future.error(
          const StremfinException(code: 'not_found', status: 404),
        ),
        version: null,
      );
      await expectLater(radio.songs('1'), throwsA(isA<StremfinException>()));
      expect(radio.usable, isTrue);
      await expectLater(radio.songs('2'), throwsA(isA<StremfinException>()));
      expect(radio.usable, isFalse);
      now = now.add(KostvSongRadio.missingFor);
      expect(radio.usable, isTrue);
    });
  });

  group('the ten a minute', () {
    test('each song\'s radio is asked once and kept an hour', () async {
      final radio = radioWith(fourAway);
      await radio.songs('1');
      await radio.songs('1');
      expect(radio.keeps('1'), isTrue);
      expect(fetched, ['1']);
      now = now.add(KostvSongRadio.keep);
      expect(radio.keeps('1'), isFalse);
      await radio.songs('1');
      expect(fetched, ['1', '1']);
    });

    test('«too many»: left alone for its Retry-After, and so is the '
        'artists\' radio (the same ten)', () async {
      final shared = KostvStreamRadio(
        fetch: (artists, {artistIds = const [], only, limit}) async =>
            const StremfinRadio(),
        who: () => 'ana',
        clock: () => now,
      );
      final radio = radioWith(
        (_) => Future.error(
          const StremfinException(
            code: 'too_many_requests',
            status: 429,
            retryAfter: Duration(seconds: 40),
          ),
        ),
        shares: shared,
      );
      await expectLater(radio.songs('1'), throwsA(isA<StremfinException>()));
      await expectLater(
        radio.songs('2'),
        throwsA(isA<KostvSongRadioUnavailable>()),
      );
      await expectLater(shared.songs(artists: ['Lola']), throwsA(anything));
      expect(fetched, ['1']);
      expect(shared.calls, 0);
      now = now.add(const Duration(seconds: 41));
      await expectLater(radio.songs('2'), throwsA(isA<StremfinException>()));
      expect(fetched, ['1', '2']);
    });

    test('not answering (503, timeout): left alone a minute', () async {
      final radio = radioWith(
        (_) => Future.error(const StremfinException(code: 'network')),
      );
      await expectLater(radio.songs('1'), throwsA(isA<StremfinException>()));
      await expectLater(
        radio.songs('1'),
        throwsA(isA<KostvSongRadioUnavailable>()),
      );
      now = now.add(KostvSongRadio.quiet);
      await expectLater(radio.songs('1'), throwsA(isA<StremfinException>()));
      expect(fetched, ['1', '1']);
    });
  });

  group('a seed at home', () {
    test('matched once by its title, artist and ISRC, and kept', () async {
      final radio = radioWith(
        fourAway,
        match: (songs) async => const StremfinSongMatch(
          songs: [StremfinSong(title: 'Canción seed', deezerId: '42')],
        ),
      );
      final seed = _home('seed', 'Lola', isrc: 'ES1234567890');
      final first = await kostvSongRadioStationFor(
        seed,
        client: client,
        hideExplicit: false,
        radio: radio,
        homeItems: (ids) async => const [],
      );
      expect(matched.single.single, (
        title: 'Canción seed',
        artist: 'Lola',
        isrc: 'ES1234567890',
      ));
      expect(fetched, ['42']);
      expect(first, hasLength(4));
      await kostvSongRadioStationFor(
        seed,
        client: client,
        hideExplicit: false,
        radio: radio,
        homeItems: (ids) async => const [],
      );
      expect(matched, hasLength(1));
      expect(fetched, ['42']);
    });

    test('Deezer doesn\'t have it: no radio (the plugin\'s then), and not '
        'matched again for a while; not answered: asked again', () async {
      var failed = true;
      final radio = radioWith(
        fourAway,
        match: (songs) async => failed
            ? const StremfinSongMatch(songs: [null], failed: {0})
            : const StremfinSongMatch(songs: [null]),
      );
      final seed = _home('seed', 'Lola');
      Future<List<AggregatedItem>?> ask() => kostvSongRadioStationFor(
        seed,
        client: client,
        hideExplicit: false,
        radio: radio,
        homeItems: (ids) async => const [],
      );
      expect(await ask(), isNull);
      failed = false;
      expect(await ask(), isNull);
      expect(await ask(), isNull);
      expect(matched, hasLength(2));
      expect(fetched, isEmpty);
    });

    test('a song the radio said is at home needs no matching', () async {
      final radio = radioWith(
        (id) async =>
            StremfinSongRadio(songs: [_away('5', 'Sol', jellyfinId: 'h5')]),
      );
      await radio.songs('42');
      expect(await radio.deezerIdOf(_home('h5', 'Sol'), artist: 'Sol'), '5');
      expect(matched, isEmpty);
    });
  });

  group('what goes in the queue', () {
    test('at home from home; one the home server doesn\'t give the person '
        'is left out, never streamed', () async {
      final radio = radioWith(
        (_) async => StremfinSongRadio(
          songs: [
            _away('1', 'Rayo', jellyfinId: 'h1'),
            _away('2', 'Sol', jellyfinId: 'hidden'),
            _away('3', 'Luna'),
          ],
        ),
      );
      final asked = <List<String>>[];
      final station = await kostvSongRadioStationFor(
        streamSeed(),
        client: client,
        hideExplicit: false,
        radio: radio,
        homeItems: (ids) async {
          asked.add(ids);
          return [_home('h1', 'Rayo')];
        },
      );
      expect(asked.single, ['h1', 'hidden']);
      expect(station!.map((e) => e.id), ['h1', 'stremfin:3']);
    });

    test('kids: nothing explicit from away; «No me gusta», the seed and '
        'what is in the queue are left out', () async {
      final radio = radioWith(
        (_) async => StremfinSongRadio(
          songs: [
            _away('1', 'Rayo', explicit: true),
            _away('2', 'Sol'),
            _away('3', 'Nube'),
            _away('42', 'Lola'),
            _away('4', 'Luna'),
            _away('5', 'Mar', jellyfinId: 'h5', explicit: true),
          ],
        ),
      );
      final dislikes = KostvMusicDislikes.fromJson({
        'Songs': [
          {'DeezerId': '3', 'Name': 'Fuera 3'},
        ],
      })!;
      final station = await kostvSongRadioStationFor(
        streamSeed(),
        client: client,
        hideExplicit: true,
        dislikes: dislikes,
        skip: {'stremfin:4'},
        radio: radio,
        homeItems: (ids) async => [_home('h5', 'Mar')],
      );
      // At home, Jellyfin's own control says what the person sees.
      expect(station!.map((e) => e.id), ['stremfin:2', 'h5']);
    });
  });
}
