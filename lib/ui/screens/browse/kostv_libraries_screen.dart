import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/aggregated_library.dart';
import '../../../data/repositories/multi_server_repository.dart';
import '../../../data/repositories/user_views_repository.dart';
import '../../../data/services/library_scope_service.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../data/utils/blocked_ratings.dart';
import '../../../data/utils/genre_browse_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/game_library.dart';
import '../../../util/live_tv_library.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_genres_screen.dart' show KostvPictureTile, kostvGridEdgeKey;

/// One library of the page, with the picture and count found for it.
class _Library {
  _Library(this.library);

  final AggregatedLibrary library;
  int count = 0;
  String? image;
}

/// The kinds of title a library's count is of: what its page lists.
List<String>? _countedTypes(String collectionType) =>
    switch (collectionType.toLowerCase()) {
      'movies' => const ['Movie'],
      'tvshows' => const ['Series'],
      'boxsets' => const ['BoxSet'],
      'music' => const ['MusicAlbum'],
      'books' || 'audiobooks' => const ['Book', 'AudioBook'],
      _ => null,
    };

/// Kos TV: the libraries of the home server, as Genres shows its genres: a
/// grid of wide pictures, a title of each library on its tile, with its
/// name and how many titles it has. Choosing one opens it. One of the
/// menu's pages: it shows by resting on its button.
class KostvLibrariesScreen extends StatefulWidget {
  const KostvLibrariesScreen({super.key});

  @override
  State<KostvLibrariesScreen> createState() => _KostvLibrariesScreenState();
}

class _KostvLibrariesScreenState extends State<KostvLibrariesScreen> {
  /// The libraries last shown, with their pictures and counts: the page
  /// comes back at once with them, and freshens them behind.
  static List<_Library>? _last;
  static String? _lastServer;

  final _prefs = GetIt.instance<UserPreferences>();
  final _firstFocus = FocusNode(debugLabel: 'kostvLibrariesFirst');
  final _scroll = ScrollController();
  List<_Library> _libraries = const [];
  bool _loading = true;
  bool _failed = false;
  bool _disposed = false;

  /// Pictures already on a tile, so two libraries don't show the same film.
  final _used = <String>{};

