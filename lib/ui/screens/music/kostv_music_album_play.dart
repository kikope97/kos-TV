import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music_catalog.dart';
import '../../../data/services/kostv_music_plugin.dart' show KostvMusicSource;
import '../../../data/services/stremfin/stremfin_error_text.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/music/kostv_stream_play.dart';
import '../../widgets/music/music_navigation.dart';
import 'kostv_music_actions.dart';

/// Kos TV: the ▶ of an album's card (`docs/diseno-musica`): the album
/// plays whole from its first song, as «Reproducir» on its page, without
/// opening it.

/// Whether a card of [album] has its ▶: at home, or heard through the
/// requests service («Toda la música»). With «Solo la de casa» one that
/// isn't at home only opens (its page asks for it).
bool kostvStremfinAlbumPlays(StremfinAlbum album) =>
    album.inJellyfin || album.jellyfinId != null || kostvMusicCatalogAll();

/// Plays the home server's [album] (a card's ▶).
Future<void> playKostvHomeAlbum(BuildContext context, AggregatedItem album) =>
    kostvMusicOnce(() async {
      final l10n = AppLocalizations.of(context);
      final closeLoading = showMusicLoading(context);
      List<AggregatedItem> songs;
      try {
        songs = await kostvMusicService().albumSongs(album.id);
      } catch (_) {
        songs = const [];
      }
      closeLoading();
      if (!context.mounted) return;
      if (songs.isEmpty) {
        kostvMusicSay(context, l10n.kostvMusicCantPlay);
        return;
      }
      await playMusicTracks(context, songs, source: KostvMusicSource.album);
    });

/// Plays an album the requests service knows (a card's ▶): at home from
/// home, otherwise through the service; one that can't be heard opens its
/// page instead.
Future<void> playKostvStremfinAlbum(
  BuildContext context,
  StremfinAlbum album,
) async {
  final home = album.jellyfinId;
  final id = album.deezerId;
  final service = GetIt.instance.isRegistered<StremfinService>()
      ? GetIt.instance<StremfinService>()
      : null;
  if (home == null && (id == null || service == null)) {
    await openKostvStremfinAlbum(context, album);
    return;
  }
  var open = false;
  await kostvMusicOnce(() async {
    final l10n = AppLocalizations.of(context);
    if (home != null) {
      final closeLoading = showMusicLoading(context);
      List<AggregatedItem> songs;
      try {
        songs = await kostvMusicService().albumSongs(home);
      } catch (_) {
        songs = const [];
      }
      closeLoading();
      if (!context.mounted) return;
      if (songs.isEmpty) {
        open = true;
        return;
      }
      await playMusicTracks(context, songs, source: KostvMusicSource.album);
      return;
    }
    if (album.inJellyfin) {
      // At home under an id the service doesn't give: found by its name.
      open = !await playKostvArrivedAlbum(context, id!);
      return;
    }
    final closeLoading = showMusicLoading(context);
    final StremfinAlbumDetail detail;
    try {
      detail = await service!.musicAlbum(id!);
    } catch (e) {
      closeLoading();
      if (context.mounted) {
        kostvMusicSay(
          context,
          kostvStremfinErrorText(l10n, e, fallback: l10n.kostvMusicUnavailable),
        );
      }
      return;
    }
    closeLoading();
    if (!context.mounted) return;
    final plays =
        kostvMusicCatalogAll() &&
        detail.songs.any((song) => kostvTrackPlayable(song));
    if (!plays || detail.albumInstead != null) {
      open = true;
      return;
    }
    await playKostvStreamSongs(
      context,
      kostvAlbumQueueSongs(detail),
      source: KostvMusicSource.album,
    );
  });
  if (open && context.mounted) await openKostvStremfinAlbum(context, album);
}
