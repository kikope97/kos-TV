import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_away.dart';
import 'package:moonfin/data/services/kostv_music_catalog.dart';
import 'package:moonfin/data/services/kostv_music_dislikes.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/item_detail_screen.dart'
    show DetailTrackList;
import 'package:moonfin/ui/screens/music/kostv_music_actions.dart';
import 'package:moonfin/ui/screens/music/kostv_music_away_actions.dart';
import 'package:moonfin/ui/screens/music/kostv_stream_widgets.dart'
    show KostvStreamMark;
import 'package:moonfin/util/platform_detection.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: «Añadir a una lista» and ♥ of songs that aren't at home, and
/// those songs in a playlist's page (plan section 8).

const _server = 'https://casa.example';

/// The plugin: with [hasRoutes] false, one from before the routes (404).
class _Plugin implements HttpClientAdapter {
  _Plugin({this.hasRoutes = true});

  final bool hasRoutes;
  final posted = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (options.method == 'POST') posted.add(path);
    if (path.endsWith('/Dislikes')) {
      return _json({'Songs': const [], 'Artists': const []});
    }
    if (path.contains('/Away/')) {
      if (!hasRoutes) return ResponseBody.fromString('', 404);
      if (options.method == 'GET') return _json({'Songs': const []});
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

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

AggregatedItem _away({bool explicit = false}) => kostvStreamItem(
  deezerId: '77',
  title: 'Lejos',
  serverId: _server,
  artist: 'Rayo',
  album: 'Tormenta',
  albumDeezerId: 'al77',
  artistDeezerId: 'ar1',
  explicit: explicit,
)..rawData['PlaylistItemId'] = 'stremfin:77';

AggregatedItem _home(String id) => AggregatedItem(
  id: id,
  serverId: _server,
  rawData: {
    'Id': id,
    'Name': 'Casa $id',
    'Type': 'Audio',
    'PlaylistItemId': 'entry-$id',
  },
);

void main() {
  late UserPreferences prefs;
  late JellyfinMediaServerClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
    KostvMusicCatalog.instance = KostvMusicCatalog(prefs: () => prefs);
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
    GetIt.instance.registerSingleton<MediaServerClient>(client);
  });

  tearDown(() async {
    KostvMusicCatalog.instance = KostvMusicCatalog();
    KostvMusicDislikesStore.instance = KostvMusicDislikesStore();
    KostvMusicAwayStore.instance = KostvMusicAwayStore();
    await GetIt.instance.reset();
  });

  Future<_Plugin> plugin(WidgetTester tester, {bool hasRoutes = true}) async {
    final server = _Plugin(hasRoutes: hasRoutes);
    final music = KostvMusicPlugin(dio: Dio()..httpClientAdapter = server);
    KostvMusicDislikesStore.instance = KostvMusicDislikesStore(music);
    final away = KostvMusicAwayStore(music);
    KostvMusicAwayStore.instance = away;
    await tester.runAsync(() => away.load(client));
    return server;
  }

