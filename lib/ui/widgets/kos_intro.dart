import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../util/platform_detection.dart';
import 'kos_logo.dart';

/// Kos TV: the opening, the "Power 4K" intro drawn by the app itself, frame
/// by frame, from the page it was designed on (docs/marca/intro-power-4k.html):
/// the same shapes, colours and timings as its video, with the video's own
/// sound playing alongside.
///
/// The power button draws itself in the middle of the screen and is pressed
/// (a glow, a beam, three ripples), then the ring flies into the O of
/// "kOS TV" while the letters slide in, a comet starts running round the
/// ring, "kiko.me" opens out underneath and it all fades to black.
///
/// It used to be the video. Decoding one is the first thing a slow TV has to
/// do on opening the app, and some couldn't: the screen stayed black for
/// seconds while the sound played, or the picture ran in slow motion. Drawn,
/// there is nothing to decode: it shows from the first frame, and it follows
/// the clock, so a TV that can't draw every frame skips some instead of
/// falling behind the sound.
///
/// Sound: on a TV always; on a phone only while its ringer is on; on the web
/// never, since browsers refuse sound before the page is touched. Any key or
/// a tap skips it. With the system's animations turned off it is skipped
/// (unless [evenWithoutAnimations]).
///
/// [show] plays it on its own over everything, from Settings.
class KosIntro extends StatefulWidget {
  const KosIntro({
    super.key,
    this.onFinished,
    this.footer,
    this.evenWithoutAnimations = false,
  });

  /// Plays even with the system's animations turned off: asked for on
  /// purpose («Ver la animación» in Settings).
  final bool evenWithoutAnimations;

  /// Called once, when the animation has finished (or was skipped).
  final VoidCallback? onFinished;

  /// Shown over the bottom, such as a message with a Retry button. While
  /// there is one the logo stays up instead of fading to black.
  final Widget? footer;

  /// Plays it now, over everything, and comes back when it ends (or on any
  /// key or a tap): to see it whenever, whatever the rules for opening.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, _, _) => Scaffold(
          backgroundColor: Colors.black,
          body: KosIntro(
            evenWithoutAnimations: true,
            onFinished: () {
              final navigator = Navigator.of(context);
              if (navigator.canPop()) navigator.pop();
            },
          ),
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// How long the animation runs, the fade to black included.
  static const duration = Duration(milliseconds: 7300);

  /// The longest the picture waits for the sound to start.
  static const soundWait = Duration(milliseconds: 900);

  @override
  State<KosIntro> createState() => _KosIntroState();
}

class _KosIntroState extends State<KosIntro>
    with SingleTickerProviderStateMixin {
  final _seconds = ValueNotifier<double>(0);
  final _fades = ValueNotifier<bool>(true);
  final _focusNode = FocusNode(debugLabel: 'kostvIntro');
  late final Ticker _ticker = createTicker(_onTick);
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _fades.value = widget.footer == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.evenWithoutAnimations &&
          (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _seconds.value = KosIntro.duration.inMilliseconds / 1000;
        _finish();
        return;
      }
      unawaited(_begin());
    });
  }

  /// The picture starts with the sound: once the device says it is playing,
  /// or after a short wait should it not answer.
  Future<void> _begin() async {
    await KosIntroSound.start().timeout(
      KosIntro.soundWait,
      onTimeout: () => false,
    );
    if (!mounted || _finished) return;
    unawaited(_ticker.start());
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    _seconds.value = t;
    if (t * 1000 >= KosIntro.duration.inMilliseconds) {
      _finish();
      // Faded to black, there is nothing left to draw.
      if (_fades.value) _ticker.stop();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished?.call();
  }

  void _skip() {
    if (_finished) return;
    unawaited(KosIntroSound.stop());
    _finish();
  }

  @override
  void didUpdateWidget(KosIntro oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fades.value = widget.footer == null;
    // A message arrived after the fade: bring the logo back for it.
    if (!_fades.value && !_ticker.isActive && _seconds.value > 0) {
      unawaited(_ticker.start());
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    _seconds.dispose();
    _fades.dispose();
    unawaited(KosIntroSound.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.footer == null,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && !_finished) {
          _skip();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: KosIntroPainter(seconds: _seconds, fades: _fades),
              ),
            ),
            if (widget.footer != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 48,
                child: Center(child: widget.footer),
              ),
          ],
        ),
      ),
    );
  }
}

