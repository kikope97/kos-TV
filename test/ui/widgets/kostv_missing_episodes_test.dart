import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/stremfin/kostv_series_gaps.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/kostv_missing_episodes.dart';
import 'package:moonfin/ui/widgets/playback/kostv_gap_overlay.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the missing episodes of a series at home, on the player's card
/// and in an episode's sheet.
void main() {
  KostvGhostEpisode ghost(
    int number, {
    bool canRequest = true,
    StremfinRequestRef? request,
    bool aired = true,
    DateTime? airDate,
  }) => KostvGhostEpisode(
    season: 1,
    source: StremfinEpisode(
      number: number,
      title: 'Episodio con título $number',
      airDate: airDate ?? DateTime(2024, 1, number),
      aired: aired,
      request: request,
      canRequest: canRequest,
    ),
  );

  final next = AggregatedItem(
    id: 'e9',
    serverId: 'home',
    rawData: const {
      'Type': 'Episode',
      'ParentIndexNumber': 1,
      'IndexNumber': 9,
      'SeriesId': 's',
    },
  );

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    ThemeRegistry.setActiveById(ThemeRegistry.moonfinId);
  });

  tearDown(() => GetIt.instance.reset());

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group("the player's card", () {
    testWidgets('one missing: ask for it or watch the next one at home', (
      tester,
    ) async {
      var asked = 0;
      var watched = 0;
      await tester.pumpWidget(
        app(
          Stack(
            children: [
              KostvGapOverlay(
                missing: [ghost(7)],
                next: next,
                ask: KostvGapAsk.idle,
                onAsk: () => asked++,
                onWatchNext: () => watched++,
                onClose: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.text('El episodio 7 no está en casa'), findsOneWidget);
      expect(find.text('Episodio con título 7'), findsOneWidget);
      await tester.tap(find.text('Solicitarlo'));
      await tester.tap(find.text('Ver el 9'));
      expect(asked, 1);
      expect(watched, 1);
    });

    testWidgets('several missing, asked for already', (tester) async {
      await tester.pumpWidget(
        app(
          Stack(
            children: [
              KostvGapOverlay(
                missing: [ghost(7), ghost(8)],
                next: next,
                ask: KostvGapAsk.sent,
                onAsk: () {},
                onWatchNext: () {},
                onClose: () {},
              ),
            ],
          ),
        ),
      );

      expect(
        find.text('Los episodios del 7 al 8 no están en casa'),
        findsOneWidget,
      );
      // On the button and on the line under the title.
      expect(find.text('Solicitados'), findsNWidgets(2));
      expect(find.text('Ver el 9'), findsOneWidget);
    });

    testWidgets("one someone asked for already, and nothing after: it says "
        'so and only closes', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        app(
          Stack(
            children: [
              KostvGapOverlay(
                missing: [
                  ghost(
                    10,
                    canRequest: false,
                    request: const StremfinRequestRef(
                      id: 3,
                      status: 'pending',
                      mine: true,
                    ),
                  ),
                ],
                next: null,
                ask: KostvGapAsk.idle,
                onAsk: () {},
                onWatchNext: () {},
                onClose: () => closed++,
              ),
            ],
          ),
        ),
      );

      expect(
        find.text('Lo has solicitado: falta que lo acepten'),
        findsOneWidget,
      );
      expect(find.text('Solicitarlo'), findsNothing);
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(closed, 1);
    });
  });

  group("an episode's sheet", () {
    testWidgets('one on already offers asking for it', (tester) async {
      final controller = KostvSeriesGapsController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showKostvGhostSheet(
                context,
                controller: controller,
                ghost: ghost(7),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('TEMPORADA 1 · EPISODIO 7'), findsOneWidget);
      expect(find.text('Episodio con título 7'), findsOneWidget);
      expect(find.text('Se emitió el 7 de enero de 2024'), findsOneWidget);
      expect(find.text('Solicitar este episodio'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Solicitar este episodio'), findsNothing);
    });

    testWidgets('one not on yet says when, and offers nothing', (
      tester,
    ) async {
      final controller = KostvSeriesGapsController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showKostvGhostSheet(
                context,
                controller: controller,
                ghost: ghost(
                  10,
                  aired: false,
                  canRequest: false,
                  airDate: DateTime(DateTime.now().year + 1, 3, 4),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(
        find.text('Se estrena el 4 de marzo de ${DateTime.now().year + 1}'),
        findsOneWidget,
      );
      expect(find.text('Solicitar este episodio'), findsNothing);
      expect(find.text('Cerrar'), findsOneWidget);
    });
  });
}
