import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/kostv_age_gate.dart';
import 'package:moonfin/data/services/stremfin/kostv_trailers.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/ui/widgets/trailer_picker.dart';
import 'package:moonfin/util/parental_filter.dart';

import 'fake_stremfin_adapter.dart';

/// Kos TV: a title's trailers, the Spanish ones first.
void main() {
  Map<String, Object?> trailer(
    String key, {
    String? name,
    String type = 'trailer',
    String? language,
    String? country,
    bool subtitled = false,
  }) => {
    'name': name,
    'key': key,
    'url': 'https://www.youtube.com/watch?v=$key',
    'type': type,
    'language': language,
    'country': country,
    'subtitled': subtitled,
    'official': true,
    'published_at': null,
  };

  const noHeaders = <String, String>{};
  late FakeStremfinAdapter adapter;
  var role = 'member';
  var trailersStatus = 200;
  List<Map<String, Object?>> items = [];

  setUp(() {
    role = 'member';
    trailersStatus = 200;
    items = [
      trailer('es1', name: 'Tráiler oficial', language: 'es', country: 'ES'),
      trailer(
        'es2',
        name: 'Tráiler oficial [VOSE]',
        language: 'es',
        country: 'ES',
        subtitled: true,
      ),
      trailer('en1', name: 'Official Trailer', language: 'en', country: 'US'),
    ];
    adapter = FakeStremfinAdapter((path, _) {
      if (path == '/me' && role == 'none') {
        return (status: 403, body: {'error': 'forbidden'}, headers: noHeaders);
      }
      if (path == '/me') {
        return (
          status: 200,
          body: {
            'user': {'role': role},
            'access': {'can_request': true},
          },
          headers: noHeaders,
        );
      }
      if (path == '/movies/597/trailers' || path == '/series/1399/trailers') {
        return (
          status: trailersStatus,
          body: trailersStatus == 200
              ? {'type': 'movie', 'tmdb_id': 597, 'items': items}
              : {'error': 'not_found'},
          headers: noHeaders,
        );
      }
      return (status: 404, body: {'error': 'not_found'}, headers: noHeaders);
    });
  });

  StremfinService service() {
    final s = StremfinService(
      StremfinClient(
        dio: Dio()..httpClientAdapter = adapter,
        baseUrl: 'https://requests.example.org/api/v1',
        token: () => 'abc123token',
      ),
      ageLimit: () async => KostvAgeLimit.none,
      parental: () => ParentalFilter.none,
      watchLifecycle: false,
    );
    addTearDown(s.dispose);
    s.onUserChanged('someone');
    return s;
  }

  int trailerCalls() =>
      adapter.calls.where((c) => c.uri.path.endsWith('/trailers')).length;

  const serverList = [
    {'Url': 'https://www.youtube.com/watch?v=en1', 'Name': 'Official Trailer'},
    {'Url': 'https://www.youtube.com/watch?v=other', 'Name': 'Teaser'},
  ];

  test('the Spanish ones go first and the home server\'s own follow, '
      'none twice', () async {
    final sorted = await KostvTrailers.sorted(
      itemType: 'Movie',
      tmdbId: '597',
      server: serverList,
      stremfin: service(),
    );

    expect(sorted.map((t) => t['Url'].toString().split('=').last), [
      'es1',
      'es2',
      'en1',
      'other',
    ]);
    expect(sorted.first[KostvTrailers.languageKey], 'es');
    expect(sorted.first[KostvTrailers.countryKey], 'ES');
    expect(sorted[1][KostvTrailers.subtitledKey], isTrue);
    // The home server's own keeps its shape.
    expect(sorted.last, serverList.last);
  });

  test('a series asks for a series', () async {
    await KostvTrailers.sorted(
      itemType: 'Series',
      tmdbId: '1399',
      server: const [],
      stremfin: service(),
    );
    expect(
      adapter.calls.map((c) => c.uri.path),
      contains(endsWith('/series/1399/trailers')),
    );
  });

  test('an episode, or a title without a TMDB id, keeps the server\'s list '
      'and asks nothing', () async {
    final stremfin = service();
    for (final (type, id) in [
      ('Episode', '597'),
      ('Movie', null),
      ('Movie', 'x'),
    ]) {
      expect(
        await KostvTrailers.sorted(
          itemType: type,
          tmdbId: id,
          server: serverList,
          stremfin: stremfin,
        ),
        serverList,
      );
    }
    expect(adapter.calls, isEmpty);
  });

  test('a title is asked for once', () async {
    final stremfin = service();
    await stremfin.trailers(StremfinTitleType.movie, 597);
    await stremfin.trailers(StremfinTitleType.movie, 597);
    expect(trailerCalls(), 1);
  });

  test(
    'someone not let into the requests service keeps the server\'s list',
    () async {
      role = 'none';
      final sorted = await KostvTrailers.sorted(
        itemType: 'Movie',
        tmdbId: '597',
        server: serverList,
        stremfin: service(),
      );
      expect(sorted, serverList);
      expect(trailerCalls(), 0);
    },
  );

  test('a service that fails gives the server\'s list, and isn\'t asked '
      'again straight away', () async {
    trailersStatus = 503;
    final stremfin = service();
    expect(
      await KostvTrailers.sorted(
        itemType: 'Movie',
        tmdbId: '597',
        server: serverList,
        stremfin: stremfin,
      ),
      serverList,
    );
    await stremfin.trailers(StremfinTitleType.series, 1399);
    expect(trailerCalls(), 1);
  });

  test(
    'a title it doesn\'t know is no failure: the next one is asked',
    () async {
      trailersStatus = 404;
      final stremfin = service();
      expect(await stremfin.trailers(StremfinTitleType.movie, 597), isEmpty);
      trailersStatus = 200;
      expect(
        await stremfin.trailers(StremfinTitleType.series, 1399),
        hasLength(3),
      );
    },
  );

  test('a trailer without a video is left out', () {
    expect(StremfinTrailer.fromJson({'name': 'x'}), isNull);
    expect(StremfinTrailer.fromJson('x'), isNull);
    expect(
      StremfinTrailer.fromJson({'key': 'abc'})?.url,
      'https://www.youtube.com/watch?v=abc',
    );
  });

  test('the list of trailers knows each one\'s language', () async {
    final choices = trailerChoicesFor(
      locals: const [],
      remoteTrailers: KostvTrailers.merge([
        for (final item in [
          ...items,
          trailer('mx1', name: 'Tráiler', language: 'es', country: 'MX'),
        ])
          StremfinTrailer.fromJson(item)!,
      ], serverList),
    );
    expect(choices.map((c) => (c.language, c.country, c.subtitled)), [
      ('es', 'ES', false),
      ('es', 'ES', true),
      ('en', 'US', false),
      ('es', 'MX', false),
      (null, null, false),
    ]);
  });
}
