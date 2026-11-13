import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Kos TV: the menu's highlight, one glass capsule shared by all its buttons
/// that glides from the button left to the one reached, instead of each
/// button lighting up on its own.
///
/// It moves on springs, one per edge: the edge on the side it travels to is
/// quicker than the one behind, so on the way the capsule stretches a little
/// and thins, as a drop of liquid would, and settles on the button with a
/// hint of give. It grows out of the first button it lands on and fades when
/// the focus leaves the menu. Buttons take it with [NavCapsuleTarget], which
/// also tells them how much of them it covers, so their icon and text darken
/// as it passes under them.
class NavCapsule extends StatefulWidget {
  const NavCapsule({
    super.key,
    required this.child,
    this.axis = Axis.horizontal,
    this.radius = 999,
    this.color = Colors.white,
  });

  final Widget child;

  /// The way the buttons are laid out, and so the way the capsule travels.
  final Axis axis;

  /// The capsule's corner radius, at most half its height.
  final double radius;
  final Color color;

  static NavCapsuleState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_NavCapsuleScope>()?.state;

  static bool _snapping = false;

  /// Whether what is claimed now appears in place at once, rather than
  /// growing or gliding in: a page that came in under the same menu.
  static bool get snapping => _snapping;

  static Timer? _snapTimer;

  /// Makes what is claimed in the next moments appear in place: long enough
  /// for a slow device to build the page that came and open the label.
  static void snapNextFrame() {
    _snapping = true;
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(milliseconds: 450), endSnapping);
  }

  /// Back to gliding: the person moved on.
  static void endSnapping() {
    _snapTimer?.cancel();
    _snapping = false;
  }

  @override
  State<NavCapsule> createState() => NavCapsuleState();
}

class _Spring {
  double x = 0;
  double v = 0;

  void step(double target, double stiffness, double damping, double dt) {
    final friction = 2 * damping * math.sqrt(stiffness);
    v += (stiffness * (target - x) - friction * v) * dt;
    x += v * dt;
  }

  bool settledAt(double target) => (target - x).abs() < 0.2 && v.abs() < 3;

  void snap(double to) {
    x = to;
    v = 0;
  }
}

