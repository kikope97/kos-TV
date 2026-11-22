import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/data/services/kostv_music_catalog.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
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
      if (types.contains('Audio')) ..._songs,
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

class _Images implements ImageApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => '';
}

class _Client implements MediaServerClient {
  _Client(this.items);

  final _Items items;

  @override
  ItemsApi get itemsApi => items;

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

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
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
  });
}
