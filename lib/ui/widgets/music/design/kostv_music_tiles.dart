import 'package:flutter/material.dart';

import '../../../screens/music/kostv_music_widgets.dart'
    show KostvMusicCover, KostvMusicPressable;
import 'kostv_focus_frame.dart';
import 'kostv_music_tokens.dart';
import 'kostv_play_button.dart';

/// Kos TV: a quick access of «Sigue escuchando»: the cover at the start,
/// the name and a line under it («Álbum · Los Faroleros»), on a soft
/// glass. With the remote's focus, a white frame and a little bigger.
class KostvMusicQuickTile extends StatelessWidget {
  const KostvMusicQuickTile({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.cover,
    this.art,
    this.width,
    this.focusNode,
    this.autofocus = false,
    this.onKey,
    this.onLongPress,
  });

  final String title;
  final String? subtitle;
  final String? cover;

  /// Drawn instead of [cover] (the favourites' heart, a mix's art), square.
  final Widget? art;

  /// Free (to fill a grid's cell) by default.
  final double? width;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;
  final KeyEventResult Function(KeyEvent event)? onKey;

  @override
  Widget build(BuildContext context) {
    final height = KostvMusicTokens.tileHeight;
    return SizedBox(
      width: width,
      height: height,
      child: KostvMusicPressable(
        focusNode: focusNode,
        autofocus: autofocus,
        onTap: onTap,
        onLongPress: onLongPress,
        onKey: onKey,
        builder: (context, lit) => KostvFocusFrame(
          lit: lit,
          gap: 0,
          scale: 1.05,
          radius: KostvMusicTokens.radiusTile,
          child: AnimatedContainer(
            duration: KostvMusicTokens.focusDuration,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: KostvMusicTokens.glass(lit ? 0.16 : 0.07),
              borderRadius: BorderRadius.circular(KostvMusicTokens.radiusTile),
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: height,
                  child:
                      art ??
                      KostvMusicCover(url: cover, size: height, radius: 0),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KostvMusicType.body(15),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KostvMusicType.muted(12.5),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kos TV: a shelf's heading: its title in Outfit, the line under it, and
/// at the end of the title the play button ([onPlay], a chart's) and, at
/// the right, «Ver todo» ([more]).
class KostvShelfHeader extends StatelessWidget {
  const KostvShelfHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onPlay,
    this.playTooltip,
    this.playFocusNode,
    this.playOnKey,
    this.actions = const [],
    this.more,
    this.padding = EdgeInsets.zero,
    this.titleSize,
  });

  final String title;
  final String? subtitle;

  /// Plays the shelf: [KostvPlayButton] next to the title.
  final VoidCallback? onPlay;
  final String? playTooltip;
  final FocusNode? playFocusNode;
  final KeyEventResult Function(KeyEvent event)? playOnKey;

  /// After the play button (shuffle).
  final List<Widget> actions;

  /// At the right («Ver todo»).
  final Widget? more;
  final EdgeInsets padding;

  /// [KostvMusicTokens.shelfTitle] by default.
  final double? titleSize;

  @override
  Widget build(BuildContext context) {
    final onPlay = this.onPlay;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KostvMusicType.title(
                          titleSize ?? KostvMusicTokens.shelfTitle,
                        ),
                      ),
                    ),
                    if (onPlay != null) ...[
                      const SizedBox(width: 14),
                      KostvPlayButton(
                        size: KostvPlaySize.row,
                        diameter: 36,
                        tooltip: playTooltip,
                        focusNode: playFocusNode,
                        onKey: playOnKey,
                        onTap: onPlay,
                      ),
                    ],
                    for (final action in actions) ...[
                      const SizedBox(width: 10),
                      action,
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KostvMusicType.muted(14),
                  ),
                ],
              ],
            ),
          ),
          ?more,
        ],
      ),
    );
  }
}