class NavCapsuleState extends State<NavCapsule>
    with SingleTickerProviderStateMixin {
  // The edge it travels towards, the one behind and the two across.
  static const _leadStiffness = 720.0;
  static const _leadDamping = 0.82;
  static const _trailStiffness = 300.0;
  static const _trailDamping = 1.0;
  static const _crossStiffness = 620.0;
  static const _crossDamping = 0.9;
  static const _fadeStiffness = 520.0;

  /// How much of the button the capsule starts as when it appears.
  static const _appearScale = 0.55;

  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);

  /// The buttons that want the capsule, the latest last: it sits on the last
  /// one still here, so a hovered button and a focused one share it.
  final _claims = <Element>[];
  final _left = _Spring();
  final _top = _Spring();
  final _right = _Spring();
  final _bottom = _Spring();
  final _shown = _Spring();
  Rect? _goal;
  Duration? _lastTick;
  bool _snapClaim = false;

  /// Frames the target has kept still: the capsule stops only once the
  /// button under it has stopped changing too.
  int _stillFrames = 0;
  Rect? _lastTarget;

  /// Ticks while the capsule moves, for what is drawn from it.
  ValueListenable<int> get frame => _frame;

  /// How visible it is, 0 to 1.
  double get opacity => _shown.x.clamp(0.0, 1.0);

  /// Where it is now, in this widget's coordinates, or null while hidden.
  Rect? get rect => opacity <= 0.001 || _goal == null
      ? null
      : Rect.fromLTRB(_left.x, _top.x, _right.x, _bottom.x);

  /// How much it thins across while it travels fast, 0 to 0.14.
  double get squash {
    final speed = widget.axis == Axis.horizontal
        ? (_left.v + _right.v) / 2
        : (_top.v + _bottom.v) / 2;
    return (speed.abs() / 7000).clamp(0.0, 0.14);
  }

  /// The shape drawn now, thinned while it travels fast.
  RRect? get shape {
    final r = rect;
    if (r == null) return null;
    final k = squash;
    final drawn = widget.axis == Axis.horizontal
        ? Rect.fromLTRB(
            r.left,
            r.top + r.height * k / 2,
            r.right,
            r.bottom - r.height * k / 2,
          )
        : Rect.fromLTRB(
            r.left + r.width * k / 2,
            r.top,
            r.right - r.width * k / 2,
            r.bottom,
          );
    return RRect.fromRectAndRadius(
      drawn,
      Radius.circular(math.min(widget.radius, drawn.shortestSide / 2)),
    );
  }

  /// The [shape] in [button]'s own coordinates, or null when it misses it.
  RRect? shapeOver(BuildContext button) {
    final now = shape;
    final box = _boxOf(button);
    if (now == null || box == null) return null;
    if (!now.outerRect.overlaps(box)) return null;
    return now.shift(-box.topLeft);
  }

  /// Whether a button of the menu has it (the menu is in use).
  bool get engaged => _claims.any((element) => element.mounted);

  /// [button] wants the capsule (focused or under the pointer).
  void claim(BuildContext button) {
    if (NavCapsule.snapping) _snapClaim = true;
    final element = button as Element;
    _claims
      ..remove(element)
      ..add(element);
    _wake();
  }

  /// [button] no longer wants it.
  void release(BuildContext button) {
    if (_claims.remove(button)) _wake();
  }

  /// Something under it changed size (a label opening): follow it.
  void nudge() => _wake();

  /// How much of [button] the capsule covers, 0 to 1, faded with it.
  double coverOf(BuildContext button) {
    final now = rect;
    if (now == null) return 0;
    final box = _boxOf(button);
    if (box == null || box.width <= 0 || box.height <= 0) return 0;
    final overlap = now.intersect(box);
    if (overlap.width <= 0 || overlap.height <= 0) return 0;
    final share = widget.axis == Axis.horizontal
        ? overlap.width / box.width
        : overlap.height / box.height;
    return (share * opacity).clamp(0.0, 1.0);
  }

  void _wake() {
    if (!mounted || _ticker.isActive) return;
    _lastTick = null;
    _ticker.start();
  }

  Rect? _boxOf(BuildContext button) {
    final me = context.findRenderObject();
    final box = button.findRenderObject();
    if (me is! RenderBox ||
        box is! RenderBox ||
        !me.attached ||
        !box.attached ||
        !me.hasSize ||
        !box.hasSize) {
      return null;
    }
    try {
      return box.localToGlobal(Offset.zero, ancestor: me) & box.size;
    } catch (_) {
      // Somewhere between them is not laid out yet; next frame.
      return null;
    }
  }

  Rect? _target() {
    for (var i = _claims.length - 1; i >= 0; i--) {
      final element = _claims[i];
      if (!element.mounted) {
        _claims.removeAt(i);
        continue;
      }
      final box = _boxOf(element);
      if (box != null) return box;
    }
    return null;
  }

  void _tick(Duration now) {
    final elapsed = _lastTick == null
        ? 1 / 60
        : (now - _lastTick!).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = now;
    final dt = elapsed.clamp(0.0, 0.05);

    final target = _target();
    if (target != null && _snapClaim) {
      // In place at once, for as long as it is asked to and until the button
      // stops changing, so a label that opens meanwhile is followed too.
      if (!NavCapsule.snapping && _stillFrames >= 2) _snapClaim = false;
      _left.snap(target.left);
      _right.snap(target.right);
      _top.snap(target.top);
      _bottom.snap(target.bottom);
      _shown.snap(1);
      _goal = target;
    } else if (target != null) {
      if (_goal == null || (_shown.x < 0.02 && _shown.v <= 0)) {
        // Appearing: it grows out of the button.
        final c = target.center;
        _left.snap(c.dx - target.width * _appearScale / 2);
        _right.snap(c.dx + target.width * _appearScale / 2);
        _top.snap(c.dy - target.height * _appearScale / 2);
        _bottom.snap(c.dy + target.height * _appearScale / 2);
      }
      _goal = target;
    }
    final goal = _goal;
    if (goal == null) {
      _ticker.stop();
      return;
    }
    _stillFrames = target != null && target == _lastTarget
        ? _stillFrames + 1
        : 0;
    _lastTarget = target;

    final horizontal = widget.axis == Axis.horizontal;
    final travel = horizontal
        ? goal.center.dx - (_left.x + _right.x) / 2
        : goal.center.dy - (_top.x + _bottom.x) / 2;
    // Small steps keep the springs steady when a frame comes late.
    final steps = math.max(1, (dt * 240).ceil());
    final h = dt / steps;
    for (var i = 0; i < steps; i++) {
      void edge(_Spring s, double to, bool leads) => s.step(
        to,
        leads ? _leadStiffness : _trailStiffness,
        leads ? _leadDamping : _trailDamping,
        h,
      );
      void across(_Spring s, double to) =>
          s.step(to, _crossStiffness, _crossDamping, h);
      if (horizontal) {
        edge(_left, goal.left, travel < 0);
        edge(_right, goal.right, travel > 0);
        across(_top, goal.top);
        across(_bottom, goal.bottom);
      } else {
        edge(_top, goal.top, travel < 0);
        edge(_bottom, goal.bottom, travel > 0);
        across(_left, goal.left);
        across(_right, goal.right);
      }
      _shown.step(target != null ? 1 : 0, _fadeStiffness, 1, h);
    }
    // Nothing behind the trailing edge: a drop doesn't turn inside out.
    if (_right.x < _left.x) _right.x = _left.x;
    if (_bottom.x < _top.x) _bottom.x = _top.x;
    _frame.value++;

    final still =
        _left.settledAt(goal.left) &&
        _right.settledAt(goal.right) &&
        _top.settledAt(goal.top) &&
        _bottom.settledAt(goal.bottom);
    if (target == null && _shown.x < 0.01) {
      _shown.snap(0);
      _goal = null;
      _frame.value++;
      _ticker.stop();
    } else if (target != null &&
        still &&
        _shown.settledAt(1) &&
        _stillFrames >= 4 &&
        !_snapClaim) {
      _left.snap(goal.left);
      _right.snap(goal.right);
      _top.snap(goal.top);
      _bottom.snap(goal.bottom);
      _shown.snap(1);
      _frame.value++;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NavCapsuleScope(
      state: this,
      child: CustomPaint(painter: _CapsulePainter(this), child: widget.child),
    );
  }
}

