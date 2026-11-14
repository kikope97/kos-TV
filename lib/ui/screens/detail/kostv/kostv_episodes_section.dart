import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/util/season_queue_context.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../data/models/aggregated_item.dart';
import '../../../../data/services/stremfin/kostv_series_gaps.dart';
import '../../../../data/viewmodels/item_detail_view_model.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../preference/user_preferences.dart';
import '../../../../util/playback_time_label.dart';
import '../../../navigation/destinations.dart';
import '../../../widgets/focus/context_menu_sheet.dart';
import '../../../widgets/focus/focusable_wrapper.dart';
import '../../../widgets/focus/hub_focus_memory.dart';
import '../../../widgets/focus/locked_focus_row.dart';
import '../../../widgets/kostv_missing_episodes.dart';
import '../../../widgets/offline_aware_image.dart';
import '../../../widgets/scroll_edge_arrows.dart';
import '../minimalist/widgets/minimalist_episodes_section.dart';
import '../play_item_on_screen.dart';
import 'kostv_detail_buttons.dart';

const _ink = Color(0xFFF3F5FA);
const _fast = Duration(milliseconds: 160);

/// Kos TV: the seasons and their episodes, with what the home server lacks.
///
/// The season names sit over the episodes as large titles, the one shown
/// underlined in the brand's colours, and a line under them says how many
/// there are, the year and how many are watched, with what's missing and the
/// button that asks for it. On a TV or a computer the episodes run in a row
/// of cards with their still, length, a line of what happens and, on the one
/// to watch next, how much is left; the row opens on that one. On a phone
/// they're a list down the page. The episodes the home server lacks sit in
/// their place with a dotted edge.
class KostvEpisodesSection extends StatefulWidget {
  final ItemDetailViewModel viewModel;
  final UserPreferences prefs;
  final bool landscape;
  final double? maxHeight;

  /// The top of the section: the season names, the ask button or the row,
  /// whichever is first on screen.
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

  /// The row's hub that was last put on its episode to watch.
  String? _placedHub;

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

  /// The episode to watch next in [entries]: the one the server says, else
  /// the first not watched after one that is. None in a season not started.
  int _nextIndex(List<KostvEpisodeEntry> entries) {
    final nextId = _vm.nextUp?.id;
    if (nextId != null) {
      final at = entries.indexWhere((e) => e.episode?.id == nextId);
      if (at >= 0) return at;
    }
    final lastSeen = entries.lastIndexWhere(
      (e) => e.episode?.isPlayed ?? false,
    );
    if (lastSeen < 0) return -1;
    return entries.indexWhere(
      (e) => e.episode != null && !e.episode!.isPlayed,
      lastSeen,
    );
  }

