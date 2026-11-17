import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' hide ImageType;

import '../../../data/services/log_service.dart';
import '../../../data/utils/genre_browse_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/offline_aware_image.dart';
import '../calendar/calendar_common.dart';
import '../music/kostv_music_widgets.dart' show KostvMusicPressable;

/// Only films and series open from a genre, so only those are counted.
const _videoTypes = ['Movie', 'Series'];

/// One genre of the page: its name, how many titles it has and a picture.
class _Genre {
  _Genre({required this.id, required this.name, required this.count});

  final String id;
  final String name;
  int count;
  String? image;

  /// Whether [count] came from asking the server for this genre's titles
  /// (collections grouped or not), rather than the genre list's own.
  bool counted = false;
}

/// Kos TV: the genres of the home server, as Apple TV shows a category: a
/// grid of wide pictures, a film of the genre on each, with its name and
/// how many titles it has over the foot. Focus only lifts the picture.
/// Choosing one opens its films and series. One of the menu's pages: it
/// shows by resting on its button.
class KostvGenresScreen extends StatefulWidget {
  const KostvGenresScreen({super.key});

  @override
  State<KostvGenresScreen> createState() => _KostvGenresScreenState();
}

class _KostvGenresScreenState extends State<KostvGenresScreen> {
  final _client = GetIt.instance<MediaServerClient>();
  final _prefs = GetIt.instance<UserPreferences>();
  final _firstFocus = FocusNode(debugLabel: 'kostvGenresFirst');
  final _scroll = ScrollController();
  List<_Genre> _genres = const [];
  bool _loading = true;
  bool _failed = false;
  bool _disposed = false;
  int _token = 0;

  /// Pictures already on a tile, so two genres don't show the same film.
  final _used = <String>{};

  /// The genres last shown, with their pictures and counts, and whose they
  /// were: the page comes back at once with them (it opens just by resting
  /// on its menu button) and freshens them behind, without asking for every
  /// picture again.
  static List<_Genre>? _last;
  static String? _lastKey;

  String get _key => '${_client.baseUrl}|${_client.userId}|$_grouped';

