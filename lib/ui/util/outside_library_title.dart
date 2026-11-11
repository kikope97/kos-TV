import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart';

import '../../l10n/app_localizations.dart';
import '../navigation/destinations.dart';

/// Kos TV: a title from an outside list (TMDB, IMDb, MDBList, the TMDB side
/// of "Because you watched", the Radarr/Sonarr calendar…) that the home
/// server may or may not have. Pressed, it looks for it on the server by its
/// TMDB or IMDb id: there, its own page opens; not there, a short note says
/// so. Nothing opens a page for a title the server doesn't have.
Future<void> openOutsideLibraryTitle(
  BuildContext context, {
  required String title,
  String? tmdbId,
  String? imdbId,
  bool? series,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final router = GoRouter.of(context);
  final itemId = await findInLibrary(
    tmdbId: tmdbId,
    imdbId: imdbId,
    series: series,
  );
  if (itemId != null) {
    router.push(Destinations.item(itemId));
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.kostvDiscoverNotHereYet(title))));
}

/// The id on the home server of the movie or series with this TMDB or IMDb
/// id, if it has it.
Future<String?> findInLibrary({
  String? tmdbId,
  String? imdbId,
  bool? series,
  @visibleForTesting MediaServerClient? client,
}) async {
  final getIt = GetIt.instance;
  final server =
      client ??
      (getIt.isRegistered<MediaServerClient>()
          ? getIt<MediaServerClient>()
          : null);
  if (server == null) return null;
  final keys = [
    if (tmdbId != null && tmdbId.trim().isNotEmpty) 'tmdb.${tmdbId.trim()}',
    if (imdbId != null && imdbId.trim().isNotEmpty) 'imdb.${imdbId.trim()}',
  ];
  for (final key in keys) {
    try {
      final result = await server.itemsApi.getItems(
        anyProviderIdEquals: key,
        includeItemTypes: switch (series) {
          true => const ['Series'],
          false => const ['Movie'],
          null => const ['Movie', 'Series'],
        },
        recursive: true,
        limit: 1,
        enableTotalRecordCount: false,
      );
      final items = result['Items'];
      if (items is List && items.isNotEmpty) {
        final first = items.first;
        final id = first is Map ? first['Id'] : null;
        if (id is String && id.isNotEmpty) return id;
      }
    } catch (_) {
      // Not reachable or not understood: try the other id, then give up.
    }
  }
  return null;
}
