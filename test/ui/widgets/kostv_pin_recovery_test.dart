import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/auth/repositories/server_user_repository.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/store/authentication_preferences.dart';
import 'package:moonfin/data/services/kostv_password_check.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/kostv_kids_mode_gate.dart';
import 'package:moonfin/ui/widgets/kostv_pin_recovery_dialog.dart';
import 'package:moonfin/ui/widgets/pin_entry_dialog.dart';
import 'package:moonfin/util/pin_code_util.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSession extends Fake implements SessionRepository {
  @override
  String? get activeUserId => 'kid';

  @override
  String? get activeServerId => 'srv1';
}

class _FakeServers extends Fake implements ServerRepository {
  @override
  Server? getServer(String serverId) => serverId == 'srv1'
      ? Server(
          id: 'srv1',
          name: 'Casa',
          address: 'https://jellyfin.ejemplo.com',
          version: '10.10.0',
          serverType: ServerType.jellyfin,
          dateAdded: DateTime(2026),
        )
      : null;
}

class _FakeUsers extends Fake implements ServerUserRepository {
  @override
  List<PrivateUser> getStoredServerUsers(String serverId) => [
    PrivateUser(
      id: 'kid',
      name: 'Lucía',
      serverId: serverId,
      accessToken: 'token-en-uso',
      lastUsed: DateTime(2026),
    ),
  ];
}

/// Answers what the test says and remembers what it was asked.
class _FakeCheck extends KostvPasswordCheck {
  _FakeCheck()
    : super(
        deviceInfo: const DeviceInfo(
          id: 'tele',
          name: 'Tele',
          appName: 'kOS TV',
          appVersion: '1.0.0',
        ),
        dio: Dio(),
      );

  KostvPasswordVerdict answer = KostvPasswordVerdict.accepted;
  final asked =
      <({String baseUrl, String userId, String username, String password})>[];

  @override
  Future<KostvPasswordVerdict> check({
    required String baseUrl,
    required String userId,
    required String username,
    required String password,
  }) async {
    asked.add((
      baseUrl: baseUrl,
      userId: userId,
      username: username,
      password: password,
    ));
    return answer;
  }
}

