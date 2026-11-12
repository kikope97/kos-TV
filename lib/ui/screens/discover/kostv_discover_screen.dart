import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/focus/hub_focus_memory.dart';
import '../../widgets/focus/locked_focus_row.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/horizontal_scroll_section.dart';
import '../../widgets/kos_logo.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_discover_hero.dart';
import 'kostv_discover_parts.dart';
import 'kostv_discover_spotlight.dart';

/// Kos TV: what's on the streaming platforms, from the requests service. A
/// button per platform on top (and one for all of them), then the most
/// watched and the newest series and films of the one chosen. What's on the
/// home server is in colour and opens its page; the rest is grey.
///
/// On a TV or a computer a spotlight fills the top: the title the focus (or
/// the pointer) is on, large, over its art, with how it stands at home. On a
/// phone the first few of the first row turn on a carousel.
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

String _keyOf(StremfinTitle title) => '${title.type.apiValue}:${title.tmdbId}';

/// The sizes of the page on a TV or a computer, from the height of the
/// screen: posters about three tenths of it, a row and the name of the next
/// at the foot, and the spotlight in what is left above.
@immutable
class _WideMetrics {
  const _WideMetrics({
    required this.unit,
    required this.top,
    required this.pillHeight,
    required this.pillWidth,
    required this.pillsBand,
    required this.poster,
    required this.cardWidth,
    required this.headerHeight,
    required this.headroom,
    required this.footroom,
    required this.rowsRoom,
    required this.textWidth,
  });

  factory _WideMetrics.of(
    Size size,
    EdgeInsets insets,
    double uiScale, {
    required bool expansion,
  }) {
    final height = size.height;
    final unit = (height / 540 * uiScale).clamp(0.85, 1.6);
    final pillHeight = 38 * unit;
    final pillsBand = pillHeight + 22 * unit;
    final headerHeight = 34 * unit;
    final peek = 40 * unit;
    var poster = (height * 0.29).clamp(120.0, 330.0);
    double rowsRoom(double poster) =>
        headerHeight +
        _headroomFor(poster, expansion) +
        poster +
        _footroomFor(poster, expansion) +
        peek;
    // The spotlight keeps room for its words; the posters give way if not.
    final minSpotlight = 138 * unit;
    final spotlight = height - insets.top - pillsBand - rowsRoom(poster);
    if (spotlight < minSpotlight) {
      poster = math.max(100, poster - (minSpotlight - spotlight));
    }
    return _WideMetrics(
      unit: unit,
      top: insets.top,
      pillHeight: pillHeight,
      pillWidth: pillHeight * 3.4,
      pillsBand: pillsBand,
      poster: poster,
      cardWidth: poster * 2 / 3,
      headerHeight: headerHeight,
      headroom: _headroomFor(poster, expansion),
      footroom: _footroomFor(poster, expansion),
      rowsRoom: rowsRoom(poster),
      textWidth: math.min(size.width * 0.5, 600 * unit),
    );
  }

  /// Room over a poster for it to grow with the focus, and for its ring. A
  /// card that grows from its foot needs it all above.
  static double _headroomFor(double poster, bool expansion) {
    final growth = poster * (MediaCard.focusScale - 1);
    return (expansion ? growth : growth / 2) + MediaCard.focusRingOutset + 2;
  }

  static double _footroomFor(double poster, bool expansion) {
    final growth = poster * (MediaCard.focusScale - 1);
    return (expansion ? 0 : growth / 2) + MediaCard.focusRingOutset + 6;
  }

  final double unit;
  final double top;
  final double pillHeight;
  final double pillWidth;
  final double pillsBand;
  final double poster;
  final double cardWidth;
  final double headerHeight;
  final double headroom;
  final double footroom;

  /// The rows' room at the foot: one row, and the name of the next.
  final double rowsRoom;
  final double textWidth;

