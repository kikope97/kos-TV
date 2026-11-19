import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/browse/kostv_mixed_library_route.dart';

/// Kos TV: a library with films and series together opens the kOS TV
/// catalogue unless it also holds loose videos, which only the old page
/// shows.
void main() {
  tearDown(KostvMixedLibraryRoute.forgetAll);

  Widget route(
    Future<bool> Function() hasLooseItems, {
    String libraryId = 'lib',
    bool fallbackToCatalog = false,
  }) => MaterialApp(
    home: KostvMixedLibraryRoute(
      key: ValueKey(libraryId),
      libraryId: libraryId,
      serverId: null,
      fallbackToCatalog: fallbackToCatalog,
      hasLooseItems: hasLooseItems,
      catalog: (_) => const Text('catalogue'),
      oldPage: (_) => const Text('old page'),
    ),
  );

  testWidgets('only films and series: the catalogue', (tester) async {
    await tester.pumpWidget(route(() async => false));
    await tester.pumpAndSettle();
    expect(find.text('catalogue'), findsOneWidget);
  });

  testWidgets('loose videos too: the old page', (tester) async {
    await tester.pumpWidget(route(() async => true));
    await tester.pumpAndSettle();
    expect(find.text('old page'), findsOneWidget);
  });

  testWidgets('nothing shows until the answer comes', (tester) async {
    final answer = Completer<bool>();
    await tester.pumpWidget(route(() => answer.future));
    expect(find.text('catalogue'), findsNothing);
    expect(find.text('old page'), findsNothing);
    answer.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('catalogue'), findsOneWidget);
  });

  testWidgets('the answer is asked once per library', (tester) async {
    var asked = 0;
    Future<bool> ask() async {
      asked++;
      return false;
    }

    await tester.pumpWidget(route(ask));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(route(ask));
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(find.text('catalogue'), findsOneWidget);
  });

  testWidgets('a failed question opens the page the library used to open', (
    tester,
  ) async {
    await tester.pumpWidget(route(() async => throw Exception('offline')));
    await tester.pumpAndSettle();
    expect(find.text('old page'), findsOneWidget);

    KostvMixedLibraryRoute.forgetAll();
    await tester.pumpWidget(
      route(
        () async => throw Exception('offline'),
        libraryId: 'other',
        fallbackToCatalog: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('catalogue'), findsOneWidget);
  });
}
