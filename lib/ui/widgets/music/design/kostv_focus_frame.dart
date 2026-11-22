import 'package:flutter/material.dart';

import 'kostv_music_tokens.dart';

/// Kos TV: how what has the remote's focus (or the mouse over it) shows in
/// Music: a white 3 px frame, 3 px away from it, a shadow under it and a
/// little bigger (7 %). The same on cards, artists' circles and tiles.
class KostvFocusFrame extends StatelessWidget {
  const KostvFocusFrame({
    super.key,
    required this.lit,
    required this.child,
    this.radius = KostvMusicTokens.radiusCover,
    this.circle = false,
    this.scale = KostvMusicTokens.focusScale,
    this.gap = KostvMusicTokens.focusGap,
    this.alignment = Alignment.center,
  });

  final bool lit;
  final Widget child;

  /// Of [child]'s corners (the frame follows them, [gap] further out).
  final double radius;
  final bool circle;
  final double scale;

  /// Between [child] and the frame; 0 for a frame on its edge (the tiles).
  final double gap;

  /// Where it grows from.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    const frame = KostvMusicTokens.focusFrame;
    final out = gap + frame;
    return AnimatedScale(
      scale: lit ? scale : 1,
      alignment: alignment,
      duration: KostvMusicTokens.focusDuration,
      curve: KostvMusicTokens.focusCurve,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The shadow, under the child, only while lit.
          Positioned.fill(
            child: AnimatedContainer(
              duration: KostvMusicTokens.focusDuration,
              decoration: BoxDecoration(
                shape: circle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: circle ? null : BorderRadius.circular(radius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: lit ? 0.7 : 0),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
            ),
          ),
          child,
          Positioned(
            left: -out,
            top: -out,
            right: -out,
            bottom: -out,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: lit ? 1 : 0,
                duration: KostvMusicTokens.focusDuration,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: circle ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: circle
                        ? null
                        : BorderRadius.circular(radius + out),
                    border: Border.all(
                      color: KostvMusicTokens.ink,
                      width: frame,
                    ),
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
