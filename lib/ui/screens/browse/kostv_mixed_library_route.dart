import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/aggregated_library.dart';
import '../../../data/repositories/user_views_repository.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../util/game_library.dart';

/// Kos TV: what a library holds besides films and series (home videos and
/// other loose videos, photos, songs, books). The kOS TV catalogue only
/// shows films and series, so a library with any of these keeps the page
/// that shows everything.
const kostvLooseItemTypes = <String>[
  'Video',
  'MusicVideo',
  'Photo',
  'Audio',
  'AudioBook',
  'Book',
];

/// Kos TV: a library with films and series together opens the kOS TV
/// catalogue, like a library of only one of them, unless it also holds
/// loose videos (or anything else the catalogue doesn't show): then it keeps
/// [oldPage], where all of it can be reached.
///
/// Finding out takes one small request, remembered per library for as long
/// as the app runs, so going back to the library opens it at once. If the
/// question can't be answered, [fallbackToCatalog] says which page the
/// library opened before.
class KostvMixedLibraryRoute extends StatefulWidget {
  const KostvMixedLibraryRoute({
    super.key,
    required this.libraryId,
    required this.serverId,
    required this.catalog,
    required this.oldPage,
    this.fallbackToCatalog = false,
    @visibleForTesting this.hasLooseItems,
  });

  final String libraryId;
  final String? serverId;
  final WidgetBuilder catalog;
  final WidgetBuilder oldPage;
  final bool fallbackToCatalog;

  /// Answers in place of the server, for tests.
  final Future<bool> Function()? hasLooseItems;

  /// Answers already known, by server, person and library.
  static final _known = <String, bool>{};

  @visibleForTesting
  static void forgetAll() => _known.clear();

  @override
  State<KostvMixedLibraryRoute> createState() => _KostvMixedLibraryRouteState();
}

class _KostvMixedLibraryRouteState extends State<KostvMixedLibraryRoute> {
  String? _key;
  bool? _hasLoose;

  @override
  void initState() {
    super.initState();
    if (widget.hasLooseItems != null) {
      _key = 'test\u0000${widget.libraryId}';
    } else {
      final getIt = GetIt.instance;
      try {
        if (getIt.isRegistered<MediaServerClientFactory>()) {
          final client = getIt<MediaServerClientFactory>()
              .clientForServerOrActive(widget.serverId);
          _key =
              '${client.baseUrl}\u0000${client.userId}\u0000${widget.libraryId}';
        }
      } catch (_) {
        // No server to ask: the page the library always opened.
      }
    }
    _hasLoose = _key == null
        ? !widget.fallbackToCatalog
        : KostvMixedLibraryRoute._known[_key];
    if (_hasLoose == null) _ask();
  }

  Future<void> _ask() async {
    bool? hasLoose;
    try {
      hasLoose = await (widget.hasLooseItems ?? _askServer)();
      KostvMixedLibraryRoute._known[_key!] = hasLoose;
    } catch (e) {
      debugPrint('[MixedLibrary] Could not check ${widget.libraryId}: $e');
      hasLoose = !widget.fallbackToCatalog;
    }
    if (mounted) setState(() => _hasLoose = hasLoose);
  }

  Future<bool> _askServer() async {
    final client = GetIt.instance<MediaServerClientFactory>()
        .clientForServerOrActive(widget.serverId);
    final response = await client.itemsApi.getItems(
      parentId: widget.libraryId,
      includeItemTypes: kostvLooseItemTypes,
      recursive: true,
      limit: 1,
      enableTotalRecordCount: false,
    );
    final items = response['Items'];
    return items is List && items.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final hasLoose = _hasLoose;
    if (hasLoose == null) {
      return const Scaffold(backgroundColor: Colors.transparent);
    }
    return hasLoose ? widget.oldPage(context) : widget.catalog(context);
  }
}

/// Kos TV: what [KostvLibraryLookupRoute] needs to know of a library.
typedef KostvLibraryFacts = ({String collectionType, String name});

/// Kos TV: a library's address that doesn't say what the library holds or
/// what it's called (typed or bookmarked in the web app, or a link that
/// leaves them out). The library is looked up among the person's libraries
/// (usually already loaded for the menu; otherwise one request) and opens
/// as from its button: [found] with its type and name, or, for music, books,
/// games or live TV, their own page in its place. Only when the library
/// can't be found does it keep [oldPage].
class KostvLibraryLookupRoute extends StatefulWidget {
  const KostvLibraryLookupRoute({
    super.key,
    required this.libraryId,
    required this.serverId,
    required this.found,
    required this.oldPage,
    @visibleForTesting this.lookUp,
    @visibleForTesting this.openElsewhere,
  });

  final String libraryId;
  final String? serverId;
  final Widget Function(BuildContext context, String kind, String title) found;
  final WidgetBuilder oldPage;

  /// Answers in place of the server, for tests.
  final Future<KostvLibraryFacts?> Function()? lookUp;

  /// Opens another address in place of this one, for tests.
  final void Function(BuildContext context, String route)? openElsewhere;

  @override
  State<KostvLibraryLookupRoute> createState() =>
      _KostvLibraryLookupRouteState();
}

class _KostvLibraryLookupRouteState extends State<KostvLibraryLookupRoute> {
  bool _done = false;
  KostvLibraryFacts? _facts;

  @override
  void initState() {
    super.initState();
    _lookUp();
  }

  Future<void> _lookUp() async {
    KostvLibraryFacts? facts;
    try {
      facts = await (widget.lookUp ?? _askServer)();
    } catch (e) {
      debugPrint('[LibraryLookup] Could not look up ${widget.libraryId}: $e');
    }
    if (!mounted) return;
    if (facts != null && facts.name.isNotEmpty) {
      final route = libraryRoute(
        widget.libraryId,
        facts.collectionType,
        facts.name,
        serverId: widget.serverId,
      );
      // Music, books, games and live TV have pages of their own.
      if (!route.startsWith('/library/')) {
        final open =
            widget.openElsewhere ??
            (BuildContext context, String route) =>
                GoRouter.of(context).replace(route);
        open(context, route);
        return;
      }
    }
    setState(() {
      _done = true;
      _facts = facts != null && facts.name.isNotEmpty ? facts : null;
    });
  }

  Future<KostvLibraryFacts?> _askServer() async {
    final getIt = GetIt.instance;
    List<AggregatedLibrary> libraries = const [];
    // The person's own libraries are usually already loaded for the menu.
    if (widget.serverId == null && getIt.isRegistered<UserViewsRepository>()) {
      try {
        libraries = await getIt<UserViewsRepository>()
            .getAllViewsIncludingHidden();
      } catch (_) {
        // Asked again below.
      }
    }
    AggregatedLibrary? match = libraries
        .where((l) => l.id == widget.libraryId)
        .firstOrNull;
    if (match == null && getIt.isRegistered<MediaServerClientFactory>()) {
      final client = getIt<MediaServerClientFactory>().clientForServerOrActive(
        widget.serverId,
      );
      libraries = await loadUserViews(client, includeHidden: true);
      match = libraries.where((l) => l.id == widget.libraryId).firstOrNull;
    }
    if (match == null) return null;
    return (collectionType: match.collectionType, name: match.name);
  }

  @override
  Widget build(BuildContext context) {
    if (!_done) return const Scaffold(backgroundColor: Colors.transparent);
    final facts = _facts;
    if (facts == null) return widget.oldPage(context);
    return widget.found(
      context,
      facts.collectionType.toLowerCase(),
      facts.name,
    );
  }
}
