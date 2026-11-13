import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../util/platform_detection.dart';
import '../widgets/nav_capsule.dart';
import '../widgets/navigation_layout.dart';
import 'destinations.dart';

/// Kos TV: the menu shows the page of the button the person rests on, with a
/// remote or keys, without them pressing OK, and keeps the focus on the
/// menu so they can go on along it. Passing quickly loads nothing: a page
/// shows only after [restDelay] on its button.
///
/// The page that comes keeps out of the way: while the menu is in use pages
/// may not take the focus on their own ([holding]), so it stays on the button
/// until the person moves down into the page.
class MenuPreview {
  MenuPreview._();

  /// How long to rest on a button before its page shows.
  static const restDelay = Duration(milliseconds: 700);

  /// A key this recent moved the focus, rather than a page taking it.
  static const _keyWindow = Duration(milliseconds: 300);

  /// The menu page on its way, until its menu takes the focus.
  static final arriving = ValueNotifier<String?>(null);

  /// Whether the focus is being kept on the menu after showing a page.
  static bool get holding => _holding;
  static bool _holding = false;

  static FocusNode? _lastMenuFocus;
  static DateTime _lastKey = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _listening = false;
  static bool _restoring = false;

  /// Whether resting on a button shows its page here: with a remote or keys,
  /// not on touch screens.
  static bool get supported => !PlatformDetection.useMobileUi;

  static LogicalKeyboardKey? _lastArrow;
  static DateTime _lastArrowAt = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _tracking = false;

  /// Starts noting the arrow keys, for [movedAlong]. Menus call it once.
  static void track() {
    if (_tracking) return;
    _tracking = true;
    HardwareKeyboard.instance.addHandler(_noteArrow);
  }

  static bool _noteArrow(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _lastArrow = event.logicalKey;
      _lastArrowAt = DateTime.now();
      NavCapsule.endSnapping();
    }
    return false;
  }

  /// Whether the focus just moved along a menu laid out on [axis] (sideways
  /// on the top bar, up and down on the side bar), rather than coming into
  /// it from the page: only then does resting on a button show its page.
  static bool movedAlong(Axis axis) {
    if (DateTime.now().difference(_lastArrowAt) > _keyWindow) return false;
    final key = _lastArrow;
    return axis == Axis.horizontal
        ? key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight
        : key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown;
  }

  /// Shows [route], one of [Destinations.menuPages], keeping the focus on
  /// the menu. Home is never loaded again: it waits underneath as it was.
  static void show(BuildContext context, String route) {
    if (!supported || !Destinations.isMenuPage(route)) return;
    final router = GoRouter.of(context);
    final here = router.routerDelegate.currentConfiguration.uri.path;
    if (here == route) return;
    arriving.value = route;
    _hold();
    if (route == Destinations.home || PlatformDetection.isWeb) {
      router.go(route);
    } else if (Destinations.isMenuPage(here) && here != Destinations.home) {
      // One menu page replaces another, so Back still goes to Home.
      router.pushReplacement(route);
    } else {
      router.push(route);
    }
  }

  /// The menu of the page that came took the focus on [button].
  static void landed(FocusNode button) {
    if (arriving.value != null) arriving.value = null;
    _lastMenuFocus = button;
  }

  static void _hold() {
    _holding = true;
    if (_listening) return;
    _listening = true;
    FocusManager.instance.addListener(_onFocusChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  /// A touch or a click goes where the person points: the menu lets go.
  static void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent && arriving.value == null) _release();
  }

  static void _release() {
    _holding = false;
    arriving.value = null;
    _lastMenuFocus = null;
    if (!_listening) return;
    _listening = false;
    FocusManager.instance.removeListener(_onFocusChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  /// Keys that take the person out of the menu: down into the page, OK on
  /// a button, Back. Sideways keys only move along it.
  static final _leavingKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.browserBack,
  };

  static bool _onKey(KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        _leavingKeys.contains(event.logicalKey)) {
      _lastKey = DateTime.now();
    }
    return false;
  }

  static void _onFocusChanged() {
    // While a page is on its way its menu takes the focus itself.
    if (_restoring || arriving.value != null) return;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    if (isMenu(focus)) {
      _lastMenuFocus = focus;
      return;
    }
    // Arriving pages are still settling: anything they grab goes back to the
    // menu, unless the person moved there with a key.
    if (DateTime.now().difference(_lastKey) < _keyWindow) {
      _release();
      return;
    }
    final back = _lastMenuFocus;
    final backContext = back?.context;
    if (back == null ||
        backContext == null ||
        !back.canRequestFocus ||
        !(ModalRoute.isCurrentOf(backContext) ?? true)) {
      return;
    }
    _restoring = true;
    back.requestFocus();
    _restoring = false;
  }

  /// Whether [node] is in the navigation's menu (top bar or side bar).
  static bool isMenu(FocusNode node) {
    final roots = NavigationLayout.chromeFocusRoots;
    FocusNode? current = node;
    while (current != null) {
      if (roots.contains(current)) return true;
      current = current.parent;
    }
    return false;
  }

  /// The person went into the page: pages may take the focus again.
  static void stopHolding() => _release();
}
