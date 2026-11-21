import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/kostv_music_catalog.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/settings/settings_side_panel.dart';
import 'package:moonfin/util/kostv_server.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The plugin's Settings, with `Catalog` ([catalog]) or as one from before
/// it (no `Catalog`, and a 400 when it is sent alone), and its Event.
class _Plugin implements HttpClientAdapter {
  _Plugin({this.knowsCatalog = true, this.knowsStreamListen = true});

  final bool knowsCatalog;
  final bool knowsStreamListen;
  var catalog = 'all';
  final sent = <({String route, Object? body})>[];

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
    final route = '${options.method} ${options.uri.path}';
    sent.add((route: route, body: body));
    ResponseBody json(Object value) => ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
    Map<String, Object?> settings() => {
      'Learn': true,
      'Listens': 3,
      'Since': null,
      if (knowsCatalog) 'Catalog': catalog,
    };
    switch (route) {
      case 'GET /Moonfin/Kostv/Music/Settings':
        return json(settings());
      case 'POST /Moonfin/Kostv/Music/Settings':
        final map = body as Map;
        if (!knowsCatalog && !map.containsKey('Learn')) {
          return ResponseBody.fromString('{"Error":"Learn"}', 400);
        }
        if (map['Catalog'] is String) catalog = map['Catalog'] as String;
        return json(settings());
      case 'POST /Moonfin/Kostv/Music/Event':
        if ((body as Map)['Type'] == 'stream_listen' && !knowsStreamListen) {
          return ResponseBody.fromString('', 404);
        }
        return ResponseBody.fromString('', 204);
    }
    return ResponseBody.fromString('', 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Plugin plugin;
  late UserPreferences prefs;
  late JellyfinMediaServerClient client;

  Future<void> setUpWith(_Plugin routes) async {
    plugin = routes;
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
    KostvMusicPlugin.instance = KostvMusicPlugin(
      dio: Dio()..httpClientAdapter = plugin,
    );
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
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    KostvMusicCatalog.instance.debugReset();
  }

  tearDown(() async {
    await GetIt.instance.reset();
    KostvMusicPlugin.instance = KostvMusicPlugin();
    KostvMusicCatalog.instance.debugReset();
    KostvRequestsAddress.reset();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(children: const [KostvMusicLearnSection()]),
        ),
      ),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String option) async {
    await tester.tap(find.text('Qué música enseñar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pump();
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  testWidgets('«Qué música enseñar», all of it by default, kept by the '
      'plugin for the person', (tester) async {
    await tester.runAsync(() => setUpWith(_Plugin()));
    KostvRequestsAddress.reset(value: 'https://requests.example.org');
    await show(tester);
    expect(find.text('Qué música enseñar'), findsOneWidget);
    expect(find.text('Toda la música'), findsOneWidget);
    expect(kostvMusicCatalogAll(), isTrue);
    await pick(tester, 'Solo la de casa');
    expect(plugin.sent.last.body, {'Catalog': 'home'});
    expect(plugin.catalog, 'home');
    expect(kostvMusicCatalogAll(), isFalse);
    // Kos TV: kept on the device too, as the person's last known choice.
    expect(prefs.get(UserPreferences.kostvMusicCatalogAll), isFalse);
    expect(find.text('Solo la de casa'), findsOneWidget);
  });

  testWidgets('a plugin from before it: the device keeps it', (tester) async {
    await tester.runAsync(() => setUpWith(_Plugin(knowsCatalog: false)));
    KostvRequestsAddress.reset(value: 'https://requests.example.org');
    await show(tester);
    expect(KostvMusicCatalog.instance.keptByServer, isFalse);
    await pick(tester, 'Solo la de casa');
    expect(plugin.sent.where((s) => s.route.startsWith('POST')), isEmpty);
    expect(prefs.get(UserPreferences.kostvMusicCatalogAll), isFalse);
    expect(kostvMusicCatalogAll(), isFalse);
  });

  testWidgets('without the requests service there is nothing to choose', (
    tester,
  ) async {
    await tester.runAsync(() => setUpWith(_Plugin()));
    await show(tester);
    expect(find.text('Qué música enseñar'), findsNothing);
    expect(find.text('Aprender de lo que escucho'), findsOneWidget);
  });

  test('setCatalog with a plugin from before it (400) keeps nothing', () async {
    await setUpWith(_Plugin(knowsCatalog: false));
    expect(await KostvMusicPlugin.instance.setCatalog(client, 'home'), isNull);
    // Still there for everything else.
    expect(KostvMusicPlugin.instance.knownMissing(client, 'Settings'), isFalse);
  });

  test('stream_listen: what was heard; a plugin that doesn\'t know it (404) '
      'keeps the route for the other events', () async {
    await setUpWith(_Plugin(knowsStreamListen: false));
    final told = await KostvMusicPlugin.instance.sendStreamListen(
      client,
      deezerId: '3135556',
      title: 'Harder',
      artist: 'Daft Punk',
      album: 'Discovery',
      played: 123.456,
      duration: 224,
      endedBy: 'natural',
      source: 'search',
      shuffle: true,
    );
    expect(told, isFalse);
    expect(plugin.sent.single.body, {
      'Type': 'stream_listen',
      'DeezerId': '3135556',
      'Title': 'Harder',
      'Artist': 'Daft Punk',
      'Album': 'Discovery',
      'Played': 123.5,
      'Duration': 224,
      'EndedBy': 'natural',
      'Source': 'search',
      'Shuffle': true,
    });
    expect(KostvMusicPlugin.instance.knownMissing(client, 'Event'), isFalse);
  });

  test('Kos TV: read as the person signs in, and kept on the device, so «Solo '
      'la de casa» applies from the start', () async {
    await setUpWith(_Plugin()..catalog = 'home');
    expect(kostvMusicCatalogAll(), isTrue);
    kostvReadMusicCatalog(client);
    await pumpEventQueue();
    expect(kostvMusicCatalogAll(), isFalse);
    expect(prefs.get(UserPreferences.kostvMusicCatalogAll), isFalse);
    // The app opened again: before the plugin answers, the last known.
    final fresh = KostvMusicCatalog(prefs: () => prefs);
    expect(fresh.all, isFalse);
  });

  test('Kos TV: what the plugin says of someone else isn\'t kept on this '
      'person\'s device', () async {
    await setUpWith(_Plugin()..catalog = 'home');
    final other =
        JellyfinMediaServerClient(
            baseUrl: 'https://casa.example',
            deviceInfo: const DeviceInfo(
              id: 'device',
              name: 'Device',
              appName: 'kOS TV',
              appVersion: '1.0.0',
            ),
          )
          ..accessToken = 'token-luis'
          ..userId = 'luis';
    await KostvMusicCatalog.instance.refresh(other);
    expect(prefs.get(UserPreferences.kostvMusicCatalogAll), isTrue);
    expect(kostvMusicCatalogAll(), isTrue);
  });

  test('Kos TV: a plugin from before «Toda la música» is told apart (its '
      '«No me gusta» of what isn\'t at home is hidden)', () async {
    await setUpWith(_Plugin(knowsCatalog: false));
    expect(KostvMusicCatalog.instance.olderPlugin, isFalse);
    await KostvMusicCatalog.instance.refresh(client);
    expect(KostvMusicCatalog.instance.olderPlugin, isTrue);
    KostvMusicCatalog.instance.take(
      const KostvMusicLearnState(learn: true, catalog: 'all'),
      client,
    );
    expect(KostvMusicCatalog.instance.olderPlugin, isFalse);
  });
}
