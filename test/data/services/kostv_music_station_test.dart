import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_radio.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/ui/widgets/music/kostv_stream_play.dart'
    show kostvPluginStationFor, kostvSongStation;
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

const _device = DeviceInfo(
  id: 'device',
  name: 'Device',
  appName: 'kOS TV',
  appVersion: '1.0.0',
);

const _server = 'https://casa.example';
const _route = '/Moonfin/Kostv/Music/Station';

/// The server plugin's `Station` route ([station] null: a plugin from
/// before it, answering 404), noting what it was asked with.
class _Plugin implements HttpClientAdapter {
  _Plugin([this.station]);

  final Object? station;
  final asked = <Map<String, String>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path != _route) return ResponseBody.fromString('', 404);
    asked.add(options.uri.queryParameters);
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

Map<String, Object?> _away(String deezerId, String artist) => {
  'Title': 'Fuera $deezerId',
  'Artist': artist,
  'DeezerId': deezerId,
  'Explicit': false,
};

final _answer = {
  'Seed': {'Title': 'Canción seed', 'Artist': 'Lola'},
  'Items': [
    {'Card': _card('h1', 'Nube'), 'Away': null, 'Why': 'listenbrainz'},
    {'Card': null, 'Away': _away('7', 'Rayo'), 'Why': 'style'},
    {'Card': _card('h2', 'Sol'), 'Away': null, 'Why': 'deezer'},
  ],
  'Source': 'listenbrainz',
};

AggregatedItem _seed() => AggregatedItem(
  id: 'seed',
  serverId: _server,
  rawData: _card('seed', 'Lola'),
);

