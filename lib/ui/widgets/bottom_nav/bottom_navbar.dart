import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import '../../navigation/kostv_menu_controller.dart';
import '../adaptive/sf_symbol.dart';
import '../kostv_menu/kostv_glass.dart';
import '../kostv_menu/kostv_more_sheet.dart';
import '../kostv_menu/kostv_nav_avatar.dart';
import '../music/design/kostv_music_tokens.dart';
import 'bottom_mini_player.dart';
import 'bottom_nav_destinations.dart';
import 'bottom_nav_metrics.dart';
import 'bottom_nav_model.dart';

/// How much of the bottom of the screen the bottom navbar covers, for content
/// that scrolls underneath it. Only present while the bottom navbar is.
class BottomNavInsetScope extends InheritedWidget {
  final double height;

  const BottomNavInsetScope({
    super.key,
    required this.height,
    required super.child,
  });

  static double? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BottomNavInsetScope>()
      ?.height;

  @override
  bool updateShouldNotify(BottomNavInsetScope oldWidget) =>
      height != oldWidget.height;
}

/// How much of the bottom of the screen is covered. That's the bottom navbar
/// on screens that show it and the OS navigation buttons or home indicator
/// everywhere else. The bar's height already includes the system inset.
double bottomContentInset(BuildContext context) =>
    BottomNavInsetScope.maybeOf(context) ??
    MediaQuery.paddingOf(context).bottom;

/// Bottom padding for a scrollable that may run under the bottom navbar:
/// [fallback] where there is no bar, otherwise enough to clear it.
double bottomNavContentPadding(BuildContext context, double fallback) {
  final inset = BottomNavInsetScope.maybeOf(context);
  if (inset == null) return fallback;
  final clear = inset + 16;
  return clear > fallback ? clear : fallback;
}

/// Builds [builder] with [bottomNavContentPadding] read where the scrollable
/// actually sits. Screens often build their lists from their own context,
/// which is above the layout that provides the inset.
class BottomNavPadded extends StatelessWidget {
  final double fallback;
  final Widget Function(BuildContext context, double bottom) builder;

  const BottomNavPadded({
    super.key,
    required this.fallback,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) =>
      builder(context, bottomNavContentPadding(context, fallback));
}

/// Kos TV: the menu of phones and tablets (docs/diseno-menu, «cristal
/// líquido»): a floating glass bar with every tab named (Inicio · Descubrir ·
/// Música · Tú) and Search in a round glass button beside it. What sounds
/// floats in its own glass above the bar. While the person scrolls down the
/// bar gathers ([minimized]): the page's tab in a circle, the music in the
/// middle and Search; scrolling up or tapping the circle opens it again.
/// A long press on «Tú» opens «Más».
///
/// On a tablet the bar is compact and centred, with each tab's icon and name
/// side by side ([BottomNavMetrics.isTablet]).
class BottomNavbar extends StatefulWidget {
  final String? activeRoute;

  /// False while the screen hides its navigation chrome. The tabs go and the
  /// mini player stays.
  final bool chromeVisible;

  /// Drawn above the bar, like the download progress strip.
  final Widget? header;

  /// Whether the bar is gathered while the person scrolls.
  final ValueListenable<bool>? minimized;

  /// Asks the layout to open the gathered bar again.
  final VoidCallback? onExpand;

  const BottomNavbar({
    super.key,
    this.activeRoute,
    this.chromeVisible = true,
    this.header,
    this.minimized,
    this.onExpand,
  });

  /// Room the bar takes along the bottom of the screen, system inset and mini
  /// player included.
  static double heightFor(BuildContext context, {bool? miniPlayer}) =>
      BottomNavMetrics.heightFor(
        bottomInset: MediaQuery.paddingOf(context).bottom,
        miniPlayer: miniPlayer ?? bottomMiniPlayerHasTrack(),
      );

  @override
  State<BottomNavbar> createState() => _BottomNavbarState();
}

class _BottomNavbarState extends State<BottomNavbar> {
  final _menu = KostvMenuController();
  final _subs = <StreamSubscription>[];
  bool _hasTrack = false;

  static const _duration = Duration(milliseconds: 300);
  static const _curve = Curves.easeOutCubic;

