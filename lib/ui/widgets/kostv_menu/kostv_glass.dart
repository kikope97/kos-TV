import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart'
    show GlassQuality, GlassSettings;

import '../../../util/platform_detection.dart';
import '../music/design/kostv_music_tokens.dart';
import 'kostv_nav_avatar.dart';

/// Kos TV: whether the menu's glass blurs what is behind it (docs/diseno-menu,
/// «cristal líquido»). Everywhere but a TV: the menu's pieces are few and
/// small (the bar, Search, the mini player, the page's header) and share one
/// backdrop pass, so phones, tablets and the web blur them even where the
/// rest of the app keeps to the cheap tier. A device the adaptive scope found
/// struggling, and every TV, draw the same glass on a nearly opaque fill,
/// which costs what a flat bar costs.
bool get kostvGlassBlurs {
  if (PlatformDetection.isTV) return false;
  if (GlassSettings.usePackageRenderer &&
      GlassSettings.packageQuality == GlassQuality.minimal) {
    return false;
  }
  return GlassSettings.blursBackdrop || kIsWeb;
}

/// Kos TV: the grain of the glass (`NOISE` in docs/diseno-menu): white noise,
/// very soft, so the glass doesn't look like plastic. A small tile made once
/// and repeated, never a shader.
final ValueNotifier<ui.Image?> kostvGrain = _makeGrain();

ValueNotifier<ui.Image?> _makeGrain() {
  final notifier = ValueNotifier<ui.Image?>(null);
  const side = 140;
  final random = math.Random(7);
  final pixels = Uint8List(side * side * 4);
  for (var i = 0; i < side * side; i++) {
    // Fractal noise sits round the middle: the mean of a few draws.
    final n =
        (random.nextDouble() + random.nextDouble() + random.nextDouble()) / 3;
    // White, faint: what shows of the noise once screened over the glass
    // (premultiplied).
    final a = ((0.012 + (n - 0.5).abs() * 0.09) * 255).round().clamp(0, 255);
    pixels[i * 4] = a;
    pixels[i * 4 + 1] = a;
    pixels[i * 4 + 2] = a;
    pixels[i * 4 + 3] = a;
  }
  try {
    ui.decodeImageFromPixels(
      pixels,
      side,
      side,
      ui.PixelFormat.rgba8888,
      (image) => notifier.value = image,
    );
  } catch (_) {
    // No grain where an image can't be made (some tests): the glass reads
    // the same without it.
  }
  return notifier;
}

