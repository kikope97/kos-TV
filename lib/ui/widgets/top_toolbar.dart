import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/aggregated_library.dart';
import '../../l10n/app_localizations.dart';
import '../../preference/bottom_nav_tabs.dart';
import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../util/clock_format.dart';
import '../../util/focus/dpad_keys.dart';
import '../../util/focus/input_mode_tracker.dart';
import '../../util/game_library.dart';
import '../../util/platform_detection.dart';
import '../../util/tv_ui_scale.dart';
import '../navigation/destinations.dart';
import '../navigation/home_refresh_bus.dart';
import '../navigation/kostv_menu_controller.dart';
import '../navigation/menu_preview.dart';
import '../navigation/route_lifecycle_observer.dart';
import '../screens/discover/kostv_requests_tray.dart';
import 'kos_logo.dart';
import 'kostv_menu/kostv_glass.dart';
import 'kostv_menu/kostv_menu_entries.dart';
import 'kostv_menu/kostv_nav_avatar.dart';
import 'music/design/kostv_music_tokens.dart';
import 'music/kostv_now_playing.dart';
import 'music/kostv_now_playing_capsule.dart' show KostvEqualizerBars;
import 'nav_capsule.dart';
import 'navigation_layout.dart';

/// Kos TV: a length of the approved TV mockups (docs/diseno-menu, drawn on a
/// screen 1280 wide) on the TV's design canvas, so the bar is the mockup's
/// on any TV.
double kostvTvMk(double px) => px * kTvDesignWidth / 1280;
double _mk(double px) => kostvTvMk(px);

final double _kToolbarHeightTV = _mk(96);
const _kToolbarHeightDesktop = 80.0;
// The top room pages keep on phones, under the status bar, for their own
// back button and title (their menu is the glass bar at the bottom).
const _kTopRoomMobile = 60.0;
final double _kOverscanH = _mk(56);
const _kDesktopH = 40.0;
// The computer's row sits 22 px from the top (ordenador_cristal).
const _kDesktopTop = 22.0;
final double _kTabHeightTV = _mk(44);
const _kTabHeightDesktop = 40.0;

/// Kos TV: the menu of the TV and the computer: the approved design A
/// (docs/diseno-menu). Named tabs (Inicio · Descubrir · Música · Quiero
/// verlo · Bibliotecas · TV en directo), with the magnifier before them and
/// «Más» (Géneros, Calendario, Aplicaciones…) after; «Tú» is the avatar,
/// with the number of news. On the TV the clock is on the right, the white
/// capsule travels to the button with the focus, and while the page is
/// scrolled the bar gathers into a small pill ([collapsed]); Back or Up
/// bring it whole again with the focus on the page's own tab. On a computer
/// the logo is on the left, the tabs sit in a glass capsule and Search,
/// the requests tray and the avatar are on the right.
class TopToolbar extends StatefulWidget {
  final String? activeRoute;
  final bool showBackButton;
  final FocusNode? contentFocusNode;

  /// Whether the bar is gathered into its pill (the TV, while the page is
  /// scrolled and the focus is in it).
  final ValueListenable<bool>? collapsed;

  /// True while focus is inside the toolbar, so screens can avoid stealing its
  /// d-pad keys.
  static final ValueNotifier<bool> isFocusedNotifier = ValueNotifier<bool>(
    false,
  );

  /// Kos TV: true while the TV's menu is in use (the focus in it, or «Más»
  /// or «Tú» open from it): its glass lights up and the page dims a little
  /// (tele_A_foco).
  static final ValueNotifier<bool> litNotifier = ValueNotifier<bool>(false);

  /// Kos TV: true while «Más» or «Tú» is open from the TV's menu: the page
  /// dims further (45 %, tele_A_mas), the bar itself not.
  static final ValueNotifier<bool> openNotifier = ValueNotifier<bool>(false);

  const TopToolbar({
    super.key,
    this.activeRoute,
    this.showBackButton = false,
    this.contentFocusNode,
    this.collapsed,
  });

  /// Height of the toolbar for the current platform.
  /// On phones, where there is no top bar, the room pages keep at the top
  /// all the same.
  static double baseHeightFor(BuildContext context) =>
      PlatformDetection.useLeanbackUi
      ? _kToolbarHeightTV
      : PlatformDetection.useMobileUi
      ? _kTopRoomMobile
      : _kToolbarHeightDesktop;

  /// Total laid-out height of the toolbar for the current platform.
  static double heightFor(BuildContext context) => baseHeightFor(context);

  @override
  State<TopToolbar> createState() => _TopToolbarState();
}

class _TopToolbarState extends State<TopToolbar> with RouteAware {
  final _prefs = GetIt.instance<UserPreferences>();
  final _menu = KostvMenuController();

  final _avatarFocus = FocusNode(debugLabel: 'TopToolbarAvatar');
  final _homeFocus = FocusNode(debugLabel: 'TopToolbarHome');
  final _moreFocus = FocusNode(debugLabel: 'TopToolbarMore');
  final _trayFocus = FocusNode(debugLabel: 'TopToolbarTray');
  final _avatarKey = GlobalKey(debugLabel: 'TopToolbarAvatar');
  final _moreKey = GlobalKey(debugLabel: 'TopToolbarMore');
  final _toolbarScopeNode = FocusNode(
    debugLabel: 'TopToolbarScope',
    canRequestFocus: false,
    skipTraversal: true,
  );
  late final VoidCallback _focusNavbarCallback;
  late final VoidCallback _focusAvatarCallback;
  VoidCallback? _previousFocusNavbarCallback;
  VoidCallback? _previousFocusAvatarCallback;
  FocusNode? _previousFocus;
  // Tracked per instance so only the toolbar that actually held focus
  // clears the shared isFocusedNotifier on dispose.
  bool _toolbarHadFocus = false;
  bool _focusInside = false;
  bool _hovered = false;
  Timer? _clockTimer;
  late final ValueNotifier<String> _currentTime;

