import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';

import 'fake_stremfin_adapter.dart';

typedef _Reply = ({int status, Object? body, Map<String, String> headers});

/// Kos TV: asking the requests service for things, and reading how they
/// stand.
void main() {
  late FakeStremfinAdapter adapter;

  StremfinClient client() => StremfinClient(
    dio: Dio()..httpClientAdapter = adapter,
    baseUrl: 'https://requests.example.org/api/v1',
    token: () => 'abc123token',
  );

  void answer(_Reply Function(String method, String path, Object? sent) f) {
    adapter = FakeStremfinAdapter.withMethod(f);
  }

  Map<String, Object?> sentJson() {
    final data = adapter.calls.single.data;
    return (data is String ? jsonDecode(data) : data) as Map<String, Object?>;
  }

  group('a film', () {
    test('its page: what it is, and whether it can be asked for', () async {
      answer(
        (method, path, _) => (
          status: 200,
          body: {
            ...fakeTitle(920),
            'overview': 'Un coche de carreras…',
            'original_title': 'Cars',
            'runtime': 117,
            'genres': ['Animación', 'Comedia'],
            'download': null,
            'release': {
              'date': '2026-12-04',
              'text': 'Se estrena el 04/12/2026',
            },
            'can_request': {
              'allowed': true,
              'action': 'request',
              'reason': null,
            },
          },
          headers: const {},
        ),
      );
      final movie = await client().movie(920);

      expect(adapter.calls.single.uri.path, '/api/v1/movies/920');
      expect(movie.title.overview, 'Un coche de carreras…');
      expect(movie.runtime, 117);
      expect(movie.genres, ['Animación', 'Comedia']);
      expect(movie.release?.text, 'Se estrena el 04/12/2026');
      expect(movie.release?.date, DateTime(2026, 12, 4));
      expect(movie.canRequest.allowed, isTrue);
      expect(movie.canRequest.action, StremfinRequestAction.request);
      expect(movie.download, isNull);
    });

    test('one downloading says how far it has got', () async {
      answer(
        (method, path, _) => (
          status: 200,
          body: {
            ...fakeTitle(920),
            'download': {
              'status': 'downloading',
              'phase': 'downloading',
              'label': 'Descargando',
              'percent': 42,
              'downloaded_bytes': 4200,
              'total_bytes': 10000,
              'speed': 1500000,
              'eta_seconds': 300,
              'paused': false,
            },
            'can_request': {
              'allowed': true,
              'action': 'notify',
              'reason': null,
            },
          },
          headers: const {},
        ),
      );
      final movie = await client().movie(920);

      expect(movie.canRequest.action, StremfinRequestAction.notify);
      final transfer = movie.download!.transfer;
      expect(movie.download!.attention, isFalse);
      expect(transfer.phase, StremfinPhase.downloading);
      expect(transfer.percent, 42);
      expect(transfer.speed, 1500000);
      expect(transfer.etaSeconds, 300);
    });

    test('ready and at once: fast, with the version it would bring', () async {
      answer(
        (method, path, _) => (
          status: 200,
          body: {
            'tmdb_id': 920,
            'status': 'ready',
            'reason': null,
            'downloadable': true,
            'cached': true,
            'fast': true,
            'version': {
              'resolution': '1080p',
              'summary': '1080p · Castellano · 9,0 GB',
            },
            'criterion': 'en castellano de 1080p o más',
            'on_request': 'download',
          },
          headers: const {},
        ),
      );
      final availability = await client().movieAvailability(920);

      expect(adapter.calls.single.uri.path, '/api/v1/movies/920/availability');
      expect(availability.status, StremfinAvailabilityStatus.ready);
      expect(availability.fast, isTrue);
      expect(availability.summary, '1080p · Castellano · 9,0 GB');
      expect(availability.needsApproval, isFalse);
    });

    test('no good version yet: waits, and says what a good one is', () async {
      answer(
        (method, path, _) => (
          status: 200,
          body: {
            'status': 'waiting_version',
            'reason': 'quality',
            'cached': null,
            'fast': false,
            'version': null,
            'criterion': 'en castellano de 1080p o más',
            'on_request': 'review',
            'some_new_field': 1,
          },
          headers: const {},
        ),
      );
      final availability = await client().movieAvailability(920);

      expect(availability.status, StremfinAvailabilityStatus.waitingVersion);
      expect(availability.reason, 'quality');
      expect(availability.fast, isFalse);
      expect(availability.summary, isNull);
      expect(availability.criterion, 'en castellano de 1080p o más');
      expect(availability.needsApproval, isTrue);
    });
  });

  test('a series: season by season, without specials', () async {
    answer(
      (method, path, _) => (
        status: 200,
        body: {
          ...fakeTitle(1396, type: 'series'),
          'years': '2008–2013',
          'summary': {
            'aired': 62,
            'have': 7,
            'missing': 55,
            'missing_requestable': 55,
          },
          'can_request_all': true,
          'seasons': [
            {
              'season': 2,
              'aired': 13,
              'have': 0,
              'missing': 13,
              'status': 'missing',
              'request': null,
              'can_request': true,
            },
            {
              'season': 0,
              'aired': 4,
              'status': 'missing',
              'can_request': false,
            },
            {
              'season': 1,
              'aired': 7,
              'have': 7,
              'missing': 0,
              'status': 'complete',
              'request': {
                'id': 9,
                'status': 'approved',
                'mine': false,
                'requesters': ['Ana'],
              },
              'can_request': false,
            },
          ],
        },
        headers: const {},
      ),
    );
    final series = await client().series(1396);

    expect(adapter.calls.single.uri.path, '/api/v1/series/1396');
    expect(series.years, '2008–2013');
    expect(series.missingRequestable, 55);
    expect(series.canRequestAll, isTrue);
    expect(series.seasons.map((s) => s.number), [1, 2]);
    expect(series.seasons.first.status, StremfinSeasonStatus.complete);
    expect(series.seasons.first.request?.requesters, ['Ana']);
    expect(series.seasons.last.canRequest, isTrue);
  });

  group('asking for something', () {
    test('a film sends its type and id', () async {
      answer(
        (method, path, sent) => (
          status: 201,
          body: {
            'outcome': 'started',
            'message': 'En marcha.',
            'request': {
              'id': 57,
              'type': 'movie',
              'tmdb_id': 920,
              'status': 'approved',
              'direct': true,
              'mine': true,
              'progress': {'state': 'accepted', 'label': 'Aceptada'},
            },
          },
          headers: const {},
        ),
      );
      final result = await client().createRequest(
        type: StremfinTitleType.movie,
        tmdbId: 920,
      );

      final call = adapter.calls.single;
      expect(call.method, 'POST');
      expect(call.uri.path, '/api/v1/requests');
      expect(call.headers['Authorization'], 'Bearer abc123token');
      expect(sentJson(), {'type': 'movie', 'tmdb_id': 920});
      expect(result.outcome, StremfinOutcome.started);
      expect(result.request?.id, 57);
      expect(result.request?.status, StremfinRequestStatus.approved);
      expect(result.request?.progress?.state, StremfinProgressState.accepted);
    });

    test('a season, or all that is missing (season null)', () async {
      answer(
        (method, path, sent) => (
          status: 201,
          body: {
            'outcome': 'created',
            'request': {'id': 3, 'status': 'pending', 'can_withdraw': true},
          },
          headers: const {},
        ),
      );
      final result = await client().createRequest(
        type: StremfinTitleType.series,
        tmdbId: 1396,
        season: 2,
      );
      expect(sentJson(), {'type': 'series', 'tmdb_id': 1396, 'season': 2});
      expect(result.outcome, StremfinOutcome.created);
      expect(result.request?.canWithdraw, isTrue);
      expect(result.request?.progress, isNull);

      await client().createRequest(
        type: StremfinTitleType.series,
        tmdbId: 1396,
      );
      final all = adapter.calls.last.data;
      final json = (all is String ? jsonDecode(all) : all) as Map;
      expect(json, {'type': 'series', 'tmdb_id': 1396, 'season': null});
    });

    test(
      'an answer with an outcome is a result, whatever its status',
      () async {
        for (final (status, outcome, expected) in [
          (409, 'have', StremfinOutcome.have),
          (409, 'busy', StremfinOutcome.busy),
          (422, 'unavailable', StremfinOutcome.unavailable),
          (200, 'already', StremfinOutcome.already),
          (200, 'something_new', StremfinOutcome.unknown),
        ]) {
          answer(
            (method, path, sent) => (
              status: status,
              body: {'outcome': outcome, 'message': 'Texto.', 'request': null},
              headers: const {},
            ),
          );
          final result = await client().createRequest(
            type: StremfinTitleType.movie,
            tmdbId: 1,
          );
          expect(result.outcome, expected, reason: outcome);
          expect(result.message, 'Texto.');
        }
      },
    );

    test('the limit says which one and when it frees up', () async {
      answer(
        (method, path, sent) => (
          status: 429,
          body: {
            'outcome': 'limit',
            'limit': 'daily',
            'message': 'Mañana más.',
            'request': null,
          },
          headers: const {'retry-after': '3600'},
        ),
      );
      final result = await client().createRequest(
        type: StremfinTitleType.movie,
        tmdbId: 1,
      );
      expect(result.outcome, StremfinOutcome.limit);
      expect(result.limit, 'daily');
      expect(result.retryAfter, const Duration(hours: 1));
    });

    test(
      'an answer with an error is an error, even at the same status',
      () async {
        answer(
          (method, path, sent) => (
            status: 422,
            body: {
              'error': {'code': 'invalid', 'message': 'Falta el tipo.'},
            },
            headers: const {},
          ),
        );
        final error = await client()
            .createRequest(type: StremfinTitleType.movie, tmdbId: 1)
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(error, isA<StremfinException>());
        expect((error! as StremfinException).code, 'invalid');
      },
    );
  });

  test('a request downloading: phase, percent, speed and time left', () async {
    answer(
      (method, path, _) => (
        status: 200,
        body: {
          'id': 57,
          'type': 'series',
          'display_title': 'Severance · Temporada 2',
          'season': 2,
          'status': 'approved',
          'status_label': 'Aceptada',
          'can_withdraw': false,
          'requesters': ['Luis'],
          'progress': {
            'state': 'downloading',
            'label': 'Descargando',
            'phase': 'waiting_file',
            'percent': 140,
            'waiting_since': '2026-11-11T10:00:00+01:00',
            'paused': true,
            'episodes_done': 5,
            'episodes_total': 13,
            'episodes_attention': 0,
          },
          'updated_at': '2026-11-11T09:02:10+01:00',
        },
        headers: const {},
      ),
    );
    final request = await client().request(57);

    expect(adapter.calls.single.method, 'GET');
    expect(adapter.calls.single.uri.path, '/api/v1/requests/57');
    expect(request.displayTitle, 'Severance · Temporada 2');
    expect(request.status.isOpen, isTrue);
    final progress = request.progress!;
    expect(progress.state, StremfinProgressState.downloading);
    expect(progress.transfer.phase, StremfinPhase.waitingFile);
    expect(progress.transfer.percent, 100, reason: 'never past 100');
    expect(progress.transfer.paused, isTrue);
    expect(progress.transfer.waitingSince, isNotNull);
    expect(progress.episodesDone, 5);
    expect(progress.episodesTotal, 13);
    expect(request.asRef?.status, 'approved');
  });

  test('a finished or turned-down request is not open', () {
    final done = StremfinRequest.fromJson({'id': 1, 'status': 'completed'})!;
    final no = StremfinRequest.fromJson({
      'id': 2,
      'status': 'rejected',
      'reason': 'quality',
      'progress': {'state': 'downloading'},
    })!;
    expect(done.status.isOpen, isFalse);
    expect(done.asRef, isNull);
    expect(no.reason, 'quality');
    expect(no.progress, isNull, reason: 'progress only while accepted');
  });

  test('withdrawing sends a DELETE; a refusal is an error', () async {
    answer(
      (method, path, _) => (
        status: 200,
        body: {'outcome': 'withdrawn', 'message': 'Petición retirada.'},
        headers: const {},
      ),
    );
    await client().withdrawRequest(57);
    expect(adapter.calls.single.method, 'DELETE');
    expect(adapter.calls.single.uri.path, '/api/v1/requests/57');

    answer(
      (method, path, _) => (
        status: 409,
        body: {
          'error': {
            'code': 'already_answered',
            'message': 'Ya tiene respuesta.',
          },
        },
        headers: const {},
      ),
    );
    final error = await client()
        .withdrawRequest(57)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect((error! as StremfinException).code, 'already_answered');
  });

  test('who the person is: their mode and their limit', () async {
    answer(
      (method, path, _) => (
        status: 200,
        body: {
          'user': {'name': 'Mamá', 'role': 'member'},
          'access': {
            'can_request': true,
            'mode': 'review',
            'limit': 3,
            'pending': 3,
            'daily_left': 10,
            'at_limit': true,
          },
        },
        headers: const {},
      ),
    );
    final me = await client().me();
    expect(me.name, 'Mamá');
    expect(me.needsApproval, isTrue);
    expect(me.atLimit, isTrue);
    expect(me.limit, 3);
    expect(me.pending, 3);
    expect(me.dailyLeft, 10);
  });
}
