import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/settings/preference_binding.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: a settings tile follows the stored value, so a change from the
/// server's sync shows on a screen that is already open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferenceStore store;
  late UserPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
  });

  tearDown(() => GetIt.instance.reset());

  test('a change made elsewhere shows in the tile', () async {
    final binding = PreferenceBinding(store, UserPreferences.use24HourClock);
    final start = binding.value;

    await prefs.set(UserPreferences.use24HourClock, !start);
    expect(binding.value, !start);
    binding.dispose();
  });

  test('the tile still writes what it is given', () async {
    final binding = PreferenceBinding(store, UserPreferences.use24HourClock);
    final start = binding.value;

    binding.value = !start;
    await Future<void>.delayed(Duration.zero);
    expect(prefs.get(UserPreferences.use24HourClock), !start);
    binding.dispose();
  });

  test('once gone it listens no more', () async {
    final binding = PreferenceBinding(store, UserPreferences.use24HourClock);
    binding.dispose();
    await prefs.set(
      UserPreferences.use24HourClock,
      !prefs.get(UserPreferences.use24HourClock),
    );
  });
}
