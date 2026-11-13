import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:playback_core/playback_core.dart' show PlaybackManager;
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/item_mutation_repository.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_now_playing.dart';
import '../../widgets/music/music_navigation.dart';
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
  if (album.download != null) return KostvMusicBadge.onItsWay;
  if (album.request != null) return KostvMusicBadge.asked;
  if (album.inJellyfin) return KostvMusicBadge.none;
  return album.canRequest ? KostvMusicBadge.ask : KostvMusicBadge.none;
}

/// The cover of one of the home server's items (a song shows its album's).
String? kostvMusicImageOf(AggregatedItem item) {
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
Future<AggregatedItem?> _albumAtHome(String title, String? artist) async {
  final found = await kostvMusicService()
      .search(title)
      .catchError((Object _) => const KostvMusicAtHome());
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
Future<void> openKostvStremfinAlbum(
  BuildContext context,
  StremfinAlbum album,
) async {
  final atHome = album.jellyfinId;
  if (atHome != null) {
    context.push(Destinations.item(atHome));
    return;
  }
  if (album.inJellyfin) {
    final match = await _albumAtHome(album.title, album.artist);
    if (!context.mounted) return;
    if (match != null) {
      openMusicItem(context, match);
      return;
    }
  }
  if (context.mounted) openKostvMusicAlbum(context, album);
}

/// A song of a chart, a search or an artist: played if it is at home,
/// otherwise its album's page to ask for it.
Future<void> openKostvMusicSong(
  BuildContext context,
  StremfinSong song, {
  bool toAsk = false,
}) => kostvMusicOnce(() => _openSong(context, song, toAsk: toAsk));

Future<void> _openSong(
  BuildContext context,
  StremfinSong song, {
  bool toAsk = false,
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
      await playMusicTrack(context, found);
      return;
    }
  }
  if (!context.mounted) return;
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

/// An artist's page.
void openKostvMusicArtist(BuildContext context, StremfinArtist artist) =>
    context.push(
      Destinations.kostvMusicArtistOf(artist.deezerId),
      extra: artist,
    );

/// A song of an album's page that is at home: it plays, with the rest of
/// its album after it.
Future<void> playKostvMusicTrack(BuildContext context, String jellyfinId) =>
    kostvMusicOnce(() async {
      final song = await kostvMusicService()
          .item(jellyfinId)
          .catchError((Object _) => null);
      if (song != null && context.mounted) await playMusicTrack(context, song);
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

enum _SongChoice { next, last, radio, love, playlist, album, artist, ask }

/// A song's menu (OK held down, a long press or a right click). For one at
/// home: play it next or at the end of the queue, a station of songs like
/// it, ♥, add it to a playlist, its album and its artist. For one that
/// isn't: its album, to ask for it, and its artist.
Future<void> showKostvMusicSongMenu(
  BuildContext context, {
  StremfinSong? song,
  AggregatedItem? item,
}) => kostvMusicOnce(() => _songMenu(context, song: song, item: item));

Future<void> _songMenu(
  BuildContext context, {
  StremfinSong? song,
  AggregatedItem? item,
}) async {
  final l10n = AppLocalizations.of(context);
  var home = item;
  if (home == null &&
      song != null &&
      (song.inJellyfin || song.jellyfinId != null)) {
    final music = kostvMusicService();
    final id = song.jellyfinId;
    try {
      home = await (id != null
          ? music.item(id)
          : music.findSong(song.title, song.artist));
    } catch (_) {}
    if (!context.mounted) return;
  }
  final title = home?.name ?? song?.title ?? '';
  final artistName = home == null
      ? song?.artist
      : (home.artists.isNotEmpty ? home.artists.join(', ') : home.albumArtist);
  final favorite = home?.isFavorite ?? false;
  final artistId = home == null ? null : kostvMusicArtistIdOf(home);
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
        KostvMenuEntry(
          _SongChoice.playlist,
          Icons.playlist_add_rounded,
          l10n.kostvPlayerAddToPlaylist,
        ),
        if (home.albumId != null)
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
        await playMusicTracks(context, [home!]);
        return;
      }
      if (choice == _SongChoice.next) {
        queue.insertNext(home!);
        kostvMusicSay(context, l10n.kostvMusicAddedNext);
      } else {
        queue.addToQueue(home!);
        kostvMusicSay(context, l10n.kostvMusicAddedLast);
      }
    case _SongChoice.radio:
      final seed = home!;
      final mix = await kostvMusicService()
          .mix(seed.id)
          .catchError((Object _) => const <AggregatedItem>[]);
      if (!context.mounted) return;
      await playMusicTracks(context, [
        seed,
        for (final other in mix)
          if (other.id != seed.id) other,
      ]);
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
    case _SongChoice.playlist:
      await AddToPlaylistDialog.show(
        context,
        itemIds: [home!.id],
        serverId: home.serverId,
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

/// Plays the album the requests service knows as [deezerId] once it is at
/// home (a request that arrived). False when the home server doesn't have
/// it yet: Jellyfin takes a moment to find what arrives.
Future<bool> playKostvArrivedAlbum(
  BuildContext context,
  String deezerId,
) async {
  if (!GetIt.instance.isRegistered<StremfinService>()) return false;
  try {
    final detail = await GetIt.instance<StremfinService>().musicAlbum(deezerId);
    var albumId = detail.album.jellyfinId;
    final music = kostvMusicService();
    // The service doesn't know it at home yet (or is older than 1.91.0):
    // looked for by its title and artist.
    albumId ??= (await _albumAtHome(
      detail.album.title,
      detail.album.artist,
    ))?.id;
    if (albumId == null) return false;
    final songs = await music.albumSongs(albumId);
    if (songs.isEmpty || !context.mounted) return false;
    await playMusicTracks(context, songs);
    return true;
  } catch (_) {
    return false;
  }
}
