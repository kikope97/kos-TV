import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/kostv_age_gate.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_error_text.dart';
import 'package:moonfin/data/services/stremfin/stremfin_inbox.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_music_memory.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/util/parental_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../ui/screens/discover/fake_stremfin_life.dart';
import 'fake_stremfin_adapter.dart';

/// Holds back the answers to the paths [slow] says, for [delay].
class _SlowAdapter implements HttpClientAdapter {
  _SlowAdapter(
    this._inner,
    this.slow, {
    this.delay = const Duration(seconds: 10),
  });

  final HttpClientAdapter _inner;
  final bool Function(String path) slow;
  final Duration delay;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (slow(options.uri.path)) await Future<void>.delayed(delay);
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

const _noHeaders = <String, String>{};

/// Kos TV: what the audit of the requests service's layer found, fixed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  void settle(FakeAsync async) =>
      async.elapse(const Duration(milliseconds: 50));

  StremfinService serviceOn(
    HttpClientAdapter adapter, {
    String? Function()? token,
    bool Function()? kidsMode,
    Listenable? kidsModeChanges,
  }) => StremfinService(
    StremfinClient(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://stremfin.ejemplo.com/api/v1',
      token: token ?? () => 'token',
    ),
    ageLimit: () async => KostvAgeLimit.none,
    parental: () => ParentalFilter.none,
    watchLifecycle: false,
    kidsMode: kidsMode,
    kidsModeChanges: kidsModeChanges,
  );

  group('trailers', () {
    var role = 'none';
    late FakeStremfinAdapter adapter;

    setUp(() {
      role = 'none';
      adapter = FakeStremfinAdapter((path, _) {
        if (path == '/me') {
          return role == 'none'
              ? (
                  status: 403,
                  body: {
                    'error': {'code': 'no_access', 'message': 'No.'},
                  },
                  headers: _noHeaders,
                )
              : (
                  status: 200,
                  body: {
                    'user': {'role': role},
                    'access': {'can_request': true},
                  },
                  headers: _noHeaders,
                );
        }
        if (path.endsWith('/trailers')) {
          return (
            status: 200,
            body: {
              'items': [
                {
                  'key': 'es1',
                  'url': 'https://www.youtube.com/watch?v=es1',
                  'language': 'es',
                  'country': 'ES',
                },
              ],
            },
            headers: _noHeaders,
          );
        }
        return (status: 404, body: null, headers: _noHeaders);
      });
    });

    test('one asked for while turned down is asked again once let in', () async {
      final service = serviceOn(adapter);
      addTearDown(service.dispose);
      service.onUserChanged('someone');
      // Turned down: the first one checks, the next ones are answered at once.
      expect(await service.trailers(StremfinTitleType.movie, 597), isEmpty);
      expect(await service.trailers(StremfinTitleType.movie, 598), isEmpty);

      role = 'member';
      await service.refreshAccess();
      expect(service.isAllowed, isTrue);
      // The empty answer from before wasn't kept for the session.
      expect(
        await service.trailers(StremfinTitleType.movie, 598),
        hasLength(1),
      );
      expect(
        await service.trailers(StremfinTitleType.movie, 597),
        hasLength(1),
      );
    });

    test('a check of the person that doesn\'t answer doesn\'t hold up the '
        'trailer', () {
      fakeAsync((async) {
        final service = serviceOn(
          _SlowAdapter(
            adapter,
            (p) => p.endsWith('/me'),
            delay: const Duration(seconds: 30),
          ),
        );
        role = 'member';
        List<StremfinTrailer>? got;
        service.trailers(StremfinTitleType.movie, 597).then((t) => got = t);
        async.elapse(StremfinService.trailersTimeout);
        settle(async);
        expect(got, isEmpty);
        // The check carries on and lets the person in.
        async.elapse(const Duration(seconds: 30));
        expect(service.isAllowed, isTrue);
        service.dispose();
      });
    });
  });

