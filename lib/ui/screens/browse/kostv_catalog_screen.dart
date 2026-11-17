import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' hide ImageType;

import '../../../data/models/aggregated_item.dart';
import '../../../data/utils/blocked_ratings.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../data/utils/genre_browse_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/context_menu_sheet.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/offline_aware_image.dart';
import '../calendar/calendar_common.dart';
import '../detail/kostv/kostv_detail_buttons.dart'
    show kostvLight, kostvOnLight;
import '../home/home_row_card_image.dart';

/// What the page shows: everything, or only films or series.
enum _Kind { all, movies, series }

/// Everything, only what hasn't been watched, or only the favourites.
enum _Show { all, unwatched, favorites }

/// How the titles are ordered.
enum _Order { newest, name, rating }

/// Kos TV: a catalogue of titles, as Apple TV shows a category: the art of
/// one of them fading into the page behind its name, rows of pills to
/// choose films or series, what to show and the order, and a grid of
/// posters. A genre (under Genres) and a library (under Libraries) are
/// both one; the menu button of the page above stays lit.
class KostvCatalogScreen extends StatefulWidget {
  const KostvCatalogScreen({
    super.key,
    required this.title,
    required this.kicker,
    required this.activeRoute,
    this.genreId,
    this.parentId,
    this.onlyType,
    this.types,
    this.serverId,
  });

  /// A genre: its titles, within [parentId] when given.
  const KostvCatalogScreen.genre({
    super.key,
    required String this.genreId,
    required String genreName,
    this.parentId,
    this.onlyType,
    this.serverId,
  }) : title = genreName,
       kicker = null,
       activeRoute = Destinations.allGenres,
       types = null;

  /// The server the titles belong to; the active one when not given.
  final String? serverId;

  /// The name in big letters, and the small capitals over it (the word
  /// "Genre" when not given).
  final String title;
  final String? kicker;

  /// The menu page this one is under, whose button stays lit.
  final String activeRoute;

  final String? genreId;

  /// The library to look in, if any.
  final String? parentId;

  /// Only films ("Movie") or only series ("Series"): no choice between the
  /// two then.
  final String? onlyType;

  /// Other kinds of titles (collections, for one), shown as they are.
  final List<String>? types;

  @override
  State<KostvCatalogScreen> createState() => _KostvCatalogScreenState();
}

class _KostvCatalogScreenState extends State<KostvCatalogScreen> {
  static const _page = 60;

  // The server the genre came from (a Home row may show another one's).
  late final MediaServerClient _client =
      GetIt.instance<MediaServerClientFactory>().clientForServerOrActive(
        widget.serverId,
      );
  final _prefs = GetIt.instance<UserPreferences>();
  final _scroll = ScrollController();
  final _firstFocus = FocusNode(debugLabel: 'kostvCatalogFirst');
  final _pillFocus = FocusNode(debugLabel: 'kostvCatalogPills');
  final _lastPillFocus = FocusNode(debugLabel: 'kostvCatalogLastPill');

  /// The posters' focus, by place, for the remote to move along the grid.
  final Map<int, FocusNode> _nodes = {};
  int _columns = 1;

  FocusNode _nodeAt(int i) => i == 0
      ? _firstFocus
      : _nodes.putIfAbsent(i, () => FocusNode(debugLabel: 'kostvCatalog$i'));

  late _Kind _kind = switch (widget.onlyType) {
    'Movie' => _Kind.movies,
    'Series' => _Kind.series,
    _ => _Kind.all,
  };
  _Order _order = _Order.newest;
  _Show _show = _Show.all;
  final List<AggregatedItem> _items = [];
  int? _total;

  /// How many titles the server has given so far: where its next page
  /// starts. Not [_items], which leaves out those the device's parental
  /// control blocks.
  int _fetched = 0;

  /// How many of those it left out, for the count in the header.
  int _blocked = 0;
  bool _loading = true;
  bool _more = false;
  bool _failed = false;
  int _token = 0;

  /// How many films and series the genre has, to offer the choice only when
  /// it has both.
  int _movies = 0;
  int _series = 0;

