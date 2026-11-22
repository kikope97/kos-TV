import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:playback_core/playback_core.dart' show PlaybackManager;
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/item_mutation_repository.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/kostv_music_away.dart';
import '../../../data/services/kostv_music_dislikes.dart';
import '../../../data/services/kostv_music_catalog.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/stremfin/kostv_stream_song.dart';
import '../../../data/services/stremfin/stremfin_error_text.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_now_playing.dart';
import '../../widgets/music/kostv_stream_play.dart';
import '../../widgets/music/music_navigation.dart';
import 'kostv_music_away_actions.dart';
import 'kostv_music_dislike.dart';
import 'kostv_stream_widgets.dart';
import 'kostv_music_widgets.dart';

/// Kos TV: what the Music pages do when something is picked: what is at
/// home plays or opens there; what isn't opens its album's page, to ask
/// for the whole album.

KostvMusicService kostvMusicService() =>
    KostvMusicService(GetIt.instance<MediaServerClient>());

/// Bumped when a song's ♥ changes from a menu, for «Tus favoritas».
final kostvMusicFavoritesChanged = ValueNotifier<int>(0);

bool _busy = false;

/// Runs [action] unless another one is still under way: a second OK on a
/// slow TV doesn't open the player twice.
Future<void> kostvMusicOnce(Future<void> Function() action) async {
  if (_busy) return;
  _busy = true;
  try {
    await action();
  } finally {
    _busy = false;
  }
}

/// What the Music page already knows of an album it opens.
@immutable
class KostvMusicAlbumSeed {
  const KostvMusicAlbumSeed({required this.album, this.song, this.preview});

  final StremfinAlbum album;

  /// The song it was opened from, and its preview.
  final String? song;
  final String? preview;
}

/// The badge of [album] on its cover.
KostvMusicBadge kostvMusicBadgeOf(StremfinAlbum album) {
  final download = album.download;
  // Kos TV: a download that failed isn't on its way.
  if (download != null) {
    return download.failed ? KostvMusicBadge.failed : KostvMusicBadge.onItsWay;
  }
  if (album.request != null) return KostvMusicBadge.asked;
  if (album.inJellyfin) return KostvMusicBadge.none;
  return album.canRequest ? KostvMusicBadge.ask : KostvMusicBadge.none;
}

/// The cover of one of the home server's items (a song shows its album's).
String? kostvMusicImageOf(AggregatedItem item) {
  // Kos TV: one that isn't at home has the requests service's cover.
  if (isKostvStream(item)) return KostvStreamInfo.of(item)?.cover;
  final client = GetIt.instance<MediaServerClient>();
  final tag = item.primaryImageTag;
  if (tag != null) {
    return client.imageApi.getPrimaryImageUrl(item.id, maxWidth: 400, tag: tag);
  }
  final album = item.albumId;
  if (album != null && item.albumPrimaryImageTag != null) {
    return client.imageApi.getPrimaryImageUrl(
      album,
      maxWidth: 400,
      tag: item.albumPrimaryImageTag,
    );
  }
  return null;
}