  /// The row opens on the episode to watch, once per season shown.
  void _placeRail(String hub, int index, double step) {
    if (_placedHub == hub) return;
    _placedHub = hub;
    final at = index <= 0 ? 0 : index;
    if (at > 0 && HubFocusMemory.peek(hub) == null) {
      HubFocusMemory.set(hub, at);
    }
    // Another season's row starts at its own place, not where the last one
    // was left.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_railController.hasClients) return;
      final position = _railController.position;
      _railController.jumpTo((at * step).clamp(0.0, position.maxScrollExtent));
    });
  }

  /// «10 episodios · 2023 · Has visto 5 de 10».
  String _summary(
    AppLocalizations l10n,
    List<KostvEpisodeEntry> entries,
    List<AggregatedItem> episodes,
  ) {
    final years = [for (final e in episodes) ?e.premiereDate?.year];
    final seen = episodes.where((e) => e.isPlayed).length;
    return [
      l10n.kostvSeasonEpisodeCount(entries.length),
      if (years.isNotEmpty) '${years.reduce(math.min)}',
      if (episodes.isNotEmpty) l10n.kostvSeasonWatched(seen, entries.length),
    ].join('  ·  ');
  }

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
    final next = _nextIndex(entries);
    final summary = _summary(l10n, entries, episodes);

    final labels = [for (final n in seasons) _seasonLabel(l10n, n)];
    final selectedIndex = selected == null ? 0 : seasons.indexOf(selected);
    final missing = {
      for (final (i, n) in seasons.indexed)
        if (notAtHome.contains(n)) i,
    };

    return widget.landscape
        ? _landscape(
            context,
            l10n,
            labels: labels,
            missing: missing,
            selectedIndex: selectedIndex,
            seasons: seasons,
            selected: selected,
            entries: entries,
            ask: ask,
            next: next,
            summary: summary,
          )
        : _portrait(
            context,
            l10n,
            labels: labels,
            missing: missing,
            selectedIndex: selectedIndex,
            seasons: seasons,
            selected: selected,
            entries: entries,
            ask: ask,
            next: next,
            summary: summary,
          );
  }

  // ------------------------------------------------------------ TV and web

  Widget _landscape(
    BuildContext context,
    AppLocalizations l10n, {
    required List<String> labels,
    required Set<int> missing,
    required int selectedIndex,
    required List<int> seasons,
    required int? selected,
    required List<KostvEpisodeEntry> entries,
    required KostvSeasonAsk? ask,
    required int next,
    required String summary,
  }) {
    final controller = _gaps;
    final showTabs = seasons.length > 1;
    final askFocus = ask?.button != null && ask!.enabled;
    final hasRail = entries.isNotEmpty;
    final topNode = widget.episodesFocusNode;
    final askNode = showTabs ? _askNode : (topNode ?? _askNode);

    void toRail() => _railKey.currentState?.requestFocusAt(
      HubFocusMemory.getForHub(_hub(selected), entries.length),
    );
    void fromTabsDown() {
      if (askFocus) {
        askNode.requestFocus();
      } else if (hasRail) {
        toRail();
      } else {
        widget.onVerticalNavigation?.call(false);
      }
    }

    void up(bool fromRail) {
      if (fromRail && askFocus) {
        askNode.requestFocus();
      } else if (showTabs) {
        topNode?.requestFocus();
      } else {
        widget.onVerticalNavigation?.call(true);
      }
    }

    final scale = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth * 0.27).clamp(240.0, 420.0);
        const gap = 22.0;
        final railHeight =
            cardWidth * 9 / 16 +
            12 +
            scale.scale(18) * 1.3 +
            6 +
            scale.scale(14) * 1.4 * 2 +
            14;
        final hub = _hub(selected);
        if (hasRail) _placeRail(hub, next, cardWidth + gap);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTabs) ...[
              _SeasonTitles(
                labels: labels,
                missing: missing,
                toAsk: l10n.kostvSeasonToAsk,
                selectedIndex: selectedIndex,
                focusNode: topNode,
                onChanged: (index) => _selectSeason(seasons[index]),
                onUp: () => widget.onVerticalNavigation?.call(true),
                onDown: fromTabsDown,
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.72),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (ask != null)
                  _InlineAsk(
                    ask: ask,
                    focusNode: askFocus ? askNode : null,
                    onSelect: askFocus && selected != null
                        ? () => kostvAskMissing(
                            context,
                            controller!,
                            season: selected,
                          )
                        : null,
                    onUp: () => up(false),
                    onDown: () => hasRail
                        ? toRail()
                        : widget.onVerticalNavigation?.call(false),
                  ),
              ],
            ),
            if (hasRail) ...[
              const SizedBox(height: 20),
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
                    hubKey: hub,
                    itemExtent: cardWidth,
                    itemSpacing: gap,
                    height: railHeight,
                    padding: const EdgeInsets.only(top: 6),
                    controller: _railController,
                    focusNode: showTabs || askFocus ? null : topNode,
                    clipBehavior: Clip.none,
                    onTap: (_, entry) => _openEntry(context, entry),
                    onLongPress: (_, entry) => _entryMenu(context, entry),
                    onVerticalNavigation: (isUp) {
                      if (isUp && (askFocus || showTabs)) {
                        up(true);
                        return true;
                      }
                      return widget.onVerticalNavigation?.call(isUp) ?? false;
                    },
                    itemBuilder: (context, entry, index, isFocused) {
                      if (entry.ghost case final ghost?) {
                        return _GhostCard(
                          ghost: ghost,
                          width: cardWidth,
                          isFocused: isFocused,
                          canAsk: ghost.canAsk && !controller!.atLimit,
                          onTap: () => _openEntry(context, entry),
                        );
                      }
                      final episode = entry.episode!;
                      return _EpisodeCard(
                        episode: episode,
                        width: cardWidth,
                        isFocused: isFocused,
                        isNext: index == next,
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
                        onLongPress: () => _entryMenu(context, entry),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _hub(int? season) => 'kostv-episodes-${_vm.item?.id ?? ''}-$season';

  // ----------------------------------------------------------------- phone

  Widget _portrait(
    BuildContext context,
    AppLocalizations l10n, {
    required List<String> labels,
    required Set<int> missing,
    required int selectedIndex,
    required List<int> seasons,
    required int? selected,
    required List<KostvEpisodeEntry> entries,
    required KostvSeasonAsk? ask,
    required int next,
    required String summary,
  }) {
    final controller = _gaps;
    final askFocus = ask?.button != null && ask!.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (seasons.length > 1) ...[
          _SeasonChips(
            labels: labels,
            missing: missing,
            toAsk: l10n.kostvSeasonToAsk,
            selectedIndex: selectedIndex,
            onChanged: (index) => _selectSeason(seasons[index]),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          summary,
          style: TextStyle(color: _ink.withValues(alpha: 0.65), fontSize: 14),
        ),
        if (ask != null) ...[
          const SizedBox(height: 12),
          _AskBar(
            ask: ask,
            height: 56,
            compact: true,
            onSelect: askFocus && selected != null
                ? () => kostvAskMissing(context, controller!, season: selected)
                : null,
            onUp: () {},
            onDown: () {},
          ),
        ],
        const SizedBox(height: 6),
        for (final (index, entry) in entries.indexed)
          if (entry.ghost case final ghost?)
            _GhostRow(
              ghost: ghost,
              canAsk: ghost.canAsk && !controller!.atLimit,
              onTap: () => _openEntry(context, entry),
            )
          else
            _EpisodeRow(
              episode: entry.episode!,
              isNext: index == next,
              imageUrl: minimalistEpisodeImageUrl(
                entry.episode!,
                _vm,
                prefs: widget.prefs,
                cardWidth: 150,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
              onTap: () => _openEpisode(context, entry.episode!),
              onLongPress: () => _entryMenu(context, entry),
            ),
      ],
    );
  }
}

// ------------------------------------------------------------------ pieces

TextStyle _outfit(double size, Color color) => TextStyle(
  fontFamily: 'Outfit',
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: color,
  height: 1.1,
);

/// The small «Para pedir» beside a season that isn't at home.
class _ToAskTag extends StatelessWidget {
  const _ToAskTag(this.text, {this.size = 12});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: kostvViolet.withValues(alpha: 0.18),
      borderRadius: AppRadius.circular(9),
      border: Border.all(color: kostvViolet.withValues(alpha: 0.5)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: const Color(0xFFC9B8FF),
        fontSize: size,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// The season names as large titles, the one shown underlined in the
/// brand's colours. Left and right change season as they pass, as the tabs
/// they replace did.
class _SeasonTitles extends StatefulWidget {
  const _SeasonTitles({
    required this.labels,
    required this.missing,
    required this.toAsk,
    required this.selectedIndex,
    required this.onChanged,
    required this.onUp,
    required this.onDown,
    this.focusNode,
  });

  final List<String> labels;
  final Set<int> missing;
  final String toAsk;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final FocusNode? focusNode;

  @override
  State<_SeasonTitles> createState() => _SeasonTitlesState();
}

class _SeasonTitlesState extends State<_SeasonTitles> {
  final _scroll = ScrollController();
  late List<GlobalKey> _keys;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _keys = [for (final _ in widget.labels) GlobalKey()];
  }

  @override
  void didUpdateWidget(covariant _SeasonTitles old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) {
      _keys = [for (final _ in widget.labels) GlobalKey()];
    }
    if (old.selectedIndex != widget.selectedIndex) _reveal();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = widget.selectedIndex;
      if (!mounted || at < 0 || at >= _keys.length) return;
      final ctx = _keys[at].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final at = widget.selectedIndex;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (at > 0) widget.onChanged(at - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (at + 1 < widget.labels.length) widget.onChanged(at + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select) {
      widget.onDown();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (has) => setState(() => _focused = has),
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final (index, label) in widget.labels.indexed)
              Padding(
                key: _keys[index],
                padding: const EdgeInsets.only(right: 22),
                child: _title(index, label),
              ),
          ],
        ),
      ),
    );
  }

  Widget _title(int index, String label) {
    final on = index == widget.selectedIndex;
    final missing = widget.missing.contains(index);
    final color = on ? _ink : _ink.withValues(alpha: missing ? 0.32 : 0.5);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onChanged(index),
        child: AnimatedContainer(
          duration: _fast,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          decoration: BoxDecoration(
            borderRadius: AppRadius.circular(12),
            border: Border.all(
              color: on && _focused ? kostvViolet : Colors.transparent,
              width: 2,
            ),
            color: on && _focused
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: _outfit(26, color)),
                  if (missing) ...[
                    const SizedBox(width: 8),
                    _ToAskTag(widget.toAsk),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              AnimatedOpacity(
                duration: _fast,
                opacity: on ? 1 : 0,
                child: Container(
                  height: 4,
                  width: 60,
                  decoration: BoxDecoration(
                    color: _ink,
                    borderRadius: AppRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// On a phone, the seasons as buttons in a strip that slides sideways.
class _SeasonChips extends StatelessWidget {
  const _SeasonChips({
    required this.labels,
    required this.missing,
    required this.toAsk,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final Set<int> missing;
  final String toAsk;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (index, label) in labels.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(index),
                child: AnimatedContainer(
                  duration: _fast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: index == selectedIndex
                        ? _ink
                        : (missing.contains(index)
                              ? Colors.transparent
                              : Colors.white.withValues(alpha: 0.08)),
                    borderRadius: AppRadius.circular(20),
                    border: missing.contains(index) && index != selectedIndex
                        ? Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          )
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: index == selectedIndex
                              ? const Color(0xFF111111)
                              : _ink.withValues(
                                  alpha: missing.contains(index) ? 0.55 : 0.8,
                                ),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (missing.contains(index)) ...[
                        const SizedBox(width: 6),
                        _ToAskTag(toAsk, size: 11),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// «Faltan 2 episodios · Solicitar los 2», at the end of the line under the
/// season names.
class _InlineAsk extends StatelessWidget {
  const _InlineAsk({
    required this.ask,
    required this.onUp,
    required this.onDown,
    this.focusNode,
    this.onSelect,
  });

  final KostvSeasonAsk ask;
  final FocusNode? focusNode;
  final VoidCallback? onSelect;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final button = ask.button;
    Widget pill(bool focused) => AnimatedContainer(
      duration: _fast,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: kostvGlass(lit: focused, enabled: ask.enabled),
      child: Text(
        button!,
        style: TextStyle(
          color: kostvGlassInk(lit: focused, enabled: ask.enabled),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ask.icon, color: _ink.withValues(alpha: 0.6), size: 20),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            ask.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink.withValues(alpha: 0.85),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 14),
        if (button != null)
          focusNode == null
              ? pill(false)
              : FocusableWrapper(
                  focusNode: focusNode,
                  onSelect: onSelect,
                  onNavigateUp: onUp,
                  onNavigateDown: onDown,
                  borderRadius: 22,
                  disableScale: true,
                  suppressFocusGlow: true,
                  child: Builder(
                    builder: (context) => pill(Focus.of(context).hasFocus),
                  ),
                )
        else if (ask.status case final status?)
          Text(
            status,
            style: TextStyle(
              color: _ink.withValues(alpha: 0.7),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// A small dark label over a still.
class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.gradient = false, this.size = 13});
  final String text;
  final bool gradient;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: gradient ? kostvLight : Colors.black.withValues(alpha: 0.62),
      borderRadius: AppRadius.circular(9),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: gradient ? kostvOnLight : Colors.white,
        fontSize: size,
        fontWeight: gradient ? FontWeight.w800 : FontWeight.w700,
        letterSpacing: gradient ? 0.8 : 0,
      ),
    ),
  );
}

/// What an episode's corner says: how long it is, or how much is left.
String? _lengthOf(AppLocalizations l10n, AggregatedItem episode) {
  final runtime = episode.runtime;
  if (runtime == null || runtime < const Duration(minutes: 1)) return null;
  final position = episode.playbackPosition ?? Duration.zero;
  if (position > Duration.zero && position < runtime && !episode.isPlayed) {
    final left = runtime - position;
    return l10n.kostvDetailLeft(
      formatRuntimeShort(Duration(minutes: (left.inSeconds / 60).ceil())),
    );
  }
  return formatRuntimeShort(runtime);
}

double? _progressOf(AggregatedItem episode) {
  if (episode.isPlayed) return null;
  final runtime = episode.runtime;
  final position = episode.playbackPosition;
  if (runtime == null || position == null || runtime <= Duration.zero) {
    return null;
  }
  if (position <= Duration.zero || position >= runtime) return null;
  return position.inMilliseconds / runtime.inMilliseconds;
}

/// The still with its number, whether it's watched, its length and the bar
/// of how far it's got.
class _Still extends StatelessWidget {
  const _Still({
    required this.episode,
    required this.imageUrl,
    required this.radius,
    this.isNext = false,
    this.compact = false,
  });

  final AggregatedItem episode;
  final String? imageUrl;
  final double radius;
  final bool isNext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final number = episode.indexNumber;
    final length = compact ? null : _lengthOf(l10n, episode);
    final progress = _progressOf(episode);
    final url = imageUrl;
    final placeholder = ColoredBox(
      color: Colors.white.withValues(alpha: 0.06),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: _ink.withValues(alpha: 0.3),
          size: 26,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: AppRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url == null || url.isEmpty)
            placeholder
          else
            ColorFiltered(
              // Watched ones step back a little.
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: episode.isPlayed ? 0.22 : 0),
                BlendMode.darken,
              ),
              child: OfflineAwareImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
            ),
          if (number != null && !compact)
            Positioned(left: 10, top: 10, child: _Chip('$number', size: 14)),
          if (episode.isPlayed)
            Positioned(
              right: compact ? 6 : 10,
              top: compact ? 6 : 10,
              child: Container(
                width: compact ? 20 : 24,
                height: compact ? 20 : 24,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: compact ? 14 : 16,
                  color: const Color(0xFF7FE0A2),
                ),
              ),
            ),
          if (isNext && !compact)
            Positioned(
              left: 10,
              bottom: 12,
              child: _Chip(l10n.kostvEpisodeNext, gradient: true, size: 12),
            ),
          if (length != null)
            Positioned(right: 10, bottom: 12, child: _Chip(length)),
          if (progress != null) ...[
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 5,
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.2)),
            ),
            Positioned.fill(
              top: null,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(height: 5, color: _ink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// An episode in the row: the still, its title and a line of what happens.
class _EpisodeCard extends StatefulWidget {
  const _EpisodeCard({
    required this.episode,
    required this.width,
    required this.isFocused,
    required this.isNext,
    required this.imageUrl,
    required this.onTap,
    required this.onLongPress,
  });

  final AggregatedItem episode;
  final double width;
  final bool isFocused;
  final bool isNext;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.isFocused || _hovered;
    final overview = widget.episode.overview?.trim();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: widget.isFocused ? 1.04 : 1,
                duration: _fast,
                child: AnimatedContainer(
                  duration: _fast,
                  width: widget.width,
                  height: widget.width * 9 / 16,
                  foregroundDecoration: BoxDecoration(
                    borderRadius: AppRadius.circular(16),
                    border: Border.all(
                      color: lit ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.circular(16),
                    boxShadow: [
                      if (widget.isFocused)
                        BoxShadow(
                          color: kostvViolet.withValues(alpha: 0.5),
                          blurRadius: 26,
                        ),
                    ],
                  ),
                  child: _Still(
                    episode: widget.episode,
                    imageUrl: widget.imageUrl,
                    radius: 16,
                    isNext: widget.isNext,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.episode.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              if (overview != null && overview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  overview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink.withValues(alpha: lit ? 0.75 : 0.58),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The dotted place of an episode the home server lacks, with its number and
/// the button that asks for it.
class _GhostThumb extends StatelessWidget {
  const _GhostThumb({
    required this.ghost,
    required this.canAsk,
    required this.radius,
    this.compact = false,
  });

  final KostvGhostEpisode ghost;
  final bool canAsk;
  final double radius;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final badge = KostvGhostTexts.badge(context, ghost);
    return CustomPaint(
      foregroundPainter: _DashedBorder(radius: radius),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kostvViolet.withValues(alpha: 0.12),
              Colors.white.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${ghost.number}',
                style: _outfit(compact ? 26 : 34, _ink.withValues(alpha: 0.4)),
              ),
              if (!compact && badge != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: kostvGlass(enabled: canAsk, radius: 16),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: kostvGlassInk(enabled: canAsk),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.radius});
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.8),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.radius != radius;
}

/// A missing episode in the row.
class _GhostCard extends StatelessWidget {
  const _GhostCard({
    required this.ghost,
    required this.width,
    required this.isFocused,
    required this.canAsk,
    required this.onTap,
  });

  final KostvGhostEpisode ghost;
  final double width;
  final bool isFocused;
  final bool canAsk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isFocused ? 1.04 : 1,
                duration: _fast,
                child: Container(
                  width: width,
                  height: width * 9 / 16,
                  foregroundDecoration: BoxDecoration(
                    borderRadius: AppRadius.circular(16),
                    border: Border.all(
                      color: isFocused ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: _GhostThumb(ghost: ghost, canAsk: canAsk, radius: 16),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                KostvGhostTexts.title(context, ghost),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.6),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                KostvGhostTexts.note(context, ghost),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.5),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// On a phone, an episode as a line: the still to the left, and its number
/// and title, length and what happens to the right.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.isNext,
    required this.imageUrl,
    required this.onTap,
    required this.onLongPress,
  });

  final AggregatedItem episode;
  final bool isNext;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final number = episode.indexNumber;
    final length = _lengthOf(l10n, episode);
    final overview = episode.overview?.trim();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              height: 84,
              child: _Still(
                episode: episode,
                imageUrl: imageUrl,
                radius: 12,
                compact: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isNext) ...[
                    _Chip(l10n.kostvEpisodeNext, gradient: true, size: 10.5),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    number == null ? episode.name : '$number. ${episode.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (length != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      length,
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  if (!isNext && overview != null && overview.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.68),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// On a phone, a missing episode as a line, with its button.
class _GhostRow extends StatelessWidget {
  const _GhostRow({
    required this.ghost,
    required this.canAsk,
    required this.onTap,
  });

  final KostvGhostEpisode ghost;
  final bool canAsk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = KostvGhostTexts.badge(context, ghost);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              height: 84,
              child: _GhostThumb(
                ghost: ghost,
                canAsk: canAsk,
                radius: 12,
                compact: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${ghost.number}. ${KostvGhostTexts.title(context, ghost)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.6),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    KostvGhostTexts.shortNote(context, ghost),
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.5),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: kostvGlass(enabled: canAsk, radius: 16),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: kostvGlassInk(enabled: canAsk),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
    this.onSelect,
  });

  final KostvSeasonAsk ask;
  final double height;
  final bool compact;
  // On a phone, the bar is touched, not focused.
  FocusNode? get focusNode => null;
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
              decoration: kostvGlass(
                lit: ask.enabled,
                enabled: ask.enabled,
                radius: height,
              ),
              child: Text(
                button,
                style: TextStyle(
                  color: kostvGlassInk(lit: ask.enabled, enabled: ask.enabled),
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
