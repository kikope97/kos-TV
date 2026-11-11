import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/hub_focus_memory.dart';
import '../../widgets/focus/locked_focus_row.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/horizontal_scroll_section.dart';
import '../../widgets/kos_logo.dart';
import '../../widgets/media_card.dart';
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/modern_row.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';

/// Kos TV: what's on the streaming platforms, from the requests service. A
/// button per platform on top (and one for all of them), then the most
/// watched and the newest series and films of the one chosen. What's on the
/// home server is in colour and opens its page; the rest is grey.
class KostvDiscoverScreen extends StatefulWidget {
  const KostvDiscoverScreen({super.key});

  @override
  State<KostvDiscoverScreen> createState() => _KostvDiscoverScreenState();
}

/// One of the four rows under the platforms.
@immutable
class _RowSpec {
  const _RowSpec(this.type, this.list);
  final StremfinTitleType type;
  final StremfinTopList list;

  String title(AppLocalizations l10n, StremfinPlatform platform) {
    final name = platform.name;
    if (platform.isAll || name.isEmpty) {
      return switch ((type, list)) {
        (StremfinTitleType.series, StremfinTopList.popular) =>
          l10n.kostvDiscoverPopularSeries,
        (StremfinTitleType.series, StremfinTopList.fresh) =>
          l10n.kostvDiscoverNewSeries,
        (StremfinTitleType.movie, StremfinTopList.popular) =>
          l10n.kostvDiscoverPopularMovies,
        (StremfinTitleType.movie, StremfinTopList.fresh) =>
          l10n.kostvDiscoverNewMovies,
      };
    }
    return switch ((type, list)) {
      (StremfinTitleType.series, StremfinTopList.popular) =>
        l10n.kostvDiscoverPopularSeriesOn(name),
      (StremfinTitleType.series, StremfinTopList.fresh) =>
        l10n.kostvDiscoverNewSeriesOn(name),
      (StremfinTitleType.movie, StremfinTopList.popular) =>
        l10n.kostvDiscoverPopularMoviesOn(name),
      (StremfinTitleType.movie, StremfinTopList.fresh) =>
        l10n.kostvDiscoverNewMoviesOn(name),
    };
  }
}

/// Series first, then films; in each, the most watched and then the new.
const _rowSpecs = [
  _RowSpec(StremfinTitleType.series, StremfinTopList.popular),
  _RowSpec(StremfinTitleType.series, StremfinTopList.fresh),
  _RowSpec(StremfinTitleType.movie, StremfinTopList.popular),
  _RowSpec(StremfinTitleType.movie, StremfinTopList.fresh),
];

class _RowState {
  List<StremfinTitle> items = const [];
  bool loading = true;
  bool failed = false;
}

