import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/installed_apps_service.dart';
import 'app_accent_color.dart';

/// Kos TV: one app on the Apps row or the All apps screen, 16:9 like a TV
/// launcher. An app with a TV banner fills the card with it; one without
/// shows its icon over its name. With no [app] the card is an action, such
/// as All apps, drawn as [icon] over [label].
///
/// Focused, the card glows in the app's own colour (see [AppAccentColors]).
class AppTile extends StatefulWidget {
  const AppTile({
    super.key,
    required this.width,
    required this.height,
    required this.focused,
    required this.focusColor,
    this.app,
    this.icon,
    this.label,
    this.onTap,
    this.wideGlow = false,
  }) : assert(app != null || label != null);

  final double width;
  final double height;
  final bool focused;
  final Color focusColor;
  final InstalledApp? app;
  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;

  /// A wider glow, where the card has room around it (All apps); a row that
  /// clips its cards keeps it tight.
  final bool wideGlow;

  @override
  State<AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<AppTile> {
  Color? _accent;

  @override
  void initState() {
    super.initState();
    _readAccent();
  }

  @override
  void didUpdateWidget(AppTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app?.packageName != widget.app?.packageName ||
        oldWidget.app?.art != widget.app?.art) {
      _readAccent();
    }
  }

  void _readAccent() {
    final app = widget.app;
    if (app == null) {
      _accent = AppAccentColors.neutral;
      return;
    }
    _accent = AppAccentColors.cached(app);
    if (AppAccentColors.isKnown(app)) {
      _accent ??= AppAccentColors.neutral;
      return;
    }
    unawaited(
      AppAccentColors.of(app).then((color) {
        if (mounted && widget.app?.packageName == app.packageName) {
          setState(() => _accent = color ?? AppAccentColors.neutral);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final height = widget.height;
    final focused = widget.focused;
    final focusColor = widget.focusColor;
    final glow = _accent ?? focusColor;
    final radius = BorderRadius.circular(12);
    final app = widget.app;
    final art = app?.art;
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context)).round();
    final name = Text(
      app?.label ?? widget.label!,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppColorScheme.onSurface,
        fontSize: (height * 0.12).clamp(12, 16),
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
    );

    final Widget content;
    if (app != null && app.isBanner && art != null) {
      content = Image.memory(
        art,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        semanticLabel: app.label,
      );
    } else {
      final iconSize = height * 0.4;
      content = Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (art != null)
              Image.memory(
                art,
                width: iconSize,
                height: iconSize,
                cacheWidth: (iconSize * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              )
            else
              Icon(
                widget.icon ?? Icons.apps_rounded,
                size: iconSize * 0.8,
                color: AppColorScheme.onSurface,
              ),
            SizedBox(height: height * 0.07),
            name,
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColorScheme.surface,
          borderRadius: radius,
          border: Border.all(
            color: focused ? focusColor : Colors.white.withValues(alpha: 0.08),
            width: focused ? 3 : 1,
          ),
          // The app's own colour around the focused card; the same shadows,
          // clear, when it isn't, so the glow fades in and out.
          boxShadow: widget.wideGlow
              ? [
                  BoxShadow(
                    color: glow.withValues(alpha: focused ? 0.55 : 0),
                    blurRadius: focused ? 30 : 0,
                    spreadRadius: focused ? 2 : 0,
                  ),
                  BoxShadow(
                    color: glow.withValues(alpha: focused ? 0.25 : 0),
                    blurRadius: focused ? 60 : 0,
                    spreadRadius: focused ? 6 : 0,
                  ),
                ]
              : [
                  BoxShadow(
                    color: glow.withValues(alpha: focused ? 0.5 : 0),
                    blurRadius: focused ? 16 : 0,
                    spreadRadius: focused ? 1 : 0,
                  ),
                ],
        ),
        child: ClipRRect(borderRadius: radius, child: content),
      ),
    );
  }
}
