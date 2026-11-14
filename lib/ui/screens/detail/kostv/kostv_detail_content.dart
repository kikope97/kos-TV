import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../data/models/aggregated_item.dart';
import '../../../../data/viewmodels/item_detail_view_model.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../preference/detail_section_layout.dart';
import '../../../../preference/user_preferences.dart';
import '../../../../util/platform_detection.dart';
import '../../../widgets/bottom_nav/bottom_navbar.dart';
import '../../../widgets/fullscreen_backdrop_switcher.dart';
import '../../../widgets/live_tv/incomplete_recording.dart';
import '../../../widgets/logo_view.dart';
import '../../../widgets/navigation_layout.dart';
import '../../../widgets/rating_display.dart';
import '../detail_layout_metrics.dart';
import '../detail_page.dart';
import '../item_detail_screen.dart';
import 'kostv_backdrop_trailer.dart';
import 'kostv_episodes_section.dart';

/// Kos TV: the kOS TV details page. The title's art fills the screen, with
/// what it is on the left over a darkening: kind, title (its logo when it has
/// one), the facts line, ratings, tagline, overview and who made it, then
/// Play (saying how far it got) and the other buttons with their names under
/// them. The rest (episodes, cast, more like it, details) are rows further
/// down, each its own stop for the D-pad; the first one peeks at the foot.
///
/// A phone gets the art at the top, the title over its foot and the rest
/// down the page, Play across the width.
class KostvDetailContent extends StatefulWidget {
  final ItemDetailViewModel viewModel;
  final UserPreferences prefs;
  final ValueListenable<String?> backdropUrl;
  final String? selectedMediaSourceId;
  final ValueChanged<String?> onSelectedMediaSourceChanged;
  final FocusNode? initialFocusNode;
  final bool autoPlay;
  final bool actionsExpanded;
  final ValueChanged<bool> onActionsExpandedChanged;
  final ValueChanged<bool>? onToggleNavbar;

  const KostvDetailContent({
    super.key,
    required this.viewModel,
    required this.prefs,
    required this.backdropUrl,
    this.selectedMediaSourceId,
    required this.onSelectedMediaSourceChanged,
    this.initialFocusNode,
    this.autoPlay = false,
    required this.actionsExpanded,
    required this.onActionsExpandedChanged,
    this.onToggleNavbar,
  });

  @override
  State<KostvDetailContent> createState() => _KostvDetailContentState();
}

