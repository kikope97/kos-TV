import 'package:flutter/material.dart';

import '../../../../util/focus/input_mode_tracker.dart';
import '../../../screens/music/kostv_music_widgets.dart'
    show KostvMusicPressable;
import 'kostv_music_tokens.dart';

/// Kos TV: the four sizes of [KostvPlayButton].
enum KostvPlaySize {
  /// «Reproduciendo».
  player(84),

  /// An album's or an artist's page.
  album(64),

  /// On a card with the focus or the mouse over it.
  card(44),

  /// Next to a shelf's title, or in a row.
  row(32);

  const KostvPlaySize(this.diameter);

  final double diameter;
}

/// Kos TV: Music's one play button, the same for everything that plays
/// (at home or not): a circle in the brand's gradient with a black icon.
/// There is no «off» version of it. With [pause], ⏸ instead of ▶.
///
/// With [onTap] it is a stop of its own (remote, mouse, touch): with the
/// remote's focus a white frame and 10 % bigger, a little bigger under the
/// mouse, and smaller while pressed. Without, it is only drawn ([lit]
/// tells it to look focused): a card's, whose card takes the press.
class KostvPlayButton extends StatefulWidget {
  const KostvPlayButton({
    super.key,
    this.size = KostvPlaySize.card,
    this.diameter,
    this.pause = false,
    this.onTap,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    this.onKey,
    this.lit = false,
  });

  final KostvPlaySize size;

  /// Instead of [size]'s, for a place in between (the floating player's).
  final double? diameter;
  final bool pause;
  final VoidCallback? onTap;

  /// What it does, for the mouse's pointer and the screen reader.
  final String? tooltip;
  final FocusNode? focusNode;
  final bool autofocus;
  final KeyEventResult Function(KeyEvent event)? onKey;

  /// Drawn as focused (only without [onTap]).
  final bool lit;

  @override
  State<KostvPlayButton> createState() => _KostvPlayButtonState();
}

class _KostvPlayButtonState extends State<KostvPlayButton> {
  bool _pressed = false;

  double get _diameter => widget.diameter ?? widget.size.diameter;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    Widget button;
    if (onTap == null) {
      button = KostvPlayFace(
        diameter: _diameter,
        pause: widget.pause,
        focused: widget.lit,
      );
    } else {
      button = KostvMusicPressable(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onKey: widget.onKey,
        onTap: onTap,
        builder: (context, lit) => Listener(
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          // The remote's focus (the frame) or only the mouse over it.
          child: Builder(
            builder: (context) {
              final focused = InputModeTracker.showFocusVisuals(
                context,
                Focus.maybeOf(context)?.hasFocus ?? false,
              );
              return KostvPlayFace(
                diameter: _diameter,
                pause: widget.pause,
                focused: focused,
                hovered: lit && !focused,
                pressed: _pressed,
              );
            },
          ),
        ),
      );
    }
    final tooltip = widget.tooltip;
    if (tooltip == null) return button;
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(message: tooltip, child: button),
    );
  }
}

/// Kos TV: how [KostvPlayButton] looks, on its own (for a piece that is
/// pressed as a whole, a card).
class KostvPlayFace extends StatelessWidget {
  const KostvPlayFace({
    super.key,
    required this.diameter,
    this.pause = false,
    this.focused = false,
    this.hovered = false,
    this.pressed = false,
  });

  final double diameter;
  final bool pause;
  final bool focused;
  final bool hovered;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final scale = pressed ? 0.94 : (focused ? 1.1 : (hovered ? 1.05 : 1.0));
    const frame = KostvMusicTokens.focusFrame;
    const gap = KostvMusicTokens.focusGap;
    final glow = KostvMusicTokens.violet.withValues(
      alpha: focused ? 0.7 : (hovered ? 0.5 : 0.35),
    );
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 140),
      curve: KostvMusicTokens.focusCurve,
      child: SizedBox.square(
        dimension: diameter,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KostvMusicTokens.gradient,
                  boxShadow: [
                    BoxShadow(
                      color: glow,
                      blurRadius: focused ? 40 : 22,
                      offset: Offset(0, focused ? 10 : 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Padding(
                    // ▶ looks centred a little to the right of the middle.
                    padding: EdgeInsets.only(left: pause ? 0 : diameter * 0.06),
                    child: Icon(
                      pause ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: diameter * (pause ? 0.5 : 0.56),
                      color: KostvMusicTokens.background,
                    ),
                  ),
                ),
              ),
            ),
            if (focused)
              const Positioned(
                left: -(gap + frame),
                top: -(gap + frame),
                right: -(gap + frame),
                bottom: -(gap + frame),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(
                        BorderSide(color: KostvMusicTokens.ink, width: frame),
                      ),
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
