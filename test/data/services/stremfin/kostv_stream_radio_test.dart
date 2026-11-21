import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_dislikes.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_radio.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/ui/widgets/music/kostv_stream_play.dart'
    show kostvMomentDay, kostvSongsToPlay, kostvToday;
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

const _server = 'https://casa.example';

AggregatedItem _home(String id, String artist, {String? name}) =>
    AggregatedItem(
      id: id,
      serverId: _server,
      rawData: {
        'Id': id,
        'Name': name ?? 'Canción $id',
        'Type': 'Audio',
        'Artists': [artist],
        'ArtistItems': [
          {'Id': 'id-$artist', 'Name': artist},
        ],
      },
    );

AggregatedItem _away(String deezerId, String artist, {String? name}) =>
    kostvStreamItem(
      deezerId: deezerId,
      title: name ?? 'Fuera $deezerId',
      serverId: _server,
      artist: artist,
      albumDeezerId: 'al$deezerId',
    );

StremfinSong _song(
  String deezerId,
  String artist, {
  String? jellyfinId,
  bool explicit = false,
  String? title,
}) => StremfinSong(
  title: title ?? 'Radio $deezerId',
  deezerId: deezerId,
  artist: artist,
  artistDeezerId: 'ar-$artist',
  explicit: explicit,
  jellyfinId: jellyfinId,
  inJellyfin: jellyfinId != null,
  albumDeezerId: 'al$deezerId',
);

List<String> _artists(List<AggregatedItem> items) => [
  for (final item in items) kostvSongArtistKey(item),
];

bool _noTwoInARow(List<AggregatedItem> items) {
  final artists = _artists(items);
  for (var i = 1; i < artists.length; i++) {
    if (artists[i] == artists[i - 1]) return false;
  }
  return true;
}

/// A radio that answers [songs] (or fails with [error]) and counts calls.
class _Radio {
  _Radio([this.songs = const []]);

  List<StremfinSong> songs;
  Object? error;
  final asked = <({List<String> artists, List<String> ids, String? only})>[];

  Future<StremfinRadio> call(
    List<String> artists, {
    List<String> artistIds = const [],
    String? only,
    int? limit,
  }) async {
    asked.add((artists: artists, ids: artistIds, only: only));
    if (error case final e?) throw e;
    return StremfinRadio(songs: songs);
  }
}

final _mix9 = [
  for (var i = 0; i < 9; i++) _home('h$i', i.isEven ? 'Lola' : 'Nube'),
];

