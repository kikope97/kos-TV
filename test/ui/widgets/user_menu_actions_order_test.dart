import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/user_menu_dialog.dart';
import 'package:moonfin/util/kostv_server.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Servers extends Mock implements ServerRepository {}

class _Auth extends Mock implements AuthenticationStore {}

class _Session extends Mock implements SessionRepository {}

// Kos TV: the profile menu lists its actions in one order on every device:
// what you do in the app, then the account, and signing out last.
void main() {
  late AppLocalizations l10n;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    final servers = _Servers();
    when(servers.loadStoredServers).thenAnswer((_) async {});
    when(() => servers.servers).thenReturn(const []);
    final session = _Session();
    when(() => session.activeServerId).thenReturn(null);
    when(() => session.activeUserId).thenReturn(null);
    when(() => session.activeSiloSiblingCount).thenReturn(0);
    GetIt.instance
      ..registerSingleton<PreferenceStore>(store)
      ..registerSingleton<UserPreferences>(UserPreferences(store))
      ..registerSingleton<ServerRepository>(servers)
      ..registerSingleton<AuthenticationStore>(_Auth())
      ..registerSingleton<SessionRepository>(session);
    l10n = lookupAppLocalizations(const Locale('es'));
  });

  tearDown(() async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    await GetIt.instance.reset();
  });

  Future<List<String>> shownActions(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
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
              onPressed: () => showUserMenu(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final candidates = [
      l10n.kostvTrayTitle,
      l10n.kostvMyFavorites,
      l10n.settings,
      l10n.quickConnect,
      l10n.remoteControl,
      l10n.addUser,
      l10n.selectServer,
      l10n.signOut,
      l10n.signOutAllUsers,
    ];
    final found = [
      for (final label in candidates)
        if (find.text(label).evaluate().isNotEmpty) label,
    ];
    // Reading order: row by row, then left to right.
    Offset at(String label) => tester.getTopLeft(find.text(label));
    found.sort((a, b) {
      final dy = at(a).dy.compareTo(at(b).dy);
      return dy != 0 ? dy : at(a).dx.compareTo(at(b).dx);
    });
    return found;
  }

  List<String> expected(List<String> app) => [
    ...app,
    l10n.addUser,
    if (!kIsWeb && !hasKostvServer) l10n.selectServer,
    l10n.signOut,
  ];

  // Kos TV: requests, favourites and Ajustes are in «Tú»; switching person
  // keeps only what «Tú» doesn't hold.
  testWidgets('on a desktop the app comes first and signing out last', (
    tester,
  ) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.desktop);
    expect(
      await shownActions(tester),
      expected([l10n.quickConnect, l10n.remoteControl]),
    );
  });

  testWidgets('on a TV only the account', (tester) async {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.tv);
    expect(await shownActions(tester), expected(const []));
  });
}
