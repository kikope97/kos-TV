import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/kostv_music_catalog.dart';
import '../../../data/services/kostv_music_dislikes.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/stremfin/kostv_stream_radio.dart';
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
  final hideExplicit = _hidesExplicit();
  return kostvQueueOf(
    wanted,
    startIndex: start,
    hideExplicit: hideExplicit,
    homeItems: (ids) => client == null
        ? Future.value(const <AggregatedItem>[])
        : KostvMusicService(client).songs(ids),
    // Kos TV: only for someone with all the music and no limit.
    streamWhenHomeFails: all && !hideExplicit,
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

/// Kos TV: [songs] of a list to play whole, without what the person
/// doesn't want to hear ([dislikes]: by the home id, the Deezer id or the
/// artist's name) but the one at [index] (picked; -1 for none), and where
/// that one is now.
({List<StremfinSong> songs, int index}) kostvSongsToPlay(
  List<StremfinSong> songs,
  KostvMusicDislikes dislikes, {
  int index = -1,
}) {
  if (dislikes.isEmpty) return (songs: songs, index: index < 0 ? 0 : index);
  final kept = <StremfinSong>[];
  var at = 0;
  for (final (i, song) in songs.indexed) {
    if (i == index) {
      at = kept.length;
    } else if (dislikes.stremfinSongOut(song)) {
      continue;
    }
    kept.add(song);
  }
  return (songs: kept, index: at);
}

/// Kos TV: an album page's songs for [playKostvStreamSongs]. Its songs
/// don't say whether they are explicit: for someone with a limit, those
/// that aren't at home don't sound (see [kostvTrackPlayable]).
List<KostvQueueSong> kostvAlbumQueueSongs(StremfinAlbumDetail detail) {
  final server = _homeClient()?.baseUrl ?? '';
  final hideExplicit = _hidesExplicit();
  return [
    for (final track in detail.songs)
      KostvQueueSong.ofTrack(
        track,
        detail.album,
        serverId: server,
        artistDeezerId: detail.artistDeezerId,
        genres: detail.genres,
        explicit: hideExplicit,
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

/// Kos TV: [kostvSongPlayable] of an album's song. An album's songs don't
/// say whether they are explicit, so for someone with a limit one that
/// isn't at home doesn't sound (its album can still be asked for).
bool kostvTrackPlayable(StremfinAlbumTrack track) =>
    switch (kostvTrackWayOf(track)) {
      KostvSongWay.home => true,
      KostvSongWay.stream => kostvMusicCatalogAll() && !_hidesExplicit(),
      KostvSongWay.none => false,
    };

/// Kos TV: reads «Qué música enseñar» again (a Music page opening).
void kostvRefreshMusicCatalog() =>
    unawaited(KostvMusicCatalog.instance.refresh().catchError((Object _) {}));

// ------------------------------------------------- the radio and the mixes

/// Kos TV: whether a station or the endless play (∞) around [seed] goes
/// through the requests service's radio too: with «Toda la música», or
/// when the seed itself isn't at home (the home server has no mix of it).
/// With «Solo la de casa» and a seed at home, only the home server's mix,
/// as before.
bool kostvStationWantsRadio(AggregatedItem seed) =>
    isKostvStream(seed) || kostvMusicCatalogAll();

/// Kos TV: the artists the requests service's radio of [seed] is asked
/// with: by Deezer's id for a song that isn't at home, by name for one of
/// the home server's (its own two first).
({List<String> names, List<String> ids}) kostvStationArtists(
  AggregatedItem seed,
) {
  final info = KostvStreamInfo.of(seed);
  final id = info?.artistDeezerId;
  if (id != null) return (names: const [], ids: [id]);
  final names = isKostvStream(seed)
      ? seed.artists.where((a) => a.trim().isNotEmpty).take(1).toList()
      : kostvMusicArtistNames(seed).take(2).toList();
  return (names: names, ids: const []);
}

/// Kos TV: the songs of a station around [seed] (not the seed itself):
/// the home server's mix of it when it is at home, mixed in turns with the
/// requests service's radio of its artists when [kostvStationWantsRadio]
/// (what isn't at home only with «Toda la música»); without what the
/// person doesn't want to hear, nor what is in [skip]. [homeLimit] is how
/// many the home server's mix gives. [skipKeys] are the [kostvSongKey]s of
/// the songs in the queue, so the same song in its other version (at home
/// or not) doesn't go in again. Throws when neither the home server's mix
/// nor the radio answered and so nothing came (to be asked again).
Future<List<AggregatedItem>> kostvStationFor(
  AggregatedItem seed, {
  Set<String> skip = const {},
  Set<String> skipKeys = const {},
  int homeLimit = 60,
  MediaServerClient? client,
}) async {
  final server = client ?? _homeClient();
  final music = server == null ? null : KostvMusicService(server);
  final dislikes = server == null
      ? KostvMusicDislikes.empty
      : await KostvMusicDislikesStore.instance
            .load(server)
            .catchError((Object _) => KostvMusicDislikes.empty);
  Future<List<AggregatedItem>> Function()? homeMix;
  if (!isKostvStream(seed) && music != null) {
    homeMix = () => music.mix(seed.id, limit: homeLimit);
  }
  if (!kostvStationWantsRadio(seed)) {
    final mix =
        await (homeMix?.call() ?? Future.value(const <AggregatedItem>[]))
            .catchError((Object _) => const <AggregatedItem>[]);
    return [
      for (final other in mix)
        if (other.id != seed.id && !skip.contains(other.id)) other,
    ];
  }
  final artists = kostvStationArtists(seed);
  return kostvStationOf(
    radio: KostvStreamRadio.instance,
    serverId: server?.baseUrl ?? seed.serverId,
    includeAway: kostvMusicCatalogAll(),
    hideExplicit: _hidesExplicit(),
    homeItems: (ids) => music == null
        ? Future.value(const <AggregatedItem>[])
        : music.songs(ids),
    dislikes: dislikes,
    homeMix: homeMix,
    artists: artists.names,
    artistIds: artists.ids,
    seed: seed,
    skip: skip,
    skipKeys: skipKeys,
  );
}

/// Kos TV: «Crear emisora» of [seed]: it plays, and its station after it.
/// Without anything to go after it, the seed plays on its own, and the
/// person is told.
Future<void> playKostvStation(BuildContext context, AggregatedItem seed) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final closeLoading = showMusicLoading(context);
  List<AggregatedItem> station;
  try {
    station = await kostvStationFor(seed);
  } catch (_) {
    station = const [];
  } finally {
    closeLoading();
  }
  if (!context.mounted) return;
  await playMusicTracks(context, [
    seed,
    ...station,
  ], source: KostvMusicSource.radio);
  if (station.isEmpty) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.kostvStreamStationEmpty)));
  }
}

