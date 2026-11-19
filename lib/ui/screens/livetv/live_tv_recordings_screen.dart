import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';
import 'kostv_recording_labels.dart';

import '../../../data/models/live_tv_recording_state.dart';
import '../../../data/viewmodels/recordings_view_model.dart';
import '../../../data/viewmodels/schedule_view_model.dart';
import '../../../data/viewmodels/series_recordings_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
import '../../../ui/mixins/focus_state_mixin.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/focus_scroll.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/adaptive/adaptive_dialog.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/live_tv/incomplete_recording.dart';
import '../../widgets/live_tv/series_recording_dialog.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/offline_aware_image.dart';
import '../calendar/calendar_common.dart';
import '../detail/kostv/kostv_detail_buttons.dart'
    show kostvLight, kostvOnLight;

class LiveTvRecordingsScreen extends StatefulWidget {
  const LiveTvRecordingsScreen({super.key});

  @override
  State<LiveTvRecordingsScreen> createState() => _LiveTvRecordingsScreenState();
}

enum _RecordingsTab { recordings, scheduled, series }

class _LiveTvRecordingsScreenState extends State<LiveTvRecordingsScreen> {
  late final RecordingsViewModel _vm;
  late final ScheduleViewModel _scheduleVm;
  late final SeriesRecordingsViewModel _seriesVm;
  _RecordingsTab _activeTab = _RecordingsTab.recordings;
  // Kos TV: where the remote starts, the first tab under the title.
  final _firstTabFocus = FocusNode(debugLabel: 'recordingsFirstTab');

