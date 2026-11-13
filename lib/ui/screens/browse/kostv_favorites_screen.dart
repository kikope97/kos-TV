import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:playback_core/playback_core.dart' show PlaybackManager;
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/mdblist_repository.dart';
import '../../../data/services/background_service.dart';
import '../../../data/services/kostv_favorites_news.dart';
import '../../../data/viewmodels/favorites_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../navigation/playback_launcher.dart';
import '../../widgets/focus/context_menu_sheet.dart';
import '../../widgets/focus/locked_focus_row.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/focusable_dialog_row.dart';
import '../../widgets/fullscreen_backdrop_switcher.dart';
import '../../widgets/kostv_favorites_shortcut.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/overlay_sheet.dart';
import '../calendar/calendar_common.dart';
import '../home/home_row_card_image.dart';
import 'kostv_favorites_news_hero.dart';
import '../../../util/episode_code.dart';

/// Kos TV: the person's favourites («Mis favoritos»), with the menu above.
///
/// At the top, the heart, how many there are, and a bar to pick which kind
/// to see (all of them, or only films, series…) and the order. With «All»
/// there is a row for each kind, as on Home and on «Mi lista», each with its
/// icon and a line on what it holds; with one kind, all of it in a grid. The
/// artwork of the card in focus fades in behind the top of the page. Reached
/// from the profile: the heart beside the avatar, its menu, or «Tú» on
/// phones.
class KostvFavoritesScreen extends StatefulWidget {
  const KostvFavoritesScreen({super.key});

  @override
  State<KostvFavoritesScreen> createState() => _KostvFavoritesScreenState();
}

/// How a kind of favourite shows: its cards' shape and what the row says.
@immutable
class KostvFavoritesKind {
  const KostvFavoritesKind({
    required this.icon,
    required this.aspect,
    required this.imageType,
  });

  final IconData icon;

  /// Width over height of its cards.
  final double aspect;
  final ImageType imageType;

  static KostvFavoritesKind of(FavoriteTypeFilter type) => switch (type) {
    FavoriteTypeFilter.episode => const KostvFavoritesKind(
      icon: Icons.video_library_outlined,
      aspect: 16 / 9,
      imageType: ImageType.thumb,
    ),
    FavoriteTypeFilter.series => const KostvFavoritesKind(
      icon: Icons.live_tv_rounded,
      aspect: 2 / 3,
      imageType: ImageType.poster,
    ),
    FavoriteTypeFilter.collection => const KostvFavoritesKind(
      icon: Icons.collections_bookmark_outlined,
      aspect: 2 / 3,
      imageType: ImageType.poster,
    ),
    // People are drawn round, so their cards are square.
    FavoriteTypeFilter.person => const KostvFavoritesKind(
      icon: Icons.person_outline_rounded,
      aspect: 1,
      imageType: ImageType.poster,
    ),
    FavoriteTypeFilter.musicVideo => const KostvFavoritesKind(
      icon: Icons.music_video_outlined,
      aspect: 16 / 9,
      imageType: ImageType.thumb,
    ),
    FavoriteTypeFilter.musicArtist => const KostvFavoritesKind(
      icon: Icons.mic_none_rounded,
      aspect: 1,
      imageType: ImageType.poster,
    ),
    FavoriteTypeFilter.musicAlbum => const KostvFavoritesKind(
      icon: Icons.album_outlined,
      aspect: 1,
      imageType: ImageType.poster,
    ),
    FavoriteTypeFilter.audio => const KostvFavoritesKind(
      icon: Icons.music_note_outlined,
      aspect: 1,
      imageType: ImageType.poster,
    ),
    _ => const KostvFavoritesKind(
      icon: Icons.movie_outlined,
      aspect: 2 / 3,
      imageType: ImageType.poster,
    ),
  };

  /// The line under a row's title.
  static String why(FavoriteTypeFilter type, AppLocalizations l10n) =>
      switch (type) {
        FavoriteTypeFilter.movie => l10n.kostvFavoritesWhyMovie,
        FavoriteTypeFilter.series => l10n.kostvFavoritesWhySeries,
        FavoriteTypeFilter.episode => l10n.kostvFavoritesWhyEpisode,
        FavoriteTypeFilter.collection => l10n.kostvFavoritesWhyCollection,
        FavoriteTypeFilter.person => l10n.kostvFavoritesWhyPerson,
        _ => l10n.kostvFavoritesWhyMusic,
      };
}

/// Kos TV: an order the favourites can be put in, and the way it goes first.
@immutable
class KostvFavoritesOrder {
  const KostvFavoritesOrder(this.sortBy, this.direction, this.icon);

