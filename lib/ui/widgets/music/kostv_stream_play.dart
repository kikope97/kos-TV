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
import 'kostv_now_playing.dart';
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

/// Kos TV: whether a song of the requests service whose home copy wasn't
/// found has the menu of one that isn't at home: only without a home id,
/// with «Toda la música» and allowed to the person (nothing explicit with
/// a limit). One with a home id that Jellyfin didn't give (hidden from
/// them) keeps the home menu.
bool kostvSongMenuFromAway(StremfinSong song) =>
    kostvSongWayOf(song) == KostvSongWay.stream && kostvSongPlayable(song);

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

/// Kos TV: the songs of a station around [seed] (not the seed itself), as
/// the app makes it without the server plugin's ([kostvSongStation]): the
/// requests service's radio of its artists in its order and, after it, the
/// home server's mix of it when it is at home (what isn't at home only with
/// «Toda la música»; asked only when [kostvStationWantsRadio], which its
/// callers check: otherwise the home server's mix alone); without what the
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
  final dislikes = await _dislikesOf(server);
  Future<List<AggregatedItem>> Function()? homeMix;
  if (!isKostvStream(seed) && music != null) {
    homeMix = () => music.mix(seed.id, limit: homeLimit);
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

/// Kos TV: what the person doesn't want to hear, as the plugin keeps it
/// (read now if it wasn't; nothing when it can't be read).
Future<KostvMusicDislikes> _dislikesOf(MediaServerClient? server) =>
    server == null
    ? Future.value(KostvMusicDislikes.empty)
    : KostvMusicDislikesStore.instance
          .load(server)
          .catchError((Object _) => KostvMusicDislikes.empty);

/// Kos TV: the artist a station's seed is told to the plugin with: the
/// song's own first one.
String? _seedArtist(AggregatedItem seed) =>
    kostvMusicArtistNames(seed).firstOrNull ??
    seed.artists.where((a) => a.trim().isNotEmpty).firstOrNull ??
    seed.albumArtist;

/// Kos TV: the station of the song [seed] as the server plugin makes it
/// (`GET Music/Station`, `docs/musica-radio.md`): what people in general
/// listen to with it, at home and (with «Toda la música») not, already in
/// its order. Null when the plugin can't give one: from before it (404),
/// not answering, or nothing in it that can sound for the person; the app
/// then makes the station as before ([kostvSongStation]). Without what the
/// person doesn't want to hear ([dislikes]) nor what is in [skip] and
/// [skipKeys] (see [kostvStationFromPlugin]).
///
/// Kos TV: the first time a seed is asked for, the plugin answers at once
/// with what it has (`Partial`, or `Source: fallback` from a plugin that
/// doesn't say it: Deezer's radio) and works the whole station out
/// meanwhile: [onPartial] is told then, so the queue can be completed with
/// it later ([KostvNowPlaying.completeStationLater]).
Future<List<AggregatedItem>?> kostvPluginStationFor(
  AggregatedItem seed, {
  required MediaServerClient client,
  KostvMusicDislikes dislikes = KostvMusicDislikes.empty,
  Set<String> skip = const {},
  Set<String> skipKeys = const {},
  int limit = 50,
  bool? includeAway,
  bool? hideExplicit,
  KostvMusicPlugin? plugin,
  void Function()? onPartial,
}) async {
  if (seed.type != 'Audio' || seed.isAudiobook) return null;
  final String id;
  if (isKostvStream(seed)) {
    final deezerId = kostvStreamDeezerId(seed);
    if (deezerId == null || deezerId.isEmpty) return null;
    id = 'stremfin:$deezerId';
  } else {
    id = seed.id;
  }
  final all = includeAway ?? kostvMusicCatalogAll();
  final KostvMusicAnswer<KostvMusicStation> answer;
  try {
    answer = await (plugin ?? KostvMusicPlugin.instance).station(
      client,
      seed: id,
      title: seed.name,
      artist: _seedArtist(seed),
      limit: limit,
      away: all,
    );
  } catch (_) {
    return null;
  }
  final station = answer.value;
  if (station == null) return null;
  final items = kostvStationFromPlugin(
    station,
    serverId: client.baseUrl,
    includeAway: all,
    hideExplicit: hideExplicit ?? _hidesExplicit(),
    dislikes: dislikes,
    seed: seed,
    skip: skip,
    skipKeys: skipKeys,
  );
  if (station.unfinished) onPartial?.call();
  return items.isEmpty ? null : items;
}

/// Kos TV: the songs of the station of the song [seed] (not the seed
/// itself), for «Crear emisora» and the endless play (∞): the server
/// plugin's ([kostvPluginStationFor]) when it has it; otherwise as before,
/// with the requests service's radio of its artists in its order and the
/// home server's mix after it ([kostvStationFor], when
/// [kostvStationWantsRadio]) or, with «Solo la de casa» and a seed at home,
/// the home server's mix alone ([homeLimit] of it). Throws when nothing
/// answered and so nothing came (to be asked again). [onPartial]: the
/// plugin's station isn't whole yet (see [kostvPluginStationFor]).
Future<List<AggregatedItem>> kostvSongStation(
  AggregatedItem seed, {
  Set<String> skip = const {},
  Set<String> skipKeys = const {},
  int homeLimit = 60,
  MediaServerClient? client,
  void Function()? onPartial,
}) async {
  final server = client ?? _homeClient();
  final dislikes = await _dislikesOf(server);
  if (server != null) {
    final fromPlugin = await kostvPluginStationFor(
      seed,
      client: server,
      dislikes: dislikes,
      skip: skip,
      skipKeys: skipKeys,
      onPartial: onPartial,
    );
    if (fromPlugin != null) return fromPlugin;
  }
  if (kostvStationWantsRadio(seed)) {
    return kostvStationFor(
      seed,
      skip: skip,
      skipKeys: skipKeys,
      homeLimit: homeLimit,
      client: server,
    );
  }
  if (server == null) return const [];
  final mix = await KostvMusicService(server).mix(seed.id, limit: homeLimit);
  final seedKey = kostvSongKey(seed);
  return kostvRadioInOrder(
    [
      for (final song in mix)
        if (!dislikes.songOut(song) && kostvSongKey(song) != seedKey) song,
    ],
    skip: {...skip, seed.id},
    skipKeys: skipKeys,
  );
}

/// Kos TV: «Crear emisora» of [seed]: it plays, and its station after it
/// ([kostvSongStation]). Without anything to go after it, the seed plays
/// on its own, and the person is told. An artist at home (the search's top
/// result) gets their station ([playKostvHomeArtistStation]).
Future<void> playKostvStation(BuildContext context, AggregatedItem seed) async {
  if (seed.type == 'MusicArtist') {
    return playKostvHomeArtistStation(
      context,
      artistId: seed.id,
      name: seed.name,
    );
  }
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final closeLoading = showMusicLoading(context);
  List<AggregatedItem> station;
  var partial = false;
  try {
    station = await kostvSongStation(seed, onPartial: () => partial = true);
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
  // Kos TV: what plays now is the plugin's first answer; the whole
  // station goes after it once worked out.
  if (partial) KostvNowPlaying.instance.completeStationLater(seed);
  if (station.isEmpty) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.kostvStreamStationEmpty)));
  }
}

