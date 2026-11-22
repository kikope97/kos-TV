import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/kostv_music_away.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/add_to_playlist_dialog.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: «Añadir a una lista» offers songs only the playlists of music the
/// person may change, says a refusal, and a «Nueva lista» whose song that
/// isn't at home couldn't go in shows the playlist made.

const _device = DeviceInfo(
  id: 'device',
  name: 'Device',
  appName: 'kOS TV',
  appVersion: '1.0.0',
);

/// Jellyfin: its playlists, a new one made, and adding to them.
class _Jellyfin extends Interceptor {
  final playlists = <Map<String, Object?>>[
    {'Id': 'music', 'Name': 'De música', 'MediaType': 'Audio'},
    {'Id': 'films', 'Name': 'De pelis', 'MediaType': 'Video'},
    {'Id': 'mixed', 'Name': 'Sin tipo', 'MediaType': 'Unknown'},
    {'Id': 'shared', 'Name': 'Compartida', 'MediaType': 'Audio'},
  ];

  /// The status adding to a playlist answers with, when not 204.
  int? addStatus;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    if (options.method == 'GET' && path.endsWith('/Items')) {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {'Items': List.of(playlists)},
        ),
      );
      return;
    }
    if (options.method == 'POST' && path == '/Playlists') {
      final name = (options.data as Map)['Name'];
      playlists.add({'Id': 'new', 'Name': name, 'MediaType': 'Audio'});
      handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: {'Id': 'new'}),
      );
      return;
    }
    final status = addStatus;
    if (status != null) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: status),
          type: DioExceptionType.badResponse,
        ),
      );
      return;
    }
    handler.resolve(Response(requestOptions: options, statusCode: 204));
  }
}

/// The plugin: which playlists may be changed, and adding songs that aren't
/// at home ([addStatus]).
class _Plugin implements HttpClientAdapter {
  List<String>? editable = ['music', 'films', 'mixed', 'new'];
  int addStatus = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.endsWith('/Away/Playlists/Editable')) {
      final ids = editable;
      if (ids == null) return ResponseBody.fromString('', 404);
      return _json({'Ids': ids});
    }
    if (path.contains('/Away/Playlist/') && options.method == 'POST') {
      if (addStatus != 200) return ResponseBody.fromString('', addStatus);
      return _json({'Entries': const []});
    }
    return ResponseBody.fromString('', 404);
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

class _Factory extends Fake implements MediaServerClientFactory {
  @override
  MediaServerClient? getClientIfExists(String serverId) => null;
}

void main() {
  late _Jellyfin jellyfin;
  late _Plugin plugin;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    jellyfin = _Jellyfin();
    plugin = _Plugin();
    final server =
        JellyfinMediaServerClient(
            baseUrl: 'https://casa.example',
            deviceInfo: _device,
            interceptors: [jellyfin],
          )
          ..accessToken = 'token'
          ..userId = 'ana';
    KostvMusicAwayStore.instance = KostvMusicAwayStore(
      KostvMusicPlugin(dio: Dio()..httpClientAdapter = plugin),
    );
    GetIt.instance
      ..registerSingleton<MediaServerClient>(server)
      ..registerSingleton<MediaServerClientFactory>(_Factory());
  });

  tearDown(() async {
    KostvMusicAwayStore.instance = KostvMusicAwayStore();
    await GetIt.instance.reset();
  });

  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return context;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('for a song: only the playlists of music the person may '
      'change', (tester) async {
    final context = await host(tester);
    unawaited(
      AddToPlaylistDialog.show(
        context,
        itemIds: const ['song'],
        songs: (_) async => const ['song'],
      ),
    );
    await settle(tester);
    expect(find.text('De música'), findsOneWidget);
    expect(find.text('Sin tipo'), findsOneWidget);
    expect(find.text('De pelis'), findsNothing);
    expect(find.text('Compartida'), findsNothing);
  });

  testWidgets('for a film: the playlists of videos too', (tester) async {
    final context = await host(tester);
    unawaited(AddToPlaylistDialog.show(context, itemIds: const ['film']));
    await settle(tester);
    expect(find.text('De pelis'), findsOneWidget);
    expect(find.text('De música'), findsOneWidget);
  });

  testWidgets('a plugin that doesn\'t say which: all of them, and a refusal '
      'is said', (tester) async {
    plugin.editable = null;
    jellyfin.addStatus = 403;
    final context = await host(tester);
    unawaited(
      AddToPlaylistDialog.show(
        context,
        itemIds: const ['song'],
        songs: (_) async => const ['song'],
      ),
    );
    await settle(tester);
    expect(find.text('Compartida'), findsOneWidget);
    await tester.tap(find.text('Compartida'));
    await settle(tester);
    expect(find.text('No puedes cambiar esta lista'), findsOneWidget);
    // Still open, to pick another one.
    expect(find.text('De música'), findsOneWidget);
  });

  testWidgets('«Nueva lista» whose song that isn\'t at home couldn\'t go in '
      'shows the playlist made', (tester) async {
    plugin.addStatus = 500;
    final context = await host(tester);
    final away = kostvStreamItem(
      deezerId: '77',
      title: 'Lejos',
      serverId: 'https://casa.example',
    );
    unawaited(
      AddToPlaylistDialog.show(
        context,
        itemIds: const [],
        serverId: away.serverId,
        awaySongs: [away],
      ),
    );
    await settle(tester);
    expect(find.text('De pelis'), findsNothing);
    await tester.tap(find.text('Crear nueva lista de reproducción'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Para el coche');
    await tester.tap(find.text('Crear'));
    await settle(tester);
    expect(find.text('Error al añadir a la lista de reproducción'), findsOne);
    // The playlist made is there, to pick it rather than make another.
    expect(find.text('Para el coche'), findsOneWidget);
  });
}
