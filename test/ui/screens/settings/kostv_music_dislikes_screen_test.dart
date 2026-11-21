import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_dislikes.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/music/kostv_music_actions.dart';
import 'package:moonfin/ui/screens/music/kostv_music_dislike.dart';
import 'package:moonfin/ui/screens/settings/settings_side_panel.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

/// The plugin's Settings and «No me gusta» routes, kept as a server would;
/// [dislikes] false is a plugin from before them.
class _Plugin implements HttpClientAdapter {
  _Plugin({this.dislikes = true});

  final bool dislikes;
  final songs = <Map<String, Object?>>[
    {'Id': 's1', 'Name': 'Verano', 'Artist': 'Lola Brisa'},
    {'Id': 's2', 'Name': 'Noche', 'Artist': 'Nube Roja'},
  ];
  final artists = <Map<String, Object?>>[
    {'Id': 'a8', 'Name': 'Tres Lunas'},
  ];
  final asked = <String>[];

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
    asked.add(key);
    const base = '/Moonfin/Kostv/Music';
    if (key == 'GET $base/Settings') {
      return _json({'Learn': false, 'Listens': 0});
    }
    if (!dislikes) return ResponseBody.fromString('', 404);
    if (key == 'GET $base/Dislikes') {
      return _json({'Songs': songs, 'Artists': artists});
    }
    if (key == 'DELETE $base/Dislikes') {
      songs.clear();
      artists.clear();
      return ResponseBody.fromString('', 204);
    }
    if (key.startsWith('DELETE $base/Dislikes/')) {
      final id = key.split('/').last;
      songs.removeWhere((s) => s['Id'] == id);
      artists.removeWhere((a) => a['Id'] == id);
      return ResponseBody.fromString('', 204);
    }
    if (key == 'POST $base/Event') {
      final event = body as Map;
      for (final id in event['ItemIds'] as List) {
        (event['Kind'] == 'artist' ? artists : songs).insert(0, {
          'Id': id,
          'Name': 'Nombre $id',
        });
      }
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

void main() {
  late _Plugin plugin;

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    bool dislikes = true,
  }) async {
    plugin = _Plugin(dislikes: dislikes);
    KostvMusicPlugin.instance = KostvMusicPlugin(
      dio: Dio()..httpClientAdapter = plugin,
    );
    KostvMusicDislikesStore.instance = KostvMusicDislikesStore();
    GetIt.instance.registerSingleton<MediaServerClient>(
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
        ..userId = 'ana',
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  /// Lets what was asked land, without running out the notice's seconds
  /// (pumpAndSettle would).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  tearDown(() async {
    await GetIt.instance.reset();
    KostvMusicPlugin.instance = KostvMusicPlugin();
    KostvMusicDislikesStore.instance = KostvMusicDislikesStore();
  });

  group('Settings > Música', () {
    testWidgets('«Lo que no quieres oír» next to what is learnt, with how '
        'much is in it, even with «Aprender» off', (tester) async {
      await show(
        tester,
        Scaffold(body: ListView(children: const [KostvMusicLearnSection()])),
      );
      expect(find.text('Lo que no quieres oír'), findsOneWidget);
      expect(find.text('2 canciones · 1 artista'), findsOneWidget);
    });

    testWidgets('a plugin from before it: not there', (tester) async {
      await show(
        tester,
        Scaffold(body: ListView(children: const [KostvMusicLearnSection()])),
        dislikes: false,
      );
      expect(find.text('Aprender de lo que escucho'), findsOneWidget);
      expect(find.text('Lo que no quieres oír'), findsNothing);
    });
  });

