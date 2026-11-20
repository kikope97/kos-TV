import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/stremfin/kostv_age_gate.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/music/kostv_music_actions.dart';
import 'package:moonfin/ui/screens/music/kostv_music_widgets.dart';
import 'package:moonfin/ui/widgets/add_to_playlist_dialog.dart';
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
    this.onAsk,
  });

  final bool hasRoutes;

  /// Called with each `METHOD /path` before it is answered.
  final void Function(String key)? onAsk;

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
    onAsk?.call(key);
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

typedef _RadioAsk = ({
  List<String> artists,
  String? only,
  bool excludeSeedArtists,
  int? limit,
});

T? _value<T extends Object>(KostvMusicAnswer<T> answer) => answer.value;

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
      final state = await plugin.settings(client).then(_value);
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
      expect(await plugin.settings(client).then(_value), isNull);
      expect(plugin.knownMissing(client, 'Settings'), isTrue);
      expect(await plugin.settings(client).then(_value), isNull);
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
      expect(await plugin.settings(client).then(_value), isNull);
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
      ).mixes(client).then(_value);
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
      expect(
        await pluginWith(_Plugin(hasRoutes: false)).mixes(client).then(_value),
        isNull,
      );
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
      ).discovery(client).then(_value);
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
      ).discovery(client).then(_value);
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
        await pluginWith(_Plugin(hasRoutes: false))
            .discovery(client)
            .then(_value),
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
      ).moment(client).then(_value);
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
      ).moment(client).then(_value);
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
        '500 at most (the plugin\'s own limit)', () async {
      final routes = _Plugin(
        answers: {'POST /Moonfin/Kostv/Music/Context': null},
      );
      KostvMusicPlugin.instance = pluginWith(routes);
      kostvTellMusicSource(() => client, KostvMusicSource.mix('daily-2'), [
        _song('video', type: 'Movie'),
        for (var i = 0; i < 600; i++) _song('s$i'),
      ]);
      // Nothing yet: it starts once the caller went on.
      expect(routes.asked, isEmpty);
      await pumpEventQueue();
      final body = routes.asked.single.body as Map;
      expect(routes.asked.single.path, '/Moonfin/Kostv/Music/Context');
      expect(body['Source'], 'mix:daily-2');
      expect(body['ItemIds'], hasLength(500));
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

  group('missing or failed', () {
    test('a 404 is «not there», remembered; a 500 or 401 is a failure, '
        'asked again next time', () async {
      final missing = pluginWith(_Plugin(hasRoutes: false));
      final gone = await missing.mixes(client);
      expect(gone.missing, isTrue);
      expect(gone.failed, isFalse);

      for (final status in [401, 500, 503]) {
        final routes = _Plugin(
          answers: {
            'GET /Moonfin/Kostv/Music/Mixes': {'Error': 'No.'},
            'GET /Moonfin/Kostv/Music/Settings': {'Error': 'No.'},
          },
          statuses: {
            'GET /Moonfin/Kostv/Music/Mixes': status,
            'GET /Moonfin/Kostv/Music/Settings': status,
          },
        );
        final plugin = pluginWith(routes);
        final mixes = await plugin.mixes(client);
        expect(mixes.failed, isTrue, reason: '$status');
        expect(mixes.missing, isFalse);
        expect(plugin.knownMissing(client, 'Mixes'), isFalse);
        expect((await plugin.settings(client)).failed, isTrue);
        // Not remembered: asked again.
        await plugin.mixes(client);
        expect(
          routes.asked.where((a) => a.path.endsWith('/Mixes')),
          hasLength(2),
        );
      }
    });

    test('no network, or an answer that isn\'t one, is a failure', () async {
      final offline = KostvMusicPlugin(dio: Dio()..httpClientAdapter = _Down());
      expect((await offline.moment(client)).failed, isTrue);
      expect((await offline.discovery(client)).failed, isTrue);
      expect(offline.knownMissing(client, 'Moment'), isFalse);

      final garbled = pluginWith(
        _Plugin(answers: {'GET /Moonfin/Kostv/Music/Mixes': 'hola'}),
      );
      expect((await garbled.mixes(client)).failed, isTrue);
    });
  });

  group('what is kept on the device', () {
    test('the week\'s discovery only shows in its week', () {
      final note = kostvDiscoveryNote('2026-W47', [_stremfin('1')]);
      final kept = jsonDecode(jsonEncode(note));
      expect(
        kostvKeptDiscovery(kept, now: DateTime(2026, 11, 20))!.single.deezerId,
        '1',
      );
      // The next Monday: last week's isn't this one.
      expect(kostvKeptDiscovery(kept, now: DateTime(2026, 11, 23)), isNull);
      // Kept before the week went with it: not shown.
      expect(
        kostvKeptDiscovery([
          kostvStremfinSongJson(_stremfin('1')),
        ], now: DateTime(2026, 11, 20)),
        isNull,
      );
    });

    test('the daily mixes only show on their day, which starts at 5:00', () {
      final mixes = KostvDailyMixes(
        day: '2026-11-20',
        mixes: [
          KostvDailyMix(id: 'daily-1', items: [_song('1')]),
        ],
      );
      final kept = jsonDecode(jsonEncode(mixes.toJson()));
      KostvDailyMixes? at(DateTime now) =>
          kostvKeptMixes(kept, 'https://casa.example', now: now);
      expect(at(DateTime(2026, 11, 20, 18)), isNotNull);
      // Past midnight, before 5:00: still that day's.
      expect(at(DateTime(2026, 11, 21, 4, 30)), isNotNull);
      expect(at(DateTime(2026, 11, 21, 5, 30)), isNull);
      expect(kostvMusicDayAt(DateTime(2026, 11, 21, 4)), '2026-11-20');
    });

    test('a discovery song keeps its album\'s request through the plugin', () {
      final album = StremfinAlbum.fromJson({
        'title': 'Motomami',
        'deezer_id': '777',
        'library': {'in_jellyfin': false},
        'request': {'id': 4, 'status': 'pending', 'mine': true},
        'can_request': false,
      })!;
      final songs = kostvSongsWithAlbums(
        [
          StremfinSong(
            title: 'Despechá',
            deezerId: '123',
            albumTitle: 'Motomami',
            albumDeezerId: '777',
          ),
          _stremfin('2'),
        ],
        [album],
      );
      expect(songs.first.album, same(album));
      expect(songs.last.album, isNull);
      final back = StremfinSong.fromJson(
        jsonDecode(jsonEncode(kostvStremfinSongJson(songs.first))),
      )!;
      expect(back.album!.request!.status, 'pending');
      expect(back.album!.canRequest, isFalse);
      expect(back.albumDeezerId, '777');
      // Twenty of them stay far below what the plugin takes (64 KB).
      final body = jsonEncode([
        for (var i = 0; i < 20; i++) kostvStremfinSongJson(songs.first),
      ]);
      expect(body.length, lessThan(64 * 1024));
    });
  });

  group('the week\'s discovery, loaded', () {
    const discovery = 'GET /Moonfin/Kostv/Music/Discovery';
    const keep = 'PUT /Moonfin/Kostv/Music/Discovery';
    final firstTime = {
      'Week': '2026-W47',
      'Seeds': ['Bad Bunny'],
      'Songs': null,
    };
    final recommended = StremfinRecommendations(
      songs: [for (var i = 0; i < 30; i++) _stremfin('r$i')],
    );

    test('the first time, picked and kept for the week', () async {
      final routes = _Plugin(answers: {discovery: firstTime, keep: null});
      final found = await kostvLoadWeeklyDiscovery(
        pluginWith(routes),
        client,
        recommend: (_) async => recommended,
      );
      expect(found!.week, '2026-W47');
      expect(found.songs, hasLength(20));
      final put = routes.asked.singleWhere((a) => a.method == 'PUT');
      expect((put.body as Map)['Songs'], hasLength(20));
    });

    test('another device kept the week\'s while this one picked: theirs, '
        'without keeping its own', () async {
      final answers = <String, Object?>{discovery: firstTime, keep: null};
      var reads = 0;
      final routes = _Plugin(
        answers: answers,
        onAsk: (key) {
          if (key != discovery) return;
          // From the second read on, the other device's list is there.
          if (++reads == 2) {
            answers[discovery] = {
              'Week': '2026-W47',
              'Seeds': ['Bad Bunny'],
              'Songs': [kostvStremfinSongJson(_stremfin('theirs'))],
            };
          }
        },
      );
      final found = await kostvLoadWeeklyDiscovery(
        pluginWith(routes),
        client,
        recommend: (_) async => recommended,
      );
      expect(found!.songs!.single.deezerId, 'theirs');
      expect(routes.asked.where((a) => a.method == 'PUT'), isEmpty);
    });

    test('a switch of person while it worked: nothing kept with the other '
        'session, nothing given', () async {
      final routes = _Plugin(answers: {discovery: firstTime, keep: null});
      final found = await kostvLoadWeeklyDiscovery(
        pluginWith(routes),
        client,
        recommend: (_) async {
          // Bruno takes over the same server's client meanwhile.
          client
            ..userId = 'bruno'
            ..accessToken = 'token-bruno';
          return recommended;
        },
      );
      expect(found, isNull);
      expect(routes.asked.where((a) => a.method == 'PUT'), isEmpty);
    });

    test('the page gone: it stops after the wait it was in', () async {
      var open = true;
      final routes = _Plugin(answers: {discovery: firstTime, keep: null});
      final found = await kostvLoadWeeklyDiscovery(
        pluginWith(routes),
        client,
        wanted: () => open,
        recommend: (_) async {
          open = false;
          return recommended;
        },
      );
      expect(found, isNull);
      expect(routes.asked.where((a) => a.method == 'PUT'), isEmpty);
    });

    test('the plugin failing throws (what is shown stays); without the route '
        'there are no songs', () async {
      final failing = pluginWith(
        _Plugin(answers: {discovery: firstTime}, statuses: {discovery: 500}),
      );
      await expectLater(
        kostvLoadWeeklyDiscovery(
          failing,
          client,
          recommend: (_) async => recommended,
        ),
        throwsA(isA<KostvMusicUnanswered>()),
      );
      final older = await kostvLoadWeeklyDiscovery(
        pluginWith(_Plugin(hasRoutes: false)),
        client,
        recommend: (_) async => recommended,
      );
      expect(older!.songs, isNull);
    });

    test('songs already at home aren\'t picked', () {
      final pick = kostvWeeklyPick(
        [
          _stremfin('new'),
          const StremfinSong(title: 'Casa', deezerId: 'home', inJellyfin: true),
          const StremfinSong(title: 'Casa 2', deezerId: 'id', jellyfinId: 'j1'),
        ],
        user: 'ana',
        week: '2026-W47',
      );
      expect([for (final s in pick) s.deezerId], ['new']);
    });

    // Kos TV: Stremfin 1.93's radio for the week's discovery.
    Map<String, Object?> radioAlbum(
      String id, {
      Map<String, Object?>? request,
      Map<String, Object?>? download,
      bool canRequest = true,
    }) => {
      'type': 'music',
      'deezer_id': id,
      'title': 'Un disco con un título bastante largo $id',
      'artist': 'Artista con nombre largo y colaboradores',
      'cover': 'https://e-cdns-images.dzcdn.net/images/cover/0123456789abcdef0123456789abcdef/500x500-000000-80-0-0.jpg',
      'tracks': null,
      'kind': 'album',
      'release_date': '2025-05-10',
      'rank': null,
      'library': {
        'in_jellyfin': false,
        'song_in_album': null,
        'requested_recently': false,
        'jellyfin_id': null,
      },
      'download': download,
      'contains': 'La canción $id',
      'request': request,
      'can_request': canRequest,
    };
    StremfinSong radioSong(
      String id, {
      Map<String, Object?>? album,
      bool explicit = false,
      bool atHome = false,
    }) => StremfinSong.fromJson({
      'deezer_id': id,
      'title': 'La canción $id',
      'artist': 'Artista con nombre largo y colaboradores',
      'artist_deezer_id': '27',
      'duration': 224,
      'preview': 'https://cdnt-preview.dzcdn.net/api/1/1/a/b/c/0/abcdef0123456789abcdef0123456789.mp3?hdnea=exp=1763650000~acl=/api/1/1/a/b/c/0/abcdef*~data=user_id=0,application_id=42~hmac=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      'explicit': explicit,
      'album': album ?? radioAlbum('a$id'),
      'in_jellyfin': atHome,
      'in_album': null,
      'jellyfin_id': atHome ? 'j$id' : null,
      'album_jellyfin_id': null,
      'reason': 'Porque escuchas a Bad Bunny y Rosalía',
      'because': ['Bad Bunny', 'Rosalía'],
    })!;

    test('the radio first: only what the house hasn\'t, without the seeds\' '
        'own artists, up to 50; enough of it, no recommendations', () async {
      final routes = _Plugin(answers: {discovery: firstTime, keep: null});
      final asks = <_RadioAsk>[];
      var recommendedAsked = 0;
      final found = await kostvLoadWeeklyDiscovery(
        pluginWith(routes),
        client,
        recommend: (_) async {
          recommendedAsked++;
          return recommended;
        },
        radio:
            (
              artists, {
              String? only,
              bool excludeSeedArtists = false,
              int? limit,
            }) async {
              asks.add((
                artists: artists,
                only: only,
                excludeSeedArtists: excludeSeedArtists,
                limit: limit,
              ));
              return StremfinRadio(
                songs: [for (var i = 0; i < 30; i++) radioSong('radio$i')],
              );
            },
      );
      final ask = asks.single;
      expect(ask.artists, ['Bad Bunny']);
      expect(ask.only, 'missing');
      expect(ask.excludeSeedArtists, isTrue);
      expect(ask.limit, 50);
      expect(recommendedAsked, 0);
      expect(found!.songs, hasLength(20));
      expect(found.songs!.every((s) => s.deezerId!.startsWith('radio')), true);
      // The same 20 on every device of the person, this week.
      final again = kostvWeeklyPick(
        [for (var i = 0; i < 30; i++) radioSong('radio$i')],
        user: client.userId!,
        week: '2026-W47',
      );
      expect(
        [for (final s in found.songs!) s.deezerId],
        [for (final s in again) s.deezerId],
      );
    });

    test('fewer than 20 from the radio: topped up from the recommendations, '
        'without the same song twice', () async {
      final routes = _Plugin(answers: {discovery: firstTime, keep: null});
      final found = await kostvLoadWeeklyDiscovery(
        pluginWith(routes),
        client,
        recommend: (_) async => StremfinRecommendations(
          songs: [
            // Also in the radio: not twice.
            for (var i = 0; i < 8; i++) _stremfin('radio$i'),
            for (var i = 0; i < 30; i++) _stremfin('r$i'),
          ],
        ),
        radio:
            (
              artists, {
              String? only,
              bool excludeSeedArtists = false,
              int? limit,
            }) async => StremfinRadio(
              songs: [
                for (var i = 0; i < 8; i++) radioSong('radio$i'),
                // At home: not usable.
                radioSong('home', atHome: true),
              ],
            ),
      );
      final songs = found!.songs!;
      expect(songs, hasLength(20));
      final ids = [for (final s in songs) s.deezerId];
      expect(ids.toSet(), hasLength(20));
      expect(ids.take(8).every((id) => id!.startsWith('radio')), isTrue);
      expect(
        ids
            .skip(8)
            .every((id) => id!.startsWith('r') && !id.startsWith('radio')),
        isTrue,
      );
      expect(ids, isNot(contains('home')));
      // The radio's keep their whole album.
      expect(songs.first.album, isNotNull);
    });

    test('a service from before the radio (404): the recommendations, as '
        'before it', () async {
      Future<KostvWeekDiscovery?> load({bool withRadio = true}) =>
          kostvLoadWeeklyDiscovery(
            pluginWith(_Plugin(answers: {discovery: firstTime, keep: null})),
            client,
            recommend: (_) async => recommended,
            radio: withRadio
                ? (
                    artists, {
                    String? only,
                    bool excludeSeedArtists = false,
                    int? limit,
                  }) async => throw const StremfinException(
                    code: 'not_found',
                    status: 404,
                  )
                : null,
          );
      final older = await load();
      final before = await load(withRadio: false);
      expect(older!.songs, hasLength(20));
      expect(
        [for (final s in older.songs!) s.deezerId],
        [for (final s in before!.songs!) s.deezerId],
      );
    });

    for (final status in [503, 429, 500]) {
      test('the radio failing ($status): thrown, nothing kept, not the '
          'recommendations instead', () async {
        final routes = _Plugin(answers: {discovery: firstTime, keep: null});
        var recommendedAsked = 0;
        await expectLater(
          kostvLoadWeeklyDiscovery(
            pluginWith(routes),
            client,
            recommend: (_) async {
              recommendedAsked++;
              return recommended;
            },
            radio:
                (
                  artists, {
                  String? only,
                  bool excludeSeedArtists = false,
                  int? limit,
                }) async => throw StremfinException(
                  code: 'source_unavailable',
                  status: status,
                ),
          ),
          throwsA(isA<StremfinException>()),
        );
        expect(recommendedAsked, 0);
        expect(routes.asked.where((a) => a.method == 'PUT'), isEmpty);
      });
    }

    test('twenty of the radio\'s songs with their albums fit the plugin '
        '(64 KB), and keep their marks and explicit', () async {
      final routes = _Plugin(answers: {discovery: firstTime, keep: null});
      final radio = [
        for (var i = 0; i < 40; i++)
          radioSong(
            '$i',
            explicit: i.isOdd,
            album: radioAlbum(
              'a$i',
              request: i % 3 == 0
                  ? {
                      'id': 100 + i,
                      'status': 'approved',
                      'status_label': 'Aceptada',
                      'mine': true,
                      'requesters': ['Kiko', 'Ana'],
                    }
                  : null,
              download: i % 3 == 1
                  ? {
                      'phase': 'downloading',
                      'label': 'Descargando',
                      'percent': 42,
                      'track_errors': false,
                      'sent_at': '2026-11-11T10:02:00+01:00',
                      'arrived_at': null,
                    }
                  : null,
              canRequest: i % 3 == 2,
            ),
          ),
      ];
      final found = await kostvLoadWeeklyDiscovery(
        pluginWith(routes),
        client,
        recommend: (_) async => recommended,
        radio: (
          artists, {
          String? only,
          bool excludeSeedArtists = false,
          int? limit,
        }) async => StremfinRadio(songs: radio),
      );
      expect(found!.songs, hasLength(20));
      final put = routes.asked.singleWhere((a) => a.method == 'PUT');
      expect(utf8.encode(jsonEncode(put.body)).length, lessThan(64 * 1024));
      final kept = KostvMusicDiscovery.fromJson(put.body)!.songs!;
      expect(kept, hasLength(20));
      for (final song in kept) {
        final i = int.parse(song.deezerId!);
        expect(song.explicit, i.isOdd);
        expect(kostvMusicBadgeOf(song.album!), switch (i % 3) {
          0 => KostvMusicBadge.asked,
          1 => KostvMusicBadge.onItsWay,
          _ => KostvMusicBadge.ask,
        });
      }
    });

    test('someone with a limit: the explicit ones out before the pick, and '
        'out of a list the plugin kept', () async {
      List<StremfinSong> clean(List<StremfinSong> songs) =>
          kostvCleanMusicSongs(songs, hideExplicit: true);
      final routes = _Plugin(answers: {discovery: firstTime, keep: null});
      final found = await kostvLoadWeeklyDiscovery(
        pluginWith(routes),
        client,
        recommend: (_) async => StremfinRecommendations(
          songs: [
            for (var i = 0; i < 30; i++)
              StremfinSong(title: 'R $i', deezerId: 'r$i', explicit: i.isEven),
          ],
        ),
        radio:
            (
              artists, {
              String? only,
              bool excludeSeedArtists = false,
              int? limit,
            }) async => StremfinRadio(
              songs: [
                for (var i = 0; i < 30; i++)
                  radioSong('radio$i', explicit: i.isEven),
              ],
            ),
        clean: clean,
      );
      expect(found!.songs, hasLength(20));
      expect(found.songs!.any((s) => s.explicit), isFalse);
      final put = routes.asked.singleWhere((a) => a.method == 'PUT');
      expect(
        KostvMusicDiscovery.fromJson(put.body)!.songs!.any((s) => s.explicit),
        isFalse,
      );
      // Another device (an adult's phone) kept one with explicit songs.
      final theirs = await kostvLoadWeeklyDiscovery(
        pluginWith(
          _Plugin(
            answers: {
              discovery: {
                'Week': '2026-W47',
                'Seeds': ['Bad Bunny'],
                'Songs': [
                  kostvStremfinSongJson(radioSong('e', explicit: true)),
                  kostvStremfinSongJson(radioSong('c')),
                ],
              },
            },
          ),
        ),
        client,
        recommend: (_) async => recommended,
        clean: clean,
      );
      expect([for (final s in theirs!.songs!) s.deezerId], ['c']);
    });
  });

  group('where the music comes from, from the song pressed', () {
    test(
      'the songs from the one pressed on first, then those before it',
      () async {
        final routes = _Plugin(
          answers: {'POST /Moonfin/Kostv/Music/Context': null},
        );
        KostvMusicPlugin.instance = pluginWith(routes);
        kostvTellMusicSource(() => client, KostvMusicSource.favorites, [
          for (var i = 0; i < 700; i++) _song('s$i'),
        ], startIndex: 250);
        await pumpEventQueue();
        final ids = (routes.asked.single.body as Map)['ItemIds'] as List;
        expect(ids, hasLength(500));
        expect(ids.first, 's250');
        expect(ids, contains('s699'));
        // Then from the start, as many as still fit.
        expect(ids[450], 's0');
        expect(ids.last, 's49');
        expect(ids, isNot(contains('s50')));
      },
    );
  });

  group('what the person does (Event)', () {
    const event = 'POST /Moonfin/Kostv/Music/Event';

    test('songs added to a playlist, after returning', () async {
      final routes = _Plugin(answers: {event: null});
      KostvMusicPlugin.instance = pluginWith(routes);
      kostvTellPlaylistAdd(() => client, (_) async => ['1', '', '2', '1']);
      expect(routes.asked, isEmpty);
      await pumpEventQueue();
      expect(routes.asked.single.path, '/Moonfin/Kostv/Music/Event');
      expect(routes.asked.single.body, {
        'Type': 'playlist_add',
        'ItemIds': ['1', '2'],
      });
    });

    test('an album asked for from the requests service', () async {
      final routes = _Plugin(answers: {event: null});
      KostvMusicPlugin.instance = pluginWith(routes);
      kostvTellMusicRequest(
        () => client,
        deezerAlbumId: '302127',
        album: 'Discovery',
        artist: 'Daft Punk',
      );
      expect(routes.asked, isEmpty);
      await pumpEventQueue();
      expect(routes.asked.single.body, {
        'Type': 'request',
        'Album': 'Discovery',
        'Artist': 'Daft Punk',
        'DeezerAlbumId': '302127',
      });
    });

    test('an album without an artist known goes without it', () async {
      final routes = _Plugin(answers: {event: null});
      KostvMusicPlugin.instance = pluginWith(routes);
      kostvTellMusicRequest(
        () => client,
        deezerAlbumId: '1',
        album: 'Sin título',
      );
      await pumpEventQueue();
      expect(routes.asked.single.body, {
        'Type': 'request',
        'Album': 'Sin título',
        'DeezerAlbumId': '1',
      });
    });

    test('only an album that was asked for tells it', () {
      for (final outcome in StremfinOutcome.values) {
        expect(
          kostvMusicRequestCounts(outcome),
          !const {
            StremfinOutcome.limit,
            StremfinOutcome.unavailable,
            StremfinOutcome.have,
          }.contains(outcome),
          reason: outcome.name,
        );
      }
    });

    test('dislike, for when there is a button', () async {
      final routes = _Plugin(answers: {event: null});
      final plugin = pluginWith(routes);
      await plugin.sendDislike(client, ['9']);
      expect(routes.asked.single.body, {
        'Type': 'dislike',
        'ItemIds': ['9'],
      });
    });

    test('an older plugin (404): nothing breaks, and an album\'s songs '
        'aren\'t even asked for afterwards', () async {
      final routes = _Plugin(hasRoutes: false);
      KostvMusicPlugin.instance = pluginWith(routes);
      kostvTellPlaylistAdd(() => client, (_) async => ['1']);
      await pumpEventQueue();
      expect(routes.asked, hasLength(1));
      expect(KostvMusicPlugin.instance.knownMissing(client, 'Event'), isTrue);

      var asked = false;
      kostvTellPlaylistAdd(() => client, (_) async {
        asked = true;
        return ['2'];
      });
      kostvTellMusicRequest(() => client, deezerAlbumId: '3');
      await pumpEventQueue();
      expect(asked, isFalse);
      expect(routes.asked, hasLength(1));
    });

    test('a failure, or no server, reaches nobody', () async {
      KostvMusicPlugin.instance = KostvMusicPlugin(
        dio: Dio()..httpClientAdapter = _Down(),
      );
      kostvTellPlaylistAdd(() => client, (_) async => ['1']);
      kostvTellPlaylistAdd(() => client, (_) async => throw StateError('x'));
      kostvTellPlaylistAdd(() => throw StateError('no server'), (_) async {
        return ['1'];
      });
      kostvTellMusicRequest(() => null, deezerAlbumId: '1');
      await pumpEventQueue();
    });

    test('the songs of what is added', () async {
      final home = _Home();
      final server = JellyfinMediaServerClient(
        baseUrl: 'https://casa.example',
        deviceInfo: _device,
        interceptors: [home],
      )..userId = 'ana';
      expect(await kostvPlaylistSongsOf(_song('1'))!(server), ['1']);
      final album = _song('album', type: 'MusicAlbum');
      expect(
        await kostvPlaylistSongsOf(
          album,
          tracks: [
            _song('a'),
            _song('b'),
            _song('v', type: 'Video'),
          ],
        )!(server),
        ['a', 'b'],
      );
      expect(home.asked, isEmpty);
      // Without its songs at hand, they are asked for (only then).
      expect(await kostvPlaylistSongsOf(album)!(server), ['t1', 't2']);
      expect(home.asked.single.queryParameters['ParentId'], 'album');
      expect(kostvPlaylistSongsOf(_song('film', type: 'Movie')), isNull);
      expect(kostvPlaylistSongsOf(_song('ar', type: 'MusicArtist')), isNull);
    });

    Future<BuildContext> dialogHost(WidgetTester tester) async {
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
      return context;
    }

    testWidgets('adding a song to a playlist tells it, without waiting for '
        'the plugin', (tester) async {
      final home = _Home();
      final server =
          JellyfinMediaServerClient(
              baseUrl: 'https://casa.example',
              deviceInfo: _device,
              interceptors: [home],
            )
            ..accessToken = 'token'
            ..userId = 'ana';
      final never = Completer<void>();
      final routes = _Plugin(answers: {event: null});
      KostvMusicPlugin.instance = KostvMusicPlugin(
        dio: Dio()..httpClientAdapter = _Hanging(routes, never.future),
      );
      GetIt.instance
        ..registerSingleton<MediaServerClient>(server)
        ..registerSingleton<MediaServerClientFactory>(_Factory());
      final context = await dialogHost(tester);
      final song = _song('1');
      bool? added;
      unawaited(
        AddToPlaylistDialog.show(
          context,
          itemIds: [song.id],
          serverId: song.serverId,
          songs: kostvPlaylistSongsOf(song),
        ).then((value) => added = value),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi lista'));
      await tester.pumpAndSettle();
      // Added and closed, while the plugin hasn't answered.
      expect(added, isTrue);
      expect(home.asked.map((r) => '${r.method} ${r.path}'), [
        'GET /Users/ana/Items',
        'POST /Playlists/list/Items',
      ]);
      expect(routes.asked.single.body, {
        'Type': 'playlist_add',
        'ItemIds': ['1'],
      });
      never.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    });

    testWidgets('adding a film tells nothing', (tester) async {
      final home = _Home();
      final server =
          JellyfinMediaServerClient(
              baseUrl: 'https://casa.example',
              deviceInfo: _device,
              interceptors: [home],
            )
            ..accessToken = 'token'
            ..userId = 'ana';
      final routes = _Plugin(answers: {event: null});
      KostvMusicPlugin.instance = pluginWith(routes);
      GetIt.instance
        ..registerSingleton<MediaServerClient>(server)
        ..registerSingleton<MediaServerClientFactory>(_Factory());
      final context = await dialogHost(tester);
      final film = _song('film', type: 'Movie');
      unawaited(
        AddToPlaylistDialog.show(
          context,
          itemIds: [film.id],
          serverId: film.serverId,
          songs: kostvPlaylistSongsOf(film),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi lista'));
      await tester.pumpAndSettle();
      expect(home.asked.last.path, '/Playlists/list/Items');
      expect(routes.asked, isEmpty);
    });
  });
}

/// The home server's playlists, and an album's songs, answered without a
/// network; notes what it was asked.
class _Home extends Interceptor {
  final asked = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    asked.add(options);
    final types = options.queryParameters['IncludeItemTypes']?.toString();
    final Object? data = switch ((options.method, types)) {
      ('GET', 'Playlist') => {
        'Items': [
          {'Id': 'list', 'Name': 'Mi lista', 'Type': 'Playlist'},
        ],
      },
      ('GET', 'Audio') => {
        'Items': [
          {'Id': 't1', 'Type': 'Audio'},
          {'Id': 't2', 'Type': 'Audio'},
        ],
      },
      _ => null,
    };
    handler.resolve(
      Response(requestOptions: options, statusCode: 200, data: data ?? ''),
    );
  }
}

class _Factory extends Fake implements MediaServerClientFactory {
  @override
  MediaServerClient? getClientIfExists(String serverId) => null;
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

/// No network at all.
class _Down implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: 'offline',
  );

  @override
  void close({bool force = false}) {}
}
