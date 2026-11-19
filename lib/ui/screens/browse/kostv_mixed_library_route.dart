import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/services/media_server_client_factory.dart';

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
