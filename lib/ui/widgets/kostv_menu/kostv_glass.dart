import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart' show GlassSettings;

import '../../../util/platform_detection.dart';
import '../music/design/kostv_music_tokens.dart';

/// Kos TV: whether the menu's glass blurs what is behind it. Only where the
/// device draws real backdrop blurs (the glass tier is automatic: never on a
/// TV, nor on the web, where CanvasKit's blur stutters; weak phones drop to
/// it by themselves). Everywhere else the same glass is drawn on a nearly
/// opaque fill, which costs what a flat bar costs.
bool get kostvGlassBlurs =>
    GlassSettings.blursBackdrop && !PlatformDetection.isTV;

/// Kos TV: the menu's «liquid glass» (docs/diseno-menu): a light blur with
/// more saturation, a white fill from 14 % at the top to 4 %, a 1 px rim
/// brighter at the top left and the bottom right, and a soft shine at the top
/// left. Without a blur ([kostvGlassBlurs]), the fill is nearly opaque.
///
/// The blur is [BackdropFilter.grouped], so the bar, the Search button and
/// the mini player under one [BackdropGroup] (the navigation layout's) share
/// one backdrop pass.
class KostvGlass extends StatelessWidget {
  const KostvGlass({
    super.key,
    required this.child,
    this.radius = 999,
    this.heavy = false,
    this.tint,
    this.shadow = true,
    this.allowBlur = true,
  });

  final Widget child;
  final double radius;

  /// The sheets' glass: more blur and a darker fill, to read on top of a
  /// whole page.
  final bool heavy;

  /// A colour wash over the fill («Mis peticiones» in the brand's colours).
  final Gradient? tint;
  final bool shadow;

  /// False for a drawing of the glass (the settings' previews), which never
  /// blurs.
  final bool allowBlur;

  @override
  Widget build(BuildContext context) {
    final blurs = allowBlur && kostvGlassBlurs;
    final shape = BorderRadius.circular(radius);
    final base = blurs
        ? (heavy ? const Color(0x6B12121A) : const Color(0x33141C1C))
        : (heavy ? const Color(0xF2181820) : const Color(0xE61E1E28));
    Widget body = ColoredBox(
      color: base,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: heavy ? 0.12 : 0.14),
              Colors.white.withValues(alpha: heavy ? 0.03 : 0.04),
              Colors.white.withValues(alpha: heavy ? 0.03 : 0.07),
            ],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
    body = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: body),
        if (tint != null)
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: tint)),
          ),
        // The shine at the top left.
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.64, -1.4),
                  radius: 1.1,
                  colors: [Color(0x24FFFFFF), Color(0x00FFFFFF)],
                  stops: [0, 0.46],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
    if (blurs) {
      final sigma = heavy ? 22.0 : 10.0;
      body = BackdropFilter.grouped(
        filter: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          inner: const ColorFilter.matrix(_saturate),
        ),
        child: body,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: Color(0x61000000),
                  blurRadius: 32,
                  offset: Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        foregroundPainter: KostvGlassRimPainter(radius: radius),
        child: ClipRRect(borderRadius: shape, child: body),
      ),
    );
  }

  // Saturation 1.9 (a livelier backdrop than plain grey frost).
  static const _saturate = <double>[
    1.6347, -0.5653, -0.0694, 0, 0, //
    -0.1653, 1.2347, -0.0694, 0, 0, //
    -0.1653, -0.5653, 1.7306, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// Kos TV: the glass's 1 px rim: white, strongest at the top left and the
/// bottom right, or the kOS gradient on the active tab's pill.
class KostvGlassRimPainter extends CustomPainter {
  const KostvGlassRimPainter({required this.radius, this.brand = false});

  final double radius;
  final bool brand;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = radius.clamp(0.0, size.shortestSide / 2);
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.6),
      Radius.circular(r),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = brand ? 1.3 : 1
      ..shader =
          (brand
                  ? const LinearGradient(
                      begin: Alignment(-1, -0.6),
                      end: Alignment(1, 0.6),
                      colors: [
                        Color(0xE64FD8FF),
                        Color(0x8C8F6BFF),
                        Color(0xE6FF5CCF),
                      ],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xA6FFFFFF),
                        Color(0x1AFFFFFF),
                        Color(0x00FFFFFF),
                        Color(0x1AFFFFFF),
                        Color(0x73FFFFFF),
                      ],
                      stops: [0, 0.28, 0.5, 0.72, 1],
                    ))
              .createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(KostvGlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.brand != brand;
}

/// Kos TV: the active tab's pill: lighter glass with the kOS gradient on its
/// rim (the only place the gradient marks where you are).
class KostvActivePill extends StatelessWidget {
  const KostvActivePill({super.key, this.radius = 999});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: KostvGlassRimPainter(radius: radius, brand: true),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.17),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Kos TV: the short gradient line under the page you are on (the TV's
/// tabs).
class KostvHereMark extends StatelessWidget {
  const KostvHereMark({super.key, this.width = 22, this.opacity = 1});

  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        key: const ValueKey('nav_here_mark'),
        width: width,
        height: 3,
        decoration: BoxDecoration(
          gradient: KostvMusicTokens.gradient,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
