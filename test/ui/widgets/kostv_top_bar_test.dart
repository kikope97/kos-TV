import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/widgets/kos_logo.dart';
import 'package:moonfin/ui/widgets/kostv_menu/kostv_glass.dart';
import 'package:moonfin/ui/widgets/kostv_menu/kostv_nav_avatar.dart';
import 'package:moonfin/ui/widgets/navigation_layout.dart';
import 'package:moonfin/ui/widgets/top_toolbar.dart';
import 'package:moonfin/util/game_library.dart';
import 'package:moonfin/util/platform_detection.dart';

import 'bottom_nav/bottom_nav_fakes.dart';

/// Libraries for the toolbar, a films one and a shows one.
class _Views extends ChangeNotifier implements UserViewsRepository {
  @override
  Future<List<AggregatedLibrary>> getUserViews() async => const [
    AggregatedLibrary(
      id: 'films',
      name: 'Films',
      collectionType: 'movies',
      serverId: 'srv',
    ),
    AggregatedLibrary(
      id: 'shows',
      name: 'Shows',
      collectionType: 'tvshows',
      serverId: 'srv',
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Kos TV: the menu of the TV and the computer (docs/diseno-menu, option
/// A): named tabs, the magnifier before them and «Más» after, «Tú» on the
/// avatar.
void main() {
  late UserPreferences prefs;

  setUp(() async {
    prefs = (await setUpBottomNav()).prefs;
    await GetIt.instance.unregister<UserViewsRepository>();
    GetIt.instance.registerSingleton<UserViewsRepository>(_Views());
  });

  tearDown(() async {
    TopToolbar.isFocusedNotifier.value = false;
    await tearDownBottomNav();
  });

  Future<GoRouter> pumpBar(
    WidgetTester tester, {
    InterfaceLayout layout = InterfaceLayout.tv,
    String route = Destinations.home,
  }) async {
    PlatformDetection.setInterfaceLayout(layout);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget page(String location) => Scaffold(
      body: NavigationLayout(
        activeRoute: location,
        child: const Center(
          child: Focus(debugLabel: 'content', child: SizedBox(width: 50, height: 50)),
        ),
      ),
    );
    final router = GoRouter(
      initialLocation: route,
      routes: [
        for (final location in [
          Destinations.home,
          Destinations.search,
          Destinations.kostvMusic,
          Destinations.kostvLibraries,
          Destinations.allGenres,
          Destinations.allFavorites,
        ])
          GoRoute(path: location, builder: (_, _) => page(location)),
        GoRoute(
          path: '/library/:id',
          builder: (_, state) => Text('library ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    return router;
  }

  String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the toolbar registers its focus root only while mounted',
      (tester) async {
    await pumpBar(tester);
    expect(NavigationLayout.chromeFocusRoots, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(NavigationLayout.chromeFocusRoots, isEmpty);
  });

  testWidgets('TV: the magnifier, the named tabs in order and «Más»',
      (tester) async {
    await pumpBar(tester);

    final order = [
      const ValueKey('toolbar_search'),
      const ValueKey('toolbar_home'),
      const ValueKey('toolbar_music'),
      const ValueKey('toolbar_libraries'),
      const ValueKey('toolbar_more'),
    ].map((k) => tester.getCenter(find.byKey(k)).dx).toList();
    for (var i = 1; i < order.length; i++) {
      expect(order[i], greaterThan(order[i - 1]));
    }
    // Named: the tabs say what they are.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Music'), findsWidgets);
    expect(find.text('Libraries'), findsWidgets);
    // Genres, Calendar and Apps are in «Más», not on the bar.
    expect(find.text('Genres'), findsNothing);
    // The avatar is on the left, before the magnifier.
    expect(
      tester.getCenter(find.byType(KostvNavAvatar).first).dx,
      lessThan(order.first),
    );
  });

  testWidgets('the page on screen is marked with the gradient line',
      (tester) async {
    await pumpBar(tester, route: Destinations.kostvMusic);
    Finder markOn(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byKey(const ValueKey('nav_here_mark')),
    );
    expect(markOn('toolbar_music'), findsWidgets);
    expect(markOn('toolbar_home'), findsNothing);
    expect(markOn('toolbar_search'), findsNothing);
  });

  testWidgets('TV focus: the page\'s own tab, along the bar, no way out up '
      'or sideways, and down into the page', (tester) async {
    await pumpBar(tester);
    NavigationLayout.focusNavbar();
    await tester.pump();
    expect(focused(), 'TopToolbarHome');

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'TopToolbarMenu ${Destinations.kostvMusic}');

    // Up goes nowhere: there is nothing above the bar.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'TopToolbarMenu ${Destinations.kostvMusic}');

    // Left along the bar to the magnifier and the avatar, and no further.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'TopToolbarMenu ${Destinations.search}');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'TopToolbarAvatar');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'TopToolbarAvatar');

    // Right to the end, «Más», and no further.
    for (var i = 0; i < 8; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focused(), 'TopToolbarMore');
    expect(TopToolbar.isFocusedNotifier.value, isTrue);

    // Down goes into the page.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(TopToolbar.isFocusedNotifier.value, isFalse);
    expect(focused(), 'content');
  });

  testWidgets('«Más» opens under its button with Genres first, and Back '
      'closes it on the button', (tester) async {
    await pumpBar(tester);
    NavigationLayout.focusNavbar();
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focused(), 'TopToolbarMore');

    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Genres'), findsOneWidget);
    final more = tester.getRect(find.byKey(const ValueKey('toolbar_more')));
    expect(tester.getTopLeft(find.text('Genres')).dy, greaterThan(more.bottom));
    // The first row takes the focus, lit white.
    final row = find.byKey(const ValueKey('kostv-menu-genres'));
    expect(
      Focus.of(tester.element(find.text('Genres'))).hasPrimaryFocus,
      isTrue,
    );
    expect(row, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Genres'), findsNothing);
    expect(focused(), 'TopToolbarMore');
  });

  testWidgets('choosing in «Más» opens the page', (tester) async {
    final router = await pumpBar(tester);
    NavigationLayout.focusNavbar();
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await press(tester, LogicalKeyboardKey.arrowRight);
    }
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      Destinations.allGenres,
    );
  });

  testWidgets('«Tú» is the avatar: the person, favourites, switching person '
      'and Ajustes', (tester) async {
    await pumpBar(tester);
    NavigationLayout.focusNavbarAvatarNotifier.value!();
    await tester.pump();
    expect(focused(), 'TopToolbarAvatar');

    await press(tester, LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Family profile'), findsOneWidget);
    expect(find.text('My favourites'), findsOneWidget);
    expect(find.text('Switch person'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    // No requests tray without the requests service (or in kids mode).
    expect(find.text('My requests'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focused(), 'TopToolbarAvatar');
  });

  testWidgets('a tab per library while they are shown separately', (
    tester,
  ) async {
    await prefs.set(UserPreferences.showLibrariesIndividually, true);
    final router = await pumpBar(tester);
    expect(find.byKey(const ValueKey('toolbar_libraries')), findsNothing);
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Shows'), findsOneWidget);

    // The fake registry knows no games: the route by the library's kind.
    await GetIt.instance.unregister<GameLibraryRegistry>();
    await tester.tap(find.text('Shows'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.last.matchedLocation, '/library/shows');
  });

  testWidgets('kids mode leaves Music out', (tester) async {
    await prefs.set(UserPreferences.kidsModeEnabled, true);
    await pumpBar(tester);
    expect(find.byKey(const ValueKey('toolbar_music')), findsNothing);
    expect(find.byKey(const ValueKey('toolbar_libraries')), findsNothing);
  });

  testWidgets('computer: the logo, the tabs in their glass, a search box and '
      'the avatar on the right, no clock', (tester) async {
    await pumpBar(tester, layout: InterfaceLayout.desktop);
    expect(find.byType(KosLogo), findsOneWidget);
    final search = tester.getRect(find.byKey(const ValueKey('toolbar_search')));
    final home = tester.getRect(find.byKey(const ValueKey('toolbar_home')));
    expect(search.left, greaterThan(home.right));
    expect(
      tester.getCenter(find.byType(KostvNavAvatar).first).dx,
      greaterThan(search.right),
    );
    // The page on screen sits in the pill with the gradient rim.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('toolbar_home')),
        matching: find.byType(KostvActivePill),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d{1,2}:\d{2}').hasMatch(w.data ?? ''),
      ),
      findsNothing,
    );
  });
}
