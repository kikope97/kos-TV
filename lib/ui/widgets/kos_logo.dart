import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Kos TV: the kOS TV brand, taken from the "Power 4K" intro. The O is the
/// power button turned into a ring with the cyan, violet and pink gradient.
abstract final class KosBrand {
  static const cyan = Color(0xFF4FD8FF);
  static const violet = Color(0xFF8F6BFF);
  static const pink = Color(0xFFFF5CCF);
  static const ink = Color(0xFFF3F5FA);
  static const fontFamily = 'Outfit';

  static const gradientColors = [cyan, violet, pink];
  static const gradientStops = [0.0, 0.55, 1.0];

  /// The diagonal gradient of the ring, bottom left to top right.
  static Shader ringShader(Rect bounds) => const LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: gradientColors,
    stops: gradientStops,
  ).createShader(bounds);

  /// The gradient of the "TV" letters, left to right.
  static Shader textShader(Rect bounds) => const LinearGradient(
    begin: Alignment(-1, -0.2),
    end: Alignment(1, 0.2),
    colors: gradientColors,
    stops: gradientStops,
  ).createShader(bounds);

  static TextStyle letters(double fontSize) => TextStyle(
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: fontSize,
    height: 1,
    color: ink,
    letterSpacing: 0,
  );
}

/// Where the ring sits inside the slot the letter O would take: its outer
/// edge spans the cap height (plus the overshoot an O has), standing on the
/// baseline, with Outfit Bold's stroke weight.
class KosRingMetrics {
  KosRingMetrics(double fontSize, {required this.baseline, required this.width})
    : center = Offset(width / 2, baseline - fontSize * _capHeight / 2),
      radius = fontSize * (_outer - _stroke) / 2,
      stroke = fontSize * _stroke;

  static const _capHeight = 0.706;
  static const _outer = 0.728;
  static const _stroke = 0.118;

  final double baseline;
  final double width;
  final Offset center;
  final double radius;
  final double stroke;
}

/// Paints the finished ring: the gradient circle and the white comet that
/// runs around it. [cometTurn] is where the comet is, in turns from the top.
void paintKosRing(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required double stroke,
  double cometTurn = 0.14,
  double cometOpacity = 1,
  double startTurn = 0,
  double sweepTurns = 1,
}) {
  final rect = Rect.fromCircle(center: center, radius: radius);
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeCap = sweepTurns >= 1 ? StrokeCap.butt : StrokeCap.round
    ..shader = KosBrand.ringShader(rect.inflate(stroke / 2));
  const top = -math.pi / 2;
  if (sweepTurns >= 1) {
    canvas.drawCircle(center, radius, ring);
  } else if (sweepTurns > 0) {
    canvas.drawArc(
      rect,
      top + startTurn * 2 * math.pi,
      sweepTurns * 2 * math.pi,
      false,
      ring,
    );
  }
  if (cometOpacity <= 0) return;
  const cometLength = 0.09;
  final start = top + (cometTurn - cometLength / 2) * 2 * math.pi;
  final glow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke * 0.56
    ..strokeCap = StrokeCap.round
    ..color = KosBrand.cyan.withValues(alpha: 0.9 * cometOpacity)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.35);
  final comet = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke * 0.56
    ..strokeCap = StrokeCap.round
    ..color = Colors.white.withValues(alpha: cometOpacity);
  canvas.drawArc(rect, start, cometLength * 2 * math.pi, false, glow);
  canvas.drawArc(rect, start, cometLength * 2 * math.pi, false, comet);
}

/// The ring alone, as a square mark [size] across: the O of the wordmark,
/// used where Moonfin showed its moon (loading animation, admin exit).
/// With [color] it is painted flat in that colour, without the comet; else
/// in the brand gradient with the comet at [cometTurn].
class KosRingMark extends StatelessWidget {
  const KosRingMark({
    super.key,
    required this.size,
    this.color,
    this.cometTurn = 0.14,
  });

  final double size;
  final Color? color;
  final double cometTurn;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _RingMarkPainter(color, cometTurn)),
  );
}

class _RingMarkPainter extends CustomPainter {
  _RingMarkPainter(this.color, this.cometTurn);

