import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_catalog.dart';
import 'package:moonfin/data/services/kostv_music_dislikes.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/music/kostv_music_actions.dart';
import 'package:moonfin/ui/screens/music/kostv_music_album_screen.dart'
    show KostvMusicTrackRow;
import 'package:moonfin/ui/screens/music/kostv_music_links.dart';
import 'package:moonfin/ui/screens/music/kostv_music_widgets.dart';
import 'package:moonfin/ui/screens/music/kostv_stream_widgets.dart'
    show KostvPulse, KostvStreamMark, KostvStreamPill, kostvStreamAlbumState;
import 'package:moonfin/ui/widgets/music/kostv_stream_play.dart';
import 'package:moonfin/util/focus/input_mode_tracker.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the Music pages with «Toda la música» (what isn't at home plays
/// through the requests service) and, unchanged, with «Solo la de casa».

const _server = 'https://casa.example';

/// The plugin's «No me gusta» list, empty.
class _Plugin implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path.endsWith('/Dislikes')) {
      return ResponseBody.fromString(
        jsonEncode({'Songs': const [], 'Artists': const []}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

AggregatedItem _away() => kostvStreamItem(
  deezerId: '77',
  title: 'Lejos',
  serverId: _server,
  artist: 'Rayo',
  album: 'Tormenta',
  albumDeezerId: 'al77',
  artistDeezerId: 'ar1',
);

void main() {
  late UserPreferences prefs;

  Future<void> catalog({required bool all}) async {
    await prefs.set(UserPreferences.kostvMusicCatalogAll, all);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    KostvMusicCatalog.instance = KostvMusicCatalog(prefs: () => prefs);
  });

  tearDown(() async {
    KostvMusicCatalog.instance = KostvMusicCatalog();
    KostvMusicDislikesStore.instance = KostvMusicDislikesStore();
    await GetIt.instance.reset();
  });

  group('a song of a list', () {
    Future<void> row(
      WidgetTester tester, {
      bool atHome = false,
      bool away = false,
    }) => tester.pumpWidget(
      _app(
        KostvMusicSongRow(
          title: 'Lejos',
          artist: 'Rayo',
          atHome: atHome,
          away: away,
          onTap: () {},
        ),
      ),
    );

    testWidgets('with «Toda la música»: it plays, no «Pedir»', (tester) async {
      await row(tester, away: true);
      expect(find.text('Pedir'), findsNothing);
      expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('with «Solo la de casa»: «Pedir», as before', (tester) async {
      await row(tester);
      expect(find.text('Pedir'), findsOneWidget);
      await row(tester, atHome: true);
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    });

    // Kos TV: whether it is at home shows on every row that can be either.
    testWidgets('one that sounds in streaming has the small cloud after its '
        'artist, with «No está en casa»; one at home, none', (tester) async {
      await row(tester, away: true);
      expect(find.byType(KostvStreamMark), findsOneWidget);
      expect(find.byTooltip('No está en casa'), findsOneWidget);
      // Right after the artist line, on the same line.
      final artist = tester.getRect(find.text('Rayo'));
      final cloud = tester.getRect(find.byType(KostvStreamMark));
      expect(cloud.left, greaterThanOrEqualTo(artist.right));
      expect(cloud.center.dy, closeTo(artist.center.dy, 4));
      await row(tester, atHome: true);
      expect(find.byType(KostvStreamMark), findsNothing);
      // A chart's song with its album at home is played from home.
      await row(tester, atHome: true, away: true);
      expect(find.byType(KostvStreamMark), findsNothing);
      // With «Solo la de casa» it has its «Pedir» and doesn't sound.
      await row(tester);
      expect(find.byType(KostvStreamMark), findsNothing);
    });

    testWidgets('with its links (the artist and the album that open), the '
        'cloud too', (tester) async {
      await tester.pumpWidget(
        _app(
          KostvMusicSongRow(
            title: 'Lejos',
            artistLinks: [
              [KostvMusicLink('Rayo', () {})],
              [KostvMusicLink('Tormenta', () {})],
            ],
            away: true,
            onTap: () {},
          ),
        ),
      );
      expect(find.byType(KostvStreamMark), findsOneWidget);
    });
  });

  group('a song of an album\'s page', () {
    Future<void> track(
      WidgetTester tester, {
      bool atHome = false,
      bool away = false,
    }) => tester.pumpWidget(
      _app(
        KostvMusicTrackRow(
          number: 1,
          title: 'Lejos',
          duration: 200,
          atHome: atHome,
          away: away,
          onTap: () {},
        ),
      ),
    );

    testWidgets('in streaming, the cloud where one at home has its tick', (
      tester,
    ) async {
      await track(tester, away: true);
      expect(find.byType(KostvStreamMark), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      await track(tester, atHome: true);
      expect(find.byType(KostvStreamMark), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      await track(tester);
      expect(find.byType(KostvStreamMark), findsNothing);
    });
  });

  testWidgets('a list\'s heading has its «Reproducir» and «Aleatorio»', (
    tester,
  ) async {
    var played = 0;
    var shuffled = 0;
    await tester.pumpWidget(
      _app(
        KostvMusicHeading(
          title: 'Top España',
          subtitle: 'Lo más escuchado',
          actions: [
            KostvMusicRowAction(
              icon: Icons.play_arrow_rounded,
              label: 'Reproducir',
              primary: true,
              onTap: () => played++,
            ),
            KostvMusicRowAction(
              icon: Icons.shuffle_rounded,
              label: 'Aleatorio',
              onTap: () => shuffled++,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Reproducir'));
    await tester.tap(find.text('Aleatorio'));
    expect((played, shuffled), (1, 1));
  });

  group('resting on a song asks for it in advance', () {
    testWidgets('the mouse on it, and off it', (tester) async {
      final told = <bool>[];
      await tester.pumpWidget(
        _app(
          Center(
            child: KostvMusicSongRow(
              title: 'Lejos',
              away: true,
              onTap: () {},
              onRest: told.add,
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Lejos')));
      await tester.pump();
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(told, [true, false]);
      await mouse.removePointer();
    });

    testWidgets('the remote\'s focus on it (a TV)', (tester) async {
      PlatformDetection.setTvMode(true);
      addTearDown(() => PlatformDetection.setTvMode(false));
      final told = <bool>[];
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _app(
          InputModeTracker(
            child: KostvMusicSongRow(
              title: 'Lejos',
              away: true,
              focusNode: node,
              onTap: () {},
              onRest: told.add,
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      expect(told, [true]);
      node.unfocus();
      await tester.pump();
      expect(told, [true, false]);
    });

    testWidgets('a tap (a phone) doesn\'t', (tester) async {
      final told = <bool>[];
      await tester.pumpWidget(
        _app(
          KostvMusicSongRow(
            title: 'Lejos',
            away: true,
            onTap: () {},
            onRest: told.add,
          ),
        ),
      );
      await tester.tap(find.text('Lejos'));
      await tester.pump();
      expect(told, isEmpty);
    });
  });

  group('the menu of a song that is not at home', () {
    late BuildContext context;

    Future<void> host(WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
    }

    Future<void> open(WidgetTester tester, Future<void> menu) async {
      unawaited(menu);
      // What it says of its album and its artist, looked for meanwhile.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
    }

    // The menu closed: the next one may open (one at a time).
    Future<void> close(WidgetTester tester) async {
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    }

    testWidgets('what it can do, and nothing of the home server\'s', (
      tester,
    ) async {
      await catalog(all: true);
      await host(tester);
      await open(tester, showKostvMusicSongMenu(context, item: _away()));
      expect(find.text('Lejos'), findsOneWidget);
      expect(find.text('Rayo · No está en casa'), findsOneWidget);
      // Kos TV: the same cloud as in the lists, after it.
      expect(find.byType(KostvStreamMark), findsOneWidget);
      for (final entry in [
        'Reproducir a continuación',
        'Añadir al final de la cola',
        'Crear emisora',
        'Ir al álbum',
        'Ir al artista',
        'Pedir álbum',
      ]) {
        expect(find.text(entry), findsOneWidget, reason: entry);
      }
      expect(find.text('Añadir a una lista'), findsNothing);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
      // Without the plugin's list, no «No me gusta».
      expect(find.text('No me gusta'), findsNothing);
      await close(tester);
    });

    testWidgets('with the plugin\'s list, «No me gusta» too', (tester) async {
      await catalog(all: true);
      final client =
          JellyfinMediaServerClient(
              baseUrl: _server,
              deviceInfo: const DeviceInfo(
                id: 'device',
                name: 'Device',
                appName: 'kOS TV',
                appVersion: '1.0.0',
              ),
            )
            ..accessToken = 'token'
            ..userId = 'ana';
      GetIt.instance.registerSingleton<MediaServerClient>(client);
      final store = KostvMusicDislikesStore(
        KostvMusicPlugin(dio: Dio()..httpClientAdapter = _Plugin()),
      );
      KostvMusicDislikesStore.instance = store;
      await tester.runAsync(() => store.load(client));
      await host(tester);
      await open(tester, showKostvMusicSongMenu(context, item: _away()));
      expect(find.text('No me gusta'), findsOneWidget);
      await close(tester);
    });

    testWidgets('on its own album\'s page, no «Ir al álbum»', (tester) async {
      await catalog(all: true);
      await host(tester);
      await open(
        tester,
        showKostvMusicSongMenu(
          context,
          item: _away(),
          fromAlbumDeezerId: 'al77',
        ),
      );
      expect(find.text('Ir al álbum'), findsNothing);
      expect(find.text('Ir al artista'), findsOneWidget);
      await close(tester);
    });

    const song = StremfinSong(
      title: 'Lejos',
      deezerId: '77',
      artist: 'Rayo',
      artistDeezerId: 'ar1',
      albumDeezerId: 'al77',
    );

    testWidgets('a song of a list, with «Toda la música»', (tester) async {
      await catalog(all: true);
      await host(tester);
      await open(tester, showKostvMusicSongMenu(context, song: song));
      expect(find.text('Crear emisora'), findsOneWidget);
      expect(find.text('Ver el álbum para pedirlo'), findsNothing);
      await close(tester);
    });

    testWidgets('with «Solo la de casa», as before', (tester) async {
      await catalog(all: false);
      await host(tester);
      await open(tester, showKostvMusicSongMenu(context, song: song));
      expect(find.text('Ver el álbum para pedirlo'), findsOneWidget);
      expect(find.text('Ir al artista'), findsOneWidget);
      expect(find.text('Crear emisora'), findsNothing);
      expect(find.text('Reproducir a continuación'), findsNothing);
      await close(tester);
    });

    testWidgets('explicit, for someone with a limit: as one that can\'t play', (
      tester,
    ) async {
      // Without the requests service, the app hides what is explicit.
      await catalog(all: true);
      await host(tester);
      await open(
        tester,
        showKostvMusicSongMenu(
          context,
          song: const StremfinSong(
            title: 'Fuerte',
            deezerId: '78',
            artist: 'Rayo',
            explicit: true,
          ),
        ),
      );
      expect(find.text('Crear emisora'), findsNothing);
      expect(find.text('Reproducir a continuación'), findsNothing);
      await close(tester);
    });
  });

  test('«Pedir álbum» says how its album stands', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    expect(
      kostvStreamAlbumState(
        l10n,
        const StremfinAlbum(
          title: 'Tormenta',
          deezerId: 'al1',
          canRequest: true,
        ),
        hasAlbum: true,
      ),
      (label: 'Pedir álbum', icon: Icons.add_rounded, can: true),
    );
    // Not known yet: it can be asked for (the service says if not).
    expect(kostvStreamAlbumState(l10n, null, hasAlbum: true)?.can, isTrue);
    final onItsWay = kostvStreamAlbumState(
      l10n,
      const StremfinAlbum(
        title: 'Tormenta',
        download: StremfinAlbumDownload(phase: 'downloading', percent: 42),
      ),
      hasAlbum: true,
    );
    expect(onItsWay?.label, 'De camino · 42 %');
    expect(onItsWay?.can, isFalse);
    expect(kostvStreamAlbumState(l10n, null, hasAlbum: false), isNull);
    expect(
      kostvStreamAlbumState(
        l10n,
        const StremfinAlbum(title: 'Tormenta', inJellyfin: true),
        hasAlbum: true,
      ),
      isNull,
    );
  });

  group('the radio and the mixes with «Solo la de casa»', () {
    final home = AggregatedItem(
      id: 'h1',
      serverId: _server,
      rawData: const {'Id': 'h1', 'Name': 'Casa', 'Type': 'Audio'},
    );

    test('a song at home: only the home server\'s mix, as before', () async {
      await catalog(all: false);
      expect(kostvStationWantsRadio(home), isFalse);
      // One that isn't at home has no mix there: the service's radio.
      expect(kostvStationWantsRadio(_away()), isTrue);
      await catalog(all: true);
      expect(kostvStationWantsRadio(home), isTrue);
    });

    test('a daily mix stays as it is', () async {
      await catalog(all: false);
      final items = [home];
      expect(
        await kostvMixQueue(mixId: 'daily-1', items: items, because: ['Lola']),
        same(items),
      );
    });

    test('a song\'s station artists: Deezer\'s id when it has one', () {
      expect(kostvStationArtists(_away()).ids, ['ar1']);
      final song = AggregatedItem(
        id: 'h2',
        serverId: _server,
        rawData: const {
          'Id': 'h2',
          'Name': 'Casa',
          'Type': 'Audio',
          'Artists': ['Lola', 'Nube', 'Sol'],
        },
      );
      expect(kostvStationArtists(song).names, ['Lola', 'Nube']);
    });
  });

  group('Kos TV: second audit of the pages', () {
    test('a song Jellyfin didn\'t give, with a home id, keeps the home menu; '
        'one without it has the menu of one that isn\'t at home only when '
        'it may sound', () async {
      await catalog(all: true);
      // Without the requests service, the app hides what is explicit.
      const away = StremfinSong(title: 'Lejos', deezerId: '77', artist: 'Rayo');
      expect(kostvSongMenuFromAway(away), isTrue);
      const hidden = StremfinSong(
        title: 'Casa',
        deezerId: '78',
        artist: 'Rayo',
        inJellyfin: true,
        jellyfinId: 'j78',
      );
      expect(kostvSongPlayable(hidden), isTrue);
      expect(kostvSongMenuFromAway(hidden), isFalse);
      const explicit = StremfinSong(
        title: 'Fuerte',
        deezerId: '79',
        artist: 'Rayo',
        explicit: true,
      );
      expect(kostvSongMenuFromAway(explicit), isFalse);
      await catalog(all: false);
      expect(kostvSongMenuFromAway(away), isFalse);
    });

    testWidgets('the cover beats again when «Preparando…» comes back while '
        'it was settling', (tester) async {
      Future<void> pulse(bool active) => tester.pumpWidget(
        _app(KostvPulse(active: active, child: const SizedBox(width: 40))),
      );
      double opacity() => tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(KostvPulse),
              matching: find.byType(Opacity),
            ),
          )
          .opacity;
      Future<bool> beating() async {
        final before = opacity();
        await tester.pump(const Duration(milliseconds: 300));
        return opacity() != before;
      }

      await pulse(true);
      expect(await beating(), isTrue);
      await pulse(false);
      // Settling back (250 ms), and on again before it ends.
      await tester.pump(const Duration(milliseconds: 100));
      await pulse(true);
      await tester.pump(const Duration(seconds: 2));
      expect(await beating(), isTrue);
      await pulse(false);
      await tester.pumpAndSettle();
      expect(await beating(), isFalse);
    });

    testWidgets('«Pedir álbum» is cut short on a narrow phone with big '
        'text, rather than overflowing', (tester) async {
      tester.view.physicalSize = const Size(300, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(300, 700),
            textScaler: TextScaler.linear(2.5),
          ),
          child: _app(
            KostvStreamPill(
              item: _away(),
              stop: (onTap, builder) =>
                  Builder(builder: (context) => builder(context, false)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Pedir álbum'), findsOneWidget);
    });
  });
}
