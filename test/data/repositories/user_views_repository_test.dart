import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/data/services/socket_handler.dart';
import 'package:server_core/server_core.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockUsersApi extends Mock implements UsersApi {}

class _MockViewsApi extends Mock implements UserViewsApi {}

void main() {
  late _MockUsersApi users;
  late _MockViewsApi views;
  late UserViewsRepository repo;

  setUp(() {
    users = _MockUsersApi();
    views = _MockViewsApi();
    final client = _MockClient();
    when(() => client.usersApi).thenReturn(users);
    when(() => client.userViewsApi).thenReturn(views);
    repo = UserViewsRepository(client);
  });

  // Answers on the next event loop turn, so callers that ask together are all
  // waiting on the same request rather than each finding the cache empty.
  Future<T> later<T>(T value) => Future.delayed(Duration.zero, () => value);

  test('rows asking together share one configuration request', () async {
    when(() => users.getUserConfiguration()).thenAnswer(
      (_) => later(const UserConfiguration(myMediaExcludes: ['hidden'])),
    );
    when(() => views.getUserViews(includeHidden: true)).thenAnswer(
      (_) => later({
        'Items': [
          {'Id': 'movies', 'Name': 'Movies'},
          {'Id': 'hidden', 'Name': 'Hidden'},
        ],
      }),
    );

    final results = await Future.wait([
      repo.getUserViews(),
      repo.getUserViews(),
      repo.getUserViews(),
    ]);

    verify(() => users.getUserConfiguration()).called(1);
    verify(() => views.getUserViews(includeHidden: true)).called(1);
    expect(results.every((r) => r.single.id == 'movies'), isTrue);
  });

  test('the raw and parsed views share one request', () async {
    when(
      () => users.getUserConfiguration(),
    ).thenAnswer((_) => later(const UserConfiguration()));
    when(() => views.getUserViews(includeHidden: true)).thenAnswer(
      (_) => later({
        'Items': [
          {'Id': 'movies', 'Name': 'Movies'},
        ],
      }),
    );

    final raw = repo.getVisibleViewsResponse();
    final parsed = repo.getAllViewsIncludingHidden();
    expect((await raw)['Items'], hasLength(1));
    expect((await parsed).single.name, 'Movies');
    verify(() => views.getUserViews(includeHidden: true)).called(1);
  });

  group('the views are kept for the session', () {
    setUpAll(() => registerFallbackValue(const UserConfiguration()));

    setUp(() {
      when(
        () => users.getUserConfiguration(),
      ).thenAnswer((_) => later(const UserConfiguration()));
      when(() => views.getUserViews(includeHidden: true)).thenAnswer(
        (_) => later({
          'Items': [
            {'Id': 'movies', 'Name': 'Movies'},
          ],
        }),
      );
    });

    test('a later screen reads them without a request', () async {
      await repo.getUserViews();
      await repo.getUserViews();

      verify(() => views.getUserViews(includeHidden: true)).called(1);
    });

    test('invalidating reads them again and tells the nav chrome', () async {
      var notified = 0;
      repo.addListener(() => notified++);
      await repo.getUserViews();

      repo.invalidateViews();
      await repo.getUserViews();

      expect(notified, 1);
      verify(() => views.getUserViews(includeHidden: true)).called(2);
    });

    test('saving the configuration reads them again', () async {
      when(() => users.updateUserConfiguration(any())).thenAnswer((_) async {});
      await repo.getUserViews();

      await repo.updateUserConfiguration(
        const UserConfiguration(orderedViews: ['movies']),
      );
      await repo.getUserViews();

      verify(() => views.getUserViews(includeHidden: true)).called(2);
    });
  });

  test(
    'a forced configuration read still collapses while one is in flight',
    () async {
      when(
        () => users.getUserConfiguration(),
      ).thenAnswer((_) => later(const UserConfiguration()));

      await Future.wait([
        repo.getUserConfiguration(),
        repo.getUserConfiguration(),
      ]);
      verify(() => users.getUserConfiguration()).called(1);

      await repo.getUserConfiguration();
      verify(() => users.getUserConfiguration()).called(1);
    },
  );

  // Kos TV: the views and configuration follow changes the socket reports.
  group('server changes', () {
    late StreamController<ServerWebSocketMessage> events;
    late StreamController<void> reconnects;
    late _MockClient client;
    late List<Map<String, dynamic>> serverViews;
    late UserViewsRepository live;
    late int notified;

    setUp(() {
      UserViewsRepository.changeSettle = Duration.zero;
      events = StreamController<ServerWebSocketMessage>.broadcast();
      reconnects = StreamController<void>.broadcast();
      client = _MockClient();
      when(() => client.usersApi).thenReturn(users);
      when(() => client.userViewsApi).thenReturn(views);
      when(() => client.userId).thenReturn('aaaa-bbbb');
      serverViews = [
        {'Id': 'movies', 'Name': 'Movies'},
      ];
      when(
        () => users.getUserConfiguration(),
      ).thenAnswer((_) async => const UserConfiguration());
      when(
        () => views.getUserViews(includeHidden: true),
      ).thenAnswer((_) async => {'Items': List.of(serverViews)});
      live = UserViewsRepository(
        client,
        serverEvents: events.stream,
        reconnections: reconnects.stream,
      );
      notified = 0;
      live.addListener(() => notified++);
    });

    tearDown(() {
      live.stopFollowingServer();
      UserViewsRepository.changeSettle = const Duration(seconds: 5);
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('an update of this user drops both caches', () async {
      await live.getUserViews();
      events.add(
        const ServerEventMessage(type: 'UserUpdated', data: {'Id': 'AAAABBBB'}),
      );
      await settle();
      expect(notified, 1);

      serverViews.add({'Id': 'kids', 'Name': 'Kids'});
      final again = await live.getUserViews();
      expect(again.map((v) => v.id), ['movies', 'kids']);
      verify(() => users.getUserConfiguration()).called(2);
    });

    test("another user's update is left alone", () async {
      await live.getUserViews();
      events.add(
        const ServerEventMessage(type: 'UserUpdated', data: {'Id': 'other'}),
      );
      await settle();
      expect(notified, 0);
    });

    test('a library change reloads the nav only when the list moved', () async {
      await live.getUserViews();
      events.add(const LibraryChangedMessage(itemsAdded: ['episode']));
      await settle();
      await settle();
      expect(notified, 0);

      serverViews.add({'Id': 'kids', 'Name': 'Kids'});
      events.add(const LibraryChangedMessage(itemsRemoved: ['folder']));
      await settle();
      await settle();
      expect(notified, 1);
      expect((await live.getUserViews()).map((v) => v.id), ['movies', 'kids']);
    });

    test('a reconnect checks too, and nothing cached asks nothing', () async {
      reconnects.add(null);
      await settle();
      await settle();
      verifyNever(() => views.getUserViews(includeHidden: true));

      await live.getUserViews();
      serverViews.clear();
      reconnects.add(null);
      await settle();
      await settle();
      expect(notified, 1);
    });
  });

  test('one replaced on a user switch stops following the socket', () async {
    UserViewsRepository.changeSettle = Duration.zero;
    addTearDown(() {
      UserViewsRepository.changeSettle = const Duration(seconds: 5);
      return GetIt.instance.reset();
    });
    final socket = _FakeSocket();
    final handler = SocketHandler(clientFactory: (_) => socket);
    GetIt.instance.registerSingleton<SocketHandler>(handler);
    final client = _MockClient();
    when(() => client.usersApi).thenReturn(users);
    when(() => client.userViewsApi).thenReturn(views);
    when(() => client.userId).thenReturn('me');
    handler.connectTo(client);

    final old = UserViewsRepository(client);
    var notified = 0;
    old.addListener(() => notified++);
    socket.push(
      const ServerEventMessage(type: 'UserUpdated', data: {'Id': 'me'}),
    );
    await Future<void>.delayed(Duration.zero);
    socket.push(
      const ServerEventMessage(type: 'UserUpdated', data: {'Id': 'me'}),
    );
    await Future<void>.delayed(Duration.zero);

    expect(notified, 0, reason: 'it is not the registered repository');
  });
}

class _FakeSocket implements ServerWebSocketClient {
  final _messages = StreamController<ServerWebSocketMessage>.broadcast();
  final _connections = StreamController<void>.broadcast();

  @override
  Stream<ServerWebSocketMessage> get messages => _messages.stream;

  @override
  Stream<void> get connections => _connections.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void retryNow() {}

  @override
  void send(String messageType, [Object? data]) {}

  @override
  void dispose() {
    _messages.close();
    _connections.close();
  }

  void push(ServerWebSocketMessage message) => _messages.add(message);
}
