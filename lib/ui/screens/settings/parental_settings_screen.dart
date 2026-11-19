import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:server_core/server_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../util/error_message.dart';
import '../../widgets/settings/settings_section_header.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/parental_rating_severity.dart';
import '../../../util/pin_code_util.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/adaptive/adaptive_list_section.dart';
import '../../widgets/kostv_kids_mode_gate.dart';
import '../../widgets/pin_entry_dialog.dart';
import '../../widgets/settings/preference_binding.dart';
import '../../widgets/settings/preference_tiles.dart';
import '../../widgets/settings/clean_settings_typography.dart';
import 'settings_app_bar.dart';
import '../../widgets/focus/request_initial_focus.dart';

class ParentalSettingsScreen extends StatefulWidget {
  const ParentalSettingsScreen({super.key});

  @override
  State<ParentalSettingsScreen> createState() => _ParentalSettingsScreenState();
}

class _ParentalSettingsScreenState extends State<ParentalSettingsScreen> {
  late final PreferenceBinding<String> _blockedRatings;
  final FocusNode _firstRatingFocusNode = FocusNode(
    debugLabel: 'ParentalFirstRating',
  );
  final List<String> _serverRatings = [];

  /// Kos TV: this screen's own PIN, apart from the profile's. Null with
  /// nobody signed in, where there is no one to keep it for.
  final PinCodeUtil? _parentalPin = kostvParentalPin();
  final FocusNode _parentalPinFocusNode = FocusNode(
    debugLabel: 'ParentalPin',
  );
  bool _pinBusy = false;
  bool _loadingRatings = true;
  String? _ratingsError;

  @override
  void initState() {
    super.initState();
    _blockedRatings = PreferenceBinding(
      GetIt.instance<PreferenceStore>(),
      UserPreferences.blockedParentalRatings,
    );
    _loadServerRatings();
  }

  @override
  void dispose() {
    _firstRatingFocusNode.dispose();
    _parentalPinFocusNode.dispose();
    _blockedRatings.dispose();
    super.dispose();
  }

  Set<String> get _blocked => _parseStored(_blockedRatings.value);

  static Set<String> _parseStored(String csv) => csv
      .split(',')
      .map((e) => e.trim().toUpperCase())
      .where((e) => e.isNotEmpty)
      .toSet();

  /// Mildest first, so blocking reads down the list as "everything from here".
  List<String> get _effectiveRatings {
    final merged = <String>{..._serverRatings, ..._blocked};
    final sorted = merged.toList()
      ..sort((a, b) {
        final bySeverity = parentalRatingSeverity(
          a,
        ).compareTo(parentalRatingSeverity(b));
        return bySeverity != 0 ? bySeverity : a.compareTo(b);
      });
    return sorted;
  }

  /// Ratings the ladder can place, which block everything above them, and the
  /// ones it can't, which only ever block themselves.
  bool _ranks(String rating) =>
      isRankedRatingSeverity(parentalRatingSeverity(rating));

  static const _ratedItemTypes = [
    'Movie',
    'Series',
    'Episode',
    'Video',
    'MusicVideo',
    'Book',
    'AudioBook',
  ];

  Future<void> _loadServerRatings() async {
    try {
      final client = GetIt.instance<MediaServerClient>();
      final discovered = <String>{};

      // Kos TV: the server lists every rating in the library in one answer,
      // which a walk through the items capped at the first 3,000 missed in a
      // big library. The walk stays for a server that answers with none.
      final filters = await client.itemsApi.getQueryFilters(
        includeItemTypes: _ratedItemTypes,
      );
      for (final rating in filters.officialRatings) {
        final trimmed = rating.trim();
        if (trimmed.isNotEmpty) discovered.add(trimmed.toUpperCase());
      }

      final walk = discovered.isEmpty;
      const pageSize = 200;
      var startIndex = 0;
      var safetyPages = 0;

      while (walk && safetyPages < 15) {
        final response = await client.itemsApi.getItems(
          includeItemTypes: _ratedItemTypes,
          recursive: true,
          fields: 'OfficialRating',
          startIndex: startIndex,
          limit: pageSize,
          enableTotalRecordCount: true,
        );

        final items = response['Items'];
        final totalRecordCount = response['TotalRecordCount'] as num?;
        final page = items is List
            ? items
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : const <Map<String, dynamic>>[];

        for (final item in page) {
          final rating = item['OfficialRating']?.toString().trim();
          if (rating != null && rating.isNotEmpty) {
            discovered.add(rating.toUpperCase());
          }
        }

        if (page.length < pageSize) {
          break;
        }

        startIndex += page.length;
        safetyPages += 1;
        if (totalRecordCount != null &&
            startIndex >= totalRecordCount.toInt()) {
          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _serverRatings
          ..clear()
          ..addAll(discovered.toList()..sort((a, b) => a.compareTo(b)));
        _loadingRatings = false;
        _ratingsError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingRatings = false;
        _ratingsError = describeError(error, AppLocalizations.of(context));
      });
    }
  }

  void _toggle(String rating) {
    final current = _parseStored(
      GetIt.instance<UserPreferences>().get(
        UserPreferences.blockedParentalRatings,
      ),
    );
    if (current.contains(rating)) {
      current.remove(rating);
    } else {
      current.add(rating);
    }
    _blockedRatings.value = current.join(',');
    setState(() {});
  }

