import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/music/music_navigation.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

const _device = DeviceInfo(
  id: 'device',
  name: 'Device',
  appName: 'kOS TV',
  appVersion: '1.0.0',
);

/// The server plugin's music routes, as the plan sets them, or a plugin
/// from before them ([hasRoutes] false: everything answers 404).
class _Plugin implements HttpClientAdapter {
  _Plugin({
    this.hasRoutes = true,
    this.answers = const {},
    this.statuses = const {},
  });

  final bool hasRoutes;

  /// The status of a route's answer, when it isn't 200 (or 204 without one).
  final Map<String, int> statuses;

  /// Each route's answer, by `METHOD /path`.
  final Map<String, Object?> answers;

  final asked = <({String method, String path, Object? body})>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      if (bytes.isNotEmpty) body = jsonDecode(utf8.decode(bytes));
    }
    final key = '${options.method} ${options.uri.path}';
    asked.add((method: options.method, path: options.uri.path, body: body));
    if (!hasRoutes || !answers.containsKey(key)) {
      return ResponseBody.fromString('', 404);
    }
    final answer = answers[key];
    if (answer == null) return ResponseBody.fromString('', 204);
    return ResponseBody.fromString(
      jsonEncode(answer),
      statuses[key] ?? 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A player that only notes what it was asked to play, and never finishes
/// starting it.
class _Player extends Fake implements PlaybackManager {
  final played = <List<dynamic>>[];

  @override
  Future<void> playItems(
    List<dynamic> items, {
    int startIndex = 0,
    Duration startPosition = Duration.zero,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? mediaSourceId,
    bool audioSelectionExplicit = false,
    bool subtitleSelectionExplicit = false,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
    bool autoPlay = true,
    bool carryTrackSelections = false,
  }) {
    played.add(items);
    return Completer<void>().future;
  }
}

AggregatedItem _song(String id, {String type = 'Audio'}) => AggregatedItem(
  id: id,
  serverId: 'https://casa.example',
  rawData: {'Id': id, 'Name': 'Canción $id', 'Type': type},
);

StremfinSong _stremfin(String id, {String? artist}) =>
    StremfinSong(title: 'Canción $id', deezerId: id, artist: artist ?? 'Lola');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late JellyfinMediaServerClient client;

  setUp(() {
    client =
        JellyfinMediaServerClient(
            baseUrl: 'https://casa.example',
            deviceInfo: _device,
          )
          ..accessToken = 'token'
          ..userId = 'ana';
  });

  tearDown(() async {
    await GetIt.instance.reset();
    KostvMusicPlugin.instance = KostvMusicPlugin();
  });

  KostvMusicPlugin pluginWith(_Plugin plugin) =>
      KostvMusicPlugin(dio: Dio()..httpClientAdapter = plugin);

  group('Settings and Listens', () {
    test('reads whether it learns, how much and since when', () async {
      final plugin = pluginWith(
        _Plugin(
          answers: {
            'GET /Moonfin/Kostv/Music/Settings': {
              'Learn': true,
              'Listens': 1234,
              'Since': '2026-11-20T10:00:00Z',
            },
          },
        ),
      );
      final state = await plugin.settings(client);
      expect(state!.learn, isTrue);
      expect(state.listens, 1234);
      expect(state.since!.toUtc(), DateTime.utc(2026, 11, 20, 10));
    });

    test(
      'turning it off sends Learn false and gives the state after',
      () async {
        final routes = _Plugin(
          answers: {
            'POST /Moonfin/Kostv/Music/Settings': {
              'Learn': false,
              'Listens': 3,
              'Since': null,
            },
          },
        );
        final state = await pluginWith(routes).setLearn(client, false);
        expect(state!.learn, isFalse);
        expect(state.since, isNull);
        expect(routes.asked.single.body, {'Learn': false});
      },
    );

    test('deleting what was listened to is a DELETE of Listens', () async {
      final routes = _Plugin(
        answers: {'DELETE /Moonfin/Kostv/Music/Listens': null},
      );
      expect(await pluginWith(routes).forgetListens(client), isTrue);
      expect(routes.asked.single.method, 'DELETE');
    });

    test('an older plugin (404): no setting, and it isn\'t asked again '
        'for a while', () async {
      final routes = _Plugin(hasRoutes: false);
      final plugin = pluginWith(routes);
      expect(await plugin.settings(client), isNull);
      expect(plugin.knownMissing(client, 'Settings'), isTrue);
      expect(await plugin.settings(client), isNull);
      expect(routes.asked, hasLength(1));
      expect(await plugin.forgetListens(client), isFalse);
    });

    test('Since missing, null or with fractions of a second', () {
      expect(
        KostvMusicLearnState.fromJson({'Learn': true, 'Listens': 0})!.since,
        isNull,
      );
      expect(
        KostvMusicLearnState.fromJson({
          'Learn': false,
          'Listens': 2,
          'Since': null,
        })!.since,
        isNull,
      );
      expect(
        KostvMusicLearnState.fromJson({
          'Learn': true,
          'Listens': 2,
          'Since': '2026-11-20T10:00:00.1234567Z',
        })!.since!.toUtc().hour,
        10,
      );
    });

    test('an answer that isn\'t one reads as no setting', () async {
      final plugin = pluginWith(
        _Plugin(answers: {'GET /Moonfin/Kostv/Music/Settings': 'hola'}),
      );
      expect(await plugin.settings(client), isNull);
    });
  });

  group('Mixes', () {
    final answer = {
      'Day': '2026-11-20',
      'Mixes': [
        {
          'Id': 'daily-1',
          'Genre': 'Reguetón',
          'Artists': [
            {
              'Id': '4b1f0a2c-0000-4000-8000-00000000000a',
              'Name': 'Lola Brisa',
              'Type': 'MusicArtist',
              'ImageTags': {'Primary': 'p'},
            },
          ],
          'Items': [
            {
              'Id': '4b1f0a2c-0000-4000-8000-000000000001',
              'Name': 'Verano',
              'Type': 'Audio',
              'AlbumId': '4b1f0a2c-0000-4000-8000-0000000000a1',
              'Overview': 'Not kept on the device.',
            },
          ],
        },
        // A mix without songs isn't one.
        {'Id': 'daily-2', 'Genre': 'Pop', 'Artists': [], 'Items': []},
      ],
    };

    test('reads them, ids without dashes', () async {
      final mixes = await pluginWith(
        _Plugin(answers: {'GET /Moonfin/Kostv/Music/Mixes': answer}),
      ).mixes(client);
      expect(mixes!.day, '2026-11-20');
      expect(mixes.mixes, hasLength(1));
      final mix = mixes.mixes.single;
      expect(mix.id, 'daily-1');
      expect(mix.genre, 'Reguetón');
      expect(mix.artists.single.id, '4b1f0a2c00004000800000000000000a');
      expect(mix.items.single.id, '4b1f0a2c000040008000000000000001');
      expect(mix.items.single.albumId, '4b1f0a2c0000400080000000000000a1');
      expect(mix.items.single.serverId, 'https://casa.example');
    });

    test('kept on the device and read back, without what isn\'t used', () {
      final mixes = KostvDailyMixes.fromJson(answer, 'https://casa.example')!;
      final kept = jsonDecode(jsonEncode(mixes.toJson()));
      final back = KostvDailyMixes.fromJson(kept, 'https://casa.example')!;
      expect(back.mixes.single.items.single.name, 'Verano');
      expect(back.mixes.single.genre, 'Reguetón');
      expect(
        back.mixes.single.items.single.rawData.containsKey('Overview'),
        isFalse,
      );
    });

    test('an older plugin (404): none', () async {
      expect(await pluginWith(_Plugin(hasRoutes: false)).mixes(client), isNull);
    });
  });

  group('Discovery', () {
    test('the artists to ask with, and no songs yet', () async {
      final found = await pluginWith(
        _Plugin(
          answers: {
            'GET /Moonfin/Kostv/Music/Discovery': {
              'Week': '2026-W47',
              'Seeds': ['Bad Bunny', 'Rosalía', ''],
              'Songs': null,
            },
          },
        ),
      ).discovery(client);
      expect(found!.week, '2026-W47');
      expect(found.seeds, ['Bad Bunny', 'Rosalía']);
      expect(found.songs, isNull);
    });

    test('the week\'s songs, as the app kept them', () async {
      final song = StremfinSong(
        title: 'Despechá',
        deezerId: '123',
        artist: 'Rosalía',
        artistDeezerId: '4795231',
        cover: 'https://cdn.example/c.jpg',
        albumTitle: 'Motomami',
        albumDeezerId: '777',
        reason: 'Porque escuchas a Bad Bunny',
      );
      final found = await pluginWith(
        _Plugin(
          answers: {
            'GET /Moonfin/Kostv/Music/Discovery': {
              'Week': '2026-W47',
              'Seeds': ['Bad Bunny'],
              'Songs': [kostvStremfinSongJson(song)],
            },
          },
        ),
      ).discovery(client);
      final back = found!.songs!.single;
      expect(back.title, 'Despechá');
      expect(back.deezerId, '123');
      expect(back.artistDeezerId, '4795231');
      expect(back.albumTitle, 'Motomami');
      expect(back.albumDeezerId, '777');
      expect(back.reason, 'Porque escuchas a Bad Bunny');
      expect(back.inJellyfin, isFalse);
    });

    test(
      'keeping the week\'s songs is a PUT with the week, 30 at most',
      () async {
        final routes = _Plugin(
          answers: {'PUT /Moonfin/Kostv/Music/Discovery': null},
        );
        final kept = await pluginWith(routes).keepDiscovery(
          client,
          '2026-W47',
          [for (var i = 0; i < 40; i++) _stremfin('$i')],
        );
        expect(kept.kept, isTrue);
        expect(kept.week, isNull);
        final body = routes.asked.single.body as Map;
        expect(routes.asked.single.method, 'PUT');
        expect(body['Week'], '2026-W47');
        expect(body['Songs'], hasLength(30));
        expect((body['Songs'] as List).first['deezer_id'], '0');
      },
    );

    test('a week that is over (409) gives the plugin\'s week, and the '
        'route isn\'t taken for missing', () async {
      final plugin = pluginWith(
        _Plugin(
          answers: {
            'PUT /Moonfin/Kostv/Music/Discovery': {
              'Error': 'Only this week\'s list can be stored.',
              'Week': '2026-W48',
            },
          },
          statuses: {'PUT /Moonfin/Kostv/Music/Discovery': 409},
        ),
      );
      final kept = await plugin.keepDiscovery(client, '2026-W47', [
        _stremfin('1'),
      ]);
      expect(kept.kept, isFalse);
      expect(kept.week, '2026-W48');
      expect(plugin.knownMissing(client, 'Discovery'), isFalse);
    });

    test('a list it won\'t take (400, 413) is only not kept', () async {
      for (final status in [400, 413]) {
        final plugin = pluginWith(
          _Plugin(
            answers: {
              'PUT /Moonfin/Kostv/Music/Discovery': {'Error': 'No.'},
            },
            statuses: {'PUT /Moonfin/Kostv/Music/Discovery': status},
          ),
        );
        final kept = await plugin.keepDiscovery(client, '2026-W47', [
          _stremfin('1'),
        ]);
        expect(kept.kept, isFalse);
        expect(kept.week, isNull);
      }
    });

    test('an older plugin (404): none', () async {
      expect(
        await pluginWith(_Plugin(hasRoutes: false)).discovery(client),
        isNull,
      );
    });
  });

  group('Moment', () {
    test('shown only when ready, with songs', () async {
      final ready = await pluginWith(
        _Plugin(
          answers: {
            'GET /Moonfin/Kostv/Music/Moment': {
              'Slot': 'tarde',
              'Ready': true,
              'Items': [
                {'Id': 'a-1', 'Name': 'Verano', 'Type': 'Audio'},
              ],
            },
          },
        ),
      ).moment(client);
      expect(ready!.slot, 'tarde');
      expect(ready.shows, isTrue);
      expect(ready.items.single.id, 'a1');

      final waiting = await pluginWith(
        _Plugin(
          answers: {
            'GET /Moonfin/Kostv/Music/Moment': {
              'Slot': 'noche',
              'Ready': false,
            },
          },
        ),
      ).moment(client);
      expect(waiting!.shows, isFalse);
    });

    test('the slots of the day, as the plugin counts them', () {
      expect(kostvMusicSlotAt(DateTime(2026, 11, 20, 5, 59)), 'noche');
      expect(kostvMusicSlotAt(DateTime(2026, 11, 20, 6)), 'manana');
      expect(kostvMusicSlotAt(DateTime(2026, 11, 20, 12)), 'tarde');
      expect(kostvMusicSlotAt(DateTime(2026, 11, 20, 20)), 'noche');
    });
  });

  group('the rows the plugin replaces', () {
    final mixes = KostvDailyMixes(
      mixes: [
        KostvDailyMix(id: 'daily-1', items: [_song('1')]),
      ],
    );
    const ready = KostvMusicMoment(slot: 'tarde', ready: true);

    test('without the plugin\'s answer, the page is as before', () {
      final rows = kostvMusicPluginRows();
      expect(rows.dailyMixes, isFalse);
      expect(rows.discovery, isFalse);
      expect(rows.moment, isFalse);
    });

    test('an answer with nothing in it doesn\'t replace anything', () {
      final rows = kostvMusicPluginRows(
        mixes: const KostvDailyMixes(),
        discovery: const [],
        moment: ready,
      );
      expect(rows.dailyMixes, isFalse);
      expect(rows.discovery, isFalse);
      // Ready but without songs: not shown.
      expect(rows.moment, isFalse);
    });

    test('with the plugin\'s answer, its rows show', () {
      final rows = kostvMusicPluginRows(
        mixes: mixes,
        discovery: [_stremfin('1')],
        moment: KostvMusicMoment(
          slot: 'tarde',
          ready: true,
          items: [_song('1')],
        ),
      );
      expect(rows.dailyMixes, isTrue);
      expect(rows.discovery, isTrue);
      expect(rows.moment, isTrue);
    });
  });

  group('the week\'s pick', () {
    final songs = [for (var i = 0; i < 60; i++) _stremfin('s$i')];

    test('20, the same for the same person and week, whatever the order '
        'they came in', () {
      final pick = kostvWeeklyPick(songs, user: 'ana', week: '2026-W47');
      expect(pick, hasLength(20));
      final again = kostvWeeklyPick(
        songs.reversed.toList(),
        user: 'ana',
        week: '2026-W47',
      );
      expect(
        [for (final s in again) s.deezerId],
        [for (final s in pick) s.deezerId],
      );
    });

    test('another week or another person, other songs', () {
      String ids(List<StremfinSong> pick) =>
          [for (final s in pick) s.deezerId].join(',');
      final week = kostvWeeklyPick(songs, user: 'ana', week: '2026-W47');
      final next = kostvWeeklyPick(songs, user: 'ana', week: '2026-W48');
      final other = kostvWeeklyPick(songs, user: 'luis', week: '2026-W47');
      expect(ids(next), isNot(ids(week)));
      expect(ids(other), isNot(ids(week)));
    });

    test('each song once, and fewer when there are fewer', () {
      final pick = kostvWeeklyPick(
        [_stremfin('a'), _stremfin('a'), _stremfin('b')],
        user: 'ana',
        week: '2026-W47',
      );
      expect({for (final s in pick) s.deezerId}, {'a', 'b'});
      expect(pick, hasLength(2));
    });

    test('the hash is FNV-1a, the same on every platform', () {
      expect(kostvStableHash(''), 0x811c9dc5);
      expect(kostvStableHash('a'), 0xe40c292c);
      expect(kostvStableHash('foobar'), 0xbf9cf968);
    });

    test('the ISO week', () {
      expect(kostvIsoWeek(DateTime(2026, 11, 20)), '2026-W47');
      expect(kostvIsoWeek(DateTime(2021, 1, 3)), '2020-W53');
      expect(kostvIsoWeek(DateTime(2024, 12, 30)), '2025-W01');
    });
  });

  group('where the music comes from', () {
    test('sends the source with the songs, after returning, songs only and '
        '200 at most', () async {
      final routes = _Plugin(
        answers: {'POST /Moonfin/Kostv/Music/Context': null},
      );
      KostvMusicPlugin.instance = pluginWith(routes);
      kostvTellMusicSource(() => client, KostvMusicSource.mix('daily-2'), [
        _song('video', type: 'Movie'),
        for (var i = 0; i < 250; i++) _song('s$i'),
      ]);
      // Nothing yet: it starts once the caller went on.
      expect(routes.asked, isEmpty);
      await pumpEventQueue();
      final body = routes.asked.single.body as Map;
      expect(routes.asked.single.path, '/Moonfin/Kostv/Music/Context');
      expect(body['Source'], 'mix:daily-2');
      expect(body['ItemIds'], hasLength(200));
      expect((body['ItemIds'] as List).first, 's0');
    });

    test('an older plugin doesn\'t stop anything', () async {
      final routes = _Plugin(hasRoutes: false);
      KostvMusicPlugin.instance = pluginWith(routes);
      kostvTellMusicSource(() => client, KostvMusicSource.search, [_song('1')]);
      await pumpEventQueue();
      expect(routes.asked, hasLength(1));
      expect(KostvMusicPlugin.instance.knownMissing(client, 'Context'), isTrue);
    });

    testWidgets('playing music tells its source without waiting for the '
        'plugin', (tester) async {
      // A plugin that never answers.
      final never = Completer<void>();
      final routes = _Plugin(
        answers: {'POST /Moonfin/Kostv/Music/Context': null},
      );
      final player = _Player();
      GetIt.instance
        ..registerSingleton<MediaServerClient>(client)
        ..registerSingleton<PlaybackManager>(player);
      KostvMusicPlugin.instance = KostvMusicPlugin(
        dio: Dio()..httpClientAdapter = _Hanging(routes, never.future),
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      unawaited(
        playMusicTracks(context, [
          _song('1'),
          _song('2'),
        ], source: KostvMusicSource.favorites),
      );
      // Playing started at once, before the plugin was even asked.
      expect(player.played.single, hasLength(2));
      expect(routes.asked, isEmpty);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(routes.asked.single.body, {
        'Source': 'favorites',
        'ItemIds': ['1', '2'],
      });
      never.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    });
  });
}

/// The plugin, answering only once [until] completes.
class _Hanging implements HttpClientAdapter {
  _Hanging(this.inner, this.until);

  final _Plugin inner;
  final Future<void> until;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final answer = inner.fetch(options, requestStream, cancelFuture);
    await until;
    return answer;
  }

  @override
  void close({bool force = false}) {}
}