  @override
  void initState() {
    super.initState();
    final last = _last;
    if (last != null && _lastServer == _serverKey) {
      _libraries = last;
      _loading = false;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _disposed = true;
    _firstFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Whose libraries these are: the same person on the same server.
  String get _serverKey {
    try {
      final client = GetIt.instance<MediaServerClientFactory>()
          .clientForServerOrActive(null);
      // The person too: a child's profile on the same server mustn't see
      // the libraries a parent's showed.
      return '${client.baseUrl}|${client.userId}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _load() async {
    List<AggregatedLibrary> found = const [];
    try {
      final multi = _prefs.get(UserPreferences.enableMultiServerLibraries);
      final libs = multi
          ? await GetIt.instance<MultiServerRepository>()
                .getAggregatedLibraries()
          : await GetIt.instance<UserViewsRepository>().getUserViews();
      found = multi
          ? await GetIt.instance<LibraryScopeService>().withoutHiddenLibraries(
              libs,
            )
          : libs;
      // Live TV has a button of its own, and none at all in Kids Mode.
      final kids = _prefs.get(UserPreferences.kidsModeEnabled);
      final liveTvButton =
          !kids && _prefs.get(UserPreferences.showLiveTvButton);
      found = librariesForNav(found, liveTvButton, hideLiveTv: kids);
      _failed = false;
    } catch (_) {
      _failed = true;
    }
    if (_disposed) return;
    // Kept from before: what's already there keeps its picture.
    final before = {for (final l in _libraries) l.library.id: l};
    final fresh = [for (final lib in found) before[lib.id] ?? _Library(lib)];
    if (_failed && _libraries.isNotEmpty) return;
    setState(() {
      _libraries = fresh;
      _loading = false;
    });
    _last = fresh;
    _lastServer = _serverKey;
    // Kept from before: its picture stays, not a new one each visit.
    // Kos TV: three at a time, in order, rather than each waiting for the
    // one before.
    final waiting = [
      for (final lib in _libraries)
        if (lib.image == null) lib,
    ];
    var next = 0;
    Future<void> worker() async {
      while (next < waiting.length) {
        if (_disposed) return;
        await _picture(waiting[next++]);
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
  }

  /// A title of the library for its picture, and how many it has.
  Future<void> _picture(_Library lib) async {
    final types = _countedTypes(lib.library.collectionType);
    try {
      final client = GetIt.instance<MediaServerClientFactory>()
          .clientForServerOrActive(lib.library.serverId);
      final response = await client.itemsApi.getItems(
        parentId: lib.library.id,
        includeItemTypes: types,
        excludeItemTypes: types == null ? kNonRootBrowseItemTypes : null,
        sortBy: 'Random',
        recursive: true,
        limit: 8,
        enableTotalRecordCount: types != null,
        fields: 'PrimaryImageTag,ImageTags,BackdropImageTags',
        enableImageTypes: 'Primary,Backdrop,Thumb',
        imageTypeLimit: 1,
      );
      if (_disposed) return;
      // Its picture never from a title parental control blocks.
      final items = ((response['Items'] as List?) ?? const [])
          .whereType<Map>()
          .map((i) => i.cast<String, dynamic>())
          .where((i) => !isRawItemBlocked(i))
          .toList();
      final (image, _, used) = resolveGenreFallbackArtwork(
        items: items,
        imageApi: client.imageApi,
        maxWidth: 640,
        avoidIds: _used,
      );
      if (used != null) _used.add(used);
      final total = response['TotalRecordCount'];
      setState(() {
        lib.image = image;
        lib.count = types != null && total is num ? total.toInt() : 0;
      });
    } catch (_) {}
  }

  void _open(AggregatedLibrary lib) => context.push(
    libraryRoute(lib.id, lib.collectionType, lib.name, serverId: lib.serverId),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = PlatformDetection.useMobileUi;
    final insets = calendarChromeInsets(context);
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_libraries.isEmpty) {
      body = Padding(
        padding: insets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(context, null),
            Expanded(
              child: Center(
                child: Text(
                  _failed
                      ? l10n.kostvLibrariesUnavailable
                      : l10n.kostvLibrariesEmpty,
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
        activeRoute: Destinations.kostvLibraries,
        child: phone || _libraries.isEmpty
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
          l10n.libraries,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: phone ? 34 : 44,
            letterSpacing: -1,
          ),
        ),
        if (count != null && count > 0)
          Text(
            l10n.kostvLibrariesCount(count),
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
        // Fewer libraries than genres: bigger tiles.
        final columns = phone ? 1 : (width / 380).floor().clamp(2, 4);
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
                child: _title(context, _libraries.length),
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
                  childAspectRatio: phone ? 2.2 : 16 / 9,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final lib = _libraries[i];
                  final tileWidget = KostvPictureTile(
                    title: lib.library.name,
                    subtitle: lib.count > 0
                        ? l10n.kostvGenreTitles(lib.count)
                        : null,
                    image: lib.image,
                    width: tile,
                    onKey: (event) => kostvGridEdgeKey(
                      event,
                      index: i,
                      columns: columns,
                      count: _libraries.length,
                    ),
                    focusNode: i == 0 ? _firstFocus : null,
                    onTap: () => _open(lib.library),
                  );
                  if (i >= columns) return tileWidget;
                  // The first row shows the page from its top, the menu
                  // and title whole, not scrolled a little for the lift.
                  return Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (has) {
                      if (!has || !_scroll.hasClients) return;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!_scroll.hasClients) return;
                        unawaited(
                          _scroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                          ),
                        );
                      });
                    },
                    child: tileWidget,
                  );
                }, childCount: _libraries.length),
              ),
            ),
          ],
        );
      },
    );
  }
}
