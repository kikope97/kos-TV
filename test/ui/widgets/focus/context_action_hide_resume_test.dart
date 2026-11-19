import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/item_mutation_repository.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/focus/context_action.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockMutations extends Mock implements ItemMutationRepository {}

/// An ItemsApi without Silo's server-side Home hides.
class _ItemsApi extends Mock implements ItemsApi {}

/// Jellyfin's: no way to hide a resume point, so the hide clears it.
class _UserLibraryApi extends Mock implements UserLibraryApi {}

AggregatedItem _episode() => AggregatedItem(
  id: 'ep-1',
  serverId: 'server-1',
  rawData: {
    'Id': 'ep-1',
    'Type': 'Episode',
    'Name': 'Pilot',
    'SeriesId': 'series-1',
    'UserData': {'PlaybackPositionTicks': 6000000000, 'Played': false},
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockMutations mutations;
  late UserPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);

    final client = _MockClient();
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    // The menu asks the item's server whether it hides Home cards itself
    // (Silo), and Jellyfin doesn't.
    when(() => client.baseUrl).thenReturn('https://jellyfin.example');
    when(() => client.itemsApi).thenReturn(_ItemsApi());
    when(() => client.userLibraryApi).thenReturn(_UserLibraryApi());

    final users = UserRepository();
    users.setCurrentUser(
      PrivateUser(
        id: 'u1',
        name: 'Test',
        serverId: 'server-1',
        accessToken: 'token',
        lastUsed: DateTime(2026),
      ),
    );

    mutations = _MockMutations();
    when(
      () => mutations.setPlayed(any(), isPlayed: any(named: 'isPlayed')),
    ).thenAnswer((_) async {});
    when(
      () => mutations.restorePlaybackPosition(
        any(),
        positionTicks: any(named: 'positionTicks'),
        playedPercentage: any(named: 'playedPercentage'),
      ),
    ).thenAnswer((_) async {});

    GetIt.instance.registerSingleton<MediaServerClient>(client);
    GetIt.instance.registerSingleton<UserRepository>(users);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
    GetIt.instance.registerSingleton<ItemMutationRepository>(mutations);
  });

  tearDown(() => GetIt.instance.reset());

  Future<ItemContextAction> action(
    WidgetTester tester,
    String label, {
    AggregatedItem? item,
  }) async {
    late List<ItemContextAction> actions;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            actions = contextActionsFor(context, item ?? _episode());
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return actions.firstWhere((a) => a.label == label);
  }

  // Kos TV: on Jellyfin the option says the resume point goes with it.
  const forgets = 'Remove from Continue Watching (forgets where you were)';

  group('Hide from Continue Watching', () {
    testWidgets('without server support hides locally and resets as before', (
      tester,
    ) async {
      when(
        () => mutations.hideFromResume('ep-1'),
      ).thenAnswer((_) async => false);

      await (await action(tester, forgets)).onSelect();
      await tester.pump();

      verify(() => mutations.setPlayed('ep-1', isPlayed: false)).called(1);
      expect(prefs.getHiddenContinueWatchingItems().keys, ['series-1']);
      // Let the undo notice run out.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    });

    testWidgets('offers an undo that brings back where it was left', (
      tester,
    ) async {
      when(
        () => mutations.hideFromResume('ep-1'),
      ).thenAnswer((_) async => false);

      await (await action(tester, forgets)).onSelect();
      await tester.pump();
      await tester.pump();

      expect(
        find.text('“Pilot” removed from Continue Watching'),
        findsOneWidget,
      );
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump();

      verify(
        () => mutations.restorePlaybackPosition(
          'ep-1',
          positionTicks: 6000000000,
          playedPercentage: any(named: 'playedPercentage'),
        ),
      ).called(1);
      expect(prefs.getHiddenContinueWatchingItems(), isEmpty);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('left alone, the notice goes and nothing is put back', (
      tester,
    ) async {
      when(
        () => mutations.hideFromResume('ep-1'),
      ).thenAnswer((_) async => false);

      await (await action(tester, forgets)).onSelect();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(find.text('Undo'), findsNothing);
      verifyNever(
        () => mutations.restorePlaybackPosition(
          any(),
          positionTicks: any(named: 'positionTicks'),
          playedPercentage: any(named: 'playedPercentage'),
        ),
      );
      expect(prefs.getHiddenContinueWatchingItems().keys, ['series-1']);
    });
  });

  group('ContinueWatchingHideUndo', () {
    test('unhides and leaves the progress alone when it was kept', () async {
      await prefs.hideFromContinueWatching('series-1');
      final ok = await const ContinueWatchingHideUndo(
        itemId: 'ep-1',
        hiddenId: 'series-1',
        positionTicks: null,
      ).run(prefs: prefs, mutations: mutations);

      expect(ok, isTrue);
      expect(prefs.getHiddenContinueWatchingItems(), isEmpty);
      verifyNever(
        () => mutations.restorePlaybackPosition(
          any(),
          positionTicks: any(named: 'positionTicks'),
          playedPercentage: any(named: 'playedPercentage'),
        ),
      );
    });

    test('says so when the server refuses the position', () async {
      when(
        () => mutations.restorePlaybackPosition(
          any(),
          positionTicks: any(named: 'positionTicks'),
          playedPercentage: any(named: 'playedPercentage'),
        ),
      ).thenThrow(Exception('refused'));
      final ok = await const ContinueWatchingHideUndo(
        itemId: 'ep-1',
        hiddenId: 'series-1',
        positionTicks: 42,
      ).run(prefs: prefs, mutations: mutations);
      expect(ok, isFalse);
    });
  });

  group('Hide from Next Up', () {
    testWidgets('without server support still resets as before', (
      tester,
    ) async {
      when(
        () => mutations.hideFromResume('ep-1'),
      ).thenAnswer((_) async => false);

      await (await action(tester, 'Hide from Next Up')).onSelect();

      verify(() => mutations.setPlayed('ep-1', isPlayed: false)).called(1);
    });
  });
}