  @override
  void initState() {
    super.initState();
    _currentTime = ValueNotifier<String>('');
    // Guarded so a stale registration from a torn-down toolbar is a safe
    // no-op instead of focusing a disposed node.
    _focusNavbarCallback = () {
      if (!mounted) return;
      // Up into the menu (or Back) lands on the page's own tab, so resting
      // there shows nothing new.
      final route = widget.activeRoute;
      final own = route != null && Destinations.isMenuPage(route)
          ? _menuNode(route)
          : null;
      if (own != null && own.context != null && own.canRequestFocus) {
        own.requestFocus();
        return;
      }
      if (_homeFocus.context == null) return;
      _homeFocus.requestFocus();
    };
    MenuPreview.track();
    _focusAvatarCallback = () {
      if (!mounted || _avatarFocus.context == null) return;
      _avatarFocus.requestFocus();
    };
    _previousFocusNavbarCallback = NavigationLayout.focusNavbarNotifier.value;
    _previousFocusAvatarCallback =
        NavigationLayout.focusNavbarAvatarNotifier.value;
    NavigationLayout.focusNavbarNotifier.value = _focusNavbarCallback;
    NavigationLayout.focusNavbarAvatarNotifier.value = _focusAvatarCallback;
    NavigationLayout.chromeFocusRoots.add(_toolbarScopeNode);
    _avatarFocus.addListener(_onOwnFocusChanged);
    _trayFocus.addListener(_onOwnFocusChanged);
    _moreFocus.addListener(_onOwnFocusChanged);
    FocusManager.instance.addListener(_trackPreviousFocus);
    MenuPreview.arriving.addListener(_onMenuArriving);
    _onMenuArriving();
    _menu.addListener(_onMenuChanged);
    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateClock(),
    );
  }

  ModalRoute<dynamic>? _observedRoute;

  /// Whether this page was the one in front last time it looked.
  bool? _wasCurrent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    // In front again, however the page above went (Back, or a page taken
    // away by going Home, which never tells didPopNext).
    final current = route?.isCurrent ?? true;
    if (current && _wasCurrent == false) _backInFront();
    _wasCurrent = current;
    if (route == null || route == _observedRoute) return;
    if (_observedRoute != null) {
      routeLifecycleObserver.unsubscribe(this);
    }
    _observedRoute = route;
    routeLifecycleObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    // Our route is current again. An out of order route teardown can leave
    // the focus bridge pointing at a torn-down chrome instance, so re-assert
    // that it targets this live one.
    NavigationLayout.focusNavbarNotifier.value = _focusNavbarCallback;
    NavigationLayout.focusNavbarAvatarNotifier.value = _focusAvatarCallback;
    _backInFront();
  }

  /// Back on this page, the focus comes back where it was in it, which can
  /// be another page's tab in this menu (the one taken to leave). Resting
  /// there would open that page again: the menu's focus goes to this page's
  /// own tab. Once now, and again when the page above has finished leaving
  /// (the focus can come back at the end of its animation).
  void _backInFront() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusOwnButton());
    _stopWatchingReturn();
    final back = ModalRoute.of(context)?.secondaryAnimation;
    if (back != null && !back.isDismissed) {
      _returning = back..addStatusListener(_onReturnStatus);
    }
  }

  Animation<double>? _returning;

  void _onReturnStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    _stopWatchingReturn();
    _focusOwnButton();
  }

  void _stopWatchingReturn() {
    _returning?.removeStatusListener(_onReturnStatus);
    _returning = null;
  }

  void _focusOwnButton() {
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? true)) return;
    final route = widget.activeRoute;
    if (route == null || !Destinations.isMenuPage(route)) return;
    final focused = FocusManager.instance.primaryFocus;
    final own = _menuNode(route);
    if (focused == null || focused == own) return;
    final inMenu = focused == _homeFocus || _menuFocus.values.contains(focused);
    if (!inMenu || own.context == null || !own.canRequestFocus) return;
    _restTimer?.cancel();
    own.requestFocus();
  }

  @override
  void dispose() {
    if (_observedRoute != null) {
      routeLifecycleObserver.unsubscribe(this);
      _observedRoute = null;
    }
    if (identical(
      NavigationLayout.focusNavbarNotifier.value,
      _focusNavbarCallback,
    )) {
      NavigationLayout.focusNavbarNotifier.value = _previousFocusNavbarCallback;
    }
    if (identical(
      NavigationLayout.focusNavbarAvatarNotifier.value,
      _focusAvatarCallback,
    )) {
      NavigationLayout.focusNavbarAvatarNotifier.value =
          _previousFocusAvatarCallback;
    }
    _clockTimer?.cancel();
    // Only clear the shared flag if this instance held focus, so a torn-down
    // route's toolbar can't wipe the state of the one the user is on.
    if (_toolbarHadFocus) {
      TopToolbar.isFocusedNotifier.value = false;
    }
    if (_toolbarHadFocus || _open != null) {
      TopToolbar.litNotifier.value = false;
      TopToolbar.openNotifier.value = false;
    }
    NavigationLayout.chromeFocusRoots.remove(_toolbarScopeNode);
    FocusManager.instance.removeListener(_trackPreviousFocus);
    MenuPreview.arriving.removeListener(_onMenuArriving);
    _menu
      ..removeListener(_onMenuChanged)
      ..dispose();
    _stopWatchingReturn();
    _restTimer?.cancel();
    for (final node in _menuFocus.values) {
      node.dispose();
    }
    _toolbarScopeNode.dispose();
    _avatarFocus.dispose();
    _homeFocus.dispose();
    _moreFocus.dispose();
    _trayFocus.dispose();
    _currentTime.dispose();
    super.dispose();
  }

  void _onMenuChanged() {
    if (!mounted) return;
    _updateClock();
    setState(() {});
  }

  void _onOwnFocusChanged() {
    if (mounted) setState(() {});
  }

  void _updateClock() {
    final newTime = formatClockTime(
      DateTime.now(),
      use24Hour: _prefs.get(UserPreferences.use24HourClock),
    );
    if (mounted && _currentTime.value != newTime) {
      _currentTime.value = newTime;
    }
  }

  void _trackPreviousFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return;
    // A whole page or route holding the focus for a moment (while a page
    // arrives) is no place to go back to: focusing it again hands the focus
    // to whatever it last had, the menu button included.
    if (primary.skipTraversal || primary is FocusScopeNode) return;
    if (_isInsideToolbar(primary)) return;
    // Only this page's own content: not another page's menu nor a page
    // under or over this one, which go away and leave the focus nowhere.
    if (MenuPreview.isMenu(primary)) return;
    final there = primary.context;
    if (there == null || !mounted) return;
    if (!(ModalRoute.isCurrentOf(there) ?? true)) return;
    _previousFocus = primary;
  }

  bool _isInsideToolbar(FocusNode node) {
    FocusNode? current = node;
    while (current != null) {
      if (identical(current, _toolbarScopeNode)) return true;
      current = current.parent;
    }
    return false;
  }

  bool _isUsableOutsideToolbar(FocusNode? node) {
    if (node == null) return false;
    if (node.skipTraversal) return false;
    if (_isInsideToolbar(node)) return false;
    if (!_isLaidOutFocusNode(node)) return false;
    // Not a page under or going away under the one on screen.
    return ModalRoute.isCurrentOf(node.context!) ?? true;
  }

  void _restoreFocusBelowToolbar() {
    // Going down into the page, the menu lets go first. Still holding, Home
    // refused the focus it was being handed and the focus went nowhere.
    MenuPreview.stopHolding();
    if (NavigationLayout.focusDetailsPlayButton()) return;
    final focusContent = NavigationLayout.focusContentFromNavbarNotifier.value;
    if (focusContent != null && widget.activeRoute == Destinations.home) {
      focusContent();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary == null || _isInsideToolbar(primary)) {
          _restoreFocusBelowToolbarFallback();
        }
      });
      return;
    }

    _restoreFocusBelowToolbarFallback();
  }

  void _restoreFocusBelowToolbarFallback() {
    final previous = _previousFocus;
    if (previous != null && _isUsableOutsideToolbar(previous)) {
      previous.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (_isUsableOutsideToolbar(primary)) {
          return;
        }
        _previousFocus = null;
        _moveFocusDown();
      });
      return;
    }
    _previousFocus = null;
    _moveFocusDown();
  }

  /// A node can only take focus once its box exists and has been laid out.
  /// Asking earlier throws out of the focus machinery.
  bool _isReadyForFocus(FocusNode node) {
    final render = node.context?.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize;
  }

  void _moveFocusDown({int attempt = 0}) {
    if (!mounted) return;
    final scope = FocusScope.of(context);
    // Directional traversal measures every candidate it walks, so one node
    // still waiting on layout takes the whole call down. The manual paths below
    // cover the same ground, so a failure here isn't worth surfacing.
    try {
      if (scope.focusInDirection(TraversalDirection.down)) {
        final primary = FocusManager.instance.primaryFocus;
        if (_isUsableOutsideToolbar(primary)) return;
      }
    } catch (_) {}

    final firstBelow = _findFirstFocusableBelowToolbar(scope);
    if (firstBelow != null && _isReadyForFocus(firstBelow)) {
      firstBelow.requestFocus();
      return;
    }
    final fallback = widget.contentFocusNode;
    if (fallback != null && fallback.context != null) {
      final firstContent = _firstFocusableDescendant(fallback);
      if (firstContent != null) {
        if (_isReadyForFocus(firstContent)) {
          firstContent.requestFocus();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final primary = FocusManager.instance.primaryFocus;
          if (_isUsableOutsideToolbar(primary)) return;
          if (attempt < 3) {
            _moveFocusDown(attempt: attempt + 1);
          }
        });
      } else if (attempt < 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _moveFocusDown(attempt: attempt + 1);
        });
      }
      return;
    }
    if (attempt < 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveFocusDown(attempt: attempt + 1);
      });
    }
  }

  /// Moves focus one button along the toolbar, in painted order.
  bool _moveWithinToolbar(TraversalDirection direction) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || !_isInsideToolbar(primary)) return false;

    final nodes =
        _toolbarScopeNode.descendants
            .where((n) => !n.skipTraversal && _isLaidOutFocusNode(n))
            .map((n) {
              final box = n.context!.findRenderObject() as RenderBox?;
              final pos = box?.localToGlobal(Offset.zero);
              return (node: n, x: pos?.dx ?? -1.0);
            })
            .where((item) => item.x >= 0)
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));

    final index = nodes.indexWhere((e) => e.node == primary);
    if (index < 0) return false;
    final nextIndex = direction == TraversalDirection.right
        ? index + 1
        : index - 1;
    if (nextIndex < 0 || nextIndex >= nodes.length) return false;
    nodes[nextIndex].node.requestFocus();
    return true;
  }

  FocusNode? _findFirstFocusableBelowToolbar(FocusScopeNode scope) {
    for (final node in scope.traversalDescendants) {
      if (node.skipTraversal) continue;
      if (!_isLaidOutFocusNode(node)) continue;
      if (_isInsideToolbar(node)) continue;
      return node;
    }
    return null;
  }

  FocusNode? _firstFocusableDescendant(FocusNode node) {
    for (final child in node.children) {
      if (!child.skipTraversal && _isLaidOutFocusNode(child)) {
        return child;
      }
      final found = _firstFocusableDescendant(child);
      if (found != null) return found;
    }
    return null;
  }

  bool _isLaidOutFocusNode(FocusNode node) {
    if (!node.canRequestFocus) {
      return false;
    }
    final context = node.context;
    if (context == null) {
      return false;
    }
    final renderObject = context.findRenderObject();
    return renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize;
  }

  bool _isActive(String route) => widget.activeRoute == route;

  /// The tabs of the pages the menu shows by resting on them.
  final _menuFocus = <String, FocusNode>{};
  Timer? _restTimer;

  FocusNode _menuNode(String route) => route == Destinations.home
      ? _homeFocus
      : _menuFocus.putIfAbsent(
          route,
          () => FocusNode(debugLabel: 'TopToolbarMenu $route'),
        );

  /// Shows [route]'s page once the focus has rested on its tab for a moment,
  /// with a remote or keys.
  void _restOn(String route, bool focused) {
    _restTimer?.cancel();
    if (!focused || !MenuPreview.supported || _isActive(route)) return;
    if (!InputModeTracker.showFocusVisuals(context, true)) return;
    // Only moving along the menu, not coming up into it from the page.
    if (!MenuPreview.movedAlong(Axis.horizontal)) return;
    _restTimer = Timer(MenuPreview.restDelay, () {
      if (!mounted || !_menuNode(route).hasFocus) return;
      if (!(ModalRoute.isCurrentOf(context) ?? true)) return;
      MenuPreview.show(context, route);
    });
  }

  /// OK on a tab: its page opens as resting on it would, or, when it's the
  /// page already on screen, the focus goes into it.
  void _openFromMenu(String route) {
    if (MenuPreview.holding && _isActive(route)) {
      MenuPreview.stopHolding();
      _restoreFocusBelowToolbar();
      return;
    }
    if (MenuPreview.open(context, route) && _isActive(route)) {
      _restoreFocusBelowToolbar();
    }
  }

  /// The page the menu is showing is this toolbar's: its tab takes the
  /// focus, so the person goes on along the menu.
  void _onMenuArriving() {
    final route = MenuPreview.arriving.value;
    if (route == null || route != widget.activeRoute) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeArrival(route, 0));
  }

  void _takeArrival(String route, int attempt) {
    if (!mounted || MenuPreview.arriving.value != route) return;
    final node = _menuNode(route);
    if ((ModalRoute.isCurrentOf(context) ?? true) &&
        node.context != null &&
        node.canRequestFocus) {
      NavCapsule.snapNextFrame();
      node.requestFocus();
      MenuPreview.landed(node);
      return;
    }
    if (attempt >= 20) {
      MenuPreview.gaveUp(route);
      return;
    }
    Timer(
      const Duration(milliseconds: 50),
      () => _takeArrival(route, attempt + 1),
    );
  }

  bool get _showBackArrow => widget.showBackButton && !PlatformDetection.isTV;

  @override
  void didUpdateWidget(covariant TopToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeRoute != widget.activeRoute) {
      _previousFocus = null;
    }
  }

  bool get _showClock {
    // The computer has a clock of its own.
    if (!PlatformDetection.isTV) return false;
    final behavior = _prefs.get(UserPreferences.clockBehavior);
    return behavior == ClockBehavior.always ||
        behavior == ClockBehavior.inMenus;
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    // Where the menu's card is laid: the overlay's own space (on a TV, the
    // design canvas, not the scaled screen).
    final overlay = Overlay.maybeOf(
      context,
      rootOverlay: true,
    )?.context.findRenderObject();
    return box.localToGlobal(
          Offset.zero,
          ancestor: overlay is RenderBox ? overlay : null,
        ) &
        box.size;
  }

  void _openPage(BuildContext context, String route) {
    if (Destinations.isMenuPage(route)) {
      MenuPreview.open(context, route);
    } else {
      context.push(route);
    }
  }

  /// Which of the menu's cards is open from it: 'you', 'more' or none.
  String? _open;

  void _setOpen(String? which) {
    if (!mounted) return;
    setState(() => _open = which);
    _updateLit();
  }

  void _updateLit() {
    final lit = PlatformDetection.isTV && (_focusInside || _open != null);
    if (TopToolbar.litNotifier.value != lit) {
      TopToolbar.litNotifier.value = lit;
    }
    final open = PlatformDetection.isTV && _open != null;
    if (TopToolbar.openNotifier.value != open) {
      TopToolbar.openNotifier.value = open;
    }
  }

  /// «Tú»: the person's menu, under the avatar (tele_A_perfil: 8 px left of
  /// the face and 26 px under it).
  Future<void> _showYou() async {
    final anchor = _rectOf(_avatarKey);
    if (anchor == null) return;
    final tv = PlatformDetection.isTV;
    final ring = tv ? _mk(5) : 5.0;
    final face = anchor.deflate(ring);
    _setOpen('you');
    await showKostvMenuPopup(
      context: context,
      anchor: anchor,
      width: 340,
      alignEnd: !tv,
      at: tv ? Offset(face.left - _mk(8), face.bottom + _mk(26)) : null,
      scale: tv ? _mk(1) : 1,
      header: KostvMenuYouHeader(menu: _menu),
      entries: kostvYouEntries(
        AppLocalizations.of(context),
        _menu,
        openPage: _openPage,
      ),
    );
    _setOpen(null);
  }

  /// «Más»: what isn't on the bar, under its button (tele_A_mas: 9 px left
  /// of it and 14 px under it).
  Future<void> _showMore() async {
    final anchor = _rectOf(_moreKey);
    if (anchor == null) return;
    final tv = PlatformDetection.isTV;
    _setOpen('more');
    await showKostvMenuPopup(
      context: context,
      anchor: anchor,
      at: tv ? Offset(anchor.left - _mk(9), anchor.bottom + _mk(14)) : null,
      scale: tv ? _mk(1) : 1,
      entries: kostvMoreEntries(
        AppLocalizations.of(context),
        _menu,
        openPage: _openPage,
      ),
    );
    _setOpen(null);
  }

  KeyEventResult _onScopeKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _restoreFocusBelowToolbar();
      return KeyEventResult.handled;
    }
    // Up from the menu goes nowhere: there is nothing above it.
    if (key == LogicalKeyboardKey.arrowUp) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _moveWithinToolbar(
        key == LogicalKeyboardKey.arrowLeft
            ? TraversalDirection.left
            : TraversalDirection.right,
      );
      // Always consumed so the key can't escape sideways into content.
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isTV = PlatformDetection.isTV;
    final height = TopToolbar.baseHeightFor(context);
    final bar = Focus(
      focusNode: _toolbarScopeNode,
      onFocusChange: (hasFocus) {
        _toolbarHadFocus = hasFocus;
        TopToolbar.isFocusedNotifier.value = hasFocus;
        if (hasFocus != _focusInside) setState(() => _focusInside = hasFocus);
        _updateLit();
      },
      onKeyEvent: _onScopeKey,
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: isTV ? _buildTvBar() : _buildDesktopBar(),
      ),
    );
    final full = SizedBox(height: height, child: bar);
    final collapsed = widget.collapsed;
    return SafeArea(
      bottom: false,
      // The scrim reaches below the bar: not cut at its height (that cut
      // was the dark band across the TV).
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The scrim behind the bar, so its white text reads on any
          // artwork.
          // No band behind the TV's bar: only a soft shade from the top
          // (.scrim), deeper while the menu is in use; gathered, a short one
          // behind the pill.
          if (isTV)
            Positioned(
              left: 0,
              right: 0,
              top: -MediaQuery.paddingOf(context).top,
              height: _mk(190) + MediaQuery.paddingOf(context).top,
              child: IgnorePointer(
                child: collapsed == null
                    ? _TopScrim(lit: _focusInside || _open != null)
                    : ValueListenableBuilder<bool>(
                        valueListenable: collapsed,
                        builder: (_, gathered, _) => _TopScrim(
                          lit: _focusInside || _open != null,
                          gathered: gathered,
                        ),
                      ),
              ),
            ),
          if (collapsed == null)
            full
          else
            ValueListenableBuilder<bool>(
              valueListenable: collapsed,
              builder: (context, gathered, _) => Stack(
                children: [
                  // The whole bar stays in place (its tabs keep their focus
                  // nodes for Back and Up), only out of sight.
                  AnimatedOpacity(
                    opacity: gathered ? 0 : 1,
                    duration: const Duration(milliseconds: 220),
                    child: IgnorePointer(
                      ignoring: gathered,
                      child: TickerMode(enabled: !gathered, child: full),
                    ),
                  ),
                  Positioned(
                    left: _kOverscanH,
                    top: _mk(22),
                    right: _kOverscanH,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: gathered ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: TickerMode(
                          enabled: gathered,
                          child: _buildPill(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The name of the page on screen, for the pill.
  String? _pageName(AppLocalizations l10n) {
    final route = widget.activeRoute;
    return switch (route) {
      Destinations.home => l10n.home,
      Destinations.search => l10n.search,
      Destinations.kostvDiscover => l10n.kostvDiscover,
      Destinations.kostvMusic => l10n.kostvMusic,
      Destinations.myList => l10n.kostvMyList,
      Destinations.kostvLibraries => l10n.libraries,
      Destinations.liveTvGuide => l10n.liveTv,
      Destinations.allGenres => l10n.genres,
      Destinations.calendar => l10n.calendar,
      Destinations.apps => l10n.kostvAppsRow,
      Destinations.allFavorites => l10n.kostvMyFavorites,
      _ => null,
    };
  }

  /// The bar gathered: the avatar and the page's name, with the clock.
  Widget _buildPill() {
    final name = _pageName(AppLocalizations.of(context));
    return Row(
      key: const ValueKey('kostvToolbarPill'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // .glassbar.row: padding 6px 16px 6px 6px, gap 10px, 600 16px.
        Container(
          padding: EdgeInsets.fromLTRB(
            _mk(6),
            _mk(6),
            _mk(name == null ? 6 : 16),
            _mk(6),
          ),
          decoration: _tvGlassDecoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The ring reaches 5 px past the face, over the padding.
              SizedBox(
                width: _mk(30),
                height: _mk(30),
                child: OverflowBox(
                  maxWidth: _mk(40),
                  maxHeight: _mk(40),
                  child: _avatarFace(size: _mk(30), badge: 0),
                ),
              ),
              if (name != null) ...[
                SizedBox(width: _mk(10)),
                Text(
                  name,
                  style: TextStyle(
                    color: KostvMusicTokens.ink,
                    fontSize: _mk(16),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Spacer(),
        // .clk: 20px, 80 % white, 4 px lower than the pill.
        if (_showClock)
          Padding(
            padding: EdgeInsets.only(top: _mk(4)),
            child: ValueListenableBuilder<String>(
              valueListenable: _currentTime,
              builder: (context, time, _) => Text(
                time,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: KostvMusicTokens.ink.withValues(alpha: 0.8),
                  fontSize: _mk(20),
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// .glassbar: rgba(36,36,44,.62), a 1 px light edge inside and
  /// 0 10px 30px rgba(0,0,0,.35). No blur on a TV: the scrim under it does
  /// the rest.
  static final _tvGlassDecoration = BoxDecoration(
    color: const Color(0xA824242C),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    boxShadow: [
      BoxShadow(
        color: const Color(0x59000000),
        blurRadius: _mk(30),
        offset: Offset(0, _mk(10)),
      ),
    ],
  );

  Widget _avatarFace({required double size, required int badge}) =>
      KostvNavAvatar(
        size: size,
        imageUrl: _menu.userImageUrl,
        name: _menu.userName,
        badge: badge,
        ring: true,
        ringPad: PlatformDetection.isTV ? _mk(5) : 5,
        spinning: _menu.requestsWorking,
        focused:
            size > _mk(32) &&
            (_open == 'you' ||
                InputModeTracker.showFocusVisuals(
                  context,
                  _avatarFocus.hasFocus,
                )),
      );

  /// «Tú»: the avatar, with the news behind it.
  Widget _buildAvatar() {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.navYou,
      child: Focus(
        focusNode: _avatarFocus,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
            _showYou();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: _avatarKey,
            onTap: _showYou,
            child: _avatarFace(
              size: PlatformDetection.isTV ? _mk(44) : 40,
              badge: _menu.youBadge,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClock() => ValueListenableBuilder<String>(
    valueListenable: _currentTime,
    builder: (context, time, _) => Text(
      time,
      textDirection: TextDirection.ltr,
      style: TextStyle(
        color: KostvMusicTokens.ink,
        fontSize: _mk(22),
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );

  /// tele_A_reposo: 56 px in from the edges, the avatar, 22 px, the tabs;
  /// the clock on the right.
  Widget _buildTvBar() {
    // The avatar's ring reaches 5 px past its face, into that room.
    final ring = _mk(5);
    return Padding(
      padding: EdgeInsets.fromLTRB(_kOverscanH - ring, 0, _kOverscanH, 0),
      child: Row(
        children: [
          _buildAvatar(),
          SizedBox(width: _mk(22) - ring),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _buildTabs(tv: true),
            ),
          ),
          if (_showClock) ...[SizedBox(width: _mk(22)), _buildClock()],
        ],
      ),
    );
  }

  /// ordenador_cristal: 22 px from the top and 40 from the sides, the logo,
  /// the tabs in their glass capsule, and Search, the tray and the avatar.
  Widget _buildDesktopBar() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kDesktopH,
        _kDesktopTop,
        _kDesktopH,
        0,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(height: 50, child: _desktopRow(l10n)),
      ),
    );
  }

  Widget _desktopRow(AppLocalizations l10n) {
    return Row(
      children: [
        if (_showBackArrow) ...[
          _RoundButton(
            icon: Icons.arrow_back_rounded,
            label: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => context.popOrHome(),
          ),
          const SizedBox(width: 14),
        ],
        const KosLogo(height: 34),
        Expanded(child: Center(child: _buildTabs(tv: false))),
        _DesktopSearchBox(
          label: l10n.search,
          focusNode: _menuNode(Destinations.search),
          active: _isActive(Destinations.search),
          onPressed: () => _openFromMenu(Destinations.search),
        ),
        if (_menu.requestsVisible) ...[
          const SizedBox(width: 10),
          _RoundButton(
            icon: Icons.inbox_rounded,
            label: l10n.kostvMenuMyRequests,
            count: _menu.requestsNews,
            focusNode: _trayFocus,
            onPressed: () => showKostvRequestsTray(context),
          ),
        ],
        const SizedBox(width: 10),
        _buildAvatar(),
      ],
    );
  }

  /// The named tabs, with the magnifier before them on the TV and «Más»
  /// after. On the TV the glass behind them lights up while the menu has the
  /// focus; on a computer they always sit in their glass capsule.
  Widget _buildTabs({required bool tv}) {
    final l10n = AppLocalizations.of(context);
    final menu = _menu;
    final libraries = menu.shows(BottomNavTab.libraries)
        ? menu.navLibraries
        : const <AggregatedLibrary>[];
    final more = kostvMoreEntries(l10n, menu, openPage: _openPage);

    Widget page(String route, String label, {Key? key}) => _NavTab(
      key: key,
      tv: tv,
      label: label,
      focusNode: _menuNode(route),
      selected: _isActive(route),
      onFocusChanged: (f) => _restOn(route, f),
      onPressed: () => _openFromMenu(route),
    );

    final tabs = <Widget>[
      if (tv)
        _NavTab(
          key: const ValueKey('toolbar_search'),
          tv: true,
          icon: Icons.search_rounded,
          label: l10n.search,
          focusNode: _menuNode(Destinations.search),
          selected: _isActive(Destinations.search),
          onFocusChanged: (f) => _restOn(Destinations.search, f),
          onPressed: () => _openFromMenu(Destinations.search),
        ),
      _NavTab(
        key: const ValueKey('toolbar_home'),
        tv: tv,
        label: l10n.home,
        focusNode: _homeFocus,
        selected: _isActive(Destinations.home),
        onFocusChanged: (f) => _restOn(Destinations.home, f),
        onPressed: () {
          if (MenuPreview.holding && _isActive(Destinations.home)) {
            _openFromMenu(Destinations.home);
            return;
          }
          if (_isActive(Destinations.home)) {
            homeRefreshBus.request(newMediaBar: true);
            return;
          }
          homeRefreshBus.requestOnArrival();
          MenuPreview.open(context, Destinations.home);
        },
      ),
      if (menu.shows(BottomNavTab.kostvDiscover))
        page(
          Destinations.kostvDiscover,
          l10n.kostvDiscover,
          key: const ValueKey('toolbar_kostv_discover'),
        ),
      if (menu.shows(BottomNavTab.kostvMusic))
        page(
          Destinations.kostvMusic,
          l10n.kostvMusic,
          key: const ValueKey('toolbar_music'),
        ),
      if (menu.shows(BottomNavTab.myList))
        page(
          Destinations.myList,
          l10n.kostvMyList,
          key: const ValueKey('toolbar_my_list'),
        ),
      if (libraries.isNotEmpty && menu.librariesIndividually)
        for (final lib in libraries)
          _NavTab(
            // Two servers can share a library id, so the key is the library
            // itself.
            key: ObjectKey(lib),
            tv: tv,
            label: lib.name,
            onPressed: () => context.openLibraryFromMenu(
              libraryRoute(
                lib.id,
                lib.collectionType,
                lib.name,
                serverId: lib.serverId,
              ),
            ),
          )
      else if (libraries.isNotEmpty)
        page(
          Destinations.kostvLibraries,
          l10n.libraries,
          key: const ValueKey('toolbar_libraries'),
        ),
      if (menu.shows(BottomNavTab.liveTv))
        page(
          Destinations.liveTvGuide,
          l10n.liveTv,
          key: const ValueKey('toolbar_livetv'),
        ),
      // While music sounds, its equalizer opens the player.
      ListenableBuilder(
        listenable: KostvNowPlaying.instance..ensureStarted(),
        builder: (context, _) {
          final music = KostvNowPlaying.instance;
          if (music.item == null) return const SizedBox.shrink();
          return _NavTab(
            key: const ValueKey('toolbar_now_playing'),
            tv: tv,
            label: l10n.kostvNowPlaying,
            iconBuilder: (size, color) => KostvEqualizerBars(
              playing: music.playing,
              size: size * 0.8,
              color: KostvMusicTokens.pink,
            ),
            focusNode: _menuNode(Destinations.audioPlayer),
            selected: _isActive(Destinations.audioPlayer),
            onPressed: () => context.push(Destinations.audioPlayer),
          );
        },
      ),
      if (more.isNotEmpty)
        _NavTab(
          key: const ValueKey('toolbar_more'),
          anchorKey: _moreKey,
          tv: tv,
          icon: tv ? Icons.more_horiz_rounded : null,
          trailingIcon: tv ? null : Icons.keyboard_arrow_down_rounded,
          label: l10n.more,
          count: menu.moreBadge,
          focusNode: _moreFocus,
          held: _open == 'more',
          onPressed: _showMore,
        ),
    ];

    final row = NavCapsule(
      color: KostvMusicTokens.ink,
      flat: tv,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) SizedBox(width: tv ? _mk(4) : 2),
            tabs[i],
          ],
        ],
      ),
    );
    final scroll = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: row,
    );
    if (!tv) {
      // .g.bar: the phone's glass, padding 5px.
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: KostvGlass(
          fill: _hovered || _focusInside
              ? Colors.white.withValues(alpha: 0.04)
              : null,
          child: Padding(padding: const EdgeInsets.all(5), child: scroll),
        ),
      );
    }
    // On the TV the glass is there only while the menu is in use
    // (tele_A_foco, tele_A_mas).
    final lit = _focusInside || _open != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.all(_mk(5)),
      decoration: lit
          ? _tvGlassDecoration
          : BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.transparent),
            ),
      child: scroll,
    );
  }
}

/// The dark shade from the top of the screen behind the TV's bar (no band):
/// `.scrim`, 150 px from 72 % black through 35 % to nothing; 190 px from
/// 85 % through 40 % while the menu is in use; gathered, 70 px from 70 %.
class _TopScrim extends StatelessWidget {
  const _TopScrim({required this.lit, this.gathered = false});

  final bool lit;
  final bool gathered;

  @override
  Widget build(BuildContext context) {
    final full = _mk(190);
    final ({double height, double top, double mid, double stop}) shade =
        gathered
        ? (height: _mk(70), top: 0.7, mid: 0.35, stop: 0.5)
        : lit
        ? (height: full, top: 0.85, mid: 0.4, stop: 0.6)
        : (height: _mk(150), top: 0.72, mid: 0.35, stop: 0.55);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: shade.height),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, height, _) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: shade.top),
                  Colors.black.withValues(alpha: shade.mid),
                  Colors.black.withValues(alpha: 0),
                ],
                stops: [0, shade.stop, 1],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kos TV: one tab of the top bar: its name (or an icon: the magnifier and
/// «Más» on the TV). The page on screen is white and bold with the
/// gradient line under it; the white capsule (the menu's [NavCapsule])
/// comes to the tab with the remote's or the keyboard's focus, and the
/// mouse lights it softly.
class _NavTab extends StatefulWidget {
  const _NavTab({
    super.key,
    required this.tv,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconBuilder,
    this.trailingIcon,
    this.focusNode,
    this.onFocusChanged,
    this.selected = false,
    this.count = 0,
    this.anchorKey,
    this.held = false,
  });

  /// Its menu is open: it keeps the white capsule meanwhile (tele_A_mas).
  final bool held;

  final bool tv;
  final String label;
  final IconData? icon;
  final Widget Function(double size, Color color)? iconBuilder;
  final IconData? trailingIcon;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChanged;
  final bool selected;
  final VoidCallback onPressed;
  final int count;

  /// Where a menu that opens from this tab is placed.
  final GlobalKey? anchorKey;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _focused = false;
  bool _hovered = false;

  bool get _iconOnly => widget.icon != null || widget.iconBuilder != null;

  @override
  Widget build(BuildContext context) {
    final tv = widget.tv;
    final focusVisible =
        widget.held || InputModeTracker.showFocusVisuals(context, _focused);
    final height = tv ? _kTabHeightTV : _kTabHeightDesktop;
    final fontSize = tv ? _mk(18) : 15.0;
    final iconSize = tv ? _mk(24) : 24.0;
    final base = widget.selected
        ? KostvMusicTokens.ink
        : KostvMusicTokens.ink.withValues(alpha: tv ? 0.62 : 0.8);
    final hoverLit = !tv && _hovered && !focusVisible;

    Widget content(double cover) {
      final color = Color.lerp(base, KostvMusicTokens.background, cover)!;
      final bold = widget.selected || cover > 0.5;
      final Widget face;
      if (_iconOnly) {
        face = SizedBox(
          width: height,
          height: height,
          child: Center(
            child:
                widget.iconBuilder?.call(iconSize, color) ??
                Icon(widget.icon, size: iconSize, color: color),
          ),
        );
      } else {
        face = Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: tv ? _mk(18) : 16),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (widget.trailingIcon != null) ...[
                const SizedBox(width: 2),
                Icon(widget.trailingIcon, size: 18, color: color),
              ],
            ],
          ),
        );
      }
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // On a computer, the page on screen sits in the lighter glass pill
          // with the gradient rim.
          if (!tv && widget.selected)
            const Positioned.fill(child: KostvActivePill()),
          if (hoverLit)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          face,
          if (tv && widget.selected && !_iconOnly)
            Positioned(
              bottom: _mk(2),
              child: KostvHereMark(
                width: _mk(22),
                height: _mk(3),
                opacity: 1 - cover,
              ),
            ),
          if (widget.count > 0)
            Positioned(
              top: 2,
              right: 2,
              child: KostvMenuCount(count: widget.count, size: 16),
            ),
        ],
      );
    }

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: tv ? null : (_) => setState(() => _hovered = true),
        onExit: tv ? null : (_) => setState(() => _hovered = false),
        child: Focus(
          focusNode: widget.focusNode,
          onFocusChange: (f) {
            setState(() => _focused = f);
            widget.onFocusChanged?.call(f);
          },
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
              widget.onPressed();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            key: widget.anchorKey,
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Tooltip(
              message: _iconOnly ? widget.label : '',
              excludeFromSemantics: true,
              // .tab.f: the focused tab grows a little (scale 1.06).
              child: AnimatedScale(
                scale: tv && focusVisible ? 1.06 : 1,
                duration: KostvMusicTokens.focusDuration,
                curve: KostvMusicTokens.focusCurve,
                child: NavCapsuleTarget(
                  active: focusVisible,
                  builder: (context, cover) => content(cover),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round glass button of the computer's bar (back, the requests tray).
class _RoundButton extends StatefulWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.count = 0,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final int count;
  final FocusNode? focusNode;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lit =
        _hovered || InputModeTracker.showFocusVisuals(context, _focused);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.label,
        excludeFromSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Focus(
            focusNode: widget.focusNode,
            onFocusChange: (f) => setState(() => _focused = f),
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
                widget.onPressed();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: widget.onPressed,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: KostvGlass(
                      fill: lit ? Colors.white.withValues(alpha: 0.10) : null,
                      child: Center(
                        child: Icon(widget.icon, size: 19, color: Colors.white),
                      ),
                    ),
                  ),
                  if (widget.count > 0)
                    Positioned(
                      top: -4,
                      right: -5,
                      child: KostvMenuCount(count: widget.count, size: 19),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The computer's search box: one click opens Search.
class _DesktopSearchBox extends StatefulWidget {
  const _DesktopSearchBox({
    required this.label,
    required this.onPressed,
    required this.focusNode,
    required this.active,
  });

  final String label;
  final VoidCallback onPressed;
  final FocusNode focusNode;
  final bool active;

  @override
  State<_DesktopSearchBox> createState() => _DesktopSearchBoxState();
}

class _DesktopSearchBoxState extends State<_DesktopSearchBox> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final lit =
        _hovered ||
        widget.active ||
        InputModeTracker.showFocusVisuals(context, _focused);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          key: const ValueKey('toolbar_search'),
          focusNode: widget.focusNode,
          onFocusChange: (f) => setState(() => _focused = f),
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
              widget.onPressed();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            onTap: widget.onPressed,
            child: SizedBox(
              width: 220,
              height: 44,
              child: KostvGlass(
                fill: lit ? Colors.white.withValues(alpha: 0.10) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: KostvMusicTokens.ink.withValues(alpha: 0.75),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
