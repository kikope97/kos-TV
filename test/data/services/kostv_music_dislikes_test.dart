import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music.dart';
import 'package:moonfin/data/services/kostv_music_dislikes.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/music/kostv_music_screen.dart'
    show kostvMusicBecause;
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

/// The plugin's «No me gusta» and taste routes, kept as the plan's section
/// 6 sets them; [hasRoutes] false is a plugin from before them (404).
class _Server implements HttpClientAdapter {
  _Server({this.hasRoutes = true, this.taste});

  final bool hasRoutes;

  /// `GET Taste`'s answer (404 without one).
  final Object? taste;

  /// The status everything answers with for now, when the server isn't well.
  int? failing;

  /// Kos TV: holds the list's reads until it completes.
  Completer<void>? holdRead;

  final songs = <Map<String, Object?>>[];
  final artists = <Map<String, Object?>>[];
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
    final path = options.uri.path;
    asked.add((method: options.method, path: path, body: body));
    if (failing case final status?) return ResponseBody.fromString('', status);
    const base = '/Moonfin/Kostv/Music';
    if (path == '$base/Taste' && options.method == 'GET') {
      if (taste == null) return ResponseBody.fromString('', 404);
      return _json(taste);
    }
    if (!hasRoutes) return ResponseBody.fromString('', 404);
    switch ((options.method, path)) {
      case ('GET', '$base/Dislikes'):
        // What the list was when asked, answered when [holdRead] lets it.
        final answer = {
          'Songs': [...songs],
          'Artists': [...artists],
        };
        if (holdRead case final hold?) await hold.future;
        return _json(answer);
      case ('POST', '$base/Event'):
        final event = body as Map;
        for (final id in event['ItemIds'] as List) {
          (event['Kind'] == 'artist' ? artists : songs).insert(0, {
            'Id': id,
            'Name': 'Nombre $id',
            'At': '2026-11-21T10:00:00Z',
          });
        }
        return ResponseBody.fromString('', 204);
      case ('DELETE', '$base/Dislikes'):
        songs.clear();
        artists.clear();
        return ResponseBody.fromString('', 204);
      case ('DELETE', final p) when p.startsWith('$base/Dislikes/'):
        final id = p.split('/').last;
        songs.removeWhere((s) => s['Id'] == id);
        artists.removeWhere((a) => a['Id'] == id);
        return ResponseBody.fromString('', 204);
    }
    return ResponseBody.fromString('', 404);
  }

  ResponseBody _json(Object? data) => ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

AggregatedItem _song(
  String id, {
  String artistId = 'a1',
  String artist = 'Lola Brisa',
}) => AggregatedItem(
  id: id,
  serverId: 'https://casa.example',
  rawData: {
    'Id': id,
    'Name': 'Canción $id',
    'Type': 'Audio',
    'Artists': [artist],
    'ArtistItems': [
      {'Id': artistId, 'Name': artist},
    ],
    'AlbumArtists': [
      {'Id': artistId, 'Name': artist},
    ],
  },
);