/// Kos TV: a PIN kept on the device (Kids Mode, Parental controls) that was
/// forgotten gives way to the Jellyfin password of the account, which the
/// server checks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PreferenceStore store;
  late UserPreferences prefs;
  late _FakeCheck check;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_last_server_id': 'srv1',
      'pref_last_user_id': 'kid',
    });
    store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    check = _FakeCheck();
    GetIt.instance
      ..registerSingleton<PreferenceStore>(store)
      ..registerSingleton<UserPreferences>(prefs)
      ..registerSingleton<AuthenticationPreferences>(
        AuthenticationPreferences(store),
      )
      ..registerSingleton<SessionRepository>(_FakeSession())
      ..registerSingleton<ServerRepository>(_FakeServers())
      ..registerSingleton<ServerUserRepository>(_FakeUsers())
      ..registerSingleton<KostvPasswordCheck>(check);
  });

  tearDown(() async {
    kostvTakeKidsModeExit('');
    await GetIt.instance.reset();
  });

  /// Runs [ask] from a page, opens «¿Olvidaste el PIN?» in the PIN dialog
  /// and returns a reader of what [ask] said.
  Future<bool? Function()> forgot(
    WidgetTester tester,
    Future<bool> Function(BuildContext context) ask,
  ) async {
    bool? result;
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
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
    expect(find.byType(PinEntryDialog), findsOneWidget);
    await tester.tap(find.text('¿Olvidaste el PIN?'));
    await tester.pumpAndSettle();
    expect(find.byType(KostvPinRecoveryDialog), findsOneWidget);
    expect(find.text('Usuario: Lucía'), findsOneWidget);
    return () => result;
  }

  Future<void> submit(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.text('Quitar el PIN'));
    await tester.pumpAndSettle();
  }

  Future<PinCodeUtil> kidsModeOn() async {
    await prefs.set(UserPreferences.kidsModeEnabled, true);
    final pin = PinCodeUtil.kidsMode(store, 'kid');
    await pin.setPin('2222');
    return pin;
  }

  testWidgets('the right password removes the Kids Mode PIN and leaves the '
      'mode', (tester) async {
    final pin = await kidsModeOn();
    final result = await forgot(tester, kostvKidsModeLetsOut);
    await submit(tester, 'secreto');

    expect(check.asked.single.username, 'Lucía');
    expect(check.asked.single.userId, 'kid');
    expect(check.asked.single.password, 'secreto');
    expect(check.asked.single.baseUrl, 'https://jellyfin.ejemplo.com');
    expect(find.byType(KostvPinRecoveryDialog), findsNothing);
    expect(result(), isTrue);
    expect(pin.isPinEnabled, isFalse);
    expect(prefs.get(UserPreferences.kidsModeEnabled), isFalse);
  });

  testWidgets('an account without a password is checked with an empty one', (
    tester,
  ) async {
    final pin = await kidsModeOn();
    final result = await forgot(
      tester,
      (context) => kostvKidsModeLetsPick(context, holder: 'kid'),
    );
    await tester.tap(find.text('Quitar el PIN'));
    await tester.pumpAndSettle();

    expect(check.asked.single.password, '');
    expect(result(), isTrue);
    expect(pin.isPinEnabled, isFalse);
  });

  testWidgets('a wrong password says so, keeps the PIN and counts towards '
      'the wait', (tester) async {
    final pin = await kidsModeOn();
    check.answer = KostvPasswordVerdict.wrong;
    final result = await forgot(tester, kostvKidsModeLetsOut);

    for (var i = 0; i < 5; i++) {
      await submit(tester, 'mal');
      expect(find.text('Contraseña incorrecta'), findsOneWidget);
    }
    expect(find.byType(KostvPinRecoveryDialog), findsOneWidget);
    expect(pin.isPinEnabled, isTrue);
    expect(prefs.get(UserPreferences.kidsModeEnabled), isTrue);

    // The sixth wrong one costs a wait, as a wrong PIN would.
    await submit(tester, 'mal');
    expect(find.textContaining('Demasiados intentos'), findsOneWidget);
    expect(pin.isLockedOut, isTrue);

    // While it lasts, the server isn't even asked.
    check.answer = KostvPasswordVerdict.accepted;
    await submit(tester, 'secreto');
    expect(check.asked, hasLength(6));
    expect(find.textContaining('Demasiados intentos'), findsOneWidget);
    expect(pin.isPinEnabled, isTrue);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result(), isFalse);
    await pin.clearFailedAttempts();
  });

  testWidgets('without the server it says the server is needed', (
    tester,
  ) async {
    final pin = await kidsModeOn();
    check.answer = KostvPasswordVerdict.unreachable;
    await forgot(tester, kostvKidsModeLetsOut);
    await submit(tester, 'secreto');

    expect(
      find.textContaining('hace falta conectar con el servidor'),
      findsOneWidget,
    );
    expect(pin.isPinEnabled, isTrue);
  });

  testWidgets('the right password removes the Parental controls PIN and '
      'lets in', (tester) async {
    final pin = PinCodeUtil.parental(store, 'kid');
    await pin.setPin('1234');
    final result = await forgot(tester, kostvParentalControlsLetIn);
    await submit(tester, 'secreto');

    expect(result(), isTrue);
    expect(pin.isPinEnabled, isFalse);
    // Kids Mode is not this PIN's business.
    expect(prefs.get(UserPreferences.kidsModeEnabled), isFalse);
    expect(PinCodeUtil.kidsMode(store, 'kid').isPinEnabled, isFalse);
  });

  testWidgets('with the account not stored here there is no way out by '
      'password', (tester) async {
    await GetIt.instance.unregister<ServerUserRepository>();
    await kidsModeOn();
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => kostvKidsModeLetsOut(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(PinEntryDialog), findsOneWidget);
    expect(find.text('¿Olvidaste el PIN?'), findsNothing);
  });
}