  @override
  void initState() {
    super.initState();
    final last = _last;
    if (last != null && _lastKey == _key) {
      _genres = last;
      _loading = false;
    }
    _wasGrouped = _grouped;
    _prefs.addListener(_onPrefs);
    unawaited(_load());
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    _disposed = true;
    _firstFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _grouped => _prefs.get(UserPreferences.groupItemsIntoCollections);
  late bool _wasGrouped;

  /// Grouping into collections changed in Settings: counts and pictures
  /// follow.
  void _onPrefs() {
    final grouped = _grouped;
    if (grouped == _wasGrouped || _disposed) return;
    _wasGrouped = grouped;
    _used.clear();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = ++_token;
    final found = <_Genre>[];
    try {
      var start = 0;
      while (true) {
        final response = await _client.itemsApi.getGenres(
          sortBy: 'SortName',
          sortOrder: 'Ascending',
          recursive: true,
          startIndex: start,
          limit: 200,
          fields:
              'ItemCounts,PrimaryImageTag,ImageTags,BackdropImageTags,'
              'PrimaryImageAspectRatio',
          includeItemTypes: _videoTypes,
        );
        final page = ((response['Items'] as List?) ?? const [])
            .whereType<Map>()
            .map((g) => g.cast<String, dynamic>())
            .toList();
        for (final data in page) {
          final count = browsableGenreCount(
            data,
            normalizedItemTypes: _videoTypes,
          );
          if (count <= 0 && genreReportsCounts(data)) continue;
          final genre = _Genre(
            id: data['Id']?.toString() ?? '',
            name: data['Name'] as String? ?? '',
            count: count,
          );
          final (image, _, own) = resolveGenreOwnArtwork(
            genreData: data,
            imageApi: _client.imageApi,
            maxWidth: 640,
          );
          if (own) genre.image = image;
          if (genre.id.isNotEmpty && genre.name.isNotEmpty) found.add(genre);
        }
        final total = response['TotalRecordCount'] as int?;
        start += page.length;
        if (page.length < 200 || (total != null && start >= total)) break;
      }
      _failed = false;
    } catch (e) {
      _failed = true;
      if (GetIt.instance.isRegistered<LogService>()) {
        GetIt.instance<LogService>().log(
          LogCategory.network,
          'Loading genres failed',
          level: LogLevel.warning,
          error: e,
        );
      }
    }
    if (_disposed || token != _token) return;
    // Kept from before: a genre already shown keeps its picture and count.
    final before = {for (final g in _genres) g.id: g};
    for (final g in found) {
      final old = before[g.id];
      if (old != null && g.image == null) {
        g.image = old.image;
        g.counted = old.counted;
        if (old.counted) g.count = old.count;
      }
    }
    if (_failed && _genres.isNotEmpty) return;
    setState(() {
      _genres = found;
      _loading = false;
    });
    _last = found;
    _lastKey = _key;
    unawaited(_loadPictures(token));
  }

  /// A film of each genre for its picture, a few genres at a time; a genre
  /// with nothing to open goes.
  Future<void> _loadPictures(int token) async {
    // A genre with its own picture and a count from the server needs no
    // asking, unless collections change what it counts.
    final grouped = _grouped;
    final todo = [
      for (final g in _genres)
        if (g.image == null || g.count <= 0 || (grouped && !g.counted)) g,
    ];
    for (var i = 0; i < todo.length; i += 4) {
      if (_disposed || token != _token) return;
      await Future.wait(todo.skip(i).take(4).map((g) => _picture(g, token)));
    }
  }

  Future<void> _picture(_Genre genre, int token) async {
    try {
      final grouped = _grouped;
      final response = await _client.itemsApi.getItems(
        genreIds: [genre.id],
        includeItemTypes: grouped
            ? const ['Movie', 'Series', 'BoxSet']
            : _videoTypes,
        excludeItemTypes: kNonRootBrowseItemTypes,
        collapseBoxSetItems: grouped,
        sortBy: 'Random',
        recursive: true,
        limit: genre.image == null ? 6 : 0,
        enableTotalRecordCount: true,
        fields:
            'PrimaryImageTag,ImageTags,BackdropImageTags,'
            'PrimaryImageAspectRatio',
        enableImageTypes: 'Primary,Backdrop,Thumb',
        imageTypeLimit: 1,
      );
      if (_disposed || token != _token) return;
      final total = response['TotalRecordCount'];
      final count = total is num ? total.toInt() : genre.count;
      if (count <= 0) {
        setState(() => _genres = [..._genres]..remove(genre));
        return;
      }
      genre.count = count;
      genre.counted = true;
      if (genre.image == null) {
        final items = ((response['Items'] as List?) ?? const [])
            .whereType<Map>()
            .map((i) => i.cast<String, dynamic>())
            .toList();
        final (image, _, used) = resolveGenreFallbackArtwork(
          items: items,
          imageApi: _client.imageApi,
          maxWidth: 640,
          avoidIds: _used,
        );
        genre.image = image;
        if (used != null) _used.add(used);
      }
      setState(() {});
    } catch (_) {}
  }

  void _open(_Genre genre) =>
      context.push(Destinations.genre(genre.name, genreId: genre.id));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = PlatformDetection.useMobileUi;
    final insets = calendarChromeInsets(context);
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_genres.isEmpty) {
      body = Padding(
        padding: insets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(context, null),
            Expanded(
              child: Center(
                child: Text(
                  _failed ? l10n.kostvGenresUnavailable : l10n.noGenresFound,
                  style: TextStyle(
                    color: AppColorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      body = _grid(context, insets, phone);
    }
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.allGenres,
        child: phone || _genres.isEmpty
            ? body
            : RequestInitialFocus(targetNode: _firstFocus, child: body),
      ),
    );
  }

  Widget _title(BuildContext context, int? count) {
    final l10n = AppLocalizations.of(context);
    final phone = PlatformDetection.useMobileUi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.genres,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: phone ? 34 : 44,
            letterSpacing: -1,
          ),
        ),
        if (count != null && count > 0)
          Text(
            l10n.kostvGenresCount(count),
            style: TextStyle(
              color: AppColorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: phone ? 14 : 16,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _grid(BuildContext context, EdgeInsets insets, bool phone) {
    final l10n = AppLocalizations.of(context);
    final bottom =
        MediaQuery.paddingOf(context).bottom +
        (phone && NavigationLayout.usesBottomNavbar ? 110 : 40);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - insets.left - insets.right;
        final gap = phone ? 12.0 : 24.0;
        final columns = phone ? 2 : (width / 300).floor().clamp(3, 6);
        final tile = (width - gap * (columns - 1)) / columns;
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                insets.left,
                insets.top + (phone ? 4 : 8),
                insets.right,
                phone ? 16 : 26,
              ),
              sliver: SliverToBoxAdapter(
                child: _title(context, _genres.length),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                insets.left,
                0,
                insets.right,
                bottom,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  childAspectRatio: 16 / 9,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final tileWidget = KostvPictureTile(
                    title: _genres[i].name,
                    subtitle: _genres[i].count > 0
                        ? l10n.kostvGenreTitles(_genres[i].count)
                        : null,
                    image: _genres[i].image,
                    width: tile,
                    onKey: (event) => kostvGridEdgeKey(
                      event,
                      index: i,
                      columns: columns,
                      count: _genres.length,
                    ),
                    focusNode: i == 0 ? _firstFocus : null,
                    onTap: () => _open(_genres[i]),
                  );
                  if (i >= columns) return tileWidget;
                  // The first row shows the page from its top, the menu
                  // and title whole, not scrolled a little for the lift.
                  return Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (has) {
                      if (has && _scroll.hasClients) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!_scroll.hasClients) return;
                          _scroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                          );
                        });
                      }
                    },
                    child: tileWidget,
                  );
                }, childCount: _genres.length),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The remote at the edges of a grid of [count] tiles in [columns]: Down
