import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/auth/store/authentication_preferences.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/auth/store/credential_store.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:server_core/server_core.dart';

// Kos TV: a token revoked while the app is open (a password changed, the
// device removed in Jellyfin) used to leave a TV "signed in" on empty rows
// until the app was closed. A 401 from any request now checks the token, but
// only the active person's, never a sign-in's, and never in a loop.

DioException _failure(int status) => DioException(
  requestOptions: RequestOptions(path: '/Users/Me'),
  response: Response(
    requestOptions: RequestOptions(path: '/Users/Me'),
    statusCode: status,
  ),
);

class _UsersApi extends Fake implements UsersApi {
  int calls = 0;
  int status = 401;

  /// When set, the answer waits for it.
  Completer<void>? gate;

  @override
  Future<ServerUser> getCurrentUser() async {
    calls++;
    await gate?.future;
    throw _failure(status);
  }
}

class _AuthApi extends Fake implements AuthApi {
  int logoutCalls = 0;

  @override
  Future<void> logout() async => logoutCalls++;
}

class _Client extends Fake implements MediaServerClient {
  final usersApiFake = _UsersApi();
  final authApiFake = _AuthApi();

  @override
  String? accessToken = 'live-token';

  @override
  String? userId;

  @override
  UsersApi get usersApi => usersApiFake;

  @override
  AuthApi get authApi => authApiFake;
}

class _Factory extends Fake implements MediaServerClientFactory {
  final client = _Client();

  @override
  MediaServerClient getClient({
    required String serverId,
    required ServerType serverType,
    required String baseUrl,
  }) => client;

  @override
  MediaServerClient? getClientIfExists(String serverId) =>
      serverId == 'server-1' ? client : null;

  @override
  void removeClient(String serverId) {}
}

class _AuthStore extends Fake implements AuthenticationStore {
  _AuthStore(this.user);

  final PrivateUser user;
  int removedUsers = 0;

  @override
  List<PrivateUser> getUsers(String serverId) => [user];

  @override
  Future<void> removeUser(String serverId, String userId) async {
    removedUsers++;
  }
}

class _AuthPrefs extends Fake implements AuthenticationPreferences {
  @override
  UserSelectBehavior get loginBehavior => UserSelectBehavior.lastUser;

  @override
  Future<void> setLastServerId(String id) async {}

  @override
  Future<void> setLastUserId(String id) async {}

  @override
  Future<void> clearAutoLogin() async {}
}

class _CredentialStore extends Fake implements CredentialStore {
  @override
  Future<void> deleteToken(String serverId) async {}
}

class _SocketHandler extends Fake implements SocketHandler {
  @override
  void disconnect() {}
}

class _ServerRepository extends Fake implements ServerRepository {
  _ServerRepository(this.server);

  final Server server;

  @override
  Server? getServer(String id) => server;
}

class _PluginSync extends Fake implements PluginSyncService {
  @override
  void resetState({
    bool notify = true,
    bool stopStream = true,
    bool keepIncompleteRecordings = false,
    bool keepSignInRead = false,
  }) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final server = Server(
    id: 'server-1',
    name: 'Casa',
    address: 'https://server.test',
    version: '10.11.0',
    serverType: ServerType.jellyfin,
    dateAdded: DateTime.utc(2026, 11, 19),
  );
  final user = PrivateUser(
    id: 'user-1',
    name: 'kis',
    serverId: 'server-1',
    accessToken: 'live-token',
    lastUsed: DateTime.utc(2026, 11, 19),
  );

  late _Factory factory;
  late _AuthStore store;
  late SessionRepository repo;

  setUp(() {
    factory = _Factory();
    store = _AuthStore(user);
    repo = SessionRepository(
      store,
      _AuthPrefs(),
      _CredentialStore(),
      factory,
      _SocketHandler(),
      _ServerRepository(server),
      UserRepository(),
      _PluginSync(),
    )..setActiveSessionForTest('server-1', 'user-1');
  });

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a 401 with the active token checks it and signs out', () async {
    repo.noteUnauthorized('server-1', 'live-token', '/Users/user-1/Items');
    await settle();

