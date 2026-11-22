import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../music/design/kostv_music_tokens.dart';
import '../user_avatar_image.dart';

/// Kos TV: the brand's pink, for counts on the menu.
const kostvMenuBadgeColor = KostvMusicTokens.pink;

/// Kos TV: the person's avatar in the menu, which is «Tú»: their picture (or
/// their initial on the warm gradient), the number of news behind it in a
/// pink badge and, with [ring], the kOS gradient round it, turning while
/// something asked for is coming down ([spinning]).
class KostvNavAvatar extends StatefulWidget {
  const KostvNavAvatar({
    super.key,
    required this.size,
    required this.imageUrl,
    required this.name,
    this.badge = 0,
    this.ring = false,
    this.spinning = false,
    this.dot = false,
    this.focused = false,
  });

  final double size;
  final String? imageUrl;
  final String name;

  /// News behind «Tú», drawn as a count. Zero draws nothing.
  final int badge;

  /// A small pink dot instead of a count (the phone's bar).
  final bool dot;
  final bool ring;
  final bool spinning;

  /// The remote's focus: a white frame round it and a little bigger.
  final bool focused;

  @override
  State<KostvNavAvatar> createState() => _KostvNavAvatarState();
}

class _KostvNavAvatarState extends State<KostvNavAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _turn;

  @override
  void initState() {
    super.initState();
    _syncTurn();
  }

  @override
  void didUpdateWidget(KostvNavAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTurn();
  }

  // Only while something comes down: a still ring costs nothing.
  void _syncTurn() {
    final spin = widget.ring && widget.spinning;
    if (spin) {
      _turn ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      );
      if (!_turn!.isAnimating) _turn!.repeat();
    } else {
      _turn?.stop();
    }
  }

  @override
  void dispose() {
    _turn?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final initial = widget.name.isNotEmpty
        ? widget.name.characters.first.toUpperCase()
        : '?';
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 0.95,
          colors: [Color(0xFFFFC9A8), Color(0xFFE0607E)],
          stops: [0, 0.75],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontFamily: KostvMusicType.titleFamily,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.45,
            height: 1,
            color: KostvMusicTokens.background,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
    Widget face = SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: UserAvatarImage(
          url: widget.imageUrl,
          size: size,
          fallback: fallback,
        ),
      ),
    );
    if (widget.focused) {
      face = DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: KostvMusicTokens.background, spreadRadius: 3),
            BoxShadow(color: KostvMusicTokens.ink, spreadRadius: 6),
          ],
        ),
        child: face,
      );
    }
    final ringPad = widget.ring ? size * 0.12 : 0.0;
    Widget ring = const SizedBox.shrink();
    if (widget.ring) {
      final painted = CustomPaint(
        size: Size.square(size + ringPad * 2),
        painter: const _RingPainter(),
      );
      final turn = _turn;
      ring = turn == null
          ? painted
          : RotationTransition(turns: turn, child: painted);
      ring = RepaintBoundary(child: ring);
    }
    final badgeSize = math.max(16.0, size * 0.45);
    return AnimatedScale(
      scale: widget.focused ? 1.08 : 1,
      duration: KostvMusicTokens.focusDuration,
      curve: KostvMusicTokens.focusCurve,
      child: SizedBox(
        width: size + ringPad * 2,
        height: size + ringPad * 2,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (widget.ring) Positioned.fill(child: ring),
            face,
            if (widget.badge > 0)
              Positioned(
                top: -4 + ringPad * 0.3,
                right: -6 + ringPad * 0.3,
                child: KostvMenuCount(count: widget.badge, size: badgeSize),
              )
            else if (widget.dot)
              Positioned(
                top: ringPad - 1,
                right: ringPad - 3,
                child: Container(
                  width: math.max(8, size * 0.36),
                  height: math.max(8, size * 0.36),
                  decoration: BoxDecoration(
                    color: kostvMenuBadgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.45),
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The kOS gradient round the avatar, fading out on its last quarter.
class _RingPainter extends CustomPainter {
  const _RingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.055;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: GradientRotation(-math.pi / 2 + 0.7),
        colors: [
          KostvMusicTokens.cyan,
          KostvMusicTokens.violet,
          KostvMusicTokens.pink,
          Color(0x00FF5CCF),
        ],
        stops: [0, 0.35, 0.6, 0.75],
      ).createShader(rect);
    canvas.drawCircle(rect.center, (size.width - stroke) / 2, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => false;
}

/// Kos TV: a count in the menu's pink.
class KostvMenuCount extends StatelessWidget {
  const KostvMenuCount({
    super.key,
    required this.count,
    this.size = 20,
    this.outlined = true,
  });

  final int count;
  final double size;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: EdgeInsets.symmetric(horizontal: size * 0.25),
      decoration: BoxDecoration(
        color: kostvMenuBadgeColor,
        borderRadius: BorderRadius.circular(size / 2),
        border: outlined
            ? Border.all(color: KostvMusicTokens.background, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: KostvMusicTokens.background,
          fontSize: size * 0.56,
          fontWeight: FontWeight.w700,
          height: 1,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