/// from the last row and Up from the first stay in the grid, rather than
/// slipping into the side menu beside it; on the top bar, Up from the first
/// row goes up to it.
KeyEventResult kostvGridEdgeKey(
  KeyEvent event, {
  required int index,
  required int columns,
  required int count,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowDown) {
    final lastRow = (count - 1) ~/ columns;
    if (index ~/ columns >= lastRow) return KeyEventResult.handled;
  } else if (key == LogicalKeyboardKey.arrowUp && index < columns) {
    NavigationLayout.focusNavbarNotifier.value?.call();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// A wide picture filling the tile, darkened at the foot for a name and a
/// line under it (a genre and its count, a library). Focus lifts it, with
/// no frame.
class KostvPictureTile extends StatelessWidget {
  const KostvPictureTile({
    super.key,
    required this.title,
    required this.width,
    required this.onTap,
    this.subtitle,
    this.image,
    this.focusNode,
    this.onKey,
  });

  final String title;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final String? subtitle;
  final String? image;
  final double width;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  /// A colour of its own for each tile, under the picture and while it
  /// loads.
  Color get _tint {
    final hue = (title.hashCode % 360).abs().toDouble();
    return HSLColor.fromAHSL(1, hue, 0.35, 0.28).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final small = width < 220;
    final base = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_tint, Color.lerp(_tint, Colors.black, 0.55)!],
        ),
      ),
    );
    return KostvMusicPressable(
      focusNode: focusNode,
      onTap: onTap,
      onKey: onKey,
      // The grid keeps its place; moving along it keeps the tile in sight.
      centerVertically: false,
      builder: (context, lit) => AnimatedScale(
        scale: lit ? 1.06 : 1,
        duration: const Duration(milliseconds: 160),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: AppRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: lit ? 0.6 : 0.25),
                blurRadius: lit ? 30 : 12,
                offset: Offset(0, lit ? 14 : 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: AppRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                base,
                if (image case final url?)
                  OfflineAwareImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => base,
                    errorWidget: (_, _, _) => base,
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC000000)],
                      stops: [0.35, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: small ? 12 : 16,
                  right: small ? 12 : 16,
                  bottom: small ? 10 : 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: small ? 17 : 22,
                          fontWeight: FontWeight.w700,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 8),
                          ],
                        ),
                      ),
                      if (subtitle case final line?)
                        Text(
                          line,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: small ? 12 : 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