  /// The art behind the name: a title of the genre with a wide picture.
  String? _art;

  @override
  void initState() {
    super.initState();
    _wasGrouped = _grouped;
    _prefs.addListener(_onPrefs);
    _scroll.addListener(_onScroll);
    unawaited(_counts());
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    _token++;
    _scroll.dispose();
    _firstFocus.dispose();
    _pillFocus.dispose();
    _lastPillFocus.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  bool get _grouped => _prefs.get(UserPreferences.groupItemsIntoCollections);
  late bool _wasGrouped;

  /// Grouping into collections changed in Settings: the list follows.
  void _onPrefs() {
    final grouped = _grouped;
    if (grouped == _wasGrouped || !mounted) return;
    _wasGrouped = grouped;
    unawaited(_load(reset: true));
  }

  /// Whether the films/series choice applies: not to collections and the
  /// like, nor when only one of the two is wanted.
  bool get _choosesKind => widget.types == null && widget.onlyType == null;

  List<String> get _types =>
      widget.types ??
      switch (_kind) {
        _Kind.all => const ['Movie', 'Series'],
        _Kind.movies => const ['Movie'],
        _Kind.series => const ['Series'],
      };

  (String, String) get _sort => switch (_order) {
    _Order.newest => ('DateCreated,SortName', 'Descending'),
    _Order.name => ('SortName', 'Ascending'),
    _Order.rating => ('CommunityRating,SortName', 'Descending'),
  };

  Future<void> _counts() async {
    // Only films or only series: there is no choice to offer.
    if (!_choosesKind) return;
    Future<int> count(String type) async {
      final response = await _client.itemsApi.getItems(
        parentId: widget.parentId,
        genreIds: widget.genreId == null ? null : [widget.genreId!],
        includeItemTypes: [type],
        recursive: true,
        limit: 0,
        enableTotalRecordCount: true,
      );
      final total = response['TotalRecordCount'];
      return total is num ? total.toInt() : 0;
    }

    try {
      final results = await Future.wait([count('Movie'), count('Series')]);
      if (!mounted) return;
      setState(() {
        _movies = results[0];
        _series = results[1];
      });
    } catch (_) {}
  }

  Future<void> _load({bool reset = false}) async {
    final token = reset ? ++_token : _token;
    if (reset) {
      setState(() {
        _items.clear();
        _fetched = 0;
        _blocked = 0;
        _total = null;
        _loading = true;
        _failed = false;
      });
    } else {
      if (_more || _loading) return;
      setState(() => _more = true);
    }
    final grouped = _grouped && _choosesKind && _kind == _Kind.all;
    final (sortBy, sortOrder) = _sort;
    try {
      final response = await _client.itemsApi.getItems(
        parentId: widget.parentId,
        genreIds: widget.genreId == null ? null : [widget.genreId!],
        filters: switch (_show) {
          _Show.all => null,
          _Show.unwatched => const ['IsUnplayed'],
          _Show.favorites => const ['IsFavorite'],
        },
        includeItemTypes: grouped
            ? const ['Movie', 'Series', 'BoxSet']
            : _types,
        excludeItemTypes: kNonRootBrowseItemTypes,
        collapseBoxSetItems: grouped,
        sortBy: sortBy,
        sortOrder: sortOrder,
        recursive: true,
        startIndex: _fetched,
        limit: _page,
        enableTotalRecordCount: true,
        fields:
            'PrimaryImageAspectRatio,ProductionYear,UserData,ImageTags,'
            'BackdropImageTags,ChildCount,RecursiveItemCount',
        enableImageTypes: 'Primary,Backdrop,Thumb',
        imageTypeLimit: 1,
      );
      if (!mounted || token != _token) return;
      final page = [
        for (final raw in (response['Items'] as List?) ?? const [])
          if (raw is Map && raw['Id'] != null)
            AggregatedItem(
              id: raw['Id'].toString(),
              serverId: _client.baseUrl,
              rawData: raw.cast<String, dynamic>(),
            ),
      ];
      // Parental control: what the device blocks isn't shown, not even its
      // poster or its name.
      final found = withoutBlockedItems(page);
      final total = response['TotalRecordCount'];
      setState(() {
        _fetched += page.length;
        _blocked += page.length - found.length;
        _items.addAll(found);
        // A page that brings nothing ends the list, whatever the count
        // said, so the spinner at its foot doesn't stay for ever.
        _total = page.isEmpty
            ? _fetched
            : (total is num ? total.toInt() : _fetched);
        _loading = false;
        _more = false;
        _art ??= _pickArt(found);
      });
      // A page whose titles were all blocked adds nothing to scroll down
      // to: the next one is asked for at once.
      if (found.isEmpty && page.isNotEmpty && _hasMore) unawaited(_load());
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _more = false;
        _failed = reset;
      });
    }
  }

  String? _pickArt(List<AggregatedItem> items) {
    for (final item in items) {
      final tags = item.backdropImageTags;
      if (tags.isEmpty) continue;
      return _client.imageApi.getBackdropImageUrl(
        item.id,
        maxWidth: 1600,
        tag: tags.first,
      );
    }
    return null;
  }

  /// Whether the menu is the side bar (not the top bar).
  bool get _sideMenu =>
      !PlatformDetection.useMobileUi &&
      NavigationLayout.sanitizeNavbarPosition(
            _prefs.get(UserPreferences.navbarPosition),
          ) ==
          NavbarPosition.left;

  bool get _hasMore => _total != null && _fetched < _total!;

  void _onScroll() {
    if (!_hasMore || _more) return;
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - 900) {
      unawaited(_load());
    }
  }

  void _choose({_Kind? kind, _Order? order, _Show? show}) {
    if ((kind ?? _kind) == _kind &&
        (order ?? _order) == _order &&
        (show ?? _show) == _show) {
      return;
    }
    setState(() {
      _kind = kind ?? _kind;
      _order = order ?? _order;
      _show = show ?? _show;
    });
    unawaited(_load(reset: true));
  }

  void _open(AggregatedItem item) =>
      context.push(Destinations.item(item.id, serverId: item.serverId));

  @override
  Widget build(BuildContext context) {
    final phone = PlatformDetection.useMobileUi;
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: widget.activeRoute,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Art(url: _art),
            // Always the same wrapper: changing the filter mustn't rebuild
            // the page and throw the focus off the pills.
            phone
                ? _content(context)
                : RequestInitialFocus(
                    targetNode: _firstFocus,
                    child: _content(context),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final insets = calendarChromeInsets(context);
    final phone = PlatformDetection.useMobileUi;
    final bottom =
        MediaQuery.paddingOf(context).bottom +
        (phone && NavigationLayout.usesBottomNavbar ? 110 : 48);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - insets.left - insets.right;
        final gap = phone ? 12.0 : 22.0;
        final columns = phone
            ? (width / 120).floor().clamp(3, 4)
            : (width / 170).floor().clamp(4, 9);
        final cardWidth = (width - gap * (columns - 1)) / columns;
        _columns = columns;
        final expansion =
            !phone && _prefs.get(UserPreferences.cardFocusExpansion);
        final Widget grid;
        if (_loading) {
          grid = const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        } else if (_items.isEmpty) {
          grid = SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(
                child: Text(
                  _failed ? l10n.kostvGenreUnavailable : l10n.kostvGenreEmpty,
                  style: TextStyle(
                    color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          );
        } else {
          grid = SliverPadding(
            padding: EdgeInsets.fromLTRB(
              insets.left,
              0,
              insets.right,
              _hasMore ? 24 : bottom,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: gap,
                mainAxisSpacing: phone ? 14 : 26,
                // The poster and its two lines of text under it.
                // (as tall as the TV's own text size makes them)
                childAspectRatio:
                    cardWidth /
                    (cardWidth * 1.5 +
                        MediaQuery.textScalerOf(context).scale(50)),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _card(
                  context,
                  _items[i],
                  cardWidth,
                  expansion,
                  index: i,
                  topRow: i < columns,
                ),
                childCount: _items.length,
              ),
            ),
          );
        }
        return CustomScrollView(
          controller: _scroll,
          clipBehavior: Clip.none,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                insets.left,
                insets.top + (phone ? 8 : 40),
                insets.right,
                // Room for the focused poster growing up from the grid.
                phone ? 16 : 40,
              ),
              sliver: SliverToBoxAdapter(child: _header(context)),
            ),
            grid,
            if (_hasMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottom),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = PlatformDetection.useMobileUi;
    final count = ((_total ?? 0) - _blocked).clamp(0, 1 << 30);
    final kinds = _choosesKind && _movies > 0 && _series > 0;
    final pills = <Widget>[
      if (kinds) ...[
        for (final kind in _Kind.values)
          _Pill(
            focusNode: kind == _Kind.all ? _pillFocus : null,
            label: switch (kind) {
              _Kind.all => l10n.all,
              _Kind.movies => l10n.movies,
              _Kind.series => l10n.series,
            },
            selected: _kind == kind,
            onTap: () => _choose(kind: kind),
          ),
        const _Dot(),
      ],
      // These two switch on and off: neither means everything.
      for (final show in const [_Show.unwatched, _Show.favorites])
        _Pill(
          focusNode: !kinds && show == _Show.unwatched ? _pillFocus : null,
          label: show == _Show.unwatched
              ? l10n.kostvCatalogUnwatched
              : l10n.kostvCatalogFavorites,
          selected: _show == show,
          onTap: () => _choose(show: _show == show ? _Show.all : show),
        ),
      const _Dot(),
      for (final order in _Order.values)
        _Pill(
          focusNode: order == _Order.values.last ? _lastPillFocus : null,
          label: switch (order) {
            _Order.newest => l10n.kostvGenreSortNew,
            _Order.name => l10n.kostvGenreSortName,
            _Order.rating => l10n.kostvGenreSortRating,
          },
          selected: _order == order,
          onTap: () => _choose(order: order),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          (widget.kicker ?? l10n.kostvGenreKicker).toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: phone ? 12 : 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: phone ? 36 : 52,
            height: 1.05,
            letterSpacing: -1,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 18)],
          ),
        ),
        if (count > 0) ...[
          const SizedBox(height: 6),
          Text(
            l10n.kostvGenreTitles(count),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: phone ? 14 : 17,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        SizedBox(height: phone ? 16 : 26),
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          // Up from the pills goes to the menu; on a touch screen the row
          // scrolls sideways.
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowUp) {
              NavigationLayout.focusNavbarNotifier.value?.call();
              return KeyEventResult.handled;
            }
            // Left from the first pill: to the side menu, if there is one,
            // never down into the posters.
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                _pillFocus.hasPrimaryFocus) {
              if (_sideMenu) {
                NavigationLayout.focusNavbarNotifier.value?.call();
              }
              return KeyEventResult.handled;
            }
            // Right from the last pill stays: nothing of the row is
            // there, and the posters below aren't to its right.
            if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                event.logicalKey == LogicalKeyboardKey.arrowRight &&
                _lastPillFocus.hasPrimaryFocus) {
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          onFocusChange: (has) {
            if (has && _scroll.hasClients) {
              unawaited(
                _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                ),
              );
            }
          },
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final pill in pills) ...[pill, const SizedBox(width: 10)],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The remote along the grid: a row up or down, a poster to the side.
  /// Up from the top row goes to the pills; left from the first column, to
  /// the side menu when there is one.
  KeyEventResult _onCardKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final columns = _columns;
    int? target;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (index + columns < _items.length) {
        target = index + columns;
      } else if ((index ~/ columns) < ((_items.length - 1) ~/ columns)) {
        target = _items.length - 1;
      } else {
        // The last row: more to come (a page that failed to load, say)
        // is asked for again.
        if (_hasMore) unawaited(_load());
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (index < columns) {
        _pillFocus.requestFocus();
        return KeyEventResult.handled;
      }
      target = index - columns;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (index % columns == columns - 1 || index + 1 >= _items.length) {
        return KeyEventResult.handled;
      }
      target = index + 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (index % columns == 0) return KeyEventResult.ignored;
      target = index - 1;
    } else {
      return KeyEventResult.ignored;
    }
    final node = _nodeAt(target);
    if (node.context != null) {
      node.requestFocus();
      final place = node.context;
      if (place != null && target >= columns) {
        unawaited(
          Scrollable.ensureVisible(
            place,
            alignment: 0.35,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    } else {
      // Not built yet (far below): scroll to it, then take it.
      final row = target ~/ columns;
      final rowHeight =
          _scroll.position.maxScrollExtent /
          ((_items.length / columns).ceil()).clamp(1, 1 << 20);
      unawaited(
        _scroll
            .animateTo(
              (row * rowHeight).clamp(0, _scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
            )
            .then((_) {
              if (mounted && node.context != null) node.requestFocus();
            }),
      );
    }
    return KeyEventResult.handled;
  }

  Widget _card(
    BuildContext context,
    AggregatedItem item,
    double width,
    bool expansion, {
    required int index,
    required bool topRow,
  }) {
    final client = _client;
    final card = MediaCard(
      focusNode: _nodeAt(index),
      onKeyEvent: (_, event) => _onCardKey(index, event),
      title: item.name,
      subtitle: item.productionYear?.toString(),
      showLabel: true,
      imageUrl: resolveRowImageUrl(
        item,
        client.imageApi,
        width * 1.5,
        ImageType.poster,
        false,
        MediaQuery.devicePixelRatioOf(context),
      ),
      width: width,
      aspectRatio: 2 / 3,
      itemType: item.type,
      isPlayed: item.isPlayed,
      unplayedCount: item.unplayedItemCount,
      watchedBehavior: _prefs.get(UserPreferences.watchedIndicatorBehavior),
      focusColor: Color(_prefs.get(UserPreferences.focusColor).colorValue),
      cardFocusExpansion: expansion,
      onTap: () => _open(item),
      onLongPress: () => showContextMenu(context, item),
      // The top row keeps the name and the pills in sight.
      onFocus: topRow
          ? () {
              if (!_scroll.hasClients) return;
              unawaited(
                _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                ),
              );
            }
          : null,
    );
    return Align(alignment: Alignment.topCenter, child: card);
  }
}

/// The art of a title of the genre, at the top of the page, fading into it
/// at the foot and on the left where the name is.
class _Art extends StatelessWidget {
  const _Art({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final phone = PlatformDetection.useMobileUi;
    final height = phone ? size.height * 0.42 : size.height * 0.62;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: url == null
              ? const SizedBox.expand()
              : Stack(
                  key: ValueKey(url),
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: 0.55,
                      child: OfflineAwareImage(
                        imageUrl: url!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColorScheme.background.withValues(alpha: 0.2),
                            AppColorScheme.background.withValues(alpha: 0.55),
                            AppColorScheme.background,
                          ],
                          stops: const [0, 0.55, 1],
                        ),
                      ),
                    ),
                    if (!phone)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              AppColorScheme.background.withValues(alpha: 0.8),
                              AppColorScheme.background.withValues(alpha: 0),
                            ],
                            stops: const [0, 0.6],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A choice in the row under the name: grey, the chosen one a lighter grey
/// and bold, white with dark text while focused.
class _Pill extends StatefulWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.focusNode,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final phone = PlatformDetection.useMobileUi;
    final lit = _focused || _hovered;
    final Color background;
    final Color ink;
    if (lit) {
      background = kostvLight;
      ink = kostvOnLight;
    } else if (widget.selected) {
      background = Colors.white.withValues(alpha: 0.28);
      ink = Colors.white;
    } else {
      background = Colors.white.withValues(alpha: 0.10);
      ink = Colors.white.withValues(alpha: 0.8);
    }
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? 1.08 : 1,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: EdgeInsets.symmetric(
              horizontal: phone ? 14 : 18,
              vertical: phone ? 7 : 9,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                if (_focused)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: ink,
                fontSize: phone ? 14 : 16,
                fontWeight: widget.selected || lit
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small dot between the two groups of pills.
class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
    width: 4,
    height: 4,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.35),
      shape: BoxShape.circle,
    ),
  );
}