  double get rowHeight => headerHeight + headroom + poster + footroom;
}

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

  /// The card the spotlight shows: its row and which it is. Null for the
  /// first of the first row (the focus is on the platforms, or nowhere).
  ({_RowSpec spec, String key})? _spot;
  late final _follower = KostvSpotlightFollower(
    KostvSpotlightDetails(_service),
    _onExtra,
  );
  Timer? _hoverDebounce;

  /// The focus is down in the rows: with a remote or a keyboard, the
  /// platforms fold away to give them room.
  bool _inRows = false;

  /// On a TV or a computer, the height of a row: a wheel or a drag that
  /// stops between two settles on the nearer.
  double? _rowExtent;
  Timer? _settleRows;

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
    _scrollController.addListener(_onRowsScrolled);
  }

  @override
  void dispose() {
    _selectDebounce?.cancel();
    _hoverDebounce?.cancel();
    _settleRows?.cancel();
    _follower.dispose();
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
                _followSpotlight();
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
    _followSpotlight();
  }

  void _selectPlatform(StremfinPlatform platform) {
    _selectDebounce?.cancel();
    if (platform.id == _platformId) return;
    _lastPlatform = platform.id;
    setState(() {
      _platformId = platform.id;
      _spot = null;
    });
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
    _followSpotlight();
  }

  /// The rows were scrolled: once they rest, the nearer row comes up whole
  /// under the spotlight.
  void _onRowsScrolled() {
    final extent = _rowExtent;
    if (extent == null || PlatformDetection.useMobileUi) return;
    _settleRows?.cancel();
    _settleRows = Timer(const Duration(milliseconds: 160), () {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.isScrollingNotifier.value) return;
      final offset = position.pixels;
      final target = ((offset / extent).round() * extent).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - offset).abs() < 1) return;
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  // -------------------------------------------------------- the spotlight

  /// The title the spotlight shows, with its row and place.
  ({StremfinTitle title, _RowSpec spec})? get _spotlit {
    final spot = _spot;
    if (spot != null) {
      for (final title in _rows[spot.spec]!.items) {
        if (_keyOf(title) == spot.key) return (title: title, spec: spot.spec);
      }
    }
    for (final spec in _rowSpecs) {
      final items = _rows[spec]!.items;
      if (items.isNotEmpty) return (title: items.first, spec: spec);
    }
    return null;
  }

  void _followSpotlight() => _follower.show(_spotlit?.title);

  void _onExtra() {
    if (mounted) setState(() {});
  }

  /// A card took the focus, or the pointer rested on it.
  void _spotlight(_RowSpec spec, StremfinTitle title) {
    final key = _keyOf(title);
    if (_spot?.spec == spec && _spot?.key == key) return;
    void apply() {
      if (!mounted) return;
      setState(() => _spot = (spec: spec, key: key));
      _followSpotlight();
    }

    // A row can report its card while it is being built.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  void _onHover(_RowSpec spec, StremfinTitle title) {
    _hoverDebounce?.cancel();
    _hoverDebounce = Timer(
      const Duration(milliseconds: 160),
      () => _spotlight(spec, title),
    );
  }

  void _setInRows(bool inRows) {
    if (_inRows == inRows) return;
    void apply() {
      if (!mounted || _inRows == inRows) return;
      setState(() {
        _inRows = inRows;
        // Back on the platforms: the spotlight shows the first again.
        if (!inRows) _spot = null;
      });
      if (!inRows) _followSpotlight();
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  KostvSpotlightSource _sourceOf(
    StremfinTitle title,
    _RowSpec spec,
    AppLocalizations l10n,
  ) {
    final platform = _platform;
    final from = title.platform == null
        ? null
        : _platforms.where((p) => p.id == title.platform).firstOrNull;
    final season = title.season;
    return KostvSpotlightSource(
      rowTitle: spec.title(l10n, platform),
      rank: spec.list == StremfinTopList.popular ? title.rank : null,
      season:
          spec.list == StremfinTopList.fresh &&
              title.type == StremfinTitleType.series &&
              season != null
          ? (season == 1
                ? l10n.kostvDiscoverBrandNewSeries
                : l10n.kostvDiscoverNewSeason(season))
          : null,
      platform: platform.isAll ? from : null,
    );
  }

  // ------------------------------------------------------------- the page

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = PlatformDetection.useMobileUi;
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.kostvDiscover,
        // The spotlight stays put; so does the bar over it.
        pinTopToolbar: !phone,
        child: _withInitialFocus(
          Stack(
            fit: StackFit.expand,
            children: [
              if (phone) ...[_platformGlow(), _phone(l10n)] else _wide(l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// The chosen platform's colour, faint, from the top corner.
  Widget _platformGlow() {
    final tint = _platform.color ?? KosBrand.violet;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.9, -1.1),
          radius: 1.4,
          colors: [
            tint.withValues(alpha: 0.26),
            tint.withValues(alpha: 0.06),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
    );
  }

  bool get _allFailed =>
      _rowSpecs.every((s) => _rows[s]!.failed && _rows[s]!.items.isEmpty);

  Widget _unavailable(AppLocalizations l10n) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        l10n.kostvDiscoverUnavailable,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColorScheme.onSurface.withValues(alpha: 0.8),
          fontSize: 18,
        ),
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: () => setState(() => _loadLists(refresh: true)),
        child: Text(l10n.retry),
      ),
    ],
  );

  /// With a remote or a keyboard the platforms take focus on arrival; on a
  /// touch screen nothing does, so no focus ring sits on a tile.
  Widget _withInitialFocus(Widget child) => PlatformDetection.useMobileUi
      ? child
      : RequestInitialFocus(targetNode: _platformFocus, child: child);

  /// The top of the page on a TV or a computer: under the bar on top, a
  /// little closer than other pages since the spotlight runs behind it.
  EdgeInsets _wideInsets(BuildContext context) {
    final insets = calendarChromeInsets(context);
    if (!_navbarOnTop) return insets;
    return insets.copyWith(
      top: insets.top - (PlatformDetection.isTV ? 22 : 10),
    );
  }

  // ------------------------------------------------- TV and computer

  Widget _wide(AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, box) {
        final insets = _wideInsets(context);
        final uiScale = PlatformDetection.isTV
            ? 1.0
            : _prefs.get(UserPreferences.desktopUiScale).scaleFactor;
        final m = _WideMetrics.of(
          box.biggest,
          insets,
          uiScale,
          expansion: _prefs.get(UserPreferences.cardFocusExpansion),
        );
        final spot = _spotlit;
        final background = AppColorScheme.background;
        // Folded away only for a remote or a keyboard: a pointer can reach
        // them wherever it is.
        final folded =
            _inRows && InputModeTracker.of(context) == InputMode.keyboard;
        final artHeight = box.maxHeight - m.rowsRoom + 40 * m.unit;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: artHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Over the right three quarters; its left edge stays
                  // under the fade, which is whole there.
                  FractionallySizedBox(
                    alignment: Alignment.centerRight,
                    widthFactor: 0.74,
                    child: KostvSpotlightArt(
                      title: spot?.title,
                      backdrop:
                          _follower.extra?.backdrop ?? spot?.title.backdrop,
                    ),
                  ),
                  // Fades into the page to the left and below.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          background,
                          background,
                          background.withValues(alpha: 0.75),
                          background.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.28, 0.42, 0.72],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          background,
                          background.withValues(alpha: 0.6),
                          background.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.22, 0.55],
                      ),
                    ),
                  ),
                  // A shade under the bar on top, so it reads over light art.
                  if (_navbarOnTop)
                    Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: m.top + 12,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.45),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Over the art, so the colour runs on across it.
            _platformGlow(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: m.top),
                ClipRect(
                  child: AnimatedAlign(
                    alignment: Alignment.bottomCenter,
                    heightFactor: folded ? 0 : 1,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: folded ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        height: m.pillsBand,
                        child: _buildPills(
                          height: m.pillHeight,
                          width: m.pillWidth,
                          spacing: 12 * m.unit,
                          padding: EdgeInsets.fromLTRB(
                            insets.left,
                            8 * m.unit,
                            insets.right,
                            14 * m.unit,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // The spotlight takes what the rows leave, and grows when
                // the platforms fold away.
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      insets.left,
                      0,
                      insets.right,
                      6 * m.unit,
                    ),
                    child: LayoutBuilder(
                      builder: (context, room) => Align(
                        alignment: Alignment.bottomLeft,
                        child: SizedBox(
                          width: m.textWidth,
                          child: _spotlightText(
                            spot,
                            m,
                            l10n,
                            room: room.maxHeight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: m.rowsRoom,
                  child: _allFailed
                      ? Center(child: _unavailable(l10n))
                      : _wideRows(m, insets, l10n),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _spotlightText(
    ({StremfinTitle title, _RowSpec spec})? spot,
    _WideMetrics m,
    AppLocalizations l10n, {
    required double room,
  }) {
    if (spot == null) return const SizedBox.shrink();
    // As many lines of what it's about as the room above the rows allows.
    final space = room / m.unit;
    final lines = space >= 236 ? 3 : (space >= 186 ? 2 : 0);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomLeft,
      child: SizedBox(
        width: m.textWidth,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.bottomLeft,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: KostvSpotlightText(
            key: ValueKey(
              '${spot.spec.type.name}${spot.spec.list.name}'
              '|${_keyOf(spot.title)}',
            ),
            title: spot.title,
            source: _sourceOf(spot.title, spot.spec, l10n),
            extra: _follower.extra,
            unit: m.unit,
            overviewLines: lines,
          ),
        ),
      ),
    );
  }

  Widget _wideRows(_WideMetrics m, EdgeInsets insets, AppLocalizations l10n) {
    final rows = _visibleRows;
    _rowExtent = m.rowHeight;
    return LayoutBuilder(
      builder: (context, box) => ClipRect(
        // The rows scroll inside their own room; the bar on top stays.
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) => true,
          child: ListView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            // Room under the last row for it to come up under the spotlight.
            padding: EdgeInsets.only(
              bottom: math.max(0, box.maxHeight - m.rowHeight),
            ),
            children: [
              for (final spec in rows)
                _rowSection(
                  child: _buildRow(
                    spec,
                    imageHeight: m.poster,
                    cardWidth: m.cardWidth,
                    headroom: m.headroom,
                    footroom: m.footroom,
                    headerPadding: EdgeInsets.fromLTRB(
                      insets.left,
                      6 * m.unit,
                      insets.right,
                      2 * m.unit,
                    ),
                    titleSize: 19 * m.unit,
                    insets: insets,
                    labels: false,
                    l10n: l10n,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Brings a row into view when it takes the focus: to the top of the
  /// rows' room on a TV or a computer, a little down from the top on a
  /// phone.
  Widget _rowSection({required Widget child}) {
    final phone = PlatformDetection.useMobileUi;
    return Builder(
      builder: (sectionContext) => Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onFocusChange: (hasFocus) {
          if (!hasFocus) return;
          _setInRows(true);
          unawaited(
            Scrollable.ensureVisible(
              sectionContext,
              alignment: phone ? 0.15 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            ),
          );
        },
        child: child,
      ),
    );
  }

  // ------------------------------------------------------------ phone

  Widget _phone(AppLocalizations l10n) {
    final insets = calendarChromeInsets(context);
    final width = MediaQuery.sizeOf(context).width;
    final usable = width - insets.left - insets.right;
    // About three posters and a bit across a phone, more on a tablet.
    final perRow = math.max(3.25, usable / 170);
    final cardWidth = ((usable - 12 * (perRow.floor())) / perRow).clamp(
      96.0,
      180.0,
    );
    final imageHeight = cardWidth * 3 / 2;
    final count = _platforms.length.clamp(1, 4);
    final pillWidth = ((usable - 8 * (count - 1)) / count).clamp(72.0, 180.0);
    final highlights = _highlights(l10n);

    return BottomNavPadded(
      fallback: 48,
      builder: (context, bottom) => ListView(
        controller: _scrollController,
        padding: EdgeInsets.only(top: insets.top, bottom: bottom),
        children: [
          _buildPills(
            height: 38,
            width: pillWidth,
            spacing: 8,
            padding: EdgeInsets.fromLTRB(insets.left, 4, insets.right, 8),
          ),
          if (_allFailed)
            Padding(
              padding: EdgeInsets.fromLTRB(insets.left, 48, insets.right, 0),
              child: _unavailable(l10n),
            )
          else ...[
            if (highlights.isNotEmpty)
              KostvDiscoverHero(
                key: ValueKey('hero_$_platformId'),
                items: highlights,
                onOpen: _openTitle,
                width: width,
              ),
            for (final spec in _visibleRows)
              _rowSection(
                child: _buildRow(
                  spec,
                  imageHeight: imageHeight,
                  cardWidth: cardWidth,
                  headroom: 4,
                  footroom: 4,
                  headerPadding: EdgeInsets.fromLTRB(
                    insets.left,
                    18,
                    insets.right,
                    6,
                  ),
                  titleSize: 18,
                  insets: insets,
                  labels: true,
                  l10n: l10n,
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// The phone's carousel: the first of each row, then the second of each,
  /// eight at most.
  List<({StremfinTitle title, KostvSpotlightSource source})> _highlights(
    AppLocalizations l10n,
  ) {
    final picked = <({StremfinTitle title, KostvSpotlightSource source})>[];
    final seen = <String>{};
    for (var round = 0; round < 2; round++) {
      for (final spec in _rowSpecs) {
        final items = _rows[spec]!.items;
        if (round >= items.length || picked.length >= 8) continue;
        final title = items[round];
        // A title on two rows comes once.
        if (!seen.add(_keyOf(title))) continue;
        picked.add((title: title, source: _sourceOf(title, spec, l10n)));
      }
    }
    return picked;
  }

  // ------------------------------------------------------- shared parts

  Widget _buildPills({
    required double height,
    required double width,
    required double spacing,
    required EdgeInsets padding,
  }) {
    final mobile = PlatformDetection.useMobileUi;
    final focusColor = Color(_prefs.get(UserPreferences.focusColor).colorValue);
    final growth = height * 0.07;
    return LockedFocusRow<StremfinPlatform>(
      key: _platformRowKey,
      hubKey: _platformHub,
      items: _platforms,
      itemKey: (p, _) => p.id,
      focusNode: _platformFocus,
      autofocus: !mobile,
      itemExtent: width,
      itemSpacing: spacing,
      height: height + padding.vertical,
      clipBehavior: Clip.none,
      padding: padding.copyWith(left: padding.left + growth),
      onIndexChanged: (_, p) => _onPlatformFocused(p),
      onFocusChange: (has) {
        if (has) _setInRows(false);
      },
      onTap: (_, p) => _selectPlatform(p),
      onVerticalNavigation: _onPlatformVertical,
      onLeftEdge: _onLeftEdge,
      itemBuilder: (context, platform, index, focused) => Center(
        child: KostvPlatformPill(
          platform: platform,
          width: width,
          height: height,
          selected: platform.id == _platformId,
          // A ring only for a remote or the keyboard, never after a touch.
          focused: InputModeTracker.showFocusVisuals(context, focused),
          focusColor: focusColor,
          onTap: () => _selectPlatform(platform),
        ),
      ),
    );
  }

  Widget _buildRow(
    _RowSpec spec, {
    required double imageHeight,
    required double cardWidth,
    required double headroom,
    required double footroom,
    required EdgeInsets headerPadding,
    required double titleSize,
    required EdgeInsets insets,
    required bool labels,
    required AppLocalizations l10n,
  }) {
    final row = _rows[spec]!;
    final expansion = _prefs.get(UserPreferences.cardFocusExpansion);
    final focusColor = Color(_prefs.get(UserPreferences.focusColor).colorValue);
    final spacing = PlatformDetection.useMobileUi
        ? 12.0
        : MediaCard.focusGap(cardWidth, minimum: cardWidth * 0.1);
    // The poster, plus the title and year under it on a phone.
    final labelHeight = labels
        ? MediaCard.layoutHeight(
                context,
                width: cardWidth,
                aspectRatio: 2 / 3,
                hasSubtitle: true,
              ) -
              imageHeight
        : 0.0;
    final rowHeight = headroom + imageHeight + labelHeight + footroom;
    final platform = _platform;

    return HorizontalScrollSection(
      title: spec.title(l10n, platform),
      titleStyle: TextStyle(
        color: AppColorScheme.onSurface,
        fontSize: titleSize,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      headerPadding: headerPadding,
      contentSpacing: 0,
      showControls: row.items.isNotEmpty && PlatformDetection.useDesktopUi,
      builder: (context, controller) => SizedBox(
        height: rowHeight,
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
                itemKey: (t, _) => _keyOf(t),
                controller: controller,
                itemExtent: cardWidth,
                itemSpacing: spacing,
                height: rowHeight,
                clipBehavior: Clip.none,
                padding: EdgeInsets.fromLTRB(
                  insets.left,
                  headroom,
                  insets.right,
                  footroom,
                ),
                onIndexChanged: (_, title) => _spotlight(spec, title),
                onVerticalNavigation: (isUp) => _onRowVertical(spec, isUp),
                onLeftEdge: _onLeftEdge,
                onTap: (_, title) => _openTitle(title),
                itemBuilder: (context, title, index, focused) => MediaCard(
                  title: title.title,
                  subtitle: labels ? title.year?.toString() : null,
                  showLabel: labels,
                  imageUrl: title.poster,
                  width: cardWidth,
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
                  imageColorFilter: title.isInLibrary
                      ? null
                      : kostvMissingFilter,
                  subtitleColor: title.isInLibrary
                      ? null
                      : AppColorScheme.onSurface.withValues(alpha: 0.5),
                  onTap: () => _openTitle(title),
                  onHoverStart: labels ? null : () => _onHover(spec, title),
                  imageOverlays: _badges(
                    title,
                    list: spec.list,
                    platform: platform,
                    imageHeight: imageHeight,
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
    final rank = title.rank;
    final pillScale = (imageHeight / 216).clamp(0.8, 1.3);
    final source = title.platform == null
        ? null
        : _platforms.where((p) => p.id == title.platform).firstOrNull;

    // Top left: its place, where it comes from, and the season just out.
    final top = <Widget>[
      if (list == StremfinTopList.popular && rank != null)
        KostvRankTag(rank: rank, scale: pillScale),
      if (platform.isAll && source != null)
        KostvPosterPill(
          text: source.name,
          color: source.color ?? Colors.black54,
          scale: pillScale,
        ),
      if (list == StremfinTopList.fresh &&
          title.type == StremfinTitleType.series &&
          title.season != null)
        KostvPosterPill(
          text: title.season == 1
              ? l10n.kostvDiscoverBrandNewSeries
              : l10n.kostvDiscoverNewSeason(title.season!),
          color: Colors.black.withValues(alpha: 0.72),
          scale: pillScale,
        ),
    ];

    // Bottom: how it stands at home.
    final status = KostvTitleStatus.band(title, l10n);
    final bandHeight = 20 * pillScale;

    return [
      if (top.isNotEmpty)
        Positioned(
          top: 6,
          left: 6,
          right: 6,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: top,
          ),
        ),
      // The tick of a title at home: top right, above the band if any.
      if (title.isInLibrary)
        Positioned(
          top: status == null ? 6 : null,
          bottom: status == null ? null : bandHeight + 4,
          right: 6,
          child: KostvHomeTick(scale: pillScale),
        ),
      if (status != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: bandHeight,
            alignment: Alignment.center,
            color: status.color!.withValues(alpha: 0.92),
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
