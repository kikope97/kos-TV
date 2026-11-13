import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';

/// Kos TV: the music menus (a song's, the player's «···»): a dark card with
/// a title and a list of choices, for the remote, the mouse and touch.

class KostvMenuEntry<T> {
  const KostvMenuEntry(this.value, this.icon, this.label);

  final T value;
  final IconData icon;
  final String label;
}

/// Shows the menu and gives back the value of what was picked, or null.
Future<T?> showKostvMusicMenu<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<KostvMenuEntry<T>> entries,
}) => showDialog<T>(
  context: context,
  barrierColor: Colors.black.withValues(alpha: 0.55),
  builder: (context) =>
      KostvMusicMenu<T>(title: title, subtitle: subtitle, entries: entries),
);

class KostvMusicMenu<T> extends StatelessWidget {
  const KostvMusicMenu({
    super.key,
    required this.title,
    required this.entries,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<KostvMenuEntry<T>> entries;

  @override
  Widget build(BuildContext context) {
    final big = PlatformDetection.isTV;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: big ? 520 : 400,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Material(
          color: const Color(0xFF1C1C1F),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: big ? 18 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: big ? 15 : 13,
                          ),
                        ),
                    ],
                  ),
                ),
                for (var i = 0; i < entries.length; i++)
                  _MenuRow(
                    entry: entries[i],
                    autofocus: i == 0,
                    big: big,
                    onTap: () => Navigator.of(context).pop(entries[i].value),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow<T> extends StatefulWidget {
  const _MenuRow({
    required this.entry,
    required this.autofocus,
    required this.big,
    required this.onTap,
  });

  final KostvMenuEntry<T> entry;
  final bool autofocus;
  final bool big;
  final VoidCallback onTap;

  @override
  State<_MenuRow<T>> createState() => _MenuRowState<T>();
}

class _MenuRowState<T> extends State<_MenuRow<T>> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lit =
        InputModeTracker.showFocusVisuals(context, _focused) || _hovered;
    final big = widget.big;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        final direction = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowUp => TraversalDirection.up,
          LogicalKeyboardKey.arrowDown => TraversalDirection.down,
          _ => null,
        };
        if (direction == null) {
          // Sideways leads nowhere in a list.
          return event.logicalKey.isLeftKey || event.logicalKey.isRightKey
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        node.focusInDirection(direction);
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: big ? 14 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: lit
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  widget.entry.icon,
                  color: Colors.white,
                  size: big ? 26 : 22,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.entry.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: big ? 19 : 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
