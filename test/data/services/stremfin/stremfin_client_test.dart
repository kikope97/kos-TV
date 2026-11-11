import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';

import 'fake_stremfin_adapter.dart';

/// Kos TV: the client of the requests service behind Discover.
void main() {
  group('apiBaseFor', () {
    test('takes the address with or without a slash or /api/v1', () {
      for (final raw in [
        'https://requests.example.org',
        'https://requests.example.org/',
        'https://requests.example.org/api/v1',
        'https://requests.example.org/api/v1/',
        ' requests.example.org ',
      ]) {
        expect(
          StremfinClient.apiBaseFor(raw),
          'https://requests.example.org/api/v1',
          reason: raw,
        );
      }
    });

    test('always goes over https, since every call carries the token', () {
      expect(
        StremfinClient.apiBaseFor('http://requests.example.org/'),
        'https://requests.example.org/api/v1',
      );
    });

    test('no address, no service', () {
      expect(StremfinClient.apiBaseFor(''), isNull);
      expect(StremfinClient.apiBaseFor('   '), isNull);
    });
  });

  late FakeStremfinAdapter adapter;
  StremfinClient client({String? token = 'abc123token'}) {
    final dio = Dio()..httpClientAdapter = adapter;
    return StremfinClient(
      dio: dio,
      baseUrl: 'https://requests.example.org/api/v1',
      token: () => token,
    );
  }

  test(
    'sends the token in the Authorization header, never in the URL',
    () async {
      adapter = FakeStremfinAdapter(
        (path, query) => (
          status: 200,
          body: {
            'user': {'role': 'member'},
            'access': {'can_request': true},
          },
          headers: const {},
        ),
      );
      final me = await client().me();

      expect(me.canDiscover, isTrue);
      final call = adapter.calls.single;
      expect(call.headers['Authorization'], 'Bearer abc123token');
      expect(call.uri.toString(), isNot(contains('abc123token')));
      expect(call.uri.path, '/api/v1/me');
    },
  );

  test('reads a list with what the home server has of each title', () async {
    adapter = FakeStremfinAdapter(
      (path, query) => (
        status: 200,
        body: {
          'items': [
            fakeTitle(
              1,
              type: 'series',
              inLibrary: true,
              itemId: 'abc',
              rank: 1,
            ),
            fakeTitle(2, rank: 2),
            {'type': 'movie', 'title': 'No id'},
          ],
        },
        headers: const {},
      ),
    );
    final items = await client().top(
      platform: 'netflix',
      type: StremfinTitleType.series,
      list: StremfinTopList.popular,
    );

    expect(adapter.calls.single.uri.queryParameters, {
      'platform': 'netflix',
      'type': 'series',
      'list': 'popular',
    });
    expect(items, hasLength(2));
    expect(items.first.isInLibrary, isTrue);
    expect(items.first.library.itemId, 'abc');
    expect(items.first.rank, 1);
    expect(items.last.isInLibrary, isFalse);
    expect(items.last.library.status, StremfinLibraryStatus.missing);
  });

  test('"new" is asked as list=new', () async {
    adapter = FakeStremfinAdapter(
      (path, query) => (status: 200, body: {'items': []}, headers: const {}),
    );
    await client().top(
      platform: 'all',
      type: StremfinTitleType.movie,
      list: StremfinTopList.fresh,
    );
    expect(adapter.calls.single.uri.queryParameters['list'], 'new');
  });

  test('an error carries its code, message and Retry-After', () async {
    adapter = FakeStremfinAdapter(
      (path, query) => (
        status: 503,
        body: {
          'error': {'code': 'jellyfin_unavailable', 'message': 'Ahora no.'},
        },
        headers: const {'retry-after': '30'},
      ),
    );
    final error = await client().me().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );

    expect(error, isA<StremfinException>());
    final e = error! as StremfinException;
    expect(e.code, 'jellyfin_unavailable');
    expect(e.status, 503);
    expect(e.message, 'Ahora no.');
    expect(e.retryAfter, const Duration(seconds: 30));
    expect(e.isNoAccess, isFalse);
  });

  test('no token: nothing is sent', () async {
    adapter = FakeStremfinAdapter(
      (path, query) => (status: 200, body: {}, headers: const {}),
    );
    final error = await client(token: null)
        .me()
        .then<Object?>((_) => null, onError: (Object e) => e);

    expect(error, isA<StremfinException>());
    expect((error! as StremfinException).isNoAccess, isTrue);
    expect(adapter.calls, isEmpty);
  });

  test('platform colours come from their hex code', () {
    expect(StremfinPlatform.parseColor('#e50914')?.toARGB32(), 0xFFE50914);
    expect(StremfinPlatform.parseColor(null), isNull);
    expect(StremfinPlatform.parseColor('red'), isNull);
  });
}
