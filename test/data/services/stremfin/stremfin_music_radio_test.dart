import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/kostv_age_gate.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_music_memory.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/util/parental_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_stremfin_adapter.dart';

const _noHeaders = <String, String>{};

Map<String, Object?> _album(
  String id, {
  Map<String, Object?> extra = const {},
}) => {
  'type': 'music',
  'deezer_id': id,
  'title': 'Disco $id',
  'artist': 'Lola',
  'cover': 'https://cdn.ejemplo.com/$id.jpg',
  'tracks': null,
  'kind': 'album',
  'release_date': '2025-05-10',
  'rank': null,
  'library': {
    'in_jellyfin': false,
    'song_in_album': null,
    'requested_recently': false,
    'jellyfin_id': null,
  },
  'download': null,
  'contains': 'Canción',
  'request': null,
  'can_request': true,
  ...extra,
};

Map<String, Object?> _song(
  String id, {
  bool explicit = false,
  bool atHome = false,
}) => {
  'deezer_id': id,
  'title': 'Canción $id',
  'artist': 'Lola',
  'artist_deezer_id': '27',
  'duration': 200,
  'preview': 'https://cdn.ejemplo.com/$id.mp3',
  'explicit': explicit,
  'album': _album('a$id'),
  'in_jellyfin': atHome,
  'in_album': null,
  'jellyfin_id': atHome ? 'j$id' : null,
  'album_jellyfin_id': null,
  'reason': 'Porque escuchas a Bad Bunny',
  'because': ['Bad Bunny'],
};