void kostvMusicSay(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// An album's page, to ask for it. [song] is the song it was opened from.
void openKostvMusicAlbum(
  BuildContext context,
  StremfinAlbum album, {
  String? song,
  String? preview,
}) {
  final id = album.deezerId;
  if (id == null) {
    kostvMusicSay(context, AppLocalizations.of(context).kostvMusicCantAsk);
    return;
  }
  context.push(
    Destinations.kostvMusicAlbumOf(id),
    extra: KostvMusicAlbumSeed(album: album, song: song, preview: preview),
  );
}

/// The home server's album [title] by [artist], looked for by name: the
/// artist has to match too ("Greatest Hits" is everyone's).
Future<AggregatedItem?> _albumAtHome(
  String title,
  String? artist, {
  bool failOnError = false,
}) async {
  final search = kostvMusicService().search(title);
  final found = failOnError
      ? await search
      : await search.catchError((Object _) => const KostvMusicAtHome());
  String norm(String? s) => (s ?? '').toLowerCase().trim();
  final wanted = norm(artist);
  for (final album in found.albums) {
    if (norm(album.name) != norm(title)) continue;
    final by = norm(album.albumArtist);
    if (wanted.isEmpty ||
        by.isEmpty ||
        by.contains(wanted) ||
        wanted.contains(by)) {
      return album;
    }
  }
  return null;
}

/// An album the requests service knows: at home, its page there; otherwise
/// its page to ask for it.
///
/// Kos TV: [shown] is the album's page it is pressed on («Reproducir en
/// casa»): there, one the home server has under another name (a single
/// only there inside an album) plays its first song at home rather than
/// opening that same page again.
Future<void> openKostvStremfinAlbum(
  BuildContext context,
  StremfinAlbum album, {
  StremfinAlbumDetail? shown,
}) async {
  final atHome = album.jellyfinId;
  if (atHome != null) {
    context.push(Destinations.item(atHome));
    return;
  }
  if (album.inJellyfin) {
    var match = await _albumAtHome(album.title, album.artist);
    // A single the home server has inside an album: that album.
    final inside = album.songInAlbum;
    if (match == null && inside != null) {
      match = await _albumAtHome(inside, album.artist);
    }
    if (!context.mounted) return;
    if (match != null) {
      openMusicItem(context, match);
      return;
    }
    if (shown != null) {
      final song = shown.songs
          .where((song) => song.jellyfinId != null)
          .firstOrNull;
      if (song != null) {
        await playKostvMusicTrack(
          context,
          song.jellyfinId!,
          source: KostvMusicSource.album,
        );
      } else {
        kostvMusicSay(
          context,
          AppLocalizations.of(context).kostvMusicNotFoundAtHome,
        );
      }
      return;
    }
  }
  if (context.mounted) openKostvMusicAlbum(context, album);
}

/// A song of a chart, a search or an artist: played if it is at home,
/// otherwise its album's page to ask for it.
///
/// Kos TV: [source] is where it comes from ([KostvMusicSource]). [refresh]
/// asks what the service says of [song] now (one of the week's discovery,
/// picked days ago), within the same lock: a second OK while it is asked
/// doesn't open its album twice.
Future<void> openKostvMusicSong(
  BuildContext context,
  StremfinSong song, {
  bool toAsk = false,
  String source = KostvMusicSource.other,
  Future<StremfinSong?> Function(StremfinSong song)? refresh,
}) => kostvMusicOnce(() async {
  final now = await _refreshed(context, song, refresh);
  if (now == null || !context.mounted) return;
  await _openSong(context, now, toAsk: toAsk, source: source);
});

/// Kos TV: [song] as [refresh] says it is now, with the short wait while it
/// is asked (null when [context] went meanwhile). As it was when asking
/// fails.
Future<StremfinSong?> _refreshed(
  BuildContext context,
  StremfinSong song,
  Future<StremfinSong?> Function(StremfinSong song)? refresh,
) async {
  if (refresh == null) return song;
  final closeLoading = showMusicLoading(context);
  StremfinSong? now;
  try {
    now = await refresh(song);
  } catch (_) {
  } finally {
    closeLoading();
  }
  return context.mounted ? now ?? song : null;
}

Future<void> _openSong(
  BuildContext context,
  StremfinSong song, {
  bool toAsk = false,
  String source = KostvMusicSource.other,
}) async {
  if (!toAsk && (song.inJellyfin || song.jellyfinId != null)) {
    // The service says which it is (since 1.91.0); otherwise looked for by
    // its title and artist.
    final id = song.jellyfinId;
    final music = kostvMusicService();
    final found =
        await (id != null
                ? music.item(id)
                : music.findSong(song.title, song.artist))
            .catchError((Object _) => null);
    if (!context.mounted) return;
    if (found != null) {
      await playMusicTrack(context, found, source: source);
      return;
    }
  }
  if (!context.mounted) return;
  // Kos TV: with «Toda la música», one that isn't at home plays through
  // the requests service, at once (its album is asked for from its page or
  // «Reproduciendo»).
  if (!toAsk && kostvMusicCatalogAll() && kostvSongPlayable(song)) {
    await playKostvStreamSongs(
      context,
      kostvQueueSongs([song]),
      source: source,
    );
    return;
  }
  final album = song.album;
  if (album != null) {
    openKostvMusicAlbum(
      context,
      album,
      song: song.title,
      preview: song.preview,
    );
    return;
  }
  final albumId = song.albumDeezerId;
  if (albumId != null) {
    openKostvMusicAlbum(
      context,
      StremfinAlbum(
        title: song.albumTitle ?? song.title,
        deezerId: albumId,
        artist: song.artist,
        cover: song.cover,
      ),
      song: song.title,
      preview: song.preview,
    );
    return;
  }
  if (song.inJellyfin || song.jellyfinId != null) {
    kostvMusicSay(
      context,
      AppLocalizations.of(context).kostvMusicNotFoundAtHome,
    );
  }
}

/// Kos TV: [songs] of a list of the requests service (a chart, «Para ti»,
/// the discovery, an artist's top songs) played as one queue from [index]
/// («Toda la música»): what is at home from home, the rest through the
/// service; those without a Deezer id are skipped, and so is what the
/// person doesn't want to hear (but the song picked). [shuffle] plays it
/// all in a random order. Within the same lock as [openKostvMusicSong].
Future<void> playKostvSongList(
  BuildContext context,
  List<StremfinSong> songs, {
  int index = 0,
  String source = KostvMusicSource.other,
  bool shuffle = false,
  bool picked = true,
}) => kostvMusicOnce(() async {
  final client = GetIt.instance.isRegistered<MediaServerClient>()
      ? GetIt.instance<MediaServerClient>()
      : null;
  // Kos TV: what the person doesn't want to hear, read now if it wasn't
  // (just started, another person) rather than taken as nothing.
  final dislikes = client == null
      ? KostvMusicDislikes.empty
      : await KostvMusicDislikesStore.instance
            .load(client)
            .timeout(const Duration(seconds: 3))
            .catchError(
              (Object _) => KostvMusicDislikesStore.instance.of(client),
            );
  if (!context.mounted) return;
  final kept = kostvSongsToPlay(
    songs,
    dislikes,
    index: shuffle || !picked ? -1 : index,
  );
  return playKostvStreamSongs(
    context,
    kostvQueueSongs(kept.songs),
    startIndex: kept.index,
    source: source,
    shuffle: shuffle,
    picked: picked,
  );
});

/// An artist's page.
void openKostvMusicArtist(BuildContext context, StremfinArtist artist) =>
    context.push(
      Destinations.kostvMusicArtistOf(artist.deezerId),
      extra: artist,
    );

/// A song of an album's page that is at home: it plays, with the rest of
/// its album after it.
Future<void> playKostvMusicTrack(
  BuildContext context,
  String jellyfinId, {
  String source = KostvMusicSource.album,
}) => kostvMusicOnce(() async {
  final l10n = AppLocalizations.of(context);
  final song = await kostvMusicService()
      .item(jellyfinId)
      .catchError((Object _) => null);
  if (!context.mounted) return;
  if (song == null) {
    // Kos TV: said, rather than nothing happening.
    kostvMusicSay(context, l10n.kostvMusicCantPlay);
    return;
  }
  await playMusicTrack(context, song, source: source);
});

// ------------------------------------------------------------- a song's menu

/// The artist of one of the home server's songs or albums, for its page.
String? kostvMusicArtistIdOf(AggregatedItem item) {
  for (final key in const ['AlbumArtists', 'ArtistItems']) {
    final list = item.rawData[key];
    if (list is List && list.isNotEmpty && list.first is Map) {
      final id = (list.first as Map)['Id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
  }
  return null;
}

enum _SongChoice {
  next,
  last,
  radio,
  love,
  dislike,
  undislike,
  dislikeArtist,
  playlist,
  album,
  artist,
  ask,
}

/// Kos TV: what a playlist's page adds to the menu of one of its songs that
/// isn't at home: take it out, and move it up or down (null: not offered).
@immutable
class KostvAwayListActions {
  const KostvAwayListActions({this.remove, this.moveUp, this.moveDown});

  final VoidCallback? remove;
  final VoidCallback? moveUp;
  final VoidCallback? moveDown;
}

/// A song's menu (OK held down, a long press or a right click). For one at
/// home: play it next or at the end of the queue, a station of songs like
/// it, ♥, add it to a playlist, its album and its artist. For one that
/// isn't: its album, to ask for it, and its artist.
///
/// Kos TV: [fromAlbumId] is the home server's album page it is opened on,
/// whose «Ir al álbum» would only open that same page again. [source] is
/// where the song comes from, told with «A continuación» and «Al final»
/// too. [refresh] as in [openKostvMusicSong]: one that arrived home since
/// gets the menu of one at home.
///
/// Kos TV: with «Toda la música», one that isn't at home (or [item] being
/// one) gets the menu of a song that sounds through the requests service
/// ([_streamSongMenu]); [fromAlbumDeezerId] is the album page it is opened
/// on.
Future<void> showKostvMusicSongMenu(
  BuildContext context, {
  StremfinSong? song,
  AggregatedItem? item,
  String? fromAlbumId,
  String? fromAlbumDeezerId,
  String source = KostvMusicSource.other,
  Future<StremfinSong?> Function(StremfinSong song)? refresh,
  KostvAwayListActions? listActions,
}) => kostvMusicOnce(() async {
  final now = song == null ? null : await _refreshed(context, song, refresh);
  if (!context.mounted || (song != null && now == null)) return;
  await _songMenu(
    context,
    song: now,
    item: item,
    fromAlbumId: fromAlbumId,
    fromAlbumDeezerId: fromAlbumDeezerId,
    source: source,
    listActions: listActions,
  );
});

Future<void> _songMenu(
  BuildContext context, {
  StremfinSong? song,
  AggregatedItem? item,
  String? fromAlbumId,
  String? fromAlbumDeezerId,
  String source = KostvMusicSource.other,
  KostvAwayListActions? listActions,
}) async {
  final l10n = AppLocalizations.of(context);
  // Kos TV: a song that isn't at home has a menu of its own.
  if (item != null && isKostvStream(item)) {
    await _streamSongMenu(
      context,
      item,
      fromAlbumDeezerId: fromAlbumDeezerId,
      source: source,
      listActions: listActions,
    );
    return;
  }
  var home = item;
  if (home == null &&
      song != null &&
      (song.inJellyfin || song.jellyfinId != null)) {
    final music = kostvMusicService();
    final id = song.jellyfinId;
    // Kos TV: the home server's copy is looked for first: with a slow one,
    // the short wait says something is happening.
    final closeLoading = showMusicLoading(context);
    try {
      home = await (id != null
          ? music.item(id)
          : music.findSong(song.title, song.artist));
    } catch (_) {
    } finally {
      closeLoading();
    }
    if (!context.mounted) return;
  }
  // Kos TV: not at home, with «Toda la música»: it sounds through the
  // requests service, and its menu is of one that does. Not one with a home
  // id Jellyfin didn't give (hidden by the person's parental control, or
  // not answering): what Jellyfin hides never sounds through the service,
  // as in [kostvQueueOf].
  if (home == null && song != null && kostvSongMenuFromAway(song)) {
    final stream = kostvStreamItemFromSong(
      song,
      serverId: GetIt.instance.isRegistered<MediaServerClient>()
          ? GetIt.instance<MediaServerClient>().baseUrl
          : '',
    );
    if (stream != null) {
      await _streamSongMenu(
        context,
        stream,
        album: song.album,
        fromAlbumDeezerId: fromAlbumDeezerId,
        source: source,
      );
      return;
    }
  }
  final title = home?.name ?? song?.title ?? '';
  final artistName = home == null
      ? song?.artist
      : (home.artists.isNotEmpty ? home.artists.join(', ') : home.albumArtist);
  final favorite = home?.isFavorite ?? false;
  final artistId = home == null ? null : kostvMusicArtistIdOf(home);
  // Kos TV: «No me gusta», when the server plugin keeps it. The menu opens
  // at once with what is known; the list is read meanwhile if it wasn't
  // lately (for the next time).
  if (home != null) unawaited(kostvMusicDislikesReady(home));
  final canDislike = home != null && kostvMusicCanDislike(home);
  final disliked = canDislike && kostvMusicDisliked(home.id, home);
  // Kos TV: the song's own artist, not its album's (a compilation's song
  // isn't by «Various Artists»), as the server plugin leaves them out.
  final songArtist = home == null ? null : kostvMusicSongArtist(home);
  final artistToDislike =
      canDislike &&
          songArtist != null &&
          !kostvMusicDisliked(songArtist.id, home)
      ? songArtist
      : null;
  final choice = await showKostvMusicMenu<_SongChoice>(
    context,
    title: title,
    subtitle: artistName,
    entries: [
      if (home != null) ...[
        KostvMenuEntry(
          _SongChoice.next,
          Icons.playlist_play_rounded,
          l10n.kostvMusicPlayNext,
        ),
        KostvMenuEntry(
          _SongChoice.last,
          Icons.queue_music_rounded,
          l10n.kostvMusicPlayLast,
        ),
        KostvMenuEntry(
          _SongChoice.radio,
          Icons.radio_rounded,
          l10n.kostvMusicRadio,
        ),
        KostvMenuEntry(
          _SongChoice.love,
          favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          favorite ? l10n.kostvPlayerUnfavorite : l10n.kostvPlayerFavorite,
        ),
        if (canDislike)
          disliked
              ? KostvMenuEntry(
                  _SongChoice.undislike,
                  Icons.thumb_down_rounded,
                  l10n.kostvMusicUndislike,
                )
              : KostvMenuEntry(
                  _SongChoice.dislike,
                  Icons.thumb_down_outlined,
                  l10n.kostvMusicDislike,
                ),
        if (artistToDislike != null)
          KostvMenuEntry(
            _SongChoice.dislikeArtist,
            Icons.person_off_outlined,
            l10n.kostvMusicDislikeArtistNamed(artistToDislike.name),
          ),
        KostvMenuEntry(
          _SongChoice.playlist,
          Icons.playlist_add_rounded,
          l10n.kostvPlayerAddToPlaylist,
        ),
        if (home.albumId != null && home.albumId != fromAlbumId)
          KostvMenuEntry(
            _SongChoice.album,
            Icons.album_rounded,
            l10n.kostvPlayerGoToAlbum,
          ),
        if (artistId != null)
          KostvMenuEntry(
            _SongChoice.artist,
            Icons.person_rounded,
            l10n.kostvPlayerGoToArtist,
          ),
      ] else if (song != null) ...[
        KostvMenuEntry(
          _SongChoice.ask,
          Icons.album_rounded,
          l10n.kostvMusicSeeAlbumToAsk,
        ),
        if (song.artistDeezerId != null)
          KostvMenuEntry(
            _SongChoice.artist,
            Icons.person_rounded,
            l10n.kostvPlayerGoToArtist,
          ),
      ],
    ],
  );
  if (choice == null || !context.mounted) return;
  final manager = GetIt.instance<PlaybackManager>();
  final queue = manager.queueService;
  // Music sounding (an audiobook's queue isn't one to add songs to).
  final musicPlaying = KostvNowPlaying.instance.item?.type == 'Audio';
  switch (choice) {
    case _SongChoice.next:
    case _SongChoice.last:
      if (!musicPlaying) {
        await playMusicTracks(context, [home!], source: source);
        return;
      }
      // Kos TV: added to what sounds, it is told where it comes from too.
      final client = GetIt.instance.isRegistered<MediaServerClient>()
          ? GetIt.instance<MediaServerClient>()
          : null;
      kostvTellMusicSource(() => client, source, [home!]);
      if (choice == _SongChoice.next) {
        queue.insertNext(home);
        kostvMusicSay(context, l10n.kostvMusicAddedNext);
      } else {
        queue.addToQueue(home);
        kostvMusicSay(context, l10n.kostvMusicAddedLast);
      }
    case _SongChoice.radio:
      final seed = home!;
      // Kos TV: with «Toda la música», the requests service's radio of its
      // artists too, mixed in turns with the home server's mix.
      if (kostvStationWantsRadio(seed)) {
        await playKostvStation(context, seed);
        return;
      }
      final mix = await kostvMusicService()
          .mix(seed.id)
          .catchError((Object _) => const <AggregatedItem>[]);
      if (!context.mounted) return;
      await playMusicTracks(context, [
        seed,
        for (final other in mix)
          if (other.id != seed.id) other,
      ], source: KostvMusicSource.radio);
    case _SongChoice.love:
      try {
        await GetIt.instance<ItemMutationRepository>().setFavorite(
          home!.id,
          isFavorite: !favorite,
        );
        // Kept on the item too, for the next time its menu opens.
        final data = Map<String, dynamic>.from(
          (home.rawData['UserData'] as Map?) ?? const {},
        );
        data['IsFavorite'] = !favorite;
        home.rawData['UserData'] = data;
        kostvMusicFavoritesChanged.value++;
        if (context.mounted) {
          kostvMusicSay(
            context,
            favorite ? l10n.kostvMusicUnloved : l10n.kostvMusicLoved,
          );
        }
      } catch (_) {
        if (context.mounted) kostvMusicSay(context, l10n.kostvMusicCantChange);
      }
    case _SongChoice.dislike:
      await kostvDislikeSong(context, home!);
    case _SongChoice.undislike:
      await kostvUndislike(context, id: home!.id, name: home.name, from: home);
    case _SongChoice.dislikeArtist:
      await kostvDislikeArtist(
        context,
        id: artistToDislike!.id,
        name: artistToDislike.name,
        from: home,
      );
    case _SongChoice.playlist:
      await AddToPlaylistDialog.show(
        context,
        itemIds: [home!.id],
        serverId: home.serverId,
        songs: kostvPlaylistSongsOf(home),
      );
    case _SongChoice.album:
      unawaited(
        context.push(
          Destinations.item(home!.albumId!, serverId: home.serverId),
        ),
      );
    case _SongChoice.artist:
      if (home != null) {
        unawaited(
          context.push(Destinations.item(artistId!, serverId: home.serverId)),
        );
      } else {
        openKostvMusicArtist(
          context,
          StremfinArtist(
            deezerId: song!.artistDeezerId!,
            name: song.artist ?? '',
          ),
        );
      }
    case _SongChoice.ask:
      await _openSong(context, song!, toAsk: true);
  }
}

/// Kos TV: the home server's artist named [name] (the same name, not
/// minding case), or null: «No me pongas a …» of a song that isn't at home
/// goes by them (what plays by itself is the home server's, and the server
/// plugin knows its artists by their id there).
Future<AggregatedItem?> kostvHomeArtistNamed(String name) async {
  final wanted = name.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  final found = await kostvMusicService().search(name);
  return found.artists
      .where((a) => a.name.trim().toLowerCase() == wanted)
      .firstOrNull;
}

enum _StreamChoice {
  next,
  last,
  radio,
  love,
  playlist,
  remove,
  moveUp,
  moveDown,
  dislike,
  undislike,
  dislikeArtist,
  album,
  artist,
  ask,
}

/// Kos TV: the menu of a song that isn't at home, heard through the
/// requests service («Toda la música»): play it next or at the end of the
/// queue, a station around it, «No me gusta» (by its Deezer id) and «No me
/// pongas a …» (when its artist is at home), its album and its artist, and
/// «Pedir álbum» with how it stands (Pedido, De camino…). Nothing of the
/// home server's own: it isn't there. [album] is its album as the list it
/// comes from knows it.
///
/// Kos TV: ♥ and «Añadir a una lista» too when the server plugin keeps them
/// for songs that aren't at home ([kostvAwayCanKeep]); [listActions] from a
/// playlist's page. With «Solo la de casa» (a playlist's grey song) it
/// doesn't offer to play it.
Future<void> _streamSongMenu(
  BuildContext context,
  AggregatedItem stream, {
  StremfinAlbum? album,
  String? fromAlbumDeezerId,
  String source = KostvMusicSource.other,
  KostvAwayListActions? listActions,
}) async {
  final l10n = AppLocalizations.of(context);
  final info = KostvStreamInfo.of(stream)!;
  final albumId = info.albumDeezerId ?? album?.deezerId;
  final artistName =
      stream.artists.where((a) => a.trim().isNotEmpty).firstOrNull ??
      stream.albumArtist;
  var known =
      album ?? (albumId == null ? null : KostvStreamAlbums.known(albumId));
  AggregatedItem? homeArtist;
  // What the menu says of its album and its artist, looked for meanwhile
  // (with a slow service or home server, a short wait at most).
  final closeLoading = showMusicLoading(context);
  try {
    await Future.wait<void>([
      kostvMusicDislikesReady(stream),
      kostvAwayReady(stream),
      if (albumId != null)
        KostvStreamAlbums.read(albumId).then((found) {
          known = found ?? known;
        }),
    ]).timeout(const Duration(seconds: 4));
    // Kos TV: its artist at home goes by the home id, which a plugin from
    // before «Toda la música» keeps too.
    if (artistName != null && kostvMusicCanDislike()) {
      homeArtist = await kostvHomeArtistNamed(artistName)
          .timeout(const Duration(seconds: 3));
    }
  } catch (_) {
  } finally {
    closeLoading();
  }
  if (!context.mounted) return;
  final canDislike = kostvMusicCanDislike(stream);
  final disliked = canDislike && kostvMusicDisliked(stream.id, stream);
  final canKeep = kostvAwayCanKeep(stream);
  final loved = canKeep && kostvAwayLoved(stream);
  final playable = listActions == null || kostvAwayPlayable(stream);
  final artistToDislike =
      kostvMusicCanDislike() &&
          homeArtist != null &&
          !kostvMusicDisliked(homeArtist.id, stream)
      ? homeArtist
      : null;
  final askState = kostvStreamAlbumState(
    l10n,
    known,
    hasAlbum: albumId != null,
  );
  // Its artist's page: the song's own id or, from a chart (which doesn't
  // give it), its album's artist when it is the same one.
  String? fold(String? name) => name?.trim().toLowerCase();
  final artistDeezerId =
      info.artistDeezerId ??
      (albumId != null &&
              (artistName == null || fold(known?.artist) == fold(artistName))
          ? KostvStreamAlbums.artistOf(albumId)
          : null);
  final choice = await showKostvMusicMenu<_StreamChoice>(
    context,
    title: stream.name,
    subtitle: [?artistName, l10n.kostvStreamOutOfHome].join(' · '),
    entries: [
      if (playable) ...[
        KostvMenuEntry(
          _StreamChoice.next,
          Icons.playlist_play_rounded,
          l10n.kostvMusicPlayNext,
        ),
        KostvMenuEntry(
          _StreamChoice.last,
          Icons.queue_music_rounded,
          l10n.kostvMusicPlayLast,
        ),
        KostvMenuEntry(
          _StreamChoice.radio,
          Icons.radio_rounded,
          l10n.kostvMusicRadio,
        ),
      ],
      if (canKeep) ...[
        KostvMenuEntry(
          _StreamChoice.love,
          loved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          loved ? l10n.kostvPlayerUnfavorite : l10n.kostvPlayerFavorite,
        ),
        KostvMenuEntry(
          _StreamChoice.playlist,
          Icons.playlist_add_rounded,
          l10n.kostvPlayerAddToPlaylist,
        ),
      ],
      if (listActions?.remove != null)
        KostvMenuEntry(
          _StreamChoice.remove,
          Icons.playlist_remove_rounded,
          l10n.trackActionDeleteFromPlaylist,
        ),
      if (listActions?.moveUp != null)
        KostvMenuEntry(
          _StreamChoice.moveUp,
          Icons.arrow_upward_rounded,
          l10n.trackActionMoveUp,
        ),
      if (listActions?.moveDown != null)
        KostvMenuEntry(
          _StreamChoice.moveDown,
          Icons.arrow_downward_rounded,
          l10n.trackActionMoveDown,
        ),
      if (canDislike)
        disliked
            ? KostvMenuEntry(
                _StreamChoice.undislike,
                Icons.thumb_down_rounded,
                l10n.kostvMusicUndislike,
              )
            : KostvMenuEntry(
                _StreamChoice.dislike,
                Icons.thumb_down_outlined,
                l10n.kostvMusicDislike,
              ),
      if (artistToDislike != null)
        KostvMenuEntry(
          _StreamChoice.dislikeArtist,
          Icons.person_off_outlined,
          l10n.kostvMusicDislikeArtistNamed(artistToDislike.name),
        ),
      if (albumId != null && albumId != fromAlbumDeezerId)
        KostvMenuEntry(
          _StreamChoice.album,
          Icons.album_rounded,
          l10n.kostvPlayerGoToAlbum,
        ),
      if (artistDeezerId != null)
        KostvMenuEntry(
          _StreamChoice.artist,
          Icons.person_rounded,
          l10n.kostvPlayerGoToArtist,
        ),
      if (askState != null)
        KostvMenuEntry(_StreamChoice.ask, askState.icon, askState.label),
    ],
  );
  if (choice == null || !context.mounted) return;
  // Music sounding (an audiobook's queue isn't one to add songs to).
  final musicPlaying = KostvNowPlaying.instance.item?.type == 'Audio';
  switch (choice) {
    case _StreamChoice.next:
    case _StreamChoice.last:
      if (!musicPlaying) {
        await playMusicTracks(context, [stream], source: source);
        return;
      }
      final queue = GetIt.instance<PlaybackManager>().queueService;
      if (choice == _StreamChoice.next) {
        queue.insertNext(stream);
        kostvMusicSay(context, l10n.kostvMusicAddedNext);
      } else {
        queue.addToQueue(stream);
        kostvMusicSay(context, l10n.kostvMusicAddedLast);
      }
    case _StreamChoice.radio:
      await playKostvStation(context, stream);
    case _StreamChoice.love:
      await kostvAwayToggleLove(context, stream);
    case _StreamChoice.playlist:
      await kostvAwayAddToPlaylist(context, stream);
    case _StreamChoice.remove:
      listActions!.remove!();
    case _StreamChoice.moveUp:
      listActions!.moveUp!();
    case _StreamChoice.moveDown:
      listActions!.moveDown!();
    case _StreamChoice.dislike:
      await kostvDislikeSong(context, stream);
    case _StreamChoice.undislike:
      await kostvUndislike(
        context,
        id: stream.id,
        name: stream.name,
        from: stream,
      );
    case _StreamChoice.dislikeArtist:
      await kostvDislikeArtist(
        context,
        id: artistToDislike!.id,
        name: artistToDislike.name,
        from: stream,
      );
    case _StreamChoice.album:
      await openKostvStremfinAlbum(
        context,
        known ??
            StremfinAlbum(
              title: info.albumTitle ?? stream.album ?? stream.name,
              deezerId: albumId,
              artist: stream.albumArtist ?? artistName,
              cover: info.cover,
            ),
      );
    case _StreamChoice.artist:
      openKostvMusicArtist(
        context,
        StremfinArtist(deezerId: artistDeezerId!, name: artistName ?? ''),
      );
    case _StreamChoice.ask:
      if (askState!.can) {
        await kostvStreamAskAlbum(
          context,
          albumId!,
          title: known?.title ?? info.albumTitle,
          artist: known?.artist ?? stream.albumArtist,
        );
      } else {
        kostvMusicSay(context, askState.label);
      }
  }
}

/// Plays the album the requests service knows as [deezerId] once it is at
/// home (a request that arrived). False when the home server doesn't have
/// it yet: Jellyfin takes a moment to find what arrives.
///
/// Kos TV: the short wait shows while it is looked for; when looking fails
/// (the service or the home server not answering), it says so itself and
/// answers true: that isn't «not there yet».
Future<bool> playKostvArrivedAlbum(
  BuildContext context,
  String deezerId,
) async {
  if (!GetIt.instance.isRegistered<StremfinService>()) return false;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final closeLoading = showMusicLoading(context);
  final List<AggregatedItem> songs;
  try {
    final detail = await GetIt.instance<StremfinService>().musicAlbum(deezerId);
    var albumId = detail.album.jellyfinId;
    final music = kostvMusicService();
    // The service doesn't know it at home yet (or is older than 1.91.0):
    // looked for by its title and artist.
    albumId ??= (await _albumAtHome(
      detail.album.title,
      detail.album.artist,
      failOnError: true,
    ))?.id;
    if (albumId == null) {
      closeLoading();
      return false;
    }
    songs = await music.albumSongs(albumId);
  } catch (e) {
    closeLoading();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            kostvStremfinErrorText(
              l10n,
              e,
              fallback: l10n.kostvMusicCantLookNow,
            ),
          ),
        ),
      );
    return true;
  }
  closeLoading();
  if (songs.isEmpty || !context.mounted) return false;
  await playMusicTracks(context, songs, source: KostvMusicSource.album);
  return true;
}