/// Kos TV: the song an artist's station starts from, for the server
/// plugin's station of it: the first of [songs] (the artist's own, the
/// most listened first) that can sound for the person and they don't
/// mind hearing, as the queue takes it. Null when none can.
Future<AggregatedItem?> kostvArtistSeedSong(
  List<StremfinSong> songs,
  KostvMusicDislikes dislikes, {
  required Future<List<AggregatedItem>> Function(List<String> ids) homeItems,
  required String serverId,
}) async {
  for (final song in songs.take(5)) {
    if (dislikes.stremfinSongOut(song) || !kostvSongPlayable(song)) continue;
    final queue = await kostvQueueOf(
      [KostvQueueSong.ofSong(song, serverId: serverId)],
      hideExplicit: _hidesExplicit(),
      homeItems: homeItems,
    );
    final item = queue.items.firstOrNull;
    if (item != null && !dislikes.songOut(item)) return item;
  }
  return null;
}

/// Kos TV: an artist's station made by the server plugin from [seed] (one
/// of the artist's songs): the seed first, its station after it. Null when
/// the plugin can't give one (the app's own station then).
Future<List<AggregatedItem>?> _pluginArtistStation(
  AggregatedItem? seed,
  MediaServerClient? server,
  KostvMusicDislikes dislikes, {
  void Function()? onPartial,
}) async {
  if (seed == null || server == null) return null;
  final station = await kostvPluginStationFor(
    seed,
    client: server,
    dislikes: dislikes,
    onPartial: onPartial,
  );
  return station == null ? null : [seed, ...station];
}