  /// Kos TV: sets, changes or removes the Parental controls PIN. Changing or
  /// removing it asks for the current one first. Focus goes back to the
  /// section's first row, which the swap of rows would otherwise leave
  /// nowhere on a TV.
  Future<void> _editParentalPin({required bool remove}) async {
    final pin = _parentalPin;
    if (pin == null || _pinBusy) return;
    _pinBusy = true;
    try {
      final had = pin.isPinEnabled;
      if (had && !await kostvAskDevicePin(context, pin)) return;
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (remove) {
        await pin.removePin();
      } else {
        final saved = await PinEntryDialog.show(
          context,
          mode: PinEntryMode.set,
          onPinSet: pin.setPin,
        );
        if (!saved) return;
      }
      if (!mounted) return;
      setState(() {});
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            remove ? l10n.kostvParentalPinRemoved : l10n.kostvParentalPinSaved,
          ),
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && PlatformDetection.isTV) {
          _parentalPinFocusNode.requestFocus();
        }
      });
    } finally {
      _pinBusy = false;
    }
  }

  Widget _parentalPinTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    FocusNode? focusNode,
  }) {
    return TvFocusHighlight(
      builder: (context, focused) => ListTile(
        focusNode: focusNode,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }

  List<Widget> _parentalPinSection(AppLocalizations l10n) {
    final pin = _parentalPin;
    if (pin == null) return const [];
    return [
      SettingsSectionHeader(l10n.kostvParentalPinSection),
      adaptiveListSection(
        children: pin.isPinEnabled
            ? [
                _parentalPinTile(
                  icon: Icons.edit,
                  title: l10n.changePin,
                  subtitle: l10n.kostvParentalPinChangeSubtitle,
                  focusNode: _parentalPinFocusNode,
                  onTap: () => _editParentalPin(remove: false),
                ),
                _parentalPinTile(
                  icon: Icons.delete,
                  title: l10n.removePin,
                  subtitle: l10n.kostvParentalPinRemoveSubtitle,
                  onTap: () => _editParentalPin(remove: true),
                ),
              ]
            : [
                _parentalPinTile(
                  icon: Icons.pin,
                  title: l10n.kostvParentalPinSet,
                  subtitle: l10n.kostvParentalPinSetSubtitle,
                  focusNode: _parentalPinFocusNode,
                  onTap: () => _editParentalPin(remove: false),
                ),
              ],
      ),
    ];
  }

  Widget _ratingTile(
    BuildContext context, {
    required String rating,
    required bool isBlocked,
    required bool isFirst,
  }) {
    return TvFocusHighlight(
        builder: (_, focused) => ListTile(
          focusNode: isFirst ? _firstRatingFocusNode : null,
          autofocus: PlatformDetection.isTV && isFirst,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          leading: IconTheme(
            data: IconThemeData(
              color: focused
                  ? AppColors.black.withValues(alpha: 0.54)
                  : AppColorScheme.onSurface.withValues(
                      alpha: 0.7,
                    ),
              size: 24,
            ),
            child: Icon(
              isBlocked
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
            ),
          ),
          title: DefaultTextStyle.merge(
            style: TextStyle(
              color: focused
                  ? AppColors.black.withValues(alpha: 0.87)
                  : AppColorScheme.onSurface,
            ),
            child: Text(rating),
          ),
          onTap: () => _toggle(rating),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ratings = _effectiveRatings;
    final targetNode =
        PlatformDetection.isTV && !_loadingRatings && ratings.isNotEmpty
        ? _firstRatingFocusNode
        : null;
    return RequestInitialFocus(
      targetNode: targetNode,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ratings = _effectiveRatings;
    final ranked = ratings.where(_ranks).toList();
    final unranked = ratings.where((r) => !_ranks(r)).toList();

    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, Text(l10n.parentalControls)),
        body: ValueListenableBuilder<String>(
          valueListenable: _blockedRatings,
          builder: (context, blockedValue, _) {
            final blocked = _parseStored(blockedValue);

            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(l10n.blockContentWithRatings),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    l10n.blockedRatingsCeilingHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_loadingRatings)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (ratings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _ratingsError == null
                          ? l10n.noContentRatingsFound
                          : l10n.couldNotLoadServerRatings,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else ...[
                  if (_ratingsError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        l10n.couldNotRefreshRatings,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  SettingsSectionHeader(l10n.ratings),
                  adaptiveListSection(
                    children: [
                      for (final (index, rating) in ranked.indexed)
                        _ratingTile(
                          context,
                          rating: rating,
                          isBlocked: blocked.contains(rating),
                          isFirst: index == 0,
                        ),
                    ],
                  ),
                  // These can't be placed on the ladder, so they can't say
                  // anything about what else to hide.
                  if (unranked.isNotEmpty) ...[
                    SettingsSectionHeader(l10n.blockedRatingsUnrankedSection),
                    adaptiveListSection(
                      children: [
                        for (final rating in unranked)
                          _ratingTile(
                            context,
                            rating: rating,
                            isBlocked: blocked.contains(rating),
                            isFirst: false,
                          ),
                      ],
                    ),
                  ],
                ],
                SettingsSectionHeader(l10n.recommendations),
                adaptiveListSection(
                  children: [
                    SwitchPreferenceTile(
                      preference: UserPreferences
                          .recommendationsApplyParentalRatingCap,
                      title: l10n.recommendationsApplyParentalRatingCap,
                      subtitle: l10n
                          .recommendationsApplyParentalRatingCapSubtitle,
                      icon: Icons.family_restroom,
                    ),
                  ],
                ),
                ..._parentalPinSection(l10n),
              ],
            );
          },
        ),
      ),
    );
  }
}