  @override
  void initState() {
    super.initState();
    _vm = RecordingsViewModel(GetIt.instance<MediaServerClient>());
    _scheduleVm = ScheduleViewModel(GetIt.instance<MediaServerClient>());
    _seriesVm = SeriesRecordingsViewModel(GetIt.instance<MediaServerClient>());
    _vm.addListener(_onChanged);
    _scheduleVm.addListener(_onChanged);
    _seriesVm.addListener(_onChanged);
    _vm.load();
    _scheduleVm.load();
    _seriesVm.load();
    liveTvRecordingRevision.addListener(_onRecordingsChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Cancelling a series rule also cancels its scheduled showings, and a rule
  /// can be added or changed from a screen opened over this one, so every tab
  /// re-reads rather than keep the old list.
  void _onRecordingsChanged() {
    if (!mounted) return;
    _scheduleVm.refresh();
    _seriesVm.refresh();
    _vm.refreshScheduled();
  }

  @override
  void dispose() {
    liveTvRecordingRevision.removeListener(_onRecordingsChanged);
    _vm.removeListener(_onChanged);
    _scheduleVm.removeListener(_onChanged);
    _seriesVm.removeListener(_onChanged);
    _vm.dispose();
    _scheduleVm.dispose();
    _seriesVm.dispose();
    _firstTabFocus.dispose();
    super.dispose();
  }

  // Kos TV: dressed as the other kOS TV pages (the catalogue): the app's
  // background and menu, a big title with its count and the tabs under it.
  // Back is the menu's back arrow (the remote's Back on the TV).
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.liveTvGuide,
        showBackButton: true,
        // The tabs stay put and the rows scroll under them: the menu too.
        pinTopToolbar: true,
        child: RequestInitialFocus(
          targetNode: _firstTabFocus,
          child: _buildContent(),
        ),
      ),
    );
  }

  /// The page's side margins, as the catalogue's.
  EdgeInsets get _insets => calendarChromeInsets(context);

  /// Room under the last row for the phone's own bar at the bottom.
  double get _bottomInset =>
      MediaQuery.paddingOf(context).bottom +
      (PlatformDetection.useMobileUi && NavigationLayout.usesBottomNavbar
          ? 110
          : 48);

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  int get _recordingsCount =>
      _vm.recentRecordings.length +
      _vm.seriesRecordings.length +
      _vm.movieRecordings.length +
      _vm.sportsRecordings.length +
      _vm.kidsRecordings.length;

  int get _scheduledCount =>
      _scheduleVm.groups.fold(0, (sum, g) => sum + g.items.length);

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context);
    final phone = PlatformDetection.useMobileUi;
    final insets = _insets;
    final count = _vm.state == RecordingsState.loading ? 0 : _recordingsCount;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        insets.left,
        insets.top + (phone ? 8 : 40),
        insets.right,
        phone ? 12 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.liveTv.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: phone ? 12 : 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.recordings,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: phone ? 36 : 52,
              height: 1.05,
              letterSpacing: -1,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(height: 6),
            Text(
              l10n.kostvRecordingsCount(count),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: phone ? 14 : 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          SizedBox(height: phone ? 14 : 22),
          // A phone is too narrow for every tab on one line, so there they
          // wrap onto another line instead of running off the edge.
          Wrap(
            spacing: phone ? 8 : 12,
            runSpacing: 8,
            children: [
              _RecordingsPillButton(
                focusNode: _firstTabFocus,
                label: '${l10n.recordings} ($_recordingsCount)',
                isActive: _activeTab == _RecordingsTab.recordings,
                onPressed: () =>
                    setState(() => _activeTab = _RecordingsTab.recordings),
              ),
              _RecordingsPillButton(
                label: '${l10n.schedule} ($_scheduledCount)',
                isActive: _activeTab == _RecordingsTab.scheduled,
                onPressed: () =>
                    setState(() => _activeTab = _RecordingsTab.scheduled),
              ),
              _RecordingsPillButton(
                label:
                    '${l10n.seriesRecordings} (${_seriesVm.seriesTimers.length})',
                isActive: _activeTab == _RecordingsTab.series,
                onPressed: () =>
                    setState(() => _activeTab = _RecordingsTab.series),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Kos TV: an empty tab says so with an icon and a line on how to fill
  /// it, rather than a bare grey sentence in the middle of the page.
  Widget _emptyState({
    required IconData icon,
    required String title,
    required String hint,
  }) {
    final phone = PlatformDetection.useMobileUi;
    final insets = _insets;
    return Align(
      alignment: const Alignment(0, -0.35),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          insets.left,
          24,
          insets.right,
          _bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: phone ? 72 : 96,
              height: phone ? 72 : 96,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: phone ? 34 : 46,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            SizedBox(height: phone ? 16 : 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: phone ? 18 : 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: phone ? 14 : 17,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_activeTab) {
      _RecordingsTab.recordings => _buildRecordingsTab(),
      _RecordingsTab.scheduled => _buildScheduledTab(),
      _RecordingsTab.series => _buildSeriesTab(),
    };
  }

  Widget _buildRecordingsTab() {
    if (_vm.state == RecordingsState.loading) {
      return Center(child: const CircularProgressIndicator(color: Colors.white70));
    }
    if (_vm.state == RecordingsState.error) {
      return _errorState(
        AppLocalizations.of(context).failedToLoadRecordings,
        _vm.load,
      );
    }
    final l10n = AppLocalizations.of(context);
    final rows = <Widget>[];
    void addRow(String title, List<RecordingItem> items) {
      if (items.isEmpty) {
        return;
      }
      rows.add(
        _RecordingRow(
          insets: _insets,
          title: title,
          items: items,
          imageApi: _vm.imageApi,
          onItemFocused: _vm.setFocusedItem,
          onItemTap: _onItemTap,
        ),
      );
    }

    addRow(l10n.scheduledInNext24Hours, _vm.scheduledNext24h);
    addRow(l10n.recentRecordings, _vm.recentRecordings);
    addRow(l10n.tvSeries, _vm.seriesRecordings);
    addRow(l10n.movies, _vm.movieRecordings);
    addRow(l10n.sports, _vm.sportsRecordings);
    addRow(l10n.kids, _vm.kidsRecordings);
    if (rows.isEmpty) {
      return _emptyState(
        icon: Icons.fiber_dvr_outlined,
        title: l10n.noRecordingsFound,
        hint: l10n.kostvRecordingsEmptyHint,
      );
    }
    return ListView(
      padding: EdgeInsets.only(bottom: _bottomInset),
      children: rows,
    );
  }

  Widget _buildScheduledTab() {
    if (_scheduleVm.state == ScheduleState.loading) {
      return Center(child: const CircularProgressIndicator(color: Colors.white70));
    }
    if (_scheduleVm.state == ScheduleState.error) {
      return _errorState(
        AppLocalizations.of(context).failedToLoadSchedule,
        _scheduleVm.load,
      );
    }
    if (_scheduleVm.groups.isEmpty) {
      return _emptyState(
        icon: Icons.event_outlined,
        title: AppLocalizations.of(context).noScheduledRecordings,
        hint: AppLocalizations.of(context).kostvScheduledEmptyHint,
      );
    }
    return ListView(
      padding: EdgeInsets.only(bottom: _bottomInset),
      children: [
        for (final group in _scheduleVm.groups)
          _RecordingRow(
            insets: _insets,
            title: kostvScheduleDayLabel(AppLocalizations.of(context), group),
            items: group.items,
            imageApi: _scheduleVm.imageApi,
            onItemFocused: _scheduleVm.setFocusedItem,
            onItemTap: (item) => _cancelTimer(item),
          ),
      ],
    );
  }

  Widget _buildSeriesTab() {
    if (_seriesVm.state == SeriesRecordingsState.loading) {
      return Center(child: const CircularProgressIndicator(color: Colors.white70));
    }
    if (_seriesVm.state == SeriesRecordingsState.error) {
      return _errorState(
        AppLocalizations.of(context).failedToLoadSeriesRecordings,
        _seriesVm.load,
      );
    }
    if (_seriesVm.seriesTimers.isEmpty) {
      return _emptyState(
        icon: Icons.fiber_smart_record_outlined,
        title: AppLocalizations.of(context).noSeriesRecordings,
        hint: AppLocalizations.of(context).kostvSeriesRecordingsEmptyHint,
      );
    }
    return ListView(
      padding: EdgeInsets.only(bottom: _bottomInset),
      children: [
        _SeriesTimerRow(
          insets: _insets,
          timers: _seriesVm.seriesTimers,
          onItemFocused: _seriesVm.setFocusedTimer,
          onItemTap: (timer) => _showSeriesTimerOptions(timer),
        ),
      ],
    );
  }

  /// Kos TV: a failed read says so with a Retry a remote can reach, rather
  /// than leaving only a way out.
  Widget _errorState(String message, Future<void> Function() onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 16),
          _RecordingsPillButton(
            label: AppLocalizations.of(context).retry,
            onPressed: () => onRetry(),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelTimer(RecordingItem item) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFocusRestoringDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(l10n.cancelRecording, style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.cancelScheduledRecordingOf(item.name),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: Text(l10n.no),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.yesCancel),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _scheduleVm.cancelTimer(
          item.timerId ?? (throw StateError('No timer for ${item.name}')),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.failedToCancelRecording)),
          );
        }
      }
    }
  }

  Future<void> _showSeriesTimerOptions(SeriesTimerItem timer) async {
    final option = await showSeriesTimerOptionsDialog(
      context: context,
      name: timer.name,
      subtitle: kostvSeriesTimerSubtitle(AppLocalizations.of(context), timer),
    );
    if (!mounted) return;
    switch (option) {
      case SeriesTimerOption.changeSettings:
        await _changeSeriesTimer(timer);
      case SeriesTimerOption.cancel:
        await _cancelSeriesTimer(timer);
      case null:
        break;
    }
  }

  Future<void> _changeSeriesTimer(SeriesTimerItem timer) async {
    final l10n = AppLocalizations.of(context);
    try {
      final changed = await changeSeriesRecordingEpisodes(
        context: context,
        liveTvApi: GetIt.instance<MediaServerClient>().liveTvApi,
        seriesTimerId: timer.id,
      );
      if (!changed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.seriesRecordingUpdated)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToUpdateSeriesRecording)),
      );
    }
  }

  Future<void> _cancelSeriesTimer(SeriesTimerItem timer) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFocusRestoringDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(l10n.cancelSeriesRecordingQuestion, style: const TextStyle(color: Colors.white)),
        content: Text(
          l10n.stopRecordingName(timer.name),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          adaptiveDialogAction(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: Text(l10n.no),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.yesCancel),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _seriesVm.cancelSeriesTimer(timer.id);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.failedToCancelSeriesRecording)),
          );
        }
      }
    }
  }

  void _onItemTap(RecordingItem item) {
    context.push(Destinations.itemDetail.replaceFirst(':itemId', item.id));
  }
}

