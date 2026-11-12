import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/stremfin/kostv_age_gate.dart';
import 'package:moonfin/data/services/stremfin/kostv_series_gaps.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/util/parental_filter.dart';

import 'fake_stremfin_adapter.dart';

/// Kos TV: the episodes of a series at home that the home server lacks.
void main() {
  Map<String, Object?> episode(
    int n, {
    bool aired = true,
    bool have = false,
    bool downloading = false,
    Map<String, Object?>? request,
    bool? canRequest,
  }) => {
    'episode': n,
    'title': 'Episodio $n',
    'air_date':
        '${aired ? '2024-01' : '2027-03'}-${n.toString().padLeft(2, '0')}',
    'aired': aired,
    'in_jellyfin': have,
    'downloading': downloading,
    'request': request,
    'can_request':
        canRequest ?? (aired && !have && !downloading && request == null),
  };

  Map<String, Object?> season(
    int n,
    List<Map<String, Object?>> episodes, {
    bool canRequest = true,
  }) => {
    'season': n,
    'title': 'Temporada $n',
    'aired': episodes.where((e) => e['aired'] == true).length,
    'have': episodes.where((e) => e['in_jellyfin'] == true).length,
    'missing': 0,
    'status': 'partial',
    'request': null,
    'can_request': canRequest,
    'episodes': episodes,
  };

  StremfinSeriesDetail detail(List<Map<String, Object?>> seasons) =>
      StremfinSeriesDetail.fromJson({
        'type': 'series',
        'tmdb_id': 456,
        'title': 'Los Simpson',
        'age': 7,
        'seasons': seasons,
      })!;

  AggregatedItem atHome(
    int season,
    int number, {
    int? end,
    String location = 'FileSystem',
  }) => AggregatedItem(
    id: 's${season}e$number',
    serverId: 'home',
    rawData: {
      'Type': 'Episode',
      'ParentIndexNumber': season,
      'IndexNumber': number,
      'IndexNumberEnd': ?end,
      'LocationType': location,
    },
  );

  group('working out what is missing', () {
    test('episodes on already go in their place, the ones not on yet at '
        'the end', () {
      final gaps = KostvSeriesGaps.compute(
        detail: detail([
          season(1, [
            for (var n = 1; n <= 6; n++) episode(n, have: true),
            episode(7),
            episode(8),
            episode(9, have: true),
            episode(10, aired: false),
          ]),
        ]),
        episodes: [
          for (final n in [1, 2, 3, 4, 5, 6, 9]) atHome(1, n),
        ],
      );

      final one = gaps.season(1)!;
      expect(one.missing.map((g) => g.number), [7, 8]);
      expect(one.upcoming.map((g) => g.number), [10]);
      expect(one.missing.first.state, KostvGhostState.requestable);
      expect(one.upcoming.single.state, KostvGhostState.upcoming);
      expect(one.upcoming.single.canAsk, isFalse);
      expect(one.upcoming.single.airDate, DateTime(2027, 3, 10));
      expect(one.askable, 2);
      expect(one.atHome, isTrue);
    });

    test('a double episode at home counts for both numbers', () {
      final gaps = KostvSeriesGaps.compute(
        detail: detail([
          season(1, [episode(1), episode(2), episode(3)]),
        ]),
        episodes: [atHome(1, 1, end: 2), atHome(1, 3)],
      );
      expect(gaps.season(1)!.missing, isEmpty);
      expect(gaps.isEmpty, isTrue);
    });

    test("an episode the home server only lists as missing doesn't count as "
        'at home', () {
      final gaps = KostvSeriesGaps.compute(
        detail: detail([
          season(1, [episode(1, have: true), episode(2)]),
        ]),
        episodes: [
          atHome(1, 1),
          atHome(1, 2, location: 'Virtual'),
        ],
      );
      expect(gaps.season(1)!.missing.map((g) => g.number), [2]);
    });

    test('a season numbered differently from the service is left alone', () {
      final gaps = KostvSeriesGaps.compute(
        detail: detail([
          season(1, [episode(1), episode(2)]),
        ]),
        episodes: [for (var n = 1; n <= 5; n++) atHome(1, n)],
      );
      expect(gaps.season(1), isNull);
    });

    test('what the service says is at home is never shown as missing', () {
      final gaps = KostvSeriesGaps.compute(
        detail: detail([
          season(1, [episode(1, have: true), episode(2)]),
        ]),
        episodes: const [],
      );
      expect(gaps.season(1)!.missing.map((g) => g.number), [2]);
    });

    test('specials are left out and whole seasons not at home are listed', () {
      final gaps = KostvSeriesGaps.compute(
        detail: detail([
          season(0, [episode(1)]),
          season(1, [episode(1, have: true)]),
          season(2, [episode(1), episode(2)]),
          season(3, [episode(1, aired: false)]),
        ]),
        episodes: [atHome(1, 1)],
      );
      expect(gaps.season(0), isNull);
      expect(gaps.seasonsNotAtHome.map((s) => s.number), [2, 3]);
      expect(gaps.season(2)!.missing.length, 2);
      expect(gaps.season(3)!.notOnYet, isTrue);
      expect(gaps.season(3)!.premiere, DateTime(2027, 3, 1));
    });

    test('how each missing episode stands', () {
      final gaps = KostvSeriesGaps.compute(
        detail: detail([
          season(1, [
            episode(1),
            episode(
              2,
              request: {'id': 1, 'status': 'pending', 'mine': false},
              canRequest: true,
            ),
            episode(
              3,
              request: {'id': 2, 'status': 'pending', 'mine': true},
              canRequest: false,
            ),
            episode(4, downloading: true, canRequest: false),
            episode(5, canRequest: false),
          ]),
        ]),
        episodes: const [],
      );
      expect(gaps.season(1)!.missing.map((g) => g.state), [
        KostvGhostState.requestable,
        KostvGhostState.joinable,
        KostvGhostState.requested,
        KostvGhostState.downloading,
        KostvGhostState.unavailable,
      ]);
      expect(gaps.season(1)!.askable, 2);
    });

    test('for the player: what is missing right after an episode', () {
      final gaps = KostvSeriesGaps.compute(
        detail: detail([
          season(1, [
            for (var n = 1; n <= 6; n++) episode(n, have: true),
            episode(7),
            episode(8),
            episode(9, have: true),
            episode(10),
          ]),
        ]),
        episodes: [
          for (final n in [1, 2, 3, 4, 5, 6, 9]) atHome(1, n),
        ],
      );
      List<int> after(int e, {int? ns, int? ne}) => gaps
          .missingAfter(season: 1, episode: e, nextSeason: ns, nextEpisode: ne)
          .map((g) => g.number)
          .toList();

      expect(after(6, ns: 1, ne: 9), [7, 8]);
      expect(after(5, ns: 1, ne: 6), isEmpty);
      expect(after(9), [10]);
      expect(after(9, ns: 2, ne: 1), [10]);
    });
  });

  group('the controller', () {
    late FakeStremfinAdapter adapter;
    late int seriesReads;
    late List<Object?> posts;
    late bool askedFor7;

    setUp(() {
      KostvSeriesGapsController.clearKept();
      seriesReads = 0;
      posts = [];
      askedFor7 = false;
      adapter = FakeStremfinAdapter.withMethod((method, path, sent) {
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
        if (path == '/series/456') {
          seriesReads++;
          return (
            status: 200,
            body: {
              'type': 'series',
              'tmdb_id': 456,
              'title': 'Los Simpson',
              'age': 7,
              'seasons': [
                season(1, [
                  episode(1, have: true),
                  askedFor7
                      ? episode(
                          2,
                          request: {'id': 9, 'status': 'pending', 'mine': true},
                          canRequest: false,
                        )
                      : episode(2),
                ]),
              ],
            },
            headers: const <String, String>{},
          );
        }
        if (path == '/requests' && method == 'POST') {
          posts.add(sent);
          askedFor7 = true;
          return (
            status: 201,
            body: {'outcome': 'created', 'message': 'Petición enviada.'},
            headers: const <String, String>{},
          );
        }
        return (status: 404, body: null, headers: const <String, String>{});
      });
    });

    StremfinService service({KostvAgeLimit limit = KostvAgeLimit.none}) {
      final s = StremfinService(
        StremfinClient(
          dio: Dio()..httpClientAdapter = adapter,
          baseUrl: 'https://requests.example.org/api/v1',
          token: () => 'abc123token',
        ),
        ageLimit: () async => limit,
        parental: () => ParentalFilter.none,
        watchLifecycle: false,
      );
      addTearDown(s.dispose);
      s.onUserChanged('someone');
      return s;
    }

    final series = AggregatedItem(
      id: 'series',
      serverId: 'home',
      rawData: const {
        'Type': 'Series',
        'ProviderIds': {'Tmdb': '456'},
      },
    );

    test('reads the series once for every screen of it, then asks for one '
        'episode and reads it again', () async {
      final stremfin = service();
      final first = KostvSeriesGapsController(service: stremfin);
      final second = KostvSeriesGapsController(service: stremfin);
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      await first.loadFor(series);
      await second.loadFor(series);
      expect(seriesReads, 1);

      final gaps = first.gapsFor([atHome(1, 1)]);
      expect(gaps.season(1)!.missing.single.state, KostvGhostState.requestable);

      final result = await first.ask(season: 1, episode: 2);
      expect(result?.outcome, StremfinOutcome.created);
      expect(posts.single, {
        'type': 'series',
        'tmdb_id': 456,
        'season': 1,
        'episode': 2,
      });
      expect(seriesReads, 2);
      expect(
        first.gapsFor([atHome(1, 1)]).season(1)!.missing.single.state,
        KostvGhostState.requested,
      );
    });

    test('shows nothing for a series beyond the age limit', () async {
      final stremfin = service(limit: const KostvAgeLimit(maxAge: 0));
      final c = KostvSeriesGapsController(service: stremfin);
      addTearDown(c.dispose);
      await c.loadFor(series);
      expect(c.enabled, isFalse);
      expect(c.gapsFor(const []).isEmpty, isTrue);
      expect(await c.ask(season: 1, episode: 2), isNull);
    });

    test("quietly does nothing for a series the service can't place", () async {
      final stremfin = service();
      final c = KostvSeriesGapsController(service: stremfin);
      addTearDown(c.dispose);
      await c.loadFor(
        AggregatedItem(
          id: 'x',
          serverId: 'home',
          rawData: const {'Type': 'Series'},
        ),
      );
      expect(c.detail, isNull);
      expect(seriesReads, 0);
    });
  });
}
