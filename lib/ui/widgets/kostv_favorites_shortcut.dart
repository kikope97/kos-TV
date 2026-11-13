import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../l10n/app_localizations.dart';
import '../../util/focus/input_mode_tracker.dart';
import '../../util/platform_detection.dart';

/// Kos TV: the heart of «Mis favoritos».
const kostvFavoritesColor = Color(0xFFF87171);

/// Kos TV: «Mis favoritos» comes out from behind the avatar, beside the
/// requests tray, while the person is on their profile: favourites are theirs,
/// and the menu keeps «Mi lista» alone so the two don't get mixed up.
class KostvFavoritesSlot extends StatelessWidget {
  const KostvFavoritesSlot({
    super.key,
    required this.revealed,
    required this.builder,
    this.axis = Axis.horizontal,
  });

  final bool revealed;

  /// Which way it slides out from behind the avatar.
  final Axis axis;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: axis == Axis.horizontal
          ? AlignmentDirectional.centerStart
          : Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.7, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: revealed
            ? KeyedSubtree(
                key: const ValueKey('favorites'),
                child: builder(context),
              )
            : const SizedBox.shrink(key: ValueKey('none')),
      ),
    );
  }
}

/// Kos TV: the round button of «Mis favoritos», beside the avatar, made like
/// the requests tray's.
class KostvFavoritesButton extends StatefulWidget {
  const KostvFavoritesButton({
    super.key,
    required this.size,
    required this.onPressed,
    this.focusNode,
    this.onDown,
    this.background,
  });

  final double size;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  /// Down from it, on a TV or a computer (back to the page, as from the
  /// avatar).
  final VoidCallback? onDown;
  final Color? background;

  @override
  State<KostvFavoritesButton> createState() => _KostvFavoritesButtonState();
}

class _KostvFavoritesButtonState extends State<KostvFavoritesButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lit =
        InputModeTracker.showFocusVisuals(context, _focused) || _hovered;
    final size = widget.size;
    final tv = PlatformDetection.isTV;
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit && tv
            ? Colors.white
            : (widget.background ?? Colors.white.withValues(alpha: 0.12)),
        border: lit && !tv
            ? Border.fromBorderSide(ThemeRegistry.active.borders.focusBorder)
            : null,
      ),
      child: Icon(
        Icons.favorite_rounded,
        size: size * 0.5,
        color: kostvFavoritesColor,
      ),
    );
    return Semantics(
      button: true,
      label: l10n.kostvMyFavorites,
      child: Tooltip(
        message: l10n.kostvMyFavorites,
        child: Focus(
          focusNode: widget.focusNode,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              widget.onPressed();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                widget.onDown != null) {
              widget.onDown!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onPressed,
              child: AnimatedScale(
                scale: lit ? 1.08 : 1,
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  width: size + 8,
                  height: size + 8,
                  child: Center(child: circle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
