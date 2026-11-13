import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import 'unread_badge.dart';

import '../../preference/user_preferences.dart';
import '../../util/focus/dpad_keys.dart';
import '../../util/focus/input_mode_tracker.dart';
import '../../util/platform_detection.dart';
import 'focus/focus_theme.dart';
import 'focus/glass_press_scale.dart';
import 'nav_capsule.dart';

const _kExpandDuration = Duration(milliseconds: 150);

// Kos TV: under the menu's capsule the label left folds away as the next one
// unfolds, at the same pace and mirrored, so the bar keeps its width and
// doesn't sway while the capsule travels.
const _kOpenDuration = Duration(milliseconds: 300);
const _kCloseDuration = Duration(milliseconds: 300);
const _kSpacing = 10.0;

class ExpandableIconButton extends StatefulWidget {
  final IconData? icon;
  final Widget Function(double size, Color color)? iconBuilder;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final ValueChanged<bool>? onFocusChanged;
  final Color? baseColor;

  /// Unread count drawn as a small red circle on the icon. Zero draws nothing.
  final int badgeCount;

  /// When true, the label stays visible even when unfocused/unhovered instead
  /// of collapsing to an icon-only button. Drives the "always expand navbar
  /// labels" preference.
  final bool forceExpanded;

  const ExpandableIconButton({
    super.key,
    this.icon,
    this.iconBuilder,
    required this.label,
    required this.onPressed,
    this.onLongPress,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChanged,
    this.baseColor,
    this.badgeCount = 0,
    this.forceExpanded = false,
  });

  @override
  State<ExpandableIconButton> createState() => _ExpandableIconButtonState();
}

