import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

/// A plugin that keeps what it is sent, so a read after a push brings the
/// pushed settings back, and records every request.
class _PluginAdapter implements HttpClientAdapter {
  final List<String> requests = [];

  /// The settings the server holds for the profile.
  Map<String, dynamic> stored = {};

  /// Set when the server has nothing saved at all (the plugin's 404).
  bool nothingSaved = false;

  bool failPosts = false;
  Duration resolveDelay = Duration.zero;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    requests.add('${options.method} $path');

    if (path.endsWith('/Moonfin/Ping')) {
      return _json({'installed': true, 'settingsSyncEnabled': true});
    }
    if (path.contains('/Moonfin/Settings/Resolved/')) {
      if (resolveDelay > Duration.zero) {
        await Future<void>.delayed(resolveDelay);
      }
      if (nothingSaved) {
        return _json({'Error': 'No settings found'}, status: 404);
      }
      return _json(Map<String, dynamic>.from(stored));
    }
    if (path.contains('/Moonfin/Settings/Profile/') &&
        options.method == 'POST') {
      if (failPosts) return ResponseBody.fromString('', 500);
      final data = options.data;
      if (data is Map && data['profile'] is Map) {
        stored = Map<String, dynamic>.from(data['profile'] as Map);
        nothingSaved = false;
      }
      return _json({});
    }
    return ResponseBody.fromString('', 404);
  }

  ResponseBody _json(Map<String, dynamic> body, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PluginAdapter adapter;
  late UserPreferences prefs;
  late PluginSyncService service;
  late _MockClient client;

  List<String> profilePosts() => adapter.requests
      .where((r) => r.startsWith('POST') && r.contains('/Settings/Profile/'))
      .toList();
  int firstIndex(String part) =>
      adapter.requests.indexWhere((r) => r.contains(part));

  /// Waits out the 1000ms push debounce plus slack.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 1400));

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'pref_last_server_id': 'srv1',
      'pref_last_user_id': 'user1',
      // Signed in here before, so sign-in reads the server's copy.
      'pref_plugin_sync_initialized_srv1': true,
    });
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);

    client = _MockClient();
    when(() => client.baseUrl).thenReturn('http://plugin.test');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.userId).thenReturn('user1');
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.deviceInfo).thenReturn(
      const DeviceInfo(
        id: 'dev1',
        name: 'test',
        appName: 'moonfin',
        appVersion: '0.0.0',
      ),
    );

    adapter = _PluginAdapter();
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    service = PluginSyncService(prefs, store, dio: dio);

    await prefs.set(UserPreferences.pluginSyncEnabled, true);
    GetIt.instance.registerSingleton<MediaServerClient>(client);
  });

  tearDown(() async {
    service.dispose();
    await GetIt.instance.reset();
  });

  test(
    'a server answer that lands after a switch of person is dropped',
    () async {
      adapter.stored = {'use24HourClock': false};
      adapter.resolveDelay = const Duration(seconds: 1);

      unawaited(service.syncOnLogin(client, serverId: 'srv1'));
      // Waits for the read to go out rather than a fixed time, so a busy
      // machine doesn't make the switch land after the answer.
      final asked = DateTime.now();
      while (firstIndex('/Settings/Resolved/') < 0 &&
          DateTime.now().difference(asked) < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(firstIndex('/Settings/Resolved/'), isNonNegative);

      service.resetState();
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(
        prefs.get(UserPreferences.use24HourClock),
        isTrue,
        reason: 'the previous person\'s settings landed on the next one',
      );
      expect(service.pluginAvailable, isFalse);
    },
  );

  test(
    'a change made with the plugin unreachable goes up before the read',
    () async {
      // The server holds the older value.
      adapter.stored = {'use24HourClock': true};
      await prefs.set(UserPreferences.use24HourClock, false);

      await service.syncOnLogin(client, serverId: 'srv1');

      final post = firstIndex('POST /Moonfin/Settings/Profile/');
      final read = firstIndex('/Settings/Resolved/');
      expect(post, isNonNegative, reason: 'the change was never sent');
      expect(read, greaterThan(post));
      expect(prefs.get(UserPreferences.use24HourClock), isFalse);
      expect(adapter.stored['use24HourClock'], isFalse);
    },
  );

  test(
    'a mark left by a write that changed nothing synced sends nothing',
    () async {
      adapter.stored = {'use24HourClock': true};
      await service.syncOnLogin(client, serverId: 'srv1');
      service.resetState();
      adapter.requests.clear();

      // Not a synced setting: nothing to send for it.
      await prefs.set(UserPreferences.setupWizardVersionForServer('srv1'), 2);
      // Meanwhile another device changed the clock.
      adapter.stored = {'use24HourClock': false};

      await service.syncOnLogin(client, serverId: 'srv1');

      expect(profilePosts(), isEmpty);
      expect(prefs.get(UserPreferences.use24HourClock), isFalse);
    },
  );

  test('a push that fails is sent at the next sign-in', () async {
    await service.syncOnLogin(client, serverId: 'srv1');
    adapter.failPosts = true;
    await prefs.set(UserPreferences.use24HourClock, false);
    await settle();
    expect(profilePosts(), hasLength(1));
    expect(adapter.stored['use24HourClock'], isNot(false));

    adapter.failPosts = false;
    service.resetState();
    adapter.requests.clear();
    await service.syncOnLogin(client, serverId: 'srv1');

    expect(
      firstIndex('/Settings/Resolved/'),
      greaterThan(firstIndex('POST /Moonfin/Settings/Profile/')),
    );
    expect(prefs.get(UserPreferences.use24HourClock), isFalse);
    expect(adapter.stored['use24HourClock'], isFalse);
  });

  test('a change still waiting when the session ends is sent', () async {
    await service.syncOnLogin(client, serverId: 'srv1');
    adapter.requests.clear();

    await prefs.set(UserPreferences.use24HourClock, false);
    service.resetState();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(profilePosts(), hasLength(1));
    expect(adapter.stored['use24HourClock'], isFalse);
  });

  test('a screen pushing on every press sends one profile', () async {
    await service.syncOnLogin(client, serverId: 'srv1');
    adapter.requests.clear();

    for (var i = 0; i < 10; i++) {
      await prefs.set(UserPreferences.use24HourClock, i.isEven);
      await service.pushSettings(client);
    }
    expect(profilePosts(), isEmpty);

    await settle();
    expect(profilePosts(), hasLength(1));
  });

  test('a manual push says whether it reached the server', () async {
    await service.syncOnLogin(client, serverId: 'srv1');

    adapter.failPosts = true;
    expect(
      await service.pushSettingsForProfile(
        client,
        profile: service.syncProfile,
        force: true,
      ),
      isFalse,
    );

    adapter.failPosts = false;
    expect(
      await service.pushSettingsForProfile(
        client,
        profile: service.syncProfile,
        force: true,
      ),
      isTrue,
    );
  });

  test(
    'a server with nothing saved yet starts sync on the first sign-in',
    () async {
      SharedPreferences.setMockInitialValues({
        'pref_last_server_id': 'srv1',
        'pref_last_user_id': 'user1',
      });
      final store = PreferenceStore();
      await store.init();
      prefs = UserPreferences(store);
      final dio = Dio()..httpClientAdapter = adapter;
      service.dispose();
      service = PluginSyncService(prefs, store, dio: dio);
      adapter.nothingSaved = true;

      await service.syncOnLogin(client, serverId: 'srv1');

      expect(prefs.get(UserPreferences.pluginSyncEnabled), isTrue);
      expect(
        prefs.get(UserPreferences.pluginSyncInitializedForServer('srv1')),
        isTrue,
      );
    },
  );

  test(
    'turning sync back on reads the server before sending anything',
    () async {
      adapter.stored = {'use24HourClock': true};
      await service.syncOnLogin(client, serverId: 'srv1');

      await service.setSyncEnabled(false);
      await prefs.set(UserPreferences.use24HourClock, false);
      adapter.requests.clear();

      await service.setSyncEnabled(true);
      await settle();

      expect(firstIndex('/Settings/Resolved/'), isNonNegative);
      expect(profilePosts(), isEmpty);
      expect(prefs.get(UserPreferences.use24HourClock), isTrue);
    },
  );
}
