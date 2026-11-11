part of '../settings_side_panel.dart';

class _HomeScreenCategoryScreen extends StatefulWidget {
  const _HomeScreenCategoryScreen();

  @override
  State<_HomeScreenCategoryScreen> createState() =>
      _HomeScreenCategoryScreenState();
}

class _HomeScreenCategoryScreenState extends State<_HomeScreenCategoryScreen> {
  final _prefs = GetIt.instance<UserPreferences>();

  @override
  void initState() {
    super.initState();
    unawaited(_prefs.reconcileMediaPreviewMode());
    unawaited(_prefs.reconcileHomeBackdropStyle());
  }

  // Older apps only read the switch, so it follows the mode.
  Future<void> _onMediaPreviewModeChanged() async {
    await _prefs.set(
      UserPreferences.episodePreviewEnabled,
      _prefs.get(UserPreferences.mediaPreviewMode) !=
          UserPreferences.mediaPreviewOff,
    );
    _pushPersonalizationSync();
  }

  Future<void> _onHomeBackdropStyleChanged() async {
    await _prefs.set(
      UserPreferences.homeBackdropEnabled,
      _prefs.get(UserPreferences.homeBackdropStyle) !=
          UserPreferences.homeBackdropOff,
    );
    _pushPersonalizationSync();
  }

  String _mediaTypeBadgeBehaviorLabel(
    AppLocalizations l10n,
    MediaTypeBadgeBehavior behavior,
  ) => switch (behavior) {
    MediaTypeBadgeBehavior.always => l10n.always,
    MediaTypeBadgeBehavior.mixedRowsOnly => l10n.mixedRowsOnly,
    MediaTypeBadgeBehavior.never => l10n.never,
  };

