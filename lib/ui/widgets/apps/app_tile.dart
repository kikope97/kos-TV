import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/installed_apps_service.dart';

/// Kos TV: one app on the Apps row or the All apps screen, 16:9 like a TV
/// launcher. An app with a TV banner fills the card with it; one without
/// shows its icon over its name. With no [app] the card is an action, such
/// as All apps, drawn as [icon] over [label].
class AppTile extends StatelessWidget {
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
  }) : assert(app != null || label != null);

  final double width;
  final double height;
  final bool focused;
  final Color focusColor;
  final InstalledApp? app;
  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final app = this.app;
    final art = app?.art;
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context)).round();
    final name = Text(
      app?.label ?? label!,
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
                icon ?? Icons.apps_rounded,
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
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColorScheme.surface,
          borderRadius: radius,
          border: Border.all(
            color: focused ? focusColor : Colors.white.withValues(alpha: 0.08),
            width: focused ? 3 : 1,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: focusColor.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(borderRadius: radius, child: content),
      ),
    );
  }
}
