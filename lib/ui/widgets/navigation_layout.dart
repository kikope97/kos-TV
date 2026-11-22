import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/app_localizations.dart';
import '../../util/platform_detection.dart';
import '../navigation/destinations.dart';
import '../navigation/route_lifecycle_observer.dart';
import 'bottom_nav/bottom_navbar.dart';
import 'bottom_nav/bottom_mini_player.dart';
import 'bottom_nav/bottom_nav_metrics.dart';
import 'download_progress_bar.dart';
import 'kostv_menu/kostv_glass.dart';
import 'kostv_menu/kostv_page_header.dart';
import 'music/kostv_now_playing.dart';
import 'top_toolbar.dart';

/// Kos TV: the menu around every page. There is one design, with no way to
/// change it (the owner's decision, 2026-11-22): on a TV and on a computer
/// the bar of named tabs at the top, which gathers into a small pill while
/// the page is scrolled on a TV; on phones and tablets (and the web in a
/// narrow window) the glass bar at the bottom (see [BottomNavbar]).
class NavigationLayout extends StatefulWidget {
  final String? activeRoute;
  final Widget child;
  final bool showBackButton;
  final bool showNavigationChrome;

  /// Keep the top bar whole instead of gathering it into its pill as the
  /// content scrolls. No effect off-TV, where the bar never gathers.
  final bool pinTopToolbar;

  /// Kos TV: the page is one the glass bar leads to (Inicio, Descubrir,
  /// Música, Tú), not one opened inside it: on phones and tablets it has
  /// the menu's large header (docs/diseno-menu).
  final bool largeHeader;

  /// Whether the menu is the glass bar at the bottom: phones and tablets,
  /// and the web in a narrow window.
  static bool get usesBottomNavbar => PlatformDetection.useMobileUi;

  /// Whether the menu is the bar of tabs at the top: a TV and a computer.
  static bool get usesTopToolbar => !usesBottomNavbar;

  /// Focus roots of the navigation chrome, registered by the toolbar while
  /// mounted. The route focus observer refuses to land inside these, so a
  /// fresh route waits for content instead of starting the d-pad in the menu
  /// before anything has loaded.
  static final Set<FocusNode> chromeFocusRoots = <FocusNode>{};

  static final focusNavbarNotifier = ValueNotifier<VoidCallback?>(null);
  static final focusNavbarAvatarNotifier = ValueNotifier<VoidCallback?>(null);
  static final focusContentFromNavbarNotifier = ValueNotifier<VoidCallback?>(
    null,
  );
  static final focusDetailsPlayButtonNotifier = ValueNotifier<FocusNode?>(null);

  /// Hands focus to the play button a details page registered, and says
  /// whether it took it so the caller can fall back to its own choice.
  static bool focusDetailsPlayButton() {
    final node = focusDetailsPlayButtonNotifier.value;
    if (node == null || node.context == null || !node.canRequestFocus) {
      return false;
    }
    // Kos TV: only a details page on screen: one under a menu page still
    // has its button, and Down from the menu went into the hidden page.
    if (!(ModalRoute.isCurrentOf(node.context!) ?? true)) return false;
    node.requestFocus();
    return true;
  }

  /// True while a media bar trailer is playing. The toolbar fades out on TV
  /// and desktop, and focusing it cancels the trailer, which fades it back
  /// in.
  static final trailerImmersiveNotifier = ValueNotifier<bool>(false);

  // Set for a few seconds after the mouse moves, so the chrome is there to
  // reach while a trailer plays on desktop.
  static final _trailerChromeWoken = ValueNotifier<bool>(false);
  static Timer? _trailerChromeWakeTimer;

  static final trailerChromeListenable = Listenable.merge([
    trailerImmersiveNotifier,
    _trailerChromeWoken,
  ]);

  /// Whether a playing trailer has the toolbar and a peeking home row out of
  /// its way.
  static bool get trailerHidesChrome =>
      trailerImmersiveNotifier.value &&
      !PlatformDetection.useMobileUi &&
      !_trailerChromeWoken.value;

