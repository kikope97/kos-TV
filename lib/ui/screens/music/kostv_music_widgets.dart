import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/stremfin/kostv_stream_song.dart'
    show kostvStreamId;
import '../../../data/services/stremfin/stremfin_models.dart' show StremfinSong;
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/music/design/kostv_music_design.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/navigation_layout.dart';
import 'kostv_music_links.dart';

/// Kos TV: the colour of Music, Apple Music's red-pink.
const kostvMusicColor = Color(0xFFFA2D55);

/// The grey of what goes under a title.
const kostvMusicGrey = Color(0xFF98989F);

/// How a record stands, for the badge on its cover.
/// Kos TV: [failed] is a download that failed (not on its way any more).
enum KostvMusicBadge { none, ask, asked, onItsWay, failed }

/// Sizes that change with the screen.
class KostvMusicSizes {
  KostvMusicSizes._();

  static bool get phone => PlatformDetection.useMobileUi;

  /// An album's cover in a row.
  static double get cover => phone ? 150 : 176;

  /// A column of a chart's songs.
  static double songColumn(BuildContext context) =>
      phone ? MediaQuery.sizeOf(context).width * 0.84 : 420;

  static double get artist => phone ? 120 : 150;
  static double get gap => phone ? 14 : 22;
}

/// Brings [item] up or down the music page, worked out from where it is on
/// screen: asking the page to reveal something inside a sideways row sent
/// it back to the top. With [onlyIfHidden], it moves only when [item] is not
/// fully in sight. [page] is the page's scrollable, when already known.
/// Kos TV: with [preferTop], the page goes back to its top instead when
/// [item] is in sight there (a page's header: its buttons don't take the
/// header and the menu off the top of the screen).
void kostvMusicRevealVertically(
  BuildContext item, [
  ScrollableState? page,
  bool onlyIfHidden = false,
  bool preferTop = false,
]) {
  if (!item.mounted) return;
  var scrollable = page ?? Scrollable.maybeOf(item);
  if (scrollable != null &&
      axisDirectionToAxis(scrollable.axisDirection) == Axis.horizontal) {
    scrollable = Scrollable.maybeOf(scrollable.context);
  }
  if (scrollable == null || !scrollable.mounted) return;
  final box = item.findRenderObject();
  final view = scrollable.context.findRenderObject();
  if (box is! RenderBox || view is! RenderBox) return;
  if (!box.hasSize || !view.hasSize || !box.attached) return;
  final top =
      box.localToGlobal(Offset.zero).dy - view.localToGlobal(Offset.zero).dy;
  if (onlyIfHidden && top >= 0 && top + box.size.height <= view.size.height) {
    return;
  }
  final position = scrollable.position;
  final wanted = (view.size.height - box.size.height) * 0.4;
  final atTop =
      preferTop &&
      position.pixels + top - position.minScrollExtent + box.size.height <=
          view.size.height;
  final target = atTop
      ? position.minScrollExtent
      : (position.pixels + top - wanted).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
  if ((target - position.pixels).abs() < 1) return;
  unawaited(
    position.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    ),
  );
}

/// Kos TV: one stop of the Music page for touch, mouse and remote: Select
/// or a tap runs [onTap]; with the focus it comes into view and [builder]
/// is told so it can light up.
class KostvMusicPressable extends StatefulWidget {
  const KostvMusicPressable({
    super.key,
    required this.builder,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.onLongPress,
    this.onKey,
    this.centerVertically = true,
    this.revealFromTop = false,
    this.onRest,
  });

  /// Kos TV: told true when the remote's focus (shown) or the mouse comes
  /// onto it, and false when both leave: a song rested on a moment is asked
  /// for in advance. Not with touch (a phone's scroll passes by songs).
  final ValueChanged<bool>? onRest;

  /// Kos TV: a stop of a page's header (an album's buttons): with the focus,
  /// the page goes back to its top rather than bringing it to the middle,
  /// so the header and the menu stay in sight. Only when it fits there.
  final bool revealFromTop;

  /// Whether the focus brings its line to the middle of the page. A grid
  /// whose page keeps its own place (Genres) says no: its top row stays
  /// where it is, with the menu and title above it in sight.
  final bool centerVertically;

