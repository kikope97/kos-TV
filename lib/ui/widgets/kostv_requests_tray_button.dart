import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/services/stremfin/stremfin_service.dart';
import '../../l10n/app_localizations.dart';
import '../../preference/user_preferences.dart';
import '../../util/focus/input_mode_tracker.dart';
import '../../util/platform_detection.dart';

/// Kos TV: whether the signed-in person can have a requests tray: the
/// requests service lets them in, outside kids mode.
bool kostvRequestsTrayAvailable() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<StremfinService>()) return false;
  if (getIt.isRegistered<UserPreferences>() &&
      getIt<UserPreferences>().get(UserPreferences.kidsModeEnabled)) {
    return false;
  }
  return getIt<StremfinService>().isAllowed;
}

/// Kos TV: shows the requests tray's button while there is news or
/// something under way, and otherwise only while [revealed] (the avatar
/// beside it has the focus, or the pointer is over it).
class KostvRequestsTraySlot extends StatelessWidget {
  const KostvRequestsTraySlot({
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
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) return const SizedBox.shrink();
    final service = getIt<StremfinService>();
    return ListenableBuilder(
      listenable: Listenable.merge([service, service.inbox]),
      builder: (context, _) {
        final inbox = service.inbox;
        final show =
            kostvRequestsTrayAvailable() &&
            (revealed || inbox.newsCount > 0 || inbox.hasActive);
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
            child: show
                ? KeyedSubtree(
                    key: const ValueKey('tray'),
                    child: builder(context),
                  )
                : const SizedBox.shrink(key: ValueKey('none')),
          ),
        );
      },
    );
  }
}

/// Kos TV: the requests tray's button: a tray with the number of news on
/// it, and a ring turning round it while something is under way.
class KostvRequestsTrayButton extends StatefulWidget {
  const KostvRequestsTrayButton({
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
  State<KostvRequestsTrayButton> createState() =>
      _KostvRequestsTrayButtonState();
}

class _KostvRequestsTrayButtonState extends State<KostvRequestsTrayButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final service = GetIt.instance<StremfinService>();
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: service.inbox,
      builder: (context, _) {
        final inbox = service.inbox;
        final news = inbox.newsCount;
        final busy = inbox.hasActive;
        final lit =
            InputModeTracker.showFocusVisuals(context, _focused) || _hovered;
        final size = widget.size;
        final tv = PlatformDetection.isTV;
        final accent = AppColorScheme.accent;
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
                ? Border.fromBorderSide(
                    ThemeRegistry.active.borders.focusBorder,
                  )
                : null,
          ),
          child: Icon(
            news > 0 ? Icons.inbox_rounded : Icons.inbox_outlined,
            size: size * 0.52,
            color: lit && tv ? Colors.black87 : Colors.white,
          ),
        );
        return Semantics(
          button: true,
          label: l10n.kostvTrayOpen,
          child: Tooltip(
            message: l10n.kostvTrayOpen,
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
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // Something under way: a ring turning round it.
                          // Its own layer: turning, it doesn't repaint
                          // the menu around it.
                          if (busy)
                            RepaintBoundary(
                              child: SizedBox(
                                width: size + 7,
                                height: size + 7,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: accent,
                                  backgroundColor: accent.withValues(
                                    alpha: 0.18,
                                  ),
                                ),
                              ),
                            ),
                          circle,
                          if (news > 0)
                            Positioned(
                              top: -1,
                              right: -1,
                              child: _Badge(count: news, size: size * 0.46),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The number of news on the tray.
class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minWidth: size, minHeight: size),
    padding: EdgeInsets.symmetric(horizontal: size * 0.22),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE5484D),
      borderRadius: BorderRadius.circular(size),
      border: Border.all(
        color: Colors.black.withValues(alpha: 0.6),
        width: 1.5,
      ),
      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
    ),
    child: Text(
      count > 9 ? '9+' : '$count',
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.62,
        fontWeight: FontWeight.w800,
        height: 1.1,
      ),
    ),
  );
}

/// Kos TV: the number of news for a menu row or a tab: a small red pill,
/// or nothing.
class KostvRequestsNewsBadge extends StatelessWidget {
  const KostvRequestsNewsBadge({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) return const SizedBox.shrink();
    final inbox = getIt<StremfinService>().inbox;
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) => inbox.newsCount > 0
          ? _Badge(count: inbox.newsCount, size: size)
          : const SizedBox.shrink(),
    );
  }
}