  group('the requests tray', () {
    late FakeStremfinLife fake;

    setUp(() => fake = FakeStremfinLife());

    StremfinService start(FakeAsync async, {String user = 'kiko'}) {
      final service = fake.service()..onUserChanged(user);
      settle(async);
      return service;
    }

    test(
      'someone else\'s request, read on a title\'s page, stays out of it',
      () {
        fakeAsync((async) {
          final service = start(async);
          // Ana's, on the service (it never comes in the person's own list).
          fake.requests[99] = {
            'id': 99,
            'type': 'movie',
            'tmdb_id': 920,
            'status': 'approved',
            'mine': false,
            'requesters': ['Ana'],
            'progress': {'state': 'downloading', 'percent': 45},
          };
          service.request(99);
          settle(async);
          expect(service.inbox.active, isEmpty);
          expect(service.inbox.hasActive, isFalse);
          service.dispose();
        });
      },
    );

    test('their own, read on its page, is brought up to date there, and only '
        'a change is told', () {
      fakeAsync((async) {
        fake.mode = 'review';
        final service = start(async);
        service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
        settle(async);
        final id = fake.requests.keys.single;
        var told = 0;
        service.inbox.addListener(() => told++);

        service.request(id);
        settle(async);
        service.request(id);
        settle(async);
        expect(told, 0, reason: 'read again as it was');

        fake.approve(id);
        service.request(id);
        settle(async);
        expect(told, 1);
        expect(
          service.inbox.active.single.status,
          StremfinRequestStatus.approved,
        );
        service.dispose();
      });
    });

    test('what was seen isn\'t lost while the list can\'t be read', () {
      fakeAsync((async) {
        fake.mode = 'review';
        // Asked for, one arrived, the other waiting: the first time on the
        // device, nothing of it is news.
        var service = start(async);
        service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
        settle(async);
        service.createRequest(
          type: StremfinTitleType.series,
          tmdbId: 1396,
          season: 2,
        );
        settle(async);
        final film = fake.requests.keys.first;
        final season = fake.requests.keys.last;
        fake.complete(film);
        async.elapse(StremfinInbox.syncInterval);
        service.inbox.markAllSeen();
        settle(async);
        service.dispose();

        // The app opens again and the service doesn't answer the list; the
        // person opens the season's page meanwhile.
        fake.approve(season);
        fake.failNext = 503;
        service = start(async);
        expect(service.inbox.isLoaded, isFalse);
        service.request(season);
        settle(async);

        async.elapse(StremfinInbox.syncInterval);
        expect(service.inbox.isLoaded, isTrue);
        expect(service.inbox.newsCount, 0);
        service.dispose();
      });
    });

    test(
      'another person signed in while the list was being read gets theirs',
      () {
        fakeAsync((async) {
          var slow = true;
          final service = serviceOn(
            _SlowAdapter(fake.adapter, (p) => slow && p.endsWith('/requests')),
          );
          fake.mode = 'review';
          service.onUserChanged('kiko');
          settle(async);
          expect(service.inbox.isLoaded, isFalse, reason: 'still reading');

          slow = false;
          service.onUserChanged('ana');
          settle(async);
          expect(service.inbox.isLoaded, isTrue);
          // And it goes on asking.
          final asked = fake.listQueries.length;
          async.elapse(const Duration(seconds: 10));
          async.elapse(StremfinInbox.syncInterval);
          expect(fake.listQueries.length, greaterThan(asked));
          service.dispose();
        });
      },
    );

    test('kids mode: nothing asked until it goes', () {
      fakeAsync((async) {
        var kids = false;
        final changes = ValueNotifier(0);
        final service = serviceOn(
          fake.adapter,
          kidsMode: () => kids,
          kidsModeChanges: changes,
        );
        service.onUserChanged('kiko');
        settle(async);
        final asked = fake.listQueries.length;
        expect(asked, 1);

        kids = true;
        changes.value++;
        async.elapse(StremfinInbox.syncInterval * 3);
        expect(fake.listQueries.length, asked);

        kids = false;
        changes.value++;
        settle(async);
        expect(fake.listQueries.length, asked + 1);
        async.elapse(StremfinInbox.syncInterval);
        expect(fake.listQueries.length, asked + 2);
        service.dispose();
      });
    });
  });

  test('a session turned down is asked about again once it changes', () async {
    var token = 'old';
    final adapter = FakeStremfinAdapter((path, _) {
      if (path == '/me' && token == 'old') {
        return (
          status: 401,
          body: {
            'error': {'code': 'invalid_token', 'message': 'No.'},
          },
          headers: _noHeaders,
        );
      }
      return (
        status: 200,
        body: {
          'user': {'role': 'member'},
          'access': {'can_request': true},
        },
        headers: _noHeaders,
      );
    });
    final service = serviceOn(adapter, token: () => token);
    addTearDown(service.dispose);
    service.onUserChanged('kiko');
    await service.refreshAccess();
    expect(service.access, StremfinAccess.denied);

    // The same session again: not asked again.
    final calls = adapter.calls.length;
    service.onUserChanged('kiko');
    await Future<void>.delayed(Duration.zero);
    expect(adapter.calls.length, calls);

    // Signed in again: another session.
    token = 'new';
    service.onUserChanged('kiko');
    await service.refreshAccess();
    expect(service.isAllowed, isTrue);
  });

