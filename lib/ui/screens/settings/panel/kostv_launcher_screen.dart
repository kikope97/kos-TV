part of '../settings_side_panel.dart';

/// Kos TV: Launcher mode, on a TV. What a TV where kOS TV is the start screen
/// wants and a TV where it is just the player doesn't: the opening animation,
/// the Apps row on Home and the Apps screen in the menu. Each TV keeps its
/// own choices, never synced, since the same person can have kOS TV as the
/// start screen on one TV and as an app on another. More launcher things go
/// here as they come.
class _KostvLauncherScreen extends StatelessWidget {
  const _KostvLauncherScreen();

  void _chooseRowApps(BuildContext context) {
    // Out of Settings (as Administration does), to All apps, where holding OK
    // on an app adds it to the row or takes it off.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) rootNavigator.pop();
    context.navigateTopLevel(Destinations.apps);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = GetIt.instance<UserPreferences>();
    final apps = kostvAppsAvailable();
    return Scaffold(
      appBar: buildSettingsAppBar(context, Text(l10n.kostvLauncherMode)),
      body: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(
            bottom: 96 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(
                l10n.kostvLauncherModeIntro,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            adaptiveListSection(
              children: [
                SwitchPreferenceTile(
                  preference: UserPreferences.kostvIntroEnabled,
                  title: l10n.kostvIntroSetting,
                  subtitle: l10n.kostvIntroSettingSubtitle,
                  icon: Icons.movie_filter_outlined,
                ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.play_circle_outline_rounded),
                  title: Text(l10n.kostvIntroWatch),
                  subtitle: Text(l10n.kostvIntroWatchSubtitle),
                  onTap: () => KosIntro.show(context),
                ),
                if (apps) ...[
                  SwitchPreferenceTile(
                    preference: UserPreferences.showAppsRow,
                    title: l10n.kostvShowAppsRow,
                    subtitle: l10n.kostvShowAppsRowSubtitle,
                    icon: Icons.view_carousel_outlined,
                  ),
                  if (prefs.get(UserPreferences.showAppsRow))
                    _TvSettingsListTile(
                      leading: const Icon(Icons.edit_note_rounded),
                      title: Text(l10n.kostvChooseRowApps),
                      subtitle: Text(l10n.kostvChooseRowAppsSubtitle),
                      onTap: () => _chooseRowApps(context),
                    ),
                  SwitchPreferenceTile(
                    preference: UserPreferences.showAppsButton,
                    title: l10n.kostvShowAppsButton,
                    subtitle: l10n.kostvShowAppsButtonSubtitle,
                    icon: Icons.apps_rounded,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