/// Kos TV: «Crear emisora» of an artist of the requests service (their
/// page): the radio of them, what is at home from home.
Future<void> playKostvArtistStation(
  BuildContext context,
  StremfinArtist artist,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final server = _homeClient();
  final music = server == null ? null : KostvMusicService(server);
  final closeLoading = showMusicLoading(context);
  List<AggregatedItem> station;
  try {
    final dislikes = server == null
        ? KostvMusicDislikes.empty
        : await KostvMusicDislikesStore.instance
              .load(server)
              .catchError((Object _) => KostvMusicDislikes.empty);
    station = await kostvStationOf(
      radio: KostvStreamRadio.instance,
      serverId: server?.baseUrl ?? '',
      includeAway: kostvMusicCatalogAll(),
      hideExplicit: _hidesExplicit(),
      homeItems: (ids) => music == null
          ? Future.value(const <AggregatedItem>[])
          : music.songs(ids),
      dislikes: dislikes,
      artistIds: [artist.deezerId],
    );
  } catch (_) {
    station = const [];
  } finally {
    closeLoading();
  }
  if (!context.mounted) return;
  if (station.isEmpty) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.kostvStreamStationEmpty)));
    return;
  }
  await playMusicTracks(
    context,
    station,
    source: KostvMusicSource.radio,
    picked: false,
  );
}

/// Kos TV: the extra songs of the mixes, kept on the device with the Music
/// page's notes of the person.
KostvMixExtras kostvMixExtras = KostvMixExtras(
  radio: KostvStreamRadio.instance,
  load: () async {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) return null;
    return getIt<StremfinService>().rememberedMusicNote(KostvMixExtras.note);
  },
  save: (value) {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) return;
    getIt<StremfinService>().keepMusicNote(KostvMixExtras.note, value);
  },
  // Kos TV: the notes are the person signed in's: another's mixes aren't
  // read from or kept in them.
  who: () {
    final client = _homeClient();
    return client == null ? '' : '${client.baseUrl}|${client.userId}';
  },
);

/// Kos TV: today, by this device's clock (`2026-11-21`).
String kostvToday([DateTime? now]) {
  final day = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

/// Kos TV: a daily mix's songs ([items], by the artists [because]) to play:
/// with «Toda la música», about a quarter of songs that aren't at home
/// spread through it (picked once a day, see [KostvMixExtras]); with «Solo
/// la de casa», as they are. A slow radio doesn't hold the mix more than a
/// few seconds.
Future<List<AggregatedItem>> kostvMixQueue({
  required String mixId,
  required List<AggregatedItem> items,
  required List<String> because,
  String? day,
}) async {
  if (!kostvMusicCatalogAll() || items.isEmpty || because.isEmpty) {
    return items;
  }
  final server = _homeClient();
  if (server == null || !GetIt.instance.isRegistered<StremfinService>()) {
    return items;
  }
  try {
    // Kos TV: what the person doesn't want to hear, read now if it wasn't
    // (just started, another person) rather than taken as nothing.
    final dislikes = await KostvMusicDislikesStore.instance
        .load(server)
        .timeout(const Duration(seconds: 3))
        .catchError((Object _) => KostvMusicDislikesStore.instance.of(server));
    return await kostvMixExtras
        .mixWith(
          // Kept apart for each person signed in on the device.
          mixId: '${server.userId}|$mixId',
          person: '${server.baseUrl}|${server.userId}',
          day: day ?? kostvToday(),
          because: because,
          items: items,
          serverId: server.baseUrl,
          hideExplicit: _hidesExplicit(),
          dislikes: dislikes,
        )
        .timeout(const Duration(seconds: 8));
  } catch (_) {
    return items;
  }
}