class _KostvDetailContentState extends State<KostvDetailContent>
    with DetailPage<KostvDetailContent> {
  // The sections' stops down the page. Rebuilt with the page, since which
  // sections exist depends on what loaded.
  List<FocusNode> _stops = const [];

  ItemDetailViewModel get _vm => widget.viewModel;

  @override
  ItemDetailViewModel get pageViewModel => widget.viewModel;

  @override
  UserPreferences get pagePrefs => widget.prefs;

  @override
  ValueChanged<bool>? get pageNavbarToggle => widget.onToggleNavbar;

  @override
  TextStyle? get sectionTitleStyle => TextStyle(
    color: AppColorScheme.onBackground.withValues(alpha: 0.9),
    fontSize: detailUsesLandscapeLayout(context) ? 24 : 19,
    fontWeight: FontWeight.w700,
  );

  @override
  void moveUp(FocusNode node) {
    final i = _stops.indexOf(node);
    if (i > 0) return _enter(_stops[i - 1]);
    _toActions();
  }

  @override
  void moveDown(FocusNode node) {
    final i = _stops.indexOf(node);
    if (i >= 0 && i + 1 < _stops.length) _enter(_stops[i + 1]);
  }

  void _enter(FocusNode? node) {
    if (node?.context?.mounted == true) node!.requestFocus();
  }

  /// Back to whichever button was focused last, at the top of the page.
  void _toActions() {
    final last = lastActionFocus;
    _enter(last?.context?.mounted == true ? last : widget.initialFocusNode);
    if (pageScroll.hasClients) {
      pageScroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  /// Up from the buttons goes to the toolbar when it runs along the top, and
  /// stays put beside a sidebar, which Left already opens.
  void _onUpProxyFocus(bool focused) {
    if (!focused) return;
    if (navbarIsTop && NavigationLayout.focusNavbarNotifier.value != null) {
      toNavbar();
    } else {
      final last = lastActionFocus;
      _enter(last?.context?.mounted == true ? last : widget.initialFocusNode);
    }
  }

  /// Puts a section near the top of the screen as D-pad focus arrives in it,
  /// so the page reads down one section at a time.
  void _bringToTop(BuildContext section) {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !section.mounted || !pageScroll.hasClients) return;
      final page = pageScroll.position.context.storageContext
          .findRenderObject();
      final box = section.findRenderObject();
      if (page is! RenderBox || box is! RenderBox || !box.attached) return;
      final position = pageScroll.position;
      final y = box.localToGlobal(Offset.zero, ancestor: page).dy;
      final target = (position.pixels + y - 24).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() < 1) return;
      pageScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = _vm.item;
    if (item == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final landscape = detailUsesLandscapeLayout(context);
    final sections = DetailSectionVisibility.of(widget.prefs);
    final size = MediaQuery.sizeOf(context);

    // Built before the buttons, so Down from them knows where to land.
    final parts = _sections(item, sections, l10n, landscape, size);
    _stops = [for (final s in parts) s.node!];

    // The first row peeks under the art, to say there's more below.
    final heroHeight = landscape
        ? size.height - (parts.isEmpty ? 0 : (size.height * 0.1).clamp(70, 120))
        : (size.height * 0.5).clamp(320.0, 520.0);
    final side = _sideInsets(landscape, size);
    final scores = RatingsRow.forDetailScreen(
      item: item,
      extraRatings: _vm.ratings,
      prefs: widget.prefs,
      inlineChips: true,
    );
    // As large as the facts line above them.
    final ratings = scores == null
        ? null
        : MediaQuery.withClampedTextScaling(
            minScaleFactor: _factsScale(landscape),
            maxScaleFactor: 2,
            child: scores,
          );
    final textWidth = math.min(size.width * 0.52, 900.0);

    final Widget hero;
    if (landscape) {
      hero = SizedBox(
        height: heroHeight,
        child: Stack(
          children: [
            Positioned.fill(child: _buildBackdrop(item, landscape: true)),
            Padding(
              padding: EdgeInsets.fromLTRB(
                side.left,
                PlatformDetection.isTV ? 110 : 96,
                side.right,
                24,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: textWidth),
                      child: _buildHeroText(
                        item,
                        sections,
                        landscape,
                        size,
                        ratings,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Wider than the text: the buttons go on one line.
                  _buildActions(landscape),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      final art = heroHeight;
      hero = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: art,
            child: Stack(
              children: [
                Positioned.fill(child: _buildBackdrop(item, landscape: false)),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 12,
                  child: _buildTitleBlock(item, sections, landscape, size),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ratings != null) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: ratings),
                ],
                const SizedBox(height: 18),
                _buildActions(landscape),
                ..._portraitOverview(item, sections),
              ],
            ),
          ),
        ],
      );
    }

    return ColoredBox(
      color: AppColorScheme.background,
      child: SingleChildScrollView(
        controller: pageScroll,
        padding: EdgeInsets.only(
          bottom: bottomNavContentPadding(context, landscape ? 64 : 32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            for (final s in parts)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  side.left,
                  landscape ? 24 : 16,
                  side.right,
                  0,
                ),
                child: s.child,
              ),
          ],
        ),
      ),
    );
  }

  EdgeInsets _sideInsets(bool landscape, Size size) {
    if (!landscape) return const EdgeInsets.symmetric(horizontal: 16);
    final base = (size.width * 0.08).clamp(48.0, 140.0);
    // A left sidebar sits over the leading edge.
    final lead = navbarIsTop ? base : math.max(base, 120.0);
    return EdgeInsets.only(left: lead, right: base);
  }

  /// The art fills the hero, sharp, with a darkening on the left (where the
  /// text is) and at the foot (where the page goes on). A phone darkens the
  /// foot only, under the title.
  Widget _buildBackdrop(AggregatedItem item, {required bool landscape}) {
    final own = ownBackdropUrl(item);
    final showImage = widget.prefs.get(UserPreferences.detailsBackdropEnabled);
    final base = AppColorScheme.background;

    return RepaintBoundary(
      child: ValueListenableBuilder<String?>(
        valueListenable: widget.backdropUrl,
        builder: (context, value, _) {
          final url = value ?? own;
          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: base),
              if (showImage && url != null && url.isNotEmpty)
                FullscreenBackdropSwitcher(
                  imageUrl: url,
                  duration: const Duration(milliseconds: 350),
                  alignment: landscape
                      ? Alignment.topRight
                      : Alignment.topCenter,
                ),
              if (showImage)
                KostvBackdropTrailer(
                  key: ValueKey('kostv-trailer-${item.id}'),
                  item: item,
                  prefs: widget.prefs,
                ),
              if (landscape)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        base.withValues(alpha: 0.96),
                        base.withValues(alpha: 0.82),
                        base.withValues(alpha: 0.25),
                        base.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.3, 0.58, 0.75],
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      base,
                      base.withValues(alpha: landscape ? 0.6 : 0.75),
                      base.withValues(alpha: 0),
                    ],
                    stops: landscape
                        ? const [0, 0.22, 0.45]
                        : const [0.02, 0.35, 0.7],
                  ),
                ),
              ),
              if (!landscape)
                // The status bar and the back button read over any art.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.black.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.22],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// What it is, over the title: «PELÍCULA», «SERIE», «EPISODIO».
  String? _kicker(AppLocalizations l10n, AggregatedItem item) =>
      switch (item.type) {
        'Movie' => l10n.kostvDetailKindMovie,
        'Series' => l10n.kostvDetailKindSeries,
        'Season' => l10n.kostvDetailKindSeason,
        'Episode' => l10n.kostvDetailKindEpisode,
        _ => null,
      };

  double _factsScale(bool landscape) =>
      landscape ? (PlatformDetection.isTV ? 1.45 : 1.25) : 1.05;

  /// Kind, title and the facts line.
  Widget _buildTitleBlock(
    AggregatedItem item,
    DetailSectionVisibility sections,
    bool landscape,
    Size size,
  ) {
    final kicker = _kicker(AppLocalizations.of(context), item);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kicker != null) ...[
          Text(
            kicker.toUpperCase(),
            style: TextStyle(
              color: AppColorScheme.onBackground.withValues(alpha: 0.6),
              fontSize: landscape ? 17 : 13,
              fontWeight: FontWeight.w700,
              letterSpacing: landscape ? 3 : 2,
            ),
          ),
          const SizedBox(height: 12),
        ],
        _buildBranding(item, sections, landscape, size),
        SizedBox(height: landscape ? 18 : 10),
        // The facts line, larger on a big screen than the other styles set
        // it: it's read from the sofa.
        MediaQuery.withClampedTextScaling(
          minScaleFactor: _factsScale(landscape),
          maxScaleFactor: 2,
          child: DetailMetadataRow(
            item: item,
            selectedMediaSource: selectedMediaSourceForItem(
              item,
              widget.selectedMediaSourceId,
            ),
            upcomingEpisode: _vm.upcomingEpisode,
            alignStart: true,
          ),
        ),
        IncompleteRecordingDetailLine(itemId: item.id),
      ],
    );
  }

  Widget _buildHeroText(
    AggregatedItem item,
    DetailSectionVisibility sections,
    bool landscape,
    Size size,
    Widget? ratings,
  ) {
    final muted = AppColorScheme.onBackground.withValues(alpha: 0.86);
    final overview = overviewText(item);
    final overviewStyle = TextStyle(
      color: muted,
      fontSize: PlatformDetection.isTV ? 21 : 17,
      height: 1.5,
    );
    final tagline = sections.shows(DetailSection.tagline) ? item.tagline : null;
    final credits = _credits();

    return Column(
      key: const ValueKey('kostv-hero'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitleBlock(item, sections, landscape, size),
        if (ratings != null) ...[const SizedBox(height: 16), ratings],
        if (tagline != null && tagline.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            tagline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
              fontSize: PlatformDetection.isTV ? 28 : 23,
              color: AppColorScheme.onBackground,
            ),
          ),
        ],
        if (overview != null) ...[
          const SizedBox(height: 10),
          // As much of the overview as fits above the buttons.
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final line =
                    MediaQuery.textScalerOf(context)
                        .scale(overviewStyle.fontSize ?? 16) *
                    (overviewStyle.height ?? 1);
                final fit = constraints.maxHeight.isFinite
                    ? (constraints.maxHeight / line).floor()
                    : 4;
                final lines = math.min(fit, 4);
                if (lines <= 0) return const SizedBox.shrink();
                return Text(
                  overview,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: overviewStyle,
                );
              },
            ),
          ),
        ],
        if (credits != null) ...[const SizedBox(height: 14), credits],
      ],
    );
  }

  /// «Dirección Lucía Ferrer · Con Ana Ortiz, Mario Sanz, Pablo Rey».
  Widget? _credits() {
    final l10n = AppLocalizations.of(context);
    String names(List<Map<String, dynamic>> people, int count) => people
        .map((p) => p['Name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .take(count)
        .join(', ');
    final directors = names(_vm.directors, 2);
    final cast = names(_vm.actors, 3);
    if (directors.isEmpty && cast.isEmpty) return null;
    final dim = AppColorScheme.onBackground.withValues(alpha: 0.62);
    final strong = AppColorScheme.onBackground.withValues(alpha: 0.92);
    return Text.rich(
      TextSpan(
        children: [
          if (directors.isNotEmpty) ...[
            TextSpan(
              text: '${l10n.kostvDetailDirectedBy} ',
              style: TextStyle(color: strong, fontWeight: FontWeight.w600),
            ),
            TextSpan(text: directors),
          ],
          if (directors.isNotEmpty && cast.isNotEmpty)
            const TextSpan(text: '   ·   '),
          if (cast.isNotEmpty) ...[
            TextSpan(
              text: '${l10n.kostvDetailStarring} ',
              style: TextStyle(color: strong, fontWeight: FontWeight.w600),
            ),
            TextSpan(text: cast),
          ],
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: dim, fontSize: PlatformDetection.isTV ? 18 : 15),
    );
  }

  /// A phone gives the tagline, the whole overview and who made it under the
  /// buttons.
  List<Widget> _portraitOverview(
    AggregatedItem item,
    DetailSectionVisibility sections,
  ) {
    final overview = overviewText(item);
    final tagline = sections.shows(DetailSection.tagline) ? item.tagline : null;
    final credits = _credits();
    return [
      if (tagline != null && tagline.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text(
          tagline,
          style: TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w300,
            fontStyle: FontStyle.italic,
            fontSize: 20,
            color: AppColorScheme.onBackground,
          ),
        ),
      ],
      if (overview != null) ...[
        SizedBox(height: tagline == null ? 22 : 8),
        Text(
          overview,
          style: TextStyle(
            color: AppColorScheme.onBackground.withValues(alpha: 0.86),
            fontSize: 15,
            height: 1.55,
          ),
        ),
      ],
      if (credits != null) ...[const SizedBox(height: 12), credits],
    ];
  }

  /// The logo, or the name set large when there's no logo. A season or an
  /// episode names its show and then itself.
  Widget _buildBranding(
    AggregatedItem item,
    DetailSectionVisibility sections,
    bool landscape,
    Size size,
  ) {
    final partOfShow = item.type == 'Episode' || item.type == 'Season';
    final logoTag = sections.shows(DetailSection.logo)
        ? item.logoImageTag ?? (partOfShow ? item.seriesLogoImageTag : null)
        : null;
    final logoId = logoTag == null
        ? null
        : (item.logoImageTag != null ? item.id : item.seriesId);
    final shadows = [
      Shadow(color: AppColors.black.withValues(alpha: 0.55), blurRadius: 24),
    ];

    final showName = partOfShow ? (item.seriesName ?? item.name) : item.name;
    final Widget mark = logoTag != null && logoId != null && logoId.isNotEmpty
        ? Align(
            alignment: Alignment.centerLeft,
            child: LogoView(
              imageUrl: _vm.imageApi.getLogoImageUrl(
                logoId,
                maxWidth: 800,
                tag: logoTag,
              ),
              maxWidth: landscape ? 560 : 260,
              maxHeight: landscape ? math.min(170.0, size.height * 0.2) : 100,
            ),
          )
        : Text(
            showName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Outfit',
              color: AppColorScheme.onBackground,
              fontSize: landscape ? (size.width * 0.06).clamp(48.0, 110.0) : 44,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              height: 1,
              shadows: shadows,
            ),
          );

    if (!partOfShow) return mark;

    final number = item.type == 'Episode' ? episodeNumber(item) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mark,
        const SizedBox(height: 10),
        Text(
          [?number, item.name].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColorScheme.onBackground,
            fontSize: landscape ? 26 : 20,
            fontWeight: FontWeight.w600,
            shadows: shadows,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(bool landscape) {
    final kidsMode = widget.prefs.get(UserPreferences.kidsModeEnabled);
    // Left on Auto, a TV would line up every button it has. Play, four
    // circles and the ellipsis keep the row the width of the title.
    final auto = widget.prefs.get(UserPreferences.detailButtonsMaxVisible) == 0;
    final buttons = DetailActionButtons(
      key: actionsKey,
      viewModel: _vm,
      itemId: _vm.item?.id,
      selectedMediaSourceId: widget.selectedMediaSourceId,
      onSelectedMediaSourceChanged: widget.onSelectedMediaSourceChanged,
      tvPlayFocusNode: widget.initialFocusNode,
      upTarget: actionsUpProxy,
      downTarget: _stops.firstOrNull,
      onRequestFocus: (target) {
        _enter(target);
        return KeyEventResult.handled;
      },
      autoPlay: widget.autoPlay,
      modernStyle: true,
      kostv: true,
      fullWidthPrimary: !landscape,
      overflowAsMenu: !kidsMode,
      maxVisibleButtonsOverride: auto ? (landscape ? 7 : 5) : null,
      actionsExpanded: widget.actionsExpanded,
      onActionsExpandedChanged: widget.onActionsExpandedChanged,
      omitTrackButtons: true,
      labelsUnderCircles: landscape,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          focusNode: actionsUpProxy,
          onFocusChange: _onUpProxyFocus,
          child: const SizedBox.shrink(),
        ),
        buttons,
      ],
    );
  }

  /// Everything under the first screen, in reading order, each in its own
  /// frame with the node the D-pad enters it by.
  List<DetailPageSection> _sections(
    AggregatedItem item,
    DetailSectionVisibility sections,
    AppLocalizations l10n,
    bool landscape,
    Size size,
  ) {
    final out = <DetailPageSection>[];

    DetailPageSection framed(
      FocusNode node,
      Widget child, {
      String? title,
      bool whole = false,
    }) => DetailPageSection(
      node: node,
      child: _KostvSection(
        title: title == null ? null : sectionTitle(title),
        titleStyle: sectionTitleStyle,
        wholeNode: whole ? node : null,
        filled: !landscape,
        onUp: () => moveUp(node),
        onDown: () => moveDown(node),
        onFocused: _bringToTop,
        child: child,
      ),
    );

    if (item.type == 'Series' ||
        item.type == 'Season' ||
        (item.type == 'Episode' &&
            sections.shows(DetailSection.moreEpisodes))) {
      final node = pageNode('episodes');
      out.add(
        framed(
          node,
          KostvEpisodesSection(
            key: ValueKey('kostv-episodes-${item.id}'),
            viewModel: _vm,
            prefs: widget.prefs,
            landscape: landscape,
            maxHeight: landscape ? size.height * 0.5 : null,
            episodesFocusNode: node,
            onVerticalNavigation: (isUp) {
              isUp ? moveUp(node) : moveDown(node);
              return true;
            },
          ),
          title: l10n.episodes,
        ),
      );
    }

    final tracks = tracksSection(l10n);
    if (tracks != null) {
      out.add(
        framed(
          tracks.node!,
          tracks.child,
          title: l10n.settingsAudioAndSubtitlesSection,
        ),
      );
    }

    final facts = factsSection(item, sections, weighByText: true);
    if (facts != null) {
      out.add(framed(facts.node!, facts.child, title: l10n.details));
    }

    final rows = [
      ?castSection(item, sections, l10n),
      ...libraryRows(sections, l10n),
    ];
    for (final (index, row) in rows.indexed) {
      // A section with nothing to press takes the stop itself.
      final node = row.node ?? pageNode('row-$index');
      out.add(framed(node, row.child, whole: row.node == null));
    }

    return out;
  }
}