  /// Null for «Añadidos a favoritos», which the server plugin keeps.
  final LibrarySortBy? sortBy;

  /// The way that makes sense first: newest, most watched, A to Z…
  final SortDirection direction;
  final IconData icon;

  /// When each one was marked, newest first (needs the server plugin).
  static const favorited = KostvFavoritesOrder(
    null,
    SortDirection.descending,
    Icons.favorite_rounded,
  );

  static const all = [
    KostvFavoritesOrder(
      LibrarySortBy.dateAdded,
      SortDirection.descending,
      Icons.new_releases_outlined,
    ),
    KostvFavoritesOrder(
      LibrarySortBy.premiereDate,
      SortDirection.descending,
      Icons.event_outlined,
    ),
    KostvFavoritesOrder(
      LibrarySortBy.playCount,
      SortDirection.descending,
      Icons.local_fire_department_outlined,
    ),
    KostvFavoritesOrder(
      LibrarySortBy.datePlayed,
      SortDirection.descending,
      Icons.history_rounded,
    ),
    KostvFavoritesOrder(
      LibrarySortBy.communityRating,
      SortDirection.descending,
      Icons.star_outline_rounded,
    ),
    KostvFavoritesOrder(
      LibrarySortBy.name,
      SortDirection.ascending,
      Icons.sort_by_alpha_rounded,
    ),
    KostvFavoritesOrder(
      LibrarySortBy.runtime,
      SortDirection.descending,
      Icons.timer_outlined,
    ),
    KostvFavoritesOrder(
      LibrarySortBy.random,
      SortDirection.ascending,
      Icons.shuffle_rounded,
    ),
  ];

  /// The order for [sortBy], or the first one for one this page doesn't
  /// offer (left over from the old page).
  static KostvFavoritesOrder of(LibrarySortBy sortBy) =>
      all.where((o) => o.sortBy == sortBy).firstOrNull ?? all.first;

  /// The order [vm] is in.
  static KostvFavoritesOrder current(FavoritesViewModel vm) =>
      vm.byMarked ? favorited : of(vm.sortBy);

  /// The orders offered: «Añadidos a favoritos» only with the server plugin.
  static List<KostvFavoritesOrder> offered(FavoritesViewModel vm) => [
    if (vm.markedAvailable) favorited,
    ...all,
  ];

  String label(AppLocalizations l10n) => switch (sortBy) {
    null => l10n.kostvSortFavorited,
    LibrarySortBy.dateAdded => l10n.kostvSortDateAdded,
    LibrarySortBy.premiereDate => l10n.kostvSortPremiere,
    LibrarySortBy.playCount => l10n.kostvSortPlayCount,
    LibrarySortBy.datePlayed => l10n.kostvSortDatePlayed,
    LibrarySortBy.communityRating => l10n.kostvSortRating,
    LibrarySortBy.name => l10n.kostvSortName,
    LibrarySortBy.runtime => l10n.kostvSortRuntime,
    _ => l10n.kostvSortRandom,
  };
}

class _KostvFavoritesScreenState extends State<KostvFavoritesScreen> {
  final _prefs = GetIt.instance<UserPreferences>();
  late final FavoritesViewModel _vm;
  final _scroll = ScrollController();
  final Map<Object, GlobalKey<LockedFocusRowState<AggregatedItem>>> _rowKeys =
      {};
  final Map<Object, GlobalKey> _sectionKeys = {};
  final _firstChip = FocusNode(debugLabel: 'kostvFavoritesFirstChip');

  /// The bar's other pills, in order after [_firstChip].
  final List<FocusNode> _chipNodes = [];

  FocusNode _chipNode(int i) {
    while (_chipNodes.length <= i) {
      _chipNodes.add(FocusNode(debugLabel: 'kostvFavoritesChip$i'));
    }
    return _chipNodes[i];
  }

  final _firstRow = FocusNode(debugLabel: 'kostvFavoritesFirstRow');

  /// The kind shown on its own, or null for all of them in rows.
  FavoriteTypeFilter? _only;

  /// What was shown before a reload, kept on screen until the new rows come
  /// so changing the order doesn't blank the page.
  Map<FavoriteTypeFilter, List<AggregatedItem>> _lastRows = const {};

  /// The card in focus, whose artwork is behind the top of the page. Only
  /// the backdrop listens, so a step along a row doesn't rebuild the page.
  final _focused = ValueNotifier<AggregatedItem?>(null);

  /// The last list [_items] gave for each kind, given again while what it
  /// holds is the same, so the rows see the same list from build to build.
  final Map<FavoriteTypeFilter, List<AggregatedItem>> _shownItems = {};

