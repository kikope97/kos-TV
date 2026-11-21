import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_catalog.dart';
import 'package:moonfin/data/services/kostv_music_dislikes.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/music/kostv_music_actions.dart';
import 'package:moonfin/ui/screens/music/kostv_music_dislike.dart';
import 'package:moonfin/ui/screens/music/kostv_stream_widgets.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:moonfin/ui/widgets/music/music_navigation.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/stremfin/fake_stremfin_adapter.dart';

const _server = 'https://casa.example';

/// A player whose songs that aren't at home take as long as [ready] says.
class _Manager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();

  Completer<void> ready = Completer<void>();
  final played = <List<String>>[];

  // playItems, whatever it is asked with.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #playItems) {
      final items = invocation.positionalArguments.first as List;
      played.add([for (final item in items) (item as AggregatedItem).id]);
      return ready.future;
    }
    return super.noSuchMethod(invocation);
  }
}

/// The plugin: «No me gusta» (one song that isn't at home, answered after
/// [dislikesDelay]) and Settings (without `Catalog` when [older]).
class _Plugin implements HttpClientAdapter {
  bool older = false;
  Duration dislikesDelay = Duration.zero;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ResponseBody json(Object value) => ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    final path = options.uri.path;
    if (path.endsWith('/Dislikes')) {
      await Future<void>.delayed(dislikesDelay);
      return json({
        'Songs': [
          {'Id': null, 'DeezerId': '2', 'Name': 'Dos', 'Artist': 'Rayo'},
        ],
        'Artists': const [],
      });
    }
    if (path.endsWith('/Settings')) {
      return json({'Learn': true, if (!older) 'Catalog': 'all'});
    }
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

AggregatedItem _away(String id) => kostvStreamItem(
  deezerId: id,
  title: 'Canción $id',
  serverId: _server,
  artist: 'Rayo',
);

/// Kos TV: the Music pages' lock is let go while a song that isn't at home
/// is got ready; what the person doesn't want to hear is read before a list
/// plays; the album pill's «Pedido» is each person's; and with a plugin
/// from before «Toda la música», no «No me gusta» for what isn't at home.
void main() {
  late _Manager manager;
  late _Plugin plugin;
  late JellyfinMediaServerClient client;
  late UserPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    await prefs.set(UserPreferences.kostvMusicCatalogAll, true);
    plugin = _Plugin();
    final musicPlugin = KostvMusicPlugin(
      dio: Dio()..httpClientAdapter = plugin,
    );
    KostvMusicPlugin.instance = musicPlugin;
    KostvMusicDislikesStore.instance = KostvMusicDislikesStore(musicPlugin);
    KostvMusicCatalog.instance = KostvMusicCatalog(
      prefs: () => prefs,
      plugin: () => musicPlugin,
    );
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
    manager = _Manager();
    GetIt.instance
      ..registerSingleton<PlaybackManager>(manager)
      ..registerSingleton<MediaServerClient>(client);
  });

  tearDown(() async {
    KostvNowPlaying.instance.debugReset();
    KostvMusicPlugin.instance = KostvMusicPlugin();
    KostvMusicDislikesStore.instance = KostvMusicDislikesStore();
    KostvMusicCatalog.instance = KostvMusicCatalog();
    KostvStreamAlbums.debugReset();
    await GetIt.instance.reset();
  });

  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext context;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
        GoRoute(path: '/player/audio', builder: (_, _) => const SizedBox()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    return context;
  }

  testWidgets('a song that isn\'t at home being got ready doesn\'t hold the '
      'Music pages: another one can be picked meanwhile', (tester) async {
    final context = await host(tester);
    var done = false;
    unawaited(
      kostvMusicOnce(() => playMusicTracks(context, [_away('1')]))
          .then((_) => done = true),
    );
    await tester.pump();
    expect(manager.played, [
      ['stremfin:1'],
    ]);
    // Still getting it ready, and free already.
    expect(done, isTrue);
    var again = false;
    await kostvMusicOnce(() async => again = true);
    expect(again, isTrue);
    manager.ready.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a list played whole waits for the «No me gusta» list rather '
      'than taking it as empty', (tester) async {
    plugin.dislikesDelay = const Duration(milliseconds: 300);
    final context = await host(tester);
    manager.ready.complete();
    unawaited(
      playKostvSongList(context, const [
        StremfinSong(title: 'Uno', deezerId: '1', artist: 'Rayo'),
        StremfinSong(title: 'Dos', deezerId: '2', artist: 'Rayo'),
        StremfinSong(title: 'Tres', deezerId: '3', artist: 'Rayo'),
      ], picked: false),
    );
    for (var i = 0; i < 20 && manager.played.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(manager.played, [
      ['stremfin:1', 'stremfin:3'],
    ]);
  });

  test('with a plugin from before «Toda la música», no «No me gusta» for a '
      'song that isn\'t at home (it would turn it down every time)', () async {
    final home = AggregatedItem(
      id: 'h1',
      serverId: _server,
      rawData: const {'Id': 'h1', 'Name': 'Casa', 'Type': 'Audio'},
    );
    await KostvMusicDislikesStore.instance.load(client);
    await KostvMusicCatalog.instance.refresh(client);
    expect(kostvMusicCanDislike(_away('1')), isTrue);
    expect(kostvMusicCanDislike(home), isTrue);
    plugin.older = true;
    await KostvMusicCatalog.instance.refresh(client);
    expect(kostvMusicCanDislike(_away('1')), isFalse);
    // What is at home, and the artists, as before.
    expect(kostvMusicCanDislike(home), isTrue);
    expect(kostvMusicCanDislike(), isTrue);
  });

  test('the album of a song that isn\'t at home, as one person asked for it, '
      'isn\'t the next person\'s', () async {
    final service = StremfinService(
      StremfinClient(
        dio: Dio()
          ..httpClientAdapter = FakeStremfinAdapter(
            (path, _) => (
              status: path == '/music/albums/al1' ? 200 : 404,
              body: {
                'deezer_id': 'al1',
                'title': 'Tormenta',
                'request': {'id': 3, 'status': 'pending', 'mine': true},
              },
              headers: const {},
            ),
          ),
        baseUrl: 'https://requests.example.org/api/v1',
        token: () => 'token',
      ),
      watchLifecycle: false,
    );
    GetIt.instance.registerSingleton<StremfinService>(service);
    service.onUserChanged('ana');
    expect((await KostvStreamAlbums.read('al1'))?.request, isNotNull);
    expect(KostvStreamAlbums.known('al1'), isNotNull);
    service.onUserChanged('luis');
    expect(KostvStreamAlbums.known('al1'), isNull);
    service.dispose();
  });
}
