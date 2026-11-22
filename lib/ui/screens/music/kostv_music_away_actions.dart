import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music_away.dart';
import '../../../data/services/stremfin/kostv_stream_song.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../home/kostv_undo_toast.dart';
import 'kostv_music_actions.dart' show kostvMusicFavoritesChanged;
import 'kostv_music_dislike.dart' show kostvMusicClientOf, kostvFocusInTree;
import 'kostv_stream_widgets.dart';

/// Kos TV: «Añadir a una lista» and ♥ of a song that isn't at home, which
/// the server plugin keeps for Jellyfin («Listas y ♥ con canciones de
/// fuera»). Neither asks for its album by itself: the notice after offers
/// it («Añadida. ¿Pedir el álbum para tenerla en casa?»).

/// How long the notice offers to ask for the album.
const kostvAwayOfferTime = Duration(seconds: 8);

/// Kos TV: whether [stream]'s server keeps songs that aren't at home in
/// playlists and ♥ (read at least once; a plugin from before it, never).
bool kostvAwayCanKeep(AggregatedItem? stream) =>
    isKostvStream(stream) &&
    KostvMusicAwayStore.instance.supported(kostvMusicClientOf(stream));

/// Kos TV: reads whether [item]'s server keeps them, and the person's ♥,
/// if it wasn't read lately: for a menu or a page about to offer it.
Future<void> kostvAwayReady([AggregatedItem? item]) async {
  final client = kostvMusicClientOf(item);
  if (client == null) return;
  try {
    await KostvMusicAwayStore.instance
        .load(client)
        .timeout(const Duration(seconds: 3));
  } catch (_) {}
}

/// Kos TV: whether the person gave [stream] (not at home) a ♥.
bool kostvAwayLoved(AggregatedItem stream) {
  final deezerId = kostvStreamDeezerId(stream);
  return deezerId != null &&
      KostvMusicAwayStore.instance.isFavorite(
        kostvMusicClientOf(stream),
        deezerId,
      );
}

/// Kos TV: gives [stream] the person's ♥, or takes it away. With one given,
/// the notice offers to ask for its album.
Future<void> kostvAwayToggleLove(
  BuildContext context,
  AggregatedItem stream,
) async {
  final client = kostvMusicClientOf(stream);
  if (client == null) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final on = !kostvAwayLoved(stream);
  final (:done, :full) = await KostvMusicAwayStore.instance.setFavorite(
    client,
    stream,
    on: on,
  );
  if (done) kostvMusicFavoritesChanged.value++;
  final failed = full ? l10n.kostvAwayFavoritesFull : l10n.kostvMusicCantChange;
  if (!context.mounted) {
    if (!done) _say(messenger, failed);
    return;
  }
  if (!done) {
    _say(messenger, failed);
  } else if (on) {
    kostvAwayOfferAlbum(context, stream, done: l10n.kostvMusicLoved);
  } else {
    _say(messenger, l10n.kostvMusicUnloved);
  }
}

/// Kos TV: «Añadir a una lista» of [stream]: the playlists as always (and
/// «Nueva lista», made empty first); once added, the notice offers to ask
/// for its album.
Future<void> kostvAwayAddToPlaylist(
  BuildContext context,
  AggregatedItem stream,
) async {
  final added = await AddToPlaylistDialog.show(
    context,
    itemIds: const [],
    serverId: stream.serverId,
    awaySongs: [stream],
  );
  if (added != true || !context.mounted) return;
  kostvAwayOfferAlbum(
    context,
    stream,
    done: AppLocalizations.of(context).kostvAwayAdded,
  );
}

void _say(ScaffoldMessengerState? messenger, String message) => messenger
  ?..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// Kos TV: what was done with [stream] said, with «Pedir álbum» when its
/// album can be asked for («Añadida. ¿Pedir el álbum para tenerla en
/// casa?»); otherwise just [done]. With a remote the button takes the
/// focus, and any other key gives it back to where it was.
void kostvAwayOfferAlbum(
  BuildContext context,
  AggregatedItem stream, {
  required String done,
}) {
  final l10n = AppLocalizations.of(context);
  final info = KostvStreamInfo.of(stream);
  final albumId = info?.albumDeezerId;
  final state = albumId == null
      ? null
      : kostvStreamAlbumState(
          l10n,
          KostvStreamAlbums.known(albumId),
          hasAlbum: true,
        );
  if (state == null || !state.can) {
    _say(ScaffoldMessenger.maybeOf(context), done);
    return;
  }
  final overlay = Overlay.of(context, rootOverlay: true);
  final remote = InputModeTracker.of(context) == InputMode.keyboard;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!overlay.mounted) return;
    final before = FocusManager.instance.primaryFocus;
    void backToWhereItWas() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (kostvFocusInTree(before)) before!.requestFocus();
      });
    }

    showKostvUndoToastOn(
      overlay,
      message: l10n.kostvAwayAddedAskAlbum,
      undoLabel: l10n.kostvStreamAskAlbum,
      icon: Icons.album_rounded,
      duration: kostvAwayOfferTime,
      takeFocus: remote,
      onUndo: () {
        if (remote) backToWhereItWas();
        final where = context.mounted ? context : overlay.context;
        if (!where.mounted) return;
        unawaited(
          kostvStreamAskAlbum(
            where,
            albumId!,
            title: info?.albumTitle ?? stream.album,
            artist: stream.albumArtist,
          ),
        );
      },
      onLeave: backToWhereItWas,
    );
  });
}
