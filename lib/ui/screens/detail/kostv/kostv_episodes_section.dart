import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/util/season_queue_context.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../data/models/aggregated_item.dart';
import '../../../../data/services/stremfin/kostv_series_gaps.dart';
import '../../../../data/viewmodels/item_detail_view_model.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../preference/user_preferences.dart';
import '../../../navigation/destinations.dart';
import '../../../widgets/focus/context_menu_sheet.dart';
import '../../../widgets/focus/focusable_wrapper.dart';
import '../../../widgets/focus/locked_focus_row.dart';
import '../../../widgets/kostv_missing_episodes.dart';
import '../../../widgets/scroll_edge_arrows.dart';
import '../../../widgets/sliding_pill_tabs.dart';
import '../detail_layout_metrics.dart';
import '../minimalist/widgets/minimalist_episode_card.dart';
import '../minimalist/widgets/minimalist_episodes_section.dart';
import '../play_item_on_screen.dart';
import 'kostv_detail_buttons.dart';

const double _kTabsToRail = 18;
const double _kAskToRail = 16;

/// Kos TV: the seasons and their episodes, with what the home server lacks.
///
/// The seasons it has none of get their own tab, and a season's missing
/// episodes sit greyed in their place in the rail: choosing one opens what
/// it can do (ask for it, or when it premieres). Over a season missing
/// several, or not at home at all, a bar asks for them in one go.
class KostvEpisodesSection extends StatefulWidget {
  final ItemDetailViewModel viewModel;
  final UserPreferences prefs;
  final bool landscape;
  final double? maxHeight;

  /// The top of the section: the tabs, the bar or the rail, whichever is
  /// first on screen.
  final FocusNode? episodesFocusNode;
  final bool Function(bool isUp)? onVerticalNavigation;

  const KostvEpisodesSection({
    super.key,
    required this.viewModel,
    required this.prefs,
    required this.landscape,
    this.maxHeight,
    this.episodesFocusNode,
    this.onVerticalNavigation,
  });

  @override
  State<KostvEpisodesSection> createState() => _KostvEpisodesSectionState();
}

class _KostvEpisodesSectionState extends State<KostvEpisodesSection> {
  final _railKey = GlobalKey<LockedFocusRowState<KostvEpisodeEntry>>();
  final _railController = ScrollController();
  final _askNode = FocusNode(debugLabel: 'kostv-season-ask');
  KostvSeriesGapsController? _gaps;
  int? _selectedSeason;
  bool _loadStarted = false;

  ItemDetailViewModel get _vm => widget.viewModel;
  bool get _isSeries => _vm.item?.type == 'Series';
  bool get _isSeason => _vm.item?.type == 'Season';
  bool get _isEpisode => _vm.item?.type == 'Episode';

  @override
  void initState() {
    super.initState();
    _beginEpisodesLoad();
    final item = _vm.item;
    if (item != null) {
      _gaps = KostvSeriesGapsController()..addListener(_onGaps);
      unawaited(_gaps!.loadFor(item));
    }
  }

