import 'package:flutter/material.dart';

import 'music/kostv_now_playing.dart';

import 'package:flutter/rendering.dart';
import 'package:get_it/get_it.dart';

import '../../data/services/plugin_sync_service.dart';
import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../util/platform_detection.dart';
import '../../util/overlay_color_palette.dart';
import 'bottom_nav/bottom_navbar.dart';
import 'download_progress_bar.dart';
import 'left_sidebar.dart';
import 'top_toolbar.dart';

import 'dart:async';

import 'package:moonfin_design/moonfin_design.dart';

import '../navigation/destinations.dart';
import '../navigation/route_lifecycle_observer.dart';

class NavigationLayout extends StatefulWidget {
  final String? activeRoute;
  final Widget child;
  final bool showBackButton;
  final bool showNavigationChrome;

  /// Keep the top toolbar fixed instead of letting it translate away as the
  /// content scrolls. No effect off-TV, where the toolbar is already fixed.
  final bool pinTopToolbar;

  static bool get allowBottomNavbar =>
      PlatformDetection.useMobileUi && !PlatformDetection.isWeb;

  static List<NavbarPosition> get availableNavbarPositions => <NavbarPosition>[
    NavbarPosition.top,
    NavbarPosition.left,
    if (allowBottomNavbar) NavbarPosition.bottom,
  ];

  static NavbarPosition sanitizeNavbarPosition(NavbarPosition position) {
    if (position == NavbarPosition.bottom && !allowBottomNavbar) {
      return NavbarPosition.top;
    }
    return position;
  }

  static bool get usesBottomNavbar =>
      sanitizeNavbarPosition(
        GetIt.instance<UserPreferences>().get(UserPreferences.navbarPosition),
      ) ==
      NavbarPosition.bottom;

  static final positionNotifier = ValueNotifier<NavbarPosition?>(
    sanitizeNavbarPosition(
      GetIt.instance<UserPreferences>().get(UserPreferences.navbarPosition),
    ),
  );

  /// Focus roots of the navigation chrome, registered by the sidebar and
  /// toolbar while mounted. The route focus observer refuses to land inside
  /// these, so a fresh route waits for content instead of starting the d-pad
  /// in the rail and popping it open before anything has loaded.
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

  /// True while a media bar trailer is playing. The toolbar and sidebar fade
  /// out on TV and desktop, and focusing them cancels the trailer, which
  /// fades them back in.
  static final trailerImmersiveNotifier = ValueNotifier<bool>(false);

  // Set for a few seconds after the mouse moves, so the chrome is there to
  // reach while a trailer plays on desktop.
  static final _trailerChromeWoken = ValueNotifier<bool>(false);
  static Timer? _trailerChromeWakeTimer;

  static final trailerChromeListenable = Listenable.merge([
    trailerImmersiveNotifier,
    _trailerChromeWoken,
  ]);

  /// Whether a playing trailer has the toolbar, sidebar and a peeking home
  /// row out of its way.
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
  });

  @override
  State<NavigationLayout> createState() => _NavigationLayoutState();
}