  group('music', () {
    final asked = <Map<String, String>>[];
    late FakeStremfinAdapter adapter;

    setUp(() {
      asked.clear();
      adapter = FakeStremfinAdapter((path, query) {
        if (path == '/me') {
          return (
            status: 200,
            body: {
              'user': {'role': 'member'},
              'access': {'can_request': true},
            },
            headers: _noHeaders,
          );
        }
        if (path == '/music/search') {
          return (
            status: 200,
            body: {
              'artists': [
                {'deezer_id': '7', 'name': 'Tyler, The Creator'},
              ],
            },
            headers: _noHeaders,
          );
        }
        if (path == '/music/recommendations') {
          asked.add(query);
          return (
            status: 200,
            body: {'seeds': [], 'items': []},
            headers: _noHeaders,
          );
        }
        return (status: 404, body: null, headers: _noHeaders);
      });
    });

    test('«Para ti»: a name with a comma goes by its id, and two at once ask '
        'once', () async {
      final service = serviceOn(adapter);
      addTearDown(service.dispose);
      await Future.wait([
        service.musicRecommendations(['Rosalía', 'Tyler, The Creator']),
        service.musicRecommendations(['Rosalía', 'Tyler, The Creator']),
      ]);
      expect(asked, hasLength(1));
      expect(asked.single['artists'], 'Rosalía');
      expect(asked.single['artist_ids'], '7');
    });

    test('a chart read for one person isn\'t kept for the next', () {
      fakeAsync((async) {
        final service = serviceOn(
          _SlowAdapter(adapter, (p) => p.contains('/music/charts/')),
        );
        service.onUserChanged('kiko');
        settle(async);
        service.musicChart('top-songs').ignore();
        settle(async);
        service.onUserChanged('ana');
        async.elapse(const Duration(seconds: 11));
        final before = adapter.calls.length;
        service.musicChart('top-songs').ignore();
        settle(async);
        async.elapse(const Duration(seconds: 11));
        expect(
          adapter.calls
              .skip(before)
              .where((c) => c.uri.path.contains('/music/charts/')),
          hasLength(1),
        );
        service.dispose();
      });
    });
  });

  test('music kept just before signing out isn\'t written afterwards', () {
    fakeAsync((async) {
      final memory = StremfinMusicMemory();
      memory.write('kiko', '/music/charts/top-songs?', {'items': []});
      memory.clear();
      async.elapse(const Duration(seconds: 3));
      Object? read = 'x';
      memory.read('kiko', '/music/charts/top-songs?').then((v) => read = v);
      async.flushMicrotasks();
      expect(read, isNull);
      Object? stored = 'x';
      SharedPreferences.getInstance().then(
        (p) => stored = p.getString('kostv_music_memory'),
      );
      async.flushMicrotasks();
      expect(stored, isNull);
    });
  });

  test('a film\'s availability asked twice at once is asked once', () async {
    final fake = FakeStremfinLife();
    final service = fake.service();
    addTearDown(service.dispose);
    service.onUserChanged('kiko');
    await Future.wait([
      service.movieAvailability(920),
      service.movieAvailability(920),
    ]);
    await service.movieAvailability(920);
    expect(fake.calls.where((c) => c.endsWith('/availability')), hasLength(1));
  });

  test('a request of one episode keeps it in its short form', () {
    final request = StremfinRequest.fromJson({
      'id': 5,
      'type': 'series',
      'tmdb_id': 1396,
      'season': 2,
      'episode': 3,
      'status': 'pending',
    })!;
    expect(request.episode, 3);
    expect(request.asRef?.episode, 3);
  });

  test('the address works whatever case its scheme is in', () {
    expect(
      StremfinClient.apiBaseFor('HTTPS://stremfin.ejemplo.com/'),
      'https://stremfin.ejemplo.com/api/v1',
    );
    expect(
      StremfinClient.apiBaseFor('Http://stremfin.ejemplo.com'),
      'https://stremfin.ejemplo.com/api/v1',
    );
  });

  test('each of the service\'s errors has its own words', () {
    final es = lookupAppLocalizations(const Locale('es'));
    final en = lookupAppLocalizations(const Locale('en'));
    String text(AppLocalizations l10n, String code, [int? status]) =>
        kostvStremfinErrorText(
          l10n,
          StremfinException(code: code, status: status),
          fallback: 'otro',
        );
    expect(text(es, 'api_disabled', 503), es.kostvStremfinErrorDisabled);
    expect(text(en, 'api_disabled', 503), en.kostvStremfinErrorDisabled);
    expect(text(es, 'no_access', 403), es.kostvStremfinErrorNoAccess);
    expect(text(es, 'busy', 503), es.kostvStremfinErrorBusy);
    expect(text(es, 'network'), es.kostvStremfinErrorUnreachable);
    expect(text(es, 'too_many_requests', 429), es.kostvRequestTooFast);
    expect(text(es, 'http_418', 418), 'otro');
    expect(
      kostvStremfinErrorText(es, StateError('x'), fallback: 'otro'),
      'otro',
    );
  });
}