/// One section down the page. It lights up while focus is inside it, and
/// when nothing in it takes focus it's the stop itself.
class _KostvSection extends StatefulWidget {
  final String? title;
  final TextStyle? titleStyle;
  final FocusNode? wholeNode;

  /// A phone shows every section on a card, since there's no focus to frame.
  final bool filled;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueChanged<BuildContext> onFocused;
  final Widget child;

  const _KostvSection({
    required this.title,
    required this.titleStyle,
    required this.wholeNode,
    required this.filled,
    required this.onUp,
    required this.onDown,
    required this.onFocused,
    required this.child,
  });

  @override
  State<_KostvSection> createState() => _KostvSectionState();
}

class _KostvSectionState extends State<_KostvSection> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onDown();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final whole = widget.wholeNode != null;
    final on = AppColorScheme.onBackground;
    final Color border;
    if (!_focused) {
      border = Colors.transparent;
    } else {
      border = whole ? on : on.withValues(alpha: 0.18);
    }
    final Color fill;
    if (whole && _focused) {
      fill = on.withValues(alpha: 0.07);
    } else {
      fill = widget.filled ? on.withValues(alpha: 0.04) : Colors.transparent;
    }

    return Focus(
      focusNode: widget.wholeNode,
      canRequestFocus: whole,
      skipTraversal: !whole,
      onKeyEvent: whole ? _onKey : null,
      onFocusChange: (has) {
        setState(() => _focused = has);
        if (has) widget.onFocused(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        // A row runs on past the frame's edge, so it's cut off there.
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: AppRadius.circular(14),
          border: Border.all(color: border, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.title != null) ...[
              Text(widget.title!, style: widget.titleStyle),
              const SizedBox(height: 12),
            ],
            widget.child,
          ],
        ),
      ),
    );
  }
}
