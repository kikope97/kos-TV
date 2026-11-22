import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:moonfin/data/services/stremfin/kostv_age_gate.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/music/kostv_music_actions.dart';
import 'package:moonfin/ui/screens/music/kostv_music_album_screen.dart';
import 'package:moonfin/ui/screens/music/kostv_stream_widgets.dart';
import 'package:moonfin/ui/widgets/music/kostv_stream_play.dart';
import 'package:moonfin/util/game_library.dart';
import 'package:moonfin/util/parental_filter.dart';
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

/// The requests service with one album that isn't at home (two songs not
/// at home, one at home), answered when [answer] is completed.
class _Service implements HttpClientAdapter {
  Completer<void> answer = Completer<void>();
  var request = false;

  /// Kos TV: it is at home once asked for (found there straight away).
  var homeOnceAsked = false;
  var asked = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst('/api/v1', '');
    if (path == '/requests' && options.method == 'POST') {
      asked = true;
      return ResponseBody.fromString(
        jsonEncode({'outcome': 'created', 'message': 'Pedido'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (path == '/music/albums/al1') {
      await answer.future;
      return ResponseBody.fromString(
        jsonEncode({
          'deezer_id': 'al1',
          'title': 'Tormenta',
          'artist': 'Rayo',
          'can_request': !(homeOnceAsked && asked),
          if (homeOnceAsked && asked) 'library': {'in_jellyfin': true},
          if (request) 'request': {'id': 3, 'status': 'pending', 'mine': true},
          'songs': [
            {'deezer_id': '1', 'title': 'Trueno', 'position': 1},
            {'deezer_id': '2', 'title': 'Relámpago', 'position': 2},
            {
              'deezer_id': '3',
              'title': 'Calma',
              'position': 3,
              'in_jellyfin': true,
              'jellyfin_id': 'j3',
            },
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

/// Kos TV: an album that isn't at home with «Toda la música»: on the TV the
/// remote ends on «Reproducir» (not on the ask it landed on while the page
/// was read), and for someone with a limit, as with «Solo la de casa».
void main() {
  late _Service server;
  late StremfinService service;
  var kids = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    final prefs = UserPreferences(store);
    final getIt = GetIt.instance
      ..registerSingleton<PreferenceStore>(store)
      ..registerSingleton<UserPreferences>(prefs)
      ..registerSingleton<UserRepository>(_FakeUserRepository())
      ..registerSingleton<UserViewsRepository>(_FakeUserViewsRepository())
      ..registerSingleton<PluginSyncService>(_FakePluginSyncService())
      ..registerSingleton<GameLibraryRegistry>(_FakeGameLibraryRegistry())
      ..registerSingleton<PlaybackManager>(_FakePlaybackManager())
      ..registerSingleton<MediaServerClientFactory>(_FakeClientFactory());
    expect(getIt.isRegistered<UserPreferences>(), isTrue);
    KostvMusicCatalog.instance = KostvMusicCatalog(prefs: () => prefs);
    server = _Service();
    kids = false;
    service = StremfinService(
      StremfinClient(
        dio: Dio()..httpClientAdapter = server,
        baseUrl: 'https://requests.example.org/api/v1',
        token: () => 'token',
      ),
      watchLifecycle: false,
      kidsMode: () => kids,
    );
    GetIt.instance.registerSingleton<StremfinService>(service);
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    KostvMusicCatalog.instance = KostvMusicCatalog();
    KostvStreamAlbums.debugReset();
    await GetIt.instance.reset();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const KostvMusicAlbumScreen(
          deezerId: 'al1',
          seed: KostvMusicAlbumSeed(
            album: StremfinAlbum(
              title: 'Tormenta',
              deezerId: 'al1',
              artist: 'Rayo',
              canRequest: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> answer(WidgetTester tester) async {
    server.answer.complete();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

  testWidgets('on the TV, the remote goes from the ask to «Reproducir» once '
      'the album comes', (tester) async {
    PlatformDetection.setTvMode(true);
    await open(tester);
    // Read meanwhile: the ask is the main button, and has the remote.
    expect(focused(), 'kostvMusicAsk');
    await answer(tester);
    expect(find.byTooltip('Reproducir'), findsOneWidget);
    expect(find.text('Pedir el álbum'), findsOneWidget);
    // Kos TV: the music design: the calm note, the one place that says
    // it isn't at home, with «Pedir el álbum» in it.
    expect(
      find.textContaining('Este disco no está en casa', findRichText: true),
      findsOneWidget,
    );
    expect(focused(), 'kostvMusicAlbumPlay');
    // The prefetch of resting on the page, let go.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on the TV, down from «Reproducir» goes to «Pedir el álbum» '
      'in the note under it (not past it to the songs)', (tester) async {
    PlatformDetection.setTvMode(true);
    await open(tester);
    await answer(tester);
    expect(focused(), 'kostvMusicAlbumPlay');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 300));
    expect(focused(), 'kostvMusicAsk');
    // And on, down to the songs.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 300));
    expect(focused(), isNot('kostvMusicAsk'));
    expect(focused(), isNot('kostvMusicAlbumPlay'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the person moved meanwhile: the remote stays where it is', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    await open(tester);
    final other = FocusNode(debugLabel: 'elsewhere');
    addTearDown(other.dispose);
    // Somewhere else on the page (the artist's name, the back button…).
    FocusManager.instance.rootScope.requestFocus(other);
    await tester.pump();
    await answer(tester);
    expect(focused(), isNot('kostvMusicAlbumPlay'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('for someone with a limit (the songs don\'t say whether they '
      'are explicit): as with «Solo la de casa»', (tester) async {
    PlatformDetection.setTvMode(true);
    kids = true;
    await open(tester);
    await answer(tester);
    expect(find.byTooltip('Reproducir'), findsNothing);
    expect(find.byTooltip('Aleatorio'), findsNothing);
    expect(find.text('Pedir el álbum'), findsOneWidget);
    // It doesn't sound: no «suena en streaming», but why the whole album.
    expect(
      find.textContaining('Este disco no está en casa', findRichText: true),
      findsNothing,
    );
    expect(find.textContaining('Se pide el álbum entero'), findsOneWidget);
    expect(focused(), 'kostvMusicAsk');
    const away = StremfinAlbumTrack(title: 'Trueno', deezerId: '1');
    expect(kostvTrackPlayable(away), isFalse);
    const home = StremfinAlbumTrack(
      title: 'Calma',
      deezerId: '3',
      inJellyfin: true,
      jellyfinId: 'j3',
    );
    expect(kostvTrackPlayable(home), isTrue);
    kids = false;
    expect(kostvTrackPlayable(away), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Kos TV: the age limit read once the page is open: «Reproducir» '
      'comes then, without leaving and coming back', (tester) async {
    final limit = Completer<KostvAgeLimit>();
    final later = StremfinService(
      StremfinClient(
        dio: Dio()..httpClientAdapter = server,
        baseUrl: 'https://requests.example.org/api/v1',
        token: () => 'token',
      ),
      watchLifecycle: false,
      ageLimit: () => limit.future,
      parental: () => ParentalFilter.none,
    );
    GetIt.instance
      ..unregister<StremfinService>()
      ..registerSingleton<StremfinService>(later);
    unawaited(later.refreshAccess());
    await open(tester);
    await answer(tester);
    // Not known yet: as for someone with a limit.
    expect(find.byTooltip('Reproducir'), findsNothing);
    limit.complete(KostvAgeLimit.none);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byTooltip('Reproducir'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    later.dispose();
  });

  testWidgets('Kos TV: on the TV, «Ya está en casa» going with the remote on '
      'it: the remote goes to «Reproducir», not nowhere', (tester) async {
    PlatformDetection.setTvMode(true);
    server.homeOnceAsked = true;
    await open(tester);
    await answer(tester);
    expect(focused(), 'kostvMusicAlbumPlay');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 300));
    expect(focused(), 'kostvMusicAsk');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(server.asked, isTrue);
    expect(find.text('Ya está en casa'), findsOneWidget);
    expect(focused(), 'kostvMusicAsk');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Ya está en casa'), findsNothing);
    expect(focused(), 'kostvMusicAlbumPlay');
    await tester.pumpWidget(const SizedBox());
    // The service asks again whether the person may use it, every while.
    service.dispose();
    await tester.pump(const Duration(minutes: 3));
  });
}
