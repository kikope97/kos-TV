import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';

import '../../screens/discover/fake_stremfin_life.dart';
import 'bottom_nav_fakes.dart';

/// Kos TV: the requests tray in the bottom navbar hub, with its news on the
/// row and on the avatar.
void main() {
  setUp(setUpBottomNav);
  tearDown(tearDownBottomNav);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the hub lists the requests tray with its news', (tester) async {
    final fake = FakeStremfinLife(mode: 'review');
    fake.answer('POST', '/requests', {'type': 'movie', 'tmdb_id': 920});
    final service = fake.service();
    GetIt.instance.registerSingleton<StremfinService>(service);
    service.onUserChanged('kiko');

    usePhoneView(tester);
    await tester.pumpWidget(bottomNavApp());
    await settle(tester);
    // Accepted by the administrator after the app opened: news.
    fake.approve(fake.requests.keys.single);
    service.inbox.sync();
    await settle(tester);

    await tester.tap(find.text('You'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    expect(find.text('Requests'), findsOneWidget);
    // Once on the avatar and once on the row.
    expect(find.text('1'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    service.dispose();
  });

  testWidgets('no requests row without the requests service', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(bottomNavApp());
    await tester.pump();
    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    expect(find.text('Requests'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });
}
