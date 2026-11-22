import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/kostv_music_catalog.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/music/kostv_music_artist_screen.dart';
import 'package:moonfin/ui/screens/music/kostv_music_widgets.dart';
import 'package:moonfin/ui/widgets/music/design/kostv_music_design.dart';
import 'package:moonfin/util/game_library.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The page's navigation around it, with nothing in it.

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
}

class _FakeClientFactory extends Fake implements MediaServerClientFactory {}

/// The requests service with one artist: six songs (none at home) and two
/// albums.
class _Service implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    if (path == '/music/artists/ar1') {
      return ResponseBody.fromString(
        jsonEncode({
          'artist': {'deezer_id': 'ar1', 'name': 'Lola Brisa', 'albums': 2},
          'summary': {'total': 2, 'have': 0, 'missing': 2},
          'top_songs': [
            for (var i = 1; i <= 6; i++)
              {
                'deezer_id': 's$i',
                'title': 'Canción $i',
                'artist': 'Lola Brisa',
                'album_title': 'Noches',
                'album_deezer_id': 'al9',
                'duration': 200,
              },
          ],
          'related': [],
          'items': [
            {'deezer_id': 'al9', 'title': 'Noches', 'artist': 'Lola Brisa'},
            {'deezer_id': 'al13', 'title': 'Luna', 'artist': 'Lola Brisa'},
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

/// Kos TV: the music design's artist page (`docs/diseno-musica`, phase 2):
/// the big top with «Crear emisora», «Populares» in two columns on the TV
/// and the albums' ▶.
void main() {
  late UserPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance
      ..registerSingleton<PreferenceStore>(store)
      ..registerSingleton<UserPreferences>(prefs)
      ..registerSingleton<UserRepository>(_FakeUserRepository())
      ..registerSingleton<UserViewsRepository>(_FakeUserViewsRepository())
      ..registerSingleton<PluginSyncService>(_FakePluginSyncService())
      ..registerSingleton<GameLibraryRegistry>(_FakeGameLibraryRegistry())
      ..registerSingleton<PlaybackManager>(_FakePlaybackManager())
      ..registerSingleton<MediaServerClientFactory>(_FakeClientFactory());
    KostvMusicCatalog.instance = KostvMusicCatalog(prefs: () => prefs);
    GetIt.instance.registerSingleton<StremfinService>(
      StremfinService(
        StremfinClient(
          dio: Dio()..httpClientAdapter = _Service(),
          baseUrl: 'https://requests.example.org/api/v1',
          token: () => 'token',
        ),
        watchLifecycle: false,
      ),
    );
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
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
        home: const KostvMusicArtistScreen(
          deezerId: 'ar1',
          seed: StremfinArtist(deezerId: 'ar1', name: 'Lola Brisa'),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('on the TV: the big top, «Populares» in two columns, the '
      'remote on the play button and the albums\' ▶', (tester) async {
    PlatformDetection.setTvMode(true);
    await open(tester);
    expect(find.text('ARTISTA'), findsOneWidget);
    expect(find.text('2 álbumes'), findsOneWidget);
    expect(find.text('Populares'), findsOneWidget);
    expect(find.text('Crear emisora'), findsOneWidget);
    expect(find.byTooltip('Reproducir'), findsOneWidget);
    // No mark of what is at home on the artist's page.
    expect(find.textContaining('Tienes'), findsNothing);
    final first = tester.getTopLeft(find.text('Canción 1'));
    final fourth = tester.getTopLeft(find.text('Canción 4'));
    expect(fourth.dy, closeTo(first.dy, 1));
    expect(fourth.dx, greaterThan(first.dx + 300));
    // The play button has the remote (the page at its top).
    final play = find.ancestor(
      of: find.byType(KostvPlayFace),
      matching: find.byType(Focus),
    );
    expect(
      tester.widgetList<Focus>(play).any((f) => f.focusNode?.hasFocus ?? false),
      isTrue,
    );
    // With «Toda la música» each album's card has its ▶.
    final tiles = tester.widgetList<KostvMusicAlbumTile>(
      find.byType(KostvMusicAlbumTile),
    );
    expect(tiles.where((t) => t.onPlay != null), hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with «Solo la de casa»: nothing plays from the top, the '
      'remote starts on the first song and the cards only open', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    await prefs.set(UserPreferences.kostvMusicCatalogAll, false);
    await open(tester);
    expect(find.byTooltip('Reproducir'), findsNothing);
    expect(find.text('Crear emisora'), findsNothing);
    final song = find.ancestor(
      of: find.text('Canción 1'),
      matching: find.byType(Focus),
    );
    expect(
      tester.widgetList<Focus>(song).any((f) => f.focusNode?.hasFocus ?? false),
      isTrue,
    );
    final tiles = tester.widgetList<KostvMusicAlbumTile>(
      find.byType(KostvMusicAlbumTile),
    );
    expect(tiles.every((t) => t.onPlay == null), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
