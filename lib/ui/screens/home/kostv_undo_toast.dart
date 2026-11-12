import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../util/focus/dpad_keys.dart';

/// Kos TV: the notice after turning a title down, with a few seconds to take
/// it back, as an email app does after deleting one: what happened, a ring
/// counting the seconds left and an «Undo» button.
///
/// With a remote the button takes the focus, so pressing OK straight away
/// takes it back; any other key leaves it and goes on browsing, the notice
/// staying until its time is up. With touch or a mouse the button is tapped.
class KostvUndoToast extends StatefulWidget {
  const KostvUndoToast({
    super.key,
    required this.message,
    required this.undoLabel,
    required this.duration,
    required this.onUndo,
    required this.onDone,
    this.onLeave,
    this.takeFocus = false,
  });

  final String message;
  final String undoLabel;
  final Duration duration;

  /// The person took it back.
  final VoidCallback onUndo;

  /// The time is up, or it was taken back: the notice can go.
  final VoidCallback onDone;

  /// The person pressed another key while the button had the focus.
  final VoidCallback? onLeave;

  /// Whether the button takes the focus when it shows (a remote or keys).
  final bool takeFocus;

  @override
  State<KostvUndoToast> createState() => _KostvUndoToastState();
}

class _KostvUndoToastState extends State<KostvUndoToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();
  final _button = FocusNode(debugLabel: 'kostvUndo');
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _clock.addStatusListener((status) {
      if (status == AnimationStatus.completed) _close();
    });
    if (widget.takeFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _button.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _button.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    // Time up with the button still focused: the focus goes back to the row
    // rather than wherever the framework drops it.
    if (_button.hasFocus) {
      _button.unfocus();
      widget.onLeave?.call();
    }
    widget.onDone();
  }

  void _undo() {
    if (_closing) return;
    _clock.stop();
    _closing = true;
    _button.unfocus();
    widget.onUndo();
    widget.onDone();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey.isSelectKey) {
      _undo();
      return KeyEventResult.handled;
    }
    // Anything else: on with browsing, the notice staying until its time.
    _button.unfocus();
    widget.onLeave?.call();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = AppColorScheme.onSurface;
    final seconds = widget.duration.inSeconds;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2430),
          borderRadius: AppRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The seconds left, in a ring that empties.
            AnimatedBuilder(
              animation: _clock,
              builder: (context, _) {
                final left = (seconds * (1 - _clock.value)).ceil().clamp(
                  0,
                  seconds,
                );
                return SizedBox.square(
                  dimension: 30,
                  child: CustomPaint(
                    painter: _RingPainter(
                      left: 1 - _clock.value,
                      color: AppColorScheme.accent,
                    ),
                    child: Center(
                      child: Text(
                        '$left',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                widget.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: ink),
              ),
            ),
            const SizedBox(width: 12),
            Focus(
              focusNode: _button,
              onKeyEvent: _onKey,
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      color: focused
                          ? AppColorScheme.accent
                          : AppColorScheme.accent.withValues(alpha: 0.16),
                      borderRadius: AppRadius.circular(999),
                      border: Border.all(
                        color: focused ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: AppRadius.circular(999),
                      canRequestFocus: false,
                      onTap: _undo,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.undo_rounded,
                              size: 18,
                              color: focused ? Colors.white : ink,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.undoLabel,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: focused ? Colors.white : ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.left, required this.color});

  /// The part of the time left, 1 to 0.
  final double left;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.12),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * left,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.left != left || old.color != color;
}

/// Shows a [KostvUndoToast] low in the middle of the screen, over everything,
/// until its time is up or it is taken back.
void showKostvUndoToast(
  BuildContext context, {
  required String message,
  required String undoLabel,
  required Duration duration,
  required VoidCallback onUndo,
  VoidCallback? onLeave,
  bool takeFocus = false,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 32,
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - t)),
              child: child,
            ),
          ),
          child: KostvUndoToast(
            message: message,
            undoLabel: undoLabel,
            duration: duration,
            takeFocus: takeFocus,
            onUndo: onUndo,
            onLeave: onLeave,
            onDone: () => scheduleMicrotask(remove),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}
