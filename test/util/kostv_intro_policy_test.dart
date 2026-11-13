import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/kostv_intro_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the intro video plays when the app is opened after being closed,
/// not when it comes back from the background.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final morning = DateTime(2026, 11, 11, 9);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    KostvIntroPolicy.resetForTesting();
  });

  tearDown(KostvIntroPolicy.resetForTesting);

  Future<bool> launchAt(DateTime at) async {
    KostvIntroPolicy.resetForTesting();
    await KostvIntroPolicy.init(now: at);
    return KostvIntroPolicy.takeIntro();
  }

  test('the very first opening plays it', () async {
    expect(await launchAt(morning), isTrue);
  });

  test('back from the background, even started afresh, it does not', () async {
    await launchAt(morning);
    // The TV closed it to make room for another app; it is opened again
    // an hour later.
    expect(await launchAt(morning.add(const Duration(hours: 1))), isFalse);
  });

  test('after closing it on purpose it plays again', () async {
    await launchAt(morning);
    await KostvIntroPolicy.markClosed();
    expect(await launchAt(morning.add(const Duration(minutes: 5))), isTrue);
    // Only that once: the next return from the background goes without.
    expect(await launchAt(morning.add(const Duration(minutes: 20))), isFalse);
  });

  test('after a long time away it plays again', () async {
    await launchAt(morning);
    final nextDay = morning.add(
      KostvIntroPolicy.longAway + const Duration(minutes: 1),
    );
    expect(await launchAt(nextDay), isTrue);
  });

  test('once a launch: switching user goes without it', () async {
    await KostvIntroPolicy.init(now: morning);
    expect(KostvIntroPolicy.takeIntro(), isTrue);
    expect(KostvIntroPolicy.takeIntro(), isFalse);
  });

  test('a clock set back counts as a new opening', () {
    expect(
      KostvIntroPolicy.decide(
        closed: false,
        lastSeen: morning,
        now: morning.subtract(const Duration(days: 1)),
      ),
      isTrue,
    );
  });

  group('the animation switch', () {
    Future<UserPreferences> register() async {
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      GetIt.instance.registerSingleton<UserPreferences>(prefs);
      return prefs;
    }

    tearDown(() => GetIt.instance.reset());

    test('a new install starts with it off', () async {
      final prefs = await register();
      await launchAt(morning);
      expect(prefs.get(UserPreferences.kostvIntroEnabled), isFalse);
    });

    test('an install from before keeps it on', () async {
      SharedPreferences.setMockInitialValues({
        'kostv_intro_last_seen_ms': morning.millisecondsSinceEpoch,
      });
      final prefs = await register();
      await launchAt(morning.add(const Duration(hours: 1)));
      expect(prefs.get(UserPreferences.kostvIntroEnabled), isTrue);
    });

    test('one that turned it off keeps it off', () async {
      SharedPreferences.setMockInitialValues({
        'kostv_intro_last_seen_ms': morning.millisecondsSinceEpoch,
        'kostv_intro_enabled': false,
      });
      final prefs = await register();
      await launchAt(morning.add(const Duration(hours: 1)));
      expect(prefs.get(UserPreferences.kostvIntroEnabled), isFalse);
    });
  });
}
