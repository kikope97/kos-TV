import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/settings/settings_side_panel.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

/// The plugin's Settings and Listens, kept as a server would.
class _Plugin implements HttpClientAdapter {
  _Plugin({this.hasRoutes = true});

  final bool hasRoutes;
  var learn = true;
  var listens = 1234;
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
    asked.add('${options.method} ${options.uri.path}');
    if (!hasRoutes) return ResponseBody.fromString('', 404);
    switch ('${options.method} ${options.uri.path}') {
      case 'POST /Moonfin/Kostv/Music/Settings':
        learn = (body as Map)['Learn'] as bool;
      case 'GET /Moonfin/Kostv/Music/Settings':
        break;
      case 'DELETE /Moonfin/Kostv/Music/Listens':
        listens = 0;
        return ResponseBody.fromString('', 204);
      default:
        return ResponseBody.fromString('', 404);
    }
    return ResponseBody.fromString(
      jsonEncode({
        'Learn': learn,
        'Listens': listens,
        'Since': listens > 0 ? '2026-09-02T10:00:00Z' : null,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Plugin plugin;

  Future<void> show(WidgetTester tester, {bool hasRoutes = true}) async {
    plugin = _Plugin(hasRoutes: hasRoutes);
    KostvMusicPlugin.instance = KostvMusicPlugin(
      dio: Dio()..httpClientAdapter = plugin,
    );
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
        home: Scaffold(
          body: ListView(children: const [KostvMusicLearnSection()]),
        ),
      ),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  tearDown(() async {
    await GetIt.instance.reset();
    KostvMusicPlugin.instance = KostvMusicPlugin();
  });

  testWidgets('with an older plugin, nothing is shown', (tester) async {
    await show(tester, hasRoutes: false);
    expect(find.text('Aprender de lo que escucho'), findsNothing);
    expect(find.byType(Switch, skipOffstage: false), findsNothing);
  });

  testWidgets('shows the switch, how much is kept and since when', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Música'), findsOneWidget);
    expect(find.text('Aprender de lo que escucho'), findsOneWidget);
    expect(
      find.textContaining('1234 escuchas guardadas desde el'),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('Borrar lo que he escuchado'), findsOneWidget);
  });

  testWidgets('turning it off is kept on the server', (tester) async {
    await show(tester);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    expect(plugin.asked, contains('POST /Moonfin/Kostv/Music/Settings'));
    expect(plugin.learn, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(
      find.textContaining('Apagado: no se guarda lo que escuchas.'),
      findsOneWidget,
    );
  });

  testWidgets('deleting asks first, and only then deletes', (tester) async {
    await show(tester);
    await tester.tap(find.text('Borrar lo que he escuchado'));
    await tester.pumpAndSettle();
    expect(find.text('¿Borrar lo que has escuchado?'), findsOneWidget);

    // Cancelled: nothing deleted.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(
      plugin.asked,
      isNot(contains('DELETE /Moonfin/Kostv/Music/Listens')),
    );

    await tester.tap(find.text('Borrar lo que he escuchado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await tester.pump();
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    expect(plugin.asked, contains('DELETE /Moonfin/Kostv/Music/Listens'));
    expect(find.textContaining('Aún no hay nada guardado.'), findsOneWidget);
  });
}