  static void _wakeTrailerChrome() {
    if (!trailerImmersiveNotifier.value) return;
    _trailerChromeWoken.value = true;
    _trailerChromeWakeTimer?.cancel();
    _trailerChromeWakeTimer = Timer(
      const Duration(seconds: 3),
      () => _trailerChromeWoken.value = false,
    );
  }

  /// Hands focus to the navbar and reports whether there was one to take it.
  /// Callers need the answer so they only report a key as handled when focus
  /// really moved.
  static bool focusNavbar() {
    final callback = focusNavbarNotifier.value;

    if (callback == null) {
      return false;
    }

    callback();

    return true;
  }

  const NavigationLayout({
    super.key,
    this.activeRoute,
    required this.child,
    this.showBackButton = false,
    this.showNavigationChrome = true,
    this.pinTopToolbar = false,
    this.largeHeader = false,
  });

  @override
  State<NavigationLayout> createState() => _NavigationLayoutState();
}

class _NavigationLayoutState extends State<NavigationLayout>
    with WidgetsBindingObserver, RouteAware {
  final _contentFocusNode = FocusNode(debugLabel: 'NavigationContent');
  final _contentKey = GlobalKey(debugLabel: 'navigationLayoutContent');
  bool _keyboardVisible = false;

  // Kos TV: the vertical scrollables of the page that are past their top, by
  // context. Off the TV the top bar stays put, so a page scrolled under it
  // runs its cards right behind the avatar and the tabs: a soft shade comes
  // in behind the bar once the page leaves its top. On the TV, the same
  // gathers the bar into its pill.
  final _scrolledScrollables = <BuildContext>{};
  final _contentScrolled = ValueNotifier<bool>(false);
  late final Listenable _scrollShadeListenable = Listenable.merge([
    _contentScrolled,
    NavigationLayout.trailerChromeListenable,
  ]);

  // Kos TV: the TV's bar gathers into its pill once the page is this far
  // down, and while the focus is outside it.
  final _toolbarCollapsed = ValueNotifier<bool>(false);
  double _tvScrollOffset = 0;
  static const _kCollapseAfter = 24.0;

  // The bottom bar gathers while the user scrolls down and comes back on the
  // way up. The flag only flips at the thresholds, so scrolling rebuilds
  // nothing.
  final _bottomMinimized = ValueNotifier<bool>(false);

  // Kos TV: how far the page is scrolled, for its large header.
  final _headerOffset = ValueNotifier<double>(0);

  // Kos TV: the page's own list, to take it back to the top when its tab is
  // tapped again.
  BuildContext? _pageScrollable;

  void _scrollPageToTop() {
    final scrollable = _pageScrollable;
    if (scrollable == null || !scrollable.mounted) return;
    final position = Scrollable.maybeOf(scrollable)?.position;
    if (position == null || position.pixels <= position.minScrollExtent) {
      return;
    }
    position.animateTo(
      position.minScrollExtent,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  bool _userScrolling = false;
  double _scrollTravel = 0;
  ModalRoute<dynamic>? _observedRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TopToolbar.isFocusedNotifier.addListener(_updateToolbarCollapsed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || route == _observedRoute) return;
    if (_observedRoute != null) routeLifecycleObserver.unsubscribe(this);
    _observedRoute = route;
    routeLifecycleObserver.subscribe(this, route);
  }

  @override
  void didUpdateWidget(NavigationLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeRoute != widget.activeRoute) {
      _expandBottomBar();
      _headerOffset.value = 0;
      _scrolledScrollables.clear();
      _contentScrolled.value = false;
      _tvScrollOffset = 0;
      _updateToolbarCollapsed();
    }
    if (oldWidget.pinTopToolbar != widget.pinTopToolbar) {
      _updateToolbarCollapsed();
    }
  }

  bool _onToolbarContentScroll(ScrollNotification n) {
    // Rows of cards scroll sideways, and a box scrolling inside a card isn't
    // the page.
    if (n.metrics.axis != Axis.vertical || n.depth > 1) return false;
    final scrollable = n.context;
    if (scrollable == null) return false;
    if (n.metrics.pixels > n.metrics.minScrollExtent + 0.5) {
      _scrolledScrollables.add(scrollable);
    } else {
      _scrolledScrollables.remove(scrollable);
    }
    // A list that was swapped out (a page done loading) says no more.
    _scrolledScrollables.removeWhere((c) => !c.mounted);
    final scrolled = _scrolledScrollables.isNotEmpty;
    if (scrolled != _contentScrolled.value) _contentScrolled.value = scrolled;
    return false;
  }

  bool _onTvContentScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    _tvScrollOffset = n.metrics.pixels - n.metrics.minScrollExtent;
    _updateToolbarCollapsed();
    return false;
  }

  /// Kos TV: the TV's bar is a pill while the page is scrolled down and the
  /// focus is in the page; with the focus in the bar (Back or Up bring it
  /// there) it is whole again.
  void _updateToolbarCollapsed() {
    final collapsed =
        PlatformDetection.isTV &&
        !widget.pinTopToolbar &&
        !TopToolbar.isFocusedNotifier.value &&
        _tvScrollOffset > _kCollapseAfter;
    if (collapsed != _toolbarCollapsed.value) {
      _toolbarCollapsed.value = collapsed;
    }
  }

  // Home stays mounted under whatever it pushes, so coming back to it, or
  // leaving it, starts the bar out whole again.
  @override
  void didPushNext() => _expandBottomBar();

  @override
  void didPopNext() => _expandBottomBar();

  void _expandBottomBar() {
    _scrollTravel = 0;
    _bottomMinimized.value = false;
  }

  bool _onBottomScroll(ScrollNotification n) {
    // Rows of cards scroll sideways and a nested list isn't the page.
    if (n.metrics.axis != Axis.vertical || n.depth > 1) return false;

    // Only a finger moves the bar. A jump back to the top, a D-pad scroll or
    // a row snapping into view shouldn't. A drag starts at the top, so this
    // is noted before the top check below can return.
    if (n is UserScrollNotification) {
      _userScrolling = n.direction != ScrollDirection.idle;
      _scrollTravel = 0;
    }

    final metrics = n.metrics;
    // The page's own list (not one inside it) moves its large header.
    if (n.depth == 0) {
      _pageScrollable = n.context;
      final offset = (metrics.pixels - metrics.minScrollExtent).clamp(
        0.0,
        120.0,
      );
      if ((offset - _headerOffset.value).abs() >= 0.5 ||
          (offset == 0) != (_headerOffset.value == 0)) {
        _headerOffset.value = offset;
      }
    }
    if (metrics.pixels <= metrics.minScrollExtent + 8) {
      _expandBottomBar();
      return false;
    }
    if (n is ScrollUpdateNotification &&
        _userScrolling &&
        metrics.maxScrollExtent > 120) {
      final delta = n.scrollDelta ?? 0;
      if (delta.sign != _scrollTravel.sign) _scrollTravel = 0;
      _scrollTravel += delta;
      if (_scrollTravel > 24 && metrics.pixels > 56) {
        _bottomMinimized.value = true;
      } else if (_scrollTravel < -16) {
        _bottomMinimized.value = false;
      }
    }
    return false;
  }

  @override
  void dispose() {
    if (_observedRoute != null) routeLifecycleObserver.unsubscribe(this);
    TopToolbar.isFocusedNotifier.removeListener(_updateToolbarCollapsed);
    _bottomMinimized.dispose();
    _headerOffset.dispose();
    _toolbarCollapsed.dispose();
    _contentScrolled.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _contentFocusNode.dispose();
    super.dispose();
  }

  // MediaQuery can't be used for this: the Scaffold strips view insets from
  // the body the layout sits in.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    final visible = view.viewInsets.bottom / view.devicePixelRatio > 0;
    if (visible != _keyboardVisible) setState(() => _keyboardVisible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = NavigationLayout.usesBottomNavbar;
    // Kos TV: the bottom bar carries its own music player, so the floating
    // one steps aside on its pages.
    // On a computer the menu's own glass accessory plays it too.
    KostvNowPlayingRouteObserver.instance.setBottomBar(
      ModalRoute.of(context),
      bottom || _desktopPlayer,
    );
    final layout = bottom ? _buildBottomBar() : _buildToolbar();
    // Grouping only pays off when the tier draws real backdrop blurs, the
    // sheen tier never does.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (_) => NavigationLayout._wakeTrailerChrome(),
      child: kostvGlassBlurs ? BackdropGroup(child: layout) : layout,
    );
  }

  /// Keyed so the page that is already on screen is never torn down and built
  /// again when the window changes between narrow and wide.
  Widget get _content => KeyedSubtree(
    key: _contentKey,
    child: Focus(
      focusNode: _contentFocusNode,
      skipTraversal: true,
      child: widget.child,
    ),
  );

  /// Kos TV: the large header of the pages the glass bar leads to
  /// (docs/diseno-menu): its title and its buttons.
  ({String title, KostvPageHeaderActions actions})? _header(
    AppLocalizations l10n,
  ) => switch (widget.activeRoute) {
    Destinations.home => (
      title: l10n.home,
      actions: KostvPageHeaderActions.castAndInbox,
    ),
    Destinations.kostvDiscover => (
      title: l10n.kostvDiscover,
      actions: KostvPageHeaderActions.castAndInbox,
    ),
    Destinations.kostvMusic => (
      title: l10n.kostvMusic,
      actions: KostvPageHeaderActions.castAndInbox,
    ),
    Destinations.kostvYou => (
      title: l10n.navYou,
      actions: KostvPageHeaderActions.settings,
    ),
    _ => null,
  };

  Widget _buildBottomBar() {
    final content = _content;
    final header = widget.showNavigationChrome && widget.largeHeader
        ? _header(AppLocalizations.of(context))
        : null;
    final tablet = BottomNavMetrics.isTablet(MediaQuery.sizeOf(context));
    return Stack(
      children: [
        Positioned.fill(
          child: BottomNavInsetScope(
            height: BottomNavbar.heightFor(context),
            tabReturnsToTop: widget.largeHeader,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onBottomScroll,
              child: content,
            ),
          ),
        ),
        if (header != null)
          Positioned.fill(
            child: KostvPageHeader(
              key: ValueKey('kostvPageHeader-${widget.activeRoute}'),
              title: header.title,
              actions: header.actions,
              offset: _headerOffset,
            ),
          ),
        // The rows fade a little towards the glass bar (fadeBottom).
        if (widget.showNavigationChrome)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: tablet ? 200 : 150,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('kostvBarFade'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(tablet ? 0x9906060A : 0x8C06060A),
                      const Color(0x0006060A),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // The keyboard covers the bar anyway, and a bar riding up on top of
          // it would hide the field that brought it up.
          child: IgnorePointer(
            ignoring: _keyboardVisible,
            child: AnimatedSlide(
              offset: _keyboardVisible ? const Offset(0, 1.2) : Offset.zero,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: BottomNavbar(
                activeRoute: widget.activeRoute,
                chromeVisible: widget.showNavigationChrome,
                minimized: _bottomMinimized,
                onExpand: _expandBottomBar,
                onScrollToTop: _scrollPageToTop,
                // The download progress bar pads the system inset itself,
                // which it no longer touches once the bar sits under it.
                header: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: const DownloadProgressBar(),
                ),
              ),
            ),
          ),
        ),
        if (widget.showBackButton)
          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(child: _buildFloatingBackButton()),
          ),
      ],
    );
  }

  /// Kos TV: a computer's mini player is the menu's glass accessory, at the
  /// bottom right (ordenador_cristal).
  bool get _desktopPlayer =>
      !NavigationLayout.usesBottomNavbar && !PlatformDetection.isTV;

  Widget _buildToolbar() {
    final isTV = PlatformDetection.isTV;
    final content = _content;
    final toolbar = ListenableBuilder(
      listenable: NavigationLayout.trailerChromeListenable,
      builder: (context, child) {
        final show =
            widget.showNavigationChrome && !NavigationLayout.trailerHidesChrome;
        return AnimatedOpacity(
          opacity: show ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !show,
            // Hidden (under a trailer), its animations (the requests'
            // ring, the music bars) don't keep the screen redrawing.
            child: TickerMode(enabled: show, child: child!),
          ),
        );
      },
      // Its own layer: gathering into its pill doesn't repaint the page.
      child: RepaintBoundary(
        child: TopToolbar(
          activeRoute: widget.activeRoute,
          showBackButton: widget.showBackButton,
          contentFocusNode: _contentFocusNode,
          collapsed: _toolbarCollapsed,
        ),
      ),
    );
    final body = NotificationListener<ScrollNotification>(
      onNotification: isTV ? _onTvContentScroll : _onToolbarContentScroll,
      child: content,
    );
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: body),
              if (!isTV) _buildScrollShade(TopToolbar.heightFor(context)),
              // Kos TV: with the menu in use the page dims a little
              // (tele_A_foco).
              if (isTV)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        TopToolbar.litNotifier,
                        TopToolbar.openNotifier,
                      ]),
                      builder: (context, _) {
                        final dim = !widget.showNavigationChrome
                            ? 0.0
                            : TopToolbar.openNotifier.value
                            ? 0.45
                            : TopToolbar.litNotifier.value
                            ? 0.25
                            : 0.0;
                        return TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: dim),
                          duration: const Duration(milliseconds: 200),
                          builder: (context, a, _) => a <= 0
                              ? const SizedBox.expand()
                              : ColoredBox(
                                  color: Colors.black.withValues(alpha: a),
                                ),
                        );
                      },
                    ),
                  ),
                ),
              Positioned(left: 0, right: 0, top: 0, child: toolbar),
              if (_desktopPlayer)
                Positioned(
                  right: 28,
                  bottom: 24,
                  width: 372,
                  height: 60,
                  child: ListenableBuilder(
                    listenable: KostvNowPlaying.instance..ensureStarted(),
                    builder: (context, _) => bottomMiniPlayerHasTrack()
                        ? const KostvGlass(
                            key: ValueKey('kostvDesktopPlayer'),
                            child: BottomMiniPlayer(
                              height: 60,
                              variant: BottomMiniPlayerVariant.capsule,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              if (widget.showBackButton &&
                  !isTV &&
                  !widget.showNavigationChrome)
                Positioned(
                  top: 16,
                  left: 16,
                  child: SafeArea(child: _buildFloatingBackButton()),
                ),
            ],
          ),
        ),
        const DownloadProgressBar(),
      ],
    );
  }

  /// Kos TV: the shade behind the top bar while the page is scrolled under
  /// it: a plain gradient (no blur), on its own layer so fading it in
  /// doesn't repaint the page.
  Widget _buildScrollShade(double toolbarHeight) {
    final barBottom = MediaQuery.paddingOf(context).top + toolbarHeight;
    const fade = 40.0;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: barBottom + fade,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ListenableBuilder(
            listenable: _scrollShadeListenable,
            builder: (context, _) {
              final on =
                  _contentScrolled.value &&
                  widget.showNavigationChrome &&
                  !NavigationLayout.trailerHidesChrome;
              return TweenAnimationBuilder<double>(
                tween: Tween<double>(end: on ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                builder: (context, t, _) {
                  if (t <= 0) return const SizedBox.expand();
                  return DecoratedBox(
                    key: const ValueKey('kostvToolbarScrollShade'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.82 * t),
                          Colors.black.withValues(alpha: 0.6 * t),
                          Colors.black.withValues(alpha: 0),
                        ],
                        stops: [0.0, barBottom / (barBottom + fade), 1.0],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBackButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.popOrHome(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xB31E1E26),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.arrow_back, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}