/// Kos TV: the menu's «liquid glass» (docs/diseno-menu, `.g`): a light blur
/// with more saturation and a touch more light, a white fill from 14 % at the
/// top to 4 % and back to 7 %, a 1 px rim brighter at the top left and the
/// bottom right, a line of light along the top inside, a soft shine at the
/// top left and a fine grain. Without a blur ([kostvGlassBlurs]), the fill is
/// nearly opaque.
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
    this.fill,
    this.nested = false,
  });

  /// Glass on glass (a sheet's tiles): no blur of its own, as the glass
  /// under it has already blurred the page, but the same light fill.
  final bool nested;

  final Widget child;
  final double radius;

  /// The sheets' glass: more blur and a darker fill, to read on top of a
  /// whole page.
  final bool heavy;

  /// A colour wash over the fill («Mis peticiones» in the brand's colours).
  final Gradient? tint;
  final bool shadow;

  /// A lighter fill on top of the glass (a chosen chip).
  final Color? fill;

  /// False for a drawing of the glass (the settings' previews), which never
  /// blurs.
  final bool allowBlur;

  @override
  Widget build(BuildContext context) {
    final blurs = allowBlur && !nested && kostvGlassBlurs;
    final light = blurs || (nested && kostvGlassBlurs);
    final shape = BorderRadius.circular(radius);
    // rgba(20,20,28,.20) under the blur; .heavy rgba(18,18,26,.42); .nob
    // rgba(30,30,40,.90).
    final base = light
        ? (heavy ? const Color(0x6B12121A) : const Color(0x3314141C))
        : (heavy ? const Color(0xF2181820) : const Color(0xE61E1E28));
    final List<Color> sheen;
    final List<double> stops;
    if (!light) {
      sheen = [
        Colors.white.withValues(alpha: 0.10),
        Colors.white.withValues(alpha: 0.02),
      ];
      stops = const [0, 0.55];
    } else if (heavy) {
      sheen = [
        Colors.white.withValues(alpha: 0.12),
        Colors.white.withValues(alpha: 0.03),
      ];
      stops = const [0, 0.4];
    } else {
      sheen = [
        Colors.white.withValues(alpha: 0.14),
        Colors.white.withValues(alpha: 0.04),
        Colors.white.withValues(alpha: 0.07),
      ];
      stops = const [0, 0.55, 1];
    }
    Widget body = Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: base,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: sheen,
                  stops: stops,
                ),
              ),
            ),
          ),
        ),
        if (tint != null)
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: tint)),
          ),
        if (fill != null) Positioned.fill(child: ColoredBox(color: fill!)),
        // The shine at the top left and the grain (`.g:after`, at .55).
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _ShineAndGrainPainter(radius)),
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
          inner: ColorFilter.matrix(heavy ? _heavyColor : _color),
        ),
        child: body,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        // 0 12px 32px rgba(0,0,0,.38), 0 2px 6px rgba(0,0,0,.22).
        boxShadow: shadow
            ? const [
                BoxShadow(
                  color: Color(0x61000000),
                  blurRadius: 32,
                  offset: Offset(0, 12),
                ),
                BoxShadow(
                  color: Color(0x38000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
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

  /// saturate(1.9) brightness(1.06).
  static final _color = _saturateBrightness(1.9, 1.06);

  /// The sheets': saturate(1.8) brightness(.9).
  static final _heavyColor = _saturateBrightness(1.8, 0.9);

  static List<double> _saturateBrightness(double s, double b) {
    const r = 0.2126, g = 0.7152, bl = 0.0722;
    return [
      (r + (1 - r) * s) * b, (g - g * s) * b, (bl - bl * s) * b, 0, 0, //
      (r - r * s) * b, (g + (1 - g) * s) * b, (bl - bl * s) * b, 0, 0, //
      (r - r * s) * b, (g - g * s) * b, (bl + (1 - bl) * s) * b, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }
}

/// The glass's shine at the top left and its grain.
class _ShineAndGrainPainter extends CustomPainter {
  _ShineAndGrainPainter(this.radius) : super(repaint: kostvGrain);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    // radial-gradient(110% 80% at 18% -20%, rgba(255,255,255,.24),
    // transparent 46%), at .55.
    canvas.save();
    canvas.translate(size.width * 0.18, -size.height * 0.2);
    canvas.scale(1.1 * size.width, 0.8 * size.height);
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          1,
          const [Color(0x22FFFFFF), Color(0x00FFFFFF)],
          const [0, 0.46],
        ),
    );
    canvas.restore();
    final grain = kostvGrain.value;
    if (grain != null) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ImageShader(
            grain,
            TileMode.repeated,
            TileMode.repeated,
            Matrix4.identity().storage,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_ShineAndGrainPainter old) => old.radius != radius;
}

/// Kos TV: the glass's 1 px rim: white, strongest at the top left and the
/// bottom right, with a line of light along the top inside and a fainter one
/// along the bottom; or the kOS gradient on the active tab's pill.
class KostvGlassRimPainter extends CustomPainter {
  const KostvGlassRimPainter({required this.radius, this.brand = false});

  final double radius;
  final bool brand;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final r = radius.clamp(0.0, size.shortestSide / 2);
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(r));
    if (!brand) {
      // inset 0 1px 1px rgba(255,255,255,.38), inset 0 -1px 1px
      // rgba(255,255,255,.10), inset 0 0 22px rgba(255,255,255,.07).
      canvas.save();
      canvas.clipRRect(outer);
      canvas.drawRRect(
        outer.inflate(4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = const Color(0x12FFFFFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawRRect(
        outer.shift(const Offset(0, 1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x61FFFFFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
      );
      canvas.drawRRect(
        outer.shift(const Offset(0, -1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x1AFFFFFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
      );
      canvas.restore();
    }
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(brand ? 0.6 : 0.5),
      Radius.circular(r),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = brand ? 1.2 : 1
      ..shader =
          (brand
                  // linear-gradient(120deg, rgba(79,216,255,.9),
                  // rgba(143,107,255,.55) 50%, rgba(255,92,207,.9)), at .85.
                  ? const LinearGradient(
                      begin: Alignment(-0.87, -0.5),
                      end: Alignment(0.87, 0.5),
                      colors: [
                        Color(0xC34FD8FF),
                        Color(0x778F6BFF),
                        Color(0xC3FF5CCF),
                      ],
                    )
                  // linear-gradient(135deg, .65, .10 28%, 0 50%, .10 72%,
                  // .45).
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

/// Kos TV: the active tab's pill (`.pillon`): lighter glass, a line of light
/// on top and the kOS gradient on its rim (the only place the gradient marks
/// where you are).
class KostvActivePill extends StatelessWidget {
  const KostvActivePill({super.key, this.radius = 999});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return CustomPaint(
      foregroundPainter: KostvGlassRimPainter(radius: radius, brand: true),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.17),
          borderRadius: shape,
          // 0 4px 14px rgba(0,0,0,.18).
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        // inset 0 1px 0 rgba(255,255,255,.38).
        child: ClipRRect(
          borderRadius: shape,
          child: const CustomPaint(
            painter: _TopLightPainter(),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _TopLightPainter extends CustomPainter {
  const _TopLightPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final r = size.shortestSide / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(r),
      ).shift(const Offset(0, 1)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x61FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_TopLightPainter oldDelegate) => false;
}

/// Kos TV: the short gradient line under the page you are on (the TV's
/// tabs).
class KostvHereMark extends StatelessWidget {
  const KostvHereMark({
    super.key,
    this.width = 22,
    this.height = 3,
    this.opacity = 1,
  });

  final double width;
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        key: const ValueKey('nav_here_mark'),
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: KostvMusicTokens.gradient,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Kos TV: a round glass button (`.g.rb`): the page header's «send to the TV»
/// and requests tray, Search beside the bar, the gathered bar's tab, the
/// sheets' ✕. A pink count at its top right when [count] is above zero.
class KostvGlassRoundButton extends StatelessWidget {
  const KostvGlassRoundButton({
    super.key,
    required this.size,
    required this.label,
    required this.child,
    this.onTap,
    this.selected = false,
    this.count = 0,
    this.countSize = 19,
    this.shadow = true,
  });

  final double size;
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final int count;
  final double countSize;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: KostvGlass(
                    shadow: shadow,
                    child: Stack(
                      children: [
                        if (selected)
                          const Positioned.fill(child: KostvActivePill()),
                        Center(child: child),
                      ],
                    ),
                  ),
                ),
                if (count > 0)
                  // .bdg: top -4px, right -5px.
                  Positioned(
                    top: -4,
                    right: -5,
                    child: KostvMenuCount(count: count, size: countSize),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
