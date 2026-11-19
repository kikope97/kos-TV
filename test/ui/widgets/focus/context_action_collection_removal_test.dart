import 'dart:async';

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

AggregatedItem _movie() => const AggregatedItem(
  id: 'movie-1',
  serverId: 'server-1',
  rawData: {'Id': 'movie-1', 'Type': 'Movie', 'Name': 'Alpha'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockClient client;
  late UserRepository users;
  late _MockMutations mutations;

  /// What the confirmation flow asked the collection to remove.
  final removedItems = <AggregatedItem>[];

  setUp(() async {
    removedItems.clear();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();

    client = _MockClient();
    when(() => client.serverType).thenReturn(ServerType.jellyfin);
    when(() => client.baseUrl).thenReturn('https://media.example');

    users = UserRepository();

    GetIt.instance.registerSingleton<MediaServerClient>(client);
    GetIt.instance.registerSingleton<UserRepository>(users);
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    mutations = _MockMutations();
    GetIt.instance.registerSingleton<ItemMutationRepository>(mutations);
  });

  tearDown(() => GetIt.instance.reset());

  void signIn({bool canManage = false, bool admin = false}) {
    users.setCurrentUser(
      PrivateUser(
        id: 'u1',
        name: 'Test',
        serverId: 'server-1',
        accessToken: 'token',
        lastUsed: DateTime(2026),
        isAdministrator: admin,
        canManageCollections: canManage,
      ),
    );
  }

  Future<List<ItemContextAction>> buildActions(
    WidgetTester tester, {
    CollectionRemovalContext? collectionRemoval,
    AggregatedItem? item,
  }) async {
    late List<ItemContextAction> actions;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            actions = contextActionsFor(
              context,
              item ?? _movie(),
              collectionRemoval: collectionRemoval,
            );
            return const SizedBox.shrink();
          },
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    return actions;
  }

  final removal = CollectionRemovalContext(
    collectionName: 'Crossovers',
    remove: (item) async => removedItems.add(item),
  );

  testWidgets('Remove from Collection is offered from a collection page', (
    tester,
  ) async {
    signIn(canManage: true);
    final actions = await buildActions(tester, collectionRemoval: removal);
    expect(actions.map((a) => a.label), contains('Remove from Collection'));
  });

  testWidgets("the action is hidden when the user can't manage collections", (
    tester,
  ) async {
    signIn();
    final actions = await buildActions(tester, collectionRemoval: removal);
    expect(
      actions.map((a) => a.label),
      isNot(contains('Remove from Collection')),
    );
  });

  testWidgets('admins get the action even without the collection permission', (
    tester,
  ) async {
    signIn(admin: true);
    final actions = await buildActions(tester, collectionRemoval: removal);
    expect(actions.map((a) => a.label), contains('Remove from Collection'));
  });

  testWidgets('menus outside a collection page carry no remove entry', (
    tester,
  ) async {
    signIn(canManage: true);
    final actions = await buildActions(tester);
    expect(
      actions.map((a) => a.label),
      isNot(contains('Remove from Collection')),
    );
  });

  testWidgets('confirming the dialog performs the removal', (tester) async {
    signIn(canManage: true);
    final actions = await buildActions(tester, collectionRemoval: removal);
    final action = actions.firstWhere(
      (a) => a.label == 'Remove from Collection',
    );

    // onSelect waits for the dialog to close, so let it run while the test
    // drives the dialog itself.
    unawaited(action.onSelect());
    await tester.pumpAndSettle();
    expect(find.textContaining('Remove Alpha from Crossovers'), findsOneWidget);
    expect(removedItems, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(removedItems.map((i) => i.id), ['movie-1']);
  });

  // Kos TV: the cards name their server by its address, never by the
  // user's server id, and that made everyone a collection manager.
  testWidgets('a card named by the server address still needs the permission', (
    tester,
  ) async {
    signIn();
    const card = AggregatedItem(
      id: 'movie-1',
      serverId: 'https://media.example/',
      rawData: {'Id': 'movie-1', 'Type': 'Movie', 'Name': 'Alpha'},
    );
    final actions = await buildActions(tester, item: card);
    expect(actions.map((a) => a.label), isNot(contains('Add to Collection')));

    signIn(canManage: true);
    final allowed = await buildActions(tester, item: card);
    expect(allowed.map((a) => a.label), contains('Add to Collection'));
  });

  // Kos TV: Kids Mode keeps to what its detail page offers.
  testWidgets('Kids Mode offers only playing, the favourite and the series', (
    tester,
  ) async {
    signIn(admin: true, canManage: true);
    await GetIt.instance<UserPreferences>().set(
      UserPreferences.kidsModeEnabled,
      true,
    );
    const episode = AggregatedItem(
      id: 'ep-1',
      serverId: 'server-1',
      rawData: {
        'Id': 'ep-1',
        'Type': 'Episode',
        'Name': 'Uno',
        'SeriesId': 'series-1',
        'UserData': {'PlaybackPositionTicks': 100},
      },
    );
    final actions = await buildActions(
      tester,
      item: episode,
      collectionRemoval: removal,
    );
    // No hiding it from Continue Watching either, though it has progress.
    expect(actions.map((a) => a.label), [
      'Play',
      'Add to Favorites',
      'Go to Series',
    ]);
  });

  // Kos TV: a failure used to vanish: the heart lit and went out unexplained.
  testWidgets('a favourite or watched change that fails says so', (
    tester,
  ) async {
    signIn();
    when(
      () => mutations.setFavorite(any(), isFavorite: any(named: 'isFavorite')),
    ).thenThrow(Exception('offline'));
    when(() => mutations.setPlayed(any(), isPlayed: any(named: 'isPlayed')))
        .thenThrow(Exception('offline'));
    var changed = 0;
    late List<ItemContextAction> actions;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              actions = contextActionsFor(
                context,
                _movie(),
                onChanged: () => changed++,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );

    await actions.firstWhere((a) => a.label == 'Add to Favorites').onSelect();
    await tester.pump();
    expect(find.text("Couldn't change the favorite"), findsOneWidget);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    await tester.pump();

    await actions.firstWhere((a) => a.label == 'Mark as Watched').onSelect();
    await tester.pump();
    expect(find.text("Couldn't mark it as watched"), findsOneWidget);
    expect(changed, 0);
  });
}
