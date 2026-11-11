import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

/// Answers the plugin and keeps every settings stream open for the test to
/// write into, the way the server holds it open between events.
class _StreamAdapter implements HttpClientAdapter {
  final List<StreamController<Uint8List>> streams = [];

  /// Every path asked for, in order.
  final List<String> paths = [];

  void send(String text) =>
      streams.last.add(Uint8List.fromList(utf8.encode(text)));

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    paths.add(path);
    if (path.endsWith('/Moonfin/Settings/Stream')) {
      final body = StreamController<Uint8List>();
      streams.add(body);
      return ResponseBody(
        body.stream,
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    }
    Map<String, dynamic>? body;
    if (path.endsWith('/Moonfin/Ping')) {
      body = {'installed': true, 'settingsSyncEnabled': true};
    } else if (path.contains('/Moonfin/Settings/')) {
      body = {};
    }
    if (body == null) return ResponseBody.fromString('', 404);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _settingsUpdatedEvent = {'type': 'settingsUpdated'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PluginSyncService service;
  late _StreamAdapter adapter;
  late _MockClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'pref_last_server_id': 'srv1'});
    final store = PreferenceStore();
    await store.init();
    final prefs = UserPreferences(store);

    client = _MockClient();
    when(() => client.baseUrl).thenReturn('http://plugin.test');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.deviceInfo).thenReturn(
      const DeviceInfo(
        id: 'dev1',
        name: 'test',
        appName: 'moonfin',
        appVersion: '0.0.0',
      ),
    );
    GetIt.instance.registerSingleton<MediaServerClient>(client);

    adapter = _StreamAdapter();
    service = PluginSyncService(
      prefs,
      store,
      dio: Dio(pluginRequestOptions())..httpClientAdapter = adapter,
    );
    await prefs.set(UserPreferences.pluginSyncEnabled, true);
  });

  tearDown(() => GetIt.instance.reset());

  group('settings stream', () {
    test('a quiet stream stays open past the server heartbeat', () {
      fakeAsync((async) {
        int profileReads() => adapter.paths
            .where((p) => p.contains('/Moonfin/Settings/Resolved/'))
            .length;
        service.syncOnLogin(client, serverId: 'srv1');
        async.elapse(const Duration(seconds: 5));
        adapter.send(':connected\n\n');

        async.elapse(const Duration(seconds: 45));
        final readsBefore = profileReads();
        adapter.send('data: ${jsonEncode(_settingsUpdatedEvent)}\n\n');
        // Long enough for the read to go out, nowhere near the idle limit.
        async.elapse(const Duration(seconds: 1));

        expect(adapter.streams, hasLength(1));
        // The event came through the open stream, so the profile was read
        // again.
        expect(profileReads(), readsBefore + 1);
        service.dispose();
      });
    });

    test('a stream quiet past the idle limit opens again', () {
      fakeAsync((async) {
        service.syncOnLogin(client, serverId: 'srv1');
        async.elapse(const Duration(seconds: 5));
        adapter.send(':connected\n\n');

        async.elapse(const Duration(seconds: 90));

        expect(adapter.streams, hasLength(2));
        service.dispose();
      });
    });
  });
}
