import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import 'kostv_now_playing.dart';

/// The screens a music library's categories open.
enum MusicCategoryKind {
  artists,
  albums,
  songs,
  playlists,
  genres,
  favorites;

  static MusicCategoryKind? parse(String? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// How a category screen drives a category bar or rail: the category
/// showing, where Overview goes and how picking another swaps it in.
class MusicCategoryNav {
  final MusicCategoryKind current;
  final VoidCallback onOverview;
  final ValueChanged<MusicCategoryKind> onSelect;

  /// Picking the category already showing, which goes into its content.
  final VoidCallback onCurrent;

  /// The focus node for an entry, `overview` or a category's name.
  final FocusNode Function(String id) focusNode;

  const MusicCategoryNav({
    required this.current,
    required this.onOverview,
    required this.onSelect,
    required this.onCurrent,
    required this.focusNode,
  });
}

/// A music library category, routing to its own screen.
class MusicCategory {
  final IconData icon;
  final String label;
  final String route;
  const MusicCategory(this.icon, this.label, this.route);
}

List<MusicCategory> musicCategories(BuildContext context, String libraryId) {
  final l10n = AppLocalizations.of(context);
  String route(MusicCategoryKind kind) =>
      Destinations.musicCategory(libraryId, kind.name);
  return [
    MusicCategory(Icons.person, l10n.artists, route(MusicCategoryKind.artists)),
    MusicCategory(Icons.album, l10n.albums, route(MusicCategoryKind.albums)),
    MusicCategory(Icons.music_note, l10n.songs, route(MusicCategoryKind.songs)),
    MusicCategory(
      Icons.queue_music,
      l10n.playlists,
      route(MusicCategoryKind.playlists),
    ),
    MusicCategory(Icons.category, l10n.genres, route(MusicCategoryKind.genres)),
    MusicCategory(
      Icons.favorite,
      l10n.favorites,
      route(MusicCategoryKind.favorites),
    ),
  ];
}

/// Where a music row's See All goes, or null for rows without one.
String? musicSeeAllRoute(String libraryId, String rowId) {
  String route(MusicCategoryKind kind, {String? show}) =>
      Destinations.musicCategory(libraryId, kind.name, show: show);
  if (rowId.startsWith('musicalbum_')) {
    return route(MusicCategoryKind.albums);
  } else if (rowId.startsWith('albumartist_')) {
    return route(MusicCategoryKind.artists);
  } else if (rowId.startsWith('musicartist_')) {
    return route(MusicCategoryKind.artists, show: 'all');
  } else if (rowId == 'playlists') {
    return route(MusicCategoryKind.playlists);
  } else if (rowId.startsWith('favorites_')) {
    // The row itself only holds albums, so open Favorites on its albums.
    return route(MusicCategoryKind.favorites, show: 'albums');
  }
  return null;
}

/// Plays a song from its album, and opens anything else on its details
/// screen, which starts it when [autoPlay] is set.
///
/// Kos TV: [source] is where a song played comes from ([KostvMusicSource]).
void openMusicItem(
  BuildContext context,
  AggregatedItem item, {
  bool autoPlay = false,
  String source = KostvMusicSource.other,
}) {
  if (item.type == 'Audio') {
    unawaited(playMusicTrack(context, item, source: source));
    return;
  }
  context.push(
    Destinations.item(item.id, serverId: item.serverId, autoPlay: autoPlay),
  );
}

/// Kos TV: [source] is where it comes from ([KostvMusicSource]), told to
/// the server plugin without waiting for it.
Future<void> playMusicTrack(
  BuildContext context,
  AggregatedItem item, {
  String source = KostvMusicSource.other,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final manager = GetIt.instance<PlaybackManager>();
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final closeLoading = showMusicLoading(context, navigator: navigator);

  final albumId = item.albumId?.isNotEmpty == true
      ? item.albumId
      : item.parentId;

  try {
    var tracks = <AggregatedItem>[item];
    var startIndex = 0;

    if (albumId != null && albumId.isNotEmpty) {
      final factory = GetIt.instance<MediaServerClientFactory>();
      final client = item.serverId.isNotEmpty
          ? factory.getClientIfExists(item.serverId) ??
                GetIt.instance<MediaServerClient>()
          : GetIt.instance<MediaServerClient>();

      final data = await client.itemsApi.getItems(
        parentId: albumId,
        includeItemTypes: const ['Audio'],
        sortBy: 'ParentIndexNumber,IndexNumber,SortName',
        fields: 'PrimaryImageAspectRatio,BasicSyncInfo',
      );

      final loadedTracks =
          (data['Items'] as List?)
              ?.whereType<Map>()
              .map((raw) => raw.cast<String, dynamic>())
              .where((raw) => raw['Id']?.toString().isNotEmpty == true)
              .map(
                (raw) => AggregatedItem(
                  id: raw['Id'].toString(),
                  serverId: item.serverId,
                  rawData: raw,
                ),
              )
              .toList() ??
          const <AggregatedItem>[];

      if (loadedTracks.isNotEmpty) {
        tracks = loadedTracks;
        final idx = tracks.indexWhere((t) => t.id == item.id);
        if (idx >= 0) {
          startIndex = idx;
        }
      }
    }

    KostvNowPlaying.instance.noteChosen();
    kostvTellMusicSource(
      () => _clientOf(item),
      source,
      tracks,
      startIndex: startIndex,
    );
    await manager.playItems(tracks, startIndex: startIndex);
    closeLoading();
    if (context.mounted) {
      context.push(Destinations.audioPlayer);
    }
  } catch (_) {
    closeLoading();
    // Kos TV: the song on its own; if that fails too, the person is told
    // (nothing happening looks like the remote not working).
    try {
      KostvNowPlaying.instance.noteChosen();
      kostvTellMusicSource(() => _clientOf(item), source, [item]);
      await manager.playItems([item]);
      if (context.mounted) {
        context.push(Destinations.audioPlayer);
      }
    } catch (e) {
      debugPrint('[Music] Could not play it: $e');
      _sayCantPlay(messenger, l10n);
    }
  }
}

/// Kos TV: the short wait shown while music is being got ready. Returns
/// what takes it away, which only ever takes away this wait: Back may have
/// closed it already, and then nothing else is closed in its place (the
/// page under it).
VoidCallback showMusicLoading(
  BuildContext context, {
  NavigatorState? navigator,
}) {
  final nav = navigator ?? Navigator.of(context, rootNavigator: true);
  var showing = true;
  late final Route<void> route;
  route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  unawaited(nav.push(route).whenComplete(() => showing = false));
  return () {
    if (!showing) return;
    showing = false;
    if (route.isActive) nav.removeRoute(route);
  };
}

void _sayCantPlay(ScaffoldMessengerState? messenger, AppLocalizations l10n) {
  // Kos TV: a song that got as far as starting and failed there is told by
  // the player, with its retry; this is for what failed before that.
  if (KostvNowPlaying.instance.tellsStartFailure()) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.kostvMusicCantPlay)));
}