class _SeriesTimerRow extends StatelessWidget {
  final EdgeInsets insets;
  final List<SeriesTimerItem> timers;
  final ValueChanged<SeriesTimerItem> onItemFocused;
  final ValueChanged<SeriesTimerItem> onItemTap;

  const _SeriesTimerRow({
    required this.insets,
    required this.timers,
    required this.onItemFocused,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 160,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.only(left: insets.left, right: insets.right),
          itemCount: timers.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final timer = timers[index];
            return _SeriesTimerCard(
              timer: timer,
              onFocused: () => onItemFocused(timer),
              onTap: () => onItemTap(timer),
            );
          },
        ),
      ),
    );
  }
}

class _SeriesTimerCard extends StatefulWidget {
  final SeriesTimerItem timer;
  final VoidCallback onFocused;
  final VoidCallback onTap;

  const _SeriesTimerCard({
    required this.timer,
    required this.onFocused,
    required this.onTap,
  });

  @override
  State<_SeriesTimerCard> createState() => _SeriesTimerCardState();
}

class _SeriesTimerCardState extends State<_SeriesTimerCard> with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final cardExpansion =
        GetIt.instance<UserPreferences>().get(UserPreferences.cardFocusExpansion);
    final scale = cardExpansion && showFocusBorder ? 1.08 : 1.0;
    final alpha = showFocusBorder ? 1.0 : 0.75;
    final focusColor = Color(
      GetIt.instance<UserPreferences>().get(UserPreferences.focusColor).colorValue,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: Focus(
        onFocusChange: (focused) {
          setFocused(focused);
          if (focused) widget.onFocused();
        },
        onKeyEvent: (_, event) {
          if (isActivateKey(event)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            child: Opacity(
              opacity: alpha,
              child: SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 200,
                      height: 112,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: AppRadius.circular(4),
                        border: showFocusBorder
                            ? Border.fromBorderSide(
                                ThemeRegistry.active.borders.focusBorder.copyWith(
                                  color: focusColor,
                                ),
                              )
                            : null,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.fiber_smart_record,
                          size: 48,
                          color: showFocusBorder
                              ? Colors.white.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.timer.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (kostvSeriesTimerSubtitle(AppLocalizations.of(context), widget.timer).isNotEmpty)
                      Text(
                        kostvSeriesTimerSubtitle(AppLocalizations.of(context), widget.timer),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingsPillButton extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  const _RecordingsPillButton({
    required this.label,
    this.isActive = false,
    this.onPressed,
    this.focusNode,
  });

  @override
  State<_RecordingsPillButton> createState() => _RecordingsPillButtonState();
}

/// Kos TV: the catalogue's pills: grey, the chosen one a lighter grey and
/// bold, white with dark text while focused or under the mouse.
class _RecordingsPillButtonState extends State<_RecordingsPillButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final phone = PlatformDetection.useMobileUi;
    final lit = _focused || _hovered;
    final Color background;
    final Color ink;
    if (lit) {
      background = kostvLight;
      ink = kostvOnLight;
    } else if (widget.isActive) {
      background = Colors.white.withValues(alpha: 0.28);
      ink = Colors.white;
    } else {
      background = Colors.white.withValues(alpha: 0.10);
      ink = Colors.white.withValues(alpha: 0.8);
    }
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? 1.08 : 1,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: EdgeInsets.symmetric(
              horizontal: phone ? 14 : 18,
              vertical: phone ? 7 : 9,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                if (_focused)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: ink,
                fontSize: phone ? 14 : 16,
                fontWeight: widget.isActive || lit
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingRow extends StatelessWidget {
  final EdgeInsets insets;
  final String title;
  final List<RecordingItem> items;
  final ImageApi imageApi;
  final ValueChanged<RecordingItem> onItemFocused;
  final ValueChanged<RecordingItem> onItemTap;

  const _RecordingRow({
    required this.insets,
    required this.title,
    required this.items,
    required this.imageApi,
    required this.onItemFocused,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return RevealOnFocus(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(left: insets.left, bottom: 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(
                  left: insets.left,
                  right: insets.right,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _RecordingCard(
                    item: item,
                    imageUrl: item.imageUrl(imageApi),
                    onFocused: () => onItemFocused(item),
                    onTap: () => onItemTap(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingCard extends StatefulWidget {
  final RecordingItem item;
  final String? imageUrl;
  final VoidCallback onFocused;
  final VoidCallback onTap;

  const _RecordingCard({
    required this.item,
    required this.imageUrl,
    required this.onFocused,
    required this.onTap,
  });

  @override
  State<_RecordingCard> createState() => _RecordingCardState();
}

class _RecordingCardState extends State<_RecordingCard> with FocusStateMixin {

  @override
  Widget build(BuildContext context) {
    final cardExpansion =
        GetIt.instance<UserPreferences>().get(UserPreferences.cardFocusExpansion);
    final scale = cardExpansion && showFocusBorder ? 1.08 : 1.0;
    final alpha = showFocusBorder ? 1.0 : 0.75;
    final focusColor = Color(
      GetIt.instance<UserPreferences>().get(UserPreferences.focusColor).colorValue,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: Focus(
        onFocusChange: (focused) {
          setFocused(focused);
          if (focused) widget.onFocused();
        },
        onKeyEvent: (_, event) {
          if (isActivateKey(event)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            child: Opacity(
              opacity: alpha,
              child: SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 200,
                      height: 112,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: AppRadius.circular(4),
                        border: showFocusBorder
                            ? Border.fromBorderSide(
                                ThemeRegistry.active.borders.focusBorder.copyWith(
                                  color: focusColor,
                                ),
                              )
                            : null,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildImage(),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: IncompleteRecordingBadge(
                              itemId: widget.item.id,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.item.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.item.subtitle.isNotEmpty)
                      Text(
                        widget.item.subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (widget.imageUrl != null) {
      return OfflineAwareImage(
        imageUrl: widget.imageUrl!,
        fit: BoxFit.cover,
        width: 200,
        height: 112,
      );
    }
    return Center(
      child: Icon(
        Icons.fiber_dvr,
        size: 48,
        color: Colors.white.withValues(alpha: 0.2),
      ),
    );
  }
}
