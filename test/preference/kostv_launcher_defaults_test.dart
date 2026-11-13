import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: a new install starts with all of Launcher mode off (the opening
/// animation and the apps), since kOS TV is the TV's start screen only on
/// some TVs.
void main() {
  test('Launcher mode: the animation and the apps off', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    final prefs = UserPreferences(store);

    expect(prefs.get(UserPreferences.kostvIntroEnabled), isFalse);
    expect(prefs.get(UserPreferences.showAppsRow), isFalse);
    expect(prefs.get(UserPreferences.showAppsButton), isFalse);
  });

  test('a TV where someone already chose keeps the choice', () async {
    SharedPreferences.setMockInitialValues({
      'kostv_show_apps_row': true,
      'kostv_show_apps_button': true,
    });
    final store = PreferenceStore();
    await store.init();
    final prefs = UserPreferences(store);

    expect(prefs.get(UserPreferences.showAppsRow), isTrue);
    expect(prefs.get(UserPreferences.showAppsButton), isTrue);
  });
}
