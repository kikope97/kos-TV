part of '../settings_side_panel.dart';

const _kostvRepo = 'kikope97/kos-TV';

class _AboutCategoryScreen extends StatelessWidget {
  const _AboutCategoryScreen();

  @override
  Widget build(BuildContext context) {
    final appVersion = AppBeta.label(GetIt.instance<DeviceInfo>().appVersion);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: buildSettingsAppBar(context, Text(l10n.aboutTitle)),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(child: const KosLogo(height: 72)),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.versionValue(appVersion),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          _SectionHeader(l10n.settingsAppInfo),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                autofocus: true,
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.version),
                subtitle: Text(appVersion),
                trailing: const SizedBox.shrink(),
                onTap: () => AfterHoursTrigger.press(context),
              ),
              if (AppDistribution.supportsInAppUpdates)
                const _CheckForUpdatesTile(),
              // Kos TV: its own repository. Moonfin's issue tracker, Discord
              // and donation tiles are gone: this is a family app, and
              // Moonfin keeps its credit in the tile below.
              _TvSettingsListTile(
                leading: const Icon(Icons.code),
                title: Text(l10n.sourceCode),
                subtitle: const Text('github.com/$_kostvRepo'),
                onTap: () => showQrOrLaunch(
                  context,
                  url: 'https://github.com/$_kostvRepo',
                  title: l10n.sourceCode,
                ),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.nightlight_round),
                title: Text(l10n.kostvBasedOnMoonfin),
                subtitle: Text(l10n.kostvBasedOnMoonfinSubtitle),
                onTap: () => showQrOrLaunch(
                  context,
                  url: 'https://github.com/Moonfin-Client/Moonfin-Core',
                  title: l10n.kostvBasedOnMoonfin,
                ),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.troubleshoot),
                title: const Text('Diagnostics & Logging'),
                subtitle: const Text(
                  'Capture media, login and network logs and send them to the '
                  'server as a report',
                ),
                onTap: () => context.pushSettingsScreen(
                  const DiagnosticsSettingsScreen(),
                ),
              ),
              if (PlatformDetection.useDesktopUi)
                _TvSettingsListTile(
                  leading: const Icon(Icons.keyboard_outlined),
                  title: Text(l10n.keyboardShortcutsTitle),
                  subtitle: Text(l10n.keyboardShortcutsSubtitle),
                  onTap: () => context.pushSettingsScreen(
                    const _KeyboardShortcutsScreen(),
                  ),
                ),
              _TvSettingsListTile(
                leading: const Icon(Icons.auto_awesome),
                title: Text(l10n.runSetupAgain),
                // Asking again on purpose says more than the stored answers do,
                // so a deliberate re-run offers every question back.
                onTap: () {
                  GetIt.instance<SetupWizardGate>().beginRerun();
                  context.navigateTopLevel(Destinations.setup);
                },
              ),
            ],
          ),
          _SectionHeader(l10n.settingsLegal),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                leading: const Icon(Icons.description),
                title: Text(l10n.settingsLicenses),
                subtitle: Text(l10n.settingsOpenSourceLicenseNotices),
                onTap: () => showQrOrLaunch(
                  context,
                  url: 'https://github.com/$_kostvRepo/blob/HEAD/LICENSE',
                  title: l10n.settingsLicenses,
                ),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.privacy_tip),
                title: Text(l10n.settingsPrivacyPolicy),
                subtitle: Text(l10n.settingsPrivacyPolicySubtitle),
                onTap: () => showQrOrLaunch(
                  context,
                  url:
                      'https://github.com/$_kostvRepo/blob/HEAD/PRIVACY_POLICY.md',
                  title: l10n.settingsPrivacyPolicy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckForUpdatesTile extends StatefulWidget {
  const _CheckForUpdatesTile();

  @override
  State<_CheckForUpdatesTile> createState() => _CheckForUpdatesTileState();
}

class _CheckForUpdatesTileState extends State<_CheckForUpdatesTile> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await checkAndShowUpdateResult(context);
    if (!mounted) return;
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _TvSettingsListTile(
      leading: _checking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.system_update_alt),
      title: Text(l10n.settingsCheckForUpdates),
      subtitle: Text(l10n.settingsCheckForUpdatesSubtitle),
      onTap: _checking ? null : _check,
    );
  }
}