  final Widget Function(BuildContext context, bool lit) builder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Arrow keys before the default moves (the page's edges).
  final KeyEventResult Function(KeyEvent event)? onKey;

  @override
  State<KostvMusicPressable> createState() => _KostvMusicPressableState();
}

class _KostvMusicPressableState extends State<KostvMusicPressable> {
  bool _focused = false;
  bool _hovered = false;
  Timer? _hold;

  /// Kos TV: what [KostvMusicPressable.onRest] was last told.
  bool _resting = false;

  void _rest() {
    final onRest = widget.onRest;
    if (onRest == null || !mounted) return;
    final now =
        _hovered ||
        (_focused && InputModeTracker.showFocusVisuals(context, true));
    if (now == _resting) return;
    _resting = now;
    onRest(now);
  }

  @override
  void dispose() {
    _hold?.cancel();
    if (_resting) widget.onRest?.call(false);
    super.dispose();
  }

  @override
  void deactivate() {
    _hold?.cancel();
    _hold = null;
    super.deactivate();
  }

  void _onFocus(bool focused) {
    setState(() => _focused = focused);
    _rest();
    if (!focused) {
      // OK went down here and up somewhere else: no menu out of nowhere.
      _hold?.cancel();
      _hold = null;
      return;
    }
    final box = context.findRenderObject();
    if (box == null) return;
    const duration = Duration(milliseconds: 220);
    const curve = Curves.easeOutCubic;
    // Sideways only as far as needed, so a row never jumps; up and down the
    // line comes to the middle of the page.
    var scrollable = Scrollable.maybeOf(context);
    if (scrollable != null &&
        axisDirectionToAxis(scrollable.axisDirection) == Axis.horizontal) {
      final position = scrollable.position;
      unawaited(
        position.ensureVisible(
          box,
          duration: duration,
          curve: curve,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
      unawaited(
        position.ensureVisible(
          box,
          duration: duration,
          curve: curve,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ),
      );
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    if (scrollable != null && widget.centerVertically) {
      final page = scrollable;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          kostvMusicRevealVertically(
            context,
            page,
            false,
            widget.revealFromTop,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lit =
        InputModeTracker.showFocusVisuals(context, _focused) || _hovered;
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _onFocus,
      onKeyEvent: (node, event) {
        final longPress = widget.onLongPress;
        // With a menu, OK held down opens it, and a short press is the tap
        // (on letting go). The menu key opens it at once.
        if (longPress != null && event.logicalKey.isSelectKey) {
          if (event is KeyDownEvent) {
            _hold?.cancel();
            _hold = Timer(const Duration(milliseconds: 550), () {
              _hold = null;
              longPress();
            });
          } else if (event is KeyUpEvent) {
            if (_hold != null) {
              _hold?.cancel();
              _hold = null;
              widget.onTap();
            }
          }
          return KeyEventResult.handled;
        }
        if (longPress != null &&
            event is KeyDownEvent &&
            event.logicalKey.isContextMenuKey) {
          longPress();
          return KeyEventResult.handled;
        }
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        final own = widget.onKey?.call(event);
        if (own == KeyEventResult.handled) return own!;
        // The remote moves to the nearest stop that way, across the rows.
        final direction = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowUp => TraversalDirection.up,
          LogicalKeyboardKey.arrowDown => TraversalDirection.down,
          LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
          LogicalKeyboardKey.arrowRight => TraversalDirection.right,
          _ => null,
        };
        if (direction == null) return KeyEventResult.ignored;
        if (node.focusInDirection(direction)) return KeyEventResult.handled;
        // Nothing further up: the menu.
        if (direction == TraversalDirection.up) {
          NavigationLayout.focusNavbarNotifier.value?.call();
        }
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovered = true);
          _rest();
        },
        onExit: (_) {
          setState(() => _hovered = false);
          _rest();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          // A right click, with a mouse.
          onSecondaryTap: widget.onLongPress,
          child: widget.builder(context, lit),
        ),
      ),
    );
  }
}

/// A cover, rounded, with a music glyph while it is missing.
class KostvMusicCover extends StatelessWidget {
  const KostvMusicCover({
    super.key,
    required this.url,
    required this.size,
    this.radius = 10,
    this.circle = false,
    this.icon = Icons.music_note_rounded,
  });