/// Kos TV: Stremfin 1.93's radio (`GET /music/radio`), and the explicit
/// songs hidden from someone with a limit on every music answer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final songs = [
    _song('1'),
    _song('2', explicit: true),
    _song('3', explicit: true, atHome: true),
  ];
  var radioStatus = 200;
  final asked = <String, List<Map<String, String>>>{};
  late FakeStremfinAdapter adapter;

  setUp(() {
    radioStatus = 200;
    asked.clear();
    adapter = FakeStremfinAdapter((path, query) {
      (asked[path] ??= []).add(query);
      final body = switch (path) {
        '/me' => {
          'user': {'role': 'member'},
          'access': {'can_request': true},
        },
        '/music/radio' => {
          'seeds': [
            {'name': 'Bad Bunny', 'deezer_id': '10583405'},
            {'name': 'Nadie', 'deezer_id': null},
          ],
          'only': 'missing',
          'exclude_seed_artists': true,
          'songs': songs,
          'skipped': ['Nadie'],
          'failed': [],
        },
        '/music/recommendations' => {'seeds': [], 'items': [], 'songs': songs},
        '/music/search' => {'artists': [], 'songs': songs, 'items': []},
        '/music/artists/27' => {
          'artist': {'deezer_id': '27', 'name': 'Lola'},
          'items': [],
          'top_songs': songs,
        },
        '/music/songs/2' => {..._song('2', explicit: true)},
        '/music/charts/top-songs' => {
          'id': 'top-songs',
          'name': 'Top',
          'kind': 'songs',
          'items': songs,
        },
        _ => null,
      };
      if (path == '/music/radio' && radioStatus != 200) {
        return (
          status: radioStatus,
          body: {
            'error': {'code': radioStatus == 404 ? 'not_found' : 'busy'},
          },
          headers: _noHeaders,
        );
      }
      return body == null
          ? (status: 404, body: null, headers: _noHeaders)
          : (status: 200, body: body, headers: _noHeaders);
    });
  });

  StremfinService serviceWith({
    KostvAgeLimit Function()? limit,
    bool Function()? kidsMode,
    ParentalFilter Function()? parental,
  }) => StremfinService(
    StremfinClient(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://stremfin.ejemplo.com/api/v1',
      token: () => 'token',
    ),
    ageLimit: () async => (limit ?? () => KostvAgeLimit.none)(),
    parental: parental ?? () => ParentalFilter.none,
    watchLifecycle: false,
    kidsMode: kidsMode,
  );

  List<String?> ids(List<StremfinSong> songs) => [
    for (final song in songs) song.deezerId,
  ];

  group('the radio', () {
    test('read with its seeds, songs with their whole album', () {
      final radio = StremfinRadio.fromJson({
        'seeds': [
          {'name': 'Bad Bunny', 'deezer_id': '10583405'},
          {'name': 'Nadie', 'deezer_id': null},
        ],
        'only': 'missing',
        'exclude_seed_artists': true,
        'songs': [
          _song('1', explicit: true)
            ..['album'] = _album(
              'a1',
              extra: {
                'request': {'id': 4, 'status': 'pending', 'mine': true},
                'can_request': false,
              },
            ),
        ],
        'skipped': ['Nadie'],
        'failed': ['Rosalía'],
      });
      expect(radio.seeds.first, (name: 'Bad Bunny', deezerId: '10583405'));
      expect(radio.seeds.last.deezerId, isNull);
      expect(radio.only, 'missing');
      expect(radio.excludeSeedArtists, isTrue);
      expect(radio.skipped, ['Nadie']);
      expect(radio.failed, ['Rosalía']);
      final song = radio.songs.single;
      expect(song.explicit, isTrue);
      expect(song.reason, 'Porque escuchas a Bad Bunny');
      expect(song.because, ['Bad Bunny']);
      expect(song.album!.deezerId, 'a1');
      expect(song.album!.request!.status, 'pending');
      expect(song.album!.canRequest, isFalse);
      expect(song.album!.contains, 'Canción');
      expect(song.album!.rank, isNull);
      expect(song.albumDeezerId, 'a1');
    });

    test(
      'asks with its parameters, kept an hour, two at once ask once',
      () async {
        final service = serviceWith();
        addTearDown(service.dispose);
        await service.refreshAccess();
        final both = await Future.wait([
          for (var i = 0; i < 2; i++)
            service.musicRadio(
              ['Bad Bunny', 'Rosalía'],
              only: 'missing',
              excludeSeedArtists: true,
              limit: 50,
            ),
        ]);
        await service.musicRadio(
          ['Bad Bunny', 'Rosalía'],
          only: 'missing',
          excludeSeedArtists: true,
          limit: 50,
        );
        expect(asked['/music/radio'], hasLength(1));
        final query = asked['/music/radio']!.single;
        expect(query['artists'], 'Bad Bunny,Rosalía');
        expect(query['only'], 'missing');
        expect(query['exclude_seed_artists'], 'true');
        expect(query['limit'], '50');
        expect(both.first.songs, hasLength(3));
      },
    );

    test('a service without it (404) is remembered, without asking again; '
        'another failure is not', () async {
      final service = serviceWith();
      addTearDown(service.dispose);
      radioStatus = 503;
      await expectLater(
        service.musicRadio(['Bad Bunny']),
        throwsA(isA<StremfinException>().having((e) => e.status, '', 503)),
      );
      radioStatus = 404;
      await expectLater(
        service.musicRadio(['Bad Bunny']),
        throwsA(isA<StremfinException>().having((e) => e.status, '', 404)),
      );
      await expectLater(
        service.musicRadio(['Rosalía']),
        throwsA(isA<StremfinException>().having((e) => e.status, '', 404)),
      );
      expect(asked['/music/radio'], hasLength(2));
    });
  });

  group('explicit songs', () {
    test('the rule: hidden only from someone with a limit, never what is at '
        'home', () {
      const explicit = StremfinSong(title: 'E', deezerId: 'e', explicit: true);
      const home = StremfinSong(
        title: 'H',
        deezerId: 'h',
        explicit: true,
        jellyfinId: 'jh',
      );
      const clean = StremfinSong(title: 'C', deezerId: 'c');
      bool hides({
        KostvAgeLimit? limit = KostvAgeLimit.none,
        ParentalFilter parental = ParentalFilter.none,
        bool kidsMode = false,
      }) => kostvMusicHidesExplicit(
        limit: limit,
        parental: parental,
        kidsMode: kidsMode,
      );
      expect(hides(), isFalse);
      expect(hides(kidsMode: true), isTrue);
      expect(hides(limit: const KostvAgeLimit(maxAge: 16)), isTrue);
      expect(hides(limit: null), isTrue);
      expect(hides(parental: ParentalFilter.fromRatings(['18'])), isTrue);
      expect(
        kostvCleanMusicSongs([explicit, home, clean], hideExplicit: true),
        [home, clean],
      );
      expect(
        kostvCleanMusicSongs([explicit, home, clean], hideExplicit: false),
        [explicit, home, clean],
      );
    });

    Future<Map<String, List<String?>>> everySurface(
      StremfinService service,
    ) async {
      final song = await service.musicSong('2');
      return {
        'radio': ids((await service.musicRadio(['Bad Bunny'])).songs),
        'para ti': ids(
          (await service.musicRecommendations(['Bad Bunny'])).songs,
        ),
        'search': ids((await service.musicSearch('lola')).songs),
        'artist': ids((await service.musicArtist('27')).topSongs),
        'chart': ids((await service.musicChart('top-songs')).songs),
        'preview': [song.song.preview],
      };
    }

    for (final (name, make) in <(String, StremfinService Function())>[
      ('kids mode', () => serviceWith(kidsMode: () => true)),
      (
        'an age limit',
        () => serviceWith(limit: () => const KostvAgeLimit(maxAge: 12)),
      ),
      (
        'the device\'s parental control',
        () => serviceWith(parental: () => ParentalFilter.fromRatings(['16'])),
      ),
    ]) {
      test('with $name, no explicit song not at home anywhere', () async {
        final service = make();
        addTearDown(service.dispose);
        await service.refreshAccess();
        final seen = await everySurface(service);
        for (final surface in seen.keys.where((k) => k != 'preview')) {
          expect(seen[surface], ['1', '3'], reason: surface);
        }
        expect(seen['preview'], [null]);
      });
    }

    test('an adult with no limit sees everything', () async {
      final service = serviceWith();
      addTearDown(service.dispose);
      await service.refreshAccess();
      final seen = await everySurface(service);
      for (final surface in seen.keys.where((k) => k != 'preview')) {
        expect(seen[surface], ['1', '2', '3'], reason: surface);
      }
      expect(seen['preview'], ['https://cdn.ejemplo.com/2.mp3']);
    });

    test('a switch of person, or of kids mode, applies at the next answer '
        '(kept ones too)', () async {
      var who = 'adult';
      var kids = false;
      final service = serviceWith(
        limit: () =>
            who == 'kid' ? const KostvAgeLimit(maxAge: 7) : KostvAgeLimit.none,
        kidsMode: () => kids,
      );
      addTearDown(service.dispose);
      service.onUserChanged('adult');
      await service.refreshAccess();
      expect(ids((await service.musicRadio(['Bad Bunny'])).songs), [
        '1',
        '2',
        '3',
      ]);
      // Kids mode on, the same person: what was kept comes clean.
      kids = true;
      expect(ids((await service.musicRadio(['Bad Bunny'])).songs), ['1', '3']);
      kids = false;
      who = 'kid';
      service.onUserChanged('kid');
      // Their limit not read yet: hidden already.
      expect(service.hidesExplicitMusic, isTrue);
      await service.refreshAccess();
      expect(ids((await service.musicRecommendations(['Bad Bunny'])).songs), [
        '1',
        '3',
      ]);
      who = 'adult';
      service.onUserChanged('adult');
      await service.refreshAccess();
      expect(ids((await service.musicRecommendations(['Bad Bunny'])).songs), [
        '1',
        '2',
        '3',
      ]);
    });
  });

  test('Kos TV: a radio isn\'t kept in the Music page\'s memory (it would push '
      'its answers out); only when asked to', () async {
    final memory = StremfinMusicMemory();
    final client = StremfinClient(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://stremfin.ejemplo.com/api/v1',
      token: () => 'token',
      musicMemory: memory,
    );
    await client.musicRadio(['Bad Bunny']);
    await expectLater(
      client.musicRadio(['Bad Bunny'], remembered: true),
      throwsA(
        isA<StremfinException>().having(
          (e) => e.code,
          'code',
          'not_remembered',
        ),
      ),
    );
    await client.musicRadio(['Bad Bunny'], keep: true);
    final kept = await client.musicRadio(['Bad Bunny'], remembered: true);
    expect(kept.songs, isNotEmpty);
    // The page's own answers are still kept.
    await client.musicChart('top-songs');
    await client.musicChart('top-songs', remembered: true);
  });
}
