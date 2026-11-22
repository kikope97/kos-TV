import 'package:flutter/material.dart';

import 'kostv_music_tokens.dart';

/// Kos TV: the kinds of [KostvMusicPill].
enum KostvPillKind {
  /// A secondary button: see-through with a thin white edge («Pedir el
  /// álbum»).
  ghost,

  /// A state, not a button: grey and quiet («Pedido · te avisamos», «De
  /// camino»).
  quiet,
}

/// Kos TV: the sizes of [KostvMusicPill]: 32, 40 and 52 high.
enum KostvPillSize { s, m, l }

/// Kos TV: Music's secondary pill. With the focus ([lit]) it turns white
/// with black ink, as every button of the app does.
class KostvMusicPill extends StatelessWidget {
  const KostvMusicPill({
    super.key,
    required this.label,
    this.icon,
    this.kind = KostvPillKind.ghost,
    this.size = KostvPillSize.m,
    this.lit = false,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final KostvPillKind kind;
  final KostvPillSize size;
  final bool lit;

  /// A small wheel instead of [icon] (it is being asked).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final (height, pad, font, iconSize) = switch (size) {
      KostvPillSize.s => (32.0, 14.0, 13.0, 16.0),
      KostvPillSize.m => (40.0, 18.0, 15.0, 18.0),
      KostvPillSize.l => (52.0, 24.0, 18.0, 22.0),
    };
    final ink = lit
        ? KostvMusicTokens.background
        : (kind == KostvPillKind.quiet
              ? KostvMusicTokens.muted
              : KostvMusicTokens.ink);
    return AnimatedScale(
      scale: lit ? 1.06 : 1,
      duration: KostvMusicTokens.focusDuration,
      curve: KostvMusicTokens.focusCurve,
      child: AnimatedContainer(
        duration: KostvMusicTokens.focusDuration,
        constraints: BoxConstraints(minHeight: height),
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 4),
        decoration: BoxDecoration(
          color: lit
              ? KostvMusicTokens.ink
              : KostvMusicTokens.glass(
                  kind == KostvPillKind.quiet ? 0.06 : 0.08,
                ),
          borderRadius: BorderRadius.circular(999),
          border: kind == KostvPillKind.ghost && !lit
              ? Border.all(color: Colors.white.withValues(alpha: 0.22))
              : null,
          boxShadow: lit
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox.square(
                dimension: iconSize - 2,
                child: CircularProgressIndicator(strokeWidth: 2, color: ink),
              )
            else if (icon != null)
              Icon(icon, size: iconSize, color: ink),
            if (busy || icon != null) const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: font,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kos TV: a small round button in glass (shuffle, ♥, ⋯ next to the play
/// button); white with the focus.
class KostvRoundIcon extends StatelessWidget {
  const KostvRoundIcon({
    super.key,
    required this.icon,
    this.diameter = 44,
    this.lit = false,
    this.color = KostvMusicTokens.ink,
  });

  final IconData icon;
  final double diameter;
  final bool lit;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: lit ? 1.1 : 1,
    duration: KostvMusicTokens.focusDuration,
    curve: KostvMusicTokens.focusCurve,
    child: AnimatedContainer(
      duration: KostvMusicTokens.focusDuration,
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit ? KostvMusicTokens.ink : KostvMusicTokens.glass(0.10),
        boxShadow: lit
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        size: diameter * 0.46,
        color: lit ? KostvMusicTokens.background : color,
      ),
    ),
  );
}
