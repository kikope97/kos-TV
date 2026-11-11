import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/ui/screens/discover/kostv_request_controller.dart';

import 'fake_stremfin_life.dart';

/// Kos TV: a title's request page asks how the request stands every few
/// seconds while it is in sight, and gives way to the title once it
/// arrives.
/// Lets the calls in flight finish (Dio answers through short timers).
void settle(FakeAsync async) => async.elapse(const Duration(milliseconds: 20));

void main() {
  late FakeStremfinLife fake;

  setUp(() => fake = FakeStremfinLife());

  KostvMovieRequestController movie(FakeAsync async) {
    final service = fake.service();
    service.onUserChanged('kiko');
    final c = KostvMovieRequestController(
      service: service,
      tmdbId: 920,
      watchLifecycle: false,
    );
    c.load();
    settle(async);
    return c;
  }

  int polls() => fake.calls.where((c) => c.startsWith('GET /requests/')).length;

  test('a film not on the server: fast, nothing asked again', () {
    fakeAsync((async) {
      final c = movie(async);
      expect(c.loading, isFalse);
      expect(c.detail?.title.title, 'Cars');
      expect(c.availability?.fast, isTrue);
      expect(c.request, isNull);
      expect(c.isPolling, isFalse);
      // Page and availability were asked for together.
      expect(fake.calls, contains('GET /movies/920/availability'));
      c.dispose();
    });
  });

  test('asked for directly: follows it down, then gives way to it', () {
    fakeAsync((async) {
      final c = movie(async);
      final notices = <KostvRequestNotice>[];
      c.onNotice = notices.add;

      c.ask();
      settle(async);
      expect(notices.single.result?.outcome, StremfinOutcome.started);
      expect(c.request?.status, StremfinRequestStatus.approved);
      // Accepted, nothing downloading: asked again every 15 s.
      expect(c.isPolling, isTrue);
      final id = c.request!.id;

      fake.download(id, 40);
      async.elapse(KostvRequestController.slowInterval);
      expect(c.request?.progress?.transfer.percent, 40);

      // Downloading: every 5 s.
      fake.download(id, 80);
      final before = polls();
      async.elapse(KostvRequestController.quickInterval);
      expect(polls(), before + 1);
      expect(c.request?.progress?.transfer.percent, 80);

      fake.complete(id);
      async.elapse(KostvRequestController.quickInterval);
      expect(c.arrivedItemId, 'cars-item');
      expect(c.arrivedOnOpen, isFalse);
      expect(c.isPolling, isFalse);
      c.dispose();
    });
  });

  test('arrived but not yet ready to open: keeps asking', () {
    fakeAsync((async) {
      final c = movie(async);
      c.ask();
      settle(async);
      final id = c.request!.id;

      fake.complete(id, indexed: false);
      async.elapse(KostvRequestController.slowInterval);
      expect(c.arrivingSoon, isTrue);
      expect(c.arrivedItemId, isNull);
      expect(c.isPolling, isTrue);

      fake.movieLibrary = 'available';
      async.elapse(KostvRequestController.slowInterval);
      expect(c.arrivedItemId, 'cars-item');
      c.dispose();
    });
  });

  test('waiting for approval: can be taken back', () {
    fakeAsync((async) {
      fake.mode = 'review';
      final c = movie(async);
      final notices = <KostvRequestNotice>[];
      c.onNotice = notices.add;

      c.ask();
      settle(async);
      expect(notices.single.result?.outcome, StremfinOutcome.created);
      expect(c.request?.status, StremfinRequestStatus.pending);
      expect(c.request?.canWithdraw, isTrue);
      expect(c.isPolling, isTrue);

      c.withdraw();
      settle(async);
      expect(notices.last.withdrawn, isTrue);
      expect(c.request, isNull);
      expect(fake.requests, isEmpty);
      expect(c.isPolling, isFalse);
      c.dispose();
    });
  });

  test('turned down: says why, and it can be asked for again', () {
    fakeAsync((async) {
      fake.mode = 'review';
      final c = movie(async);
      c.ask();
      settle(async);

      fake.reject(c.request!.id, 'quality');
      async.elapse(KostvRequestController.slowInterval);
      expect(c.request, isNull);
      expect(c.rejected?.reason, 'quality');
      expect(c.detail?.canRequest.allowed, isTrue);
      expect(c.isPolling, isFalse);
      c.dispose();
    });
  });

  test('accepted by the administrator: from pending to downloading', () {
    fakeAsync((async) {
      fake.mode = 'review';
      final c = movie(async);
      c.ask();
      settle(async);
      final id = c.request!.id;

      fake
        ..approve(id)
        ..download(id, 10);
      async.elapse(KostvRequestController.slowInterval);
      expect(c.request?.status, StremfinRequestStatus.approved);
      expect(c.request?.progress?.state, StremfinProgressState.downloading);
      c.dispose();
    });
  });

  test('only asks while in sight, and catches up when back', () {
    fakeAsync((async) {
      final c = movie(async);
      c.ask();
      settle(async);
      final id = c.request!.id;
      fake.download(id, 10);
      async.elapse(KostvRequestController.slowInterval);

      c.setVisible(false);
      final hidden = polls();
      async.elapse(const Duration(minutes: 2));
      expect(polls(), hidden, reason: 'nothing while covered');

      fake.download(id, 90);
      c.setVisible(true);
      settle(async);
      async.elapse(Duration.zero);
      expect(polls(), hidden + 1, reason: 'asks at once on coming back');
      expect(c.request?.progress?.transfer.percent, 90);
      c.dispose();
    });
  });

  test('the service not answering: tries again a little later', () {
    fakeAsync((async) {
      final c = movie(async);
      c.ask();
      settle(async);
      fake.download(c.request!.id, 10);
      async.elapse(KostvRequestController.slowInterval);

      fake.failNext = 503;
      final before = polls();
      async.elapse(KostvRequestController.quickInterval);
      expect(polls(), before + 1);
      // Not again in 5 s, but in 30.
      async.elapse(KostvRequestController.quickInterval);
      expect(polls(), before + 1);
      async.elapse(KostvRequestController.backoffInterval);
      expect(polls(), greaterThan(before + 1));
      expect(c.request?.progress?.transfer.percent, 10);
      c.dispose();
    });
  });

  test('already on the server when opened: straight to it', () {
    fakeAsync((async) {
      fake.movieLibrary = 'available';
      final c = movie(async);
      expect(c.arrivedItemId, 'cars-item');
      expect(c.arrivedOnOpen, isTrue);
      expect(c.isPolling, isFalse);
      c.dispose();
    });
  });

  test('downloading for someone else: "notify me" and how it goes', () {
    fakeAsync((async) {
      fake.movieDownload = {
        'status': 'downloading',
        'phase': 'downloading',
        'percent': 30,
      };
      final c = movie(async);
      expect(c.detail?.canRequest.action, StremfinRequestAction.notify);
      expect(c.detail?.download?.transfer.percent, 30);
      expect(c.isPolling, isTrue);
      c.dispose();
    });
  });

  group('a series', () {
    KostvSeriesRequestController series(FakeAsync async) {
      final service = fake.service();
      service.onUserChanged('kiko');
      final c = KostvSeriesRequestController(
        service: service,
        tmdbId: 1396,
        watchLifecycle: false,
      );
      c.load();
      settle(async);
      return c;
    }

    test('a season asked for, followed until it is there', () {
      fakeAsync((async) {
        final c = series(async);
        expect(c.detail?.seasons, hasLength(3));
        expect(c.detail?.canRequestAll, isTrue);
        expect(c.isPolling, isFalse);

        c.ask(season: 2);
        settle(async);
        final season2 = c.detail!.seasons[1];
        final request = c.requestFor(season2);
        expect(request?.season, 2);
        expect(season2.canRequest, isFalse);
        expect(c.isPolling, isTrue);
        expect(c.sendingSeason, isNull);

        fake.download(request!.id, 50);
        async.elapse(KostvRequestController.slowInterval);
        expect(
          c.requestFor(c.detail!.seasons[1])?.progress?.transfer.percent,
          50,
        );

        fake.complete(request.id);
        async.elapse(KostvRequestController.quickInterval);
        expect(c.arrivedItemId, 'marea-item');
        expect(c.arrivedOnOpen, isFalse);
        c.dispose();
      });
    });

    test('everything missing, in one request', () {
      fakeAsync((async) {
        final c = series(async);
        c.ask();
        settle(async);
        expect(c.wholeRequest?.wholeSeries, isTrue);
        expect(c.detail?.canRequestAll, isFalse);
        expect(
          c.detail!.seasons
              .where((s) => s.number > 1)
              .every((s) => c.requestFor(s)?.id == c.wholeRequest?.id),
          isTrue,
        );
        c.dispose();
      });
    });

    test('at the limit: nothing is made', () {
      fakeAsync((async) {
        fake.atLimit = true;
        final c = series(async);
        final notices = <KostvRequestNotice>[];
        c.onNotice = notices.add;
        c.ask(season: 3);
        settle(async);
        expect(notices.single.result?.outcome, StremfinOutcome.limit);
        expect(notices.single.result?.limit, 'daily');
        expect(c.requests, isEmpty);
        expect(c.service.me?.atLimit, isTrue);
        c.dispose();
      });
    });
  });
}
