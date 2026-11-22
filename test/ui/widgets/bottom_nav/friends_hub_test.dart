import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/services/achievements_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/you/kostv_you_screen.dart';

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

  /// Kos TV: the «Tú» page, where the rest of what is each person's is
  /// (the «Más» sheet keeps to the places, movil_cristal_hoja).
  Future<void> openHub(WidgetTester tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const KostvYouScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('«Tú» lists Friends with what is waiting', (tester) async {
    await GetIt.instance<UserPreferences>().set(
      UserPreferences.showFriendsButton,
      true,
    );
    GetIt.instance.registerSingleton<AchievementsService>(
      _FakeAchievements(socialAvailable: true),
    );
    await openHub(tester);

    expect(find.text('Friends'), findsOneWidget);
    // On its row (the avatar on the bar has a dot for «Tú»'s own news).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('kostvYou-friends')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Friends stays out of «Más» until it\'s turned on', (
    tester,
  ) async {
    GetIt.instance.registerSingleton<AchievementsService>(
      _FakeAchievements(socialAvailable: true),
    );
    await openHub(tester);

    expect(find.text('Friends'), findsNothing);
    expect(find.text('My favourites'), findsOneWidget);
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
    expect(find.text('My favourites'), findsOneWidget);
  });
}
