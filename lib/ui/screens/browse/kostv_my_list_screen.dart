import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_my_list.dart';
import '../../../data/services/user_data_sync.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../navigation/route_lifecycle_observer.dart';
import '../../widgets/focus/context_menu_sheet.dart';
import '../../widgets/focus/locked_focus_row.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../calendar/calendar_common.dart';
import '../home/home_row_card_image.dart';
import '../home/kostv_undo_toast.dart';

/// Kos TV: the person's list («Mi lista») in three rows: what they are part
/// way through, what they haven't started and what they have watched, with a
/// card at the end of the last to clear it out.
class KostvMyListScreen extends StatefulWidget {
  const KostvMyListScreen({super.key});

  @override
  State<KostvMyListScreen> createState() => _KostvMyListScreenState();
}

enum _Part { watching, toStart, watched }

/// The card that clears the watched ones, at the end of their row.
const _clearCard = AggregatedItem(id: 'kostv_clear', serverId: '', rawData: {});

class _KostvMyListScreenState extends State<KostvMyListScreen> with RouteAware {
  final _list = GetIt.instance<KostvMyListService>();
  final _prefs = GetIt.instance<UserPreferences>();
  final _scroll = ScrollController();
  final Map<_Part, GlobalKey<LockedFocusRowState<AggregatedItem>>> _rowKeys = {
    for (final part in _Part.values) part: GlobalKey(),
  };
  final Map<_Part, GlobalKey> _sectionKeys = {
    for (final part in _Part.values) part: GlobalKey(),
  };
  final _firstFocus = FocusNode(debugLabel: 'kostvMyListFirst');
  bool _loading = true;
  bool _failed = false;

  /// Kos TV: the rows shown at the last change, to tell which went away.
  List<_Part> _lastShown = const [];

  /// Kos TV: the page reads the list again when what it shows was watched
  /// or started elsewhere (the player, a card's menu, another device), a
  /// moment after the last change, since a title can move to another row.
  Timer? _syncDebounce;
  ModalRoute<dynamic>? _observedRoute;

  /// Whether a page is pushed over this one, and whether something changed
  /// meanwhile, so it reads the list once on the way back.
  bool _covered = false;
  bool _staleWhileCovered = false;

  /// What [userDataSync] had told when the page last looked, so only what
  /// changed since counts.
  int _seenRevision = userDataSync.revision;

