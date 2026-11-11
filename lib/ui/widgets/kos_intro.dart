import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kos_logo.dart';

/// Kos TV: the opening animation, a three second cut of the "Power 4K" intro.
///
/// The power button draws itself in the middle of the screen and is pressed
/// (a flash, two ripples, a beam), then the ring flies into the O of the
/// wordmark while k, S and TV slide in, and the comet starts running around
/// the ring. Silent. Once done the logo stays, ring spinning, for as long as
/// the screen is up. With the system's animations turned off it shows the
/// finished logo at once.
class KosIntro extends StatefulWidget {
  const KosIntro({super.key, this.onFinished, this.footer});

  /// Called once, when the animation has finished (or was skipped).
  final VoidCallback? onFinished;

  /// Shown under the logo, such as a message with a Retry button.
  final Widget? footer;

  /// How long the animation runs.
  static const duration = Duration(milliseconds: 3000);

  @override
  State<KosIntro> createState() => _KosIntroState();
}

class _KosIntroState extends State<KosIntro> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: KosIntro.duration,
  );
  late final AnimationController _comet = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  final _stackKey = GlobalKey();
  final _slotKey = GlobalKey();
  Rect? _slot;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _intro.value = 1;
        _finish();
      } else {
        _intro.forward();
        _comet.repeat();
      }
    });
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    _intro.dispose();
    _comet.dispose();
    super.dispose();
  }

  /// Finds the O's slot in the wordmark, where the ring ends up.
  void _measure() {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final slot = _slotKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || slot == null || !slot.hasSize || !stack.hasSize) {
      return;
    }
    final rect = slot.localToGlobal(Offset.zero, ancestor: stack) & slot.size;
    if (rect != _slot) setState(() => _slot = rect);
  }

  double get _seconds =>
      _intro.value * KosIntro.duration.inMilliseconds / 1000;

  /// k slides in from the right, S and TV from the left, each fading in
  /// over the first half of its entrance.
  Widget Function(KosLogoPart, Widget) _decorate(double fontSize) {
    const curve = Cubic(0.16, 1, 0.3, 1);
    return (part, child) {
      final (start, length, from) = switch (part) {
        KosLogoPart.k => (1.48, 0.9, 1.0),
        KosLogoPart.s => (1.54, 0.9, -1.0),
        KosLogoPart.tv => (1.70, 1.0, -1.0),
      };
      return AnimatedBuilder(
        animation: _intro,
        child: child,
        builder: (context, child) {
          final p = ((_seconds - start) / length).clamp(0.0, 1.0);
          return Opacity(
            opacity: (p / 0.45).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(from * fontSize * 0.3 * (1 - curve.transform(p)), 0),
              child: child,
            ),
          );
        },
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final fontSize = math.min(size.width * 0.15, size.height * 0.24);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _measure();
        });
        final slot = _slot;
        final ring = slot == null
            ? null
            : kosRingMetricsFor(KosBrand.letters(fontSize), slot.width);
        return Stack(
          key: _stackKey,
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            RepaintBoundary(
              child: CustomPaint(
                painter: _IntroPainter(
                  intro: _intro,
                  comet: _comet,
                  slotCenter: slot == null ? null : slot.topLeft + ring!.center,
                  slotRadius: ring?.radius ?? fontSize * 0.305,
                  slotStroke: ring?.stroke ?? fontSize * 0.118,
                ),
              ),
            ),
            Center(
              child: KosLogo.animated(
                fontSize: fontSize,
                ringSlotKey: _slotKey,
                decorate: _decorate(fontSize),
              ),
            ),
            if (widget.footer != null)
              Align(
                alignment: const Alignment(0, 0.8),
                child: widget.footer,
              ),
          ],
        );
      },
    );
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter({
    required this.intro,
    required this.comet,
    required this.slotCenter,
    required this.slotRadius,
    required this.slotStroke,
  }) : super(repaint: Listenable.merge([intro, comet]));

  final Animation<double> intro;
  final Animation<double> comet;
  final Offset? slotCenter;
  final double slotRadius;
  final double slotStroke;

  static const _travel = Cubic(0.65, 0, 0.2, 1);
  static const _ripple = Cubic(0.1, 0.6, 0.3, 1);
  static const _settle = Cubic(0.2, 0.8, 0.2, 1);

  static double _phase(double t, double start, double length) =>
      ((t - start) / length).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final t = intro.value * KosIntro.duration.inMilliseconds / 1000;
    final center = size.center(Offset.zero);
    final cqw = size.width / 100;

    _glow(canvas, center, cqw, t);
    _rippleRing(canvas, center, cqw, _phase(t, 0.84, 1.2), KosBrand.cyan);
    _rippleRing(canvas, center, cqw, _phase(t, 0.98, 1.3), KosBrand.violet);
    _beam(canvas, center, cqw, t);
    _ring(canvas, size, center, t);
  }

  void _glow(Canvas canvas, Offset center, double cqw, double t) {
    final p = _phase(t, 0.82, 1.2);
    if (p <= 0 || p >= 1) return;
    final opacity = p < 0.18 ? p / 0.18 : 1 - (p - 0.18) / 0.82;
    final radius = 45 * cqw * (0.5 + 0.8 * p);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF82B4FF).withValues(alpha: 0.38 * opacity),
          const Color(0xFF6E78FF).withValues(alpha: 0.13 * opacity),
          Colors.transparent,
        ],
        stops: const [0, 0.28, 0.62],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  void _rippleRing(
    Canvas canvas,
    Offset center,
    double cqw,
    double p,
    Color color,
  ) {
    if (p <= 0 || p >= 1) return;
    final e = _ripple.transform(p);
    final radius = 17 * cqw * (1 + 2.2 * e);
    final opacity = 0.9 * (1 - e);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.35 * cqw
        ..color = color.withValues(alpha: opacity * 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cqw),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.35 * cqw
        ..color = color.withValues(alpha: opacity),
    );
  }

  void _beam(Canvas canvas, Offset center, double cqw, double t) {
    final p = _phase(t, 0.82, 0.6);
    if (p <= 0 || p >= 1) return;
    final grow = _settle.transform((p / 0.35).clamp(0.0, 1.0));
    final fade = p < 0.35 ? 1.0 : 1 - (p - 0.35) / 0.65;
    final narrow = p < 0.35 ? 1.0 : 1 - 0.8 * (p - 0.35) / 0.65;
    final height = 120 * cqw * grow;
    final rect = Rect.fromCenter(
      center: center,
      width: 0.5 * cqw * narrow,
      height: height,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            KosBrand.cyan.withValues(alpha: fade),
            Colors.white.withValues(alpha: fade),
            KosBrand.violet.withValues(alpha: fade),
            Colors.transparent,
          ],
          stops: const [0, 0.3, 0.5, 0.7, 1],
        ).createShader(rect),
    );
  }

  void _ring(Canvas canvas, Size size, Offset screenCenter, double t) {
    // From the middle of the screen, big (its outer edge 46 % of the height),
    // to its slot in the wordmark.
    final slotOuter = 2 * slotRadius + slotStroke;
    final bigScale = size.height * 0.46 / slotOuter;
    final travel = _travel.transform(_phase(t, 1.0, 0.75));
    final target = slotCenter ?? screenCenter;
    final center = Offset.lerp(screenCenter, target, travel)!;

    // The press: a quick dip and back.
    var press = 1.0;
    if (t > 0.82 && t < 1.0) {
      press = 1 - 0.1 * math.sin(math.pi * (t - 0.82) / 0.18);
    }
    final radius =
        slotRadius * (bigScale + (1 - bigScale) * travel) * press;

    // Thin while it is the power button, as thick as the letters once in place.
    final double units;
    if (t < 0.82) {
      units = 5;
    } else if (t < 0.96) {
      units = 5 + (t - 0.82) / 0.14;
    } else {
      units = 6 + 10 * _phase(t, 0.96, 0.79);
    }
    final stroke = units / 42 * radius;

    // Drawn with a gap at the top for the bar, closed on the press.
    double start = 0.06, sweep;
    if (t < 0.82) {
      sweep = 0.88 * Curves.easeInOutCubic.transform(_phase(t, 0, 0.7));
    } else {
      final close = Curves.easeOut.transform(_phase(t, 0.82, 0.14));
      start = 0.06 * (1 - close);
      sweep = 0.88 + 0.12 * close;
    }

    final cometOpacity = _phase(t, 1.9, 0.5);
    paintKosRing(
      canvas,
      center: center,
      radius: radius,
      stroke: stroke,
      startTurn: start,
      sweepTurns: sweep,
      cometTurn: 0.14 + comet.value,
      cometOpacity: cometOpacity,
    );

    // The bar of the power symbol: drops in, then retracts on the press.
    double bar;
    if (t < 0.82) {
      bar = Curves.easeOut.transform(_phase(t, 0.385, 0.21));
    } else {
      bar = 1 - Curves.easeIn.transform(_phase(t, 0.82, 0.16));
    }
    if (bar > 0) {
      final top = center.translate(0, -1.286 * radius);
      final bottom = center.translate(0, -0.286 * radius);
      canvas.drawLine(
        top,
        Offset.lerp(top, bottom, bar)!,
        Paint()
          ..color = KosBrand.ink
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_IntroPainter old) =>
      old.slotCenter != slotCenter ||
      old.slotRadius != slotRadius ||
      old.slotStroke != slotStroke;
}