class _NavigationLayoutState extends State<NavigationLayout>
    with WidgetsBindingObserver, RouteAware {
  final _prefs = GetIt.instance<UserPreferences>();
  final _contentFocusNode = FocusNode(debugLabel: 'NavigationContent');
  final _contentKey = GlobalKey(debugLabel: 'navigationLayoutContent');
  final ValueNotifier<double> _toolbarScrollOffset = ValueNotifier<double>(0.0);
  late NavbarPosition _position;
  late BottomNavbarStyle _bottomStyle;
  bool _keyboardVisible = false;

  // Kos TV: off the TV the top bar stays put, so a page scrolled under it
  // runs its cards right behind the avatar and the buttons. A soft shade
  // behind the bar comes in once the page leaves its top, and goes back at
  // the top, where the banners and backdrops look as they always did. The
  // vertical scrollables of the page that are past their top, by context.
  final _scrolledScrollables = <BuildContext>{};
  final _contentScrolled = ValueNotifier<bool>(false);
  late final Listenable _scrollShadeListenable = Listenable.merge([
    _contentScrolled,
    NavigationLayout.trailerChromeListenable,
  ]);

  // Split shrinks while the user scrolls down and comes back on the way up.
  // The flag only flips at the thresholds, so scrolling rebuilds nothing.
  final _bottomMinimized = ValueNotifier<bool>(false);
  bool _userScrolling = false;
  double _scrollTravel = 0;
  ModalRoute<dynamic>? _observedRoute;

  @override
  void initState() {
    super.initState();
    final storedPosition = _prefs.get(UserPreferences.navbarPosition);
    _position = NavigationLayout.sanitizeNavbarPosition(storedPosition);
    if (_position != storedPosition) {
      _prefs.set(UserPreferences.navbarPosition, _position);
    }
    _bottomStyle = _prefs.get(UserPreferences.bottomNavbarStyle);
    _prefs.addListener(_onPrefsChanged);
    // Kos TV: a switch of person changes whose preferences are read without
    // writing any of them. The plugin sync announces each sign-in, reached
    // or not, so the bar follows the new person's position from there.
    if (GetIt.instance.isRegistered<PluginSyncService>()) {
      GetIt.instance<PluginSyncService>().addListener(_onPrefsChanged);
    }
    WidgetsBinding.instance.addObserver(this);
    NavigationLayout.positionNotifier.addListener(_onPositionNotified);
    // Kos TV: the details page reads the shared notifier, which may still
    // hold the previous person's position.
    if (NavigationLayout.positionNotifier.value != _position) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (NavigationLayout.positionNotifier.value != _position) {
          NavigationLayout.positionNotifier.value = _position;
        }
      });
    }
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
      _scrolledScrollables.clear();
      _contentScrolled.value = false;
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
    if (_bottomStyle != BottomNavbarStyle.split) return false;
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
    _bottomMinimized.dispose();
    _contentScrolled.dispose();
    _prefs.removeListener(_onPrefsChanged);
    if (GetIt.instance.isRegistered<PluginSyncService>()) {
      GetIt.instance<PluginSyncService>().removeListener(_onPrefsChanged);
    }
    NavigationLayout.positionNotifier.removeListener(_onPositionNotified);
    WidgetsBinding.instance.removeObserver(this);
    _contentFocusNode.dispose();
    _toolbarScrollOffset.dispose();
    super.dispose();
  }

  void _onPositionNotified() {
    final pos = NavigationLayout.positionNotifier.value;
    if (pos != null && pos != _position && mounted) {
      final normalized = NavigationLayout.sanitizeNavbarPosition(pos);
      if (normalized != pos) {
        NavigationLayout.positionNotifier.value = normalized;
      }
      if (_prefs.get(UserPreferences.navbarPosition) != normalized) {
        _prefs.set(UserPreferences.navbarPosition, normalized);
      }
      if (normalized != _position) {
        setState(() => _position = normalized);
      }
    }
  }

  // The bar's height, and with it the content inset, depends on the style.
  void _onPrefsChanged() {
    if (!mounted) return;
    // Kos TV: a switch of person brings their own bar position, which no
    // settings screen or server apply announces when the plugin can't be
    // reached, so the bar (and the details page, which follows the notifier)
    // would keep the previous person's.
    final pos = NavigationLayout.sanitizeNavbarPosition(
      _prefs.get(UserPreferences.navbarPosition),
    );
    if (pos != _position) {
      setState(() => _position = pos);
      if (NavigationLayout.positionNotifier.value != pos) {
        NavigationLayout.positionNotifier.value = pos;
      }
    }
    final style = _prefs.get(UserPreferences.bottomNavbarStyle);
    if (style == _bottomStyle) return;
    _expandBottomBar();
    setState(() => _bottomStyle = style);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPosition();
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

  void _refreshPosition() {
    final storedPosition = _prefs.get(UserPreferences.navbarPosition);
    final pos = NavigationLayout.sanitizeNavbarPosition(storedPosition);
    if (storedPosition != pos) {
      _prefs.set(UserPreferences.navbarPosition, pos);
      NavigationLayout.positionNotifier.value = pos;
    }
    if (pos != _position && mounted) setState(() => _position = pos);
  }

  @override
  Widget build(BuildContext context) {
    // Kos TV: the phone's bottom bar carries its own music player, so the
    // floating one steps aside on its pages.
    KostvNowPlayingRouteObserver.instance.setBottomBar(
      ModalRoute.of(context),
      _position == NavbarPosition.bottom && NavigationLayout.allowBottomNavbar,
    );
    final layout = switch (_position) {
      NavbarPosition.left => _buildSidebar(),
      NavbarPosition.top => _buildToolbar(),
      NavbarPosition.bottom =>
        NavigationLayout.allowBottomNavbar
            ? _buildBottomBar()
            : _buildToolbar(),
    };
    // Grouping only pays off when the tier draws real backdrop blurs, the
    // sheen tier never does.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (_) => NavigationLayout._wakeTrailerChrome(),
      child: AppColorScheme.isGlass && GlassSettings.blursBackdrop
          ? BackdropGroup(child: layout)
          : layout,
    );
  }

  /// Keyed so moving the navbar reparents the page that is already on screen
  /// instead of tearing it down and building it again.
  Widget get _content => KeyedSubtree(
    key: _contentKey,
    child: Focus(
      focusNode: _contentFocusNode,
      skipTraversal: true,
      child: widget.child,
    ),
  );

  Widget _buildBottomBar() {
    final content = _content;
    return Stack(
      children: [
        Positioned.fill(
          child: BottomNavInsetScope(
            height: BottomNavbar.heightFor(context, style: _bottomStyle),
            child: NotificationListener<ScrollNotification>(
              onNotification: _onBottomScroll,
              child: content,
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

  Widget _buildToolbar() {
    final translateWithScroll = PlatformDetection.isTV && !widget.pinTopToolbar;
    final shadeOnScroll = !PlatformDetection.isTV;
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
      // Its own layer: moved with the scroll on the TV without repainting.
      child: RepaintBoundary(
        child: TopToolbar(
          activeRoute: widget.activeRoute,
          showBackButton: widget.showBackButton,
          contentFocusNode: _contentFocusNode,
        ),
      ),
    );
    final maxTranslate = TopToolbar.heightFor(context);
    final body = translateWithScroll
        ? NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.axis != Axis.vertical) return false;
              final px = n.metrics.pixels.clamp(0.0, double.infinity);
              if ((px - _toolbarScrollOffset.value).abs() > 0.5) {
                _toolbarScrollOffset.value = px;
              }
              return false;
            },
            child: content,
          )
        : shadeOnScroll
        ? NotificationListener<ScrollNotification>(
            onNotification: _onToolbarContentScroll,
            child: content,
          )
        : content;
    final musicExtra = TopToolbar.musicBarExtraHeight();
    final insetBody = (widget.pinTopToolbar && musicExtra > 0)
        ? Padding(
            padding: EdgeInsets.only(top: musicExtra),
            child: body,
          )
        : body;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: insetBody),
              if (shadeOnScroll) _buildScrollShade(maxTranslate),
              if (translateWithScroll)
                ValueListenableBuilder<bool>(
                  valueListenable: TopToolbar.isFocusedNotifier,
                  builder: (_, toolbarFocused, child) =>
                      ValueListenableBuilder<double>(
                        valueListenable: _toolbarScrollOffset,
                        builder: (_, offset, child) {
                          // A focused toolbar must be visible. Screens can hand
                          // focus to it while the content is scrolled down, which
                          // would leave focus in a toolbar translated off screen.
                          final translate = !widget.showNavigationChrome
                              ? maxTranslate
                              : toolbarFocused
                              ? 0.0
                              : offset.clamp(0.0, maxTranslate);
                          return Positioned(
                            left: 0,
                            right: 0,
                            top: -translate,
                            child: IgnorePointer(
                              ignoring:
                                  !widget.showNavigationChrome ||
                                  translate >= maxTranslate,
                              // Scrolled away, nothing in it keeps animating.
                              child: TickerMode(
                                enabled: translate < maxTranslate,
                                child: child!,
                              ),
                            ),
                          );
                        },
                        child: child,
                      ),
                  child: toolbar,
                )
              else
                Positioned(left: 0, right: 0, top: 0, child: toolbar),
              if (widget.showBackButton &&
                  !PlatformDetection.isTV &&
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

  Widget _buildSidebar() {
    final content = _content;

    final sidebar = ListenableBuilder(
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
      child: RepaintBoundary(
        child: LeftSidebar(
          activeRoute: widget.activeRoute,
          contentFocusNode: _contentFocusNode,
          showBackButton: widget.showBackButton,
        ),
      ),
    );

    if (PlatformDetection.isTV ||
        (PlatformDetection.isDesktop ||
            (PlatformDetection.isWeb && !PlatformDetection.useMobileUi))) {
      return Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: content),
                Positioned(top: 0, left: 0, bottom: 0, child: sidebar),
                if (widget.showBackButton && !PlatformDetection.isTV)
                  Positioned(
                    top: 16,
                    left: 88,
                    child: _buildFloatingBackButton(),
                  ),
              ],
            ),
          ),
          const DownloadProgressBar(),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: content),
              Positioned.fill(child: sidebar),
            ],
          ),
        ),
        const DownloadProgressBar(),
      ],
    );
  }

  Widget _buildFloatingBackButton() {
    final overlayColor = OverlayColorPalette.resolveColor(
      _prefs.get(UserPreferences.navbarColor),
    );
    final opacity = _prefs.get(UserPreferences.navbarOpacity) / 100.0;
    final backgroundColor = ThemeRegistry.active.transparentNavbarSurface
        ? Colors.transparent
        : overlayColor.withValues(alpha: opacity);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.popOrHome(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
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
