import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/data/services/kostv_music_catalog.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_music_memory.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/ui/screens/music/kostv_music_album_play.dart';
import 'package:moonfin/ui/screens/music/kostv_music_home_parts.dart';
import 'package:moonfin/ui/screens/music/kostv_music_screen.dart';
import 'package:moonfin/ui/screens/music/kostv_music_widgets.dart';
import 'package:moonfin/ui/widgets/music/design/kostv_music_design.dart';
import 'package:moonfin/util/game_library.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/stremfin/fake_stremfin_adapter.dart';

// ---------------------------------------------------------------- fakes

class _FakeUserRepository extends Fake implements UserRepository {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> get currentUserStream => const Stream.empty();
}

class _FakeUserViewsRepository extends ChangeNotifier
    implements UserViewsRepository {
  @override
  Future<List<AggregatedLibrary>> getUserViews() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePluginSyncService extends ChangeNotifier
    implements PluginSyncService {
  @override
  bool get calendarAvailable => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGameLibraryRegistry extends Fake implements GameLibraryRegistry {
  @override
  Future<void> refresh() async {}
}

class _FakePlaybackManager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();

  /// Kos TV: what was put on to play.
  final played = <List<dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #playItems) {
      played.add(invocation.positionalArguments.first as List<dynamic>);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeClientFactory extends Fake implements MediaServerClientFactory {}

Map<String, dynamic> _album(String id, String name, String artist) => {
  'Id': id,
  'Name': name,
  'Type': 'MusicAlbum',
  'AlbumArtist': artist,
};

/// The home server's music: three albums (two played lately), two artists,
/// two ♥ songs and a playlist.
class _Items implements ItemsApi {
  final calls = <Map<Symbol, dynamic>>[];

  /// Kos TV: more albums at home after the three (a big house), and parts
  /// that fail to be read.
  int extraAlbums = 0;
  bool failPlaylists = false;
  bool failAlbums = false;

  /// Kos TV: the songs of another person (what they listened to), instead
  /// of the two of these.
  List<Map<String, dynamic>>? songs;

  static final _albums = [
    _album('al1', 'Faroles', 'Los Faroleros'),
    _album('al2', 'Brillo', 'Clara Vega'),
    _album('al3', 'Verano', 'Lola Brisa'),
  ];
  static final _artists = [
    {'Id': 'ar1', 'Name': 'Clara Vega', 'Type': 'MusicArtist'},
    {'Id': 'ar2', 'Name': 'Los Faroleros', 'Type': 'MusicArtist'},
  ];
  static final _songs = [
    {
      'Id': 's1',
      'Name': 'Calle',
      'Type': 'Audio',
      'AlbumId': 'al1',
      'Album': 'Faroles',
      'Artists': ['Los Faroleros'],
      'AlbumArtists': [
        {'Id': 'ar2', 'Name': 'Los Faroleros'},
      ],
    },
    {
      'Id': 's2',
      'Name': 'Luna llena',
      'Type': 'Audio',
      'AlbumId': 'al2',
      'Album': 'Brillo',
      'Artists': ['Clara Vega'],
      'AlbumArtists': [
        {'Id': 'ar1', 'Name': 'Clara Vega'},
      ],
    },
  ];

  Map<String, dynamic> _page(
    List<Map<String, dynamic>> items, {
    int? start,
    int? limit,
  }) => {
    'Items': start == null
        ? items
        : items.skip(start).take(limit ?? items.length).toList(),
    'TotalRecordCount': items.length,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #getItems) {
      return super.noSuchMethod(invocation);
    }
    final args = invocation.namedArguments;
    calls.add(args);
    final types = (args[#includeItemTypes] as List<String>?) ?? const [];
    final term = (args[#searchTerm] as String?)?.toLowerCase();
    final ids = args[#ids] as List<String>?;
    if (types.contains('Playlist') && failPlaylists) {
      return Future<Map<String, dynamic>>.error(Exception('no lists'));
    }
    if (types.contains('MusicAlbum') && ids == null && failAlbums) {
      return Future<Map<String, dynamic>>.error(Exception('no albums'));
    }
    List<Map<String, dynamic>> pool = [
      if (types.contains('MusicAlbum')) ..._albums,
      if (types.contains('MusicAlbum'))
        for (var i = 0; i < extraAlbums; i++)
          _album('x$i', 'Zeta ${i.toString().padLeft(3, '0')}', 'Otra'),
      if (types.contains('MusicArtist')) ..._artists,
      if (types.contains('Audio')) ...(songs ?? _songs),
      if (types.contains('Playlist'))
        {
          'Id': 'pl1',
          'Name': 'Para la cena',
          'Type': 'Playlist',
          'MediaType': 'Audio',
          'ChildCount': 12,
        },
    ];
    if (term != null) {
      pool = [
        for (final item in pool)
          if ((item['Name'] as String).toLowerCase().contains(term)) item,
      ];
    }
    if (ids != null) {
      pool = [
        for (final item in pool)
          if (ids.contains(item['Id'])) item,
      ];
    }
    return Future.value(
      _page(
        pool,
        start: args[#startIndex] as int?,
        limit: args[#limit] as int?,
      ),
    );
  }
}

/// Kos TV: a song a person listened to [plays] times, of [genre].
Map<String, dynamic> _played(
  String id,
  String albumId,
  String artistId,
  String artist,
  String genre,
  int plays,
) => {
  'Id': id,
  'Name': 'Canción $id',
  'Type': 'Audio',
  'AlbumId': albumId,
  'Artists': [artist],
  'AlbumArtists': [
    {'Id': artistId, 'Name': artist},
  ],
  'Genres': [genre],
  'UserData': {'Played': true, 'PlayCount': plays},
};

/// Kos TV: the home server's mix of an artist (their station).
class _Mixes implements InstantMixApi {
  final asked = <String>[];

  @override
  Future<Map<String, dynamic>> getInstantMix(
    String itemId, {
    int? limit,
  }) async {
    asked.add(itemId);
    return {
      'Items': [
        for (final id in ['m1', 'm2', 'm3'])
          {'Id': id, 'Name': 'Mezcla $id', 'Type': 'Audio'},
      ],
    };
  }
}

/// Kos TV: the requests service of the Music page: the charts (each its
/// own songs: «ES 1», «LAT 1», «POP 1», «MX 1», «US 1») and «Para ti» with
/// an album for each artist asked about, and what it was asked.
class _Requests {
  _Requests({this.memory});

  final calls = <String>[];

  /// Kos TV: what the page kept on the device last time (the week's
  /// discovery, for one).
  final StremfinMusicMemory? memory;

  late final adapter = FakeStremfinAdapter(answer);

  StremfinService service() => StremfinService(
    StremfinClient(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://requests.example.org/api/v1',
      token: () => 'token',
      musicMemory: memory,
    ),
    watchLifecycle: false,
  );

  static Map<String, Object?> _songsChart(String id, String tag) => {
    'id': id,
    'name': 'Top $tag · Canciones',
    'kind': 'songs',
    'items': [
      for (var i = 1; i <= 6; i++)
        {
          'rank': i,
          'title': '$tag $i',
          'artist': 'Artista $tag',
          'deezer_id': '$tag-$i',
          'in_jellyfin': false,
          'album': {'deezer_id': 'al-$tag-$i', 'title': 'Disco $tag $i'},
        },
    ],
  };

  ({int status, Object? body, Map<String, String> headers}) answer(
    String path,
    Map<String, String> query,
  ) {
    final country = query['country'];
    calls.add(country == null ? path : '$path?$country');
    ({int status, Object? body, Map<String, String> headers}) ok(
      Object? body,
    ) => (status: 200, body: body, headers: const {});
    switch (path) {
      case '/me':
        return ok({
          'user': {'name': 'Kiko', 'role': 'member'},
          'access': {'can_request': true, 'mode': 'direct'},
        });
      case '/music/charts/top-songs':
        return ok(_songsChart('top-songs', country ?? 'ES'));
      case '/music/charts/latino-songs':
        return ok(_songsChart('latino-songs', 'LAT'));
      case '/music/charts/pop-songs':
        return ok(_songsChart('pop-songs', 'POP'));
      case '/music/charts/top-albums':
        return ok({
          'id': 'top-albums',
          'name': 'Top España · Álbumes',
          'kind': 'albums',
          'items': [
            for (var i = 1; i <= 4; i++)
              {'deezer_id': 'ta$i', 'title': 'Álbum top $i', 'rank': i},
          ],
        });
      case '/music/recommendations':
        final names = (query['artists'] ?? '')
            .split(',')
            .where((n) => n.isNotEmpty)
            .toList();
        return ok({
          'seeds': [
            for (final (i, n) in names.indexed) {'name': n, 'deezer_id': 'd$i'},
          ],
          'items': [
            for (final (i, n) in names.indexed)
              {
                'deezer_id': 'rec$i',
                'title': 'Parecido a $n',
                'artist': 'Otro $i',
                'reason': 'Porque escuchas a $n',
              },
          ],
          'songs': const [],
        });
    }
    return (
      status: 404,
      body: {
        'error': {'code': 'not_found', 'message': 'No.'},
      },
      headers: const {},
    );
  }
}

class _Images implements ImageApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => '';
}

class _Client implements MediaServerClient {
  _Client(this.items);

  final _Items items;
  final mixes = _Mixes();

  @override
  ItemsApi get itemsApi => items;

  @override
  InstantMixApi get instantMixApi => mixes;

  @override
  ImageApi get imageApi => _Images();

  @override
  String get baseUrl => 'http://home.example';

  @override
  String? get userId => 'u1';

  // No token: the server plugin's routes aren't asked (no network here).
  @override
  String? get accessToken => null;

  @override
  ServerType get serverType => ServerType.jellyfin;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // ------------------------------------------------------------ the rules

  group('«Sigue escuchando»', () {
    test('the design\'s order: favourites second, a mix fourth and a '
        'playlist seventh, between the albums', () {
      final r = kostvKeepListening(
        albums: ['a0', 'a1', 'a2', 'a3', 'a4', 'a5'],
        favorites: 'fav',
        mix: 'mix',
        playlist: 'list',
      );
      expect(r.picks, ['a0', 'fav', 'a1', 'mix', 'a2', 'a3', 'list', 'a4']);
      expect(r.albumsUsed, 5);
    });

    test('what is missing leaves its place to the next album; six on the '
        'phone', () {
      final r = kostvKeepListening<String>(
        albums: ['a0', 'a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7'],
        count: 6,
      );
      expect(r.picks, ['a0', 'a1', 'a2', 'a3', 'a4', 'a5']);
      expect(r.albumsUsed, 6);
    });

    test('without albums, the favourites, the mix and the playlist', () {
      final r = kostvKeepListening<String>(
        albums: const [],
        favorites: 'fav',
        mix: 'mix',
        playlist: 'list',
      );
      expect(r.picks, ['fav', 'mix', 'list']);
      expect(r.albumsUsed, 0);
    });
  });

  test('the tabs\' order: what was played lately first, then the rest A–Z', () {
    final all = ['ana', 'bea', 'carla', 'dani'];
    expect(kostvRecentFirst(['carla', 'gone', 'ana', 'carla'], all, (x) => x), [
      'carla',
      'ana',
      'bea',
      'dani',
    ]);
    expect(kostvRecentFirst(const [], all, (x) => x), all);
  });

  group('«Lo mejor»', () {
    test('the one called as the query, an artist before an album, accents '
        'and case aside', () {
      final top = kostvTopResult('LUNA', const [
        KostvTopCandidate(KostvTopKind.album, 'Luna de Madrid', 'a1'),
        KostvTopCandidate(KostvTopKind.song, 'Luna', 's1'),
        KostvTopCandidate(KostvTopKind.album, 'Lúna', 'a2'),
      ]);
      expect(top?.item, 'a2');
      final artist = kostvTopResult('sal y limon', const [
        KostvTopCandidate(KostvTopKind.album, 'Sal y Limón', 'a1'),
        KostvTopCandidate(KostvTopKind.artist, 'Sal y Limón', 'ar1'),
      ]);
      expect(artist?.item, 'ar1');
    });

    test('none called so: the first (what is at home comes first)', () {
      final top = kostvTopResult('lu', const [
        KostvTopCandidate(KostvTopKind.album, 'Luna de Madrid', 'home'),
        KostvTopCandidate(KostvTopKind.artist, 'Lunares', 'away'),
      ]);
      expect(top?.item, 'home');
      expect(kostvTopResult<String>('x', const []), isNull);
    });
  });

  group('«Para ti»: its order', () {
    test('what the person listens to first, then «Listas de éxitos», '
        '«Porque escuchas a …» and the radios of their artists', () {
      final order = kostvForYouOrder();
      expect(order.take(7), [
        'quick',
        'moment',
        'mixes',
        'charts',
        'because',
        'radios',
        'discovery',
      ]);
      // Then the news and «Más de …», the songs and what is new at home,
      // and the rest in its order of before.
      expect(order.skip(7), [
        'your-news',
        'more-of',
        'foryou-songs',
        'new-at-home',
        'recent',
        'favorites',
        'playlists',
        'releases',
        'requested',
      ]);
    });

    test('someone new: the charts right after «Sigue escuchando»', () {
      final order = kostvForYouOrder(newListener: true);
      expect(order.take(3), ['quick', 'charts', 'moment']);
      expect(order.toSet(), kostvForYouOrder().toSet());
      expect(order, hasLength(kostvForYouOrder().length));
    });

    test('«Listas de éxitos» opens with the list of the person\'s genre, '
        'otherwise España', () {
      const all = KostvChartList.values;
      expect(
        kostvDefaultChart(firstGenre: 'latino', available: all),
        KostvChartList.latino,
      );
      expect(
        kostvDefaultChart(firstGenre: 'pop', available: all),
        KostvChartList.genre,
      );
      expect(
        kostvDefaultChart(firstGenre: null, available: all),
        KostvChartList.spain,
      );
      // Their genre's list isn't there (yet): España.
      expect(
        kostvDefaultChart(
          firstGenre: 'pop',
          available: const [KostvChartList.spain, KostvChartList.latino],
        ),
        KostvChartList.spain,
      );
      expect(
        kostvDefaultChart(
          firstGenre: null,
          available: const [KostvChartList.mexico],
        ),
        KostvChartList.mexico,
      );
      expect(kostvDefaultChart(firstGenre: null, available: const []), isNull);
    });

    test('«Porque escuchas a …»: a row for each artist, in the person\'s '
        'order, then what names none of them', () {
      final rows = kostvBecauseRows<String>(
        [
          'a: Porque escuchas a Rosalía y Bad Bunny',
          'b: Porque escuchas a Bad Bunny',
          'c: Porque escuchas a Ana',
          'd: Porque escuchas a Anabel',
          'e',
        ],
        (item) => item.length > 3 ? item.substring(3) : null,
        ['Bad Bunny', 'Rosalía', 'Ana', 'Nadie'],
      );
      // Each goes with the first of the person's artists its reason names:
      // Rosalía, with nothing of her own, has no row.
      expect(
        [for (final r in rows) r.artist],
        ['Bad Bunny', 'Ana', null, null],
      );
      expect(rows[0].items, [
        'a: Porque escuchas a Rosalía y Bad Bunny',
        'b: Porque escuchas a Bad Bunny',
      ]);
      expect(rows[1].items, ['c: Porque escuchas a Ana']);
      // «Anabel» isn't «Ana»: its own reason; without one, «Discos para ti».
      expect(rows[2].reason, 'Porque escuchas a Anabel');
      expect(rows[3].reason, isNull);
      // Five rows at most.
      final many = kostvBecauseRows<String>(
        [for (var i = 0; i < 8; i++) 'Porque escuchas a A$i'],
        (i) => i,
        [for (var i = 0; i < 8; i++) 'A$i'],
      );
      expect([for (final r in many) r.artist], ['A0', 'A1', 'A2', 'A3', 'A4']);
    });
  });

  // -------------------------------------------------------------- pieces

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('a mix card draws its name («Mix diario 2») on its colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const Center(child: KostvDailyMixArt(number: 2, size: 172))),
    );
    expect(find.text('Mix diario 2'), findsOneWidget);
  });

  testWidgets('«Lo mejor»: the card opens, its ▶ plays', (tester) async {
    var opened = 0;
    var played = 0;
    await tester.pumpWidget(
      app(
        Center(
          child: SizedBox(
            width: 440,
            child: KostvTopResultCard(
              title: 'Luna',
              subtitle: 'Álbum · Sal y Limón',
              onTap: () => opened++,
              onPlay: () => played++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Luna'));
    await tester.tap(find.byType(KostvPlayButton));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, 1);
    expect(played, 1);
  });

  // ------------------------------------------------------------ the page

  group('Music\'s home', () {
    late _Items items;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      items = _Items();
      GetIt.instance
        ..registerSingleton<PreferenceStore>(store)
        ..registerSingleton<UserPreferences>(prefs)
        ..registerSingleton<UserRepository>(_FakeUserRepository())
        ..registerSingleton<UserViewsRepository>(_FakeUserViewsRepository())
        ..registerSingleton<PluginSyncService>(_FakePluginSyncService())
        ..registerSingleton<GameLibraryRegistry>(_FakeGameLibraryRegistry())
        ..registerSingleton<PlaybackManager>(_FakePlaybackManager())
        ..registerSingleton<MediaServerClientFactory>(_FakeClientFactory())
        ..registerSingleton<MediaServerClient>(_Client(items));
      KostvMusicCatalog.instance = KostvMusicCatalog(prefs: () => prefs);
    });

    tearDown(() async {
      PlatformDetection.setTvMode(false);
      PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
      KostvMusicCatalog.instance = KostvMusicCatalog();
      await GetIt.instance.reset();
    });

    Future<void> open(WidgetTester tester, {bool router = false}) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        router
            // Kos TV: with the player's page to go to once a song plays.
            ? MaterialApp.router(
                locale: const Locale('es'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: GoRouter(
                  routes: [
                    GoRoute(
                      path: '/',
                      builder: (_, _) => const KostvMusicScreen(),
                    ),
                    GoRoute(
                      path: Destinations.audioPlayer,
                      builder: (_, _) => const SizedBox(),
                    ),
                  ],
                ),
              )
            : MaterialApp(
                locale: const Locale('es'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const KostvMusicScreen(),
              ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('the tabs and «Sigue escuchando» with what was played '
        'lately, the favourites and the playlist', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      await open(tester);
      for (final tab in ['Para ti', 'Tus listas', 'Artistas', 'Álbumes']) {
        expect(find.text(tab), findsWidgets, reason: tab);
      }
      expect(find.text('Sigue escuchando'), findsOneWidget);
      final tiles = find.byType(KostvMusicQuickTile);
      final names = [
        for (final tile in tester.widgetList<KostvMusicQuickTile>(tiles))
          tile.title,
      ];
      // The albums, the favourites second, the mix of the artist listened
      // to most fourth and the playlist.
      expect(names.take(3), ['Faroles', 'Tus favoritas', 'Brillo']);
      expect(names[3], isIn(['Los Faroleros', 'Clara Vega']));
      expect(names.last, 'Para la cena');
      expect(names, hasLength(5));
      await leave(tester);
    });

    testWidgets('on the TV the remote goes from the search to the tabs, to '
        'the first access and back up; OK changes the tab', (tester) async {
      PlatformDetection.setTvMode(true);
      await open(tester);
      final search = FocusManager.instance.rootScope.descendants.firstWhere(
        (n) => n.debugLabel == 'kostvMusicSearch',
      );
      search.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'kostvMusicTab-forYou');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'kostvMusicFirst');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), 'kostvMusicTab-forYou');
      // Along the tabs; the arrows don't change it, OK does.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'kostvMusicTab-albums');
      expect(find.text('Sigue escuchando'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Sigue escuchando'), findsNothing);
      expect(find.text('Escuchado hace poco'), findsOneWidget);
      expect(find.text('A–Z'), findsOneWidget);
      // The albums at home, those played lately first.
      final albums = [
        for (final tile in tester.widgetList<KostvMusicAlbumTile>(
          find.byType(KostvMusicAlbumTile),
        ))
          tile.title,
      ];
      expect(albums, ['Faroles', 'Brillo', 'Verano']);
      // Down from the tabs, the order; up from it, the tabs again; right
      // from the last tab, the search.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'kostvMusicSortRecent');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), 'kostvMusicTab-albums');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'kostvMusicSearch');
      await leave(tester);
    });

    testWidgets('Kos TV: «Álbumes» goes on past the first page as it is '
        'scrolled, and what was played lately stays first', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      items.extraAlbums = 450;
      await open(tester);
      await tester.tap(find.text('Álbumes').first);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      List<Map<Symbol, dynamic>> pages() => [
        for (final call in items.calls)
          if ((call[#includeItemTypes] as List?)?.contains('MusicAlbum') ==
                  true &&
              call[#startIndex] != null)
            call,
      ];
      expect(pages().map((c) => c[#startIndex]), [0]);
      // Played lately first, even before the rest is read.
      final first = [
        for (final tile in tester.widgetList<KostvMusicAlbumTile>(
          find.byType(KostvMusicAlbumTile),
        ))
          tile.title,
      ];
      expect(first.take(2), ['Faroles', 'Brillo']);
      // Down to the end of what it has: the next pages come.
      for (var i = 0; i < 80 && find.text('Zeta 449').evaluate().isEmpty; i++) {
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -3000),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Zeta 449'), findsOneWidget);
      expect(pages().map((c) => c[#startIndex]), [0, 200, 400]);
      await leave(tester);
    });

    testWidgets('Kos TV: «Tus listas» that fail to be read say so, with '
        '«Reintentar»', (tester) async {
      items.failPlaylists = true;
      await open(tester);
      await tester.tap(find.text('Tus listas').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No se han podido cargar tus listas.'), findsOneWidget);
      expect(find.textContaining('Aún no tienes listas'), findsNothing);
      items.failPlaylists = false;
      await tester.tap(find.text('Reintentar'));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Para la cena'), findsOneWidget);
      expect(find.text('No se han podido cargar tus listas.'), findsNothing);
      await leave(tester);
    });

    testWidgets('Kos TV: «Álbumes» that fail to be read have «Reintentar», '
        'for the remote too', (tester) async {
      PlatformDetection.setTvMode(true);
      items.failAlbums = true;
      await open(tester);
      final albums = FocusManager.instance.rootScope.descendants.firstWhere(
        (n) => n.debugLabel == 'kostvMusicTab-albums',
      );
      albums.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Reintentar'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'kostvMusicFirst');
      items.failAlbums = false;
      await press(tester, LogicalKeyboardKey.select);
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Reintentar'), findsNothing);
      expect(find.text('Verano'), findsWidgets);
      await leave(tester);
    });

    testWidgets('Kos TV: the ▶ of a card of the service\'s album that is at '
        'home plays it from home, without the requests service', (
      tester,
    ) async {
      await open(tester);
      final manager = GetIt.instance<PlaybackManager>() as _FakePlaybackManager;
      final context = tester.element(find.byType(KostvMusicScreen));
      const album = StremfinAlbum(
        title: 'Faroles',
        artist: 'Los Faroleros',
        inJellyfin: true,
      );
      expect(kostvStremfinAlbumPlays(album), isTrue);
      await tester.runAsync(() async {
        try {
          await playKostvStremfinAlbum(context, album);
        } catch (_) {
          // The player's page: no router here.
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(manager.played, hasLength(1));
      expect(manager.played.single.map((s) => (s as AggregatedItem).id), [
        's1',
        's2',
      ]);
      await leave(tester);
    });

    testWidgets('«Tus listas» opens with «Nueva lista»', (tester) async {
      await open(tester);
      await tester.tap(find.text('Tus listas').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Nueva lista'), findsOneWidget);
      expect(find.text('Para la cena'), findsOneWidget);
      expect(find.text('Sigue escuchando'), findsNothing);
      await leave(tester);
    });

    testWidgets('a search: «Lo mejor», the songs and the albums, with '
        'the filters on the web', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      await open(tester);
      await tester.enterText(find.byType(TextField), 'luna');
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Lo mejor'), findsOneWidget);
      expect(find.byType(KostvTopResultCard), findsOneWidget);
      for (final pill in ['Todo', 'Canciones', 'Álbumes', 'Listas']) {
        expect(find.text(pill), findsWidgets, reason: pill);
      }
      // Its tabs aren't there while searching.
      expect(find.text('Para ti'), findsNothing);
      // «Canciones» shows only the songs.
      await tester.tap(find.text('Canciones').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(KostvTopResultCard), findsNothing);
      expect(find.text('Luna llena'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('on the TV, a search: from «Lo mejor» to its ▶ and to the '
        'songs beside it; up to the search', (tester) async {
      PlatformDetection.setTvMode(true);
      await open(tester);
      // As the TV's keyboard types it.
      tester
              .widget<CustomTVTextField>(find.byType(CustomTVTextField))
              .controller!
              .text =
          'luna';
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Lo mejor'), findsOneWidget);
      FocusNode node(String label) => FocusManager
          .instance
          .rootScope
          .descendants
          .firstWhere((n) => n.debugLabel == label);
      node('kostvMusicFirst').requestFocus();
      await tester.pump(const Duration(milliseconds: 300));
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'kostvMusicTopPlay');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'kostvMusicFirstSong');
      node('kostvMusicFirst').requestFocus();
      await tester.pump(const Duration(milliseconds: 300));
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), 'kostvMusicSearch');
      await leave(tester);
    });

    testWidgets('on the phone: the tabs at the top, the search in a button '
        'whose ✕ brings the tabs back', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.phone);
      await open(tester);
      expect(find.text('Para ti'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      // Only the accesses, without the heading (the design's).
      expect(find.text('Sigue escuchando'), findsNothing);
      expect(find.byType(KostvMusicQuickTile), findsWidgets);
      await tester.tap(find.byTooltip('Buscar'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'luna');
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Lo mejor'), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar la búsqueda'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Para ti'), findsOneWidget);
      expect(find.text('Lo mejor'), findsNothing);
      await leave(tester);
    });

    // ------------------------------------------------ «Para ti» per person

    /// Kos TV: the page with the requests service too (its charts and «Para
    /// ti»), for the person whose songs are [songs] (none: someone new).
    Future<_Requests> openFor(
      WidgetTester tester,
      List<Map<String, dynamic>> songs, {
      bool router = false,
      StremfinMusicMemory? memory,
    }) async {
      items.songs = songs;
      final requests = _Requests(memory: memory);
      final service = requests.service();
      GetIt.instance.registerSingleton<StremfinService>(service);
      addTearDown(service.dispose);
      await open(tester, router: router);
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      return requests;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Kos TV: a pill of «Listas de éxitos» clicked.
    Future<void> pick(WidgetTester tester, String label) async {
      final pill = find.descendant(
        of: find.byType(KostvMusicChoiceRow<KostvChartList>),
        matching: find.text(label),
      );
      await tester.ensureVisible(pill);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(pill);
    }

    /// The sections of «Para ti», top to bottom.
    List<String> sections(WidgetTester tester) => [
      for (final part in tester.widgetList<KeyedSubtree>(
        find.byWidgetPredicate(
          (w) =>
              w is KeyedSubtree &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('music-') &&
              !(w.key! as ValueKey<String>).value.endsWith('-gap'),
          skipOffstage: false,
        ),
      ))
        (part.key! as ValueKey<String>).value.substring('music-'.length),
    ];

    // Someone who listens to Latin music, Lola Brisa most.
    final latina = [
      for (var i = 0; i < 4; i++)
        _played('l$i', 'al3', 'ar9', 'Lola Brisa', 'Latin', 20 - i),
      _played('l9', 'al1', 'ar2', 'Los Faroleros', 'Latin', 3),
    ];
    // Someone who listens to pop, Clara Vega most.
    final pop = [
      for (var i = 0; i < 4; i++)
        _played('p$i', 'al2', 'ar1', 'Clara Vega', 'Pop', 30 - i),
    ];

    testWidgets('«Para ti» of someone who listens to Latin music: their '
        'mixes, «Listas de éxitos» on Latino, «Porque escuchas a» their '
        'artists and their radios, then the rest', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      final requests = await openFor(tester, latina);
      final order = sections(tester);
      expect(order.take(5), [
        'quick',
        'mixes',
        'charts',
        'foryou-reason-Lola Brisa',
        'foryou-reason-Los Faroleros',
      ]);
      expect(order.indexOf('radios'), 5);
      expect(
        order.indexOf('recent') > order.indexOf('radios') ||
            !order.contains('recent'),
        isTrue,
      );
      expect(order.indexOf('favorites'), greaterThan(order.indexOf('radios')));
      // One section of the charts: Latino first and picked.
      expect(find.text('Listas de éxitos'), findsOneWidget);
      expect(find.text('Top España'), findsNothing);
      expect(find.text('LAT 1'), findsOneWidget);
      expect(find.text('ES 1'), findsNothing);
      final pills = tester.widget<KostvMusicChoiceRow<KostvChartList>>(
        find.byType(KostvMusicChoiceRow<KostvChartList>),
      );
      expect(pills.values, [
        KostvChartList.latino,
        KostvChartList.spain,
        KostvChartList.mexico,
        KostvChartList.usa,
        KostvChartList.albums,
      ]);
      expect(pills.selected, KostvChartList.latino);
      expect(find.text('Porque escuchas a Lola Brisa'), findsOneWidget);
      expect(find.text('Radio de Lola Brisa'), findsOneWidget);
      // Nothing more asked at the opening than before: México, EE. UU.
      // and the albums only when picked.
      expect(requests.calls, isNot(contains('/music/charts/top-songs?MX')));
      expect(requests.calls, isNot(contains('/music/charts/top-albums')));
      await pick(tester, 'México');
      await settle(tester);
      expect(requests.calls, contains('/music/charts/top-songs?MX'));
      expect(find.text('MX 1'), findsOneWidget);
      expect(find.text('LAT 1'), findsNothing);
      // Picked again, it isn't asked again.
      await pick(tester, 'Latino');
      await settle(tester);
      await pick(tester, 'México');
      await settle(tester);
      expect(
        requests.calls.where((c) => c == '/music/charts/top-songs?MX'),
        hasLength(1),
      );
      await leave(tester);
    });

    testWidgets('«Para ti» of someone who listens to pop: the chart of their '
        'genre first, and their own artists', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      await openFor(tester, pop);
      final order = sections(tester);
      expect(order.take(4), [
        'quick',
        'mixes',
        'charts',
        'foryou-reason-Clara Vega',
      ]);
      expect(find.text('POP 1'), findsOneWidget);
      final pills = tester.widget<KostvMusicChoiceRow<KostvChartList>>(
        find.byType(KostvMusicChoiceRow<KostvChartList>),
      );
      expect(pills.values.first, KostvChartList.genre);
      expect(pills.selected, KostvChartList.genre);
      expect(find.text('Pop'), findsOneWidget);
      expect(find.text('Porque escuchas a Clara Vega'), findsOneWidget);
      expect(find.text('Porque escuchas a Lola Brisa'), findsNothing);
      expect(find.text('Radio de Clara Vega'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('«Para ti» of someone new: «Listas de éxitos» right after '
        '«Sigue escuchando», on España', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      await openFor(tester, const []);
      final order = sections(tester);
      expect(order.take(2), ['quick', 'charts']);
      expect(order, isNot(contains('mixes')));
      expect(order, isNot(contains('radios')));
      expect(find.text('ES 1'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('on the TV, «Listas de éxitos»: down from the tabs to its '
        'pills, along them and OK picks one, down to its songs', (
      tester,
    ) async {
      PlatformDetection.setTvMode(true);
      // Someone new without lists: the charts are the first section.
      items.failPlaylists = true;
      await openFor(tester, const []);
      expect(sections(tester).first, 'charts');
      final search = FocusManager.instance.rootScope.descendants.firstWhere(
        (n) => n.debugLabel == 'kostvMusicSearch',
      );
      search.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'kostvMusicTab-forYou');
      await press(tester, LogicalKeyboardKey.arrowDown);
      // The first pill (España) is the page's first stop.
      expect(focused(), 'kostvMusicFirst');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'kostvMusicChart-latino');
      // The arrows don't change the list; OK does, and the remote stays.
      expect(find.text('ES 1'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      await settle(tester);
      expect(find.text('LAT 1'), findsOneWidget);
      expect(find.text('ES 1'), findsNothing);
      expect(focused(), 'kostvMusicChart-latino');
      // Down to its songs, and up to the pills again.
      await press(tester, LogicalKeyboardKey.arrowDown);
      final row = FocusManager.instance.primaryFocus?.context;
      expect(row, isNotNull);
      expect(
        row!.findAncestorWidgetOfExactType<KostvMusicSongRow>(),
        isNotNull,
      );
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), startsWith('kostvMusic'));
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<
              KostvMusicChoiceRow<KostvChartList>
            >(),
        isNotNull,
      );
      // Up from the pills, the tabs.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), 'kostvMusicFirst');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), 'kostvMusicTab-forYou');
      await leave(tester);
    });

    testWidgets('«Radios de tus artistas»: a card starts the station of the '
        'artist, from the home server\'s mix of them', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      await openFor(tester, latina, router: true);
      final manager = GetIt.instance<PlaybackManager>() as _FakePlaybackManager;
      final client = GetIt.instance<MediaServerClient>() as _Client;
      final card = find.text('Radio de Lola Brisa');
      await tester.ensureVisible(card);
      await tester.pump();
      await tester.tap(card);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
      expect(client.mixes.asked, ['ar9']);
      expect(manager.played, hasLength(1));
      expect(manager.played.single.map((s) => (s as AggregatedItem).id), [
        'm1',
        'm2',
        'm3',
      ]);
      await leave(tester);
    });
    testWidgets('«Descubrimiento semanal»: the focus frame of its card is as '
        'tall as the card, not as its row of four songs', (tester) async {
      PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
      // Kos TV: this week's discovery, as the page kept it last time.
      final memory = StremfinMusicMemory();
      memory.write(StremfinMusicMemory.scopeOf('token'), 'note:discovery', {
        'Week': kostvIsoWeek(DateTime.now()),
        'Songs': [
          for (var i = 0; i < 8; i++)
            {
              'title': 'Semana $i',
              'artist': 'Artista $i',
              'deezer_id': 'w$i',
              'in_jellyfin': true,
              'jellyfin_id': 'j$i',
            },
        ],
      });
      await openFor(tester, latina, memory: memory);
      final card = find.byKey(const ValueKey('discovery-card'));
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await tester.pump(const Duration(milliseconds: 300));
      final frame = find.descendant(
        of: card,
        matching: find.byType(KostvFocusFrame),
      );
      final art = find.descendant(
        of: card,
        matching: find.byType(KostvDiscoveryArt),
      );
      final side = tester.widget<KostvDiscoveryArt>(art).size;
      expect(tester.getSize(art).height, side);
      expect(tester.getSize(frame).height, side);
      expect(tester.getSize(frame).width, side);
      await leave(tester);
    });
  });
}
