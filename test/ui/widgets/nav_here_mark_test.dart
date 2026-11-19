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
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/widgets/left_sidebar.dart';
import 'package:moonfin/ui/widgets/navigation_layout.dart';
import 'package:moonfin/ui/widgets/top_toolbar.dart';
import 'package:moonfin/util/game_library.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kos TV: the menu marks the page on screen, and the side rail is entered on
// that page's own item.

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

Widget _host(Widget body) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

final _mark = find.byKey(const ValueKey('nav_here_mark'));

Finder _markOn(String key) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: _mark);

String? _focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

/// A page of cards to the right of the rail, as the Genres grid is.
Widget _railOverPage(FocusNode firstCard) => Stack(
  children: [
    Positioned.fill(
      left: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 200),
          Focus(
            focusNode: firstCard,
            child: const SizedBox(width: 200, height: 120),
          ),
          Focus(
            debugLabel: 'Card 2',
            child: const SizedBox(width: 200, height: 120),
          ),
        ],
      ),
    ),
    const Positioned(
      top: 0,
      left: 0,
      bottom: 0,
      child: LeftSidebar(activeRoute: Destinations.allGenres),
    ),
  ],
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    final getIt = GetIt.instance;
    getIt.registerSingleton<PreferenceStore>(store);
    getIt.registerSingleton<UserPreferences>(UserPreferences(store));
    getIt.registerSingleton<UserRepository>(_FakeUserRepository());
    getIt.registerSingleton<UserViewsRepository>(_FakeUserViewsRepository());
    getIt.registerSingleton<PluginSyncService>(_FakePluginSyncService());
    getIt.registerSingleton<GameLibraryRegistry>(_FakeGameLibraryRegistry());
    getIt.registerSingleton<PlaybackManager>(_FakePlaybackManager());
    getIt.registerSingleton<MediaServerClientFactory>(_FakeClientFactory());
  });

  tearDown(() async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    NavigationLayout.chromeFocusRoots.clear();
    await GetIt.instance.reset();
  });

  Future<void> setView(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  for (final layout in [
    InterfaceLayout.tv,
    InterfaceLayout.desktop,
    InterfaceLayout.phone,
  ]) {
    testWidgets('the top bar marks the page on screen (${layout.name})', (
      tester,
    ) async {
      PlatformDetection.setInterfaceLayout(layout);
      await setView(
        tester,
        layout == InterfaceLayout.phone
            ? const Size(400, 850)
            : const Size(1600, 900),
      );
      await tester.pumpWidget(
        _host(const TopToolbar(activeRoute: Destinations.allGenres)),
      );
      await tester.pump();

      expect(_markOn('toolbar_genres'), findsWidgets);
      expect(_markOn('toolbar_home'), findsNothing);
      expect(_markOn('toolbar_search'), findsNothing);
    });
  }

  for (final layout in [InterfaceLayout.tv, InterfaceLayout.desktop]) {
    testWidgets('the side rail marks the page on screen (${layout.name})', (
      tester,
    ) async {
      PlatformDetection.setInterfaceLayout(layout);
      await setView(tester, const Size(1600, 900));
      await tester.pumpWidget(
        _host(const LeftSidebar(activeRoute: Destinations.allGenres)),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(_markOn('sidebar-genres'), findsWidgets);
      expect(_markOn('sidebar-home'), findsNothing);
      expect(_markOn('sidebar-search'), findsNothing);
    });
  }

  testWidgets('the open rail is near opaque over the page', (tester) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    await setView(tester, const Size(1280, 720));
    await tester.pumpWidget(
      _host(const LeftSidebar(activeRoute: Destinations.allGenres)),
    );
    await tester.pump(const Duration(milliseconds: 700));
    NavigationLayout.focusNavbarNotifier.value!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The panel behind the items, as wide as the open rail's backdrop.
    final panel = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.constraints?.maxWidth == 264 &&
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).color != null,
        )
        .single;
    // The default menu colour is grey at half opacity; the open panel lays
    // it over a dark base.
    expect((panel.decoration! as BoxDecoration).color!.a, greaterThan(0.97));
  });

  group('entering the TV rail from the page', () {
    setUp(() => PlatformDetection.setInterfaceLayout(InterfaceLayout.tv));

    testWidgets('Left lands on the page\'s own item, and Up and Down move '
        'along the rail', (tester) async {
      await setView(tester, const Size(1280, 720));
      final firstCard = FocusNode(debugLabel: 'Card 1');
      addTearDown(firstCard.dispose);
      await tester.pumpWidget(_host(_railOverPage(firstCard)));
      // The rail ignores focus for a moment after it mounts.
      await tester.pump(const Duration(milliseconds: 700));

      firstCard.requestFocus();
      await tester.pump();
      expect(_focusedLabel(), 'Card 1');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_focusedLabel(), 'SidebarMenu ${Destinations.allGenres}');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final below = _focusedLabel();
      expect(below, isNot('SidebarMenu ${Destinations.allGenres}'));
      expect(below, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_focusedLabel(), 'SidebarMenu ${Destinations.allGenres}');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_focusedLabel(), isNot('SidebarMenu ${Destinations.allGenres}'));
      expect(_focusedLabel(), startsWith('SidebarMenu'));
    });

    testWidgets('a page with no item of its own keeps the nearest item', (
      tester,
    ) async {
      await setView(tester, const Size(1280, 720));
      final firstCard = FocusNode(debugLabel: 'Card 1');
      addTearDown(firstCard.dispose);
      await tester.pumpWidget(
        _host(
          Stack(
            children: [
              Positioned.fill(
                left: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 200),
                    Focus(
                      focusNode: firstCard,
                      child: const SizedBox(width: 200, height: 120),
                    ),
                  ],
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                bottom: 0,
                child: LeftSidebar(activeRoute: '/item/abc'),
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      firstCard.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_focusedLabel(), isNot('Card 1'));
      expect(_focusedLabel(), isNot('SidebarMenu ${Destinations.allGenres}'));
    });
  });
}
