import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_away.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

/// Kos TV: the plugin's routes for songs that aren't at home in playlists
/// and ♥ (plan section 8), as the contract and its details set them;
/// [hasRoutes] false is a plugin from before them (404).
class _Server implements HttpClientAdapter {
  _Server({this.hasRoutes = true});

  final bool hasRoutes;

  /// The status a POST answers with (403, 400…), when set.
  int? postStatus;

  /// Kos TV: the status of the others, when set: a DELETE, a GET of the
  /// ♥ or of a playlist, an arrival.
  int? deleteStatus;
  int? favoritesStatus;
  int? playlistStatus;
  int? arrivedStatus;

  /// Kos TV: a playlist's GET waits for this, when set.
  Completer<void>? playlistGate;

  /// Kos TV: the playlists the person may change (`Away/Playlists/Editable`).
  List<String> editable = const [];

  final asked = <({String method, String path, Object? body})>[];
  final favorites = <Map<String, Object?>>[];
  final entries = <Map<String, Object?>>[];

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
    if (!hasRoutes) return ResponseBody.fromString('', 404);
    const base = '/Moonfin/Kostv/Music/Away';
    final method = options.method;
    if (method == 'POST' && path == '$base/Playlists/Editable') {
      return _json({'Ids': editable});
    }
    if (method == 'POST' && path == '$base/Arrived' && arrivedStatus != null) {
      return ResponseBody.fromString('', arrivedStatus!);
    }
    if (method == 'POST' && postStatus != null) {
      return ResponseBody.fromString('', postStatus!);
    }
    if (method == 'DELETE' && deleteStatus != null) {
      return ResponseBody.fromString('', deleteStatus!);
    }
    if (method == 'GET' && path == '$base/Favorites') {
      if (favoritesStatus != null) {
        return ResponseBody.fromString('', favoritesStatus!);
      }
      return _json({'Songs': favorites});
    }
    if (method == 'GET' && path.startsWith('$base/Playlist/')) {
      await playlistGate?.future;
      if (playlistStatus != null) {
        return ResponseBody.fromString('', playlistStatus!);
      }
      return _json({'Entries': entries});
    }
    if (method == 'POST' &&
        path.startsWith('$base/Playlist/') &&
        !path.endsWith('/Order')) {
      for (final song in ((body as Map)['Songs'] as List)) {
        entries.add({...(song as Map).cast<String, Object?>(), 'After': null});
      }
      return _json({'Entries': entries});
    }
    return ResponseBody.fromString('', 204);
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

AggregatedItem _home(String id, {String? lastPlayed}) => AggregatedItem(
  id: id,
  serverId: 'https://casa.example',
  rawData: {
    'Id': id,
    'Name': 'Canción $id',
    'Type': 'Audio',
    'PlaylistItemId': 'entry-$id',
    'UserData': {'LastPlayedDate': ?lastPlayed},
  },
);

KostvAwayEntry _entry(
  String id, {
  String? after,
  bool explicit = false,
  DateTime? added,
}) => KostvAwayEntry(
  song: KostvAwaySong(deezerId: id, title: 'Fuera $id', explicit: explicit),
  after: after,
  added: added,
);

List<String> _ids(List<AggregatedItem> items) => [for (final i in items) i.id];

void main() {
  late JellyfinMediaServerClient client;

  JellyfinMediaServerClient person(String user, {String token = 'token'}) =>
      JellyfinMediaServerClient(
          baseUrl: 'https://casa.example',
          deviceInfo: const DeviceInfo(
            id: 'device',
            name: 'Device',
            appName: 'kOS TV',
            appVersion: '1.0.0',
          ),
        )
        ..accessToken = token
        ..userId = user;

  setUp(() => client = person('ana'));

  KostvMusicPlugin pluginWith(_Server server) =>
      KostvMusicPlugin(dio: Dio()..httpClientAdapter = server);

  final away = kostvStreamItem(
    deezerId: '77',
    title: 'Lejos',
    serverId: 'https://casa.example',
    artist: 'Rayo',
    album: 'Tormenta',
    albumDeezerId: '700',
    artistDeezerId: '7',
    cover: 'https://img.example/77.jpg',
    durationSeconds: 200,
  );

  group('a song that isn\'t at home, as the plugin takes it', () {
    test('from the queue\'s song', () {
      expect(KostvAwaySong.ofItem(away)!.toJson(), {
        'DeezerId': '77',
        'Title': 'Lejos',
        'Artist': 'Rayo',
        'Album': 'Tormenta',
        'AlbumDeezerId': '700',
        'ArtistDeezerId': '7',
        'Cover': 'https://img.example/77.jpg',
        'Duration': 200,
        'Explicit': false,
      });
    });

    test('without what the plugin would turn down', () {
      final json = KostvAwaySong(
        deezerId: '1',
        title: 'x' * 250,
        cover: 'ftp://img.example/1.jpg',
        duration: 7 * 3600,
      ).toJson();
      expect((json['Title'] as String).length, 200);
      expect(json.containsKey('Artist'), isFalse);
      expect(json.containsKey('Album'), isFalse);
      expect(json.containsKey('Cover'), isFalse);
      expect(json.containsKey('Duration'), isFalse);
      final long = KostvAwaySong(
        deezerId: '1',
        title: 't',
        cover: 'https://img.example/${'a' * 1000}',
      ).toJson();
      expect(long.containsKey('Cover'), isFalse);
    });

    test('read with ids as numbers and Explicit missing', () {
      final song = KostvAwaySong.fromJson({
        'DeezerId': 3135556,
        'Title': 'Harder',
        'AlbumDeezerId': 302127,
      })!;
      expect(song.deezerId, '3135556');
      expect(song.albumDeezerId, '302127');
      expect(song.explicit, isFalse);
      expect(KostvAwaySong.fromJson({'DeezerId': '1'}), isNull);
    });
  });

  group('the routes', () {
    test('a playlist\'s songs, with their places', () async {
      final server = _Server()
        ..entries.add({
          'DeezerId': '9',
          'Title': 'Nueve',
          'After': 'abc',
          'Added': '2026-11-21T10:00:00Z',
        });
      final answer = await pluginWith(server).awayPlaylist(client, 'pl-1');
      expect(answer.value!.single.after, 'abc');
      expect(answer.value!.single.added, DateTime.utc(2026, 11, 21, 10));
      expect(
        server.asked.single.path,
        '/Moonfin/Kostv/Music/Away/Playlist/pl-1',
      );
    });

    test('adding goes at the end, without After', () async {
      final server = _Server();
      final added = await pluginWith(server)
          .addAwayToPlaylist(client, 'pl', [KostvAwaySong.ofItem(away)!]);
      expect(added.entries, hasLength(1));
      final body = server.asked.single.body as Map;
      expect(body.containsKey('After'), isFalse);
      expect((body['Songs'] as List).single['DeezerId'], '77');
    });

    test('without permission, or over the limit, it says so', () async {
      final server = _Server()..postStatus = 403;
      final plugin = pluginWith(server);
      final song = KostvAwaySong.ofItem(away)!;
      final forbidden = await plugin.addAwayToPlaylist(client, 'pl', [song]);
      expect(forbidden.forbidden, isTrue);
      expect(forbidden.entries, isNull);
      server.postStatus = 400;
      final full = await plugin.addAwayToPlaylist(client, 'pl', [song]);
      expect(full.full, isTrue);
      expect(await plugin.addAwayFavorite(client, song), 400);
    });

    test('taking out, the order, the ♥ and an arrival', () async {
      final server = _Server();
      final plugin = pluginWith(server);
      await plugin.removeAwayFromPlaylist(client, 'pl', '77');
      await plugin.orderAwayPlaylist(client, 'pl', ['a', 'stremfin:77']);
      expect(
        await plugin.addAwayFavorite(client, KostvAwaySong.ofItem(away)!),
        204,
      );
      await plugin.removeAwayFavorite(client, '77');
      await plugin.sendAwayArrived(client, deezerId: '77', jellyfinId: 'j1');
      expect(
        [for (final a in server.asked) '${a.method} ${a.path}'],
        [
          'DELETE /Moonfin/Kostv/Music/Away/Playlist/pl/77',
          'POST /Moonfin/Kostv/Music/Away/Playlist/pl/Order',
          'POST /Moonfin/Kostv/Music/Away/Favorites',
          'DELETE /Moonfin/Kostv/Music/Away/Favorites/77',
          'POST /Moonfin/Kostv/Music/Away/Arrived',
        ],
      );
      expect(server.asked[1].body, {
        'Ids': ['a', 'stremfin:77'],
      });
      expect(server.asked.last.body, {'DeezerId': '77', 'JellyfinId': 'j1'});
    });
  });

  group('merging a playlist by its anchors', () {
    test('first, after a home song, after another one, at the end', () {
      final merged = kostvMergeAway(
        [_home('a'), _home('b')],
        [
          _entry('1'),
          _entry('2', after: 'a'),
          _entry('3', after: 'stremfin:2'),
          _entry('4', after: 'gone'),
        ],
        serverId: 's',
      );
      expect(_ids(merged), [
        'stremfin:1',
        'a',
        'stremfin:2',
        'stremfin:3',
        'b',
        'stremfin:4',
      ]);
      // Each one an entry of the list, by its own id.
      expect(merged.first.rawData['PlaylistItemId'], 'stremfin:1');
    });

    test('Jellyfin\'s ids match with or without dashes, any case', () {
      final merged = kostvMergeAway(
        [_home('AB-CD')],
        [_entry('1', after: 'abcd')],
        serverId: 's',
      );
      expect(_ids(merged), ['AB-CD', 'stremfin:1']);
    });

    test('no anchors left at all: all at the end, in order', () {
      final merged = kostvMergeAway(
        [_home('a')],
        [_entry('1', after: 'x'), _entry('2', after: 'y'), _entry('1')],
        serverId: 's',
      );
      expect(_ids(merged), ['a', 'stremfin:1', 'stremfin:2']);
    });

    test('for someone with a limit, no explicit ones; those after stay', () {
      final merged = kostvMergeAway(
        [_home('a')],
        [
          _entry('1', after: 'a', explicit: true),
          _entry('2', after: 'stremfin:1'),
        ],
        serverId: 's',
        hideExplicit: true,
      );
      expect(_ids(merged), ['a', 'stremfin:2']);
    });

    test('Jellyfin moves its own among its own', () {
      final list = [_home('a'), away, _home('b')];
      expect(kostvHomeIndexAt(list, 0), 0);
      expect(kostvHomeIndexAt(list, 2), 1);
      expect(kostvAwayOrderIds(list), ['a', 'stremfin:77', 'b']);
    });
  });

  group('playing a playlist', () {
    final list = [_home('a'), away, _home('b')];

    test('«Solo la de casa»: the one not at home doesn\'t sound', () {
      final play = kostvPlaylistToPlay(
        list,
        startIndex: 2,
        catalogAll: false,
        hideExplicit: false,
        dislikes: KostvMusicDislikes.empty,
      );
      expect(_ids(play.tracks), ['a', 'b']);
      expect(play.startIndex, 1);
    });

    test('«Toda la música»: all of it, in its order', () {
      final play = kostvPlaylistToPlay(
        list,
        startIndex: 1,
        catalogAll: true,
        hideExplicit: false,
        dislikes: KostvMusicDislikes.empty,
      );
      expect(_ids(play.tracks), ['a', 'stremfin:77', 'b']);
      expect(play.startIndex, 1);
    });

    test('what the person doesn\'t want is skipped, but the one picked', () {
      final dislikes = KostvMusicDislikes(
        songs: [
          KostvMusicDisliked(id: 'a', name: 'A'),
          KostvMusicDisliked(id: 'stremfin:77', name: 'Lejos', deezerId: '77'),
        ],
      );
      final whole = kostvPlaylistToPlay(
        list,
        picked: false,
        catalogAll: true,
        hideExplicit: false,
        dislikes: dislikes,
      );
      expect(_ids(whole.tracks), ['b']);
      final picked = kostvPlaylistToPlay(
        list,
        startIndex: 1,
        catalogAll: true,
        hideExplicit: false,
        dislikes: dislikes,
      );
      expect(_ids(picked.tracks), ['stremfin:77', 'b']);
      expect(picked.startIndex, 0);
    });

    test('a list with nothing of it plays as it is', () {
      final home = [_home('a'), _home('b')];
      final play = kostvPlaylistToPlay(
        home,
        startIndex: 1,
        dislikes: KostvMusicDislikes.empty,
      );
      expect(identical(play.tracks, home), isTrue);
    });
  });

  test('«Tus favoritas» merges by date, the latest first', () {
    final merged = kostvMergeFavorites(
      [
        _home('a', lastPlayed: '2026-11-20T10:00:00Z'),
        _home('b', lastPlayed: '2026-11-10T10:00:00Z'),
        _home('c'),
      ],
      [
        KostvAwayFavorite(
          song: const KostvAwaySong(deezerId: '1', title: 'Uno'),
          added: DateTime.utc(2026, 11, 21),
        ),
        KostvAwayFavorite(
          song: const KostvAwaySong(deezerId: '2', title: 'Dos'),
          added: DateTime.utc(2026, 11, 15),
        ),
        KostvAwayFavorite(
          song: const KostvAwaySong(
            deezerId: '3',
            title: 'Tres',
            explicit: true,
          ),
          added: DateTime.utc(2026, 11, 1),
        ),
      ],
      serverId: 's',
      hideExplicit: true,
    );
    expect(_ids(merged), ['stremfin:1', 'a', 'stremfin:2', 'b', 'c']);
  });

  group('the store', () {
    test('an old plugin: nothing offered, no playlist asked', () async {
      final server = _Server(hasRoutes: false);
      final store = KostvMusicAwayStore(pluginWith(server));
      await store.load(client);
      expect(store.supported(client), isFalse);
      expect(store.knownMissing(client), isTrue);
      server.asked.clear();
      expect((await store.playlist(client, 'pl')).missing, isTrue);
      expect(server.asked, isEmpty);
    });

    test('a ♥ shows at once and goes back when not kept', () async {
      final server = _Server();
      final store = KostvMusicAwayStore(pluginWith(server));
      await store.load(client);
      expect(store.supported(client), isTrue);
      final done = await store.setFavorite(client, away, on: true);
      expect(done.done, isTrue);
      expect(store.isFavorite(client, '77'), isTrue);
      server.postStatus = 400;
      await store.setFavorite(client, away, on: false);
      final again = await store.setFavorite(client, away, on: true);
      expect(again, (done: false, full: true));
      expect(store.isFavorite(client, '77'), isFalse);
    });

    test('each person\'s own ♥', () async {
      final server = _Server()
        ..favorites.add({'DeezerId': '77', 'Title': 'Lejos'});
      final store = KostvMusicAwayStore(pluginWith(server));
      await store.load(client);
      expect(store.isFavorite(client, '77'), isTrue);
      final luis = person('luis', token: 'other');
      expect(store.isFavorite(luis, '77'), isFalse);
      expect(store.favoritesOf(luis), isEmpty);
    });

    test(
      'an arrival is told once per song and person, and takes its ♥',
      () async {
        final server = _Server()
          ..favorites.add({'DeezerId': '77', 'Title': 'Lejos'});
        final store = KostvMusicAwayStore(pluginWith(server));
        await store.load(client);
        server.asked.clear();
        store.arrived(client, '77', 'j1');
        store.arrived(client, '77', 'j1');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          server.asked.where((a) => a.path.endsWith('/Arrived')),
          hasLength(1),
        );
        expect(store.isFavorite(client, '77'), isFalse);
        // Another person: told again for them.
        final luis = person('luis', token: 'other');
        await store.load(luis);
        store.arrived(luis, '77', 'j1');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          server.asked.where((a) => a.path.endsWith('/Arrived')),
          hasLength(2),
        );
      },
    );
  });

  test('a playlist page\'s songs with those not at home', () async {
    final server = _Server()
      ..entries.add({'DeezerId': '9', 'Title': 'Nueve', 'After': 'a'});
    final store = KostvMusicAwayStore(pluginWith(server));
    final merged = await kostvPlaylistWithAway(client, 'pl', [
      _home('a'),
      _home('b'),
    ], store: store);
    expect(_ids(merged), ['a', 'stremfin:9', 'b']);
    // Not for a playlist of videos.
    final video = await kostvPlaylistWithAway(
      client,
      'pl',
      [_home('a')],
      mediaType: 'Video',
      store: store,
    );
    expect(_ids(video), ['a']);
  });

  group('Kos TV: what the review of it found', () {
    test('«Tus favoritas»: one without a date doesn\'t hold back the rest, '
        'and no more than the limit', () {
      final home = [
        _home('a', lastPlayed: '2026-11-20T10:00:00Z'),
        _home('b', lastPlayed: '2026-11-10T10:00:00Z'),
      ];
      final away = [
        const KostvAwayFavorite(
          song: KostvAwaySong(deezerId: '1', title: 'U'),
        ),
        KostvAwayFavorite(
          song: const KostvAwaySong(deezerId: '2', title: 'D'),
          added: DateTime.utc(2026, 11, 15),
        ),
      ];
      expect(_ids(kostvMergeFavorites(home, away, serverId: 's')), [
        'a',
        'stremfin:2',
        'b',
        'stremfin:1',
      ]);
      expect(_ids(kostvMergeFavorites(home, away, serverId: 's', limit: 3)), [
        'a',
        'stremfin:2',
        'b',
      ]);
      final many = [
        for (var i = 0; i < 100; i++)
          KostvAwayFavorite(
            song: KostvAwaySong(deezerId: '$i', title: 'T$i'),
            added: DateTime.utc(2026, 11, 21),
          ),
      ];
      expect(
        kostvMergeFavorites(home, many, serverId: 's'),
        hasLength(kostvFavoritesShown),
      );
    });

    test('a playlist\'s songs: the plugin is asked at the same time as '
        'Jellyfin', () async {
      final server = _Server()
        ..entries.add({'DeezerId': '9', 'Title': 'Nueve', 'After': 'a'});
      final store = KostvMusicAwayStore(pluginWith(server));
      final home = Completer<List<AggregatedItem>>();
      final songs = kostvPlaylistSongs(client, 'pl', home.future, store: store);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        server.asked.where((a) => a.path.contains('/Away/Playlist/')),
        hasLength(1),
      );
      home.complete([_home('a')]);
      final got = await songs;
      expect(_ids(got.tracks), ['a', 'stremfin:9']);
      expect(got.awayFailed, isFalse);
    });

    test('a plugin that fails: Jellyfin\'s alone, and said; not asked again '
        'for a while, but for «Reintentar»', () async {
      final server = _Server()
        ..playlistStatus = 500
        ..favoritesStatus = 500;
      final store = KostvMusicAwayStore(pluginWith(server));
      Future<KostvPlaylistSongs> read({bool retry = false}) =>
          kostvPlaylistSongs(
            client,
            'pl',
            Future.value([_home('a')]),
            store: store,
            retry: retry,
          );
      final first = await read();
      expect(first.awayFailed, isTrue);
      expect(_ids(first.tracks), ['a']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.asked.clear();
      final again = await read();
      expect(again.awayFailed, isTrue);
      expect(server.asked.where((a) => a.path.contains('/Playlist/')), isEmpty);
      server
        ..playlistStatus = null
        ..entries.add({'DeezerId': '9', 'Title': 'Nueve', 'After': 'a'});
      final retried = await read(retry: true);
      expect(retried.awayFailed, isFalse);
      expect(_ids(retried.tracks), ['a', 'stremfin:9']);
      // A plugin from before it isn't a failure.
      final old = KostvMusicAwayStore(pluginWith(_Server(hasRoutes: false)));
      final plain = await kostvPlaylistSongs(
        client,
        'pl',
        Future.value([_home('a')]),
        store: old,
      );
      expect(plain.awayFailed, isFalse);
    });

    test('a menu doesn\'t wait again for a plugin that just failed', () async {
      final server = _Server()..favoritesStatus = 500;
      final store = KostvMusicAwayStore(pluginWith(server));
      await store.load(client);
      expect(store.down(client), isTrue);
      server.asked.clear();
      await store.load(client);
      expect(server.asked, isEmpty);
      server.favoritesStatus = null;
      await store.load(client, force: true);
      expect(server.asked, hasLength(1));
      expect(store.down(client), isFalse);
    });

    test(
      'an arrival the plugin didn\'t take keeps its ♥ and is told again',
      () async {
        final server = _Server()
          ..favorites.add({'DeezerId': '77', 'Title': 'Lejos'})
          ..arrivedStatus = 500;
        final store = KostvMusicAwayStore(pluginWith(server));
        await store.load(client);
        expect(await store.arrived(client, '77', 'j1'), isFalse);
        expect(store.isFavorite(client, '77'), isTrue);
        server.arrivedStatus = null;
        expect(await store.arrived(client, '77', 'j1'), isTrue);
        expect(store.isFavorite(client, '77'), isFalse);
        // Told once it was taken.
        expect(await store.arrived(client, '77', 'j1'), isFalse);
        expect(
          server.asked.where((a) => a.path.endsWith('/Arrived')),
          hasLength(2),
        );
      },
    );

    test('which playlists may be changed, and a refusal said', () async {
      final server = _Server()..editable = ['abcd'];
      final store = KostvMusicAwayStore(pluginWith(server));
      expect(await store.editable(client, ['AB-CD', 'ef']), {'abcd'});
      expect(server.asked.last.body, {
        'Ids': ['AB-CD', 'ef'],
      });
      expect(await store.canEdit(client, 'AB-CD'), isTrue);
      expect(await store.canEdit(client, 'ef'), isFalse);
      server.deleteStatus = 403;
      expect(
        await store.removeFromPlaylist(client, 'pl', '77'),
        KostvAwayEdit.forbidden,
      );
      server.postStatus = 403;
      expect(await store.order(client, 'pl', [away]), KostvAwayEdit.forbidden);
      server
        ..deleteStatus = 500
        ..postStatus = null;
      expect(
        await store.removeFromPlaylist(client, 'pl', '77'),
        KostvAwayEdit.failed,
      );
      expect(await store.order(client, 'pl', [away]), KostvAwayEdit.done);
      // A plugin from before it: not known.
      final old = KostvMusicAwayStore(pluginWith(_Server(hasRoutes: false)));
      expect(await old.canEdit(client, 'ef'), isNull);
    });
  });
}
