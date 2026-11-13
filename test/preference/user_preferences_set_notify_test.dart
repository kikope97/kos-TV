import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UserPreferences> _prefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setting the value already stored does not notify', () async {
    final prefs = await _prefs({
      UserPreferences.screensaverEnabled.key: true,
      UserPreferences.screensaverTimeout.key: ScreensaverTimeout.m10.name,
      UserPreferences.downloadKeptIds.key: <String>['a', 'b'],
    });
    var notified = 0;
    prefs.addListener(() => notified++);

    await prefs.set(UserPreferences.screensaverEnabled, true);
    await prefs.set(UserPreferences.screensaverTimeout, ScreensaverTimeout.m10);
    await prefs.set(UserPreferences.downloadKeptIds, <String>['a', 'b']);

    expect(notified, 0);
  });

  test('a changed value still notifies', () async {
    final prefs = await _prefs({
      UserPreferences.screensaverEnabled.key: true,
      UserPreferences.downloadKeptIds.key: <String>['a', 'b'],
    });
    var notified = 0;
    prefs.addListener(() => notified++);

    await prefs.set(UserPreferences.screensaverEnabled, false);
    await prefs.set(UserPreferences.downloadKeptIds, <String>['b', 'a']);

    expect(notified, 2);
    expect(prefs.get(UserPreferences.screensaverEnabled), isFalse);
    expect(prefs.get(UserPreferences.downloadKeptIds), ['b', 'a']);
  });

  test('a missing key is written and notifies even with the default', () async {
    final prefs = await _prefs();
    var notified = 0;
    prefs.addListener(() => notified++);
    final pref = UserPreferences.screensaverEnabled;

    await prefs.set(pref, pref.defaultValue);

    expect(notified, 1);
    expect(prefs.containsPreferenceKey(pref.key), isTrue);
  });
}
