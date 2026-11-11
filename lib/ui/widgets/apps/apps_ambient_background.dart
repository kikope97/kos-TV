import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// What the background of All apps takes on: the focused app's [color] and
/// how far across the screen it is ([across], 0 at the left, 1 at the right).
@immutable
class AppsAmbience {
  const AppsAmbience({required this.color, this.across = 0});

  final Color color;
  final double across;

  static AppsAmbience lerp(AppsAmbience a, AppsAmbience b, double t) =>
      AppsAmbience(
        color: Color.lerp(a.color, b.color, t)!,
        across: a.across + (b.across - a.across) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is AppsAmbience && other.color == color && other.across == across;

  @override
  int get hashCode => Object.hash(color, across);
}

class _AmbienceTween extends Tween<AppsAmbience> {
  _AmbienceTween({super.begin, super.end});

  @override
  AppsAmbience lerp(double t) => AppsAmbience.lerp(begin!, end!, t);
}

/// Kos TV: the background of All apps, which takes on the colour of the
/// focused app (Jellyfin blue, Netflix red…): a soft light from the top that
/// slides along to stand over the focused app's column, and a fainter one
/// from the bottom on the other side, both drifting slowly and blending into
/// the next app's colour as the focus moves.
///
/// With animations turned off on the device the lights stay still and change
/// at once.
class AppsAmbientBackground extends StatefulWidget {
  const AppsAmbientBackground({super.key, required this.ambience});

  /// What to take on; it changes as the focus moves.
  final ValueListenable<AppsAmbience> ambience;

  /// How long the glows take to blend into a new colour.
  static const blend = Duration(milliseconds: 650);

  /// One slow round of the drift.
  static const drift = Duration(seconds: 16);

  @override
  State<AppsAmbientBackground> createState() => _AppsAmbientBackgroundState();
}

class _AppsAmbientBackgroundState extends State<AppsAmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: AppsAmbientBackground.drift,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: ValueListenableBuilder<AppsAmbience>(
        valueListenable: widget.ambience,
        builder: (context, ambience, _) => TweenAnimationBuilder<AppsAmbience>(
          tween: _AmbienceTween(begin: ambience, end: ambience),
          duration: still ? Duration.zero : AppsAmbientBackground.blend,
          curve: Curves.easeOutCubic,
          builder: (context, blended, _) => CustomPaint(
            painter: _GlowPainter(ambience: blended, drift: _drift),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.ambience, required this.drift})
    : super(repaint: drift);

  final AppsAmbience ambience;
  final Animation<double> drift;

  Color get color => ambience.color;

  @override
  void paint(Canvas canvas, Size size) {
    final turn = drift.value * 2 * math.pi;
    final side = size.longestSide;
    final across = ambience.across.clamp(0.0, 1.0);
    // From the top, over the focused app's column.
    _glow(
      canvas,
      size,
      center: Offset(
        size.width * (0.12 + 0.76 * across + 0.05 * math.sin(turn)),
        size.height * (0.02 + 0.08 * math.cos(turn)),
      ),
      radius: side * (0.72 + 0.05 * math.sin(turn * 2)),
      alpha: 0.42,
    );
    // Fainter, from the bottom on the other side, moving the other way.
    _glow(
      canvas,
      size,
      center: Offset(
        size.width * (0.88 - 0.76 * across - 0.05 * math.cos(turn)),
        size.height * (1.04 - 0.07 * math.sin(turn)),
      ),
      radius: side * 0.6,
      alpha: 0.2,
    );
  }

  void _glow(
    Canvas canvas,
    Size size, {
    required Offset center,
    required double radius,
    required double alpha,
  }) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.35),
          color.withValues(alpha: 0),
        ],
        const [0, 0.45, 1],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) =>
      oldDelegate.ambience != ambience || oldDelegate.drift != drift;
}
