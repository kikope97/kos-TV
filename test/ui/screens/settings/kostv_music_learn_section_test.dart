import 'dart:async';
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

  /// The status the server answers with for now, when it isn't well.
  int? failing;

  /// Held until it completes, when set: a slow server.
  Completer<void>? slow;
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
    await slow?.future;
    if (!hasRoutes) return ResponseBody.fromString('', 404);
    final status = failing;
    if (status != null) return ResponseBody.fromString('', status);
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

  Future<void> show(
    WidgetTester tester, {
    bool hasRoutes = true,
    int? failing,
    int listens = 1234,
  }) async {
    plugin = _Plugin(hasRoutes: hasRoutes)
      ..failing = failing
      ..listens = listens;
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
      find.textContaining('1.234 escuchas guardadas desde el'),
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

  testWidgets('a server that fails doesn\'t hide the setting: it says so '
      'and asks again', (tester) async {
    await show(tester, failing: 503);
    expect(find.text('Aprender de lo que escucho'), findsOneWidget);
    expect(
      find.text(
        'No se ha podido consultar ahora. Pulsa para volver a intentarlo.',
      ),
      findsOneWidget,
    );
    expect(find.byType(Switch), findsNothing);

    plugin.failing = null;
    await tester.tap(find.text('Aprender de lo que escucho'));
    await tester.pump();
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    expect(find.textContaining('1.234 escuchas guardadas'), findsOneWidget);
  });

  testWidgets('a big number of listens is written with separators', (
    tester,
  ) async {
    await show(tester, listens: 12345);
    expect(find.textContaining('12.345 escuchas guardadas'), findsOneWidget);
  });

  testWidgets('while the server answers, the switch stays one that can hold '
      'the remote\'s focus, and a second press is ignored', (tester) async {
    await show(tester);
    final slow = plugin.slow = Completer<void>();
    // The line's own focus, as the remote has it.
    final node = Focus.of(
      tester.element(find.text('Aprender de lo que escucho')),
    );
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);
    await tester.tap(find.text('Aprender de lo que escucho'));
    await tester.pump();
    expect(node.hasFocus, isTrue);
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.onChanged, isNotNull);
    // Pressed again while it is under way: nothing more is sent.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    slow.complete();
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    expect(
      plugin.asked.where((a) => a == 'POST /Moonfin/Kostv/Music/Settings'),
      hasLength(1),
    );
    expect(plugin.learn, isFalse);
  });
}
