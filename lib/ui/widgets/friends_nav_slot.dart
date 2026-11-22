import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import '../../data/services/achievements_service.dart';
import '../../preference/user_preferences.dart';
import '../screens/settings/achievements_screen.dart';
import 'settings/settings_panel.dart';

/// Friends in the menu (Kos TV: in «Más»): whether the person left the
/// button on, whether the server has friends, and opening the list.
abstract final class FriendsNavSlot {
  static bool isOffered() =>
      GetIt.instance<UserPreferences>().get(UserPreferences.showFriendsButton);

  /// Whether the button has something to open right now.
  static bool isAvailable() =>
      GetIt.instance.isRegistered<AchievementsService>() &&
      GetIt.instance<AchievementsService>().socialAvailable;

  /// Opens the friends list in the side panel the settings use.
  static Future<void> open(BuildContext context) =>
      SettingsPanel.open(context, const FriendsScreen());
}
