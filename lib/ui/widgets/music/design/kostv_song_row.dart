import 'package:flutter/material.dart';

import '../../../../util/platform_detection.dart';
import '../../../screens/music/kostv_music_widgets.dart'
    show KostvMusicCover, KostvMusicPressable;
import '../kostv_now_playing.dart';
import '../kostv_now_playing_capsule.dart' show KostvEqualizerBars;
import 'kostv_music_tokens.dart';

/// Kos TV: whether a row's song is the one the player has.
enum KostvSongSound {
  none,

  /// The player has it, paused: the equalizer stands still.
  paused,

  /// It sounds: the equalizer moves.
  playing,
}

/// Kos TV: the time of a song, «3:09», from its [seconds].
String? kostvSongLength(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Kos TV: a song's row in Music, the same wherever songs are listed (an
/// album, a chart, a search, favourites) and whether the song is at home
/// or not: no button of its own. The whole row is pressed (a tap, a click,
/// OK) and, with the remote's focus or the mouse over it, its [number]
/// turns into ▶ (with no number, ▶ goes over the cover) and «⋯» shows for
/// its menu. The song that sounds has the equalizer in its place and its
/// title in the brand's colours.
class KostvSongRow extends StatelessWidget {
  const KostvSongRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.subtitleBuilder,
    this.number,
    this.cover,
    this.coverArt,
    this.showCover,
    this.duration,
    this.explicit = false,
    this.sound,
    this.soundingId,
    this.picked = false,
    this.trailing,
    this.onMenu,
    this.focusNode,
    this.autofocus = false,
    this.onKey,
    this.onRest,
    this.height,
    this.textSize,
    this.coverSize,
  });

  final String title;

  /// The line under it (artist, album).
  final String? subtitle;

  /// Instead of [subtitle], when it is more than a text (names that open
  /// their pages): told the row's [TextStyle].
  final Widget Function(TextStyle style)? subtitleBuilder;

  /// Its place in a list or chart («7», «2·3» for a disc's).
  final String? number;
  final String? cover;

  /// Instead of [cover]'s picture, a cover of its own (a downloaded file's,
  /// the player's queue). Square, [coverSize] across.
  final Widget? coverArt;

  /// Whether there is a cover (with no [cover], its placeholder). By
  /// default, when [cover] or [coverArt] is given.
  final bool? showCover;

  /// «3:09».
  final String? duration;
  final bool explicit;

  /// Whether the player has it, when the list knows ([soundingId] asks the
  /// player instead).
  final KostvSongSound? sound;

  /// The id of the song in the player's queue: the row follows the player
  /// and shows the equalizer while it has it.
  final String? soundingId;

  /// The song the page was opened for: its title stands out.
  final bool picked;

  /// Something before the time: only a request's state, with «Solo la de
  /// casa» (a song that isn't at home then doesn't play).
  final Widget? trailing;

  /// Its menu: OK held down, a long press, a right click or «⋯».
  final VoidCallback? onMenu;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final KeyEventResult Function(KeyEvent event)? onKey;

  /// See [KostvMusicPressable.onRest].
  final ValueChanged<bool>? onRest;

  /// Of the row; free by default.
  final double? height;

  /// Of the title (the rest goes by it); [KostvMusicTokens.rowText] by
  /// default.
  final double? textSize;
  final double? coverSize;

  @override
  Widget build(BuildContext context) {
    final soundingId = this.soundingId;
    Widget row(KostvSongSound sound) => KostvMusicPressable(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onLongPress: onMenu,
      onKey: onKey,
      onRest: onRest,
      builder: (context, lit) => KostvSongRowFace(
        lit: lit,
        sound: sound,
        title: title,
        subtitle: subtitle,
        subtitleBuilder: subtitleBuilder,
        number: number,
        cover: cover,
        coverArt: coverArt,
        showCover: showCover ?? (cover != null || coverArt != null),
        duration: duration,
        explicit: explicit,
        picked: picked,
        trailing: trailing,
        onMenu: onMenu,
        height: height,
        textSize: textSize,
        coverSize: coverSize,
      ),
    );
    if (sound != null || soundingId == null) {
      return row(sound ?? KostvSongSound.none);
    }
    final music = KostvNowPlaying.instance;
    return ListenableBuilder(
      listenable: music,
      builder: (context, _) => row(
        music.item?.id != soundingId
            ? KostvSongSound.none
            : (music.playing ? KostvSongSound.playing : KostvSongSound.paused),
      ),
    );
  }
}