  void _onGaps() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gaps?.removeListener(_onGaps);
    _gaps?.dispose();
    _railController.dispose();
    _askNode.dispose();
    super.dispose();
  }

  void _beginEpisodesLoad() {
    if (_loadStarted || !(_isSeries || _isEpisode)) return;
    _loadStarted = true;
    final viewModel = _vm;
    if (viewModel.seriesEpisodes.isNotEmpty) return;
    unawaited(
      viewModel.loadAllSeriesEpisodes().whenComplete(() {
        if (!mounted || !identical(_vm, viewModel)) return;
        setState(() {});
      }),
    );
  }

  List<AggregatedItem> get _allEpisodes =>
      _isSeason ? _vm.episodes : _vm.seriesEpisodes;

  String _seasonLabel(AppLocalizations l10n, int number) =>
      number == 0 ? l10n.specials : l10n.seasonNumber(number);

  void _selectSeason(int number) {
    if (_selectedSeason == number) return;
    setState(() => _selectedSeason = number);
    if (_railController.hasClients) _railController.jumpTo(0);
  }

  void _openEpisode(BuildContext context, AggregatedItem episode) {
    if (episode.id == _vm.item?.id) {
      playItemOnScreen(context);
      return;
    }
    final location = Destinations.item(
      episode.id,
      serverId: episode.serverId,
      seasonContext: seasonContextParam(
        contextSeasonId: _isSeason ? _vm.item?.id : null,
        episodeSeasonId: episode.seasonId,
      ),
    );
    _isEpisode ? context.pushReplacement(location) : context.push(location);
  }

  void _openEntry(BuildContext context, KostvEpisodeEntry entry) {
    if (entry.episode case final episode?) {
      _openEpisode(context, episode);
    } else if (entry.ghost case final ghost?) {
      showKostvGhostSheet(context, controller: _gaps!, ghost: ghost);
    }
  }

  void _entryMenu(BuildContext context, KostvEpisodeEntry entry) {
    if (entry.episode case final episode?) {
      showContextMenu(context, episode, onChanged: () => setState(() {}));
    } else {
      _openEntry(context, entry);
    }
  }

  double _titleBlockHeight(BuildContext context, double cardWidth) {
    final line =
        MediaQuery.textScalerOf(context)
            .scale(MinimalistEpisodeCard.titleFontSize(cardWidth)) *
        MinimalistEpisodeCard.titleLineHeight;
    return MinimalistEpisodeCard.titleGap +
        line * MinimalistEpisodeCard.titleMaxLines;
  }

  double? _stillBudget(BuildContext context, bool showTabs, bool showAsk) {
    final budget = widget.maxHeight;
    if (budget == null || !budget.isFinite) return null;
    final chrome =
        (showTabs ? SlidingPillTabs.height + _kTabsToRail : 0.0) +
        (showAsk ? _askHeight + _kAskToRail : 0.0);
    return budget - chrome - _titleBlockHeight(context, double.infinity);
  }

  double get _askHeight => widget.landscape ? 64 : 56;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = _allEpisodes;
    final controller = _gaps;
    final gaps = controller == null || all.isEmpty
        ? KostvSeriesGaps.none
        : controller.gapsFor(all);
    final atHome = all
        .map((episode) => episode.parentIndexNumber)
        .whereType<int>()
        .toSet();
    // A season's own page only lists that season.
    final notAtHome = _isSeason
        ? const <int>{}
        : {for (final season in gaps.seasonsNotAtHome) season.number};
    final seasons = {...atHome, ...notAtHome}.toList()..sort();
    if (seasons.isEmpty && all.isEmpty) return const SizedBox.shrink();

    final arrivedIn = _isEpisode
        ? _vm.item?.parentIndexNumber
        : _vm.nextUp?.parentIndexNumber;
    final fallback = arrivedIn != null && seasons.contains(arrivedIn)
        ? arrivedIn
        : (atHome.isEmpty
              ? (seasons.isEmpty ? null : seasons.first)
              : (atHome.where((n) => n > 0).toList()..sort()).firstOrNull ??
                    atHome.first);
    final selected =
        _selectedSeason != null && seasons.contains(_selectedSeason)
        ? _selectedSeason!
        : fallback;

    final episodes = selected == null
        ? all
        : (all.where((e) => e.parentIndexNumber == selected).toList()
            ..sort(ItemDetailViewModel.compareEpisodes));
    final seasonGaps = selected == null ? null : gaps.season(selected);
    final entries = seasonGaps == null
        ? <KostvEpisodeEntry>[
            for (final e in episodes) (episode: e, ghost: null),
          ]
        : seasonGaps.merge(episodes);
    final ask = seasonGaps == null || controller == null
        ? null
        : KostvSeasonAsk.of(context, seasonGaps, controller);
    final askFocus = ask?.button != null && ask!.enabled;

    final showTabs = seasons.length > 1;
    final hasRail = entries.isNotEmpty;

    void toRail() => _railKey.currentState?.requestFocusAt(0);
    bool down(bool fromTabs) {
      if (fromTabs && askFocus) {
        _askNode.requestFocus();
        return true;
      }
      if (hasRail) {
        toRail();
        return true;
      }
      return widget.onVerticalNavigation?.call(false) ?? false;
    }

    final topNode = widget.episodesFocusNode;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = minimalistEpisodeCardWidth(
          constraints.maxWidth,
          landscape: widget.landscape,
          maxStillHeight: _stillBudget(context, showTabs, ask != null),
          prefs: widget.prefs,
        );
        final railHeight =
            cardWidth * 9 / 16 + _titleBlockHeight(context, cardWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTabs) ...[
              SlidingPillTabs(
                key: const ValueKey('kostv-season-tabs'),
                labels: [for (final n in seasons) _seasonLabel(l10n, n)],
                selectedIndex: selected == null ? 0 : seasons.indexOf(selected),
                onChanged: (index) => _selectSeason(seasons[index]),
                focusNode: topNode,
                onVerticalNavigation: (isUp) {
                  if (!isUp) return down(true);
                  return widget.onVerticalNavigation?.call(true) ?? false;
                },
              ),
              const SizedBox(height: _kTabsToRail),
            ],
            if (ask != null) ...[
              _AskBar(
                ask: ask,
                height: _askHeight,
                compact: !widget.landscape,
                focusNode: askFocus
                    ? (showTabs ? _askNode : (topNode ?? _askNode))
                    : null,
                onSelect: askFocus && selected != null
                    ? () => kostvAskMissing(
                        context,
                        controller!,
                        season: selected,
                      )
                    : null,
                onUp: () {
                  if (showTabs) {
                    topNode?.requestFocus();
                  } else {
                    widget.onVerticalNavigation?.call(true);
                  }
                },
                onDown: () => down(false),
              ),
              if (hasRail) const SizedBox(height: _kAskToRail),
            ],
            if (hasRail)
              SizedBox(
                key: const ValueKey('kostv-episode-rail'),
                height: railHeight,
                child: ScrollEdgeArrows(
                  controller: _railController,
                  child: LockedFocusRow<KostvEpisodeEntry>(
                    key: _railKey,
                    items: entries,
                    itemKey: (entry, _) => entry.episode != null
                        ? '${entry.episode!.serverId}|${entry.episode!.id}'
                        : 'ghost-${entry.ghost!.season}-${entry.ghost!.number}',
                    hubKey: 'kostv-episodes-${_vm.item?.id ?? ''}-$selected',
                    itemExtent: cardWidth,
                    itemSpacing: minimalistEpisodeRailGap(
                      landscape: widget.landscape,
                    ),
                    height: railHeight,
                    controller: _railController,
                    focusNode: showTabs || askFocus ? null : topNode,
                    clipBehavior: Clip.none,
                    onTap: (_, entry) => _openEntry(context, entry),
                    onLongPress: (_, entry) => _entryMenu(context, entry),
                    onVerticalNavigation: (isUp) {
                      if (isUp && askFocus) {
                        (showTabs ? _askNode : (topNode ?? _askNode))
                            .requestFocus();
                        return true;
                      }
                      if (isUp && showTabs) {
                        topNode?.requestFocus();
                        return true;
                      }
                      return widget.onVerticalNavigation?.call(isUp) ?? false;
                    },
                    itemBuilder: (context, entry, index, isFocused) {
                      final ghost = entry.ghost;
                      if (ghost != null) {
                        return _GhostCard(
                          ghost: ghost,
                          width: cardWidth,
                          isFocused: isFocused,
                          onTap: () => _openEntry(context, entry),
                        );
                      }
                      final episode = entry.episode!;
                      return MinimalistEpisodeCard(
                        episode: episode,
                        width: cardWidth,
                        isFocused: isFocused,
                        isCurrent: _isEpisode && episode.id == _vm.item?.id,
                        imageUrl: minimalistEpisodeImageUrl(
                          episode,
                          _vm,
                          prefs: widget.prefs,
                          cardWidth: cardWidth,
                          devicePixelRatio: MediaQuery.devicePixelRatioOf(
                            context,
                          ),
                        ),
                        onTap: () => _openEpisode(context, episode),
                        onLongPress: () => showContextMenu(
                          context,
                          episode,
                          onChanged: () => setState(() {}),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The bar over a season missing several episodes, or not at home: what's
/// missing, and the button that asks for it.
class _AskBar extends StatelessWidget {
  const _AskBar({
    required this.ask,
    required this.height,
    required this.compact,
    required this.onUp,
    required this.onDown,
    this.focusNode,
    this.onSelect,
  });

  final KostvSeasonAsk ask;
  final double height;
  final bool compact;
  final FocusNode? focusNode;
  final VoidCallback? onSelect;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFFF3F5FA);
    Widget bar(bool focused) {
      final button = ask.button;
      final text = Text(
        ask.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ink.withValues(alpha: 0.9),
          fontSize: compact ? 15 : 17,
          fontWeight: FontWeight.w600,
        ),
      );
      final Widget? trailing = button != null
          ? Container(
              alignment: compact ? Alignment.center : null,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 20,
                vertical: compact ? 11 : 11,
              ),
              decoration: BoxDecoration(
                gradient: ask.enabled ? kostvGradient : null,
                color: ask.enabled ? null : Colors.white.withValues(alpha: 0.1),
                borderRadius: AppRadius.circular(height),
              ),
              child: Text(
                button,
                style: TextStyle(
                  color: ask.enabled
                      ? Colors.white
                      : ink.withValues(alpha: 0.5),
                  fontSize: compact ? 15 : 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : switch (ask.status) {
              final String status => Padding(
                padding: EdgeInsets.only(right: compact ? 0 : 12),
                child: Text(
                  status,
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.7),
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _ => null,
            };
      final label = Row(
        children: [
          Icon(ask.icon, color: ink.withValues(alpha: 0.7), size: 22),
          SizedBox(width: compact ? 10 : 14),
          Expanded(child: text),
        ],
      );
      return AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: BoxConstraints(minHeight: height),
        padding: compact
            ? const EdgeInsets.all(12)
            : const EdgeInsets.fromLTRB(22, 8, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: focused ? 0.12 : 0.06),
          borderRadius: AppRadius.circular(compact ? 22 : height / 2),
          border: Border.all(
            color: focused ? kostvViolet : Colors.white.withValues(alpha: 0.1),
            width: focused ? 2 : 1,
          ),
        ),
        // On a phone the button goes under the text, the full width.
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: label,
                  ),
                  if (trailing != null) ...[
                    const SizedBox(height: 10),
                    trailing,
                  ],
                ],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  ?trailing,
                ],
              ),
      );
    }

    if (focusNode == null) return bar(false);
    return FocusableWrapper(
      focusNode: focusNode,
      onSelect: onSelect,
      onNavigateUp: onUp,
      onNavigateDown: onDown,
      borderRadius: compact ? 22 : height / 2,
      disableScale: true,
      suppressFocusGlow: true,
      autoScroll: true,
      child: Builder(builder: (context) => bar(Focus.of(context).hasFocus)),
    );
  }
}

/// An episode the home server lacks, greyed in its place in the rail.
class _GhostCard extends StatelessWidget {
  const _GhostCard({
    required this.ghost,
    required this.width,
    required this.isFocused,
    required this.onTap,
  });

  final KostvGhostEpisode ghost;
  final double width;
  final bool isFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = AppColorScheme.onSurface;
    final badge = KostvGhostTexts.badge(context, ghost);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: isFocused ? 1 : 0.75,
                  child: KostvGhostThumb(
                    ghost: ghost,
                    width: width,
                    radius: 14,
                    ink: ink,
                  ),
                ),
                if (badge != null)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: AppRadius.circular(10),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.circular(14),
                        border: Border.all(
                          color: isFocused ? ink : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MinimalistEpisodeCard.titleGap),
            Flexible(
              child: Text(
                KostvGhostTexts.title(context, ghost),
                maxLines: MinimalistEpisodeCard.titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w700,
                  fontSize: MinimalistEpisodeCard.titleFontSize(width),
                  height: MinimalistEpisodeCard.titleLineHeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
