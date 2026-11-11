import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/installed_apps_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/key_event_utils.dart';
import '../../mixins/focus_state_mixin.dart';
import '../../navigation/destinations.dart';
import '../../widgets/apps/app_tile.dart';
import '../../widgets/navigation_layout.dart';
import '../downloads/widgets/saved_media_menu.dart';

/// Kos TV: every app installed on the TV, like a launcher's app drawer. The
/// first card opens the TV's own settings. A long press (or the menu key) on
/// an app adds it to the Apps row on Home or takes it off.
class AllAppsScreen extends StatefulWidget {
  const AllAppsScreen({super.key});

  @override
  State<AllAppsScreen> createState() => _AllAppsScreenState();
}

class _AllAppsScreenState extends State<AllAppsScreen> {
  final InstalledAppsService _apps = GetIt.instance<InstalledAppsService>();

  @override
  void initState() {
    super.initState();
    _apps.addListener(_onAppsChanged);
    unawaited(_apps.refresh());
  }

  @override
  void dispose() {
    _apps.removeListener(_onAppsChanged);
    super.dispose();
  }

  void _onAppsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _open(InstalledApp app) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await _apps.launch(app)) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.kostvAppCouldNotOpen(app.label))),
      );
    }
  }

  Future<void> _showMenu(InstalledApp app) {
    final l10n = AppLocalizations.of(context);
    final onHome = _apps.isOnHome(app);
    return showSavedMediaMenu(
      context,
      title: app.label,
      actions: [
        SavedMediaAction(
          icon: Icons.open_in_new_rounded,
          label: l10n.kostvAppOpen,
          onSelect: () => _open(app),
        ),
        if (onHome)
          SavedMediaAction(
            icon: Icons.remove_circle_outline_rounded,
            label: l10n.kostvAppRemoveFromHome,
            isDestructive: true,
            onSelect: () => _apps.removeFromHome(app),
          )
        else
          SavedMediaAction(
            icon: Icons.add_circle_outline_rounded,
            label: l10n.kostvAppAddToHome,
            onSelect: () => _apps.addToHome(app),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final Widget content;
    if (!_apps.isLoaded) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) {
          const padding = 48.0;
          const spacing = 20.0;
          final usable = constraints.maxWidth - padding * 2;
          final columns = (usable / 260).floor().clamp(2, 8);
          final tileWidth = (usable - spacing * (columns - 1)) / columns;
          final tileHeight = tileWidth * 9 / 16;
          final apps = _apps.apps;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(padding, 24, padding, 16),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    l10n.kostvAllApps,
                    style: TextStyle(
                      color: AppColorScheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(padding, 0, padding, 48),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: tileWidth / tileHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: apps.length + 1,
                    (context, index) {
                      if (index == 0) {
                        return _AppGridTile(
                          autofocus: true,
                          width: tileWidth,
                          height: tileHeight,
                          icon: Icons.settings_rounded,
                          label: l10n.kostvTvSettings,
                          onTap: () => unawaited(_apps.openSystemSettings()),
                        );
                      }
                      final app = apps[index - 1];
                      return _AppGridTile(
                        key: ValueKey(app.packageName),
                        width: tileWidth,
                        height: tileHeight,
                        app: app,
                        onTap: () => unawaited(_open(app)),
                        onLongPress: () => unawaited(_showMenu(app)),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(activeRoute: Destinations.apps, child: content),
    );
  }
}

/// One card of the grid, which looks after its own focus (a grid has no row
/// to do it for it).
class _AppGridTile extends StatefulWidget {
  const _AppGridTile({
    super.key,
    required this.width,
    required this.height,
    required this.onTap,
    this.app,
    this.icon,
    this.label,
    this.onLongPress,
    this.autofocus = false,
  });

  final double width;
  final double height;
  final InstalledApp? app;
  final IconData? icon;
  final String? label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;

  @override
  State<_AppGridTile> createState() => _AppGridTileState();
}

class _AppGridTileState extends State<_AppGridTile> with FocusStateMixin {
  final _selectKeys = LongPressSelectKeyHandler();

  @override
  void dispose() {
    _selectKeys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onLongPress = widget.onLongPress;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: setFocused,
      onKeyEvent: (_, event) {
        if (onLongPress != null) {
          final handled = _selectKeys.handleKeyEvent(
            event,
            onTap: widget.onTap,
            onLongPress: onLongPress,
          );
          if (handled != KeyEventResult.ignored) return handled;
          if (event is KeyDownEvent && event.logicalKey.isContextMenuKey) {
            onLongPress();
            return KeyEventResult.handled;
          }
        } else if (isActivateKey(event)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setHovered(true),
        onExit: (_) => setHovered(false),
        child: GestureDetector(
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: AnimatedScale(
            scale: showFocusBorder ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: AppTile(
              width: widget.width,
              height: widget.height,
              focused: showFocusBorder,
              focusColor: focusColor,
              app: widget.app,
              icon: widget.icon,
              label: widget.label,
              onTap: widget.onTap,
            ),
          ),
        ),
      ),
    );
  }
}
