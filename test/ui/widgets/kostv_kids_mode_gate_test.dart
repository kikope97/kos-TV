import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/store/authentication_preferences.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/kostv_kids_mode_gate.dart';
import 'package:moonfin/ui/widgets/pin_entry_dialog.dart';
import 'package:moonfin/util/pin_code_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the user picker can't be the way out of Kids Mode (from the
/// "time's up" screen, a web address, a start with automatic sign-in off),
/// while the child can still go back to their own profile.
const _keys = {'1': LogicalKeyboardKey.digit1, '2': LogicalKeyboardKey.digit2};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferenceStore store;
  late UserPreferences prefs;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_last_server_id': 'srv1',
      'pref_last_user_id': 'kid',
    });
    store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance
      ..registerSingleton<PreferenceStore>(store)
      ..registerSingleton<UserPreferences>(prefs)
      ..registerSingleton<AuthenticationPreferences>(
        AuthenticationPreferences(store),
      );
  });

  tearDown(() async {
    // A grant left by one test must not reach the next.
    kostvTakeKidsModeExit('');
    await GetIt.instance.reset();
  });

  Future<void> kidsModeOn() async {
    await prefs.set(UserPreferences.kidsModeEnabled, true);
    await PinCodeUtil.kidsMode(store, '').setPin('2222');
    await PinCodeUtil.kidsMode(store, 'kid').setPin('2222');
  }

  /// Runs [ask] from a page and returns what it said, typing [typed] into a
  /// PIN dialog if one comes up.
  Future<bool?> run(
    WidgetTester tester,
    Future<bool> Function(BuildContext context) ask, {
    String? typed,
  }) async {
    bool? result;
    // The error line takes room the default test screen does not have.
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await ask(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    if (typed != null) {
      expect(find.byType(PinEntryDialog), findsOneWidget);
      for (final digit in typed.split('')) {
        await tester.sendKeyEvent(_keys[digit]!);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }
    return result;
  }

  group('the profile in Kids Mode', () {
    test('is nobody with the mode off', () {
      expect(kostvKidsModeHolder(), isNull);
    });

    test('is the last one signed in here, with the mode on', () async {
      await kidsModeOn();
      expect(kostvKidsModeHolder(), 'kid');
    });
  });

  group('picking in the user picker', () {
    testWidgets('lets anyone through with the mode off', (tester) async {
      final result = await run(
        tester,
        (context) => kostvKidsModeLetsPick(
          context,
          holder: kostvKidsModeHolder(),
          pickedUserId: 'parent',
        ),
      );
      expect(result, isTrue);
      expect(find.byType(PinEntryDialog), findsNothing);
    });

    testWidgets('lets the child back into their own profile', (tester) async {
      await kidsModeOn();
      final result = await run(
        tester,
        (context) => kostvKidsModeLetsPick(
          context,
          holder: kostvKidsModeHolder(),
          pickedUserId: 'kid',
        ),
      );
      expect(result, isTrue);
      expect(find.byType(PinEntryDialog), findsNothing);
    });

    testWidgets('asks for the PIN before anyone else', (tester) async {
      await kidsModeOn();
      final result = await run(
        tester,
        (context) => kostvKidsModeLetsPick(
          context,
          holder: kostvKidsModeHolder(),
          pickedUserId: 'parent',
        ),
        typed: '2222',
      );
      expect(result, isTrue);
    });

    testWidgets('keeps a wrong PIN out', (tester) async {
      await kidsModeOn();
      await run(
        tester,
        (context) => kostvKidsModeLetsPick(
          context,
          holder: kostvKidsModeHolder(),
          pickedUserId: 'parent',
        ),
        typed: '1111',
      );
      // Still asking.
      expect(find.byType(PinEntryDialog), findsOneWidget);
    });

    testWidgets('asks for it before a sign-in of someone\'s choosing', (
      tester,
    ) async {
      await kidsModeOn();
      await run(
        tester,
        (context) =>
            kostvKidsModeLetsPick(context, holder: kostvKidsModeHolder()),
      );
      expect(find.byType(PinEntryDialog), findsOneWidget);
    });
  });

  group('leaving with the PIN', () {
    testWidgets('lets the picker opened next through once', (tester) async {
      await kidsModeOn();
      final result = await run(tester, kostvKidsModeLetsOut, typed: '2222');
      expect(result, isTrue);
      expect(kostvTakeKidsModeExit(''), isTrue);
      expect(kostvTakeKidsModeExit(''), isFalse);
    });

    testWidgets('forgets the wrong guesses before it', (tester) async {
      await kidsModeOn();
      final pin = PinCodeUtil.kidsMode(store, '');
      for (var i = 0; i < 5; i++) {
        await pin.registerFailedAttempt();
      }
      await run(tester, kostvKidsModeLetsOut, typed: '2222');

      // Five more slips by the parent cost no wait: the child's tries are gone.
      for (var i = 0; i < 5; i++) {
        expect(await pin.registerFailedAttempt(), Duration.zero);
      }
    });
  });
}