void main() {
  late JellyfinMediaServerClient client;

  setUp(() {
    client = JellyfinMediaServerClient(baseUrl: _server, deviceInfo: _device)
      ..accessToken = 'token'
      ..userId = 'ana';
  });

  tearDown(() async {
    await GetIt.instance.reset();
    KostvMusicPlugin.instance = KostvMusicPlugin();
    KostvStreamRadio.instance = KostvStreamRadio();
  });

  KostvMusicPlugin pluginWith(_Plugin routes) =>
      KostvMusicPlugin(dio: Dio()..httpClientAdapter = routes);

  group('GET Music/Station', () {
    test('asks with the seed, its title and artist, the limit and away, and '
        'reads Card and Away in order', () async {
      final routes = _Plugin(_answer);
      final answer = await pluginWith(routes).station(
        client,
        seed: 'stremfin:42',
        title: 'Canción 42',
        artist: 'Lola',
        away: true,
      );
      expect(routes.asked.single, {
        'seed': 'stremfin:42',
        'title': 'Canción 42',
        'artist': 'Lola',
        'limit': '50',
        'away': 'true',
      });
      final station = answer.value!;
      expect(station.source, 'listenbrainz');
      expect(station.entries.map((e) => e.card?.id ?? e.away?.deezerId), [
        'h1',
        '7',
        'h2',
      ]);
      expect(station.entries[1].why, 'style');
      expect(station.entries.first.card!.serverId, _server);
    });

    test('what isn\'t at home comes with its cover, length, album and '
        'artist; Partial says whether it is still being worked out', () async {
      final routes = _Plugin({
        ..._answer,
        'Items': [
          {
            'Away': {
              ..._away('9', 'Rayo'),
              'Cover': 'https://cdn.example/9.jpg',
              'Duration': 201,
              'AlbumDeezerId': '90',
              'ArtistDeezerId': '91',
            },
            'Why': 'listenbrainz',
          },
          {
            'Away': {..._away('10', 'Nube'), 'Cover': 'http://inseguro/10.jpg'},
          },
        ],
        'Source': 'fallback',
        'Partial': false,
      });
      final station = (await pluginWith(
        routes,
      ).station(client, seed: 'seed', away: true)).value!;
      final away = station.entries.first.away!;
      expect(away.cover, 'https://cdn.example/9.jpg');
      expect(away.duration, 201);
      expect(away.albumDeezerId, '90');
      expect(away.artistDeezerId, '91');
      expect(station.entries[1].away!.cover, isNull);
      // Whole, of Deezer's radio only: nothing more to wait for.
      expect(station.partial, isFalse);
      expect(station.unfinished, isFalse);

      final item = kostvStationFromPlugin(
        station,
        serverId: _server,
        includeAway: true,
        hideExplicit: false,
      ).first;
      final info = KostvStreamInfo.of(item)!;
      expect(info.cover, 'https://cdn.example/9.jpg');
      expect(info.albumDeezerId, '90');
      expect(info.artistDeezerId, '91');
      expect(item.rawData['RunTimeTicks'], 201 * 10000000);

      expect(
        KostvMusicStation.fromJson({
          'Items': const [],
          'Source': 'listenbrainz',
          'Partial': true,
        }, _server)!.unfinished,
        isTrue,
      );
      // A plugin that doesn't say: «fallback» is taken as not finished.
      expect(
        KostvMusicStation.fromJson({
          'Items': const [],
          'Source': 'fallback',
        }, _server)!.unfinished,
        isTrue,
      );
    });

    test('a plugin from before it: missing, and left alone a while', () async {
      final routes = _Plugin();
      final plugin = pluginWith(routes);
      final answer = await plugin.station(client, seed: 'seed', away: true);
      expect(answer.missing, isTrue);
      expect(plugin.knownMissing(client, 'Station'), isTrue);
      await plugin.station(client, seed: 'seed', away: true);
      expect(routes.asked, hasLength(1));
    });
  });

  group('the app\'s station from the plugin\'s', () {
    test('a song at home goes by its id; Card and Away as the queue takes '
        'them, without the seed', () async {
      final routes = _Plugin({
        ..._answer,
        'Items': [
          {'Card': _card('seed', 'Lola')},
          ...(_answer['Items']! as List),
        ],
      });
      final items = await kostvPluginStationFor(
        _seed(),
        client: client,
        includeAway: true,
        hideExplicit: false,
        plugin: pluginWith(routes),
      );
      expect(routes.asked.single['seed'], 'seed');
      expect(routes.asked.single['title'], 'Canción seed');
      expect(routes.asked.single['artist'], 'Lola');
      expect(items!.map((e) => e.id), ['h1', 'stremfin:7', 'h2']);
      expect(isKostvStream(items[1]), isTrue);
    });

    test('a song that isn\'t at home goes as stremfin:<DeezerId>', () async {
      final routes = _Plugin(_answer);
      final seed = kostvStreamItem(
        deezerId: '42',
        title: 'Fuera 42',
        serverId: _server,
        artist: 'Lola',
      );
      await kostvPluginStationFor(
        seed,
        client: client,
        includeAway: true,
        hideExplicit: false,
        plugin: pluginWith(routes),
      );
      expect(routes.asked.single['seed'], 'stremfin:42');
      expect(routes.asked.single['title'], 'Fuera 42');
      expect(routes.asked.single['artist'], 'Lola');
    });

    test(
      '«Solo la de casa» asks with away=false and keeps only Card',
      () async {
        final routes = _Plugin(_answer);
        final items = await kostvPluginStationFor(
          _seed(),
          client: client,
          includeAway: false,
          hideExplicit: false,
          plugin: pluginWith(routes),
        );
        expect(routes.asked.single['away'], 'false');
        expect(items!.map((e) => e.id), ['h1', 'h2']);
      },
    );

    test('kids and «No me gusta»: the app\'s own guard too', () async {
      final routes = _Plugin({
        ..._answer,
        'Items': [
          {
            'Away': {
              'Title': 'Fuera 8',
              'Artist': 'Rayo',
              'DeezerId': '8',
              'Explicit': true,
            },
          },
          ...(_answer['Items']! as List),
        ],
      });
      final dislikes = KostvMusicDislikes.fromJson({
        'Songs': [
          {'Id': 'h2'},
        ],
      })!;
      final items = await kostvPluginStationFor(
        _seed(),
        client: client,
        includeAway: true,
        hideExplicit: true,
        dislikes: dislikes,
        plugin: pluginWith(routes),
      );
      expect(items!.map((e) => e.id), ['h1', 'stremfin:7']);
    });

    test('it is told when the station is still being worked out, and only '
        'then', () async {
      Future<bool> told(Map<String, Object?> answer) async {
        var partial = false;
        await kostvPluginStationFor(
          _seed(),
          client: client,
          includeAway: true,
          hideExplicit: false,
          plugin: pluginWith(_Plugin(answer)),
          onPartial: () => partial = true,
        );
        return partial;
      }

      expect(await told({..._answer, 'Partial': true}), isTrue);
      expect(await told({..._answer, 'Source': 'fallback'}), isTrue);
      expect(
        await told({..._answer, 'Source': 'fallback', 'Partial': false}),
        isFalse,
      );
      expect(await told(_answer), isFalse);
    });

    test('404, or nothing that can sound: none (the app makes it as '
        'before)', () async {
      expect(
        await kostvPluginStationFor(
          _seed(),
          client: client,
          includeAway: true,
          hideExplicit: false,
          plugin: pluginWith(_Plugin()),
        ),
        isNull,
      );
      expect(
        await kostvPluginStationFor(
          _seed(),
          client: client,
          includeAway: false,
          hideExplicit: false,
          plugin: pluginWith(
            _Plugin({
              'Items': [
                {'Away': _away('7', 'Rayo')},
              ],
              'Source': 'fallback',
            }),
          ),
        ),
        isNull,
      );
    });

    test('a plugin from before it: «Crear emisora» of a song that isn\'t at '
        'home is the radio of its artist, in its order', () async {
      KostvMusicPlugin.instance = pluginWith(_Plugin());
      final asked = <List<String>>[];
      KostvStreamRadio.instance = KostvStreamRadio(
        fetch: (artists, {artistIds = const [], only, limit}) async {
          asked.add(artistIds);
          return const StremfinRadio(
            songs: [
              StremfinSong(title: 'Uno', deezerId: '1', artist: 'Rayo'),
              StremfinSong(title: 'Dos', deezerId: '2', artist: 'Rayo'),
              StremfinSong(title: 'Tres', deezerId: '3', artist: 'Sol'),
            ],
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
      expect(station.map((e) => e.id), [
        'stremfin:1',
        // Not Rayo twice in a row: the next one by someone else first.
        'stremfin:3',
        'stremfin:2',
      ]);
    });
  });
}
