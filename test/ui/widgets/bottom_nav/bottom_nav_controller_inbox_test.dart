import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/ui/navigation/kostv_menu_controller.dart';

import '../../screens/discover/fake_stremfin_life.dart';
import 'bottom_nav_fakes.dart';

/// Kos TV: the requests tray notifies every few seconds while something
/// downloads; the menu only shows its news and whether something is on its
/// way, so only those reach it.
void main() {
  setUp(setUpBottomNav);
  tearDown(tearDownBottomNav);

  testWidgets('the bar ignores the tray unless its news change', (
    tester,
  ) async {
    final fake = FakeStremfinLife(mode: 'review');
    fake.answer('POST', '/requests', {'type': 'movie', 'tmdb_id': 920});
    final service = fake.service();
    GetIt.instance.registerSingleton<StremfinService>(service);
    service.onUserChanged('kiko');
    await tester.pump(const Duration(milliseconds: 300));

    final controller = KostvMenuController();
    await tester.pump(const Duration(milliseconds: 300));
    var rebuilds = 0;
    controller.addListener(() => rebuilds++);

    // A download's progress: the tray changes, its news don't.
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    service.inbox.notifyListeners();
    expect(rebuilds, 0);

    // Accepted by the administrator: news.
    fake.approve(fake.requests.keys.single);
    await tester.runAsync(() => service.inbox.sync());
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.inbox.newsCount, 1);
    expect(rebuilds, greaterThan(0));

    controller.dispose();
    service.dispose();
  });
}