  Future<void> _refreshCustomRows() async {
    bool dialogDismissed = false;
    unawaited(
      showFocusRestoringDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return withCleanSettingsTypography(
            ctx,
            PopScope(
              canPop: false,
              child: AlertDialog(
                title: Text(AppLocalizations.of(ctx).kostvRefreshingCustomRows),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    const SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppLocalizations.of(ctx).kostvRefreshingCustomRowsDetail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ).then((_) {
        dialogDismissed = true;
      }),
    );

    try {
      final customService = GetIt.instance<CustomExternalListsService>();
      await Future.wait([
        for (final config in _prefs.homeSectionsConfig)
          if (config.pluginSource == HomeSectionPluginSource.custom &&
              config.enabled)
            () async {
              try {
                final items = await customService.fetchCustomRow(
                  config,
                  forceRefresh: true,
                );
                if (items.isNotEmpty) {
                  await customService.saveCustomRowToCache(config, items);
                }
              } catch (e) {
                debugPrint(
                  '[RefreshCustomRows] Failed to refresh ${config.pluginSection}: $e',
                );
              }
            }(),
      ]);

      await _prefs.set(
        UserPreferences.lastExternalRowsRefreshTime,
        DateTime.now().millisecondsSinceEpoch,
      );
      _reloadHomeRows();

      if (mounted && !dialogDismissed) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).kostvCustomRowsRefreshed,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted && !dialogDismissed) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        final detail = describeError(e, AppLocalizations.of(context));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).kostvCustomRowsRefreshFailed(detail),
            ),
          ),
        );
      }
    }
  }

  String _rowsStyleLabel(AppLocalizations l10n, HomeRowsStyle style) =>
      switch (style) {
        HomeRowsStyle.v1 => l10n.homeRowsStyleClassic,
        HomeRowsStyle.v2 => l10n.homeRowsStyleModern,
      };

  void _reloadHomeRows() {
    if (!GetIt.instance.isRegistered<HomeViewModel>()) return;
    GetIt.instance<HomeViewModel>().load(preserveExisting: true);
  }

  void _syncMdblistWatchingNowSection(bool isEnabled) {
    final configs = List<HomeSectionConfig>.from(_prefs.homeSectionsConfig);
    final idx = configs.indexWhere(
      (c) => c.type == HomeSectionType.mdblistWatchingNow,
    );

    if (isEnabled) {
      if (idx >= 0) {
        final existing = configs.removeAt(idx);
        final lastEnabledIndex = configs.lastIndexWhere((c) => c.enabled);
        final insertIndex = lastEnabledIndex >= 0 ? lastEnabledIndex + 1 : 0;
        configs.insert(insertIndex, existing.copyWith(enabled: true));
      } else {
        final lastEnabledIndex = configs.lastIndexWhere((c) => c.enabled);
        final insertIndex = lastEnabledIndex >= 0 ? lastEnabledIndex + 1 : 0;
        configs.insert(
          insertIndex,
          const HomeSectionConfig(
            type: HomeSectionType.mdblistWatchingNow,
            enabled: true,
            order: 0,
          ),
        );
      }
    } else {
      if (idx >= 0) {
        configs[idx] = configs[idx].copyWith(enabled: false);
      }
    }

    for (var i = 0; i < configs.length; i++) {
      configs[i] = configs[i].copyWith(order: i);
    }
    _prefs.setHomeSectionsConfig(configs);
    _pushPersonalizationSync();
    _reloadHomeRows();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rowsStyle = _prefs.get(UserPreferences.homeRowsStyle);
    final isMobileUi = PlatformDetection.useMobileUi;
    final isFullScreenRows =
        !isMobileUi && _prefs.get(UserPreferences.fullScreenRows);
    final isInfoOverlayOn =
        !isMobileUi &&
        rowsStyle == HomeRowsStyle.v1 &&
        _prefs.get(UserPreferences.homeRowInfoOverlay);
    final isPaddingEnabled = !isFullScreenRows && !isInfoOverlayOn;
    final syncService = GetIt.instance<PluginSyncService>();
    final pluginAvailable = syncService.pluginAvailable;
    final tmdbAvailable = syncService.tmdbAvailable;
    // Only when the plugin reaches a Sonarr or Radarr this user may see.
    final showUpcomingCalendars = syncService.calendarAvailable;
    return Scaffold(
      appBar: buildSettingsAppBar(context, Text(l10n.homeScreen)),
      body: ListView(
        children: [
          _SectionHeader(l10n.settingsContentsSection),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                autofocus: true,
                leading: const Icon(Icons.list),
                title: Text(l10n.homeRows),
                subtitle: Text(l10n.homeRowsSubtitle),
                onTap: () =>
                    context.pushSettingsScreen(const HomeSectionsScreen()),
              ),
              // Kos TV: the Apps row (a TV whose apps can be listed).
              if (kostvAppsAvailable())
                SwitchPreferenceTile(
                  preference: UserPreferences.showAppsRow,
                  title: l10n.kostvShowAppsRow,
                  subtitle: l10n.kostvShowAppsRowSubtitle,
                  icon: Icons.apps_rounded,
                ),
              _TvSettingsListTile(
                leading: const Icon(Icons.featured_play_list),
                title: Text(l10n.mediaBar),
                subtitle: Text(l10n.featuredContentAppearance),
                onTap: () =>
                    context.pushSettingsScreen(const MediaBarSettingsScreen()),
              ),
            ],
          ),

          _SectionHeader(l10n.settingsLooksSection),
          adaptiveListSection(
            children: [
              EnumPreferenceTile<HomeRowsStyle>(
                preference: UserPreferences.homeRowsStyle,
                title: l10n.rowsType,
                description: l10n.rowsTypeDescription,
                icon: Icons.view_carousel,
                labelOf: (style) => _rowsStyleLabel(l10n, style),
                onChanged: () {
                  _pushPersonalizationSync();
                  _reloadHomeRows();
                  if (!mounted) return;
                  setState(() {});
                },
              ),
              EnumPreferenceTile<PosterSize>(
                preference: UserPreferences.posterSize,
                title: l10n.cardSize,
                icon: Icons.photo_size_select_large,
                labelOf: (v) => switch (v) {
                  PosterSize.small => l10n.small,
                  PosterSize.medium => l10n.medium,
                  PosterSize.large => l10n.large,
                  PosterSize.extraLarge => l10n.extraLarge,
                  PosterSize.grandparents => l10n.uiScaleGrandparents,
                },
                onChanged: _pushPersonalizationSync,
              ),
              StringPickerPreferenceTile(
                preference: UserPreferences.mediaPreviewMode,
                title: l10n.mediaPreview,
                description: l10n.mediaPreviewDescription,
                icon: Icons.ondemand_video,
                options: {
                  UserPreferences.mediaPreviewOff: l10n.off,
                  UserPreferences.mediaPreviewMedia: l10n.mediaPreview,
                  UserPreferences.mediaPreviewTrailer: l10n.trailerPreview,
                },
                onChanged: _onMediaPreviewModeChanged,
              ),
              SwitchPreferenceTile(
                preference: UserPreferences.previewAudioEnabled,
                title: l10n.previewAudio,
                subtitle: l10n.enablePreviewAudio,
                icon: Icons.volume_up,
                onChanged: _pushPersonalizationSync,
              ),
              SliderPreferenceTile(
                preference: UserPreferences.previewVolume,
                title: l10n.previewVolume,
                description: l10n.previewVolumeDescription,
                icon: Icons.volume_down,
                min: 0,
                max: 100,
                divisions: 20,
                labelOf: (v) => '$v%',
                onChangeEnd: _pushPersonalizationSync,
              ),
            ],
          ),

          // Kos TV: the technical rest, behind «Más ajustes».
          ...settingsMore(
            context,
            id: 'home',
            summary: l10n.kostvMoreHomeSummary,
            children: [
              _SectionHeader(l10n.settingsContentsSection),
              adaptiveListSection(
                children: [
                  _TvSettingsListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(l10n.rowOptions),
                    subtitle: Text(l10n.rowOptionsSubtitle),
                    onTap: () => context.pushSettingsScreen(
                      const HomeRowTogglesScreen(),
                    ),
                  ),
                ],
              ),
              _SectionHeader(l10n.settingsLooksSection),
              adaptiveListSection(
                children: [
                  if (rowsStyle == HomeRowsStyle.v2)
                    SwitchPreferenceTile(
                      preference: UserPreferences.modernCardsOnMyMediaRow,
                      title: l10n.modernCardsOnMyMediaRow,
                      subtitle: l10n.modernCardsOnMyMediaRowDescription,
                      icon: Icons.photo_library_outlined,
                      onChanged: () {
                        _pushPersonalizationSync();
                        _reloadHomeRows();
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                  if (rowsStyle == HomeRowsStyle.v2 && !isMobileUi) ...[
                    EnumPreferenceTile<ModernCardTransitionSpeed>(
                      preference: UserPreferences.modernCardTransitionSpeed,
                      title: l10n.modernCardsTransitionSpeed,
                      description: l10n.modernCardsTransitionSpeedSubtitle,
                      icon: Icons.auto_awesome_motion_outlined,
                      labelOf: (v) => switch (v) {
                        ModernCardTransitionSpeed.extraSlow =>
                          l10n.animationSpeedExtraSlow,
                        ModernCardTransitionSpeed.slow =>
                          l10n.animationSpeedSlow,
                        ModernCardTransitionSpeed.medium =>
                          l10n.animationSpeedMedium,
                        ModernCardTransitionSpeed.fast =>
                          l10n.animationSpeedFast,
                        ModernCardTransitionSpeed.off => l10n.animationSpeedOff,
                      },
                    ),
                    SwitchPreferenceTile(
                      preference:
                          UserPreferences.delayCardExpansionOnRapidScroll,
                      title: l10n.delayCardExpansionOnRapidScroll,
                      subtitle: l10n.delayCardExpansionOnRapidScrollSubtitle,
                      icon: Icons.hourglass_empty_rounded,
                    ),
                  ],
                  SliderPreferenceTile(
                    preference: rowsStyle == HomeRowsStyle.v2
                        ? UserPreferences.modernHomeRowsPadding
                        : UserPreferences.classicHomeRowsPadding,
                    title: l10n.homeRowsPadding,
                    description: l10n.homeRowsPaddingDescription,
                    icon: Icons.unfold_more,
                    min: rowsStyle == HomeRowsStyle.v2 ? 360 : 10,
                    max: rowsStyle == HomeRowsStyle.v2 ? 560 : 130,
                    divisions: rowsStyle == HomeRowsStyle.v2 ? 10 : 6,
                    enabled: isPaddingEnabled,
                    onChangeEnd: _pushPersonalizationSync,
                  ),
                  if (!PlatformDetection.useMobileUi)
                    SwitchPreferenceTile(
                      preference: UserPreferences.fullScreenRows,
                      title: l10n.fullScreenRows,
                      subtitle: l10n.fullScreenRowsDescription,
                      icon: Icons.image_aspect_ratio,
                      onChanged: () {
                        _pushPersonalizationSync();
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                  if (rowsStyle == HomeRowsStyle.v1)
                    _TvSettingsListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: Text(l10n.imageTypePerRow),
                      subtitle: Text(l10n.configureImageTypeForEachRow),
                      onTap: () => context.pushSettingsScreen(
                        const HomeRowsImageTypeScreen(),
                      ),
                    ),
                  SwitchPreferenceTile(
                    preference: UserPreferences.seriesThumbnailsEnabled,
                    title: l10n.seriesThumbnails,
                    subtitle: l10n.seriesThumbnailsDescription,
                    icon: Icons.image_aspect_ratio,
                    onChanged: _pushPersonalizationSync,
                  ),
                  if (rowsStyle == HomeRowsStyle.v1 && !isMobileUi)
                    SwitchPreferenceTile(
                      preference: UserPreferences.homeRowInfoOverlay,
                      title: l10n.homeRowInfoOverlay,
                      subtitle: l10n.showTitleMetadataOnHomeRows,
                      icon: Icons.info_outline,
                      onChanged: () {
                        _pushPersonalizationSync();
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                  if (isMobileUi)
                    SwitchPreferenceTile(
                      preference: UserPreferences.homeBackdropEnabled,
                      title: l10n.homeScreenBackdrop,
                      icon: Icons.photo,
                      onChanged: _pushPersonalizationSync,
                    )
                  else
                    StringPickerPreferenceTile(
                      preference: UserPreferences.homeBackdropStyle,
                      title: l10n.homeScreenBackdrop,
                      icon: Icons.photo,
                      options: {
                        UserPreferences.homeBackdropOff: l10n.off,
                        UserPreferences.homeBackdropFullScreen:
                            l10n.homeScreenBackdropFullScreen,
                        UserPreferences.homeBackdropCorner:
                            l10n.homeScreenBackdropCorner,
                        UserPreferences.homeBackdropTop:
                            l10n.homeScreenBackdropTop,
                      },
                      onChanged: _onHomeBackdropStyleChanged,
                    ),
                  SwitchPreferenceTile(
                    preference: UserPreferences.hideHomeMediaDescription,
                    title: l10n.hideHomeMediaDescription,
                    subtitle: l10n.hideHomeMediaDescriptionSubtitle,
                    icon: Icons.description_outlined,
                    onChanged: _pushPersonalizationSync,
                  ),
                  SwitchPreferenceTile(
                    preference: UserPreferences.hideHomeWatchProgress,
                    title: l10n.hideHomeWatchProgress,
                    subtitle: l10n.hideHomeWatchProgressSubtitle,
                    icon: Icons.linear_scale,
                    onChanged: _pushPersonalizationSync,
                  ),
                  SwitchPreferenceTile(
                    preference: UserPreferences.hideHomeUnwatchedCount,
                    title: l10n.hideHomeUnwatchedCount,
                    subtitle: l10n.hideHomeUnwatchedCountSubtitle,
                    icon: Icons.filter_9_plus_outlined,
                    onChanged: _pushPersonalizationSync,
                  ),
                ],
              ),
              _SectionHeader(l10n.ratings),
              adaptiveListSection(
                children: _ratingsSettingsTiles(
                  context,
                  l10n,
                  UserPreferences.homeRowsRatings,
                ),
              ),

              // Every source here needs the Moonbase plugin. The Radarr and Sonarr
              // calendars also need one of them linked to it.
              if (pluginAvailable) ...[
                _SectionHeader(l10n.externalSources),
                adaptiveListSection(
                  children: [
                    _TvSettingsListTile(
                      leading: const Icon(Icons.movie_outlined),
                      title: Text(l10n.kostvImdbLists),
                      subtitle: Text(l10n.kostvImdbListsSubtitle),
                      onTap: () =>
                          context.pushSettingsScreen(const _ImdbListsScreen()),
                    ),
                    SwitchPreferenceTile(
                      preference: UserPreferences.mdblistWatchingNowEnabled,
                      title: l10n.mdblistWatchingNow,
                      subtitle: l10n.mdblistWatchingNowDescription,
                      icon: Icons.public,
                      onChangedValue: _syncMdblistWatchingNowSection,
                    ),
                    _TvSettingsListTile(
                      leading: const Icon(Icons.trending_up),
                      title: Text(l10n.kostvTmdbLists),
                      subtitle: Text(
                        tmdbAvailable
                            ? l10n.kostvTmdbListsSubtitle
                            : l10n.kostvTmdbListsUnavailable,
                      ),
                      onTap: tmdbAvailable
                          ? () => context.pushSettingsScreen(
                              const _TmdbListsScreen(),
                            )
                          : null,
                    ),
                    _TvSettingsListTile(
                      leading: const Icon(Icons.celebration_outlined),
                      title: Text(l10n.seasonalRow),
                      subtitle: Text(l10n.seasonalRowDescription),
                      onTap: () => context.pushSettingsScreen(
                        const _SeasonalRowScreen(),
                      ),
                    ),
                    if (showUpcomingCalendars)
                      _TvSettingsListTile(
                        leading: const Icon(Icons.calendar_month),
                        title: Text(l10n.upcomingCalendars),
                        subtitle: Text(l10n.upcomingCalendarsDescription),
                        onTap: () => context.pushSettingsScreen(
                          const _UpcomingCalendarsScreen(),
                        ),
                      ),
                    _TvSettingsListTile(
                      leading: const Icon(Icons.tune_outlined),
                      title: Text(l10n.kostvCustomRows),
                      subtitle: Text(l10n.kostvCustomRowsSubtitle),
                      onTap: () => context.pushSettingsScreen(
                        const _CustomListsScreen(),
                      ),
                    ),
                    EnumPreferenceTile<MediaTypeBadgeBehavior>(
                      preference: UserPreferences.mediaTypeBadgeBehavior,
                      title: l10n.kostvMediaTypeBadges,
                      description: l10n.kostvMediaTypeBadgesSubtitle,
                      icon: Icons.info_outline,
                      labelOf: (behavior) =>
                          _mediaTypeBadgeBehaviorLabel(l10n, behavior),
                      onChanged: () {
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    _TvSettingsListTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(l10n.kostvRefreshCustomRows),
                      subtitle: Text(l10n.kostvRefreshCustomRowsSubtitle),
                      onTap: _refreshCustomRows,
                    ),
                  ],
                ),
              ],

              if (PlatformDetection.isAppleTV) ...[
                _SectionHeader(l10n.appleTvHomeScreen),
                adaptiveListSection(
                  children: [
                    EnumPreferenceTile<TopShelfContent>(
                      preference: UserPreferences.topShelfContent,
                      title: l10n.topShelf,
                      description: l10n.topShelfDescription,
                      icon: Icons.tv,
                      labelOf: (v) => switch (v) {
                        TopShelfContent.latestMedia => l10n.topShelfLatestMedia,
                        TopShelfContent.appBanner => l10n.topShelfAppBanner,
                      },
                      onChanged: TopShelfService().refresh,
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
