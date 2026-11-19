import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/navigation/kids_mode_page_guard.dart';
import 'package:moonfin/ui/navigation/menu_preview.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: turning Kids Mode on over a page it blocks, and menu pages the
/// router would send to Home.
void main() {
  late UserPreferences prefs;
  late GoRouter router;
  late ValueNotifier<bool> settingsOpen;
  late KidsModePageGuard guard;

  Widget page(String name) => Scaffold(body: Text(name));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
    router = GoRouter(
      initialLocation: Destinations.home,
      routes: [
        for (final path in [
          Destinations.home,
          Destinations.kostvDiscover,
          Destinations.myList,
          Destinations.liveTvGuide,
          Destinations.calendar,
        ])
          GoRoute(path: path, builder: (_, _) => page(path)),
      ],
    );
    settingsOpen = ValueNotifier(false);
    guard = KidsModePageGuard(
      prefs: prefs,
      router: router,
      settingsOpen: settingsOpen,
    );
  });

  tearDown(() async {
    guard.dispose();
    router.dispose();
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    await GetIt.instance.reset();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  String shown() => MenuPreview.shownPath(router);

  testWidgets('a blocked page pushed over Home goes as the mode goes on', (
    tester,
  ) async {
    await pumpApp(tester);
    // As on a TV: the page goes over Home and the address stays on /home.
    router.push(Destinations.kostvDiscover);
    await tester.pumpAndSettle();
    expect(shown(), Destinations.kostvDiscover);

    await prefs.set(UserPreferences.kidsModeEnabled, true);
    await tester.pumpAndSettle();
    expect(shown(), Destinations.home);
    expect(router.canPop(), isFalse);
  });

  testWidgets('waits for Settings to close', (tester) async {
    await pumpApp(tester);
    router.push(Destinations.liveTvGuide);
    await tester.pumpAndSettle();

    settingsOpen.value = true;
    await prefs.set(UserPreferences.kidsModeEnabled, true);
    await tester.pumpAndSettle();
    expect(shown(), Destinations.liveTvGuide);

    settingsOpen.value = false;
    await tester.pumpAndSettle();
    expect(shown(), Destinations.home);
  });

  testWidgets('leaves a page the mode allows alone', (tester) async {
    await pumpApp(tester);
    router.push(Destinations.myList);
    await tester.pumpAndSettle();

    await prefs.set(UserPreferences.kidsModeEnabled, true);
    await tester.pumpAndSettle();
    expect(shown(), Destinations.myList);
  });

  testWidgets('the menu opens nothing the router would turn into Home', (
    tester,
  ) async {
    await pumpApp(tester);
    await prefs.set(UserPreferences.kidsModeEnabled, true);
    final context = tester.element(find.text(Destinations.home));

    expect(MenuPreview.open(context, Destinations.calendar), isFalse);
    await tester.pumpAndSettle();
    // No second Home stacked over the first.
    expect(router.canPop(), isFalse);
    expect(shown(), Destinations.home);
  });

  testWidgets('a page no menu takes in is not waited for for ever', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    await pumpApp(tester);
    final context = tester.element(find.text(Destinations.home));

    MenuPreview.show(context, Destinations.myList);
    expect(MenuPreview.arriving.value, Destinations.myList);
    await tester.pumpAndSettle();
    // Nothing here takes the focus for it, as with a page sent elsewhere.
    await tester.pump(MenuPreview.arrivalTimeout);
    expect(MenuPreview.arriving.value, isNull);
    MenuPreview.stopHolding();
  });
}
