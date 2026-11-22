import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/bottom_nav/bottom_mini_player.dart';
import 'package:moonfin/ui/widgets/bottom_nav/bottom_nav_metrics.dart';
import 'package:moonfin/ui/widgets/bottom_nav/bottom_navbar.dart';
import 'package:moonfin/ui/widgets/kostv_menu/kostv_glass.dart';
import 'package:moonfin/ui/widgets/top_toolbar.dart';
import 'package:moonfin/util/platform_detection.dart';

import 'bottom_nav_fakes.dart';

/// Kos TV: the menu of phones and tablets (docs/diseno-menu, «cristal
/// líquido»), the only one there is: the floating glass bar with every tab
/// named and Search on a round button of its own.
void main() {
  late FakePlaybackManager playback;

  setUp(() async {
    final setup = await setUpBottomNav();
    playback = setup.playback;
  });

  tearDown(tearDownBottomNav);

  Finder tab(String id) => find.byKey(ValueKey('kostvBarTab-$id'));
  // The bar's own words (the page's header names the page too).
  Finder inBar(String text) =>
      find.descendant(of: find.byType(BottomNavbar), matching: find.text(text));
  final search = find.byKey(const ValueKey('kostvBarSearch'));

  group('heights', () {
    test('the bar, its float above the edge and the mini player', () {
      // 24 px above the edge (the mockup's), or just over the system's
      // own inset where that is taller.
      expect(
        BottomNavMetrics.heightFor(bottomInset: 34, miniPlayer: false),
        62 + 34 + 4,
      );
      expect(
        BottomNavMetrics.heightFor(bottomInset: 0, miniPlayer: false),
        62 + 24,
      );
      expect(
        BottomNavMetrics.heightFor(bottomInset: 0, miniPlayer: true),
        62 + 24 + 54 + 10,
      );
      // A tablet: 26 above the edge, a 56 high player 12 above the bar.
      expect(
        BottomNavMetrics.heightFor(
          bottomInset: 0,
          miniPlayer: true,
          tablet: true,
        ),
        62 + 26 + 56 + 12,
      );
    });

    testWidgets('the content under the bar is told how much it covers', (
      tester,
    ) async {
      usePhoneView(tester);
      double? seen;
      await tester.pumpWidget(
        bottomNavApp(
          child: Builder(
            builder: (context) {
              seen = BottomNavInsetScope.maybeOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pump();
      expect(seen, 62 + 24);
    });
  });

  testWidgets('Inicio, the bar\'s tabs and Tú, named, with Search apart', (
    tester,
  ) async {
    usePhoneView(tester);
    await tester.pumpWidget(bottomNavApp());
    await tester.pump();

    // Without the requests service there is no Discover: Música and the
    // next destination take its place (no library on the fake server, so
    // Genres).
    for (final label in ['Home', 'Music', 'Genres', 'You']) {
      expect(inBar(label), findsOneWidget, reason: label);
    }
    expect(tab('home'), findsOneWidget);
    expect(tab('you'), findsOneWidget);
    // Search is a round button beside the bar, not a tab.
    expect(search, findsOneWidget);
    expect(tab('search'), findsNothing);
    expect(
      tester.getTopLeft(search).dx,
      greaterThan(tester.getTopRight(tab('you')).dx),
    );
    // Favourites is in «Tú», never on the bar.
    expect(find.text('My favourites'), findsNothing);
  });

  testWidgets('the page on screen sits in the pill with the gradient rim', (
    tester,
  ) async {
    usePhoneView(tester);
    await tester.pumpWidget(bottomNavApp());
    await tester.pump();

    expect(
      find.descendant(of: tab('home'), matching: find.byType(KostvActivePill)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tab('you'), matching: find.byType(KostvActivePill)),
      findsNothing,
    );
  });

  testWidgets('the mini player floats above the bar', (tester) async {
    usePhoneView(tester);
    playback.queueService.setQueue([testTrack]);
    await tester.pumpWidget(bottomNavApp());
    await tester.pump();

    final player = find.byType(BottomMiniPlayer);
    expect(player, findsOneWidget);
    expect(find.text('A Song'), findsOneWidget);
    expect(
      tester.getBottomLeft(player).dy,
      lessThan(tester.getTopLeft(tab('home')).dy),
    );
    // The accessory: plain pause and next, no heart nor round play button.
    // Not playing in the fake: the plain «play» in the pause's place.
    expect(
      find.descendant(
        of: player,
        matching: find.byIcon(Icons.play_arrow_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: player,
        matching: find.byIcon(Icons.skip_next_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: player,
        matching: find.byIcon(Icons.favorite_border_rounded),
      ),
      findsNothing,
    );
    expect(
      tester.widget<BottomMiniPlayer>(player).variant,
      BottomMiniPlayerVariant.capsule,
    );
  });

  testWidgets('gathered: the page\'s tab, the music and Search in a row', (
    tester,
  ) async {
    usePhoneView(tester);
    playback.queueService.setQueue([testTrack]);
    final minimized = ValueNotifier<bool>(true);
    addTearDown(minimized.dispose);
    var expanded = 0;
    // The layout owns the flag; this drives a bar of its own with it.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BottomNavbar(
              activeRoute: '/home',
              minimized: minimized,
              onExpand: () => expanded++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('kostvBarGathered')), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    final player = find.byType(BottomMiniPlayer);
    expect(
      tester.widget<BottomMiniPlayer>(player).variant,
      BottomMiniPlayerVariant.inline,
    );
    final circle = find.byKey(const ValueKey('kostvBarGatheredTab'));
    expect(tester.getCenter(circle).dx, lessThan(tester.getCenter(player).dx));

    await tester.tap(circle);
    expect(expanded, 1);
  });

  testWidgets('hidden chrome drops the tabs and keeps the player', (
    tester,
  ) async {
    usePhoneView(tester);
    playback.queueService.setQueue([testTrack]);
    await tester.pumpWidget(bottomNavApp(chrome: false));
    await tester.pumpAndSettle();

    expect(find.byType(BottomMiniPlayer), findsOneWidget);
    final opacity = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('Home'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(opacity.opacity, 0);
  });

  testWidgets('a long press on «Tú» opens «Más»', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(bottomNavApp());
    await tester.pump();

    await tester.longPress(find.text('You'));
    await tester.pumpAndSettle();

    expect(find.text('More'), findsOneWidget);
    expect(find.text('Switch person'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    // The places that aren't on the bar (movil_cristal_hoja); what is each
    // person's (their favourites) is on the «Tú» page.
    expect(find.text('My favourites'), findsNothing);
  });

  testWidgets('a tablet\'s bar is compact and centred, names beside icons', (
    tester,
  ) async {
    usePhoneView(tester, size: const Size(834, 1194));
    playback.queueService.setQueue([testTrack]);
    await tester.pumpWidget(bottomNavApp());
    await tester.pump();

    final bar = tester.getRect(
      find.ancestor(of: tab('home'), matching: find.byType(KostvGlass)).first,
    );
    expect(bar.width, closeTo(BottomNavMetrics.tabletBarWidth, 0.5));
    final searchRect = tester.getRect(search);
    expect(searchRect.left - bar.right, closeTo(BottomNavMetrics.gap, 0.5));
    // Centred: as much room on either side of the bar and Search together.
    expect(bar.left, closeTo(834 - searchRect.right, 0.5));
    // Icon and name side by side.
    final homeLabel = tester.getCenter(inBar('Home'));
    final homeIcon = tester.getCenter(
      find.descendant(of: tab('home'), matching: find.byType(Icon)).first,
    );
    expect(homeLabel.dy, closeTo(homeIcon.dy, 2));
    // The mini player above, as wide as the bar and Search.
    final player = tester.getRect(
      find
          .ancestor(
            of: find.byType(BottomMiniPlayer),
            matching: find.byType(KostvGlass),
          )
          .first,
    );
    expect(player.width, closeTo(searchRect.right - bar.left, 0.5));
  });

  testWidgets('the bar leaves while the keyboard is up', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(bottomNavApp());
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pumpAndSettle();
    final slide = tester.widget<AnimatedSlide>(
      find.ancestor(
        of: find.byType(BottomNavbar),
        matching: find.byType(AnimatedSlide),
      ),
    );
    expect(slide.offset.dy, greaterThan(0));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
  });

  testWidgets('a TV and a computer have the bar of tabs at the top instead', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(bottomNavApp());
    await tester.pump();
    expect(find.byType(BottomNavbar), findsNothing);
    expect(find.byType(TopToolbar), findsOneWidget);
  });

  testWidgets('the page\'s large header: its name, then small as it scrolls', (
    tester,
  ) async {
    usePhoneView(tester);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      bottomNavApp(
        largeHeader: true,
        child: ListView(
          controller: scroll,
          children: [for (var i = 0; i < 40; i++) SizedBox(height: 80)],
        ),
      ),
    );
    await tester.pump();

    final large = find.byKey(const ValueKey('kostvPageHeaderLarge'));
    expect(large, findsOneWidget);
    expect(
      find.descendant(of: large, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('kostvPageHeaderSmall')), findsNothing);

    scroll.jumpTo(300);
    await tester.pump();
    expect(large, findsNothing);
    final small = find.byKey(const ValueKey('kostvPageHeaderSmall'));
    expect(
      find.descendant(of: small, matching: find.text('Home')),
      findsOneWidget,
    );

    // Tapping the page's own tab takes it back to the top.
    await tester.tap(tab('home'));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(large, findsOneWidget);
  });

  testWidgets('a page opened inside one (an album in Música) has no large '
      'header', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(bottomNavApp(activeRoute: '/musica'));
    await tester.pump();
    expect(find.byKey(const ValueKey('kostvPageHeaderLarge')), findsNothing);
  });
}