/// Kos TV: the client of [item]'s server, to tell its plugin where the
/// music comes from; null when there is none.
MediaServerClient? _clientOf(AggregatedItem item) {
  final getIt = GetIt.instance;
  // Whatever goes wrong here, the music plays: it is only not told.
  try {
    if (item.serverId.isNotEmpty &&
        getIt.isRegistered<MediaServerClientFactory>()) {
      final client = getIt<MediaServerClientFactory>().getClientIfExists(
        item.serverId,
      );
      if (client != null) return client;
    }
    return getIt.isRegistered<MediaServerClient>()
        ? getIt<MediaServerClient>()
        : null;
  } catch (_) {
    return null;
  }
}

/// Plays [tracks] from [startIndex] and opens the player. Nothing happens
/// when there's nothing to play; if it can't be played, the person is told.
///
/// Kos TV: every Music page starts its music here (or in [playMusicTrack]),
/// so this is where the server plugin is told where it comes from
/// ([source], a [KostvMusicSource]), without waiting for it.
Future<void> playMusicTracks(
  BuildContext context,
  List<AggregatedItem> tracks, {
  int startIndex = 0,
  String source = KostvMusicSource.other,
}) async {
  if (tracks.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  KostvNowPlaying.instance.noteChosen();
  kostvTellMusicSource(
    () => _clientOf(tracks.first),
    source,
    tracks,
    startIndex: startIndex,
  );
  try {
    await GetIt.instance<PlaybackManager>().playItems(
      tracks,
      startIndex: startIndex,
    );
  } catch (e) {
    debugPrint('[Music] Could not play it: $e');
    _sayCantPlay(messenger, l10n);
    return;
  }
  if (context.mounted) context.push(Destinations.audioPlayer);
}

/// Plays the songs under [parentId], an album or a whole library, in a
/// random order.
Future<void> shuffleMusic(
  BuildContext context, {
  required String parentId,
  String? serverId,
}) async {
  final client = GetIt.instance<MediaServerClientFactory>()
      .clientForServerOrActive(serverId);
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final response = await client.itemsApi.getItems(
      parentId: parentId,
      includeItemTypes: const ['Audio'],
      recursive: true,
      sortBy: 'Random',
      limit: 300,
      fields: 'PrimaryImageAspectRatio,BasicSyncInfo',
    );
    final tracks = ((response['Items'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (raw) => AggregatedItem(
            id: raw['Id']?.toString() ?? '',
            serverId: client.baseUrl,
            rawData: raw.cast<String, dynamic>(),
          ),
        )
        .where((track) => track.id.isNotEmpty)
        .toList();
    if (context.mounted) await playMusicTracks(context, tracks);
  } catch (e) {
    debugPrint('Failed to shuffle music: $e');
    _sayCantPlay(messenger, l10n);
  }
}