    expect(factory.client.usersApiFake.calls, 1);
    expect(store.removedUsers, 1);
    expect(repo.activeServerId, isNull);
    expect(
      factory.client.authApiFake.logoutCalls,
      0,
      reason: 'the logout would authenticate with the dead token',
    );
  });

  test('a 401 the check does not confirm keeps the session', () async {
    factory.client.usersApiFake.status = 500;
    repo.noteUnauthorized('server-1', 'live-token', '/Users/user-1/Items');
    await settle();

    expect(factory.client.usersApiFake.calls, 1);
    expect(store.removedUsers, 0);
    expect(repo.activeServerId, 'server-1');
  });

  test('a 401 for another token, server or a sign-in is left alone', () async {
    repo.noteUnauthorized('server-1', 'old-token', '/Users/user-1/Items');
    repo.noteUnauthorized('server-1', null, '/Users/user-1/Items');
    repo.noteUnauthorized('server-2', 'live-token', '/Users/user-1/Items');
    repo.noteUnauthorized(
      'server-1',
      'live-token',
      '/Users/AuthenticateByName',
    );
    repo.noteUnauthorized('server-1', 'live-token', '/QuickConnect/Connect');
    await settle();

    expect(factory.client.usersApiFake.calls, 0);
    expect(store.removedUsers, 0);
  });

  test('a burst of 401s costs one check', () async {
    final gate = Completer<void>();
    factory.client.usersApiFake
      ..status = 500
      ..gate = gate;
    for (var i = 0; i < 5; i++) {
      repo.noteUnauthorized('server-1', 'live-token', '/Items/$i');
    }
    gate.complete();
    await settle();
    // Right after a check, another 401 waits its turn.
    repo.noteUnauthorized('server-1', 'live-token', '/Items/again');
    await settle();

    expect(factory.client.usersApiFake.calls, 1);
  });

  test('a check that answers after a sign-out ends nothing more', () async {
    final gate = Completer<void>();
    factory.client.usersApiFake.gate = gate;
    repo.noteUnauthorized('server-1', 'live-token', '/Items');
    await settle();
    await repo.destroyCurrentSession();
    final removedBySignOut = store.removedUsers;
    gate.complete();
    await settle();

    expect(store.removedUsers, removedBySignOut);
  });

  test(
    'a token check that answers after another switch began is dropped',
    () async {
      final gate = Completer<void>();
      factory.client.usersApiFake.gate = gate;
      final switching = repo.switchCurrentSession(
        serverId: 'server-1',
        userId: 'user-1',
        validateToken: true,
      );
      await settle();
      // Somebody else takes over while the server takes its time.
      await repo.destroyCurrentSession();
      final removedBySignOut = store.removedUsers;
      gate.complete();

      expect(await switching, isFalse);
      expect(store.removedUsers, removedBySignOut);
    },
  );

  group('isSignInRequestPath', () {
    test('sign-ins and the sign-out', () {
      expect(isSignInRequestPath('/Users/AuthenticateByName'), isTrue);
      expect(
        isSignInRequestPath('/jf/Users/AuthenticateWithQuickConnect'),
        isTrue,
      );
      expect(isSignInRequestPath('/QuickConnect/Initiate'), isTrue);
      expect(isSignInRequestPath('/Sessions/Logout'), isTrue);
    });

    test('anything else', () {
      expect(isSignInRequestPath('/Users/Me'), isFalse);
      expect(isSignInRequestPath('/Users/abc/Items'), isFalse);
      expect(isSignInRequestPath('/Sessions/Playing/Stopped'), isFalse);
    });
  });

  test('authorizationToken reads the token of the header', () {
    expect(
      authorizationToken(
        'MediaBrowser Client="kOS TV", Device="TV", DeviceId="d", '
        'Version="1", Token="abc123"',
      ),
      'abc123',
    );
    expect(
      authorizationToken('MediaBrowser Client="kOS TV", Device="TV"'),
      isNull,
    );
    expect(authorizationToken(null), isNull);
  });
}