  group('the list', () {
    testWidgets('says what it does, with the songs and the artists', (
      tester,
    ) async {
      await show(tester, const KostvMusicDislikesScreen());
      expect(
        find.textContaining('Solo cambia lo que suena solo'),
        findsOneWidget,
      );
      expect(
        find.textContaining('«Borrar lo que he escuchado» no lo borra'),
        findsOneWidget,
      );
      expect(find.text('Canciones'), findsOneWidget);
      expect(find.text('Verano'), findsOneWidget);
      expect(find.text('Lola Brisa'), findsOneWidget);
      expect(find.text('Artistas'), findsOneWidget);
      expect(find.text('Tres Lunas'), findsOneWidget);
      expect(find.text('Vaciar la lista'), findsOneWidget);
    });

    testWidgets('one taken off, and put back with «Deshacer»', (tester) async {
      await show(tester, const KostvMusicDislikesScreen());
      await tester.tap(find.text('Verano'));
      await settle(tester);
      expect(plugin.asked, contains('DELETE /Moonfin/Kostv/Music/Dislikes/s1'));
      expect(find.text('Verano'), findsNothing);
      expect(find.text('«Verano» puede volver a sonar'), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await settle(tester);
      expect(plugin.asked.last, 'POST /Moonfin/Kostv/Music/Event');
      expect(plugin.songs.first['Id'], 's1');
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('emptied, only after asking', (tester) async {
      await show(tester, const KostvMusicDislikesScreen());
      await tester.tap(find.text('Vaciar la lista'));
      await tester.pumpAndSettle();
      expect(find.text('¿Vaciar la lista?'), findsOneWidget);
      await tester.tap(find.text('Vaciar'));
      await settle(tester);
      expect(plugin.asked, contains('DELETE /Moonfin/Kostv/Music/Dislikes'));
      expect(find.text('Verano'), findsNothing);
      expect(find.textContaining('Aún no hay nada'), findsOneWidget);
    });
  });

  testWidgets('«No me gusta» of a song: five seconds to take it back', (
    tester,
  ) async {
    final song = AggregatedItem(
      id: 's9',
      serverId: '',
      rawData: const {'Id': 's9', 'Name': 'Fuego', 'Type': 'Audio'},
    );
    await show(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => kostvDislikeSong(context, song),
            child: const Text('No me gusta'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('No me gusta'));
    await settle(tester);
    expect(plugin.songs.first['Id'], 's9');
    expect(find.text('«Fuego» ya no saldrá en tus mezclas'), findsOneWidget);
    await tester.tap(find.text('Deshacer'));
    await settle(tester);
    expect(plugin.asked.last, 'DELETE /Moonfin/Kostv/Music/Dislikes/s9');
    expect(plugin.songs.any((s) => s['Id'] == 's9'), isFalse);
    await tester.pump(const Duration(seconds: 6));
  });

  group('a song\'s menu', () {
    final song = AggregatedItem(
      id: 's7',
      serverId: '',
      rawData: const {
        'Id': 's7',
        'Name': 'Luna',
        'Type': 'Audio',
        'AlbumArtists': [
          {'Id': 'a1', 'Name': 'Lola Brisa'},
        ],
      },
    );

    Future<void> openMenu(WidgetTester tester, {required bool dislikes}) async {
      late BuildContext context;
      await show(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
        dislikes: dislikes,
      );
      unawaited(showKostvMusicSongMenu(context, item: song));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
    }

    testWidgets('«No me gusta» and «No me pongas a …»', (tester) async {
      await openMenu(tester, dislikes: true);
      expect(find.text('No me gusta'), findsOneWidget);
      expect(find.text('No me pongas a Lola Brisa'), findsOneWidget);
      Navigator.of(tester.element(find.text('No me gusta'))).pop();
      await tester.pumpAndSettle();
    });

    testWidgets('a plugin from before it: neither', (tester) async {
      await openMenu(tester, dislikes: false);
      expect(find.text('No me gusta'), findsNothing);
      expect(find.textContaining('No me pongas'), findsNothing);
      expect(find.text('Ir al artista'), findsOneWidget);
      Navigator.of(tester.element(find.text('Ir al artista'))).pop();
      await tester.pumpAndSettle();
    });
  });
}