  final String? url;
  final double size;
  final double radius;
  final bool circle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: const Color(0xFF2C2C2E),
      alignment: Alignment.center,
      child: Icon(icon, color: kostvMusicGrey, size: size * 0.36),
    );
    final url = this.url;
    final image = url == null
        ? placeholder
        : BoundedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            maxWidth: 600,
            errorBuilder: (context, _, _) => placeholder,
          );
    return SizedBox.square(
      dimension: size,
      child: circle
          ? ClipOval(child: image)
          : ClipRRect(borderRadius: AppRadius.circular(radius), child: image),
    );
  }
}

/// The heading of a section: big and bold, with a line under it.
class KostvMusicHeading extends StatelessWidget {
  const KostvMusicHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.padding = EdgeInsets.zero,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final EdgeInsets padding;

  /// Kos TV: small buttons at the end of the title's line («Reproducir»,
  /// «Aleatorio» of a list), [KostvMusicRowAction]s.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final phone = KostvMusicSizes.phone;
    return Padding(
      padding: padding,
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
                  // Kos TV: the brand's letters for titles (Outfit).
                  style: KostvMusicType.title(KostvMusicTokens.shelfTitle),
                ),
              ),
              for (final action in actions) ...[
                SizedBox(width: phone ? 8 : 12),
                action,
              ],
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KostvMusicType.muted(phone ? 13 : 14),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kos TV: a small button of a list's heading («Reproducir», «Aleatorio»):
/// the play button, or a round one with its icon (its word in the tooltip).
class KostvMusicRowAction extends StatelessWidget {
  const KostvMusicRowAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.onKey,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    // Kos TV: the music design's pieces: «Reproducir» is the one play
    // button (the brand's gradient), the rest round glass buttons; their
    // words go in the tooltip and to the screen reader.
    if (primary && icon == Icons.play_arrow_rounded) {
      return KostvPlayButton(
        size: KostvPlaySize.row,
        diameter: KostvMusicSizes.phone ? 34 : 38,
        tooltip: label,
        focusNode: focusNode,
        onKey: onKey,
        onTap: onTap,
      );
    }
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: KostvMusicPressable(
          focusNode: focusNode,
          onTap: onTap,
          onKey: onKey,
          builder: (context, lit) => KostvRoundIcon(
            icon: icon,
            lit: lit,
            diameter: KostvMusicSizes.phone ? 34 : 38,
          ),
        ),
      ),
    );
  }
}

/// The small pill of how a record stands: «Pedir», «Pedido», «De camino»,
/// «Falló». Kos TV: only with «Solo la de casa» (what isn't at home doesn't
/// play then); with «Toda la música» everything looks the same and asking
/// for an album is on its page. In the music design's quiet language: a
/// see-through pill, not a coloured chip.
class KostvMusicBadgePill extends StatelessWidget {
  const KostvMusicBadgePill({super.key, required this.badge});

  final KostvMusicBadge badge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, icon) = switch (badge) {
      KostvMusicBadge.ask => (l10n.kostvMusicAsk, Icons.download_rounded),
      KostvMusicBadge.asked => (l10n.kostvMusicAsked, Icons.check_rounded),
      KostvMusicBadge.onItsWay => (
        l10n.kostvMusicOnItsWay,
        Icons.local_shipping_rounded,
      ),
      KostvMusicBadge.failed => (
        l10n.kostvMusicDownloadFailedBadge,
        Icons.error_outline_rounded,
      ),
      KostvMusicBadge.none => ('', Icons.circle),
    };
    if (badge == KostvMusicBadge.none) return const SizedBox.shrink();
    final ink = badge == KostvMusicBadge.ask
        ? KostvMusicTokens.ink
        : KostvMusicTokens.muted;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xCC1A1822),
        borderRadius: AppRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: badge == KostvMusicBadge.ask ? 0.28 : 0.10,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ink),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: ink,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// An album (or a mix) as a square cover with its title and artist under
/// it, as Apple Music shows them.
class KostvMusicAlbumTile extends StatelessWidget {
  const KostvMusicAlbumTile({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.cover,
    this.badge = KostvMusicBadge.none,
    this.rank,
    this.size,
    this.circle = false,
    this.focusNode,
    this.autofocus = false,
    this.onKey,
    this.art,
    this.onLongPress,
    this.subtitleLines = 1,
    this.onPlay,
  });

  final String title;
  final String? subtitle;

