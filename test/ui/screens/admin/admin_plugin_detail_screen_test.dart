import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/admin_nav.dart';
import 'package:moonfin/ui/screens/admin/plugins/admin_plugin_detail_screen.dart';
import 'package:moonfin/ui/screens/admin/providers/admin_user_providers.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Serves GET /web/ConfigurationPages and GET /Packages like Jellyfin 12.2.
class _FakePluginsApi extends Fake implements AdminPluginsApi {
  List<Map<String, dynamic>> pages = [
    {
      'Name': 'TMDb',
      'EnableInMainMenu': false,
      'DisplayName': 'TMDb',
      'PluginId': 'b8715ed16c4745289ad3f72deb539cd4',
    },
  ];
  List<PackageInfo> packages = const [];
  int pageLookups = 0;
  final installs = <String?>[];
  final disabled = <String>[];
  final uninstalled = <String>[];

  @override
  Future<void> disablePlugin(String pluginId, String version) async =>
      disabled.add(pluginId);

  @override
  Future<void> uninstallPlugin(String pluginId, String version) async =>
      uninstalled.add(pluginId);

  @override
  Future<List<Map<String, dynamic>>> getConfigurationPages() async {
    pageLookups++;
    return pages;
  }

  @override
  Future<List<PackageInfo>> getAvailablePackages() async => packages;

  @override
  Future<void> installPackage(
    String name, {
    String? assemblyGuid,
    String? version,
    String? repositoryUrl,
    String? updateClass,
  }) async {
    installs.add(version);
  }
}

const _tmdb = PluginInfo(
  name: 'TMDb',
  id: 'b8715ed16c4745289ad3f72deb539cd4',
  version: '12.2.0.0',
);

const _moonbase = PluginInfo(
  name: 'Moonbase',
  id: 'moonbase',
  version: '2.4.0.0',
  canUninstall: true,
);

/// With no CanUninstall or Status.
const _embyBackup = PluginInfo(
  name: 'Backup & Restore',
  id: 'e711475e-efad-431b-8527-033ba9873a34',
  version: '1.8.7.0',
  hasImage: true,
  imageTag: '1',
);

/// The kOS TV server plugin, as Jellyfin sends its id (no dashes).
const _kosTv = PluginInfo(
  name: 'kOS TV',
  id: '561f86dffa004fcaaa4d2fed0e332670',
  version: '3.1.0.2',
  canUninstall: true,
);

void main() {
  late _FakePluginsApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakePluginsApi();
    final client = _MockMediaServerClient();
    when(() => client.adminPluginsApi).thenReturn(api);
    when(() => client.baseUrl).thenReturn('http://jf.test');
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pump(
    WidgetTester tester,
    String pluginId, {
    ServerType server = ServerType.jellyfin,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminInstalledPluginsProvider.overrideWith(
            (ref) async => const [_tmdb, _moonbase, _embyBackup, _kosTv],
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdminServerScope(
            serverType: server,
            child: Scaffold(body: AdminPluginDetailScreen(pluginId: pluginId)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a bundled plugin keeps its Settings entry', (tester) async {
    await pump(tester, _tmdb.id);

    expect(api.pageLookups, 1);
    expect(find.text(l10n.settings), findsOneWidget);
    expect(find.text(l10n.adminPluginDetailEnablePlugin), findsNothing);
    expect(find.text(l10n.uninstall), findsNothing);
  });

  testWidgets('no configuration page means no Settings entry', (tester) async {
    await pump(tester, _moonbase.id);

    expect(find.text(l10n.adminPluginDetailEnablePlugin), findsOneWidget);
    expect(find.text(l10n.settings), findsNothing);
  });

  testWidgets('an update from an outside repository asks first', (
    tester,
  ) async {
    api.packages = const [
      PackageInfo(
        name: 'Moonbase',
        id: 'moonbase',
        versions: [
          VersionInfo(
            version: '2.5.0.0',
            repositoryUrl: 'https://example.com/manifest.json',
          ),
        ],
      ),
    ];
    await pump(tester, _moonbase.id);

    await tester.tap(
      find.text(l10n.adminPluginsInstallUpdateVersioned('2.5.0.0')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminPluginInstallConfirmTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.install));
    await tester.pumpAndSettle();
    expect(api.installs, ['2.5.0.0']);
  });

  // Kos TV: turning a plugin off asks first, and for kOS TV's own it says the
  // apps depend on it.
  testWidgets('disabling a plugin asks first', (tester) async {
    await pump(tester, _moonbase.id);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.adminDisablePluginConfirm('Moonbase')),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(api.disabled, isEmpty);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.disable));
    await tester.pumpAndSettle();
    expect(api.disabled, [_moonbase.id]);
  });

  testWidgets('disabling or uninstalling kOS TV warns about the apps', (
    tester,
  ) async {
    await pump(tester, _kosTv.id);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '${l10n.adminDisablePluginConfirm('kOS TV')}\n\n'
        '${l10n.adminKosTvPluginWarning}',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.uninstall));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '${l10n.adminUninstallPluginConfirm('kOS TV')}\n\n'
        '${l10n.adminKosTvPluginWarning}',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.uninstall));
    await tester.pumpAndSettle();
    expect(api.uninstalled, [_kosTv.id]);
    expect(api.disabled, isEmpty);
  });

  test('the main-menu page wins, else the first one', () {
    final pages = [
      {'Name': 'A', 'PluginId': 'p', 'EnableInMainMenu': false},
      {'Name': 'B', 'PluginId': 'p', 'EnableInMainMenu': true},
      {'Name': 'C', 'PluginId': 'q', 'EnableInMainMenu': false},
    ];
    expect(configurationPageFor(pages, 'p'), 'B');
    expect(configurationPageFor(pages, 'q'), 'C');
    expect(configurationPageFor(pages, 'missing'), isNull);
  });
}
