import 'dart:async';
import 'dart:math' as math;

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
import '../../widgets/apps/app_accent_color.dart';
import '../../widgets/apps/app_tile.dart';
import '../../widgets/apps/apps_ambient_background.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import '../downloads/widgets/saved_media_menu.dart';

/// Kos TV: every app installed on the TV, like a launcher's app drawer. The
/// first card opens the TV's own settings (the TV's Settings app isn't listed
/// again). A long press (or the menu key) on an app adds it to the Apps row
/// on Home or takes it off.
///
/// The background takes on the colour of the focused app and the cards come
/// in one after another when the screen opens.
class AllAppsScreen extends StatefulWidget {
  const AllAppsScreen({super.key});

  @override
  State<AllAppsScreen> createState() => _AllAppsScreenState();
}

class _AllAppsScreenState extends State<AllAppsScreen>
    with SingleTickerProviderStateMixin {
  final InstalledAppsService _apps = GetIt.instance<InstalledAppsService>();

  /// The colour of the focused app and where it is, for the background.
  final _ambience = ValueNotifier(
    const AppsAmbience(color: AppAccentColors.neutral),
  );
  InstalledApp? _focused;
  int _columns = 1;

  /// The cards coming in, once, when the list is first there.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  /// Animations turned off on the device: the cards are just there.
  bool _still = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _apps.addListener(_onAppsChanged);
    unawaited(_apps.refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _startOnceLoaded();
  }

  @override
  void dispose() {
    _apps.removeListener(_onAppsChanged);
    _ambience.dispose();
    _entrance.dispose();
    super.dispose();
  }

  void _onAppsChanged() {
    if (!mounted) return;
    _startOnceLoaded();
    setState(() {});
  }

  /// Once the list is there: the cards come in and their colours are read.
  void _startOnceLoaded() {
    if (!_apps.isLoaded || _started) return;
    _started = true;
    if (_still) {
      _entrance.value = 1;
    } else {
      _comeInOnceShown();
    }
    unawaited(_readAccents(_apps.apps));
  }

  /// The cards come in once the screen has faded in (they would be lost in
  /// the fade otherwise), from the frame after, so a slow first frame doesn't
  /// eat into it.
  void _comeInOnceShown() {
    final route = ModalRoute.of(context)?.animation;
    void start() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _entrance.isDismissed) unawaited(_entrance.forward());
      });
    }

    if (route == null || route.isCompleted) {
      start();
      return;
    }
    void onStatus(AnimationStatus status) {
      if (!status.isCompleted) return;
      route.removeStatusListener(onStatus);
      start();
    }

    route.addStatusListener(onStatus);
  }

  /// Reads every app's colour ahead, one after another, so the background is
  /// ready as the focus gets to each.
  Future<void> _readAccents(List<InstalledApp> apps) async {
    for (final app in apps) {
      if (!mounted) return;
      await AppAccentColors.of(app);
    }
  }

  /// The focus is on the card at [index]: [app], or the TV settings card
  /// when null.
  void _onTileFocused(int index, InstalledApp? app) {
    _focused = app;
    final column = index % _columns;
    final across = _columns > 1 ? column / (_columns - 1) : 0.0;
    void show(Color? color) => _ambience.value = AppsAmbience(
      color: color ?? AppAccentColors.neutral,
      across: across,
    );
    if (app == null) {
      show(null);
      return;
    }
    if (AppAccentColors.isKnown(app)) {
      show(AppAccentColors.cached(app));
      return;
    }
    // Moves over at once in the old colour, then takes on the new one.
    show(_ambience.value.color);
    unawaited(
      AppAccentColors.of(app).then((color) {
        if (mounted && identical(_focused, app)) show(color);
      }),
    );
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
      // The same room around the navigation bar as Calendar leaves.
      final insets = calendarChromeInsets(context);
      content = LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 20.0;
          final usable = constraints.maxWidth - insets.left - insets.right;
          final columns = (usable / 260).floor().clamp(2, 8);
          _columns = columns;
          final tileWidth = (usable - spacing * (columns - 1)) / columns;
          final tileHeight = tileWidth * 9 / 16;
          final apps = _apps.apps;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  insets.left,
                  insets.top,
                  insets.right,
                  16,
                ),
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
                padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 48),
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
                      final Widget tile;
                      if (index == 0) {
                        tile = _AppGridTile(
                          autofocus: true,
                          width: tileWidth,
                          height: tileHeight,
                          icon: Icons.settings_rounded,
                          label: l10n.kostvTvSettings,
                          onTap: () => unawaited(_apps.openSystemSettings()),
                          onFocused: () => _onTileFocused(index, null),
                        );
                      } else {
                        final app = apps[index - 1];
                        tile = _AppGridTile(
                          key: ValueKey(app.packageName),
                          width: tileWidth,
                          height: tileHeight,
                          app: app,
                          onTap: () => unawaited(_open(app)),
                          onLongPress: () => unawaited(_showMenu(app)),
                          onFocused: () => _onTileFocused(index, app),
                        );
                      }
                      return _Entrance(
                        animation: _entrance,
                        // Row by row, then along it, so they come in like a
                        // wave from the top corner.
                        order: index ~/ columns + index % columns,
                        child: tile,
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
      body: NavigationLayout(
        activeRoute: Destinations.apps,
        // The arrows move between cards, as on the Live TV guide; on the web
        // they would otherwise scroll the page.
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
              TraversalDirection.up,
            ),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                DirectionalFocusIntent(TraversalDirection.left),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                DirectionalFocusIntent(TraversalDirection.right),
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppsAmbientBackground(ambience: _ambience),
              content,
            ],
          ),
        ),
      ),
    );
  }
}

/// A card coming in: it fades in and rises a little, [order] steps after the
/// first.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.animation,
    required this.order,
    required this.child,
  });

  final Animation<double> animation;
  final int order;
  final Widget child;

  static const _step = 0.05;
  static const _span = 0.5;

  @override
  Widget build(BuildContext context) {
    final start = math.min(order * _step, 1 - _span);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(
          ((animation.value - start) / _span).clamp(0.0, 1.0),
        );
        // The same widgets all along, so the card keeps its state (and its
        // focus) when it has come in.
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: child,
          ),
        );
      },
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
    this.onFocused,
    this.autofocus = false,
  });

  final double width;
  final double height;
  final InstalledApp? app;
  final IconData? icon;
  final String? label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocused;
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
      onFocusChange: (focused) {
        setFocused(focused);
        if (focused) widget.onFocused?.call();
      },
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
        onEnter: (_) {
          setHovered(true);
          widget.onFocused?.call();
        },
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
              wideGlow: true,
            ),
          ),
        ),
      ),
    );
  }
}