/// Kos TV: how [KostvSongRow] looks, told whether it is [lit].
class KostvSongRowFace extends StatelessWidget {
  const KostvSongRowFace({
    super.key,
    required this.lit,
    required this.title,
    this.sound = KostvSongSound.none,
    this.subtitle,
    this.subtitleBuilder,
    this.number,
    this.cover,
    this.coverArt,
    this.showCover = false,
    this.duration,
    this.explicit = false,
    this.picked = false,
    this.trailing,
    this.onMenu,
    this.height,
    this.textSize,
    this.coverSize,
  });

  final bool lit;
  final KostvSongSound sound;
  final String title;
  final String? subtitle;
  final Widget Function(TextStyle style)? subtitleBuilder;
  final String? number;
  final String? cover;
  final Widget? coverArt;
  final bool showCover;
  final String? duration;
  final bool explicit;
  final bool picked;
  final Widget? trailing;
  final VoidCallback? onMenu;
  final double? height;
  final double? textSize;
  final double? coverSize;

  @override
  Widget build(BuildContext context) {
    final fs = textSize ?? KostvMusicTokens.rowText;
    final sounding = sound != KostvSongSound.none;
    final coverSize = this.coverSize ?? KostvMusicTokens.rowCover;
    final subStyle = KostvMusicType.muted(fs - 2);
    Widget? lead;
    final number = this.number;
    if (number != null) {
      lead = SizedBox(
        width: number.length > 2 ? 34 : 24,
        child: Center(
          child: sounding
              ? _bars(fs + 1)
              : lit
              ? Icon(
                  Icons.play_arrow_rounded,
                  size: fs + 5,
                  color: KostvMusicTokens.ink,
                )
              : Text(
                  number,
                  maxLines: 1,
                  style: KostvMusicType.muted(fs)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
        ),
      );
    }
    Widget? art;
    if (showCover) {
      final overlay = number == null && (sounding || lit);
      art = SizedBox.square(
        dimension: coverSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            coverArt ??
                KostvMusicCover(
                  url: cover,
                  size: coverSize,
                  radius: KostvMusicTokens.radiusSmallCover,
                ),
            if (overlay)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(
                    KostvMusicTokens.radiusSmallCover,
                  ),
                ),
                child: Center(
                  child: sounding && !lit
                      ? _bars(coverSize * 0.4)
                      : Icon(
                          Icons.play_arrow_rounded,
                          size: coverSize * 0.5,
                          color: KostvMusicTokens.ink,
                        ),
                ),
              ),
          ],
        ),
      );
    }
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: KostvMusicType.body(
        fs,
        weight: picked ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    final subtitleBuilder = this.subtitleBuilder;
    final subtitle = this.subtitle;
    final menu = onMenu;
    // «⋯» only where there is a pointer or a remote: on the phone the row
    // is long-pressed.
    final showMenu = lit && menu != null;
    // A wide row (an album's, the web's) grows by a few pixels at most,
    // not 2 % of its width: its number and time would move too much.
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedScale(
        scale: lit ? _rowScale(constraints.maxWidth) : 1,
        duration: KostvMusicTokens.focusDuration,
        curve: KostvMusicTokens.focusCurve,
        child: AnimatedContainer(
          duration: KostvMusicTokens.focusDuration,
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: height == null ? 7 : 0,
          ),
          decoration: BoxDecoration(
            color: lit ? KostvMusicTokens.glass(0.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(KostvMusicTokens.radiusRow),
            border: Border.all(
              color: lit ? KostvMusicTokens.ink : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 12)],
              if (art != null) ...[art, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: sounding
                              ? KostvGradientText(child: titleText)
                              : titleText,
                        ),
                        if (explicit) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.explicit_rounded,
                            size: fs,
                            color: KostvMusicTokens.muted,
                          ),
                        ],
                      ],
                    ),
                    if (subtitleBuilder != null) ...[
                      const SizedBox(height: 3),
                      subtitleBuilder(subStyle),
                    ] else if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subStyle,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
              if (duration != null) ...[
                const SizedBox(width: 12),
                Text(duration!, style: KostvMusicType.muted(fs - 1)),
              ],
              if (showMenu || (menu != null && !PlatformDetection.useMobileUi))
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Visibility(
                    visible: showMenu,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: menu,
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          Icons.more_horiz_rounded,
                          size: fs + 6,
                          color: KostvMusicTokens.ink,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static double _rowScale(double width) => width.isFinite && width > 0
      ? 1 + (16 / width).clamp(0.004, KostvMusicTokens.focusScaleRow - 1)
      : KostvMusicTokens.focusScaleRow;

  Widget _bars(double size) => KostvEqualizerBars(
    playing: sound == KostvSongSound.playing,
    size: size,
    gradient: KostvMusicTokens.gradient,
  );
}