  group('the menu of a song that is not at home', () {
    late BuildContext context;

    Future<void> open(WidgetTester tester, Future<void> menu) async {
      unawaited(menu);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
    }

    Future<void> host(WidgetTester tester) => tester.pumpWidget(
      _app(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    testWidgets('with the plugin: ♥ and «Añadir a una lista»', (tester) async {
      await prefs.set(UserPreferences.kostvMusicCatalogAll, true);
      await plugin(tester);
      await host(tester);
      await open(tester, showKostvMusicSongMenu(context, item: _away()));
      expect(find.text('Me gusta'), findsOneWidget);
      expect(find.text('Añadir a una lista'), findsOneWidget);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    });

    testWidgets('with a plugin from before it: neither', (tester) async {
      await prefs.set(UserPreferences.kostvMusicCatalogAll, true);
      await plugin(tester, hasRoutes: false);
      await host(tester);
      await open(tester, showKostvMusicSongMenu(context, item: _away()));
      expect(find.text('Me gusta'), findsNothing);
      expect(find.text('Añadir a una lista'), findsNothing);
      expect(find.text('Crear emisora'), findsOneWidget);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    });

    testWidgets('♥ from the menu keeps it, without asking for the album', (
      tester,
    ) async {
      await prefs.set(UserPreferences.kostvMusicCatalogAll, true);
      final server = await plugin(tester);
      await host(tester);
      await open(tester, showKostvMusicSongMenu(context, item: _away()));
      await tester.tap(find.text('Me gusta'));
      // Kos TV: the notice says it went to the favourites (looked for
      // before its seconds run out).
      final loved = find.text(
        'Añadida a tus favoritas. ¿Pedir el álbum para tenerla en casa?',
      );
      for (var i = 0; i < 30 && loved.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(loved, findsOneWidget);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      // Only the ♥: no album asked for.
      expect(server.posted, ['/Moonfin/Kostv/Music/Away/Favorites']);
      expect(KostvMusicAwayStore.instance.isFavorite(client, '77'), isTrue);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('the notice after it offers the album', (tester) async {
      await host(tester);
      kostvAwayOfferAlbum(context, _away(), done: 'Hecho');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Añadida a la lista. ¿Pedir el álbum para tenerla en casa?'),
        findsOneWidget,
      );
      expect(find.text('Pedir álbum'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      // One without an album to ask for: just what was done.
      kostvAwayOfferAlbum(
        context,
        kostvStreamItem(deezerId: '5', title: 'Sin disco', serverId: _server),
        done: 'Hecho',
      );
      await tester.pump();
      expect(find.text('Hecho'), findsOneWidget);
    });

    testWidgets('a playlist with nothing that sounds says why', (tester) async {
      await prefs.set(UserPreferences.kostvMusicCatalogAll, false);
      await host(tester);
      kostvAwaySayNothingToPlay(context, [_away()]);
      await tester.pump();
      expect(
        find.text(
          'Ninguna de estas canciones está en casa: con «Solo la de casa» no '
          'suenan',
        ),
        findsOneWidget,
      );
      await prefs.set(UserPreferences.kostvMusicCatalogAll, true);
      kostvAwaySayNothingToPlay(context, [_home('a')]);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('No se encontraron elementos'), findsOneWidget);
    });

    testWidgets('from a playlist, its own actions', (tester) async {
      await prefs.set(UserPreferences.kostvMusicCatalogAll, false);
      await plugin(tester);
      await host(tester);
      var removed = false;
      await open(
        tester,
        showKostvMusicSongMenu(
          context,
          item: _away(),
          listActions: KostvAwayListActions(remove: () => removed = true),
        ),
      );
      // «Solo la de casa»: it doesn't offer to play it.
      expect(find.text('Reproducir a continuación'), findsNothing);
      await tester.tap(find.text('Eliminar de la lista de reproducción'));
      await tester.pumpAndSettle();
      expect(removed, isTrue);
    });
  });

  group('a playlist\'s page', () {
    Future<List<int>> list(WidgetTester tester) async {
      final played = <int>[];
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: DetailTrackList(
              tracks: [_home('a'), _away()],
              isPlaylist: true,
              getFocusNode: (id) => FocusNode(debugLabel: id),
              onPlayTrack: played.add,
            ),
          ),
        ),
      );
      await tester.pump();
      return played;
    }

    testWidgets('the cloud on the song not at home; it plays', (tester) async {
      await prefs.set(UserPreferences.kostvMusicCatalogAll, true);
      final played = await list(tester);
      expect(find.byType(KostvStreamMark), findsOneWidget);
      await tester.tap(find.text('Lejos'));
      await tester.pump();
      expect(played, [1]);
    });

    testWidgets('«Solo la de casa»: in grey, and a press says why', (
      tester,
    ) async {
      await prefs.set(UserPreferences.kostvMusicCatalogAll, false);
      final played = await list(tester);
      await tester.tap(find.text('Lejos'));
      await tester.pump();
      expect(played, isEmpty);
      expect(
        find.text('No está en casa: con «Solo la de casa» no suena'),
        findsOneWidget,
      );
      final grey = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('Lejos'), matching: find.byType(Opacity))
            .first,
      );
      expect(grey.opacity, lessThan(1));
    });

    testWidgets('on the TV, OK on it plays it', (tester) async {
      PlatformDetection.setTvMode(true);
      addTearDown(() => PlatformDetection.setTvMode(false));
      await prefs.set(UserPreferences.kostvMusicCatalogAll, true);
      final nodes = <String, FocusNode>{};
      final played = <int>[];
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: DetailTrackList(
              tracks: [_home('a'), _away()],
              isPlaylist: true,
              getFocusNode: (id) => nodes.putIfAbsent(id, FocusNode.new),
              onPlayTrack: played.add,
            ),
          ),
        ),
      );
      nodes['entry-a']!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(nodes['stremfin:77']!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 50));
      expect(played, [1]);
      for (final node in nodes.values) {
        node.dispose();
      }
    });
  });
}