  @override
  void initState() {
    super.initState();
    _list.addListener(_onChanged);
    userDataSync.addListener(_onUserData);
    final page = _list.page;
    if (page != null) _lastShown = _shown(page);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || route == _observedRoute) return;
    if (_observedRoute != null) routeLifecycleObserver.unsubscribe(this);
    _observedRoute = route;
    routeLifecycleObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    if (_observedRoute != null) routeLifecycleObserver.unsubscribe(this);
    _syncDebounce?.cancel();
    _list.removeListener(_onChanged);
    userDataSync.removeListener(_onUserData);
    _scroll.dispose();
    _firstFocus.dispose();
    super.dispose();
  }

  @override
  void didPushNext() => _covered = true;

  @override
  void didPopNext() {
    _covered = false;
    if (!_staleWhileCovered) return;
    _staleWhileCovered = false;
    unawaited(_list.load());
  }

  void _onChanged() {
    if (!mounted) return;
    final page = _list.page;
    final shown = page == null ? const <_Part>[] : _shown(page);
    final gone = [
      for (final part in _lastShown)
        if (!shown.contains(part) &&
            (_rowKeys[part]?.currentState?.hasFocusedItem ?? false))
          part,
    ];
    final before = _lastShown;
    _lastShown = shown;
    setState(() {});
    // Kos TV: the row holding the focus went away (its last title left it):
    // the focus goes to the row next to it, or up to the menu, rather than
    // being lost with the row. Only with the remote or the keyboard: a touch
    // leaves no focus to move, and moving it would scroll the page.
    if (gone.isNotEmpty && InputModeTracker.of(context) == InputMode.keyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNear(before, gone.first);
      });
    }
  }

  /// Puts the focus on the row shown nearest to where [gone] was in
  /// [before]: the one above, else the one below, else the menu.
  void _focusNear(List<_Part> before, _Part gone) {
    final page = _list.page;
    final shown = page == null ? const <_Part>[] : _shown(page);
    final at = before.indexOf(gone);
    final above = [
      for (final part in before.take(at < 0 ? 0 : at).toList().reversed)
        if (shown.contains(part)) part,
    ];
    final below = [
      for (final part in before.skip(at + 1))
        if (shown.contains(part)) part,
    ];
    final target = above.firstOrNull ?? below.firstOrNull;
    final row = target == null ? null : _rowKeys[target]?.currentState;
    if (row != null) {
      row.requestFocusAt(0);
    } else {
      NavigationLayout.focusNavbarNotifier.value?.call();
    }
  }

  /// Kos TV: something this page shows was watched, started or marked: its
  /// card is painted with it now, and the list is read again in a moment to
  /// put it in its row (or once back, when a page covers this one).
  void _onUserData() {
    if (!mounted) return;
    final page = _list.page;
    final seen = _seenRevision;
    _seenRevision = userDataSync.revision;
    if (page == null) return;
    final touched = _Part.values.any(
      (part) => _raw(
        page,
        part,
      ).any((item) => userDataSync.revisionFor(item.id) > seen),
    );
    if (!touched) return;
    setState(() {});
    if (_covered) {
      _staleWhileCovered = true;
      return;
    }
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) unawaited(_list.load());
    });
  }

  Future<void> _load() async {
    final page = await _list.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = page == null && _list.page == null;
    });
  }

  /// Kos TV: with the newest watched and favourite state this client knows,
  /// so a card shows what was just done to it and its menu offers the rest.
  List<AggregatedItem> _items(KostvMyListPage page, _Part part) =>
      userDataSync.applyAll(_raw(page, part));

  /// The part as the plugin sent it.
  List<AggregatedItem> _raw(KostvMyListPage page, _Part part) => switch (part) {
    _Part.watching => page.watching,
    _Part.toStart => page.toStart,
    _Part.watched => page.watched,
  };

  List<_Part> _shown(KostvMyListPage page) => [
    for (final part in _Part.values)
      if (_items(page, part).isNotEmpty) part,
  ];

  void _open(AggregatedItem item) {
    if (identical(item, _clearCard)) {
      unawaited(_clearWatched());
      return;
    }
    context.push(Destinations.item(item.id, serverId: item.serverId));
  }

  /// Kos TV: the watched ones leave at once and a notice offers a few
  /// seconds to take it back, as «Not interested» does on Home; only then
  /// is the server told. The row goes with the focus in it, which moves to
  /// the row above, or up to the menu (see [_onChanged]).
  Future<void> _clearWatched() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final remote = InputModeTracker.of(context) == InputMode.keyboard;
    final page = _list.page;
    final before = page == null ? const <_Part>[] : _shown(page);
    var undone = false;
    final done = _list.clearWatchedLater();

    showKostvUndoToast(
      context,
      message: l10n.kostvMyListCleared,
      undoLabel: l10n.kostvUndo,
      duration: KostvMyListService.clearUndoTime,
      takeFocus: remote,
      onUndo: () {
        undone = true;
        _list.undoClearWatched();
        if (!remote) return;
        // Back on the card that cleared them.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final watched = _list.page?.watched.length ?? 0;
          _rowKeys[_Part.watched]?.currentState?.requestFocusAt(watched);
        });
      },
      onLeave: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNear(before, _Part.watched);
        });
      },
    );

    final cleared = await done;
    if (!cleared && !undone) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.kostvMyListChangeFailed)),
      );
    }
  }

  /// Kos TV: a card's menu changed something (watched, its list): the list is
  /// read again so the title moves to its row.
  void _reloadAfterMenu() => unawaited(_list.load());

  /// A remote moving between rows: the next one shown, or the bar above.
  bool _onVertical(KostvMyListPage page, _Part part, bool isUp) {
    final shown = _shown(page);
    final at = shown.indexOf(part) + (isUp ? -1 : 1);
    if (at < 0) {
      NavigationLayout.focusNavbarNotifier.value?.call();
      return true;
    }
    if (at >= shown.length) return true;
    final next = shown[at];
    _rowKeys[next]?.currentState?.requestFocusAt(0);
    final section = _sectionKeys[next]?.currentContext;
    if (section != null) {
      unawaited(
        Scrollable.ensureVisible(
          section,
          alignment: 0.1,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final page = _list.page;
    final phone = PlatformDetection.useMobileUi;
    Widget body;
    if (page == null && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (page == null || _failed) {
      body = _message(
        icon: Icons.cloud_off_rounded,
        title: AppLocalizations.of(context).kostvMyListUnavailable,
        retry: true,
      );
    } else if (page.isEmpty) {
      body = _message(
        icon: Icons.bookmark_border_rounded,
        title: AppLocalizations.of(context).kostvMyListEmpty,
        text: AppLocalizations.of(context).kostvMyListEmptyHint,
      );
    } else {
      body = _rows(context, page);
    }
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.myList,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A faint glow of the list's colour from the top corner.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.9, -1.1),
                  radius: 1.4,
                  colors: [
                    Color(0x33F472B6),
                    Color(0x0AF472B6),
                    Color(0x00000000),
                  ],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            phone || page == null || page.isEmpty
                ? body
                : RequestInitialFocus(targetNode: _firstFocus, child: body),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, KostvMyListPage? page) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = page == null
        ? 0
        : page.watching.length + page.toStart.length + page.watched.length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF472B6).withValues(alpha: 0.16),
            borderRadius: AppRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF472B6).withValues(alpha: 0.4),
            ),
          ),
          child: const Icon(
            Icons.bookmark_rounded,
            color: Color(0xFFF472B6),
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.kostvMyList,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: AppColorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (count > 0)
                Text(
                  l10n.kostvMyListCount(count),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    String? text,
    bool retry = false,
  }) {
    final theme = Theme.of(context);
    final insets = calendarChromeInsets(context);
    return Padding(
      padding: insets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, null),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 56,
                      color: AppColorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (text != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        text,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                    if (retry) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        autofocus: !PlatformDetection.useMobileUi,
                        onPressed: () {
                          setState(() => _loading = true);
                          unawaited(_load());
                        },
                        child: Text(AppLocalizations.of(context).retry),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rows(BuildContext context, KostvMyListPage page) {
    final insets = calendarChromeInsets(context);
    final phone = PlatformDetection.useMobileUi;
    final shown = _shown(page);
    final bottom =
        MediaQuery.paddingOf(context).bottom +
        (phone && NavigationLayout.usesBottomNavbar ? 96 : 32);
    return SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.only(top: insets.top, bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: insets.left, right: insets.right),
            child: _header(context, page),
          ),
          SizedBox(height: phone ? 12 : 20),
          for (final part in shown)
            _section(
              context,
              page,
              part,
              insets: insets,
              first: part == shown.first,
            ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    KostvMyListPage page,
    _Part part, {
    required EdgeInsets insets,
    required bool first,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final phone = PlatformDetection.useMobileUi;
    final wide = part == _Part.watching;
    final imageHeight = phone ? (wide ? 118.0 : 165.0) : (wide ? 162.0 : 228.0);
    final aspect = wide ? 16 / 9 : 2 / 3;
    final cardWidth = imageHeight * aspect;
    final spacing = phone ? 12.0 : 20.0;
    final expansion = !phone && _prefs.get(UserPreferences.cardFocusExpansion);
    // The focused card grows from its middle: room above it for that, so it
    // never covers the section's title.
    final headroom = expansion
        ? imageHeight * (MediaCard.focusScale - 1) + 22
        : 8.0;
    final labels = 54.0;
    final focusColor = Color(_prefs.get(UserPreferences.focusColor).colorValue);
    final items = [
      ..._items(page, part),
      if (part == _Part.watched) _clearCard,
    ];
    final (title, why, icon) = switch (part) {
      _Part.watching => (
        l10n.kostvMyListWatching,
        l10n.kostvMyListWatchingWhy,
        Icons.play_circle_outline_rounded,
      ),
      _Part.toStart => (
        l10n.kostvMyListToStart,
        l10n.kostvMyListToStartWhy,
        Icons.bookmark_add_outlined,
      ),
      _Part.watched => (
        l10n.kostvMyListWatched,
        l10n.kostvMyListWatchedWhy,
        Icons.check_circle_outline_rounded,
      ),
    };
    final client = GetIt.instance<MediaServerClient>();

    return Column(
      key: _sectionKeys[part],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(insets.left, 8, insets.right, 0),
          child: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFFF472B6)),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$title · ${_items(page, part).length}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      why,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        LockedFocusRow<AggregatedItem>(
          key: _rowKeys[part],
          hubKey: 'kostv_my_list_${part.name}',
          items: items,
          itemKey: (item, _) => item.id,
          focusNode: first ? _firstFocus : null,
          itemExtent: cardWidth,
          itemSpacing: spacing,
          height: headroom + imageHeight + labels + 12,
          clipBehavior: Clip.none,
          padding: EdgeInsets.fromLTRB(insets.left, headroom, insets.right, 12),
          onVerticalNavigation: (isUp) => _onVertical(page, part, isUp),
          onLeftEdge: () => NavigationLayout.focusNavbarNotifier.value?.call(),
          onTap: (_, item) => _open(item),
          onLongPress: (_, item) {
            if (identical(item, _clearCard)) return;
            showContextMenu(context, item, onChanged: _reloadAfterMenu);
          },
          itemBuilder: (context, item, index, focused) {
            final showFocus = InputModeTracker.showFocusVisuals(
              context,
              focused,
            );
            if (identical(item, _clearCard)) {
              return MediaCard(
                title: l10n.kostvMyListClearWatched,
                showLabel: true,
                width: cardWidth,
                aspectRatio: aspect,
                focusColor: focusColor,
                cardFocusExpansion: expansion,
                externalIsFocused: showFocus,
                onTap: () => _open(item),
                imageOverlays: [
                  // The card writes its title in the middle; the icon sits
                  // above it.
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 72),
                      child: Center(
                        child: Icon(
                          Icons.playlist_remove_rounded,
                          size: 40,
                          color: AppColorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            return MediaCard(
              title: item.name,
              subtitle: item.productionYear?.toString(),
              showLabel: true,
              imageUrl: resolveRowImageUrl(
                item,
                client.imageApi,
                imageHeight,
                wide ? ImageType.thumb : ImageType.poster,
                false,
                MediaQuery.devicePixelRatioOf(context),
              ),
              width: cardWidth,
              aspectRatio: aspect,
              itemType: item.type,
              isPlayed: item.isPlayed,
              unplayedCount: item.unplayedItemCount,
              playedPercentage: wide ? item.playedPercentage : null,
              watchedBehavior: _prefs.get(
                UserPreferences.watchedIndicatorBehavior,
              ),
              focusColor: focusColor,
              cardFocusExpansion: expansion,
              externalIsFocused: showFocus,
              onTap: () => _open(item),
              onLongPress: () =>
                  showContextMenu(context, item, onChanged: _reloadAfterMenu),
            );
          },
        ),
      ],
    );
  }
}
