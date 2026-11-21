import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/kostv_music_catalog.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/stremfin/kostv_stream_song.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import 'music_navigation.dart';

/// Kos TV: the building blocks the Music pages play the requests service's
/// songs with («Toda la música»): what is at home plays from home, the rest
/// through the service, in one queue, through [playMusicTracks] like any
/// other music.

/// The home server signed in, whose songs these are (and in whose name the
/// out-of-home ones go into the queue).
MediaServerClient? _homeClient() =>
    GetIt.instance.isRegistered<MediaServerClient>()
    ? GetIt.instance<MediaServerClient>()
    : null;

/// Whether the person isn't shown explicit songs that aren't at home.
bool _hidesExplicit() =>
    !GetIt.instance.isRegistered<StremfinService>() ||
    GetIt.instance<StremfinService>().hidesExplicitMusic;

/// Kos TV: [songs] as the queue that plays them from [startIndex]: at home
/// from home, the rest (with «Toda la música») through the service; what
/// can't sound is left out. With «Solo la de casa» ([includeStream] false),
/// only what is at home.
Future<({List<AggregatedItem> items, int startIndex})> kostvStreamQueue(
  List<KostvQueueSong> songs, {
  int startIndex = 0,
  bool? includeStream,
}) async {
  final client = _homeClient();
  final all = includeStream ?? kostvMusicCatalogAll();
  final wanted = all
      ? songs
      : [
          for (final song in songs)
            if (song.way == KostvSongWay.home)
              KostvQueueSong(way: song.way, jellyfinId: song.jellyfinId),
        ];
  // The start stays on the song picked, or the next one that is kept.
  var start = startIndex;
  if (!all) {
    start = 0;
    for (var i = 0; i < startIndex && i < songs.length; i++) {
      if (songs[i].way == KostvSongWay.home) start++;
    }
  }
  return kostvQueueOf(
    wanted,
    startIndex: start,
    hideExplicit: _hidesExplicit(),
    homeItems: (ids) => client == null
        ? Future.value(const <AggregatedItem>[])
        : KostvMusicService(client).songs(ids),
  );
}

/// Kos TV: plays [songs] (the requests service's, at home or not) from
/// [startIndex] and opens the player; see [kostvStreamQueue] and
/// [playMusicTracks] ([source], [picked]). Says so when none can sound.
Future<void> playKostvStreamSongs(
  BuildContext context,
  List<KostvQueueSong> songs, {
  int startIndex = 0,
  String source = KostvMusicSource.other,
  bool picked = true,
  bool shuffle = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final queue = await kostvStreamQueue(songs, startIndex: startIndex);
  if (!context.mounted) return;
  if (queue.items.isEmpty) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.kostvStreamCantListen)));
    return;
  }
  var items = queue.items;
  var start = queue.startIndex;
  if (shuffle) {
    items = List.of(items)..shuffle();
    start = 0;
  }
  await playMusicTracks(
    context,
    items,
    startIndex: start,
    source: source,
    picked: picked,
  );
}

/// Kos TV: [songs] of the requests service (a search, a chart, «Para ti»…)
/// for [playKostvStreamSongs].
List<KostvQueueSong> kostvQueueSongs(List<StremfinSong> songs) {
  final server = _homeClient()?.baseUrl ?? '';
  return [
    for (final song in songs) KostvQueueSong.ofSong(song, serverId: server),
  ];
}

/// Kos TV: an album page's songs for [playKostvStreamSongs].
List<KostvQueueSong> kostvAlbumQueueSongs(StremfinAlbumDetail detail) {
  final server = _homeClient()?.baseUrl ?? '';
  return [
    for (final track in detail.songs)
      KostvQueueSong.ofTrack(
        track,
        detail.album,
        serverId: server,
        artistDeezerId: detail.artistDeezerId,
      ),
  ];
}

/// Kos TV: whether [song] can sound now: at home, or (with «Toda la
/// música») through the service, explicit ones not for someone with a
/// limit.
bool kostvSongPlayable(StremfinSong song) => switch (kostvSongWayOf(song)) {
  KostvSongWay.home => true,
  KostvSongWay.stream =>
    kostvMusicCatalogAll() &&
        kostvStreamAllowed(
          explicit: song.explicit,
          hideExplicit: _hidesExplicit(),
        ),
  KostvSongWay.none => false,
};

/// Kos TV: [kostvSongPlayable] of an album's song.
bool kostvTrackPlayable(StremfinAlbumTrack track) =>
    switch (kostvTrackWayOf(track)) {
      KostvSongWay.home => true,
      KostvSongWay.stream => kostvMusicCatalogAll(),
      KostvSongWay.none => false,
    };

/// Kos TV: reads «Qué música enseñar» again (a Music page opening).
void kostvRefreshMusicCatalog() =>
    unawaited(KostvMusicCatalog.instance.refresh().catchError((Object _) {}));