  /// The column the grid's focus is in, kept moving up and down.
  int _gridColumn = 0;

  /// The news of the favourite series, when the server plugin keeps it.
  final KostvFavoritesNewsService? _news =
      GetIt.instance.isRegistered<KostvFavoritesNewsService>()
      ? GetIt.instance<KostvFavoritesNewsService>()
      : null;

  /// The series whose news came since the person last looked, kept marked
  /// while they're here though the alert goes once they open the page.
  Set<String> _fresh = const {};
  final _heroWatch = FocusNode(debugLabel: 'kostvFavoritesNewsWatch');
  final _newsRowKey = GlobalKey<LockedFocusRowState<KostvSeriesNews>>();
  final _newsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _vm = FavoritesViewModel(
      client: GetIt.instance<MediaServerClient>(),
      prefs: _prefs,
      mdbListRepository: GetIt.instance<MdbListRepository>(),
    );
    _vm.addListener(_onChanged);
    _news?.addListener(_onNews);
    unawaited(_readNews());
    // The page is always rows, whatever the old one was left on, and in an
    // order it offers.
    unawaited(_start());
  }

  Future<void> _start() async {
    await _vm.setViewStyle(FavoritesViewStyle.home, reload: false);
    // With the server plugin, the last one marked comes first, unless the
    // person picked another order since.
    if (_vm.byMarked) {
      final picked = _prefs.containsPreference(
        UserPreferences.kostvFavoritesByMarked,
      );
      if (!picked && _vm.sortDirection != SortDirection.descending) {
        await _vm.setByMarked(SortDirection.descending);
      } else {
        await _vm.load();
      }
      return;
    }
    // Someone who never picked one sees the newest in the library first.
    final chosen = _prefs.containsPreference(
      UserPreferences.librarySortBy('favorites'),
    );
    final order = chosen
        ? KostvFavoritesOrder.of(_vm.sortBy)
        : KostvFavoritesOrder.all.first;
    final sortBy = order.sortBy ?? LibrarySortBy.dateAdded;
    final reorder = !chosen || sortBy != _vm.sortBy;
    if (reorder) {
      await _vm.setSort(sortBy, order.direction);
    } else {
      await _vm.load();
    }
  }

  /// Reads the news afresh and, once on screen, takes the heart's alert off
  /// (here and on the person's other devices).
  Future<void> _readNews() async {
    final news = _news;
    if (news == null) return;
    _fresh = {
      for (final n in news.news)
        if (n.unseen) n.series.id,
    };
    await news.refresh(force: true);
    if (!mounted) return;
    _fresh = {
      ..._fresh,
      for (final n in news.news)
        if (n.unseen) n.series.id,
    };
    setState(() {});
    await news.markSeen();
  }

  void _onNews() {
    if (mounted) setState(() {});
  }

  /// The news shown: none on an old server plugin.
  List<KostvSeriesNews> get _newsNow {
    final news = _news;
    if (news == null || !news.available) return const [];
    return news.news;
  }

  @override
  void dispose() {
    _news?.removeListener(_onNews);
    _heroWatch.dispose();
    _focused.dispose();
    _vm.removeListener(_onChanged);
    _vm.dispose();
    _scroll.dispose();
    _firstChip.dispose();
    for (final node in _chipNodes) {
      node.dispose();
    }
    _firstRow.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    if (_vm.state == FavoritesState.ready) _lastRows = _vm.rowItems;
    setState(() {});
  }

  Map<FavoriteTypeFilter, List<AggregatedItem>> get _rowsNow =>
      _vm.state == FavoritesState.loading ? _lastRows : _vm.rowItems;

  /// What is still a favourite: one taken off here or elsewhere goes at once.
  List<AggregatedItem> _items(FavoriteTypeFilter type) {
    final items = [
      for (final item in _rowsNow[type] ?? const <AggregatedItem>[])
        if (item.isFavorite) item,
    ];
    final shown = _shownItems[type];
    if (shown != null && shown.length == items.length) {
      var same = true;
      for (var i = 0; i < items.length; i++) {
        if (!identical(shown[i], items[i])) {
          same = false;
          break;
        }
      }
      if (same) return shown;
    }
    return _shownItems[type] = items;
  }

  /// The kinds with something in them, in the page's order.
  List<FavoriteTypeFilter> _kinds() => [
    for (final type in FavoritesViewModel.rowTypes)
      if (type != FavoriteTypeFilter.watchlist && _items(type).isNotEmpty) type,
  ];

  /// How many of [type] there are, counting what isn't loaded yet.
  int _countOf(FavoriteTypeFilter type) =>
      _vm.rowTotalCount(type) -
      (_rowsNow[type]?.length ?? 0) +
      _items(type).length;

  void _open(AggregatedItem item) {
    context.push(
      Destinations.itemOrPhoto(
        item.id,
        serverId: item.serverId,
        type: item.type,
        channelId: item.channelId,
      ),
    );
  }

  void _focusOn(AggregatedItem item) {
    if (identical(item, _focused.value) || PlatformDetection.useMobileUi) {
      return;
    }
    _focused.value = item;
  }

  void _show(FavoriteTypeFilter? only) {
    if (only == _only) return;
    setState(() {
      _only = only;
      _gridColumn = 0;
    });
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Future<void> _pickOrder() async {
    final l10n = AppLocalizations.of(context);
    final current = KostvFavoritesOrder.current(_vm);
    final picked = await showFocusRestoringDialog<KostvFavoritesOrder>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1B1F27),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text(
                    l10n.kostvFavoritesSortTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final order in KostvFavoritesOrder.offered(_vm))
                          FocusableDialogRow(
                            icon: order == current
                                ? Icons.check_rounded
                                : order.icon,
                            label: order.label(l10n),
                            autofocus: order == current,
                            onTap: () => Navigator.of(context).pop(order),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final sortBy = picked.sortBy;
    unawaited(
      sortBy == null
          ? _vm.setByMarked(picked.direction)
          : _vm.setSort(sortBy, picked.direction),
    );
  }

  void _flipDirection() => unawaited(_vm.toggleSortDirection());

  /// Plays the first of a favourite series' new episodes.
  Future<void> _watch(AggregatedItem episode) async {
    final manager = GetIt.instance<PlaybackManager>();
    await launchPlayerWhilePreparing(
      context,
      manager: manager,
      destination: Destinations.videoPlayer,
      startPlayback: (launchSession) async {
        await runPlaybackStart(
          launchSession,
          () => manager.playItems([episode]),
        );
        return true;
      },
    );
  }

  /// Whether the row of news is on the page: in «Todo», with more news than
  /// the highlight's one.
  bool get _newsRowShown => _only == null && _newsNow.length > 1;

  /// Up from the bar: the news highlight, or the menu.
  void _aboveChips() {
    if (_newsNow.isEmpty) {
      NavigationLayout.focusNavbarNotifier.value?.call();
      return;
    }
    _heroWatch.requestFocus();
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _focusNewsRow() {
    _newsRowKey.currentState?.requestFocusAt(0);
    final section = _newsSectionKey.currentContext;
    if (section != null) {
      unawaited(
        Scrollable.ensureVisible(
          section,
          alignment: 0.15,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  /// Down from the bar: the news, the first row, or the grid's first line.
  void _intoContent() {
    final only = _only;
    if (_newsRowShown) {
      _focusNewsRow();
      return;
    }
    final first = _rowKeys[only == null ? _kinds().firstOrNull : (only, 0)];
    first?.currentState?.requestFocusAt(0);
  }

  /// A remote moving between rows: the next one shown, or the bar above.
  bool _onVertical(FavoriteTypeFilter type, bool isUp) {
    final shown = _kinds();
    final at = shown.indexOf(type) + (isUp ? -1 : 1);
    if (at < 0) {
      _newsRowShown ? _focusNewsRow() : _firstChip.requestFocus();
      return true;
    }
    if (at >= shown.length) return true;
    _focusRow(shown[at], 0);
    return true;
  }

  void _focusRow(Object key, int index) {
    _rowKeys[key]?.currentState?.requestFocusAt(index);
    final section = _sectionKeys[key]?.currentContext;
    if (section != null) {
      unawaited(
        Scrollable.ensureVisible(
          section,
          alignment: 0.15,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = PlatformDetection.useMobileUi;
    final kinds = _kinds();
    // A kind that emptied (everything taken off) goes back to all of them.
    if (_only != null &&
        !kinds.contains(_only) &&
        _vm.state != FavoritesState.loading) {
      _only = null;
    }
    Widget body;
    if (_vm.state == FavoritesState.loading && kinds.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_vm.state == FavoritesState.error && kinds.isEmpty) {
      body = _message(
        icon: Icons.cloud_off_rounded,
        title: l10n.kostvFavoritesUnavailable,
        retry: true,
      );
    } else if (kinds.isEmpty) {
      body = _message(
        icon: Icons.favorite_border_rounded,
        title: l10n.kostvFavoritesEmpty,
        text: l10n.kostvFavoritesEmptyHint,
      );
    } else {
      body = _page(context, kinds);
    }
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.allFavorites,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The artwork of the card in focus, behind the top of the page.
            if (!phone)
              Positioned.fill(
                child: ValueListenableBuilder<AggregatedItem?>(
                  valueListenable: _focused,
                  builder: (context, focused, _) {
                    final backdrop = _backdropUrl(focused);
                    return AnimatedOpacity(
                      opacity: backdrop == null ? 0 : 1,
                      duration: const Duration(milliseconds: 400),
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
                          stops: [0, 0.7],
                        ).createShader(rect),
                        child: FullscreenBackdropSwitcher(
                          imageUrl: backdrop,
                          duration: BackgroundService.transitionDuration,
                        ),
                      ),
                    );
                  },
                ),
              ),
            // A faint glow of the heart's colour from the top corner.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.9, -1.1),
                  radius: 1.4,
                  colors: [
                    Color(0x33F87171),
                    Color(0x0AF87171),
                    Color(0x00000000),
                  ],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            phone || kinds.isEmpty
                ? body
                : RequestInitialFocus(
                    targetNode: _newsNow.isEmpty ? _firstRow : _heroWatch,
                    child: body,
                  ),
          ],
        ),
      ),
    );
  }

  String? _backdropUrl(AggregatedItem? item) {
    if (item == null || !GetIt.instance.isRegistered<BackgroundService>()) {
      return null;
    }
    if (item.type == 'Person') return null;
    return GetIt.instance<BackgroundService>()
        .backdropUrlsFor(item)
        .firstOrNull;
  }

  Widget _header(BuildContext context, int count) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kostvFavoritesColor.withValues(alpha: 0.32),
                kostvFavoritesColor.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: AppRadius.circular(14),
            border: Border.all(
              color: kostvFavoritesColor.withValues(alpha: 0.45),
            ),
          ),
          child: const Icon(
            Icons.favorite_rounded,
            color: kostvFavoritesColor,
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.kostvMyFavorites,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: AppColorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (count > 0)
                Text(
                  l10n.kostvFavoritesCount(count),
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

  /// The bar under the header: which kind to see, and the order.
  Widget _controls(BuildContext context, List<FavoriteTypeFilter> kinds) {
    final l10n = AppLocalizations.of(context);
    final order = KostvFavoritesOrder.current(_vm);
    final descending = _vm.sortDirection == SortDirection.descending;
    final reloading = _vm.state == FavoritesState.loading;
    final sortable = order.sortBy != LibrarySortBy.random;
    // The pills after «All»: one per kind, the order and, but for random,
    // its direction.
    final chips = kinds.length + 1 + (sortable ? 1 : 0);
    var next = 0;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _intoContent();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _aboveChips();
          return KeyEventResult.handled;
        }
        // Along the bar, pill by pill, stopping at its ends.
        final left = event.logicalKey == LogicalKeyboardKey.arrowLeft;
        if (left || event.logicalKey == LogicalKeyboardKey.arrowRight) {
          final pills = [
            _firstChip,
            for (var i = 0; i < chips; i++) _chipNode(i),
          ];
          final at = pills.indexWhere((node) => node.hasFocus);
          if (at < 0) return KeyEventResult.ignored;
          final to = at + (left ? -1 : 1);
          if (to < 0) {
            NavigationLayout.focusNavbarNotifier.value?.call();
          } else if (to < pills.length) {
            pills[to].requestFocus();
            final pill = pills[to].context;
            if (pill != null) {
              unawaited(
                Scrollable.ensureVisible(
                  pill,
                  alignment: 0.5,
                  duration: const Duration(milliseconds: 220),
                ),
              );
            }
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FocusTraversalGroup(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _FavChip(
                focusNode: _firstChip,
                label: l10n.kostvFavoritesAll,
                selected: _only == null,
                onTap: () => _show(null),
              ),
              for (final type in kinds) ...[
                const SizedBox(width: 8),
                _FavChip(
                  focusNode: _chipNode(next++),
                  icon: KostvFavoritesKind.of(type).icon,
                  label: '${type.label(l10n)} · ${_countOf(type)}',
                  selected: _only == type,
                  onTap: () => _show(type),
                ),
              ],
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: Colors.white.withValues(alpha: 0.16),
              ),
              _FavChip(
                focusNode: _chipNode(next++),
                icon: order.icon,
                label: order.label(l10n),
                trailing: Icons.expand_more_rounded,
                onTap: _pickOrder,
              ),
              if (sortable) ...[
                const SizedBox(width: 8),
                _FavChip(
                  focusNode: _chipNode(next++),
                  icon: descending
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  label: descending
                      ? l10n.kostvSortDescending
                      : l10n.kostvSortAscending,
                  onTap: _flipDirection,
                ),
              ],
              AnimatedOpacity(
                opacity: reloading ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Padding(
                  padding: EdgeInsets.only(left: 14),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
          _header(context, 0),
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
                        onPressed: () => unawaited(_vm.load()),
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

  Widget _page(BuildContext context, List<FavoriteTypeFilter> kinds) {
    final insets = calendarChromeInsets(context);
    final phone = PlatformDetection.useMobileUi;
    final bottom =
        MediaQuery.paddingOf(context).bottom +
        (phone && NavigationLayout.usesBottomNavbar ? 96 : 32);
    final only = _only;
    final count = kinds.fold(0, (sum, type) => sum + _countOf(type));
    final news = _newsNow;
    return SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.only(top: insets.top, bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: insets.left, right: insets.right),
            child: _header(context, count),
          ),
          SizedBox(height: phone ? 12 : 16),
          if (news.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(left: insets.left, right: insets.right),
              child: KostvFavoritesNewsHero(
                news: news.take(5).toList(),
                fresh: _fresh,
                watchNode: _heroWatch,
                onWatch: (episode) => unawaited(_watch(episode)),
                onOpen: _open,
                onUp: () => NavigationLayout.focusNavbarNotifier.value?.call(),
                onDown: _firstChip.requestFocus,
                onLeftEdge: () =>
                    NavigationLayout.focusNavbarNotifier.value?.call(),
              ),
            ),
            SizedBox(height: phone ? 14 : 20),
          ],
          Padding(
            padding: EdgeInsets.only(left: insets.left, right: insets.right),
            child: _controls(context, kinds),
          ),
          SizedBox(height: phone ? 8 : 12),
          // The new view rises in; the old one goes at once, as its rows and
          // the new one's must never be on screen together.
          TweenAnimationBuilder<double>(
            key: ValueKey(only),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - t)),
                child: child,
              ),
            ),
            child: only == null
                ? Column(
                    key: const ValueKey('rows'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_newsRowShown) _newsSection(context, news, insets),
                      for (final type in kinds)
                        _section(
                          context,
                          type,
                          insets: insets,
                          first: type == kinds.first,
                        ),
                    ],
                  )
                : _grid(context, only, insets: insets),
          ),
        ],
      ),
    );
  }

  /// What a card says under its title.
  String? _subtitle(AggregatedItem item) {
    if (item.type == 'Episode') {
      final season = item.parentIndexNumber;
      final episode = item.indexNumber;
      final number = season != null && episode != null
          ? '$seasonMark$season:E$episode'
          : null;
      return [
        item.seriesName,
        number,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    }
    return item.productionYear?.toString();
  }

  ({double imageHeight, double width, double spacing, double headroom})
  _metrics(KostvFavoritesKind kind) {
    final phone = PlatformDetection.useMobileUi;
    final wide = kind.aspect > 1.2;
    final square = !wide && kind.aspect > 0.9;
    final imageHeight = phone
        ? (wide ? 118.0 : (square ? 150.0 : 165.0))
        : (wide ? 162.0 : (square ? 200.0 : 228.0));
    final expansion = !phone && _prefs.get(UserPreferences.cardFocusExpansion);
    return (
      imageHeight: imageHeight,
      width: imageHeight * kind.aspect,
      spacing: phone ? 12.0 : 20.0,
      // The focused card grows from its middle: room above it for that, so
      // it never covers what is above.
      headroom: expansion ? imageHeight * (MediaCard.focusScale - 1) + 22 : 8.0,
    );
  }

  Widget _card(
    BuildContext context,
    AggregatedItem item,
    KostvFavoritesKind kind,
    bool focused,
  ) {
    final m = _metrics(kind);
    final wide = kind.aspect > 1.2;
    final phone = PlatformDetection.useMobileUi;
    final client = GetIt.instance<MediaServerClient>();
    return MediaCard(
      title: item.name,
      subtitle: _subtitle(item),
      showLabel: true,
      imageUrl: resolveRowImageUrl(
        item,
        client.imageApi,
        m.imageHeight,
        kind.imageType,
        false,
        MediaQuery.devicePixelRatioOf(context),
      ),
      width: m.width,
      aspectRatio: kind.aspect,
      itemType: item.type,
      isPlayed: item.isPlayed,
      unplayedCount: item.unplayedItemCount,
      playedPercentage: wide ? item.playedPercentage : null,
      watchedBehavior: _prefs.get(UserPreferences.watchedIndicatorBehavior),
      focusColor: Color(_prefs.get(UserPreferences.focusColor).colorValue),
      cardFocusExpansion:
          !phone && _prefs.get(UserPreferences.cardFocusExpansion),
      externalIsFocused: InputModeTracker.showFocusVisuals(context, focused),
      onTap: () => _open(item),
      onLongPress: () => showContextMenu(context, item),
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    FavoriteTypeFilter type,
    EdgeInsets insets,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final kind = KostvFavoritesKind.of(type);
    return Padding(
      padding: EdgeInsets.fromLTRB(insets.left, 8, insets.right, 0),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: kostvFavoritesColor.withValues(alpha: 0.14),
              borderRadius: AppRadius.circular(9),
            ),
            child: Icon(kind.icon, size: 18, color: kostvFavoritesColor),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${type.label(l10n)} · ${_countOf(type)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  KostvFavoritesKind.why(type, l10n),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    FavoriteTypeFilter type, {
    required EdgeInsets insets,
    required bool first,
  }) {
    final kind = KostvFavoritesKind.of(type);
    final m = _metrics(kind);
    const labels = 54.0;
    final items = _items(type);
    return Column(
      key: _sectionKeys.putIfAbsent(type, GlobalKey.new),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, type, insets),
        LockedFocusRow<AggregatedItem>(
          key: _rowKeys.putIfAbsent(type, GlobalKey.new),
          hubKey: 'kostv_favorites_${type.name}',
          items: items,
          itemKey: (item, _) => item.id,
          focusNode: first ? _firstRow : null,
          itemExtent: m.width,
          itemSpacing: m.spacing,
          height: m.headroom + m.imageHeight + labels + 12,
          clipBehavior: Clip.none,
          padding: EdgeInsets.fromLTRB(
            insets.left,
            m.headroom,
            insets.right,
            12,
          ),
          onVerticalNavigation: (isUp) => _onVertical(type, isUp),
          onLeftEdge: () => NavigationLayout.focusNavbarNotifier.value?.call(),
          onIndexChanged: (index, item) {
            _focusOn(item);
            if (index >= items.length - 5) {
              unawaited(_vm.loadMoreForType(type));
            }
          },
          onTap: (_, item) => _open(item),
          onLongPress: (_, item) => showContextMenu(context, item),
          itemBuilder: (context, item, index, focused) {
            // Scrolled near the end by touch or a mouse: the next ones.
            if (index >= items.length - 3) {
              scheduleMicrotask(() => _vm.loadMoreForType(type));
            }
            return _card(context, item, kind, focused);
          },
        ),
      ],
    );
  }

  /// «Novedades en tus series»: what arrived of each favourite series.
  Widget _newsSection(
    BuildContext context,
    List<KostvSeriesNews> news,
    EdgeInsets insets,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    const kind = KostvFavoritesKind(
      icon: Icons.fiber_new_rounded,
      aspect: 16 / 9,
      imageType: ImageType.thumb,
    );
    final m = _metrics(kind);
    const labels = 54.0;
    final phone = PlatformDetection.useMobileUi;
    final client = GetIt.instance<MediaServerClient>();
    final kinds = _kinds();
    return Column(
      key: _newsSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(insets.left, 8, insets.right, 0),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D).withValues(alpha: 0.18),
                  borderRadius: AppRadius.circular(9),
                ),
                child: const Icon(
                  Icons.fiber_new_rounded,
                  size: 20,
                  color: Color(0xFFFF6B6F),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.kostvFavoritesNewsTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      l10n.kostvFavoritesNewsWhy,
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
        LockedFocusRow<KostvSeriesNews>(
          key: _newsRowKey,
          hubKey: 'kostv_favorites_news',
          items: news,
          itemKey: (n, _) => n.series.id,
          itemExtent: m.width,
          itemSpacing: m.spacing,
          height: m.headroom + m.imageHeight + labels + 12,
          clipBehavior: Clip.none,
          padding: EdgeInsets.fromLTRB(
            insets.left,
            m.headroom,
            insets.right,
            12,
          ),
          onVerticalNavigation: (isUp) {
            if (isUp) {
              _firstChip.requestFocus();
            } else if (kinds.isNotEmpty) {
              _focusRow(kinds.first, 0);
            }
            return true;
          },
          onLeftEdge: () => NavigationLayout.focusNavbarNotifier.value?.call(),
          onIndexChanged: (_, n) => _focusOn(n.series),
          onTap: (_, n) => _open(n.series),
          onLongPress: (_, n) => showContextMenu(context, n.series),
          itemBuilder: (context, n, index, focused) => MediaCard(
            title: n.series.name,
            subtitle: kostvNewsLine(n, l10n),
            showLabel: true,
            imageUrl: resolveRowImageUrl(
              n.episode,
              client.imageApi,
              m.imageHeight,
              ImageType.thumb,
              false,
              MediaQuery.devicePixelRatioOf(context),
            ),
            width: m.width,
            aspectRatio: kind.aspect,
            itemType: n.episode.type,
            watchedBehavior: _prefs.get(
              UserPreferences.watchedIndicatorBehavior,
            ),
            focusColor: Color(_prefs.get(UserPreferences.focusColor).colorValue),
            cardFocusExpansion:
                !phone && _prefs.get(UserPreferences.cardFocusExpansion),
            externalIsFocused: InputModeTracker.showFocusVisuals(
              context,
              focused,
            ),
            onTap: () => _open(n.series),
            onLongPress: () => showContextMenu(context, n.series),
          ),
        ),
      ],
    );
  }

  /// One kind on its own: all of it, in lines as wide as the page.
  Widget _grid(
    BuildContext context,
    FavoriteTypeFilter type, {
    required EdgeInsets insets,
  }) {
    final kind = KostvFavoritesKind.of(type);
    final m = _metrics(kind);
    const labels = 54.0;
    final items = _items(type);
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth - insets.left - insets.right;
        final columns = math.max(
          1,
          ((room + m.spacing) / (m.width + m.spacing)).floor(),
        );
        final lines = <List<AggregatedItem>>[
          for (var i = 0; i < items.length; i += columns)
            items.sublist(i, math.min(i + columns, items.length)),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, type, insets),
            for (final (line, cards) in lines.indexed)
              KeyedSubtree(
                key: _sectionKeys.putIfAbsent((type, line), GlobalKey.new),
                child: LockedFocusRow<AggregatedItem>(
                  key: _rowKeys.putIfAbsent((type, line), GlobalKey.new),
                  hubKey: 'kostv_favorites_grid_${type.name}_$line',
                  items: cards,
                  itemKey: (item, _) => item.id,
                  focusNode: line == 0 ? _firstRow : null,
                  itemExtent: m.width,
                  itemSpacing: m.spacing,
                  height: m.headroom + m.imageHeight + labels + 12,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.fromLTRB(
                    insets.left,
                    m.headroom,
                    insets.right,
                    4,
                  ),
                  onVerticalNavigation: (isUp) {
                    final to = line + (isUp ? -1 : 1);
                    if (to < 0) {
                      _firstChip.requestFocus();
                      return true;
                    }
                    if (to >= lines.length) {
                      unawaited(_vm.loadMoreForType(type));
                      return true;
                    }
                    _focusRow((
                      type,
                      to,
                    ), math.min(_gridColumn, lines[to].length - 1));
                    return true;
                  },
                  onLeftEdge: () =>
                      NavigationLayout.focusNavbarNotifier.value?.call(),
                  onIndexChanged: (index, item) {
                    _gridColumn = index;
                    _focusOn(item);
                    if (line >= lines.length - 2) {
                      unawaited(_vm.loadMoreForType(type));
                    }
                  },
                  onTap: (_, item) => _open(item),
                  onLongPress: (_, item) => showContextMenu(context, item),
                  itemBuilder: (context, item, index, focused) {
                    if (line >= lines.length - 1) {
                      scheduleMicrotask(() => _vm.loadMoreForType(type));
                    }
                    return _card(context, item, kind, focused);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Kos TV: a pill of the favourites' bar, for a kind to see or the order.
class _FavChip extends StatefulWidget {
  const _FavChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.selected = false,
    this.focusNode,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final IconData? trailing;
  final bool selected;
  final FocusNode? focusNode;

  @override
  State<_FavChip> createState() => _FavChipState();
}

class _FavChipState extends State<_FavChip> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lit =
        InputModeTracker.showFocusVisuals(context, _focused) || _hovered;
    final selected = widget.selected;
    final Color background;
    final Color border;
    final Color ink;
    if (lit) {
      background = Colors.white;
      border = Colors.white;
      ink = Colors.black;
    } else if (selected) {
      background = kostvFavoritesColor.withValues(alpha: 0.22);
      border = kostvFavoritesColor.withValues(alpha: 0.7);
      ink = Colors.white;
    } else {
      background = Colors.white.withValues(alpha: 0.07);
      border = Colors.white.withValues(alpha: 0.14);
      ink = Colors.white.withValues(alpha: 0.82);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent && event.logicalKey.isSelectKey) {
            widget.onTap();
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
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: lit ? 1.05 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: AppRadius.circular(999),
                  border: Border.all(color: border),
                  boxShadow: lit
                      ? const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: 18,
                        color: lit
                            ? Colors.black
                            : (selected ? kostvFavoritesColor : ink),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: ink,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 4),
                      Icon(widget.trailing, size: 18, color: ink),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
