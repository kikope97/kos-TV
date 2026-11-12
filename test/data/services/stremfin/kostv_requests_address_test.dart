import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/kostv_server.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_stremfin_adapter.dart';

class _MockClient extends Mock implements MediaServerClient {}

/// Answers the plugin's ping with what [ping] holds.
class _PingAdapter implements HttpClientAdapter {
  Map<String, dynamic> ping = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.uri.path.endsWith('/Moonfin/Ping')) {
      return ResponseBody.fromString('', 404);
    }
    return ResponseBody.fromString(
      jsonEncode(ping),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Kos TV: the requests service's address comes from the home server's
/// plugin, not from the app's build.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    KostvRequestsAddress.reset();
  });

  tearDown(KostvRequestsAddress.reset);

  group('the address on the device', () {
    test('is kept for the next start, and taken away when the plugin gives '
        'none', () async {
      await KostvRequestsAddress.update('https://requests.example.org');
      expect(kostvRequestsUrl, 'https://requests.example.org');
      expect(hasKostvRequests, isTrue);

      KostvRequestsAddress.reset();
      expect(hasKostvRequests, isFalse);
      await KostvRequestsAddress.load();
      expect(kostvRequestsUrl, 'https://requests.example.org');

      await KostvRequestsAddress.update(null);
      expect(hasKostvRequests, isFalse);
      KostvRequestsAddress.reset();
      await KostvRequestsAddress.load();
      expect(hasKostvRequests, isFalse);
    });

    test('is asked for again after six hours', () async {
      final at = DateTime(2026, 11, 12, 10);
      expect(KostvRequestsAddress.isStale(now: at), isTrue);

      await KostvRequestsAddress.update(
        'https://requests.example.org',
        now: at,
      );
      expect(
        KostvRequestsAddress.isStale(now: at.add(const Duration(hours: 5))),
        isFalse,
      );
      expect(
        KostvRequestsAddress.isStale(now: at.add(const Duration(hours: 6))),
        isTrue,
      );
    });
  });

  group('the plugin', () {
    late _PingAdapter adapter;
    late PluginSyncService sync;
    late _MockClient client;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'pref_last_server_id': 'srv1'});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      await prefs.set(UserPreferences.pluginSyncEnabled, true);

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
      adapter = _PingAdapter();
      sync = PluginSyncService(
        prefs,
        store,
        dio: Dio()..httpClientAdapter = adapter,
      );
    });

    test('gives the address in its ping', () async {
      adapter.ping = {
        'installed': true,
        'settingsSyncEnabled': true,
        'kostvRequestsUrl': 'https://requests.example.org',
      };

      await sync.refreshAvailability(client);

      expect(kostvRequestsUrl, 'https://requests.example.org');
      expect(KostvRequestsAddress.isStale(), isFalse);
    });

    test('gives it even with settings sync off', () async {
      adapter.ping = {
        'installed': true,
        'settingsSyncEnabled': false,
        'kostvRequestsUrl': 'https://requests.example.org',
      };

      await sync.refreshAvailability(client);

      expect(kostvRequestsUrl, 'https://requests.example.org');
    });

    test('an older plugin, without the address, hides Discover', () async {
      await KostvRequestsAddress.update('https://requests.example.org');
      adapter.ping = {'installed': true, 'settingsSyncEnabled': true};

      await sync.refreshAvailability(client);

      expect(hasKostvRequests, isFalse);
    });
  });

  group('the requests service', () {
    test('follows the address the plugin gives', () async {
      final adapter = FakeStremfinAdapter((path, query) {
        return (
          status: 200,
          body: {
            'user': {'role': 'member'},
            'access': {'can_request': true},
          },
          headers: const <String, String>{},
        );
      });
      final client = StremfinClient(
        dio: Dio()..httpClientAdapter = adapter,
        token: () => 'abc123token',
      );
      final stremfin = StremfinService(client, watchLifecycle: false);
      KostvRequestsAddress.notifier.addListener(stremfin.onAddressChanged);
      addTearDown(() {
        KostvRequestsAddress.notifier.removeListener(stremfin.onAddressChanged);
        stremfin.dispose();
      });

      stremfin.onUserChanged('user-1');
      await stremfin.refreshAccess();
      expect(client.isConfigured, isFalse);
      expect(stremfin.isAllowed, isFalse);

      await KostvRequestsAddress.update('https://requests.example.org');
      await stremfin.refreshAccess();

      expect(client.isConfigured, isTrue);
      expect(stremfin.isAllowed, isTrue);
      expect(
        adapter.calls.last.uri.toString(),
        startsWith('https://requests.example.org/api/v1/me'),
      );

      await KostvRequestsAddress.update(null);
      expect(client.isConfigured, isFalse);
      expect(stremfin.isAllowed, isFalse);
    });
  });
}
