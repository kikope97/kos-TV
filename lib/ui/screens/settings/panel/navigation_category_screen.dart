part of '../settings_side_panel.dart';

/// Kos TV: what the menu offers. Its design has no settings: there is one,
/// the same for everyone (the owner's decision, 2026-11-22); what is left
/// here are the switches of the destinations it shows.
class _NavigationCategoryScreen extends StatefulWidget {
  const _NavigationCategoryScreen();

  @override
  State<_NavigationCategoryScreen> createState() =>
      _NavigationCategoryScreenState();
}

class _NavigationCategoryScreenState extends State<_NavigationCategoryScreen> {
  late final PluginSyncService _syncService;

  @override
  void initState() {
    super.initState();
    _syncService = GetIt.instance<PluginSyncService>();
    _syncService.addListener(_onSyncChanged);
    unawaited(SetupPreviewData.loadLibraries());
  }

  @override
  void dispose() {
    _syncService.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = GetIt.instance<UserPreferences>();
    return Scaffold(
      appBar: buildSettingsAppBar(context, Text(l10n.navigationBar)),
      body: ListView(
        children: [
          _SectionHeader(l10n.navButtons),
          // The switches write through their own bindings, so this watches
          // the preferences to follow them, and the libraries to offer Live
          // TV once it turns out to be set up.
          ListenableBuilder(
            listenable: Listenable.merge([prefs, SetupPreviewData.libraries]),
            builder: (context, _) => adaptiveListSection(
              children: [
                SwitchPreferenceTile(
                  preference: UserPreferences.showGenresButton,
                  title: l10n.showGenresButton,
                  subtitle: l10n.settingsShowGenresButtonInNavigation,
                  icon: Icons.theater_comedy,
                  onChanged: _pushPersonalizationSync,
                ),
                if (SetupPreviewData.hasLiveTv)
                  SwitchPreferenceTile(
                    preference: UserPreferences.showLiveTvButton,
                    title: l10n.showLiveTvButton,
                    subtitle: l10n.settingsShowLiveTvButtonInNavigation,
                    icon: Icons.live_tv,
                    onChanged: _pushPersonalizationSync,
                  ),
                SwitchPreferenceTile(
                  preference: UserPreferences.showLibrariesInToolbar,
                  title: l10n.showLibrariesInToolbar,
                  subtitle: l10n.settingsShowLibrariesButtonInNavigation,
                  icon: Icons.video_library,
                  onChanged: _pushPersonalizationSync,
                ),
                // The phone's bar keeps Bibliotecas as one page, so this
                // only applies to the bar of tabs at the top.
                if (NavigationLayout.usesTopToolbar &&
                    prefs.get(UserPreferences.showLibrariesInToolbar))
                  SwitchPreferenceTile(
                    preference: UserPreferences.showLibrariesIndividually,
                    title: l10n.showLibrariesIndividually,
                    subtitle: l10n.showLibrariesIndividuallySubtitle,
                    icon: Icons.video_library,
                    onChanged: _pushPersonalizationSync,
                  ),
                if (prefs.get(UserPreferences.syncPlayEnabled))
                  SwitchPreferenceTile(
                    preference: UserPreferences.showSyncPlayButton,
                    title: l10n.settingsSyncplayButton,
                    subtitle: l10n.settingsSyncplayButtonSubtitle,
                    icon: Icons.groups,
                    onChanged: _pushPersonalizationSync,
                  ),
                // Kos TV: the Discover button, for a person the requests
                // service lets in.
                if (kostvDiscoverAllowed())
                  SwitchPreferenceTile(
                    preference: UserPreferences.showDiscoverButton,
                    title: l10n.kostvShowDiscoverButton,
                    icon: Icons.explore_rounded,
                    onChanged: _pushPersonalizationSync,
                  ),
                // Kos TV: Music, the page of its own.
                SwitchPreferenceTile(
                  preference: UserPreferences.kostvShowMusicButton,
                  title: l10n.kostvMusicShowButton,
                  subtitle: l10n.kostvMusicShowButtonSubtitle,
                  icon: Icons.music_note_rounded,
                  onChanged: _pushPersonalizationSync,
                ),
                if (_syncService.calendarAvailable)
                  SwitchPreferenceTile(
                    preference: UserPreferences.showCalendarButton,
                    title: l10n.showCalendarButton,
                    subtitle: l10n.showCalendarButtonSubtitle,
                    icon: Icons.calendar_month_rounded,
                    onChanged: _pushPersonalizationSync,
                  ),
                // Saved downloads keep the button even after downloading is
                // turned off.
                if (DownloadsNavSlot.isAvailable() ||
                    DownloadsNavSlot.hasSavedMedia())
                  SwitchPreferenceTile(
                    preference: UserPreferences.showDownloadsButton,
                    title: l10n.showDownloadsButton,
                    icon: Icons.download_for_offline,
                    onChanged: _pushPersonalizationSync,
                  ),
                // Server messages come from the server plugin.
                if (moonfinPluginOnAnySignedInServer())
                  SwitchPreferenceTile(
                    preference: UserPreferences.showServerMessagesButton,
                    title: l10n.serverMessagesShowButton,
                    subtitle: l10n.serverMessagesShowButtonSubtitle,
                    icon: Icons.info_outline_rounded,
                    onChanged: _pushPersonalizationSync,
                  ),
                // Only where the plugin has friends on, so nobody is offered
                // a button that would never show.
                if (GetIt.instance<AchievementsService>().socialAvailable)
                  SwitchPreferenceTile(
                    preference: UserPreferences.showFriendsButton,
                    title: l10n.friendsShowButton,
                    subtitle: l10n.friendsShowButtonSubtitle,
                    icon: Icons.people_alt_rounded,
                    onChanged: _pushPersonalizationSync,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