class _ExpandableIconButtonState extends State<ExpandableIconButton>
    with SingleTickerProviderStateMixin {
  final _prefs = GetIt.instance<UserPreferences>();
  late final FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;

  /// Kos TV: how open the label is, 0 to 1, under the menu's capsule.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: _kOpenDuration,
    reverseDuration: _kCloseDuration,
  );
  late final Animation<double> _width = CurvedAnimation(
    parent: _open,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<double> _labelOpacity = CurvedAnimation(
    parent: _open,
    curve: const Interval(0.3, 1, curve: Curves.easeOut),
    reverseCurve: const Interval(0.45, 1, curve: Curves.easeIn),
  );
  bool? _openTarget;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
    _open.addListener(() => NavCapsule.maybeOf(context)?.nudge());
    _open.addStatusListener((status) {
      if (status == AnimationStatus.completed && _focusNode.hasFocus) {
        _ensureVisible();
      }
    });
  }

  void _setOpen(bool open) {
    if (_openTarget == open) return;
    final first = _openTarget == null;
    _openTarget = open;
    if (first) {
      _open.value = open ? 1 : 0;
      return;
    }
    // A page that came in under the same menu: its label is open already,
    // from this very frame.
    if (open && NavCapsule.snapping) {
      _open.value = 1;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _openTarget != open) return;
      open ? _open.forward() : _open.reverse();
    });
  }

  bool _lastExpanded = false;
  bool _lastActive = false;

  @override
  void dispose() {
    _open.dispose();
    _longPressTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    final hasFocus = _focusNode.hasFocus;
    if (hasFocus == _isFocused) return;
    setState(() => _isFocused = hasFocus);
    if (hasFocus) _ensureVisible();
    widget.onFocusChanged?.call(hasFocus);
  }

  // Keep the focused item on screen inside a horizontally-scrolling navbar.
  // Runs after the frame so the expand animation's new width is measured first.
  // A no-op when there is no enclosing Scrollable.
  void _ensureVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      // Scrolling a box into view needs it laid out first, and focus can land
      // here a frame before that happens.
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final delegated = widget.onKeyEvent?.call(node, event);
    if (delegated != null && delegated != KeyEventResult.ignored) {
      return delegated;
    }

    if (widget.onLongPress != null &&
        event is KeyDownEvent &&
        event.logicalKey.isContextMenuKey) {
      widget.onLongPress!();
      return KeyEventResult.handled;
    }

    if (widget.onLongPress != null && event.logicalKey.isSelectKey) {
      if (event is KeyDownEvent) {
        _longPressTriggered = false;
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(milliseconds: 450), () {
          if (!mounted || !_focusNode.hasFocus) return;
          _longPressTriggered = true;
          widget.onLongPress?.call();
        });
        return KeyEventResult.handled;
      }

      if (event is KeyUpEvent) {
        _longPressTimer?.cancel();
        _longPressTimer = null;
        final triggered = _longPressTriggered;
        _longPressTriggered = false;
        if (!triggered) {
          widget.onPressed();
        }
        return KeyEventResult.handled;
      }
    }

    if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
      widget.onPressed();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = PlatformDetection.useMobileUi;
    final isTV = PlatformDetection.isTV;
    final desktopScale = _prefs.get(UserPreferences.desktopUiScale).scaleFactor;
    final btnSize = (isMobile ? 40.0 : (isTV ? 44.0 : 56.0)) * desktopScale;
    final iconSize = (isMobile ? 22.0 : (isTV ? 24.0 : 30.0)) * desktopScale;
    final focusColor = Color(_prefs.get(UserPreferences.focusColor).colorValue);

    // Gate focus visuals to keyboard/D-pad input
    final focusVisible = InputModeTracker.showFocusVisuals(context, _isFocused);
    final hoverActive = _isHovered && !isTV;
    final leanbackFocused = focusVisible && !isMobile;
    final isExpanded = widget.forceExpanded || focusVisible || hoverActive;
    final effectiveBorderRadius = !isMobile ? 36.0 : (btnSize / 2);
    final baseColor = widget.baseColor ?? AppColorScheme.onSurface.withValues(alpha: 0.6);
    final useBaseForFocus = widget.baseColor != null;

    final bgColor = leanbackFocused
        ? AppColorScheme.onSurface
        : (focusVisible || hoverActive)
        ? focusColor.withValues(alpha: 0.18)
        : Colors.transparent;

    final fgColor = leanbackFocused
      ? AppColors.black
      : (focusVisible || hoverActive)
      ? (useBaseForFocus ? baseColor : focusColor)
      : baseColor;

    final hoverEnabled = !isTV;
    // Kos TV: with a remote, a keyboard or a mouse the menu's capsule shows
    // the button; on touch screens it keeps its own look.
    if (!isMobile && NavCapsule.maybeOf(context) != null) {
      // On a page that is no longer the one shown the button stays as it
      // was, so a page coming in over it under the same menu matches it.
      final current = ModalRoute.isCurrentOf(context) ?? true;
      final expanded = current ? isExpanded : _lastExpanded;
      final active = current ? (focusVisible || hoverActive) : _lastActive;
      _lastExpanded = expanded;
      _lastActive = active;
      _setOpen(expanded);
      return MouseRegion(
        cursor: hoverEnabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: hoverEnabled ? (_) => setState(() => _isHovered = true) : null,
        onExit: hoverEnabled ? (_) => setState(() => _isHovered = false) : null,
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKeyEvent,
          child: GestureDetector(
            onTap: widget.onPressed,
            onLongPress: widget.onLongPress,
            child: GlassPressScale(
              child: NavCapsuleTarget(
                active: active,
                builder: (context, cover) => AnimatedBuilder(
                  animation: _open,
                  builder: (context, _) => _capsuleContent(
                    btnSize: btnSize,
                    iconSize: iconSize,
                    color: Color.lerp(baseColor, AppColors.black, cover)!,
                    fontSize: isTV ? 14 : 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return MouseRegion(
      cursor: hoverEnabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: hoverEnabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: hoverEnabled ? (_) => setState(() => _isHovered = false) : null,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKeyEvent,
        child: GestureDetector(
          onTap: widget.onPressed,
          onLongPress: widget.onLongPress,
          child: GlassPressScale(
            child: AnimatedContainer(
              duration: _kExpandDuration,
              curve: Curves.easeOut,
              // A growing label can push a button at the end of a crowded
              // navbar off screen, so it scrolls into view again once grown.
              onEnd: () {
                if (_focusNode.hasFocus) _ensureVisible();
              },
              height: isMobile ? btnSize : null,
              constraints: BoxConstraints(
                minWidth: btnSize,
                maxWidth: isExpanded ? 200 : btnSize,
              ),
              decoration: FocusTheme.focusDecoration(
                isFocused: focusVisible && isMobile,
                radius: effectiveBorderRadius,
                color: focusColor,
                backgroundColor: bgColor,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: isExpanded ? (isMobile ? 18 : 24) : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  UnreadBadge(
                    count: widget.badgeCount,
                    child:
                        widget.iconBuilder?.call(iconSize, fgColor) ??
                        Icon(widget.icon, size: iconSize, color: fgColor),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(width: _kSpacing),
                    Flexible(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          color: fgColor,
                          fontSize: isMobile ? 14 : (isTV ? 14 : 16),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The icon and, opening beside it, the label, for the capsule look.
  Widget _capsuleContent({
    required double btnSize,
    required double iconSize,
    required Color color,
    required double fontSize,
  }) {
    final t = _width.value;
    final shown = _labelOpacity.value;
    return Container(
      constraints: BoxConstraints(minWidth: btnSize, minHeight: btnSize),
      padding: EdgeInsets.symmetric(horizontal: 22 * t),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UnreadBadge(
            count: widget.badgeCount,
            child:
                widget.iconBuilder?.call(iconSize, color) ??
                Icon(widget.icon, size: iconSize, color: color),
          ),
          // In from the frame it starts opening, so the label is there at once.
          if (t > 0 || _openTarget == true)
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: t,
                child: Opacity(
                  opacity: shown,
                  child: Transform.translate(
                    offset: Offset(-8 * (1 - shown), 0),
                    child: Padding(
                      padding: const EdgeInsets.only(left: _kSpacing),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            color: color,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