void main() {
  group('mixing what is at home with what is not', () {
    test('takes them in turns, each once, never the same artist twice', () {
      final home = [
        _home('h1', 'Lola'),
        _home('h2', 'Lola'),
        _home('h3', 'Nube'),
      ];
      final away = [
        _away('1', 'Rayo'),
        _away('2', 'Lola'),
        _away('3', 'Rayo'),
        // The same song as one at home: once.
        _away('4', 'Nube', name: 'Canción h3'),
      ];
      final mixed = kostvInterleaveRadio(home, away);
      expect(mixed.map((e) => e.id), [
        'h1',
        'stremfin:1',
        'h2',
        // Not «Lola» right after «Lola»: the next one of Rayo first.
        'stremfin:3',
        'h3',
        'stremfin:2',
      ]);
      expect(_noTwoInARow(mixed), isTrue);
    });

    test('what is in the queue already is skipped', () {
      final mixed = kostvInterleaveRadio(
        [_home('h1', 'Lola'), _home('h2', 'Nube')],
        [_away('1', 'Rayo')],
        skip: {'h1'},
      );
      expect(mixed.map((e) => e.id), ['h2', 'stremfin:1']);
    });

    test('only one artist left: it still goes on', () {
      final mixed = kostvInterleaveRadio([
        _home('h1', 'Lola'),
        _home('h2', 'Lola'),
      ], const []);
      expect(mixed.map((e) => e.id), ['h1', 'h2']);
    });
  });

  group('the daily mix with what is not at home', () {
    test('about a quarter of the whole, at most twelve', () {
      expect(kostvMixExtraCount(0), 0);
      expect(kostvMixExtraCount(2), 1);
      expect(kostvMixExtraCount(9), 3);
      expect(kostvMixExtraCount(30), 10);
      expect(kostvMixExtraCount(60), 12);
    });

    test('spread through it, not at the start, no artist twice in a row', () {
      final base = [
        for (var i = 0; i < 9; i++) _home('h$i', i.isEven ? 'Lola' : 'Nube'),
      ];
      final extras = [_away('1', 'Mar'), _away('2', 'Rayo'), _away('3', 'Sol')];
      final mixed = kostvSpreadExtras(base, extras);
      expect(mixed.length, 12);
      expect(mixed.first.id, 'h0');
      expect(_noTwoInARow(mixed), isTrue);
      // The mix's own order stays.
      expect(
        [
          for (final item in mixed)
            if (!isKostvStream(item)) item.id,
        ],
        [for (final item in base) item.id],
      );
      // Spread: never two extras together.
      for (var i = 1; i < mixed.length; i++) {
        expect(isKostvStream(mixed[i]) && isKostvStream(mixed[i - 1]), isFalse);
      }
    });
  });

  test('moved off its even place to keep an artist apart', () {
    final base = [
      _home('h0', 'A'),
      _home('h1', 'B'),
      _home('h2', 'C'),
      _home('h3', 'A'),
      _home('h4', 'B'),
      _home('h5', 'C'),
    ];
    final mixed = kostvSpreadExtras(base, [_away('1', 'C')]);
    expect(mixed.map((e) => e.id).toList().indexOf('stremfin:1'), 4);
    expect(_noTwoInARow(mixed), isTrue);
  });

  group('the radio, asked once per set of artists', () {
    test('the same artists (in any order or case) are one call', () async {
      final fake = _Radio([_song('1', 'Rayo')]);
      final radio = KostvStreamRadio(fetch: fake.call, who: () => 'ana');
      await radio.songs(artists: ['Lola', 'Nube']);
      await radio.songs(artists: ['nube', 'LOLA']);
      expect(fake.asked, hasLength(1));
      await radio.songs(artists: ['Lola']);
      expect(fake.asked, hasLength(2));
    });

    test('nothing to ask with: no call', () async {
      final fake = _Radio();
      final radio = KostvStreamRadio(fetch: fake.call);
      expect(await radio.songs(artists: [' ']), isEmpty);
      expect(fake.asked, isEmpty);
    });

    test('another person gets their own', () async {
      final fake = _Radio([_song('1', 'Rayo')]);
      var who = 'ana';
      final radio = KostvStreamRadio(fetch: fake.call, who: () => who);
      await radio.songs(artists: ['Lola']);
      who = 'luis';
      await radio.songs(artists: ['Lola']);
      expect(fake.asked, hasLength(2));
    });

    test('after a no (too many asked), it rests a minute', () async {
      final fake = _Radio()
        ..error = const StremfinException(code: 'rate_limited', status: 429);
      var now = DateTime(2026, 11, 21, 10);
      final radio = KostvStreamRadio(fetch: fake.call, clock: () => now);
      await expectLater(radio.songs(artists: ['Lola']), throwsA(anything));
      fake.error = null;
      await expectLater(radio.songs(artists: ['Nube']), throwsA(anything));
      expect(fake.asked, hasLength(1));
      now = now.add(KostvStreamRadio.quiet);
      expect(await radio.songs(artists: ['Nube']), isEmpty);
      expect(fake.asked, hasLength(2));
    });
  });

  group('a station', () {
    Future<List<AggregatedItem>> homeItems(List<String> ids) async => [
      for (final id in ids) _home(id, 'Casa $id'),
    ];

    test(
      'mixes the home server\'s mix with the radio, home ones by id',
      () async {
        final fake = _Radio([
          _song('1', 'Rayo'),
          _song('2', 'Brisa', jellyfinId: 'j2'),
          _song('3', 'Sol'),
        ]);
        final seed = _home('seed', 'Lola');
        final station = await kostvStationOf(
          radio: KostvStreamRadio(fetch: fake.call),
          serverId: _server,
          includeAway: true,
          hideExplicit: false,
          homeItems: homeItems,
          homeMix: () async => [seed, _home('m1', 'Lola'), _home('m2', 'Nube')],
          artists: ['Lola'],
          seed: seed,
        );
        expect(fake.asked.single.only, 'all');
        expect(station.map((e) => e.id), [
          'm1',
          'stremfin:1',
          'm2',
          'stremfin:3',
          'j2',
        ]);
        expect(_noTwoInARow(station), isTrue);
      },
    );

    test('with «Solo la de casa», only what the radio has at home', () async {
      final fake = _Radio([
        _song('1', 'Rayo'),
        _song('2', 'Brisa', jellyfinId: 'j2'),
      ]);
      final station = await kostvStationOf(
        radio: KostvStreamRadio(fetch: fake.call),
        serverId: _server,
        includeAway: false,
        hideExplicit: false,
        homeItems: homeItems,
        artistIds: ['ar1'],
      );
      expect(fake.asked.single.only, 'available');
      expect(fake.asked.single.ids, ['ar1']);
      expect(station.map((e) => e.id), ['j2']);
    });

    test('without what the person said no to, nor explicit for kids', () async {
      final fake = _Radio([
        _song('1', 'Rayo'),
        _song('2', 'Nube Roja'),
        _song('3', 'Sol', explicit: true),
        _song('4', 'Brisa'),
      ]);
      final dislikes = KostvMusicDislikes(
        songs: [
          KostvMusicDisliked(
            id: kostvStreamId('1'),
            deezerId: '1',
            name: 'Radio 1',
          ),
        ],
        artists: const [
          KostvMusicDisliked(id: 'a9', name: 'Nube Roja', artist: true),
        ],
      );
      final station = await kostvStationOf(
        radio: KostvStreamRadio(fetch: fake.call),
        serverId: _server,
        includeAway: true,
        hideExplicit: true,
        homeItems: homeItems,
        dislikes: dislikes,
        artists: ['Lola'],
      );
      expect(station.map((e) => e.id), ['stremfin:4']);
    });

    test('the radio not answering: the home server\'s mix alone', () async {
      final fake = _Radio()..error = StateError('down');
      final station = await kostvStationOf(
        radio: KostvStreamRadio(fetch: fake.call),
        serverId: _server,
        includeAway: true,
        hideExplicit: false,
        homeItems: homeItems,
        homeMix: () async => [_home('m1', 'Lola')],
        artists: ['Lola'],
      );
      expect(station.map((e) => e.id), ['m1']);
    });
  });

  group('the mixes\' extra songs, once a day', () {
    final mix = [
      for (var i = 0; i < 9; i++) _home('h$i', i.isEven ? 'Lola' : 'Nube'),
    ];

    test('one radio call per mix per day, kept on the device', () async {
      final fake = _Radio([
        _song('1', 'Rayo'),
        // Already in the mix (by its title and artist): not again.
        _song('2', 'Lola', title: 'Canción h0'),
        _song('3', 'Sol'),
        _song('4', 'Brisa', jellyfinId: 'j4'),
        _song('5', 'Mar'),
        _song('6', 'Río'),
      ]);
      Object? kept;
      final extras = KostvMixExtras(
        radio: KostvStreamRadio(fetch: fake.call),
        load: () async => kept,
        save: (value) => kept = jsonDecode(jsonEncode(value)),
      );
      Future<List<AggregatedItem>> play(KostvMixExtras extras, String day) =>
          extras.mixWith(
            mixId: 'daily-1',
            day: day,
            because: const ['Lola', 'Nube'],
            items: mix,
            serverId: _server,
            hideExplicit: false,
          );
      final first = await play(extras, '2026-11-21');
      expect(fake.asked.single.only, 'missing');
      expect(fake.asked.single.artists, ['Lola', 'Nube']);
      final away = [
        for (final item in first)
          if (isKostvStream(item)) item.id,
      ];
      expect(away, ['stremfin:1', 'stremfin:3', 'stremfin:5']);
      expect(_noTwoInARow(first), isTrue);
      // Opened again (and on another start of the app): the same, no call.
      expect((await play(extras, '2026-11-21')).map((e) => e.id), [
        for (final item in first) item.id,
      ]);
      final again = KostvMixExtras(
        radio: KostvStreamRadio(fetch: fake.call),
        load: () async => kept,
      );
      expect((await play(again, '2026-11-21')).map((e) => e.id), [
        for (final item in first) item.id,
      ]);
      expect(fake.asked, hasLength(1));
      // The next day, new ones.
      await play(again, '2026-11-22');
      expect(fake.asked, hasLength(2));
    });

    test('nothing found is kept too: not asked again that day', () async {
      final fake = _Radio();
      final extras = KostvMixExtras(radio: KostvStreamRadio(fetch: fake.call));
      for (var i = 0; i < 2; i++) {
        final items = await extras.mixWith(
          mixId: 'daily-2',
          day: '2026-11-21',
          because: const ['Lola'],
          items: mix,
          serverId: _server,
          hideExplicit: false,
        );
        expect(items, mix);
      }
      expect(fake.asked, hasLength(1));
    });

    test('a failure is asked again (once the radio rests)', () async {
      final fake = _Radio()..error = StateError('down');
      var now = DateTime(2026, 11, 21, 10);
      final extras = KostvMixExtras(
        radio: KostvStreamRadio(fetch: fake.call, clock: () => now),
      );
      Future<List<AggregatedItem>> play() => extras.mixWith(
        mixId: 'daily-3',
        day: '2026-11-21',
        because: const ['Lola'],
        items: mix,
        serverId: _server,
        hideExplicit: false,
      );
      expect(await play(), mix);
      fake
        ..error = null
        ..songs = [_song('1', 'Rayo')];
      now = now.add(const Duration(minutes: 2));
      expect((await play()).where(isKostvStream), hasLength(1));
      expect(fake.asked, hasLength(2));
    });

    test('without what the person said no to, nor explicit for kids', () async {
      final fake = _Radio([
        _song('1', 'Rayo'),
        _song('2', 'Sol', explicit: true),
        _song('3', 'Brisa'),
      ]);
      final extras = KostvMixExtras(radio: KostvStreamRadio(fetch: fake.call));
      final items = await extras.mixWith(
        mixId: 'daily-4',
        day: '2026-11-21',
        because: const ['Lola'],
        items: mix,
        serverId: _server,
        hideExplicit: true,
        dislikes: KostvMusicDislikes(
          songs: [
            KostvMusicDisliked(
              id: kostvStreamId('3'),
              deezerId: '3',
              name: 'Radio 3',
            ),
          ],
        ),
      );
      expect(
        [
          for (final item in items)
            if (isKostvStream(item)) item.id,
        ],
        ['stremfin:1'],
      );
    });

    test('a mix without its artists stays as it is (no call)', () async {
      final fake = _Radio([_song('1', 'Rayo')]);
      final extras = KostvMixExtras(radio: KostvStreamRadio(fetch: fake.call));
      final items = await extras.mixWith(
        mixId: 'daily-5',
        day: '2026-11-21',
        because: const [],
        items: mix,
        serverId: _server,
        hideExplicit: false,
      );
      expect(items, mix);
      expect(fake.asked, isEmpty);
    });
  });

  group('a list played whole', () {
    test('without what the person said no to, but the song picked', () {
      final songs = [
        _song('1', 'Rayo'),
        _song('2', 'Nube Roja'),
        _song('3', 'Sol'),
        _song('4', 'Nube Roja'),
      ];
      final dislikes = KostvMusicDislikes(
        songs: [
          KostvMusicDisliked(id: kostvStreamId('3'), deezerId: '3', name: 'x'),
        ],
        artists: const [
          KostvMusicDisliked(id: 'a9', name: 'Nube Roja', artist: true),
        ],
      );
      final kept = kostvSongsToPlay(songs, dislikes, index: 3);
      expect(kept.songs.map((s) => s.deezerId), ['1', '4']);
      expect(kept.index, 1);
      final all = kostvSongsToPlay(songs, dislikes);
      expect(all.songs.map((s) => s.deezerId), ['1']);
      expect(all.index, 0);
    });

    test('today, by the device\'s clock', () {
      expect(kostvToday(DateTime(2026, 3, 4, 23, 59)), '2026-03-04');
    });
  });

  group('«No me gusta» of a song that is not at home', () {
    late JellyfinMediaServerClient client;
    late _Plugin server;
    late KostvMusicDislikesStore store;

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
      server = _Plugin();
      store = KostvMusicDislikesStore(
        KostvMusicPlugin(dio: Dio()..httpClientAdapter = server),
      );
    });

    test('the list reads them with their DeezerId', () async {
      server.songs.add({
        'Id': null,
        'DeezerId': '3135556',
        'Name': 'Fuera',
        'Artist': 'Rayo',
        'At': '2026-11-21T10:00:00Z',
      });
      final list = await store.load(client);
      final entry = list.songs.single;
      expect(entry.id, 'stremfin:3135556');
      expect(entry.deezerId, '3135556');
      expect(entry.outOfHome, isTrue);
      expect(entry.artistName, 'Rayo');
      expect(list.has('stremfin:3135556'), isTrue);
    });

    test('sent as Songs, left out at once, and undone by its id', () async {
      await store.load(client);
      final song = _away('77', 'Rayo', name: 'Lejos');
      expect(await store.dislikeSong(client, song), isTrue);
      final sent = server.asked.where((a) => a.method == 'POST').single.body;
      expect(sent, {
        'Type': 'dislike',
        'Songs': [
          {'DeezerId': '77', 'Name': 'Lejos', 'Artist': 'Rayo'},
        ],
        'Kind': 'song',
      });
      final now = store.of(client);
      expect(now.songOut(song), isTrue);
      expect(now.stremfinSongOut(_song('77', 'Otro')), isTrue);
      expect(now.stremfinSongOut(_song('78', 'Otro')), isFalse);
      // «Deshacer».
      expect(await store.remove(client, song.id), isTrue);
      expect(
        server.asked.last.path,
        '/Moonfin/Kostv/Music/Dislikes/stremfin%3A77',
      );
      expect(store.of(client).songOut(song), isFalse);
      // Put back from Settings («Deshacer» there): sent as Songs again.
      final entry = KostvMusicDisliked(
        id: song.id,
        deezerId: '77',
        name: 'Lejos',
        artistName: 'Rayo',
      );
      expect(await store.restore(client, entry), isTrue);
      expect(
        (server.asked.where((a) => a.method == 'POST').last.body
            as Map)['Songs'],
        isNotNull,
      );
    });

    test('a plugin that doesn\'t keep it: put back', () async {
      await store.load(client);
      server.failPosts = true;
      final song = _away('77', 'Rayo');
      expect(await store.dislikeSong(client, song), isFalse);
      expect(store.of(client).songOut(song), isFalse);
    });

    test('an artist the person said no to leaves out their songs', () {
      const dislikes = KostvMusicDislikes(
        artists: [KostvMusicDisliked(id: 'a1', name: 'Rayo', artist: true)],
      );
      expect(dislikes.songOut(_away('1', 'Rayo')), isTrue);
      expect(dislikes.songOut(_away('2', 'Sol')), isFalse);
      expect(dislikes.stremfinSongOut(_song('3', 'Rayo & Sol')), isTrue);
    });
  });

  group('Kos TV: the audit of «Toda la música»', () {
    Future<List<AggregatedItem>> homeItems(List<String> ids) async => [
      for (final id in ids) _home(id, 'Casa $id'),
    ];

    test('a song already in the queue in its other version doesn\'t go in '
        'again', () async {
      final fake = _Radio([
        _song('1', 'Lola', title: 'Canción q1'),
        _song('2', 'Rayo'),
      ]);
      final queued = _home('q1', 'Lola');
      final station = await kostvStationOf(
        radio: KostvStreamRadio(fetch: fake.call),
        serverId: _server,
        includeAway: true,
        hideExplicit: false,
        homeItems: homeItems,
        artists: ['Lola'],
        skip: {queued.id},
        skipKeys: {kostvSongKey(queued)},
      );
      expect(station.map((e) => e.id), ['stremfin:2']);
      expect(
        kostvInterleaveRadio(
          const [],
          [_away('9', 'Lola', name: 'Canción q1')],
          skipKeys: {kostvSongKey(queued)},
        ),
        isEmpty,
      );
    });

    test('neither the radio nor the home server answering: it says so, to be '
        'asked again', () async {
      final fake = _Radio()..error = StateError('down');
      await expectLater(
        kostvStationOf(
          radio: KostvStreamRadio(fetch: fake.call),
          serverId: _server,
          includeAway: true,
          hideExplicit: false,
          homeItems: homeItems,
          artistIds: ['ar1'],
        ),
        throwsA(isA<StateError>()),
      );
      // The radio answering nothing isn't a failure.
      expect(
        await kostvStationOf(
          radio: KostvStreamRadio(fetch: _Radio().call),
          serverId: _server,
          includeAway: true,
          hideExplicit: false,
          homeItems: homeItems,
          artistIds: ['ar1'],
        ),
        isEmpty,
      );
    });

    test('a radio song at home the home server doesn\'t give is left out; '
        'through the service only when the home server fails, with all the '
        'music and no limit', () async {
      final fake = _Radio([_song('1', 'Rayo', jellyfinId: 'j1')]);
      Future<List<AggregatedItem>> station({
        required bool includeAway,
        required bool hideExplicit,
        required Future<List<AggregatedItem>> Function(List<String>) home,
      }) => kostvStationOf(
        radio: KostvStreamRadio(fetch: fake.call),
        serverId: _server,
        includeAway: includeAway,
        hideExplicit: hideExplicit,
        homeItems: home,
        artistIds: ['ar1'],
      );
      Future<List<AggregatedItem>> none(List<String> _) async => const [];
      Future<List<AggregatedItem>> down(List<String> _) async =>
          throw StateError('offline');
      expect(
        await station(includeAway: true, hideExplicit: false, home: none),
        isEmpty,
      );
      expect(
        await station(includeAway: false, hideExplicit: false, home: down),
        isEmpty,
      );
      expect(
        await station(includeAway: true, hideExplicit: true, home: down),
        isEmpty,
      );
      expect(
        (await station(
          includeAway: true,
          hideExplicit: false,
          home: down,
        )).map((e) => e.id),
        ['stremfin:1'],
      );
    });

    test('a radio kept is asked again after an hour', () async {
      final fake = _Radio([_song('1', 'Rayo')]);
      var now = DateTime(2026, 11, 21, 10);
      final radio = KostvStreamRadio(fetch: fake.call, clock: () => now);
      await radio.songs(artists: ['Lola']);
      now = now.add(const Duration(minutes: 59));
      await radio.songs(artists: ['Lola']);
      expect(fake.asked, hasLength(1));
      now = now.add(const Duration(minutes: 2));
      await radio.songs(artists: ['Lola']);
      expect(fake.asked, hasLength(2));
    });

    final mix = [
      for (var i = 0; i < 9; i++) _home('h$i', i.isEven ? 'Lola' : 'Nube'),
    ];

    test('a daily mix and the moment\'s mix, each with its own day, don\'t '
        'undo each other', () async {
      final fake = _Radio([_song('1', 'Rayo'), _song('2', 'Sol')]);
      final extras = KostvMixExtras(radio: KostvStreamRadio(fetch: fake.call));
      Future<List<AggregatedItem>> play(String mixId, String day) =>
          extras.mixWith(
            mixId: mixId,
            day: day,
            because: const ['Lola'],
            items: mix,
            serverId: _server,
            hideExplicit: false,
          );
      // Between midnight and 5:00: the daily mixes are still yesterday's.
      await play('daily-1', '2026-11-20');
      await play('morning', '2026-11-21');
      await play('daily-1', '2026-11-20');
      await play('morning', '2026-11-21');
      expect(fake.asked, hasLength(1));
    });

    test(
      'each person\'s mixes are read from and kept in their own note',
      () async {
        final fake = _Radio([_song('1', 'Rayo')]);
        final notes = <String, Object?>{};
        var who = 'casa|ana';
        final extras = KostvMixExtras(
          radio: KostvStreamRadio(fetch: fake.call, who: () => who),
          load: () async => notes[who],
          save: (value) => notes[who] = jsonDecode(jsonEncode(value)),
          who: () => who,
        );
        Future<List<AggregatedItem>> play(String person) => extras.mixWith(
          mixId: '${person.split('|').last}|daily-1',
          person: person,
          day: '2026-11-21',
          because: const ['Lola'],
          items: mix,
          serverId: _server,
          hideExplicit: false,
        );
        await play('casa|ana');
        expect((notes['casa|ana']! as Map)['mixes'], contains('ana|daily-1'));
        // Luis had his picked already today (another time the app was open).
        notes['casa|luis'] = {
          'mixes': {
            'luis|daily-1': {
              'day': '2026-11-21',
              'songs': [
                {'id': 'stremfin:7', 'raw': _away('7', 'Mar').rawData},
              ],
            },
          },
        };
        who = 'casa|luis';
        final luis = await play('casa|luis');
        expect(luis.where(isKostvStream).map((e) => e.id), ['stremfin:7']);
        expect(fake.asked, hasLength(1));
        // Nothing of Ana's in Luis's note.
        who = 'casa|luis';
        await extras.mixWith(
          mixId: 'luis|daily-2',
          person: 'casa|luis',
          day: '2026-11-21',
          because: const ['Nube'],
          items: mix,
          serverId: _server,
          hideExplicit: false,
        );
        final kept = (notes['casa|luis']! as Map)['mixes'] as Map;
        expect(kept.keys, unorderedEquals(['luis|daily-1', 'luis|daily-2']));
      },
    );

    test('a note of before (one day for all) is still read', () async {
      final fake = _Radio([_song('1', 'Rayo')]);
      final extras = KostvMixExtras(
        radio: KostvStreamRadio(fetch: fake.call),
        load: () async => {
          'day': '2026-11-21',
          'mixes': {
            'daily-1': [
              {'id': 'stremfin:7', 'raw': _away('7', 'Mar').rawData},
            ],
          },
        },
      );
      final items = await extras.mixWith(
        mixId: 'daily-1',
        day: '2026-11-21',
        because: const ['Lola'],
        items: mix,
        serverId: _server,
        hideExplicit: false,
      );
      expect(items.where(isKostvStream).map((e) => e.id), ['stremfin:7']);
      expect(fake.asked, isEmpty);
    });
  });

  group('Kos TV: second audit of the lists', () {
    test('radios that expired go when another is kept', () async {
      final fake = _Radio([_song('1', 'Rayo')]);
      var now = DateTime(2026, 11, 21, 10);
      final radio = KostvStreamRadio(fetch: fake.call, clock: () => now);
      await radio.songs(artists: ['Lola']);
      await radio.songs(artists: ['Nube']);
      expect(radio.debugKeptCount, 2);
      now = now.add(const Duration(hours: 2));
      await radio.songs(artists: ['Sol']);
      // Only the one just asked for: Lola's and Nube's had expired.
      expect(radio.debugKeptCount, 1);
      await radio.songs(artists: ['Lola']);
      expect(fake.asked, hasLength(4));
      expect(radio.debugKeptCount, 2);
    });

    test('a mix put on for someone who is no longer signed in doesn\'t take '
        'their note as read', () async {
      final fake = _Radio([_song('1', 'Rayo')]);
      final notes = <String, Object?>{
        'casa|ana': {
          'mixes': {
            'ana|daily-1': {
              'day': '2026-11-21',
              'songs': [
                {'id': 'stremfin:7', 'raw': _away('7', 'Mar').rawData},
              ],
            },
          },
        },
      };
      // Luis signed in while Ana's mix was being put on.
      var who = 'casa|luis';
      final extras = KostvMixExtras(
        radio: KostvStreamRadio(fetch: fake.call, who: () => who),
        load: () async => notes[who],
        save: (value) => notes[who] = jsonDecode(jsonEncode(value)),
        who: () => who,
      );
      Future<List<AggregatedItem>> play(String mixId) => extras.mixWith(
        mixId: mixId,
        person: 'casa|ana',
        day: '2026-11-21',
        because: const ['Lola'],
        items: _mix9,
        serverId: _server,
        hideExplicit: false,
      );
      await play('ana|daily-2');
      final asked = fake.asked.length;
      // Ana back: her note is read, and her mix keeps today's songs.
      who = 'casa|ana';
      final again = await play('ana|daily-1');
      expect(again.where(isKostvStream).map((e) => e.id), ['stremfin:7']);
      expect(fake.asked, hasLength(asked));
    });

    test('the night\'s mix keeps its day past midnight', () {
      expect(kostvMomentDay(DateTime(2026, 11, 21, 23)), '2026-11-21');
      expect(kostvMomentDay(DateTime(2026, 11, 22, 1)), '2026-11-21');
      expect(kostvMomentDay(DateTime(2026, 11, 22, 5, 59)), '2026-11-21');
      // The morning and the afternoon are the day's own.
      expect(kostvMomentDay(DateTime(2026, 11, 22, 6)), '2026-11-22');
      expect(kostvMomentDay(DateTime(2026, 11, 22, 19)), '2026-11-22');
    });
  });
}

/// The plugin's «No me gusta» routes, with songs that aren't at home.
class _Plugin implements HttpClientAdapter {
  final songs = <Map<String, Object?>>[];
  final asked = <({String method, String path, Object? body})>[];
  bool failPosts = false;

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
    final path = options.uri.path;
    asked.add((method: options.method, path: path, body: body));
    const base = '/Moonfin/Kostv/Music';
    switch ((options.method, path)) {
      case ('GET', '$base/Dislikes'):
        return ResponseBody.fromString(
          jsonEncode({'Songs': songs, 'Artists': const []}),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      case ('POST', '$base/Event'):
        return ResponseBody.fromString('', failPosts ? 500 : 204);
      case ('DELETE', final p) when p.startsWith('$base/Dislikes/'):
        return ResponseBody.fromString('', 204);
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}
