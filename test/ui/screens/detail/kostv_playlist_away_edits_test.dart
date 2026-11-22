import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/tmdb_repository.dart';
import 'package:moonfin/data/services/kostv_music_away.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/user_data_sync.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PluginSyncService extends Mock implements PluginSyncService {}

/// Kos TV: a playlist with songs that aren't at home: its changes go one
/// after the other, what followed a song taken out keeps its place, a
/// playlist the person can't change doesn't offer it, and one whose songs
/// that aren't at home couldn't be read says so.

/// Jellyfin: the playlist «pl» with the songs a and b.
class _Jellyfin extends Interceptor {
  final songs = <String>['a', 'b'];
  int reads = 0;
  final moves = <String>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    Object? data = <String, Object?>{};
    if (options.method == 'GET' && path == '/Users/ana/Items/pl') {
      data = {
        'Id': 'pl',
        'Type': 'Playlist',
        'Name': 'Lista',
        'MediaType': 'Audio',
      };
    } else if (options.method == 'GET' && path == '/Playlists/pl/Items') {
      reads++;
      data = {
        'Items': [
          for (final id in songs)
            {
              'Id': id,
              'Name': 'Casa $id',
              'Type': 'Audio',
              'PlaylistItemId': 'e$id',
            },
        ],
      };
    } else if (options.method == 'DELETE' && path == '/Playlists/pl/Items') {
      final entry = options.queryParameters['EntryIds']?.toString() ?? '';
      songs.removeWhere((id) => 'e$id' == entry);
    } else if (path.contains('/Move/')) {
      moves.add(path);
    }
    handler.resolve(
      Response(requestOptions: options, statusCode: 200, data: data),
    );
  }
}

/// The plugin: the song «9» after a, which playlists may be changed, and
/// the orders it is told (each answered when [orderGate] says).
class _Plugin implements HttpClientAdapter {
  List<String> editable = ['pl'];
  int playlistStatus = 200;
  int orderStatus = 204;
  final orders = <List<Object?>>[];
  Future<void> Function(int call)? orderGate;

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
    if (path.endsWith('/Away/Favorites')) return _json({'Songs': const []});
    if (path.endsWith('/Away/Playlists/Editable')) {
      return _json({'Ids': editable});
    }
    if (path.endsWith('/Away/Playlist/pl/Order')) {
      final call = orders.length;
      orders.add((body as Map)['Ids'] as List);
      await orderGate?.call(call);
      return ResponseBody.fromString('', orderStatus);
    }
    if (options.method == 'GET' && path.endsWith('/Away/Playlist/pl')) {
      if (playlistStatus != 200) {
        return ResponseBody.fromString('', playlistStatus);
      }
      return _json({
        'Entries': [
          {'DeezerId': '9', 'Title': 'Nueve', 'After': 'a'},
        ],
      });
    }
    return ResponseBody.fromString('', 204);
  }

  ResponseBody _json(Object data) => ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Jellyfin jellyfin;
  late _Plugin plugin;
  late JellyfinMediaServerClient client;

  setUp(() async {
    await GetIt.instance.reset();
    userDataSync.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance
      ..registerSingleton<UserPreferences>(UserPreferences(store))
      ..registerSingleton<PluginSyncService>(_PluginSyncService());
    jellyfin = _Jellyfin();
    plugin = _Plugin();
    client =
        JellyfinMediaServerClient(
            baseUrl: 'https://casa.example',
            deviceInfo: const DeviceInfo(
              id: 'device',
              name: 'Device',
              appName: 'kOS TV',
              appVersion: '1.0.0',
            ),
            interceptors: [jellyfin],
          )
          ..accessToken = 'token'
          ..userId = 'ana';
    KostvMusicAwayStore.instance = KostvMusicAwayStore(
      KostvMusicPlugin(dio: Dio()..httpClientAdapter = plugin),
    );
  });

  tearDown(() async {
    KostvMusicAwayStore.instance = KostvMusicAwayStore();
    userDataSync.reset();
    await GetIt.instance.reset();
  });

  Future<ItemDetailViewModel> open() async {
    final tmdb = TmdbRepository(client);
    final vm = ItemDetailViewModel(
      itemId: 'pl',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, tmdb),
      tmdbRepository: tmdb,
    );
    addTearDown(vm.dispose);
    await vm.load();
    for (var i = 0; i < 100 && vm.tracks.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return vm;
  }

  List<String> ids(ItemDetailViewModel vm) => [for (final t in vm.tracks) t.id];

  test('the list, with the song not at home in its place', () async {
    final vm = await open();
    expect(ids(vm), ['a', 'stremfin:9', 'b']);
    expect(vm.canManagePlaylistTracks, isTrue);
  });

  test('a song at home taken out: the plugin is told the order without '
      'it', () async {
    final vm = await open();
    await vm.removeTrackFromPlaylist(vm.tracks.first);
    expect(jellyfin.songs, ['b']);
    expect(plugin.orders.single, ['stremfin:9', 'b']);
  });

  test('a playlist the person can\'t change doesn\'t offer it', () async {
    plugin.editable = const [];
    final vm = await open();
    expect(vm.canManagePlaylistTracks, isFalse);
  });

  test('a refusal says so, puts the list back and takes the changes '
      'away', () async {
    // Taken for one that may be changed, but the plugin refuses it.
    plugin.orderStatus = 403;
    final vm = await open();
    final failures = <DetailActionFailure>[];
    vm.onActionFailed = failures.add;
    await vm.reorderPlaylistTrack(1, 0);
    expect(failures, [DetailActionFailure.playlistNotAllowed]);
    expect(ids(vm), ['a', 'stremfin:9', 'b']);
    expect(vm.canManagePlaylistTracks, isFalse);
  });

  test('moves made one after the other reach the plugin in their order, '
      'and the list is read again once', () async {
    final vm = await open();
    final first = Completer<void>();
    plugin.orderGate = (call) => call == 0 ? first.future : Future.value();
    final readsBefore = jellyfin.reads;
    // The song not at home down twice, quickly.
    final one = vm.reorderPlaylistTrack(1, 2);
    final two = vm.reorderPlaylistTrack(2, 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // The second waits for the first.
    expect(plugin.orders, hasLength(1));
    expect(ids(vm), ['a', 'stremfin:9', 'b']);
    first.complete();
    await Future.wait([one, two]);
    expect(plugin.orders, [
      ['a', 'b', 'stremfin:9'],
      ['a', 'stremfin:9', 'b'],
    ]);
    expect(jellyfin.reads - readsBefore, 1);
    expect(ids(vm), ['a', 'stremfin:9', 'b']);
  });

  test('the songs not at home couldn\'t be read: said, and «Reintentar» '
      'reads them', () async {
    plugin.playlistStatus = 500;
    var said = 0;
    final tmdb = TmdbRepository(client);
    final vm = ItemDetailViewModel(
      itemId: 'pl',
      client: client,
      mutations: ItemMutationRepository(client),
      mdbListRepository: MdbListRepository(client, tmdb),
      tmdbRepository: tmdb,
    )..onAwayFailed = () => said++;
    addTearDown(vm.dispose);
    await vm.load();
    for (var i = 0; i < 100 && said == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(said, 1);
    expect(ids(vm), ['a', 'b']);
    plugin.playlistStatus = 200;
    await vm.retryAwayTracks();
    expect(ids(vm), ['a', 'stremfin:9', 'b']);
    expect(said, 1);
  });
}