  /// Kos TV: the lines [subtitle] may take (a mix's «Con X, Y y más»).
  final int subtitleLines;
  final String? cover;
  final KostvMusicBadge badge;

  /// Kos TV: its menu (OK held down, a long press or a right click).
  final VoidCallback? onLongPress;
  final int? rank;
  final double? size;
  final bool circle;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final KeyEventResult Function(KeyEvent event)? onKey;

  /// Drawn instead of [cover] (a mix's own art).
  final Widget? art;

  /// Kos TV: plays it from the ▶ that shows on its cover with the focus
  /// or the mouse over it (a click or a tap on it); the rest of the card
  /// still opens it ([onTap]).
  final VoidCallback? onPlay;

  /// Kos TV: the menu of a card that plays and has none of its own (on the
  /// TV, OK opens it: «Reproducir» is here, with OK held down).
  Future<void> _playMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showKostvMusicMenu<int>(
      context,
      title: title,
      subtitle: subtitle,
      entries: [KostvMenuEntry(0, Icons.play_arrow_rounded, l10n.play)],
    );
    if (choice == 0) onPlay?.call();
  }

  @override
  Widget build(BuildContext context) {
    final playable = !circle && badge == KostvMusicBadge.none;
    if (playable && onPlay != null && !PlatformDetection.isTV) {
      // Kos TV: a finger on the web shows the ▶ by itself.
      return ValueListenableBuilder<bool>(
        valueListenable: InputModeTracker.touchInUse,
        builder: (context, _, _) => _build(context, playable),
      );
    }
    return _build(context, playable);
  }

  Widget _build(BuildContext context, bool playable) {
    final size = this.size ?? KostvMusicSizes.cover;
    final radius = KostvMusicTokens.radiusCover;
    final phone = KostvMusicSizes.phone;
    // Kos TV: with a finger nothing lights a card up: a smaller ▶ stays on
    // it to be tapped.
    final touch = onPlay != null && KostvMusicTokens.touchFirst;
    return SizedBox(
      width: size,
      child: KostvMusicPressable(
        focusNode: focusNode,
        autofocus: autofocus,
        onTap: onTap,
        onLongPress:
            onLongPress ??
            (onPlay != null && playable ? () => _playMenu(context) : null),
        onKey: onKey,
        builder: (context, lit) => Column(
          crossAxisAlignment: circle
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kos TV: the music design's focus (a white frame apart from
            // the cover, 7 % bigger) and, on a record, the play button.
            KostvFocusFrame(
              lit: lit,
              circle: circle,
              radius: radius,
              alignment: const Alignment(0, -0.2),
              child: Stack(
                children: [
                  art ??
                      KostvMusicCover(
                        url: cover,
                        size: size,
                        circle: circle,
                        radius: radius,
                        icon: circle
                            ? Icons.person_rounded
                            : Icons.album_rounded,
                      ),
                  if (badge != KostvMusicBadge.none)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: KostvMusicBadgePill(badge: badge),
                    ),
                  if (rank != null)
                    Positioned(
                      left: 8,
                      bottom: 6,
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          fontFamily: KostvMusicType.titleFamily,
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 10),
                          ],
                        ),
                      ),
                    ),
                  if (playable)
                    Positioned(
                      right: touch ? 4 : 8,
                      bottom: touch ? 4 : 8,
                      child: IgnorePointer(
                        ignoring: !(lit || touch) || onPlay == null,
                        child: AnimatedOpacity(
                          opacity: lit || touch ? 1 : 0,
                          duration: KostvMusicTokens.focusDuration,
                          child: GestureDetector(
                            key: const ValueKey('kostv-card-play'),
                            behavior: HitTestBehavior.opaque,
                            onTap: onPlay,
                            // Kos TV: a finger's room around the smaller ▶.
                            child: Padding(
                              padding: EdgeInsets.all(touch ? 4 : 0),
                              child: KostvPlayFace(
                                diameter: touch
                                    ? (size * 0.2).clamp(28, 36)
                                    : (size * 0.26).clamp(32, 48),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: lit ? 14 : 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              style: KostvMusicType.body(
                phone ? 14 : 15,
                color: lit ? Colors.white : KostvMusicTokens.ink,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  subtitle!,
                  maxLines: subtitleLines,
                  // Kos TV: wrapped even where the text around says not to
                  // (the TV's).
                  softWrap: subtitleLines > 1 ? true : null,
                  overflow: TextOverflow.ellipsis,
                  textAlign: circle ? TextAlign.center : TextAlign.start,
                  style: KostvMusicType.muted(phone ? 12.5 : 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A song as a row: its place in a chart, its cover, title and artist.
/// Kos TV: the music design's [KostvSongRow], with no button of its own and
/// the same whether the song is at home or not; only with «Solo la de
/// casa», one that isn't (it doesn't play then) says how its request
/// stands.
class KostvMusicSongRow extends StatelessWidget {
  const KostvMusicSongRow({
    super.key,
    required this.title,
    required this.onTap,
    this.artist,
    this.cover,
    this.rank,
    this.atHome = false,
    this.badge = KostvMusicBadge.none,
    this.explicit = false,
    this.focusNode,
    this.autofocus = false,
    this.onKey,
    this.trailing,
    this.onLongPress,
    this.artistLinks,
    this.onRest,
    this.away = false,
    this.duration,
    this.soundingId,
  });

  /// The song's menu (OK held down, a long press, a right click or «⋯»).
  final VoidCallback? onLongPress;

  /// Kos TV: see [KostvMusicPressable.onRest].
  final ValueChanged<bool>? onRest;

  /// Kos TV: it isn't at home but plays all the same, through the requests
  /// service («Toda la música»): it looks like one at home.
  final bool away;

  final String title;
  final String? artist;

  /// Kos TV: [artist] as names that open their pages, «Artista · Álbum»
  /// (see [KostvMusicLinks]); off the TV, a tap on one opens it and on the
  /// rest of the row plays the song.
  final List<List<KostvMusicLink>>? artistLinks;
  final String? cover;
  final int? rank;
  final bool atHome;

  /// Kos TV: how its request stands, shown only for one that is neither at
  /// home nor [away] («Solo la de casa»): «Pedir» when none is given.
  final KostvMusicBadge badge;
  final bool explicit;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final KeyEventResult Function(KeyEvent event)? onKey;

  /// Kos TV: shown before the time instead of the request's state.
  final Widget? trailing;

  /// Kos TV: its length in seconds.
  final int? duration;

  /// Kos TV: its id in the player's queue, for the equalizer while it
  /// sounds.
  final String? soundingId;

  @override
  Widget build(BuildContext context) {
    final phone = KostvMusicSizes.phone;
    final links = artistLinks;
    final hasLinks = links != null && links.any((group) => group.isNotEmpty);
    return KostvSongRow(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onMenu: onLongPress,
      onKey: onKey,
      onRest: onRest,
      height: kostvMusicSongRowHeight(context, phone),
      title: title,
      number: rank == null ? null : '$rank',
      cover: cover,
      showCover: true,
      explicit: explicit,
      duration: kostvSongLength(duration),
      soundingId: soundingId,
      subtitle: artist,
      subtitleBuilder: hasLinks
          ? (style) => KostvMusicLinks(groups: links, style: style)
          : null,
      trailing:
          trailing ??
          (atHome || away
              ? null
              : KostvMusicBadgePill(
                  badge: badge == KostvMusicBadge.none
                      ? KostvMusicBadge.ask
                      : badge,
                )),
    );
  }
}

/// Kos TV: the id [song] has in the player's queue (the home server's, or
/// the one of a song that isn't at home), for its row's equalizer.
String? kostvSongSoundingId(StremfinSong song) =>
    song.jellyfinId ??
    (song.deezerId == null ? null : kostvStreamId(song.deezerId!));

/// A row of tiles that scrolls sideways, under its heading.
class KostvMusicShelf extends StatelessWidget {
  const KostvMusicShelf({
    super.key,
    required this.title,
    required this.children,
    required this.insets,
    this.subtitle,
    this.height,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final EdgeInsets insets;

  /// Of the row; a cover's with its two lines by default.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final gap = KostvMusicSizes.gap;
    // The lines of text under the pictures grow with the TV's or phone's
    // own text size, and the shelf with them.
    final grown = MediaQuery.textScalerOf(context).scale(40) - 40;
    final height =
        (this.height ?? KostvMusicSizes.cover + 64) + (grown > 0 ? grown : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KostvMusicHeading(
          title: title,
          subtitle: subtitle,
          padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 12),
        ),
        SizedBox(
          height: height,
          child: FocusTraversalGroup(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.only(
                left: insets.left,
                right: insets.right,
                top: 6,
              ),
              itemCount: children.length,
              separatorBuilder: (_, _) => SizedBox(width: gap),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        ),
      ],
    );
  }
}

/// A mix's own art: a gradient in one of a few colours, «Mezcla» and the
/// artist's name, as the streaming apps make theirs.
/// Kos TV: the music design's mix card (`docs/diseno-musica`): the colour of
/// the mix, the artist's picture in a circle and the name in the brand's
/// letters, with a stripe of its colour at the foot.
class KostvMusicMixArt extends StatelessWidget {
  const KostvMusicMixArt({
    super.key,
    required this.name,
    required this.index,
    required this.size,
    this.picture,
  });

  final String name;
  final int index;
  final double size;
  final String? picture;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _KostvMixCard(
      colors: kostvMixColors(index),
      size: size,
      pictures: [?picture],
      kicker: l10n.kostvMusicMixLabel,
      label: name,
    );
  }
}

/// Kos TV: the colours of the mix cards, as the design draws them (a
/// light and a deep one of each).
const _kostvMixColors = [
  [Color(0xFFE33AD6), Color(0xFF5B0F30)],
  [Color(0xFF3BA9F2), Color(0xFF2A1561)],
  [Color(0xFF9BF23A), Color(0xFF0E5A3C)],
  [Color(0xFFF2A33A), Color(0xFF3B5A0E)],
  [Color(0xFF36E58C), Color(0xFF0C2B5E)],
  [Color(0xFFF2456B), Color(0xFF6A4A12)],
];

/// Kos TV: the two colours of the [index]th mix card (from 0).
List<Color> kostvMixColors(int index) =>
    _kostvMixColors[index % _kostvMixColors.length];

/// Kos TV: a mix card's drawing: its colour, up to two of its artists'
/// pictures in circles, its name at the foot in Outfit and a stripe of its
/// colour under it. Drawn to its size: the device's larger text doesn't
/// push the words out of it.
class _KostvMixCard extends StatelessWidget {
  const _KostvMixCard({
    required this.colors,
    required this.size,
    required this.pictures,
    required this.label,
    this.kicker,
  });

  final List<Color> colors;
  final double size;
  final List<String> pictures;
  final String label;
  final String? kicker;

  Widget _portrait(String? url, double d) {
    final empty = DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.6),
          colors: [
            Colors.white.withValues(alpha: 0.30),
            Colors.black.withValues(alpha: 0.25),
          ],
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        size: d * 0.62,
        color: Colors.black.withValues(alpha: 0.35),
      ),
    );
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: d * 0.18,
            offset: Offset(0, d * 0.05),
          ),
        ],
      ),
      child: ClipOval(
        child: url == null || url.isEmpty
            ? empty
            : BoundedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                maxWidth: 400,
                errorBuilder: (context, _, _) => empty,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final big = size * 0.44;
    final small = size * 0.30;
    final shadow = [
      Shadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12),
    ];
    return MediaQuery.withNoTextScaling(
      child: ClipRRect(
        borderRadius: AppRadius.circular(KostvMusicTokens.radiusCover),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: const Alignment(-0.6, -1),
                      end: const Alignment(0.6, 1),
                      colors: colors,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: size * 0.10,
                top: size * 0.10,
                child: _portrait(pictures.firstOrNull, big),
              ),
              if (pictures.length > 1)
                Positioned(
                  left: size * 0.48,
                  top: size * 0.20,
                  child: _portrait(pictures[1], small),
                ),
              Positioned(
                left: size * 0.09,
                right: size * 0.09,
                bottom: size * 0.11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kicker != null)
                      Text(
                        kicker!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KostvMusicType.titleFamily,
                          fontWeight: FontWeight.w300,
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: size * 0.065,
                          letterSpacing: size * 0.01,
                          shadows: shadow,
                        ),
                      ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KostvMusicType.title(
                        size * 0.13,
                        color: Colors.white,
                      ).copyWith(shadows: shadow),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: (size * 0.03).clamp(3, 6),
                child: ColoredBox(
                  color: Color.lerp(colors.first, Colors.white, 0.18)!,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A song row's height: grows with the person's text size, as the lists
/// that hold the rows do.
double kostvMusicSongRowHeight(BuildContext context, bool phone) {
  final base = phone ? 62.0 : 70.0;
  final grown = MediaQuery.textScalerOf(context).scale(36) - 36;
  return base + (grown > 0 ? grown : 0);
}

/// Kos TV: a daily mix's cover: its colour, two of its artists' pictures
/// in circles and its name («Mix diario 1») at the foot, as the music
/// design draws the mix cards.
class KostvDailyMixArt extends StatelessWidget {
  const KostvDailyMixArt({
    super.key,
    required this.number,
    required this.size,
    this.pictures = const [],
  });

  /// From 1.
  final int number;
  final double size;

  /// Its artists' pictures (the first two are drawn).
  final List<String> pictures;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _KostvMixCard(
      colors: kostvMixColors(number - 1),
      size: size,
      pictures: pictures,
      label: l10n.kostvMusicDailyMix(number),
    );
  }
}

/// Kos TV: the cover of an artist's radio («Radios de tus artistas»): the
/// artist's picture in a circle, with rings of the brand's gradient around
/// it like a station's waves, on the page's dark tinted with the colour of
/// a mix, and «RADIO» and the name at the foot in the brand's letters.
class KostvArtistRadioArt extends StatelessWidget {
  const KostvArtistRadioArt({
    super.key,
    required this.name,
    required this.index,
    required this.size,
    this.picture,
  });

  final String name;
  final int index;
  final double size;
  final String? picture;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tint = kostvMixColors(index).last;
    final d = size * 0.50;
    final shadow = [
      Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 12),
    ];
    final empty = ColoredBox(
      color: Colors.white.withValues(alpha: 0.08),
      child: Icon(
        Icons.person_rounded,
        size: d * 0.6,
        color: Colors.white.withValues(alpha: 0.35),
      ),
    );
    return MediaQuery.withNoTextScaling(
      child: ClipRRect(
        borderRadius: AppRadius.circular(KostvMusicTokens.radiusCover),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.35),
                      radius: 0.9,
                      colors: [
                        Color.lerp(tint, Colors.white, 0.12)!,
                        Color.lerp(tint, KostvMusicTokens.background, 0.72)!,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _KostvRadioWaves(
                    center: Offset(size / 2, size * 0.38),
                    radius: d / 2,
                  ),
                ),
              ),
              Positioned(
                left: (size - d) / 2,
                top: size * 0.38 - d / 2,
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: d * 0.2,
                        offset: Offset(0, d * 0.05),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: picture == null || picture!.isEmpty
                        ? empty
                        : BoundedNetworkImage(
                            imageUrl: picture!,
                            fit: BoxFit.cover,
                            maxWidth: 400,
                            errorBuilder: (context, _, _) => empty,
                          ),
                  ),
                ),
              ),
              Positioned(
                left: size * 0.09,
                // Kos TV: clear of the card's ▶, always shown on the phone.
                right: size * 0.27,
                bottom: size * 0.09,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        KostvGradientText(
                          child: Icon(
                            Icons.sensors_rounded,
                            size: size * 0.085,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: size * 0.025),
                        Flexible(
                          child: Text(
                            l10n.kostvMusicRadioKicker.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: KostvMusicType.titleFamily,
                              fontWeight: FontWeight.w300,
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: size * 0.065,
                              letterSpacing: size * 0.012,
                              shadows: shadow,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KostvMusicType.title(
                        size * 0.12,
                        color: Colors.white,
                      ).copyWith(shadows: shadow),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kos TV: the rings of an artist's radio cover, in the brand's gradient,
/// fainter as they go out.
class _KostvRadioWaves extends CustomPainter {
  const _KostvRadioWaves({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: center, radius: radius * 2.2);
    for (final (i, alpha) in const [0.85, 0.45, 0.2].indexed) {
      final r = radius + radius * 0.16 + i * radius * 0.26;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (radius * 0.05).clamp(1.5, 4)
        ..shader = KostvMusicTokens.gradient.createShader(rect)
        ..color = Colors.white.withValues(alpha: alpha);
      canvas.saveLayer(
        rect,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
      canvas.drawCircle(center, r, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_KostvRadioWaves old) =>
      old.center != center || old.radius != radius;
}
