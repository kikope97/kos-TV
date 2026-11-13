import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/mdblist_repository.dart';
import '../../../data/viewmodels/favorites_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/context_menu_sheet.dart';
import '../../widgets/focus/locked_focus_row.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/kostv_favorites_shortcut.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import '../home/home_row_card_image.dart';

/// Kos TV: the person's favourites («Mis favoritos»), with the menu above, a
/// row for each kind (films, series, episodes, people…) as on Home and on
/// «Mi lista», each with its icon and a line on what it holds. Reached from
/// the profile: the heart beside the avatar, its menu, or «Tú» on phones.
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

class _KostvFavoritesScreenState extends State<KostvFavoritesScreen> {
  final _prefs = GetIt.instance<UserPreferences>();
  late final FavoritesViewModel _vm;
  final _scroll = ScrollController();
  final Map<FavoriteTypeFilter, GlobalKey<LockedFocusRowState<AggregatedItem>>>
  _rowKeys = {};
  final Map<FavoriteTypeFilter, GlobalKey> _sectionKeys = {};
  final _firstFocus = FocusNode(debugLabel: 'kostvFavoritesFirst');

  @override
  void initState() {
    super.initState();
    _vm = FavoritesViewModel(
      client: GetIt.instance<MediaServerClient>(),
      prefs: _prefs,
      mdbListRepository: GetIt.instance<MdbListRepository>(),
    );
    _vm.addListener(_onChanged);
    // The page is always rows, whatever the old one was left on.
    if (_vm.viewStyle == FavoritesViewStyle.home) {
      unawaited(_vm.load());
    } else {
      unawaited(_vm.setViewStyle(FavoritesViewStyle.home));
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _vm.dispose();
    _scroll.dispose();
    _firstFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// What is still a favourite: one taken off here or elsewhere goes at once.
  List<AggregatedItem> _items(FavoriteTypeFilter type) => [
    for (final item in _vm.rowItems[type] ?? const <AggregatedItem>[])
      if (item.isFavorite) item,
  ];

  List<FavoriteTypeFilter> _shown() => [
    for (final type in FavoritesViewModel.rowTypes)
      if (_items(type).isNotEmpty) type,
  ];

  int _count(List<FavoriteTypeFilter> shown) => shown.fold(
    0,
    (sum, type) =>
        sum +
        (_vm.rowTotalCount(type) - (_vm.rowItems[type]?.length ?? 0)) +
        _items(type).length,
  );

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

  /// A remote moving between rows: the next one shown, or the bar above.
  bool _onVertical(FavoriteTypeFilter type, bool isUp) {
    final shown = _shown();
    final at = shown.indexOf(type) + (isUp ? -1 : 1);
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
    final l10n = AppLocalizations.of(context);
    final phone = PlatformDetection.useMobileUi;
    final shown = _shown();
    Widget body;
    if (_vm.state == FavoritesState.loading && shown.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_vm.state == FavoritesState.error && shown.isEmpty) {
      body = _message(
        icon: Icons.cloud_off_rounded,
        title: l10n.kostvFavoritesUnavailable,
        retry: true,
      );
    } else if (shown.isEmpty) {
      body = _message(
        icon: Icons.favorite_border_rounded,
        title: l10n.kostvFavoritesEmpty,
        text: l10n.kostvFavoritesEmptyHint,
      );
    } else {
      body = _rows(context, shown);
    }
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.allFavorites,
        child: Stack(
          fit: StackFit.expand,
          children: [
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
            phone || shown.isEmpty
                ? body
                : RequestInitialFocus(targetNode: _firstFocus, child: body),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int count) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kostvFavoritesColor.withValues(alpha: 0.16),
            borderRadius: AppRadius.circular(12),
            border: Border.all(
              color: kostvFavoritesColor.withValues(alpha: 0.4),
            ),
          ),
          child: const Icon(
            Icons.favorite_rounded,
            color: kostvFavoritesColor,
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

  Widget _rows(BuildContext context, List<FavoriteTypeFilter> shown) {
    final insets = calendarChromeInsets(context);
    final phone = PlatformDetection.useMobileUi;
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
            child: _header(context, _count(shown)),
          ),
          SizedBox(height: phone ? 12 : 20),
          for (final type in shown)
            _section(context, type, insets: insets, first: type == shown.first),
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
          ? 'T$season:E$episode'
          : null;
      return [
        item.seriesName,
        number,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    }
    return item.productionYear?.toString();
  }

  Widget _section(
    BuildContext context,
    FavoriteTypeFilter type, {
    required EdgeInsets insets,
    required bool first,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final phone = PlatformDetection.useMobileUi;
    final kind = KostvFavoritesKind.of(type);
    final wide = kind.aspect > 1.2;
    final square = !wide && kind.aspect > 0.9;
    final imageHeight = phone
        ? (wide ? 118.0 : (square ? 150.0 : 165.0))
        : (wide ? 162.0 : (square ? 200.0 : 228.0));
    final cardWidth = imageHeight * kind.aspect;
    final spacing = phone ? 12.0 : 20.0;
    final expansion = !phone && _prefs.get(UserPreferences.cardFocusExpansion);
    // The focused card grows from its middle: room above it for that, so it
    // never covers the section's title.
    final headroom = expansion
        ? imageHeight * (MediaCard.focusScale - 1) + 22
        : 8.0;
    const labels = 54.0;
    final focusColor = Color(_prefs.get(UserPreferences.focusColor).colorValue);
    final items = _items(type);
    final client = GetIt.instance<MediaServerClient>();
    final rowKey = _rowKeys.putIfAbsent(type, GlobalKey.new);
    final sectionKey = _sectionKeys.putIfAbsent(type, GlobalKey.new);
    final total = _vm.rowTotalCount(type);
    final shownCount = total - (_vm.rowItems[type]?.length ?? 0) + items.length;

    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(insets.left, 8, insets.right, 0),
          child: Row(
            children: [
              Icon(kind.icon, size: 20, color: kostvFavoritesColor),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${type.label(l10n)} · $shownCount',
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
        ),
        LockedFocusRow<AggregatedItem>(
          key: rowKey,
          hubKey: 'kostv_favorites_${type.name}',
          items: items,
          itemKey: (item, _) => item.id,
          focusNode: first ? _firstFocus : null,
          itemExtent: cardWidth,
          itemSpacing: spacing,
          height: headroom + imageHeight + labels + 12,
          clipBehavior: Clip.none,
          padding: EdgeInsets.fromLTRB(insets.left, headroom, insets.right, 12),
          onVerticalNavigation: (isUp) => _onVertical(type, isUp),
          onLeftEdge: () => NavigationLayout.focusNavbarNotifier.value?.call(),
          onTap: (_, item) => _open(item),
          onLongPress: (_, item) => showContextMenu(context, item),
          itemBuilder: (context, item, index, focused) {
            // Near the end of what is loaded: the next ones.
            if (index >= items.length - 4) {
              scheduleMicrotask(() => _vm.loadMoreForType(type));
            }
            final showFocus = InputModeTracker.showFocusVisuals(
              context,
              focused,
            );
            return MediaCard(
              title: item.name,
              subtitle: _subtitle(item),
              showLabel: true,
              imageUrl: resolveRowImageUrl(
                item,
                client.imageApi,
                imageHeight,
                kind.imageType,
                false,
                MediaQuery.devicePixelRatioOf(context),
              ),
              width: cardWidth,
              aspectRatio: kind.aspect,
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
              onLongPress: () => showContextMenu(context, item),
            );
          },
        ),
      ],
    );
  }
}