  final Color? color;
  final double cometTurn;

  // Outfit Bold's stroke to the O's outer size, as in [KosRingMetrics].
  static const _strokeRatio = KosRingMetrics._stroke / KosRingMetrics._outer;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = size.shortestSide * 0.92;
    final stroke = outer * _strokeRatio;
    final radius = (outer - stroke) / 2;
    final center = size.center(Offset.zero);
    if (color != null) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = color!,
      );
      return;
    }
    paintKosRing(
      canvas,
      center: center,
      radius: radius,
      stroke: stroke,
      cometTurn: cometTurn,
    );
  }

  @override
  bool shouldRepaint(_RingMarkPainter old) =>
      old.color != color || old.cometTurn != cometTurn;
}

/// One of the parts of the wordmark, so the opening animation can bring
/// each in on its own.
enum KosLogoPart { k, s, tv }

/// The kOS TV wordmark, stacked: "kOS" with the ring for an O, and "TV"
/// spaced out underneath in the gradient (proposal B).
class KosLogo extends StatelessWidget {
  /// A logo [height] tall, the whole wordmark included.
  const KosLogo({super.key, required this.height})
    : fontSize = null,
      ringSlotKey = null,
      paintRing = true,
      decorate = null;

  /// The wordmark the opening animation builds: the ring is painted by the
  /// animation (it flies in from the middle of the screen), so the slot only
  /// keeps its place, under [ringSlotKey], and [decorate] wraps each part.
  const KosLogo.animated({
    super.key,
    required double this.fontSize,
    required GlobalKey this.ringSlotKey,
    required Widget Function(KosLogoPart part, Widget child) this.decorate,
  }) : height = 0,
       paintRing = false;

  /// Overall height relative to the font size: the "kOS" line, the gap and
  /// the "TV" line.
  static const heightFactor = 1.0 + 0.12 + 0.3;

  final double height;
  final double? fontSize;
  final GlobalKey? ringSlotKey;
  final bool paintRing;
  final Widget Function(KosLogoPart part, Widget child)? decorate;

  @override
  Widget build(BuildContext context) {
    final fs = fontSize ?? height / heightFactor;
    Widget part(KosLogoPart which, Widget child) =>
        decorate == null ? child : decorate!(which, child);
    final style = KosBrand.letters(fs);
    final tvSize = fs * 0.3;
    final tvSpacing = tvSize * 0.6;

    return Semantics(
      label: 'kOS TV',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              part(KosLogoPart.k, Text('k', style: style)),
              _RingSlot(key: ringSlotKey, style: style, paintRing: paintRing),
              part(KosLogoPart.s, Text('S', style: style)),
            ],
          ),
          SizedBox(height: fs * 0.12),
          part(
            KosLogoPart.tv,
            Padding(
              padding: EdgeInsets.only(left: tvSpacing),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: KosBrand.textShader,
                child: Text(
                  'TV',
                  style: TextStyle(
                    fontFamily: KosBrand.fontFamily,
                    fontWeight: FontWeight.w300,
                    fontSize: tvSize,
                    height: 1,
                    letterSpacing: tvSpacing,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Takes the place of the letter O (an invisible O gives it the width and
/// the baseline the row aligns on) and paints the ring in it.
class _RingSlot extends StatelessWidget {
  const _RingSlot({super.key, required this.style, required this.paintRing});

  final TextStyle style;
  final bool paintRing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(opacity: 0, child: Text('O', style: style)),
        if (paintRing)
          Positioned.fill(
            child: CustomPaint(painter: _RingPainter(style)),
          ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.style);

  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final m = kosRingMetricsFor(style, size.width);
    paintKosRing(canvas, center: m.center, radius: m.radius, stroke: m.stroke);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.style != style;
}

/// The ring's place inside a slot [width] wide set in [style].
KosRingMetrics kosRingMetricsFor(TextStyle style, double width) {
  final painter = TextPainter(
    text: TextSpan(text: 'O', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final baseline = painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  painter.dispose();
  return KosRingMetrics(style.fontSize!, baseline: baseline, width: width);
}