  @override
  void initState() {
    super.initState();
    _menu.addListener(_onChanged);
    _hasTrack = bottomMiniPlayerHasTrack();
    final playback = GetIt.instance<PlaybackManager>();
    _subs.addAll([
      playback.state.playingStream.listen((_) => _onPlaybackChanged()),
      playback.queueService.queueChangedStream.listen(
        (_) => _onPlaybackChanged(),
      ),
    ]);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onPlaybackChanged() {
    final hasTrack = bottomMiniPlayerHasTrack();
    if (hasTrack != _hasTrack && mounted) setState(() => _hasTrack = hasTrack);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _menu
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onTap(BottomNavBarItem item) {
    final route = widget.activeRoute ?? '';
    HapticFeedback.selectionClick();
    switch (item.kind) {
      case BottomNavItemKind.home:
        openBottomNavHome(context, alreadyHome: route == Destinations.home);
      case BottomNavItemKind.tab:
        // Its page decides: already on it, nothing; on a page opened
        // inside it, back to it; elsewhere, it opens.
        openBottomNavTab(context, item.tab!);
      case BottomNavItemKind.you:
        if (route != Destinations.kostvYou) {
          openBottomNavPage(context, Destinations.kostvYou);
        }
    }
  }

  void _onSearch() {
    HapticFeedback.selectionClick();
    if (widget.activeRoute != Destinations.search) {
      openBottomNavPage(context, Destinations.search);
    }
  }

  void _showMore() {
    HapticFeedback.mediumImpact();
    showKostvMoreSheet(context: context, menu: _menu);
  }

  String _label(AppLocalizations l10n, BottomNavBarItem item) =>
      switch (item.kind) {
        BottomNavItemKind.home => l10n.home,
        BottomNavItemKind.tab => bottomNavTabLabel(l10n, item.tab!),
        BottomNavItemKind.you => l10n.navYou,
      };

  Widget _icon(BottomNavBarItem item, bool active, double size, Color color) =>
      switch (item.kind) {
        BottomNavItemKind.home => AdaptiveIcon(
          active ? Icons.home_rounded : Icons.home_outlined,
          size: size,
          color: color,
        ),
        BottomNavItemKind.tab => bottomNavTabIconWidget(
          item.tab!,
          active: active,
          size: size,
          color: color,
        ),
        BottomNavItemKind.you => KostvNavAvatar(
          size: BottomNavMetrics.avatarSize,
          imageUrl: _menu.userImageUrl,
          name: _menu.userName,
          dot: _menu.youBadge > 0,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = _menu.barItems();
    final active = activeBarIndex(items, widget.activeRoute);
    final padding = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final tablet = BottomNavMetrics.isTablet(size);
    final horizontalInset =
        padding.left > padding.right ? padding.left : padding.right;
    final bottom = BottomNavMetrics.floatingBottomGap(padding.bottom);

    Widget bar(bool minimized) => _GlassBarRow(
      items: items,
      active: active,
      tablet: tablet,
      minimized: minimized,
      tabsVisible: widget.chromeVisible,
      hasTrack: _hasTrack,
      labelOf: (item) => _label(l10n, item),
      iconOf: _icon,
      searchLabel: l10n.search,
      searchActive: widget.activeRoute == Destinations.search,
      youHint: l10n.kostvMenuYouHint,
      onTap: (i) => _onTap(items[i]),
      onSearch: _onSearch,
      onMore: _showMore,
      onExpand: widget.onExpand,
    );

    final minimized = widget.minimized;
    final content = minimized == null
        ? bar(false)
        : ValueListenableBuilder<bool>(
            valueListenable: minimized,
            builder: (_, gathered, _) => bar(gathered),
          );

    // A tablet's bar and mini player keep to the middle, as wide as the bar
    // and Search together.
    final width = tablet
        ? BottomNavMetrics.tabletBarWidth +
              BottomNavMetrics.gap +
              BottomNavMetrics.barHeight
        : double.infinity;
    final side = BottomNavMetrics.side + horizontalInset;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.header,
        Padding(
          padding: EdgeInsets.fromLTRB(side, 0, side, bottom),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: AnimatedSize(
                duration: _duration,
                curve: _curve,
                alignment: Alignment.bottomCenter,
                child: content,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The bar itself, open or gathered, with the mini player.
class _GlassBarRow extends StatelessWidget {
  const _GlassBarRow({
    required this.items,
    required this.active,
    required this.tablet,
    required this.minimized,
    required this.tabsVisible,
    required this.hasTrack,
    required this.labelOf,
    required this.iconOf,
    required this.searchLabel,
    required this.searchActive,
    required this.youHint,
    required this.onTap,
    required this.onSearch,
    required this.onMore,
    required this.onExpand,
  });

  final List<BottomNavBarItem> items;
  final int? active;
  final bool tablet;
  final bool minimized;
  final bool tabsVisible;
  final bool hasTrack;
  final String Function(BottomNavBarItem item) labelOf;
  final Widget Function(
    BottomNavBarItem item,
    bool active,
    double size,
    Color color,
  )
  iconOf;
  final String searchLabel;
  final bool searchActive;
  final String youHint;
  final ValueChanged<int> onTap;
  final VoidCallback onSearch;
  final VoidCallback onMore;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final gathered = minimized && tabsVisible;
    final player = hasTrack
        ? KostvGlass(
            key: const ValueKey('kostvBarPlayer'),
            child: SizedBox(
              height: gathered
                  ? BottomNavMetrics.collapsedSize
                  : BottomNavMetrics.accessoryHeight,
              child: BottomMiniPlayer(
                variant: gathered
                    ? BottomMiniPlayerVariant.inline
                    : BottomMiniPlayerVariant.capsule,
              ),
            ),
          )
        : null;

    if (gathered) {
      const s = BottomNavMetrics.collapsedSize;
      final index = active ?? 0;
      final item = items[index];
      return Row(
        key: const ValueKey('kostvBarGathered'),
        children: [
          _RoundGlassButton(
            key: const ValueKey('kostvBarGatheredTab'),
            size: s,
            label: labelOf(item),
            onTap: onExpand,
            child: iconOf(item, true, 25, KostvMusicTokens.ink),
          ),
          const SizedBox(width: 8),
          Expanded(child: player ?? const SizedBox.shrink()),
          const SizedBox(width: 8),
          _RoundGlassButton(
            size: s,
            label: searchLabel,
            onTap: onSearch,
            child: AdaptiveIcon(
              Icons.search_rounded,
              size: 25,
              color: KostvMusicTokens.ink,
            ),
          ),
        ],
      );
    }

    final tabs = Row(
      children: [
        Expanded(
          child: KostvGlass(
            child: SizedBox(
              height: BottomNavMetrics.barHeight,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _GlassTab(
                          key: ValueKey('kostvBarTab-${items[i].id}'),
                          label: labelOf(items[i]),
                          active: i == active,
                          tablet: tablet,
                          icon: (on, size, color) =>
                              iconOf(items[i], on, size, color),
                          hint: items[i].kind == BottomNavItemKind.you
                              ? youHint
                              : null,
                          onTap: () => onTap(i),
                          onLongPress:
                              items[i].kind == BottomNavItemKind.you
                              ? onMore
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: BottomNavMetrics.gap),
        _RoundGlassButton(
          key: const ValueKey('kostvBarSearch'),
          size: BottomNavMetrics.barHeight,
          label: searchLabel,
          selected: searchActive,
          onTap: onSearch,
          child: AdaptiveIcon(
            Icons.search_rounded,
            size: 26,
            color: searchActive
                ? KostvMusicTokens.ink
                : KostvMusicTokens.ink.withValues(alpha: 0.9),
          ),
        ),
      ],
    );

    return Column(
      key: const ValueKey('kostvBarOpen'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (player != null) ...[
          player,
          const SizedBox(height: BottomNavMetrics.gap),
        ],
        AnimatedOpacity(
          opacity: tabsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(ignoring: !tabsVisible, child: tabs),
        ),
      ],
    );
  }
}

/// One tab of the glass bar: the icon with its name under it (beside it on
/// a tablet). The page you are on sits in the lighter pill with the
/// gradient rim.
class _GlassTab extends StatelessWidget {
  const _GlassTab({
    super.key,
    required this.label,
    required this.active,
    required this.tablet,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.hint,
  });

  final String label;
  final bool active;
  final bool tablet;
  final Widget Function(bool active, double size, Color color) icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Colors.white
        : KostvMusicTokens.ink.withValues(alpha: 0.78);
    // Names share a narrow cell, so a large text setting shrinks them to fit
    // rather than pushing the icon out of the bar.
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.15);
    final text = Text(
      label,
      maxLines: 1,
      textScaler: textScaler,
      style: TextStyle(
        color: color,
        fontSize: tablet ? 14 : 10.5,
        height: 1.1,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        decoration: TextDecoration.none,
      ),
    );
    final face = tablet
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon(active, 22, color),
              const SizedBox(width: 7),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: text)),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon(active, BottomNavMetrics.iconSize, color),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: text),
            ],
          );
    return Semantics(
      button: true,
      selected: active,
      label: label,
      hint: hint,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              Positioned.fill(
                child: tablet
                    ? Center(
                        child: SizedBox(
                          height: 52,
                          child: _PillAround(child: face),
                        ),
                      )
                    : const KostvActivePill(),
              ),
            if (!(active && tablet))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: face,
              ),
          ],
        ),
      ),
    );
  }
}

/// The tablet's active pill, hugging the tab's icon and name.
class _PillAround extends StatelessWidget {
  const _PillAround({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: KostvActivePill()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Center(widthFactor: 1, child: child),
        ),
      ],
    );
  }
}

/// A round glass button: Search, and the gathered bar's tab.
class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    super.key,
    required this.size,
    required this.label,
    required this.child,
    this.onTap,
    this.selected = false,
  });

  final double size;
  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: KostvGlass(
              child: Stack(
                children: [
                  if (selected) const Positioned.fill(child: KostvActivePill()),
                  Center(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
