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
import '../detail_episode_images.dart';
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
      showContextMenu(
        context,
        episode,
        onChanged: () {
          if (mounted) setState(() {});
        },
      );
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
  void _placeRail(String hub, int index, String? key, double step) {
    // Once per season shown and per episode to watch: the list can grow
    // under it (missing episodes, the next one arriving late).
    final placing = '$hub|$key';
    if (_placedHub == placing) return;
    _placedHub = placing;
    final at = index <= 0 ? 0 : index;
    // This visit opens on the episode to watch, whatever the last one left.
    HubFocusMemory.set(hub, at);
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

    final seriesArt = _seriesArt(all);
    final view = (
      labels: labels,
      missing: missing,
      selectedIndex: selectedIndex,
      seasons: seasons,
      selected: selected,
      entries: entries,
      ask: ask,
      next: next,
      summary: summary,
      seriesArt: seriesArt,
    );
    return widget.landscape
        ? _landscape(context, l10n, view)
        : _portrait(context, l10n, view);
  }

  /// The series' own picture, for the episodes it lacks: its thumb, else
  /// the backdrop of the page's title.
  String? _seriesArt(List<AggregatedItem> all) {
    final api = _vm.imageApi;
    if (all.isNotEmpty) {
      final thumb = resolveSeriesLandscapeThumbnailUrl(
        all.first,
        api,
        maxWidth: 640,
      );
      if (thumb != null) return thumb;
    }
    final item = _vm.item;
    if (item == null || item.backdropImageTags.isEmpty) return null;
    return api.getBackdropImageUrl(
      item.id,
      maxWidth: 640,
      tag: item.backdropImageTags.first,
    );
  }

  /// «No está en casa. Pulsa para solicitarlo.»
  String _ghostText(
    BuildContext context,
    KostvGhostEpisode ghost,
    String? ask,
  ) {
    final state = KostvGhostTexts.shortNote(context, ghost);
    return ask == null ? state : '$state. $ask';
  }

  KostvGhostEpisode? _ghostCanAsk(KostvGhostEpisode ghost) =>
      ghost.canAsk && !(_gaps?.atLimit ?? true) ? ghost : null;

  // ------------------------------------------------------------ TV and web

  Widget _landscape(BuildContext context, AppLocalizations l10n, _View v) {
    final controller = _gaps;
    final showTabs = v.seasons.length > 1;
    final ask = v.ask;
    // The ask keeps its place (and the focus) while it's being sent.
    final askFocus = ask?.button != null;
    final hasRail = v.entries.isNotEmpty;
    final topNode = widget.episodesFocusNode;
    final askNode = showTabs ? _askNode : (topNode ?? _askNode);
    final selected = v.selected;

    void toRail() => _railKey.currentState?.requestFocusAt(
      HubFocusMemory.getForHub(_hub(selected), v.entries.length),
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

    // The ask went away (asked, or now a status) while it had the focus:
    // the focus goes on to the episodes, or the season names.
    if (!askFocus && askNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (hasRail) {
          toRail();
        } else if (showTabs) {
          topNode?.requestFocus();
        }
      });
    }
    final scale = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth * 0.27).clamp(240.0, 420.0);
        const gap = 24.0;
        final railHeight =
            cardWidth * 9 / 16 +
            14 +
            scale.scale(12) * 1.3 +
            4 +
            scale.scale(18) * 1.3 +
            5 +
            scale.scale(14) * 1.4 * 2 +
            24;
        final hub = _hub(selected);
        if (hasRail) {
          final next = v.next < 0 ? null : v.entries[v.next];
          _placeRail(
            hub,
            v.next,
            next?.episode?.id ?? next?.ghost?.number.toString(),
            cardWidth + gap,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTabs) ...[
              Transform.translate(
                // The words line up with the cards, not the pill around them.
                offset: const Offset(-18, 0),
                child: _SeasonTitles(
                  labels: v.labels,
                  missing: v.missing,
                  notAtHome: l10n.kostvGhostNotAtHome,
                  selectedIndex: v.selectedIndex,
                  focusNode: topNode,
                  onChanged: (index) => _selectSeason(v.seasons[index]),
                  onUp: () => widget.onVerticalNavigation?.call(true),
                  onDown: fromTabsDown,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 18,
              runSpacing: 10,
              children: [
                Text(
                  v.summary,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (ask?.button case final button?)
                  _Button(
                    label: button,
                    icon: Icons.add_rounded,
                    enabled: ask!.enabled,
                    focusNode: askFocus ? askNode : null,
                    onSelect: ask.enabled && selected != null
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
                  )
                else if (ask?.status case final status?)
                  Text(
                    status,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            if (hasRail) ...[
              const SizedBox(height: 18),
              SizedBox(
                key: const ValueKey('kostv-episode-rail'),
                height: railHeight,
                child: ScrollEdgeArrows(
                  controller: _railController,
                  child: LockedFocusRow<KostvEpisodeEntry>(
                    key: _railKey,
                    items: v.entries,
                    itemKey: (entry, _) => entry.episode != null
                        ? '${entry.episode!.serverId}|${entry.episode!.id}'
                        : 'ghost-${entry.ghost!.season}-${entry.ghost!.number}',
                    hubKey: hub,
                    itemExtent: cardWidth,
                    itemSpacing: gap,
                    height: railHeight,
                    padding: const EdgeInsets.only(top: 12),
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
                        final canAsk = _ghostCanAsk(ghost) != null;
                        return _Card(
                          width: cardWidth,
                          isFocused: isFocused,
                          dim: true,
                          still: _GhostStill(
                            ghost: ghost,
                            imageUrl: v.seriesArt,
                            canAsk: canAsk,
                            radius: 12,
                          ),
                          kicker: [l10n.episodeNumber(ghost.number)],
                          title: KostvGhostTexts.title(context, ghost),
                          text: _ghostText(
                            context,
                            ghost,
                            canAsk ? l10n.kostvGhostSelectToAsk : null,
                          ),
                          onTap: () => _openEntry(context, entry),
                        );
                      }
                      final episode = entry.episode!;
                      return _Card(
                        width: cardWidth,
                        isFocused: isFocused,
                        still: _Still(
                          episode: episode,
                          radius: 12,
                          imageUrl: minimalistEpisodeImageUrl(
                            episode,
                            _vm,
                            prefs: widget.prefs,
                            cardWidth: cardWidth,
                            devicePixelRatio: MediaQuery.devicePixelRatioOf(
                              context,
                            ),
                          ),
                        ),
                        kicker: _kickerOf(l10n, episode),
                        title: episode.name,
                        text: episode.overview,
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

  Widget _portrait(BuildContext context, AppLocalizations l10n, _View v) {
    final controller = _gaps;
    final ask = v.ask;
    final askFocus = ask?.button != null && ask!.enabled;
    final selected = v.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (v.seasons.length > 1) ...[
          Transform.translate(
            offset: const Offset(-13, 0),
            child: _SeasonChips(
              labels: [
                for (final (i, label) in v.labels.indexed)
                  v.missing.contains(i)
                      ? '$label · ${l10n.kostvGhostNotAtHome}'
                      : label,
              ],
              selectedIndex: v.selectedIndex,
              onChanged: (index) => _selectSeason(v.seasons[index]),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(v.summary, style: const TextStyle(color: _muted, fontSize: 14)),
        if (ask?.button case final button?) ...[
          const SizedBox(height: 12),
          _Button(
            label: button,
            icon: Icons.add_rounded,
            enabled: ask!.enabled,
            expand: true,
            onSelect: askFocus && selected != null
                ? () => kostvAskMissing(context, controller!, season: selected)
                : null,
          ),
        ] else if (ask?.status case final status?) ...[
          const SizedBox(height: 8),
          Text(status, style: const TextStyle(color: _muted, fontSize: 14)),
        ],
        const SizedBox(height: 8),
        for (final entry in v.entries)
          if (entry.ghost case final ghost?)
            _Line(
              dim: true,
              still: _GhostStill(
                ghost: ghost,
                imageUrl: v.seriesArt,
                canAsk: _ghostCanAsk(ghost) != null,
                radius: 10,
                glyph: 34,
              ),
              kicker: [l10n.episodeNumber(ghost.number)],
              title: KostvGhostTexts.title(context, ghost),
              text: _ghostText(
                context,
                ghost,
                _ghostCanAsk(ghost) != null ? l10n.kostvGhostTapToAsk : null,
              ),
              onTap: () => _openEntry(context, entry),
            )
          else
            _Line(
              still: _Still(
                episode: entry.episode!,
                radius: 10,
                inset: 8,
                imageUrl: minimalistEpisodeImageUrl(
                  entry.episode!,
                  _vm,
                  prefs: widget.prefs,
                  cardWidth: 150,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
              ),
              kicker: _kickerOf(l10n, entry.episode!),
              title: entry.episode!.name,
              text: entry.episode!.overview,
              onTap: () => _openEpisode(context, entry.episode!),
              onLongPress: () => _entryMenu(context, entry),
            ),
      ],
    );
  }
}

typedef _View = ({
  List<String> labels,
  Set<int> missing,
  int selectedIndex,
  List<int> seasons,
  int? selected,
  List<KostvEpisodeEntry> entries,
  KostvSeasonAsk? ask,
  int next,
  String summary,
  String? seriesArt,
});

// ------------------------------------------------------------------ pieces
//
// As Apple TV's and Netflix's: the picture and the words carry it. Nothing
// is framed or labelled on the stills; what has focus lifts, and a button
// is a soft grey that turns white under focus.

const _muted = Color(0x99F5F5F7);
const _faint = Color(0x80F5F5F7);

/// The small capitals over an episode's title: «EPISODIO 6 · QUEDAN 22 MIN».
class _Kicker extends StatelessWidget {
  const _Kicker(this.parts, {this.size = 12, this.dim = false});
  final List<String> parts;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) => Text(
    parts.join(' · ').toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: dim ? _ink.withValues(alpha: 0.42) : _faint,
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    ),
  );
}

/// The season names as plain words, the one shown in white; with focus it
/// becomes a white pill with dark words. Left and right change season as
/// they pass, as the tabs they replace did.
class _SeasonTitles extends StatefulWidget {
  const _SeasonTitles({
    required this.labels,
    required this.missing,
    required this.notAtHome,
    required this.selectedIndex,
    required this.onChanged,
    required this.onUp,
    required this.onDown,
    this.focusNode,
  });

  final List<String> labels;
  final Set<int> missing;
  final String notAtHome;
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
    // Past the first one, Left goes on (to a sidebar), as anywhere else.
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (at == 0) return KeyEventResult.ignored;
      widget.onChanged(at - 1);
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
                padding: const EdgeInsets.only(right: 6),
                child: _title(index, label),
              ),
          ],
        ),
      ),
    );
  }

  Widget _title(int index, String label) {
    final on = index == widget.selectedIndex;
    final pill = on && _focused;
    final missing = widget.missing.contains(index);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onChanged(index),
        child: AnimatedScale(
          scale: pill ? 1.06 : 1,
          duration: _fast,
          child: AnimatedContainer(
            duration: _fast,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: pill ? kostvLight : Colors.transparent,
              borderRadius: AppRadius.circular(12),
              boxShadow: [
                if (pill)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: label),
                  if (missing)
                    TextSpan(
                      text: '  ·  ${widget.notAtHome}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: pill
                            ? kostvOnLight.withValues(alpha: 0.6)
                            : _ink.withValues(alpha: 0.38),
                      ),
                    ),
                ],
              ),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: pill
                    ? kostvOnLight
                    : (on ? _ink : _ink.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// On a phone, the season names in a strip that slides sideways, the one
/// shown on a soft grey.
class _SeasonChips extends StatelessWidget {
  const _SeasonChips({
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (index, label) in labels.indexed)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: _fast,
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: index == selectedIndex
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: AppRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: index == selectedIndex ? _ink : _muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A button as Apple TV's: a soft grey that turns white with focus.
class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    this.icon,
    this.enabled = true,
    this.focusNode,
    this.onSelect,
    this.onUp,
    this.onDown,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final bool enabled;
  final FocusNode? focusNode;
  final VoidCallback? onSelect;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    Widget face(bool lit) {
      final ink = kostvGlassInk(lit: lit, enabled: enabled);
      return AnimatedScale(
        scale: lit && !expand ? 1.06 : 1,
        duration: _fast,
        child: AnimatedContainer(
          duration: _fast,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: expand ? 12 : 9,
          ),
          decoration: kostvGlass(lit: lit, enabled: enabled, radius: 10),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: ink, size: 19),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (focusNode == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onSelect : null,
        child: face(false),
      );
    }
    return FocusableWrapper(
      focusNode: focusNode,
      onSelect: onSelect,
      onNavigateUp: onUp,
      onNavigateDown: onDown,
      borderRadius: 10,
      disableScale: true,
      suppressFocusGlow: true,
      useBackgroundFocus: false,
      child: Builder(builder: (context) => face(Focus.of(context).hasFocus)),
    );
  }
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

/// «EPISODIO 6 · QUEDAN 22 MIN», or «EPISODIO 5 · 51 MIN · VISTO».
List<String> _kickerOf(AppLocalizations l10n, AggregatedItem episode) => [
  if (episode.indexNumber case final n?) l10n.episodeNumber(n),
  ?_lengthOf(l10n, episode),
  if (episode.isPlayed) l10n.watched,
];

/// A picture, or a quiet tile while there's none.
Widget _picture(String? url) {
  final placeholder = ColoredBox(
    color: Colors.white.withValues(alpha: 0.06),
    child: Center(
      child: Icon(
        Icons.movie_outlined,
        color: _ink.withValues(alpha: 0.25),
        size: 26,
      ),
    ),
  );
  if (url == null || url.isEmpty) return placeholder;
  return OfflineAwareImage(
    imageUrl: url,
    fit: BoxFit.cover,
    placeholder: (_, _) => placeholder,
    errorWidget: (_, _, _) => placeholder,
  );
}

/// The still, and only a thin bar of how far it's got.
class _Still extends StatelessWidget {
  const _Still({
    required this.episode,
    required this.imageUrl,
    required this.radius,
    this.inset = 12,
  });

  final AggregatedItem episode;
  final String? imageUrl;
  final double radius;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final progress = _progressOf(episode);
    return ClipRRect(
      borderRadius: AppRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _picture(imageUrl),
          // Watched ones step back a little.
          if (episode.isPlayed)
            ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
          if (progress != null)
            Positioned(
              left: inset,
              right: inset,
              bottom: inset,
              height: 4,
              child: ClipRRect(
                borderRadius: AppRadius.circular(2),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: const ColoredBox(color: kostvLight),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The series' picture in grey, darkened, with a «+» (or what's become of
/// it) in the middle: an episode the home server lacks.
class _GhostStill extends StatelessWidget {
  const _GhostStill({
    required this.ghost,
    required this.imageUrl,
    required this.canAsk,
    required this.radius,
    this.glyph = 46,
  });

  final KostvGhostEpisode ghost;
  final String? imageUrl;
  final bool canAsk;
  final double radius;
  final double glyph;

  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl == null)
            ColoredBox(color: Colors.white.withValues(alpha: 0.08))
          else
            ColorFiltered(colorFilter: _grey, child: _picture(imageUrl)),
          ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
          Center(
            child: Container(
              width: glyph,
              height: glyph,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                canAsk ? Icons.add_rounded : KostvGhostTexts.icon(ghost),
                color: _ink.withValues(alpha: 0.9),
                size: glyph * 0.58,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card of the row: what lifts with focus, and the words under it.
class _Card extends StatefulWidget {
  const _Card({
    required this.width,
    required this.isFocused,
    required this.still,
    required this.kicker,
    required this.title,
    required this.onTap,
    this.text,
    this.onLongPress,
    this.dim = false,
  });

  final double width;
  final bool isFocused;
  final Widget still;
  final List<String> kicker;
  final String title;
  final String? text;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool dim;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.isFocused || _hovered;
    final text = widget.text?.trim();
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
                scale: lit ? 1.06 : 1,
                duration: _fast,
                child: AnimatedContainer(
                  duration: _fast,
                  width: widget.width,
                  height: widget.width * 9 / 16,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.circular(12),
                    boxShadow: [
                      if (lit)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                    ],
                  ),
                  child: widget.still,
                ),
              ),
              const SizedBox(height: 14),
              _Kicker(widget.kicker, dim: widget.dim),
              const SizedBox(height: 4),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.dim ? _ink.withValues(alpha: 0.6) : _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (text != null && text.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink.withValues(alpha: lit ? 0.7 : 0.55),
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

/// On a phone, a line of the list: the still to the left, the words to the
/// right.
class _Line extends StatelessWidget {
  const _Line({
    required this.still,
    required this.kicker,
    required this.title,
    required this.onTap,
    this.text,
    this.onLongPress,
    this.dim = false,
  });

  final Widget still;
  final List<String> kicker;
  final String title;
  final String? text;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final text = this.text?.trim();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, height: 84, child: still),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Kicker(kicker, size: 11, dim: dim),
                  const SizedBox(height: 3),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dim ? _ink.withValues(alpha: 0.6) : _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (text != null && text.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ink.withValues(alpha: 0.55),
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
