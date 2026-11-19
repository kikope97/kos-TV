import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/syncplay/syncplay_manager.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

class _MockPlaybackManager extends Mock implements PlaybackManager {}

class _MockUserPreferences extends Mock implements UserPreferences {}

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeUsersApi extends Fake implements AdminUsersApi {
  int calls = 0;

  @override
  Future<List<ServerUser>> getUsers({bool? isDisabled, bool? isHidden}) async {
    calls++;
    return const [
      ServerUser(id: 'u1', name: 'Mittens', primaryImageTag: 'tag1'),
    ];
  }
}

class _FakeImageApi extends Fake implements ImageApi {
  @override
  String getUserImageUrl(String userId) =>
      'http://jf/Users/$userId/Images/Primary';
}

void main() {
  // Kos TV: a group's leftovers go with the session that joined it.
  test(
    'a session change drops the error and the last person\'s users',
    () async {
      final manager = SyncPlayManager(
        _MockPlaybackManager(),
        _MockUserPreferences(),
      );
      final users = _FakeUsersApi();
      final client = _MockMediaServerClient();
      when(() => client.baseUrl).thenReturn('http://jf');
      when(() => client.adminUsersApi).thenReturn(users);
      when(() => client.imageApi).thenReturn(_FakeImageApi());
      manager.setActiveClient(client);

      manager.participantImageUrlFor('Mittens');
      await Future<void>.delayed(Duration.zero);
      expect(manager.participantImageUrlFor('Mittens'), isNotNull);
      manager.handleRealtimeSessionInterrupted(SyncPlayError.serverRestarting);
      expect(manager.error, SyncPlayError.serverRestarting);

      await manager.resetForSessionChange(notifyServer: false);

      expect(manager.error, isNull);
      expect(manager.state.enabled, isFalse);
      // The user list is fetched again, for the new person.
      expect(manager.participantImageUrlFor('Mittens'), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(users.calls, 2);
    },
  );

  group('a group playlist with entries that failed to load', () {
    test('starts on the group\'s own title, not the one after it', () {
      // Episodes 1 to 8, the group on the 5th (index 4), the 2nd failed.
      final loaded = <String?>['e1', null, 'e3', 'e4', 'e5', 'e6', 'e7', 'e8'];
      final (items, start) = syncPlayLoadedStart(loaded, 4)!;
      expect(items, ['e1', 'e3', 'e4', 'e5', 'e6', 'e7', 'e8']);
      expect(items[start], 'e5');
    });

    test('plays nothing when the group\'s own title failed', () {
      expect(syncPlayLoadedStart(<String?>['a', null, 'c'], 1), isNull);
      expect(syncPlayLoadedStart(<String?>[], 0), isNull);
    });

    test('an index out of range clamps as before', () {
      final (items, start) = syncPlayLoadedStart(<String?>['a', 'b'], 9)!;
      expect(items[start], 'b');
      final (_, first) = syncPlayLoadedStart(<String?>['a', 'b'], -1)!;
      expect(first, 0);
    });
  });
}
