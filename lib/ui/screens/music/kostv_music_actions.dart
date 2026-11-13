import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/destinations.dart';
import '../../widgets/music/music_navigation.dart';
import 'kostv_music_widgets.dart';

/// Kos TV: what the Music pages do when something is picked: what is at
/// home plays or opens there; what isn't opens its album's page, to ask
/// for the whole album.

KostvMusicService kostvMusicService() =>
    KostvMusicService(GetIt.instance<MediaServerClient>());

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
    final found = await kostvMusicService()
        .search(album.title)
        .catchError((Object _) => const KostvMusicAtHome());
    if (!context.mounted) return;
    final match = found.albums.firstOrNull;
    if (match != null) {
      openMusicItem(context, match);
      return;
    }
  }
  if (context.mounted) openKostvMusicAlbum(context, album);
}

/// A song of a chart, a search or an artist: played if it is at home,
/// otherwise its album's page to ask for it.
Future<void> openKostvMusicSong(BuildContext context, StremfinSong song) async {
  if (song.inJellyfin || song.jellyfinId != null) {
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
Future<void> playKostvMusicTrack(
  BuildContext context,
  String jellyfinId,
) async {
  final song = await kostvMusicService()
      .item(jellyfinId)
      .catchError((Object _) => null);
  if (song != null && context.mounted) await playMusicTrack(context, song);
}