/// A compilation's song: by [artist], on an album by «Various Artists».
AggregatedItem _compilationSong(
  String id, {
  bool ownArtists = true,
  String artistId = 'a1',
  String artist = 'Lola Brisa',
}) => AggregatedItem(
  id: id,
  serverId: 'https://casa.example',
  rawData: {
    'Id': id,
    'Name': 'Canción $id',
    'Type': 'Audio',
    if (ownArtists) ...{
      'Artists': [artist],
      'ArtistItems': [
        {'Id': artistId, 'Name': artist},
      ],
    },
    'AlbumArtist': 'Various Artists',
    'AlbumArtists': [
      {'Id': 'va', 'Name': 'Various Artists'},
    ],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late JellyfinMediaServerClient client;

  setUp(() {
    client =
        JellyfinMediaServerClient(
            baseUrl: 'https://casa.example',
            deviceInfo: const DeviceInfo(
              id: 'device',
              name: 'Device',
              appName: 'kOS TV',
              appVersion: '1.0.0',
            ),
          )
          ..accessToken = 'token'
          ..userId = 'ana';
  });

  KostvMusicPlugin pluginWith(_Server server) =>
      KostvMusicPlugin(dio: Dio()..httpClientAdapter = server);

  group('the plugin\'s routes', () {
    test('a song\'s «No me gusta» says what it is', () async {
      final server = _Server();
      expect(await pluginWith(server).sendDislike(client, ['9']), isTrue);
      expect(server.asked.single.body, {
        'Type': 'dislike',
        'ItemIds': ['9'],
        'Kind': 'song',
      });
    });

    test('an artist\'s too', () async {
      final server = _Server();
      await pluginWith(server).sendDislike(client, ['a1'], artist: true);
      expect((server.asked.single.body as Map)['Kind'], 'artist');
    });

    test('reads the list, ids without dashes, the latest first', () async {
      final server = _Server()
        ..songs.add({
          'Id': 'ab-cd',
          'Name': 'Verano',
          'Artist': 'Lola Brisa',
          'ArtistId': 'a-1',
          'AlbumId': 'al1',
          'At': '2026-11-20T21:00:00Z',
        })
        ..artists.add({'Id': 'a2', 'Name': 'Nube Roja'});
      final list = (await pluginWith(server).dislikes(client)).value!;
      expect(list.songs.single.id, 'abcd');
      expect(list.songs.single.artistName, 'Lola Brisa');
      expect(list.songs.single.artistId, 'a1');
      expect(list.artists.single.name, 'Nube Roja');
      expect(list.artists.single.artist, isTrue);
      expect(list.has('ab-cd'), isTrue);
    });

    test('takes one off and empties it', () async {
      final server = _Server();
      final plugin = pluginWith(server);
      expect(await plugin.removeDislike(client, 'x1'), isTrue);
      expect(await plugin.clearDislikes(client), isTrue);
      expect(server.asked.map((a) => '${a.method} ${a.path}'), [
        'DELETE /Moonfin/Kostv/Music/Dislikes/x1',
        'DELETE /Moonfin/Kostv/Music/Dislikes',
      ]);
    });

    test('a plugin from before it: missing, not failed', () async {
      final answer = await pluginWith(_Server(hasRoutes: false))
          .dislikes(client);
      expect(answer.missing, isTrue);
    });

    test('reads the taste; lately\'s first, then always\', once', () async {
      final taste = KostvMusicPluginTaste.fromJson({
        'Learned': 0.5,
        'Artists': [
          for (final n in ['1', '2', '3']) {'Id': 'a$n', 'Name': 'A$n'},
        ],
        'Recent': [
          for (final n in ['9', '2', '8', '7', '6', '5'])
            {'Id': 'a$n', 'Name': 'A$n'},
        ],
        'Genres': [
          {'Name': 'Pop', 'Score': 3},
          {'Name': 'Latin', 'Score': 2},
        ],
      })!;
      expect(taste.learned, 0.5);
      final mine = taste.toTaste();
      expect(mine.artists.map((a) => a.id), [
        'a9',
        'a2',
        'a8',
        'a7',
        'a1',
        'a3',
        'a6',
        'a5',
      ]);
      expect(mine.genres, ['Pop', 'Latin']);
    });

    test('the mixes and the moment bring who is in them', () {
      final mixes = KostvDailyMixes.fromJson({
        'Mixes': [
          {
            'Id': 'daily-1',
            'Items': [
              {'Id': '1', 'Name': 'Uno'},
            ],
            'Because': ['Lola', 'Nube', '', 'Lola'],
          },
        ],
      }, 'https://casa.example')!;
      expect(mixes.mixes.single.because, ['Lola', 'Nube']);
      // Kept on the device and read back.
      expect(
        KostvDailyMixes.fromJson(
          mixes.toJson(),
          'https://casa.example',
        )!.mixes.single.because,
        ['Lola', 'Nube'],
      );
      final moment = KostvMusicMoment.fromJson({
        'Slot': 'tarde',
        'Ready': true,
        'Because': ['Clara'],
      }, 'https://casa.example')!;
      expect(moment.because, ['Clara']);
    });
  });

  group('what is left out', () {
    const list = KostvMusicDislikes(
      songs: [KostvMusicDisliked(id: 's1', name: 'Uno')],
      artists: [KostvMusicDisliked(id: 'a9', name: 'Nube Roja', artist: true)],
    );

    test('a song by its id, or by its artist\'s id or name', () {
      expect(list.songOut(_song('s1')), isTrue);
      expect(list.songOut(_song('s2', artistId: 'a9')), isTrue);
      expect(
        list.songOut(_song('s3', artistId: 'x', artist: 'nube roja')),
        isTrue,
      );
      expect(list.songOut(_song('s4')), isFalse);
    });

    test('the requests service\'s, by the artist\'s name (lowercase), or '
        'by the home server\'s id', () {
      expect(
        list.stremfinSongOut(
          const StremfinSong(title: 'X', artist: 'Lola & NUBE ROJA'),
        ),
        isTrue,
      );
      expect(
        list.stremfinSongOut(
          const StremfinSong(title: 'X', artist: 'Lola', jellyfinId: 's1'),
        ),
        isTrue,
      );
      expect(
        list.stremfinSongOut(const StremfinSong(title: 'X', artist: 'Lola')),
        isFalse,
      );
      expect(
        list
            .stremfinAlbumsIn(const [
              StremfinAlbum(title: 'A', artist: 'Nube Roja'),
              StremfinAlbum(title: 'B', artist: 'Lola'),
            ])
            .map((a) => a.title),
        ['B'],
      );
    });

    test('a radio keeps the song it was picked from', () {
      final kept = kostvMusicLeaveOut(list, [
        _song('s4'),
        _song('s1'),
        _song('s5', artistId: 'a9'),
        _song('s6'),
      ], startIndex: 1);
      expect(kept.tracks.map((t) => t.id), ['s4', 's1', 's6']);
      expect(kept.startIndex, 1);
    });

    test('an artist\'s radio, with no song picked, doesn\'t start with one '
        'out', () {
      final kept = kostvMusicLeaveOut(list, [
        _song('s1'),
        _song('s5', artistId: 'a9'),
        _song('s6'),
        _song('s7'),
      ], keepStart: false);
      expect(kept.tracks.map((t) => t.id), ['s6', 's7']);
      expect(kept.startIndex, 0);
      // From the middle: the first kept from there on.
      final later = kostvMusicLeaveOut(
        list,
        [_song('s4'), _song('s1'), _song('s6')],
        startIndex: 1,
        keepStart: false,
      );
      expect(later.tracks.map((t) => t.id), ['s4', 's6']);
      expect(later.startIndex, 1);
      // All of it out: nothing to play.
      expect(
        kostvMusicLeaveOut(list, [_song('s1')], keepStart: false).tracks,
        isEmpty,
      );
    });

    test('a compilation\'s song is by its own artist, not «Various '
        'Artists»', () {
      final song = _compilationSong('c1');
      expect(kostvMusicArtistIds(song), ['a1']);
      expect(kostvMusicArtistNames(song), ['Lola Brisa', 'Lola Brisa']);
      expect(kostvMusicSongArtist(song), (id: 'a1', name: 'Lola Brisa'));
      const various = KostvMusicDislikes(
        artists: [
          KostvMusicDisliked(id: 'va', name: 'Various Artists', artist: true),
        ],
      );
      expect(various.songOut(song), isFalse);
      const lola = KostvMusicDislikes(
        artists: [KostvMusicDisliked(id: 'a1', name: 'Lola', artist: true)],
      );
      expect(lola.songOut(song), isTrue);
      // One that names no artist of its own is its album's, as for the
      // plugin.
      final bare = _compilationSong('c2', ownArtists: false);
      expect(kostvMusicSongArtist(bare), (id: 'va', name: 'Various Artists'));
      expect(various.songOut(bare), isTrue);
    });

    test('a mix without them, and without them in «Con …»', () {
      final mixes = list.mixesIn(
        KostvDailyMixes(
          mixes: [
            KostvDailyMix(
              id: 'daily-1',
              items: [_song('s1'), _song('s4')],
              because: const ['Nube Roja', 'Lola Brisa'],
            ),
            KostvDailyMix(id: 'daily-2', items: [_song('s1')]),
          ],
        ),
      );
      expect(mixes.mixes.single.items.map((i) => i.id), ['s4']);
      expect(mixes.mixes.single.because, ['Lola Brisa']);
    });
  });

  group('the list kept for the person', () {
    test('a plugin from before it: not offered, nothing left out', () async {
      final store = KostvMusicDislikesStore(
        pluginWith(_Server(hasRoutes: false)),
      );
      await store.load(client);
      expect(store.supported(client), isFalse);
      expect(store.of(client).isEmpty, isTrue);
    });

    test('left out at once, and kept by the plugin', () async {
      final server = _Server();
      final store = KostvMusicDislikesStore(pluginWith(server));
      await store.load(client);
      expect(store.supported(client), isTrue);
      final kept = store.dislikeSong(client, _song('s1'));
      expect(store.of(client).has('s1'), isTrue);
      expect(await kept, isTrue);
      expect(server.songs.single['Id'], 's1');
    });

    test('undone: off the list and the plugin\'s', () async {
      final server = _Server();
      final store = KostvMusicDislikesStore(pluginWith(server));
      await store.load(client);
      await store.dislikeArtist(client, id: 'a9', name: 'Nube Roja');
      expect(await store.remove(client, 'a9'), isTrue);
      expect(store.of(client).isEmpty, isTrue);
      expect(server.artists, isEmpty);
    });

    test('not kept (the server failing): put back', () async {
      final server = _Server();
      final store = KostvMusicDislikesStore(pluginWith(server));
      await store.load(client);
      server.failing = 500;
      expect(await store.dislikeSong(client, _song('s1')), isFalse);
      expect(store.of(client).has('s1'), isFalse);
    });

    test('a read on its way doesn\'t undo a change made meanwhile', () async {
      final server = _Server()..songs.add({'Id': 's1', 'Name': 'Uno'});
      final store = KostvMusicDislikesStore(pluginWith(server));
      await store.load(client);
      server.holdRead = Completer<void>();
      final reading = store.refresh(client);
      // Asked before the change: its answer still has s1 and not s2.
      await Future<void>.delayed(Duration.zero);
      await store.remove(client, 's1');
      await store.dislikeSong(client, _song('s2'));
      server.holdRead!.complete();
      await reading;
      expect(store.of(client).has('s1'), isFalse);
      expect(store.of(client).has('s2'), isTrue);
      // And the next load still has the change.
      server.holdRead = null;
      await store.load(client);
      expect(store.of(client).has('s1'), isFalse);
      expect(store.of(client).has('s2'), isTrue);
    });

    test('after a failure it waits before asking again', () async {
      final server = _Server()..failing = 500;
      final store = KostvMusicDislikesStore(pluginWith(server));
      await store.load(client);
      await store.load(client);
      await store.load(client);
      int reads() => server.asked
          .where((a) => a.method == 'GET' && a.path.endsWith('/Dislikes'))
          .length;
      expect(reads(), 1);
      // Asked on purpose (Settings), it is read.
      server.failing = null;
      await store.load(client, force: true);
      expect(reads(), 2);
      expect(store.supported(client), isTrue);
    });

    test('someone else\'s list isn\'t this person\'s', () async {
      final server = _Server()..songs.add({'Id': 's1', 'Name': 'Uno'});
      final store = KostvMusicDislikesStore(pluginWith(server));
      await store.load(client);
      expect(store.of(client).has('s1'), isTrue);
      client.userId = 'luis';
      expect(store.of(client).isEmpty, isTrue);
    });
  });

  group('«Para ti»\'s taste', () {
    Future<KostvMusicTaste> fallback() async =>
        const KostvMusicTaste(artists: [(id: 'own', name: 'De la app')]);

    test('the plugin\'s, when it has the route', () async {
      final server = _Server(
        taste: {
          'Learned': 1,
          'Artists': [
            {'Id': 'a1', 'Name': 'Lola Brisa'},
          ],
          'Recent': [
            {'Id': 'a2', 'Name': 'Nube Roja'},
          ],
          'Genres': [
            {'Name': 'Pop'},
          ],
        },
      );
      final taste = await kostvLoadMusicTaste(
        pluginWith(server),
        client,
        fallback: fallback,
      );
      expect(taste.artists.map((a) => a.name), ['Nube Roja', 'Lola Brisa']);
      expect(taste.genres, ['Pop']);
    });

    test('the app\'s own with a plugin from before it (404)', () async {
      final taste = await kostvLoadMusicTaste(
        pluginWith(_Server()),
        client,
        fallback: fallback,
      );
      expect(taste.artists.single.id, 'own');
    });

    test('the app\'s own when the plugin fails', () async {
      final taste = await kostvLoadMusicTaste(
        pluginWith(_Server(taste: const {})..failing = 500),
        client,
        fallback: fallback,
      );
      expect(taste.artists.single.id, 'own');
    });

    test('without the artists the person doesn\'t want', () async {
      final taste = await kostvLoadMusicTaste(
        pluginWith(_Server()),
        client,
        fallback: () async => const KostvMusicTaste(
          artists: [(id: 'a9', name: 'Nube Roja'), (id: 'a1', name: 'Lola')],
        ),
        dislikes: () async => const KostvMusicDislikes(
          artists: [
            KostvMusicDisliked(id: 'a9', name: 'Nube Roja', artist: true),
          ],
        ),
      );
      expect(taste.artists.map((a) => a.id), ['a1']);
    });
  });

  testWidgets('«Con X, Y y más»', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(kostvMusicBecause(l10n, const []), isNull);
    expect(kostvMusicBecause(l10n, const ['Lola']), 'Con Lola');
    expect(kostvMusicBecause(l10n, const ['Lola', 'Nube']), 'Con Lola y Nube');
    // «e» before the «i» sound, but not before «hie».
    expect(
      kostvMusicBecause(l10n, const ['Lola', 'Isabel']),
      'Con Lola e Isabel',
    );
    expect(
      kostvMusicBecause(l10n, const ['Lola', 'Hilario']),
      'Con Lola e Hilario',
    );
    expect(kostvMusicBecause(l10n, const ['Lola', 'Ívar']), 'Con Lola e Ívar');
    expect(
      kostvMusicBecause(l10n, const ['Lola', 'Hielo Azul']),
      'Con Lola y Hielo Azul',
    );
    expect(
      kostvMusicBecause(l10n, const ['Isabel', 'Lola']),
      'Con Isabel y Lola',
    );
    expect(
      kostvMusicBecause(l10n, const ['Lola', 'Nube', 'Clara']),
      'Con Lola, Nube y más',
    );
  });

  testWidgets('in English, «and» whatever the name', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      kostvMusicBecause(l10n, const ['Lola', 'Isabel']),
      'With Lola and Isabel',
    );
  });
}