/// The grey of a title that isn't on the server, a little dimmed.
const _missingFilter = ColorFilter.matrix([
  0.2126 * 0.7,
  0.7152 * 0.7,
  0.0722 * 0.7,
  0,
  0,
  0.2126 * 0.7,
  0.7152 * 0.7,
  0.0722 * 0.7,
  0,
  0,
  0.2126 * 0.7,
  0.7152 * 0.7,
  0.0722 * 0.7,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

/// The platforms' white logos, from TMDB's images (nothing is bundled with
/// the app).
const _platformLogos = {
  'netflix': 'https://image.tmdb.org/t/p/w500_filter(duotone,ffffff,bababa)/wwemzKWzjKYJFfCeiB57q3r4Bcm.png',
  'disney': 'https://image.tmdb.org/t/p/w500_filter(duotone,ffffff,bababa)/gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png',
  'prime': 'https://image.tmdb.org/t/p/w500_filter(duotone,ffffff,bababa)/ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png',
};

class _KostvDiscoverScreenState extends State<KostvDiscoverScreen> {
  final _service = GetIt.instance<StremfinService>();
  final _prefs = GetIt.instance<UserPreferences>();

  static const _platformHub = 'kostv_discover_platforms';

  /// The platform last looked at, while the app is open.
  static String _lastPlatform = StremfinPlatform.allId;

  List<StremfinPlatform> _platforms = StremfinPlatform.defaults;
  late String _platformId = _lastPlatform;
  final Map<_RowSpec, _RowState> _rows = {
    for (final spec in _rowSpecs) spec: _RowState(),
  };

  /// Bumped on each platform change, so a slow list of the previous one
  /// doesn't land on screen.
  int _generation = 0;
  Timer? _selectDebounce;

  final _scrollController = ScrollController();
  final _platformFocus = FocusNode(debugLabel: 'kostvDiscoverPlatforms');
  final _platformRowKey = GlobalKey<LockedFocusRowState<StremfinPlatform>>();
  final Map<_RowSpec, GlobalKey<LockedFocusRowState<StremfinTitle>>> _rowKeys =
      {
        for (final spec in _rowSpecs)
          spec: GlobalKey<LockedFocusRowState<StremfinTitle>>(),
      };

  StremfinPlatform get _platform => _platforms.firstWhere(
    (p) => p.id == _platformId,
    orElse: () => _platforms.first,
  );

  @override
  void initState() {
    super.initState();
    _setPlatformMemory();
    _service.addListener(_onAccessChanged);
    _service.listsRevision.addListener(_onListsChanged);
    unawaited(_loadPlatforms());
    _loadLists();
  }

  @override
  void dispose() {
    _selectDebounce?.cancel();
    _service.removeListener(_onAccessChanged);
    _service.listsRevision.removeListener(_onListsChanged);
    _scrollController.dispose();
    _platformFocus.dispose();
    super.dispose();
  }

  /// The service turned the person away meanwhile: back Home.
  void _onAccessChanged() {
    if (!mounted || _service.access != StremfinAccess.denied) return;
    context.go(Destinations.home);
  }

  void _setPlatformMemory() {
    final index = _platforms.indexWhere((p) => p.id == _platformId);
    HubFocusMemory.set(_platformHub, index < 0 ? 0 : index);
  }

  Future<void> _loadPlatforms() async {
    final platforms = await _service.platforms();
    if (!mounted || platforms.isEmpty) return;
    setState(() {
      _platforms = platforms;
      if (!platforms.any((p) => p.id == _platformId)) {
        _platformId = platforms.first.id;
      }
    });
    _setPlatformMemory();
  }

  void _loadLists({bool refresh = false}) {
    final generation = ++_generation;
    final platform = _platformId;
    for (final spec in _rowSpecs) {
      final row = _rows[spec]!;
      final kept = _service.keptList(
        platform: platform,
        type: spec.type,
        list: spec.list,
      );
      row
        ..items = kept ?? const []
        ..loading = true
        ..failed = false;
      unawaited(
        _service
            .top(
              platform: platform,
              type: spec.type,
              list: spec.list,
              refresh: refresh,
            )
            .then(
              (items) {
                if (!mounted || generation != _generation) return;
                setState(() {
                  row
                    ..items = items
                    ..loading = false;
                });
              },
              onError: (Object e) {
                if (!mounted || generation != _generation) return;
                setState(() {
                  row
                    ..loading = false
                    ..failed = true;
                });
              },
            ),
      );
    }
  }

  void _selectPlatform(StremfinPlatform platform) {
    _selectDebounce?.cancel();
    if (platform.id == _platformId) return;
    _lastPlatform = platform.id;
    setState(() => _platformId = platform.id);
    _loadLists();
  }

  /// Moving along the platforms switches to the one landed on, once the
  /// arrows rest.
  void _onPlatformFocused(StremfinPlatform platform) {
    _selectDebounce?.cancel();
    _selectDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _selectPlatform(platform),
    );
  }

  List<_RowSpec> get _visibleRows => [
    for (final spec in _rowSpecs)
      if (_rows[spec]!.items.isNotEmpty || _rows[spec]!.loading) spec,
  ];

  bool _focusRow(int visibleIndex) {
    final rows = _visibleRows;
    if (visibleIndex < 0 || visibleIndex >= rows.length) return false;
    final state = _rowKeys[rows[visibleIndex]]!.currentState;
    if (state == null || _rows[rows[visibleIndex]]!.items.isEmpty) {
      return false;
    }
    state.requestFocusFromMemory();
    return true;
  }

  bool _onPlatformVertical(bool isUp) {
    if (isUp) {
      if (_navbarOnTop) {
        NavigationLayout.focusNavbarNotifier.value?.call();
        return true;
      }
      return false;
    }
    // Down: the platform chosen is the one on screen, even mid-debounce.
    final focused = _platformRowKey.currentState?.focusedIndex;
    if (focused != null && focused < _platforms.length) {
      _selectPlatform(_platforms[focused]);
    }
    return _focusRow(0);
  }

  bool _onRowVertical(_RowSpec spec, bool isUp) {
    final index = _visibleRows.indexOf(spec);
    if (isUp) {
      if (index <= 0) {
        _focusPlatforms();
        return true;
      }
      _focusRow(index - 1);
      return true;
    }
    // Past the last row there is nothing; the focus stays.
    _focusRow(index + 1);
    return true;
  }

  void _focusPlatforms() {
    final index = _platforms.indexWhere((p) => p.id == _platformId);
    _platformRowKey.currentState?.requestFocusAt(index < 0 ? 0 : index);
  }

  bool get _navbarOnTop =>
      NavigationLayout.sanitizeNavbarPosition(
        _prefs.get(UserPreferences.navbarPosition),
      ) ==
      NavbarPosition.top;

  void _onLeftEdge() {
    if (_navbarOnTop) return;
    NavigationLayout.focusNavbarNotifier.value?.call();
  }

  /// What's on the home server opens its page there. The rest, and a series
  /// missing the season its card announces, opens its page to request it.
  void _openTitle(StremfinTitle title) {
    final itemId = title.library.itemId;
    final partial = title.library.status == StremfinLibraryStatus.partial;
    if (title.isInLibrary && itemId != null && !partial) {
      context.push(Destinations.item(itemId));
      return;
    }
    context.push(
      Destinations.kostvRequestOf(title.type.apiValue, title.tmdbId),
      extra: title,
    );
  }

  /// A title changed on the lists kept (asked for, arrived…): the cards
  /// show it as it stands.
  void _onListsChanged() {
    if (!mounted) return;
    setState(() {
      for (final spec in _rowSpecs) {
        final kept = _service.keptList(
          platform: _platformId,
          type: spec.type,
          list: spec.list,
        );
        if (kept != null) _rows[spec]!.items = kept;
      }
    });
  }

  ({double imageHeight, double cardWidth, double scale}) _sizes() {
    final scale = _prefs.get(UserPreferences.desktopUiScale).scaleFactor;
    final platformScale = PlatformDetection.isTV ? 0.8 * scale : scale;
    final posterSize = _prefs.get(UserPreferences.posterSize).upToExtraLarge;
    final imageHeight = modernImageHeight(posterSize, platformScale);
    return (
      imageHeight: imageHeight,
      cardWidth: imageHeight * 2 / 3,
      scale: scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final insets = calendarChromeInsets(context);
    final sizes = _sizes();
    final rows = _visibleRows;
    final allFailed = _rowSpecs.every(
      (s) => _rows[s]!.failed && _rows[s]!.items.isEmpty,
    );
    final tint = _platform.color ?? KosBrand.violet;

    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.kostvDiscover,
        child: _withInitialFocus(
          Stack(
            fit: StackFit.expand,
            children: [
              // The chosen platform's colour, faint, from the top corner.
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.9, -1.1),
                    radius: 1.4,
                    colors: [
                      tint.withValues(alpha: 0.32),
                      tint.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
              BottomNavPadded(
                fallback: 48,
                builder: (context, bottom) => ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.only(top: insets.top, bottom: bottom),
                  children: [
                    _section(
                      scrollToTop: true,
                      child: _buildPlatforms(sizes, insets),
                    ),
                    if (allFailed)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          insets.left,
                          48,
                          insets.right,
                          0,
                        ),
                        child: Column(
                          children: [
                            Text(
                              l10n.kostvDiscoverUnavailable,
                              style: TextStyle(
                                color: AppColorScheme.onSurface.withValues(
                                  alpha: 0.8,
                                ),
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () =>
                                  setState(() => _loadLists(refresh: true)),
                              child: Text(l10n.retry),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final spec in rows)
                        _section(child: _buildRow(spec, sizes, insets, l10n)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// With a remote or a keyboard the platforms take focus on arrival; on a
  /// touch screen nothing does, so no focus ring sits on a tile.
  Widget _withInitialFocus(Widget child) => PlatformDetection.useMobileUi
      ? child
      : RequestInitialFocus(targetNode: _platformFocus, child: child);

  /// Keeps whatever takes focus in view.
  Widget _section({required Widget child, bool scrollToTop = false}) {
    return Builder(
      builder: (sectionContext) => Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onFocusChange: (hasFocus) {
          if (!hasFocus) return;
          if (scrollToTop) {
            if (_scrollController.hasClients) {
              unawaited(
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOut,
                ),
              );
            }
            return;
          }
          unawaited(
            Scrollable.ensureVisible(
              sectionContext,
              alignment: 0.15,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOut,
            ),
          );
        },
        child: child,
      ),
    );
  }

  Widget _buildPlatforms(
    ({double imageHeight, double cardWidth, double scale}) sizes,
    EdgeInsets insets,
  ) {
    // On a phone the four share the width; elsewhere they follow the posters.
    final mobile = PlatformDetection.useMobileUi;
    final spacing = mobile ? 10.0 : 20.0;
    final double tileWidth;
    final double tileHeight;
    if (mobile) {
      final usable =
          MediaQuery.sizeOf(context).width - insets.left - insets.right;
      final count = _platforms.length.clamp(1, 4);
      tileWidth = ((usable - spacing * (count - 1)) / count).clamp(72.0, 200.0);
      tileHeight = tileWidth * 0.56;
    } else {
      tileHeight = (sizes.imageHeight * 0.42).clamp(64.0, 120.0);
      tileWidth = tileHeight * 2.3;
    }
    final growth = tileHeight * 0.08;
    final focusColor = Color(_prefs.get(UserPreferences.focusColor).colorValue);
    return LockedFocusRow<StremfinPlatform>(
      key: _platformRowKey,
      hubKey: _platformHub,
      items: _platforms,
      itemKey: (p, _) => p.id,
      focusNode: _platformFocus,
      autofocus: !mobile,
      itemExtent: tileWidth,
      itemSpacing: spacing,
      height: tileHeight + growth * 2 + 12,
      clipBehavior: Clip.none,
      padding: EdgeInsets.fromLTRB(
        insets.left,
        growth + 6,
        insets.right,
        growth + 6,
      ),
      onIndexChanged: (_, p) => _onPlatformFocused(p),
      onTap: (_, p) => _selectPlatform(p),
      onVerticalNavigation: _onPlatformVertical,
      onLeftEdge: _onLeftEdge,
      itemBuilder: (context, platform, index, focused) => _PlatformTile(
        platform: platform,
        width: tileWidth,
        height: tileHeight,
        selected: platform.id == _platformId,
        // A ring only for a remote or the keyboard, never after a touch.
        focused: InputModeTracker.showFocusVisuals(context, focused),
        focusColor: focusColor,
        onTap: () => _selectPlatform(platform),
      ),
    );
  }

  Widget _buildRow(
    _RowSpec spec,
    ({double imageHeight, double cardWidth, double scale}) sizes,
    EdgeInsets insets,
    AppLocalizations l10n,
  ) {
    final row = _rows[spec]!;
    final scale = sizes.scale;
    final expansion = _prefs.get(UserPreferences.cardFocusExpansion);
    final focusColor = Color(_prefs.get(UserPreferences.focusColor).colorValue);
    final growth = MediaCard.focusHeadroom(
      sizes.imageHeight,
      expansion: expansion,
    );
    final spacing = expansion && !PlatformDetection.useMobileUi
        ? MediaCard.focusGap(sizes.cardWidth, minimum: 14.0 * scale)
        : 14.0 * scale;
    // The poster plus room for the title and year under it.
    final rowHeight = sizes.imageHeight + 65.0 * scale + growth;
    final platform = _platform;

    return HorizontalScrollSection(
      title: spec.title(l10n, platform),
      titleStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: AppColorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      headerPadding: EdgeInsets.fromLTRB(
        insets.left,
        14 * scale,
        insets.right,
        4 * scale,
      ),
      contentSpacing: 0,
      showControls: row.items.isNotEmpty && PlatformDetection.useDesktopUi,
      builder: (context, controller) => SizedBox(
        height: rowHeight + 10 * scale,
        child: row.items.isEmpty
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : LockedFocusRow<StremfinTitle>(
                key: _rowKeys[spec],
                hubKey:
                    'kostv_discover_${_platformId}_${spec.type.apiValue}_${spec.list.apiValue}',
                items: row.items,
                itemKey: (t, _) => '${t.type.apiValue}:${t.tmdbId}',
                controller: controller,
                itemExtent: sizes.cardWidth,
                itemSpacing: spacing,
                height: rowHeight,
                clipBehavior: Clip.none,
                padding: EdgeInsets.fromLTRB(
                  insets.left,
                  5 * scale + growth,
                  insets.right,
                  5 * scale,
                ),
                onVerticalNavigation: (isUp) => _onRowVertical(spec, isUp),
                onLeftEdge: _onLeftEdge,
                onTap: (_, title) => _openTitle(title),
                itemBuilder: (context, title, index, focused) => MediaCard(
                  title: title.title,
                  subtitle: title.year?.toString(),
                  imageUrl: title.poster,
                  width: sizes.cardWidth,
                  aspectRatio: 2 / 3,
                  itemType: title.type == StremfinTitleType.movie
                      ? 'Movie'
                      : 'Series',
                  focusColor: focusColor,
                  cardFocusExpansion: expansion,
                  externalIsFocused: InputModeTracker.showFocusVisuals(
                    context,
                    focused,
                  ),
                  imageColorFilter: title.isInLibrary ? null : _missingFilter,
                  subtitleColor: title.isInLibrary
                      ? null
                      : AppColorScheme.onSurface.withValues(alpha: 0.5),
                  onTap: () => _openTitle(title),
                  imageOverlays: _badges(
                    title,
                    list: spec.list,
                    platform: platform,
                    imageHeight: sizes.imageHeight,
                    l10n: l10n,
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _badges(
    StremfinTitle title, {
    required StremfinTopList list,
    required StremfinPlatform platform,
    required double imageHeight,
    required AppLocalizations l10n,
  }) {
    final library = title.library;
    final request = title.request;
    final rank = title.rank;
    final pillScale = (imageHeight / 216).clamp(0.8, 1.3);
    final source = title.platform == null
        ? null
        : _platforms.where((p) => p.id == title.platform).firstOrNull;

    // Top left: where it comes from, and the season that has just come out.
    final top = <Widget>[
      if (platform.isAll && source != null)
        _Pill(
          text: source.name,
          color: source.color ?? Colors.black54,
          scale: pillScale,
        ),
      if (list == StremfinTopList.fresh &&
          title.type == StremfinTitleType.series &&
          title.season != null)
        _Pill(
          text: title.season == 1
              ? l10n.kostvDiscoverBrandNewSeries
              : l10n.kostvDiscoverNewSeason(title.season!),
          color: Colors.black.withValues(alpha: 0.72),
          scale: pillScale,
        ),
    ];

    // Bottom: how it stands on the home server.
    final ({String text, Color color})? status;
    if (library.status == StremfinLibraryStatus.partial &&
        library.season != null) {
      status = (
        text: l10n.kostvDiscoverMissingSeason(library.season!),
        color: const Color(0xFFE08A00),
      );
    } else if (title.isInLibrary) {
      status = null;
    } else if (library.downloading ||
        library.status == StremfinLibraryStatus.downloading) {
      status = (
        text: l10n.kostvDiscoverComingSoon,
        color: const Color(0xFF1E88E5),
      );
    } else if (request != null) {
      status = (
        text: request.mine
            ? l10n.kostvDiscoverRequestedByYou
            : l10n.kostvDiscoverRequested,
        color: const Color(0xFF6D4AFF),
      );
    } else {
      status = null;
    }
    final checkSize = 26 * pillScale;
    final bandHeight = 20 * pillScale;

    return [
      if (top.isNotEmpty)
        Positioned(
          top: 6,
          left: 6,
          right: 6,
          child: Wrap(spacing: 4, runSpacing: 4, children: top),
        ),
      // The tick of a title on the server: top right, or bottom right when
      // the top holds labels (above the band, if there is one).
      if (title.isInLibrary)
        Positioned(
          top: top.isEmpty ? 6 : null,
          bottom: top.isEmpty ? null : (status == null ? 6 : bandHeight + 4),
          right: 6,
          child: Tooltip(
            message: l10n.kostvDiscoverInLibrary,
            child: Container(
              width: checkSize,
              height: checkSize,
              decoration: const BoxDecoration(
                color: Color(0xFF2EAD5B),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
              ),
              child: Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 18 * pillScale,
              ),
            ),
          ),
        ),
      if (list == StremfinTopList.popular && rank != null)
        Positioned(
          left: 4,
          bottom: status == null ? -6 : bandHeight - 4,
          child: _RankNumber(rank: rank, height: imageHeight * 0.3),
        ),
      // How it stands, as a band across the bottom, wide enough for the
      // words even on a small poster.
      if (status != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: bandHeight,
            alignment: Alignment.center,
            color: status.color.withValues(alpha: 0.92),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              status.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 11.5 * pillScale,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ),
    ];
  }
}

/// A platform button: its logo on its colour; full colour when chosen.
class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.platform,
    required this.width,
    required this.height,
    required this.selected,
    required this.focused,
    required this.focusColor,
    required this.onTap,
  });

  final StremfinPlatform platform;
  final double width;
  final double height;
  final bool selected;
  final bool focused;
  final Color focusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = platform.color;
    final radius = BorderRadius.circular(14);
    final logo = _platformLogos[platform.id];
    final Widget content;
    if (platform.isAll) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KosRingMark(size: height * 0.42),
          SizedBox(width: height * 0.14),
          Text(
            l10n.kostvDiscoverAll,
            style: TextStyle(
              color: Colors.white,
              fontFamily: KosBrand.fontFamily,
              fontSize: height * 0.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    } else {
      final name = Text(
        platform.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: height * 0.26,
          fontWeight: FontWeight.w800,
        ),
      );
      content = logo == null
          ? name
          : Image.network(
              logo,
              height: height * 0.42,
              width: width * 0.62,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => name,
            );
    }

    final base = color ?? const Color(0xFF2A2140);
    final background = selected
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: platform.isAll
                ? [KosBrand.violet, const Color(0xFF3B2A7A)]
                : [base, Color.lerp(base, Colors.black, 0.45)!],
          )
        : LinearGradient(
            colors: [
              Color.lerp(base, AppColorScheme.background, 0.72)!,
              Color.lerp(base, AppColorScheme.background, 0.8)!,
            ],
          );

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: focused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedOpacity(
            opacity: selected || focused ? 1 : 0.7,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: height * 0.18),
              decoration: BoxDecoration(
                gradient: background,
                borderRadius: radius,
                border: Border.all(
                  color: focused
                      ? focusColor
                      : (selected
                            ? Colors.white.withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.08)),
                  width: focused ? 3 : 1.5,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: focusColor.withValues(alpha: 0.45),
                          blurRadius: 18,
                        ),
                      ]
                    : null,
              ),
              child: FittedBox(fit: BoxFit.scaleDown, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small label over a poster.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, required this.scale});

  final String text;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6 * scale),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11.5 * scale,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

/// The place on a most-watched list, large, in the corner of the poster.
class _RankNumber extends StatelessWidget {
  const _RankNumber({required this.rank, required this.height});

  final int rank;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: KosBrand.fontFamily,
      fontSize: height,
      fontWeight: FontWeight.w900,
      height: 1,
      letterSpacing: -height * 0.06,
    );
    return Stack(
      children: [
        Text(
          '$rank',
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = height * 0.06
              ..color = Colors.black.withValues(alpha: 0.85),
          ),
        ),
        Text(
          '$rank',
          style: style.copyWith(
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
      ],
    );
  }
}
