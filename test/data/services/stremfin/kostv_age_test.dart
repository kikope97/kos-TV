import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/kostv_age_gate.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/util/parental_filter.dart';
import 'package:server_core/server_core.dart';

import 'fake_stremfin_adapter.dart';

/// Kos TV: what of the requests service someone may see by age. The service
/// only says how old a title is for; the app hides what the person can't see.
void main() {
  StremfinTitle titled({
    StremfinTitleType type = StremfinTitleType.movie,
    int? age,
    String? label,
  }) => StremfinTitle(
    type: type,
    tmdbId: 1,
    title: 'Title',
    age: age,
    ageLabel: label ?? (age == null ? null : '$age'),
  );

  group('the rule', () {
    bool allows(
      StremfinTitle title, {
      KostvAgeLimit limit = KostvAgeLimit.none,
      ParentalFilter parental = ParentalFilter.none,
    }) => kostvAgeAllows(title, limit: limit, parental: parental);

    test('someone with no limit sees everything, rated or not', () {
      expect(allows(titled(age: 18)), isTrue);
      expect(allows(titled()), isTrue);
    });

    test('an age limit hides what is for older people and what has no '
        'known rating', () {
      const twelve = KostvAgeLimit(maxAge: 12);
      expect(allows(titled(age: 0), limit: twelve), isTrue);
      expect(allows(titled(age: 12), limit: twelve), isTrue);
      expect(allows(titled(age: 16), limit: twelve), isFalse);
      expect(allows(titled(), limit: twelve), isFalse);
    });

    test('hiding unrated titles of one kind leaves the other kind alone', () {
      const unratedFilms = KostvAgeLimit(
        blockUnrated: {StremfinTitleType.movie},
      );
      expect(allows(titled(), limit: unratedFilms), isFalse);
      expect(allows(titled(age: 18), limit: unratedFilms), isTrue);
      expect(
        allows(titled(type: StremfinTitleType.series), limit: unratedFilms),
        isTrue,
      );
    });

    test("the device's parental control hides its ratings and the "
        'unknown', () {
      final sixteen = ParentalFilter.fromRatings(['16']);
      expect(allows(titled(age: 12), parental: sixteen), isTrue);
      expect(allows(titled(age: 16), parental: sixteen), isFalse);
      expect(allows(titled(age: 18), parental: sixteen), isFalse);
      expect(allows(titled(), parental: sixteen), isFalse);

      final pg13 = ParentalFilter.fromRatings(['PG-13']);
      expect(allows(titled(age: 13, label: 'PG-13'), parental: pg13), isFalse);
    });

    test('the limit comes from the home server account', () {
      final policy = UserPolicy.fromJson(const {
        'IsAdministrator': false,
        'MaxParentalRating': 12,
        'BlockUnratedItems': ['Movie', 'Book'],
      });
      expect(
        KostvAgeLimit.fromPolicy(policy),
        const KostvAgeLimit(
          maxAge: 12,
          blockUnrated: {StremfinTitleType.movie},
        ),
      );
      expect(
        KostvAgeLimit.fromPolicy(UserPolicy.fromJson(const {})),
        KostvAgeLimit.none,
      );
    });
  });

  test('a title reads its age and rating, and none from an older service', () {
    final rated = StremfinTitle.fromJson(fakeTitle(1, rated: true, age: 16))!;
    expect(rated.age, 16);
    expect(rated.ageLabel, '16');
    final unrated = StremfinTitle.fromJson(fakeTitle(2, rated: true))!;
    expect(unrated.age, isNull);
    final older = StremfinTitle.fromJson(fakeTitle(3))!;
    expect(older.age, isNull);
  });

  group('the service', () {
    late FakeStremfinAdapter adapter;
    late List<Map<String, Object?>> topItems;
    late Map<String?, ({List<Map<String, Object?>> items, String? next})>
    searchPages;

    RequestOptions topCall() =>
        adapter.calls.lastWhere((c) => c.uri.path.endsWith('/top'));

    StremfinService service(Future<KostvAgeLimit> Function() ageLimit) =>
        StremfinService(
          StremfinClient(
            dio: Dio()..httpClientAdapter = adapter,
            baseUrl: 'https://requests.example.org/api/v1',
            token: () => 'abc123token',
          ),
          ageLimit: ageLimit,
          parental: () => ParentalFilter.none,
          watchLifecycle: false,
        );

    setUp(() {
      topItems = [
        fakeTitle(1, rated: true, age: 7),
        fakeTitle(2, rated: true, age: 18),
        fakeTitle(3, rated: true),
        fakeTitle(4, rated: true, age: 12),
      ];
      searchPages = {
        null: (items: [fakeTitle(10, rated: true, age: 18)], next: '2.0'),
        '2.0': (items: [fakeTitle(11, rated: true, age: 0)], next: null),
      };
      adapter = FakeStremfinAdapter((path, query) {
        if (path == '/me') {
          return (
            status: 200,
            body: {
              'user': {'role': 'member'},
              'access': {'can_request': true},
            },
            headers: const <String, String>{},
          );
        }
        if (path == '/top') {
          return (
            status: 200,
            body: {'items': topItems},
            headers: const <String, String>{},
          );
        }
        if (path == '/search') {
          final page = searchPages[query['cursor']]!;
          return (
            status: 200,
            body: {'items': page.items, 'next_cursor': page.next},
            headers: const <String, String>{},
          );
        }
        return (status: 404, body: null, headers: const <String, String>{});
      });
    });

    test('Discover only lists what the person may see, read longer', () async {
      final stremfin = service(() async => const KostvAgeLimit(maxAge: 12));
      addTearDown(stremfin.dispose);
      stremfin.onUserChanged('kid');
      await stremfin.refreshAccess();

      final items = await stremfin.top(
        platform: 'all',
        type: StremfinTitleType.movie,
        list: StremfinTopList.popular,
      );

      expect(items.map((t) => t.tmdbId), [1, 4]);
      expect(topCall().uri.queryParameters['limit'], '40');
    });

    test('someone with no limit gets the lists as they come', () async {
      final stremfin = service(() async => KostvAgeLimit.none);
      addTearDown(stremfin.dispose);
      stremfin.onUserChanged('adult');
      await stremfin.refreshAccess();

      final items = await stremfin.top(
        platform: 'all',
        type: StremfinTitleType.movie,
        list: StremfinTopList.popular,
      );

      expect(items.map((t) => t.tmdbId), [1, 2, 3, 4]);
      expect(topCall().uri.queryParameters.containsKey('limit'), isFalse);
    });

    test('a search page left empty reads on to the next', () async {
      final stremfin = service(() async => const KostvAgeLimit(maxAge: 12));
      addTearDown(stremfin.dispose);
      stremfin.onUserChanged('kid');
      await stremfin.refreshAccess();

      final page = await stremfin.search('montaña');

      expect(page.items.map((t) => t.tmdbId), [11]);
      expect(page.nextCursor, isNull);
    });

    test("without the person's limit nothing shows, and Discover stays "
        'hidden', () async {
      final stremfin = service(() async => throw Exception('offline'));
      addTearDown(stremfin.dispose);
      stremfin.onUserChanged('kid');
      await stremfin.refreshAccess();

      expect(stremfin.isAllowed, isFalse);
      expect(stremfin.allows(titled(age: 0)), isFalse);
    });
  });

  group('asking while the service is busy', () {
    test('asks again, as the service says, and gets through', () async {
      var posts = 0;
      final adapter = FakeStremfinAdapter.withMethod((method, path, sent) {
        posts++;
        if (posts == 1) {
          return (
            status: 503,
            body: {
              'error': {'code': 'busy', 'message': 'Un momento.'},
            },
            headers: const <String, String>{},
          );
        }
        return (
          status: 201,
          body: {'outcome': 'created', 'message': 'Petición enviada.'},
          headers: const <String, String>{},
        );
      });
      final client = StremfinClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://requests.example.org/api/v1',
        token: () => 'abc123token',
      );

      final result = await client.createRequest(
        type: StremfinTitleType.movie,
        tmdbId: 920,
        busyPause: Duration.zero,
      );

      expect(posts, 2);
      expect(result.outcome.name, 'created');
    });

    test('gives up after asking three times', () async {
      var posts = 0;
      final adapter = FakeStremfinAdapter.withMethod((method, path, sent) {
        posts++;
        return (
          status: 503,
          body: {
            'error': {'code': 'busy', 'message': 'Un momento.'},
          },
          headers: const <String, String>{},
        );
      });
      final client = StremfinClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://requests.example.org/api/v1',
        token: () => 'abc123token',
      );

      await expectLater(
        client.createRequest(
          type: StremfinTitleType.movie,
          tmdbId: 920,
          busyPause: Duration.zero,
        ),
        throwsA(isA<StremfinException>().having((e) => e.code, 'code', 'busy')),
      );
      expect(posts, 3);
    });
  });
}
