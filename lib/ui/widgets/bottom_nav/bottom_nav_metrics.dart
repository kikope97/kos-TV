import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Kos TV: sizes of the glass bar (docs/diseno-menu, the phone's «cristal
/// líquido» and the tablet's compact bar) and of everything that has to
/// leave room for it.
abstract final class BottomNavMetrics {
  /// Side inset of the bar on a phone.
  static const double side = 14;

  /// The bar's height, and the round Search button's size beside it.
  static const double barHeight = 62;

  /// Between the bar and Search, and between the mini player and the bar.
  static const double gap = 10;

  /// The tablet's: between the mini player and the bar.
  static const double tabletGap = 12;

  /// The gathered bar: the page's tab and Search are circles this size.
  static const double collapsedSize = 54;

  /// The mini player above the open bar.
  static const double accessoryHeight = 54;

  /// The tablet's mini player.
  static const double tabletAccessoryHeight = 56;

  /// From the screen's edge to the bar (24 on a phone, 26 on a tablet in
  /// the mockups, the gesture line included).
  static const double floatingInset = 24;
  static const double tabletFloatingInset = 26;

  static const double iconSize = 23;
  static const double avatarSize = 24;

  /// Kos TV: a tablet (the shortest side of the window at least this wide)
  /// has a compact bar, centred, with each tab's icon and name side by side.
  static const double tabletBreakpoint = 600;

  /// The tablet's bar, without Search.
  static const double tabletBarWidth = 560;

  /// Whether the window is a tablet's.
  static bool isTablet(Size size) => size.shortestSide >= tabletBreakpoint;

  static double floatingBottomGap(double bottomInset, {bool tablet = false}) {
    final floor = tablet ? tabletFloatingInset : floatingInset;
    return bottomInset > 0 ? math.max(floor, bottomInset + 4) : floor;
  }

  /// Room the bar takes along the bottom of the screen, system inset and mini
  /// player included. The bar reports its open height even while gathered,
  /// so content padded by it doesn't jump every time the person changes
  /// scroll direction.
  static double heightFor({
    required double bottomInset,
    required bool miniPlayer,
    bool tablet = false,
  }) =>
      barHeight +
      floatingBottomGap(bottomInset, tablet: tablet) +
      (miniPlayer
          ? (tablet ? tabletAccessoryHeight + tabletGap : accessoryHeight + gap)
          : 0);
}
