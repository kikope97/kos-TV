import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/kostv_music_catalog.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/music/kostv_music_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A song of the week's discovery that isn't at home: what the service says
/// of it now is asked before it opens, within the same lock as opening it.
///
/// Kos TV: with «Solo la de casa», where such a song opens its album (with
/// «Toda la música» it plays, see `kostv_stream_screens_test.dart`).
void main() {
  const song = StremfinSong(title: 'Despechá', deezerId: '123');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    final prefs = UserPreferences(store);
    await prefs.set(UserPreferences.kostvMusicCatalogAll, false);
    KostvMusicCatalog.instance = KostvMusicCatalog(prefs: () => prefs);
  });

  tearDown(() => KostvMusicCatalog.instance = KostvMusicCatalog());

  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return context;
  }

  testWidgets('two presses while the service is asked: asked once, opened '
      'once', (tester) async {
    final context = await host(tester);
    final answer = Completer<StremfinSong?>();
    var asked = 0;
    Future<StremfinSong?> refresh(StremfinSong _) {
      asked++;
      return answer.future;
    }

    unawaited(openKostvMusicSong(context, song, refresh: refresh));
    await tester.pump();
    // The second OK lands while the first is still asking.
    unawaited(openKostvMusicSong(context, song, refresh: refresh));
    await tester.pump();
    expect(asked, 1);
    // The short wait is shown meanwhile.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    answer.complete(song);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Free again once it is done.
    unawaited(openKostvMusicSong(context, song, refresh: (_) async => song));
    await tester.pumpAndSettle();
    expect(asked, 1);
  });

  testWidgets('the menu waits for the same lock: no menu while a song opens', (
    tester,
  ) async {
    final context = await host(tester);
    final answer = Completer<StremfinSong?>();
    var asked = 0;
    unawaited(
      openKostvMusicSong(
        context,
        song,
        refresh: (_) {
          asked++;
          return answer.future;
        },
      ),
    );
    await tester.pump();
    unawaited(
      showKostvMusicSongMenu(
        context,
        song: song,
        refresh: (_) async {
          asked++;
          return song;
        },
      ),
    );
    await tester.pump();
    expect(asked, 1);
    answer.complete(null);
    await tester.pumpAndSettle();
  });
}
