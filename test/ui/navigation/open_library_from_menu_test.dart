import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/navigation/menu_preview.dart';

/// Kos TV: a library's own menu button ("Show libraries separately") goes
/// as the menu's pages do, so Back from a library goes to Home.
void main() {
  late GoRouter router;

  setUp(() {
    router = GoRouter(
      initialLocation: Destinations.home,
      routes: [
        GoRoute(path: Destinations.home, builder: (_, _) => const Text('home')),
        GoRoute(
          path: Destinations.kostvDiscover,
          builder: (_, _) => const Text('discover'),
        ),
        GoRoute(
          path: Destinations.libraryBrowse,
          builder: (_, state) =>
              Text('library ${state.pathParameters['libraryId']}'),
        ),
        GoRoute(
          path: Destinations.itemDetail,
          builder: (_, _) => const Text('item'),
        ),
      ],
    );
  });

  tearDown(() => router.dispose());

  Future<BuildContext> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return tester.element(find.text('home'));
  }

  int depth() => router.routerDelegate.currentConfiguration.matches.length;

  testWidgets('one library takes the place of another', (tester) async {
    final context = await pumpApp(tester);
    context.openLibraryFromMenu('/library/films');
    await tester.pumpAndSettle();
    context.openLibraryFromMenu('/library/series');
    await tester.pumpAndSettle();
    context.openLibraryFromMenu('/library/docs');
    await tester.pumpAndSettle();

    expect(MenuPreview.shownPath(router), '/library/docs');
    expect(depth(), 2);
    router.pop();
    await tester.pumpAndSettle();
    expect(MenuPreview.shownPath(router), Destinations.home);
  });

  testWidgets('a library takes the place of a menu page', (tester) async {
    final context = await pumpApp(tester);
    router.push(Destinations.kostvDiscover);
    await tester.pumpAndSettle();
    context.openLibraryFromMenu('/library/films');
    await tester.pumpAndSettle();
    expect(depth(), 2);
  });

  testWidgets('over anything else it goes on top, as before', (tester) async {
    final context = await pumpApp(tester);
    router.push('/item/abc');
    await tester.pumpAndSettle();
    context.openLibraryFromMenu('/library/films');
    await tester.pumpAndSettle();
    expect(depth(), 3);
  });
}
