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

  /// The gathered bar: the page's tab and Search are circles this size.
  static const double collapsedSize = 54;

  /// The mini player above the open bar.
  static const double accessoryHeight = 54;

  /// Above the screen's edge where the system reports no inset of its own.
  static const double floatingInset = 16;

  static const double iconSize = 23;
  static const double avatarSize = 24;

  /// Kos TV: a tablet (the shortest side of the window at least this wide)
  /// has a compact bar, centred, with each tab's icon and name side by side.
  static const double tabletBreakpoint = 600;

  /// The tablet's bar, without Search.
  static const double tabletBarWidth = 560;

  /// Whether the window is a tablet's.
  static bool isTablet(Size size) => size.shortestSide >= tabletBreakpoint;

  static double floatingBottomGap(double bottomInset) =>
      bottomInset > 0 ? bottomInset + 8 : floatingInset;

  /// Room the bar takes along the bottom of the screen, system inset and mini
  /// player included. The bar reports its open height even while gathered,
  /// so content padded by it doesn't jump every time the person changes
  /// scroll direction.
  static double heightFor({
    required double bottomInset,
    required bool miniPlayer,
  }) =>
      barHeight +
      floatingBottomGap(bottomInset) +
      (miniPlayer ? accessoryHeight + gap : 0);
}
