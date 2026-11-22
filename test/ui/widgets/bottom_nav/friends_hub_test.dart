import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/services/achievements_service.dart';
import 'package:moonfin/preference/user_preferences.dart';

import 'bottom_nav_fakes.dart';

class _FakeAchievements extends ChangeNotifier implements AchievementsService {
  _FakeAchievements({required this.socialAvailable});

  @override
  final bool socialAvailable;

  @override
  int get socialBadgeCount => 2;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(setUpBottomNav);
  tearDown(tearDownBottomNav);

  /// Kos TV: «Más», a long press on «Tú».
  Future<void> openHub(WidgetTester tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(bottomNavApp());
    await tester.pump();
    await tester.longPress(find.text('You'));
    await tester.pumpAndSettle();
  }

  testWidgets('«Más» lists Friends with what is waiting', (tester) async {
    await GetIt.instance<UserPreferences>().set(
      UserPreferences.showFriendsButton,
      true,
    );
    GetIt.instance.registerSingleton<AchievementsService>(
      _FakeAchievements(socialAvailable: true),
    );
    await openHub(tester);

    expect(find.text('Friends'), findsOneWidget);
    // On its tile (the avatar on the bar has a dot for «Tú»'s own news).
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('Friends stays out of «Más» until it\'s turned on', (
    tester,
  ) async {
    GetIt.instance.registerSingleton<AchievementsService>(
      _FakeAchievements(socialAvailable: true),
    );
    await openHub(tester);

    expect(find.text('Friends'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('no Friends without the plugin', (tester) async {
    await GetIt.instance<UserPreferences>().set(
      UserPreferences.showFriendsButton,
      true,
    );
    GetIt.instance.registerSingleton<AchievementsService>(
      _FakeAchievements(socialAvailable: false),
    );
    await openHub(tester);

    expect(find.text('Friends'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });
}
