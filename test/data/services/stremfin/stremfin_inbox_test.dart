import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/stremfin_inbox.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../ui/screens/discover/fake_stremfin_life.dart';

/// Lets the calls in flight finish (Dio answers through short timers).
void settle(FakeAsync async) => async.elapse(const Duration(milliseconds: 50));

/// Kos TV: the requests tray: the person's own requests, what is new to
/// them and what is under way.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeStremfinLife fake;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fake = FakeStremfinLife();
  });

  StremfinService start(FakeAsync async, {String user = 'kiko'}) {
    final service = fake.service()..onUserChanged(user);
    settle(async);
    return service;
  }

  /// Asks for the film through the fake service, as someone would.
  int askFilm() {
    fake.answer('POST', '/requests', {'type': 'movie', 'tmdb_id': 920});
    return fake.requests.keys.last;
  }

  test('only their own: in full once, then only what changed', () {
    fakeAsync((async) {
      final service = start(async);
      expect(fake.listQueries.first['scope'], 'mine');
      expect(fake.listQueries.first['status'], 'all');
      expect(fake.listQueries.first.containsKey('since'), isFalse);
      expect(service.inbox.isLoaded, isTrue);

      async.elapse(StremfinInbox.syncInterval);
      expect(fake.listQueries.last['scope'], 'mine');
      expect(fake.listQueries.last['since'], startsWith('t'));
      service.dispose();
    });
  });

  test('what had happened before the first time is not news', () {
    fakeAsync((async) {
      final id = askFilm();
      fake.complete(id);
      final service = start(async);
      expect(service.inbox.finished.single.id, id);
      expect(service.inbox.newsCount, 0);
      service.dispose();
    });
  });

  test('accepted by the administrator, then arrived: news until seen', () {
    fakeAsync((async) {
      fake.mode = 'review';
      final service = start(async);
      final inbox = service.inbox;
      service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
      settle(async);
      final id = fake.requests.keys.single;
      expect(inbox.hasActive, isTrue);
      expect(inbox.newsCount, 0, reason: 'waiting for an answer');

      fake.approve(id);
      async.elapse(StremfinInbox.syncInterval);
      expect(inbox.newsCount, 1);
      expect(inbox.news.single.status, StremfinRequestStatus.approved);

      inbox.markAllSeen();
      settle(async);
      expect(inbox.newsCount, 0);

      fake.complete(id);
      async.elapse(StremfinInbox.syncInterval);
      expect(inbox.newsCount, 1);
      expect(inbox.news.single.status, StremfinRequestStatus.completed);
      expect(inbox.hasActive, isFalse);
      service.dispose();
    });
  });

  test('accepted on its own is not news; turned down is', () {
    fakeAsync((async) {
      final service = start(async);
      final inbox = service.inbox;
      service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
      settle(async);
      async.elapse(StremfinInbox.syncInterval);
      expect(inbox.active.single.direct, isTrue);
      expect(inbox.newsCount, 0);

      fake.mode = 'review';
      service.createRequest(
        type: StremfinTitleType.series,
        tmdbId: 1396,
        season: 3,
      );
      settle(async);
      fake.reject(fake.requests.keys.last, 'later');
      async.elapse(StremfinInbox.syncInterval);
      expect(inbox.newsCount, 1);
      expect(inbox.news.single.reason, 'later');
      service.dispose();
    });
  });

  test('what was seen is kept on the device, for each person', () {
    fakeAsync((async) {
      fake.mode = 'review';
      var service = start(async);
      service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
      settle(async);
      fake.approve(fake.requests.keys.single);
      async.elapse(StremfinInbox.syncInterval);
      expect(service.inbox.newsCount, 1);
      service.inbox.markAllSeen();
      settle(async);
      service.dispose();

      // The app opened again: still seen.
      service = start(async);
      expect(service.inbox.newsCount, 0);
      service.dispose();
    });
  });

  test('seen on its own page is not news', () {
    fakeAsync((async) {
      fake.mode = 'review';
      final service = start(async);
      service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
      settle(async);
      final id = fake.requests.keys.single;
      fake.approve(id);
      // The page of the film asks how it stands, and shows it.
      service.request(id);
      settle(async);
      async.elapse(StremfinInbox.syncInterval);
      expect(service.inbox.newsCount, 0);
      service.dispose();
    });
  });

  test('with the tray open, what is under way is followed live', () {
    fakeAsync((async) {
      final service = start(async);
      final inbox = service.inbox;
      service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
      settle(async);
      final id = fake.requests.keys.single;
      fake.download(id, 30);

      inbox.watch();
      settle(async);
      expect(fake.listQueries.last['status'], 'open');
      expect(inbox.active.single.progress?.transfer.percent, 30);
      expect(inbox.hasDownloading, isTrue);

      fake.download(id, 60);
      async.elapse(StremfinInbox.liveQuick);
      expect(inbox.active.single.progress?.transfer.percent, 60);

      // It arrives: no longer open, so what happened is asked, and it is news.
      fake.complete(id);
      async.elapse(StremfinInbox.liveQuick);
      expect(inbox.active, isEmpty);
      expect(inbox.newsCount, 1);

      inbox.unwatch();
      final asked = fake.listQueries.length;
      async.elapse(const Duration(minutes: 1));
      expect(fake.listQueries.length, asked, reason: 'closed: not followed');
      service.dispose();
    });
  });

  test('taken back: gone from the tray', () {
    fakeAsync((async) {
      fake.mode = 'review';
      final service = start(async);
      service.createRequest(type: StremfinTitleType.movie, tmdbId: 920);
      settle(async);
      expect(service.inbox.active, hasLength(1));
      service.withdrawRequest(fake.requests.keys.single);
      settle(async);
      expect(service.inbox.active, isEmpty);
      service.dispose();
    });
  });

  test('another person starts with an empty tray', () {
    fakeAsync((async) {
      askFilm();
      final service = start(async);
      expect(service.inbox.active, hasLength(1));
      service.onUserChanged('ana');
      expect(service.inbox.active, isEmpty);
      service.dispose();
    });
  });
}