/// Kos TV: «Crear emisora» of an artist of the requests service (their
/// page, [topSongs] its songs; the search's top result reads them): the
/// server plugin's station of their most listened song when it has it;
/// otherwise the radio of them, what is at home from home.
Future<void> playKostvArtistStation(
  BuildContext context,
  StremfinArtist artist, {
  List<StremfinSong>? topSongs,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final server = _homeClient();
  final music = server == null ? null : KostvMusicService(server);
  final closeLoading = showMusicLoading(context);
  List<AggregatedItem> station;
  AggregatedItem? partialSeed;
  try {
    final dislikes = await _dislikesOf(server);
    Future<List<AggregatedItem>> homeItems(List<String> ids) => music == null
        ? Future.value(const <AggregatedItem>[])
        : music.songs(ids);
    var top = topSongs;
    if (top == null &&
        server != null &&
        !KostvMusicPlugin.instance.knownMissing(server, 'Station') &&
        GetIt.instance.isRegistered<StremfinService>()) {
      top = await GetIt.instance<StremfinService>()
          .musicArtist(artist.deezerId, keep: true)
          .then((detail) => detail.topSongs)
          .timeout(const Duration(seconds: 8))
          .catchError((Object _) => const <StremfinSong>[]);
    }
    final seed = top == null || server == null
        ? null
        : await kostvArtistSeedSong(
            top,
            dislikes,
            homeItems: homeItems,
            serverId: server.baseUrl,
          ).catchError((Object _) => null);
    station =
        await _pluginArtistStation(
          seed,
          server,
          dislikes,
          onPartial: () => partialSeed = seed,
        ) ??
        await kostvStationOf(
          radio: KostvStreamRadio.instance,
          serverId: server?.baseUrl ?? '',
          includeAway: kostvMusicCatalogAll(),
          hideExplicit: _hidesExplicit(),
          homeItems: homeItems,
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
  final seed = partialSeed;
  if (seed != null) KostvNowPlaying.instance.completeStationLater(seed);
}

/// Kos TV: the station of an artist at home (Music's «Radios de tus
/// artistas»), as «Crear emisora» makes one: the server plugin's station
/// of the artist's song the person plays most, when it has it; otherwise
/// the requests service's radio of them (with «Toda la música»,
/// [kostvStationWantsRadio]'s rule) and the home server's mix of them
/// after it; without what the person doesn't want to hear, nor what is
/// explicit and not at home for someone with a limit. Nothing found: the
/// person is told.
Future<void> playKostvHomeArtistStation(
  BuildContext context, {
  required String artistId,
  required String name,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final server = _homeClient();
  final music = server == null ? null : KostvMusicService(server);
  final closeLoading = showMusicLoading(context);
  List<AggregatedItem> station;
  AggregatedItem? partialSeed;
  try {
    final dislikes = await _dislikesOf(server);
    final all = kostvMusicCatalogAll();
    final seed =
        music == null ||
            KostvMusicPlugin.instance.knownMissing(server!, 'Station')
        ? null
        : await music
              .artistSongs(artistId)
              .then(
                (songs) => songs.where((s) => !dislikes.songOut(s)).firstOrNull,
              )
              .catchError((Object _) => null);
    station =
        await _pluginArtistStation(
          seed,
          server,
          dislikes,
          onPartial: () => partialSeed = seed,
        ) ??
        await kostvStationOf(
          radio: KostvStreamRadio.instance,
          serverId: server?.baseUrl ?? '',
          includeAway: all,
          hideExplicit: _hidesExplicit(),
          homeItems: (ids) => music == null
              ? Future.value(const <AggregatedItem>[])
              : music.songs(ids),
          dislikes: dislikes,
          homeMix: music == null ? null : () => music.mix(artistId),
          // Kos TV: with «Solo la de casa», the home server's mix alone, as
          // «Crear emisora» of what is at home.
          artists: all ? [name] : const [],
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
  final seed = partialSeed;
  if (seed != null) KostvNowPlaying.instance.completeStationLater(seed);
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

/// Kos TV: the day the moment's mix [now] falls in belongs to: the one its
/// slot started on, so the night's (20:00–6:00) keeps the songs it got
/// before midnight after it (see [kostvMusicSlotAt]).
String kostvMomentDay([DateTime? now]) =>
    kostvToday((now ?? DateTime.now()).subtract(const Duration(hours: 6)));

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