class _NavCapsuleScope extends InheritedWidget {
  const _NavCapsuleScope({required this.state, required super.child});

  final NavCapsuleState state;

  @override
  bool updateShouldNotify(_NavCapsuleScope old) => old.state != state;
}

class _CapsulePainter extends CustomPainter {
  _CapsulePainter(this.capsule) : super(repaint: capsule._frame);

  final NavCapsuleState capsule;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = capsule.shape;
    final o = capsule.opacity;
    if (shape == null || o <= 0) return;
    final rect = shape.outerRect;
    final radius = shape.tlRadiusX;
    final color = capsule.widget.color;

    // A soft shadow lifts it off the bar.
    canvas.drawRRect(
      shape.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3 * o)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // The body, lit from above.
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: o),
            Color.lerp(color, Colors.black, 0.1)!.withValues(alpha: 0.92 * o),
          ],
        ).createShader(rect),
    );
    // A sheen across the top half, as on glass.
    final sheen = Rect.fromLTRB(
      rect.left + 1.5,
      rect.top + 1.5,
      rect.right - 1.5,
      rect.center.dy,
    );
    if (sheen.width > 0 && sheen.height > 0) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          sheen,
          topLeft: Radius.circular(math.max(0, radius - 1.5)),
          topRight: Radius.circular(math.max(0, radius - 1.5)),
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.55 * o),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(sheen),
      );
    }
    // A bright rim.
    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.7 * o),
    );
  }

  @override
  bool shouldRepaint(_CapsulePainter old) => old.capsule != capsule;
}

/// A button of a [NavCapsule]: takes the capsule while [active], and is built
/// twice by [builder]: as it looks on the bar (`cover` 0) and as it looks on
/// the capsule (`cover` 1), the second shown only where the capsule is, cut to
/// its shape, so the icon and text turn dark exactly where it passes under
/// them. Without a capsule above, it is built once, with `cover` 1 while
/// active.
class NavCapsuleTarget extends StatefulWidget {
  const NavCapsuleTarget({
    super.key,
    required this.active,
    required this.builder,
  });

  final bool active;
  final Widget Function(BuildContext context, double cover) builder;

  @override
  State<NavCapsuleTarget> createState() => _NavCapsuleTargetState();
}

class _NavCapsuleTargetState extends State<NavCapsuleTarget> {
  NavCapsuleState? _capsule;
  bool _claimed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depends on the route, to wake when its page is the one shown again.
    ModalRoute.isCurrentOf(context);
    final capsule = NavCapsule.maybeOf(context);
    if (capsule != _capsule) {
      if (_claimed) _capsule?.release(context);
      _claimed = false;
      _capsule?.frame.removeListener(_onFrame);
      _capsule = capsule;
      capsule?.frame.addListener(_onFrame);
    }
    _sync();
  }

  // Where the capsule covers it, as last drawn.
  RRect? _over;

  /// Each frame of the capsule's slide: rebuilt only the buttons it is
  /// over, or has just left (not every button of the menu every frame).
  void _onFrame() {
    final capsule = _capsule;
    if (capsule == null || !mounted) return;
    final over = capsule.shapeOver(context);
    if (over == null && _over == null) return;
    setState(() => _over = over);
  }

  @override
  void didUpdateWidget(NavCapsuleTarget old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final capsule = _capsule;
    if (capsule == null || widget.active == _claimed) return;
    // A menu on a page that is no longer the one shown stays as it was, so a
    // page coming in over it under the same menu doesn't show it changing.
    if (!(ModalRoute.isCurrentOf(context) ?? true)) return;
    _claimed = widget.active;
    if (_claimed) {
      capsule.claim(context);
    } else {
      capsule.release(context);
    }
  }

  @override
  void dispose() {
    _capsule?.frame.removeListener(_onFrame);
    if (_claimed) _capsule?.release(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capsule = _capsule;
    if (capsule == null) {
      return widget.builder(context, widget.active ? 1 : 0);
    }
    final over = _over = capsule.shapeOver(context);
    // The dark look only while the capsule is over it, cut to its shape;
    // the plain one stays the same widget either way.
    return Stack(
      children: [
        widget.builder(context, 0),
        if (over != null)
          Positioned.fill(
            child: ClipPath(
              clipper: _ShapeClipper(over),
              child: widget.builder(context, 1),
            ),
          ),
      ],
    );
  }
}

class _ShapeClipper extends CustomClipper<Path> {
  _ShapeClipper(this.shape);

  final RRect? shape;

  @override
  Path getClip(Size size) {
    final shape = this.shape;
    return shape == null ? Path() : (Path()..addRRect(shape));
  }

  @override
  bool shouldReclip(_ShapeClipper old) => old.shape != shape;
}
