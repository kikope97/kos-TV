import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/navigation_layout.dart';

/// Kos TV: the colour of Music, Apple Music's red-pink.
const kostvMusicColor = Color(0xFFFA2D55);

/// The grey of what goes under a title.
const kostvMusicGrey = Color(0xFF98989F);

/// How a record stands, for the badge on its cover.
enum KostvMusicBadge { none, ask, asked, onItsWay }

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
void kostvMusicRevealVertically(
  BuildContext item, [
  ScrollableState? page,
  bool onlyIfHidden = false,
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
  final target = (position.pixels + top - wanted).clamp(
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
  });

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

  @override
  void dispose() {
    _hold?.cancel();
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
    if (scrollable != null) {
      final page = scrollable;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) kostvMusicRevealVertically(context, page);
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
        // Nothing further up, or left with the menu at the side: the menu.
        final side =
            GetIt.instance<UserPreferences>().get(
              UserPreferences.navbarPosition,
            ) ==
            NavbarPosition.left;
        if (direction == TraversalDirection.up ||
            (direction == TraversalDirection.left && side)) {
          NavigationLayout.focusNavbarNotifier.value?.call();
        }
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
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
  });

  final String title;
  final String? subtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: phone ? 21 : 24,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: kostvMusicGrey,
                fontSize: phone ? 13 : 14,
              ),
            ),
        ],
      ),
    );
  }
}

/// The small pill on a cover: «Pedir», «Pedido», «De camino».
class KostvMusicBadgePill extends StatelessWidget {
  const KostvMusicBadgePill({super.key, required this.badge});

  final KostvMusicBadge badge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, color, icon) = switch (badge) {
      KostvMusicBadge.ask => (
        l10n.kostvMusicAsk,
        kostvMusicColor,
        Icons.add_rounded,
      ),
      KostvMusicBadge.asked => (
        l10n.kostvMusicAsked,
        const Color(0xFF636366),
        Icons.check_rounded,
      ),
      KostvMusicBadge.onItsWay => (
        l10n.kostvMusicOnItsWay,
        const Color(0xFF0A84FF),
        Icons.downloading_rounded,
      ),
      KostvMusicBadge.none => ('', Colors.transparent, Icons.circle),
    };
    if (badge == KostvMusicBadge.none) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.circular(999),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
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
  });

  final String title;
  final String? subtitle;
  final String? cover;
  final KostvMusicBadge badge;
  final int? rank;
  final double? size;
  final bool circle;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final KeyEventResult Function(KeyEvent event)? onKey;

  /// Drawn instead of [cover] (a mix's own art).
  final Widget? art;

  @override
  Widget build(BuildContext context) {
    final size = this.size ?? KostvMusicSizes.cover;
    return SizedBox(
      width: size,
      child: KostvMusicPressable(
        focusNode: focusNode,
        autofocus: autofocus,
        onTap: onTap,
        onKey: onKey,
        builder: (context, lit) => Column(
          crossAxisAlignment: circle
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: lit ? 1.06 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  shape: circle ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: circle ? null : AppRadius.circular(12),
                  border: Border.all(
                    color: lit ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: lit
                      ? const [
                          BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  children: [
                    art ??
                        KostvMusicCover(
                          url: cover,
                          size: size - 6,
                          circle: circle,
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
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 10),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                color: Colors.white,
                fontSize: KostvMusicSizes.phone ? 13.5 : 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: circle ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  color: kostvMusicGrey,
                  fontSize: KostvMusicSizes.phone ? 12.5 : 13.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A song as a row: its cover, its place in a chart, title and artist, and
/// at the end whether it is at home or can be asked for.
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
  });

  /// The song's menu (OK held down, a long press or a right click).
  final VoidCallback? onLongPress;

  final String title;
  final String? artist;
  final String? cover;
  final int? rank;
  final bool atHome;
  final KostvMusicBadge badge;
  final bool explicit;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    return KostvMusicPressable(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onLongPress: onLongPress,
      onKey: onKey,
      builder: (context, lit) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: phone ? 62 : 70,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: lit ? Colors.white : Colors.transparent,
          borderRadius: AppRadius.circular(10),
        ),
        child: Row(
          children: [
            KostvMusicCover(url: cover, size: phone ? 48 : 54, radius: 6),
            if (rank != null)
              SizedBox(
                width: phone ? 34 : 40,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: lit ? Colors.black : Colors.white,
                    fontSize: phone ? 16 : 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: lit ? Colors.black : Colors.white,
                            fontSize: phone ? 15 : 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (explicit) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.explicit_rounded,
                          size: 16,
                          color: lit ? Colors.black54 : kostvMusicGrey,
                        ),
                      ],
                    ],
                  ),
                  if (artist != null)
                    Text(
                      artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: lit ? Colors.black54 : kostvMusicGrey,
                        fontSize: phone ? 13 : 14,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                (atHome
                    ? Tooltip(
                        message: l10n.kostvMusicAtHome,
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: lit ? Colors.black : kostvMusicColor,
                          size: phone ? 26 : 28,
                        ),
                      )
                    : KostvMusicBadgePill(
                        badge: badge == KostvMusicBadge.none
                            ? KostvMusicBadge.ask
                            : badge,
                      )),
          ],
        ),
      ),
    );
  }
}

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
    final height = this.height ?? KostvMusicSizes.cover + 64;
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

  static const _colors = [
    [Color(0xFFFA2D55), Color(0xFF8E1B6E)],
    [Color(0xFF5E5CE6), Color(0xFF1E3A8A)],
    [Color(0xFF30D158), Color(0xFF0E5F5C)],
    [Color(0xFFFF9F0A), Color(0xFFB4235F)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _colors[index % _colors.length];
    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: AppRadius.circular(10),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
              ),
            ),
            if (picture != null)
              Opacity(
                opacity: 0.35,
                child: BoundedNetworkImage(
                  imageUrl: picture!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(size * 0.08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: size * 0.16,
                  ),
                  const Spacer(),
                  Text(
                    l10n.kostvMusicMixLabel.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: size * 0.07,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.12,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
