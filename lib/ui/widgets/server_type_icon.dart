import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

class ServerTypeIcon extends StatelessWidget {
  final ServerType serverType;
  final double size;
  final Color? color;

  const ServerTypeIcon({
    super.key,
    required this.serverType,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColorScheme.onSurface;
    return CustomPaint(
      size: Size.square(size),
      painter: switch (serverType) {
        ServerType.jellyfin => _JellyfinLogoPainter(effectiveColor),
        ServerType.silo => _SiloGlyphPainter(effectiveColor),
      },
    );
  }
}

class _JellyfinLogoPainter extends CustomPainter {
  final Color color;
  _JellyfinLogoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final scale = size.width / 256;
    canvas.scale(scale);

    final path = Path()
      ..moveTo(127.998, 39.598)
      ..cubicTo(104.6, 39.598, 29.281, 176.145, 40.766, 199.206)
      ..cubicTo(52.251, 222.267, 203.874, 222.0, 215.233, 199.206)
      ..cubicTo(226.592, 176.412, 151.395, 39.598, 127.998, 39.598)
      ..close()
      ..moveTo(128.009, 74.617)
      ..cubicTo(143.338, 74.617, 192.609, 164.251, 185.166, 179.198)
      ..cubicTo(177.724, 194.14, 78.384, 194.307, 70.854, 179.198)
      ..cubicTo(63.324, 164.089, 112.681, 74.617, 128.009, 74.617)
      ..close()
      ..moveTo(127.998, 107.341)
      ..cubicTo(120.233, 107.341, 95.235, 152.658, 99.05, 160.31)
      ..cubicTo(102.865, 167.962, 153.178, 167.878, 156.948, 160.31)
      ..cubicTo(160.718, 152.742, 136.763, 107.344, 127.998, 107.341)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_JellyfinLogoPainter old) => old.color != color;
}

/// A generic grain-silo glyph: a domed cylinder with three bands cut out.
/// Deliberately not the Silo project's logo, which is its own trademark.
/// Drawn on a 24x24 grid like Material icons.
class _SiloGlyphPainter extends CustomPainter {
  final Color color;
  _SiloGlyphPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Clears the bands out of the body, so they show whatever is behind the
    // icon instead of a fixed background color.
    final cut = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..blendMode = BlendMode.clear;

    canvas.saveLayer(Offset.zero & const Size(24, 24), Paint());
    final body = Path()
      ..moveTo(6, 9)
      ..arcToPoint(const Offset(18, 9), radius: const Radius.circular(6))
      ..lineTo(18, 21)
      ..lineTo(6, 21)
      ..close();
    canvas.drawPath(body, fill);
    for (final y in const [11.5, 15.0, 18.5]) {
      canvas.drawLine(Offset(6, y), Offset(18, y), cut);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SiloGlyphPainter old) => old.color != color;
}
