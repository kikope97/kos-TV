import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/settings/parental_settings_screen.dart';
import 'package:moonfin/ui/widgets/kostv_kids_mode_gate.dart';
import 'package:moonfin/ui/widgets/pin_entry_dialog.dart';
import 'package:moonfin/util/pin_code_util.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSession extends Fake implements SessionRepository {
  _FakeSession(this.activeUserId);

  @override
  final String? activeUserId;
}

class _Client extends Mock implements MediaServerClient {}

class _Items extends Mock implements ItemsApi {}

const _digits = {
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '9': LogicalKeyboardKey.digit9,
};

Future<void> _type(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.sendKeyEvent(_digits[digit]!);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Kos TV: Parental controls can have a PIN of their own, apart from the
/// profile's sign in PIN, which whoever uses the profile knows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferenceStore store;
  late UserPreferences prefs;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance
      ..registerSingleton<PreferenceStore>(store)
      ..registerSingleton<UserPreferences>(prefs)
      ..registerSingleton<SessionRepository>(_FakeSession('parent'));
  });

  tearDown(() => GetIt.instance.reset());

  group('the PIN', () {
    test('is kept apart from the sign in and Kids Mode PINs', () async {
      await PinCodeUtil.parental(store, 'parent').setPin('1234');
      expect(PinCodeUtil.parental(store, 'parent').isPinEnabled, isTrue);
      expect(PinCodeUtil(store, 'parent').isPinEnabled, isFalse);
      expect(PinCodeUtil.kidsMode(store, 'parent').isPinEnabled, isFalse);
      expect(PinCodeUtil.parental(store, 'child').isPinEnabled, isFalse);
    });

    test('is kept hashed, with the same wait after wrong guesses', () async {
      final pin = PinCodeUtil.parental(store, 'parent');
      await pin.setPin('1234');
      expect(store.getString('parental_pin_hash_parent'), isNot('1234'));
      expect(
        store.getString('parental_pin_hash_parent'),
        PinCodeUtil.hashPin('1234'),
      );
      for (var i = 0; i < 6; i++) {
        await pin.registerFailedAttempt();
      }
      expect(pin.isLockedOut, isTrue);
      expect(pin.verifyPin('1234'), isFalse);
      await pin.clearFailedAttempts();
    });

    test('is the signed in person\'s', () async {
      expect(kostvParentalPin(), isNotNull);
      GetIt.instance.unregister<SessionRepository>();
      GetIt.instance.registerSingleton<SessionRepository>(_FakeSession(null));
      expect(kostvParentalPin(), isNull);
    });
  });

  group('opening Parental controls', () {
    Future<bool?> run(WidgetTester tester, {String? typed}) async {
      bool? result;
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
                onPressed: () async =>
                    result = await kostvParentalControlsLetIn(context),
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
        await _type(tester, typed);
      }
      return result;
    }

    testWidgets('without its own PIN, behaves as before', (tester) async {
      // No profile PIN to fall back on either, so it lets through.
      final result = await run(tester);
      expect(result, isTrue);
      expect(find.byType(PinEntryDialog), findsNothing);
    });

    testWidgets('with its own PIN, asks for it', (tester) async {
      await PinCodeUtil.parental(store, 'parent').setPin('1234');
      expect(await run(tester, typed: '1234'), isTrue);
    });

    testWidgets('keeps a wrong PIN out', (tester) async {
      await PinCodeUtil.parental(store, 'parent').setPin('1234');
      await run(tester, typed: '9999');
      expect(find.byType(PinEntryDialog), findsOneWidget);
    });

    testWidgets('doesn\'t take the profile\'s PIN instead', (tester) async {
      await PinCodeUtil(store, 'parent').setPin('9999');
      await PinCodeUtil.parental(store, 'parent').setPin('1234');
      await run(tester, typed: '9999');
      expect(find.byType(PinEntryDialog), findsOneWidget);
    });
  });

  group('the screen', () {
    setUp(() {
      final items = _Items();
      final client = _Client();
      when(() => client.itemsApi).thenReturn(items);
      when(
        () => items.getQueryFilters(
          includeItemTypes: any(named: 'includeItemTypes'),
        ),
      ).thenAnswer(
        (_) async => const QueryFilterValues(officialRatings: ['ES-18']),
      );
      GetIt.instance.registerSingleton<MediaServerClient>(client);
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ParentalSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sets, changes and removes its own PIN', (tester) async {
      final pin = PinCodeUtil.parental(store, 'parent');
      await pump(tester);
      expect(find.text('PIN del control parental'), findsOneWidget);

      await tester.tap(find.text('Poner un PIN propio'));
      await tester.pumpAndSettle();
      await _type(tester, '1234');
      await _type(tester, '1234');
      expect(pin.verifyPin('1234'), isTrue);
      expect(find.text('Cambiar PIN'), findsOneWidget);
      expect(find.text('Poner un PIN propio'), findsNothing);

      // Changing it asks for the current one first.
      await tester.tap(find.text('Cambiar PIN'));
      await tester.pumpAndSettle();
      await _type(tester, '1234');
      await _type(tester, '4321');
      await _type(tester, '4321');
      expect(pin.verifyPin('4321'), isTrue);

      // A wrong current PIN removes nothing.
      await tester.tap(find.text('Eliminar PIN'));
      await tester.pumpAndSettle();
      await _type(tester, '9999');
      expect(find.byType(PinEntryDialog), findsOneWidget);
      expect(pin.isPinEnabled, isTrue);
      await _type(tester, '4321');
      expect(pin.isPinEnabled, isFalse);
      expect(find.text('Poner un PIN propio'), findsOneWidget);
    });
  });

  group('book Discover', () {
    test('is left out in Kids Mode, whatever the setting says', () async {
      expect(prefs.effectiveShowBookDiscoverTab, isTrue);
      await prefs.set(UserPreferences.kidsModeEnabled, true);
      expect(prefs.effectiveShowBookDiscoverTab, isFalse);
      await prefs.set(UserPreferences.kidsModeEnabled, false);
      await prefs.set(UserPreferences.showBookDiscoverTab, false);
      expect(prefs.effectiveShowBookDiscoverTab, isFalse);
    });
  });
}