/// Kos TV: the sound of the opening, the video's own track
/// (assets/intro/kostv_intro.m4a), played by the device's sound player: it
/// starts at once, with nothing of the app's video player to load.
abstract final class KosIntroSound {
  static const asset = 'assets/intro/kostv_intro.m4a';
  static const _channel = MethodChannel('org.moonfin.androidtv/platform');

  /// Starts it, where it may sound. Completes true once it is playing.
  static Future<bool> start() async {
    if (kIsWeb || !PlatformDetection.isAndroid) return false;
    try {
      final allowed =
          await _channel.invokeMethod<bool>('introSoundAllowed') ?? true;
      if (!allowed) return false;
      return await _channel.invokeMethod<bool>('introSoundPlay', {
            'asset': asset,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !PlatformDetection.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('introSoundStop');
    } on PlatformException {
      // Nothing was playing.
    } on MissingPluginException {
      // Not this platform.
    }
  }
}

/// Paints the opening at [seconds] on a 3840 × 2160 stage scaled to fit,
/// with the page's own numbers.
class KosIntroPainter extends CustomPainter {
  KosIntroPainter({required this.seconds, this.fades})
    : super(repaint: Listenable.merge([seconds, fades]));

  final ValueListenable<double> seconds;

  /// Whether it ends fading to black. Null for yes.
  final ValueListenable<bool>? fades;

  static const stage = Size(3840, 2160);
  static const _cx = 1920.0;
  static const _cy = 1000.0;
  static const _fontSize = 480.0;

  // Outfit Bold's O as the page measures it: its height with the overshoot
  // and its stroke, and the cap height its middle sits at, in ems.
  static const _oHeight = 0.732 * _fontSize;
  static const _oStroke = 0.158 * _fontSize;
  static const _capHeight = 0.706 * _fontSize;

  /// The ring as the power button: this many times the O.
  static const _big = 2.3;

  // CSS's named curves and the page's own.
  static const _ease = Cubic(0.25, 0.1, 0.25, 1);
  static const _easeIn = Cubic(0.42, 0, 1, 1);
  static const _easeOut = Cubic(0, 0, 0.58, 1);
  static const _draw = Cubic(0.6, 0, 0.2, 1);
  static const _close = Cubic(0.5, 0, 0.2, 1);
  static const _press = Cubic(0.3, 0, 0.2, 1);
  static const _travel = Cubic(0.65, 0, 0.2, 1);
  static const _bar = Cubic(0.3, 0.8, 0.2, 1);
  static const _flash = Cubic(0.2, 0.8, 0.2, 1);
  static const _ripple = Cubic(0.1, 0.6, 0.3, 1);
  static const _settle = Cubic(0.2, 0.6, 0.2, 1);
  static const _letter = Cubic(0.16, 1, 0.3, 1);
  static const _sweep = Cubic(0.3, 0.7, 0.2, 1);

  static const _subGrey = Color(0xFF8D96AA);
  static const _subLight = Color(0xFFC9D2E6);

  /// How far through a step that starts at [start] and lasts [length], 0 to 1.
  static double _phase(double t, double start, double length) =>
      ((t - start) / length).clamp(0.0, 1.0);

  /// A value keyed at [stops] (fractions of the step) taking [values], eased
  /// between each pair of keys, as CSS eases each stretch of its keyframes.
  static double _keyed(
    double p,
    List<double> stops,
    List<double> values,
    Curve curve,
  ) {
    if (p <= stops.first) return values.first;
    for (var i = 1; i < stops.length; i++) {
      if (p <= stops[i]) {
        final local = (p - stops[i - 1]) / (stops[i] - stops[i - 1]);
        return ui.lerpDouble(values[i - 1], values[i], curve.transform(local))!;
      }
    }
    return values.last;
  }

  static TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  static TextStyle _bold(Color color, {List<Shadow>? shadows}) => TextStyle(
    fontFamily: KosBrand.fontFamily,
    fontWeight: FontWeight.w700,
    fontSize: _fontSize,
    height: 1,
    color: color,
    shadows: shadows,
  );

  // The wordmark's measures, the same on every frame.
  static _Wordmark? _wordmarkCache;
  static _Wordmark get _wordmark => _wordmarkCache ??= _Wordmark.measure();

  @visibleForTesting
  static void resetForTesting() => _wordmarkCache = null;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final t = seconds.value;
    final scale = math.min(
      size.width / stage.width,
      size.height / stage.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - stage.width * scale) / 2,
      (size.height - stage.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.clipRect(Offset.zero & stage);

    _glow(canvas, t);
    _rippleRing(canvas, _phase(t, 1.55, 1.5), KosBrand.cyan, t >= 1.55);
    _rippleRing(canvas, _phase(t, 1.73, 1.6), KosBrand.violet, t >= 1.73);
    _rippleRing(canvas, _phase(t, 1.91, 1.7), KosBrand.pink, t >= 1.91);
    _beam(canvas, t);
    _flashStreak(canvas, t);
    _sweepStreak(canvas, t);

    // The wordmark settles from a touch large, about the middle of its O.
    final settle = 1.06 - 0.06 * _settle.transform(_phase(t, 1.95, 4.6));
    canvas.save();
    canvas.translate(_cx, _cy);
    canvas.scale(settle);
    canvas.translate(-_cx, -_cy);
    _letters(canvas, t);
    _ring(canvas, t);
    canvas.restore();

    _subtitle(canvas, t);

    if (fades?.value ?? true) {
      final fade = _easeIn.transform(_phase(t, 6.4, 0.8));
      if (fade > 0) {
        canvas.drawRect(
          Offset.zero & stage,
          Paint()..color = Colors.black.withValues(alpha: fade),
        );
      }
    }
    canvas.restore();
  }

  void _glow(Canvas canvas, double t) {
    if (t < 1.5 || t >= 3.2) return;
    final p = _phase(t, 1.5, 1.7);
    final opacity = _keyed(p, const [0, 0.18, 1], const [0, 1, 0], _easeOut);
    if (opacity <= 0) return;
    final radius = 1000 * (0.5 + 0.8 * _easeOut.transform(p));
    const center = Offset(_cx, _cy);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            const Color(0xFF82B4FF).withValues(alpha: 0.38 * opacity),
            const Color(0xFF6E78FF).withValues(alpha: 0.13 * opacity),
            const Color(0x006E78FF),
          ],
          const [0, 0.28, 0.62],
        ),
    );
  }

  /// A ring that opens out from the button and fades. Its light is three
  /// strokes, a sharp one and two wide faint ones, rather than a blur.
  void _rippleRing(Canvas canvas, double p, Color color, bool started) {
    if (!started || p >= 1) return;
    final e = _ripple.transform(p);
    final grow = 1 + 2.4 * e;
    final radius = _oHeight * _big * 1.06 / 2 * grow;
    final opacity = 0.9 * (1 - e);
    const center = Offset(_cx, _cy);
    void stroke(double width, double alpha) => canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * grow
        ..color = color.withValues(alpha: alpha * opacity),
    );
    stroke(56, 0.035);
    stroke(24, 0.1);
    stroke(4, 1);
  }

  void _beam(Canvas canvas, double t) {
    if (t < 1.5 || t >= 2.2) return;
    final p = _phase(t, 1.5, 0.7);
    final tall = _keyed(p, const [0, 0.35, 1], const [0, 1, 1], _flash);
    final wide = _keyed(p, const [0, 0.35, 1], const [1, 1, 0.2], _flash);
    final opacity = _keyed(p, const [0, 0.35, 1], const [1, 1, 0], _flash);
    if (tall <= 0 || opacity <= 0) return;
    void bar(double width, double alpha) {
      final rect = Rect.fromCenter(
        center: const Offset(_cx, _cy),
        width: width * wide,
        height: 2600 * tall,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            rect.bottomCenter,
            [
              const Color(0x004FD8FF),
              KosBrand.cyan.withValues(alpha: alpha * opacity),
              Colors.white.withValues(alpha: alpha * opacity),
              KosBrand.violet.withValues(alpha: alpha * opacity),
              const Color(0x008F6BFF),
            ],
            const [0, 0.3, 0.5, 0.7, 1],
          ),
      );
    }

    bar(96, 0.1);
    bar(40, 0.22);
    bar(8, 1);
  }

  /// The flat streak of light across the screen on the press.
  void _flashStreak(Canvas canvas, double t) {
    if (t < 1.56 || t >= 2.66) return;
    final p = _phase(t, 1.56, 1.1);
    final wide = _keyed(p, const [0, 0.3, 1], const [0, 1, 1.05], _flash);
    final tall = _keyed(p, const [0, 0.3, 1], const [1, 1, 0.4], _flash);
    final opacity = _keyed(p, const [0, 0.3, 1], const [1, 1, 0], _flash);
    if (wide <= 0 || opacity <= 0) return;
    final rect = Rect.fromCenter(
      center: const Offset(_cx, _cy),
      width: 3800 * wide,
      height: 6 * tall,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          [
            const Color(0x004FD8FF),
            KosBrand.cyan.withValues(alpha: 0.8 * opacity),
            Colors.white.withValues(alpha: opacity),
            KosBrand.violet.withValues(alpha: 0.8 * opacity),
            const Color(0x008F6BFF),
          ],
          const [0, 0.4, 0.5, 0.6, 1],
        ),
    );
  }

  /// The glint that runs across the letters as they land.
  void _sweepStreak(Canvas canvas, double t) {
    if (t < 2.7 || t >= 4.0) return;
    final p = _phase(t, 2.7, 1.3);
    final opacity = _keyed(p, const [0, 0.25, 1], const [0, 0.9, 0], _sweep);
    if (opacity <= 0) return;
    final x = -1300 + 2600 * _sweep.transform(p);
    final rect = Rect.fromCenter(
      center: Offset(_cx + x, _cy),
      width: 3800,
      height: 6,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          [
            const Color(0x004FD8FF),
            const Color(0x004FD8FF),
            KosBrand.cyan.withValues(alpha: 0.7 * opacity),
            Colors.white.withValues(alpha: opacity),
            KosBrand.pink.withValues(alpha: 0.7 * opacity),
            const Color(0x00FF5CCF),
            const Color(0x00FF5CCF),
          ],
          const [0, 0.3, 0.47, 0.5, 0.53, 0.7, 1],
        ),
    );
  }

  void _letters(Canvas canvas, double t) {
    final mark = _wordmark;
    _slideLetter(
      canvas,
      t,
      2.5,
      1,
      150,
      'k',
      mark.kX,
      mark,
      const Color(0xFF78D2FF),
    );
    _slideLetter(
      canvas,
      t,
      2.56,
      1,
      -150,
      'S',
      mark.sX,
      mark,
      const Color(0xFF968CFF),
    );
    _tv(canvas, t, mark);
  }

  /// One letter sliding in from [from] stage pixels away: clear by 45 % of
  /// its entrance, lit up by a glow that then dies down.
  void _slideLetter(
    Canvas canvas,
    double t,
    double start,
    double length,
    double from,
    String letter,
    double x,
    _Wordmark mark,
    Color light,
  ) {
    if (t < start) return;
    final p = _phase(t, start, length);
    final opacity = _keyed(p, const [0, 0.45], const [0, 1], _letter);
    final glow = _keyed(p, const [0, 0.45, 1], const [0, 0.7, 0], _letter);
    final shift = from * (1 - _letter.transform(p));
    final painter = p >= 1
        ? (letter == 'k' ? mark.k : mark.s)
        : _text(
            letter,
            _bold(
              KosBrand.ink.withValues(alpha: opacity),
              // The same blur every frame, so only its strength changes.
              shadows: glow > 0.01
                  ? [
                      Shadow(
                        color: light.withValues(alpha: glow),
                        blurRadius: 46,
                      ),
                    ]
                  : null,
            ),
          );
    painter.paint(canvas, Offset(x + shift, mark.top));
    if (p < 1) painter.dispose();
  }

  void _tv(Canvas canvas, double t, _Wordmark mark) {
    const start = 2.74, length = 1.2;
    if (t < start) return;
    final p = _phase(t, start, length);
    final opacity = _keyed(p, const [0, 0.45], const [0, 1], _letter);
    final glow = _keyed(p, const [0, 0.45, 1], const [0, 0.7, 0], _letter);
    final shift = -150 * (1 - _letter.transform(p));
    final origin = Offset(mark.tvX + shift, mark.top);
    final box = origin & mark.tv.size;
    // The page's 100° gradient across the two letters.
    final lean = box.width * 0.1;
    final style = _Wordmark.tvStyle(
      Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..shader = ui.Gradient.linear(
          box.centerLeft.translate(0, -lean),
          box.centerRight.translate(0, lean),
          KosBrand.gradientColors,
          KosBrand.gradientStops,
        ),
      shadows: glow > 0.01 && p < 1
          ? [
              Shadow(
                color: const Color(0xFF968CFF).withValues(alpha: glow),
                blurRadius: 46,
              ),
            ]
          : null,
    );
    final painter = _text('TV', style);
    painter.paint(canvas, origin);
    painter.dispose();
  }

  void _ring(Canvas canvas, double t) {
    if (t < 0.3) return;
    final mark = _wordmark;
    final appear = _phase(t, 0.3, 0.15);

    // In the middle of the screen, big, then off to its place as the O.
    final travel = _travel.transform(_phase(t, 1.95, 1.05));
    var size = ui.lerpDouble(_big, 1, travel)!;
    if (t >= 1.5 && t < 2.0) {
      // The press: a quick dip and back.
      size *= _keyed(
        _phase(t, 1.5, 0.5),
        const [0, 0.3, 1],
        const [1, 0.9, 1],
        _press,
      );
    }
    final center = Offset(ui.lerpDouble(_cx, mark.oX, travel)!, _cy);

    // Thin while it is the button, as thick as the letters once in place.
    final thick = _travel.transform(_phase(t, 1.95, 1.05));
    final stroke = ui.lerpDouble(_oStroke * 0.24, _oStroke, thick)! * size;
    final radius = (_oHeight - _oStroke) / 2 * size;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = KosBrand.ink.withValues(alpha: appear);

    // Two halves drawn up from the bottom, leaving a gap at the top for the
    // bar, closed on the press.
    final double drawn;
    if (t < 1.5) {
      drawn = 0.87 * _draw.transform(_phase(t, 0.35, 0.95));
    } else {
      drawn = 0.87 + 0.13 * _close.transform(_phase(t, 1.5, 0.4));
    }
    if (drawn >= 1) {
      canvas.drawCircle(center, radius, ink);
    } else if (drawn > 0) {
      canvas.drawArc(rect, math.pi / 2, drawn * math.pi, false, ink);
      canvas.drawArc(rect, math.pi / 2, -drawn * math.pi, false, ink);
    }

    // The bar of the power symbol: drops in, then draws back on the press.
    if (t >= 1.0 && t < 1.8) {
      final unit = _oHeight / 100 * size;
      final r = 50 - _oStroke / _oHeight * 50;
      final top = center.translate(0, -(r + 7) * unit);
      final bottom = center.translate(0, -r * 0.1 * unit);
      final double length, opacity;
      if (t < 1.5) {
        length = _bar.transform(_phase(t, 1.0, 0.4));
        opacity = 1;
      } else {
        final out = _easeIn.transform(_phase(t, 1.5, 0.3));
        length = 1 - out;
        opacity = 1 - out;
      }
      if (length > 0 && opacity > 0) {
        canvas.drawLine(
          top,
          Offset.lerp(top, bottom, length)!,
          Paint()
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..color = KosBrand.ink.withValues(alpha: opacity),
        );
      }
    }

    // The comet: a tail of the three colours running round the ring.
    if (t >= 3.0) {
      final opacity = _ease.transform(_phase(t, 3.0, 0.7));
      final turn = ((t - 3.0) / 2.6) % 1;
      final shader = ui.Gradient.sweep(
        center,
        [
          const Color(0x004FD8FF),
          const Color(0x004FD8FF),
          KosBrand.cyan,
          KosBrand.violet,
          KosBrand.pink,
          KosBrand.ink,
        ],
        const [0, 0.6, 0.82, 0.91, 0.95, 1],
        TileMode.clamp,
        0,
        math.pi * 2,
        (Matrix4.translationValues(center.dx, center.dy, 0)
              ..rotateZ(-math.pi / 2 + turn * 2 * math.pi)
              ..translateByDouble(-center.dx, -center.dy, 0, 1))
            .storage,
      );
      Paint tail(double width, double alpha) => Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = shader
        ..color = Colors.white.withValues(alpha: alpha * opacity);
      canvas.drawCircle(
        center,
        radius,
        tail(stroke * 1.9, 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
      canvas.drawCircle(center, radius, tail(stroke, 1));
    }
  }

  void _subtitle(Canvas canvas, double t) {
    if (t < 3.3) return;
    final p = _letter.transform(_phase(t, 3.3, 1.4));
    const size = 64.0;
    final spacing = size * (1.2 - 0.6 * p);
    TextStyle style(Color color) => TextStyle(
      fontFamily: KosBrand.fontFamily,
      fontWeight: FontWeight.w300,
      fontSize: size,
      height: 1.25,
      letterSpacing: spacing,
      color: color.withValues(alpha: p),
    );
    final painter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(text: 'kiko', style: style(_subLight)),
          TextSpan(text: '.me', style: style(_subGrey)),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(_cx - painter.width / 2, _cy + _oHeight / 2 + 175),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(KosIntroPainter old) =>
      old.seconds != seconds || old.fades != fades;
}

/// Where the letters of "kOS TV" stand on the stage, the O's middle on the
/// stage's.
class _Wordmark {
  _Wordmark({
    required this.k,
    required this.s,
    required this.tv,
    required this.kX,
    required this.oX,
    required this.sX,
    required this.tvX,
    required this.top,
  });

  factory _Wordmark.measure() {
    final k = KosIntroPainter._text('k', KosIntroPainter._bold(KosBrand.ink));
    final o = KosIntroPainter._text('O', KosIntroPainter._bold(KosBrand.ink));
    final s = KosIntroPainter._text('S', KosIntroPainter._bold(KosBrand.ink));
    final tv = KosIntroPainter._text('TV', tvStyle(Paint()));
    const gap = 0.17 * KosIntroPainter._fontSize;
    final width = k.width + o.width + s.width + gap + tv.width;
    final left = KosIntroPainter._cx - width / 2;
    final baseline = k.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final mark = _Wordmark(
      k: k,
      s: s,
      tv: tv,
      kX: left,
      oX: left + k.width + o.width / 2 + 2,
      sX: left + k.width + o.width,
      tvX: left + k.width + o.width + s.width + gap,
      // The O's middle, half the cap height above the baseline, on the
      // stage's.
      top: KosIntroPainter._cy + KosIntroPainter._capHeight / 2 - baseline,
    );
    o.dispose();
    return mark;
  }

  static TextStyle tvStyle(Paint foreground, {List<Shadow>? shadows}) =>
      TextStyle(
        fontFamily: KosBrand.fontFamily,
        fontWeight: FontWeight.w200,
        fontSize: KosIntroPainter._fontSize,
        height: 1,
        letterSpacing: 0.01 * KosIntroPainter._fontSize,
        foreground: foreground,
        shadows: shadows,
      );

  final TextPainter k;
  final TextPainter s;
  final TextPainter tv;
  final double kX;

  /// The middle of the O, where the ring ends up.
  final double oX;
  final double sX;
  final double tvX;
  final double top;
}
