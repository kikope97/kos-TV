import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';

import 'fake_stremfin_adapter.dart';

/// Kos TV: who may use Discover, and the lists kept between platforms.
void main() {
  late FakeStremfinAdapter adapter;
  late DateTime now;
  late ({int status, Object? body, Map<String, String> headers}) meReply;

  StremfinService service() => StremfinService(
    StremfinClient(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://requests.example.org/api/v1',
      token: () => 'abc123token',
    ),
    clock: () => now,
    watchLifecycle: false,
  );

  setUp(() {
    now = DateTime(2026, 11, 11, 20);
    meReply = (
      status: 200,
      body: {
        'user': {'role': 'member'},
        'access': {'can_request': true},
      },
      headers: const {},
    );
    adapter = FakeStremfinAdapter((path, query) {
      if (path == '/me') return meReply;
      return (
        status: 200,
        body: {
          'items': [fakeTitle(1), fakeTitle(2, inLibrary: true, itemId: 'x')],
        },
        headers: const {},
      );
    });
  });

  test('someone with access sees Discover once the service says so', () async {
    final stremfin = service();
    expect(stremfin.access, StremfinAccess.unknown);

    stremfin.onUserChanged('user-1');
    await stremfin.refreshAccess();

    expect(stremfin.isAllowed, isTrue);
    stremfin.dispose();
  });

  test(
    'without access, or with the token refused, Discover stays hidden',
    () async {
      meReply = (
        status: 200,
        body: {
          'user': {'role': 'none'},
          'access': {'can_request': false},
        },
        headers: const {},
      );
      final stremfin = service();
      await stremfin.refreshAccess();
      expect(stremfin.access, StremfinAccess.denied);

      meReply = (
        status: 401,
        body: {
          'error': {'code': 'invalid_token'},
        },
        headers: const {},
      );
      await stremfin.refreshAccess();
      expect(stremfin.access, StremfinAccess.denied);
      stremfin.dispose();
    },
  );

  test('the service not answering keeps what it said last', () async {
    final stremfin = service();
    await stremfin.refreshAccess();
    expect(stremfin.isAllowed, isTrue);

    meReply = (
      status: 503,
      body: {
        'error': {'code': 'jellyfin_unavailable'},
      },
      headers: const {'retry-after': '30'},
    );
    await stremfin.refreshAccess();
    expect(stremfin.isAllowed, isTrue);
    stremfin.dispose();
  });

  test('a list is asked once while it is fresh, then again', () async {
    final stremfin = service();
    Future<List<StremfinTitle>> netflix() => stremfin.top(
      platform: 'netflix',
      type: StremfinTitleType.series,
      list: StremfinTopList.popular,
    );

    final first = await netflix();
    await netflix();
    expect(first, hasLength(2));
    expect(
      adapter.calls.where((c) => c.uri.path.endsWith('/top')),
      hasLength(1),
    );

    now = now.add(StremfinService.listLifetime);
    await netflix();
    expect(
      adapter.calls.where((c) => c.uri.path.endsWith('/top')),
      hasLength(2),
    );
    stremfin.dispose();
  });

  test('another person starts with nothing kept', () async {
    final stremfin = service();
    stremfin.onUserChanged('user-1');
    await stremfin.refreshAccess();
    await stremfin.top(
      platform: 'all',
      type: StremfinTitleType.movie,
      list: StremfinTopList.fresh,
    );
    expect(
      stremfin.keptList(
        platform: 'all',
        type: StremfinTitleType.movie,
        list: StremfinTopList.fresh,
      ),
      isNotNull,
    );

    stremfin.onUserChanged('user-2');
    expect(stremfin.access, StremfinAccess.unknown);
    expect(
      stremfin.keptList(
        platform: 'all',
        type: StremfinTitleType.movie,
        list: StremfinTopList.fresh,
      ),
      isNull,
    );
    stremfin.dispose();
  });

  test('the platforms fall back to the usual four', () async {
    adapter.answer = (path, query) =>
        (status: 500, body: {}, headers: const {});
    final stremfin = service();
    final platforms = await stremfin.platforms();
    expect(platforms.map((p) => p.id), ['all', 'netflix', 'disney', 'prime']);
    stremfin.dispose();
  });
}
