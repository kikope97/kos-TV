import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music_dislikes.dart';
import '../../../data/services/kostv_music_plugin.dart'
    show KostvMusicDisliked, KostvMusicDislikes;
import '../../../data/services/media_server_client_factory.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../widgets/music/kostv_now_playing.dart';
import '../home/kostv_undo_toast.dart';

/// Kos TV: «No me gusta» of a song and «No me pongas a este artista»: what
/// the menus and the player's button do. Left out at once (the song
/// sounding is skipped, and what is still to play loses it), with a few
/// seconds to take it back, as «No me interesa» does on Home.

/// How long the notice offers to take it back.
const kostvMusicDislikeUndoTime = Duration(seconds: 5);

/// Kos TV: the client of [item]'s server (the signed-in one without an
/// item), or null when there is none.
MediaServerClient? kostvMusicClientOf([AggregatedItem? item]) {
  final getIt = GetIt.instance;
  try {
    if (item != null &&
        item.serverId.isNotEmpty &&
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

/// Kos TV: whether «No me gusta» is offered for [item]'s server: its plugin
/// keeps the list (read at least once; a plugin from before it, never).
bool kostvMusicCanDislike([AggregatedItem? item]) =>
    KostvMusicDislikesStore.instance.supported(kostvMusicClientOf(item));

/// Kos TV: reads whether [item]'s server keeps the list, and the list, if
/// it wasn't read lately: for a menu or a page about to offer it.
Future<void> kostvMusicDislikesReady([AggregatedItem? item]) async {
  final client = kostvMusicClientOf(item);
  if (client == null) return;
  try {
    await KostvMusicDislikesStore.instance
        .load(client)
        .timeout(const Duration(seconds: 3));
  } catch (_) {}
}

/// Kos TV: whether the person said no to [id] (a song or an artist).
bool kostvMusicDisliked(String id, [AggregatedItem? item]) =>
    KostvMusicDislikesStore.instance.of(kostvMusicClientOf(item)).has(id);

void _say(ScaffoldMessengerState? messenger, String message) => messenger
  ?..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// Shows the notice with its «Deshacer»: with a remote its button takes
/// the focus, and any other key gives it back to where it was.
void _offerUndo(
  BuildContext context, {
  required String message,
  required Future<void> Function() undo,
}) {
  final l10n = AppLocalizations.of(context);
  final overlay = Overlay.of(context, rootOverlay: true);
  final remote = InputModeTracker.of(context) == InputMode.keyboard;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!overlay.mounted) return;
    final before = FocusManager.instance.primaryFocus;
    void backToWhereItWas() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (before != null &&
            before.context != null &&
            before.canRequestFocus) {
          before.requestFocus();
        }
      });
    }

    showKostvUndoToastOn(
      overlay,
      message: message,
      undoLabel: l10n.kostvUndo,
      duration: kostvMusicDislikeUndoTime,
      takeFocus: remote,
      onUndo: () {
        if (remote) backToWhereItWas();
        unawaited(undo());
      },
      onLeave: backToWhereItWas,
    );
  });
}

/// «No me gusta» of [song]: skipped if it is sounding, taken out of what is
/// still to play, kept by the server plugin, and a few seconds to take it
/// back.
Future<void> kostvDislikeSong(BuildContext context, AggregatedItem song) async {
  final client = kostvMusicClientOf(song);
  if (client == null) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final store = KostvMusicDislikesStore.instance;
  final music = KostvNowPlaying.instance;
  final id = song.id;
  final kept = store.dislikeSong(client, song);
  final left = music.leaveOutUpcoming((other) => other.id == id);
  final skipped = music.skipIfSounding(id);
  if (context.mounted) {
    _offerUndo(
      context,
      message: l10n.kostvMusicDislikedSong(song.name),
      undo: () async {
        // Kos TV: back where it was in the queue, and back to it if it was
        // the one sounding, as «No me interesa» puts the card back on Home.
        music.putBack(left, skipped: skipped);
        // Not before the plugin kept it: the undo would land first.
        await kept;
        if (!await store.remove(client, id)) {
          _say(messenger, l10n.kostvMusicDislikeFailed);
        }
      },
    );
  }
  if (!await kept) _say(messenger, l10n.kostvMusicDislikeFailed);
}

/// «No me pongas a este artista» of the artist [id], named [name]: their
/// songs go out of what is still to play by itself, and a few seconds to
/// take it back.
Future<void> kostvDislikeArtist(
  BuildContext context, {
  required String id,
  required String name,
  AggregatedItem? from,
}) async {
  final client = kostvMusicClientOf(from);
  if (client == null) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final store = KostvMusicDislikesStore.instance;
  final kept = store.dislikeArtist(client, id: id, name: name);
  // Kos TV: only this artist's songs go (and come back with «Deshacer»),
  // not others the person said no to before.
  final dislikes = KostvMusicDislikes(
    artists: [
      KostvMusicDisliked(id: id.replaceAll('-', ''), name: name, artist: true),
    ],
  );
  final music = KostvNowPlaying.instance;
  final left = music.leaveOutUpcoming(dislikes.songOut, onlyAutomatic: true);
  if (context.mounted) {
    _offerUndo(
      context,
      message: l10n.kostvMusicDislikedArtist(name),
      undo: () async {
        // Kos TV: their songs back where they were in what is to play.
        music.putBack(left);
        await kept;
        if (!await store.remove(client, id)) {
          _say(messenger, l10n.kostvMusicDislikeFailed);
        }
      },
    );
  }
  if (!await kept) _say(messenger, l10n.kostvMusicDislikeFailed);
}

/// Takes [id] (named [name]) off what the person doesn't want to hear.
Future<void> kostvUndislike(
  BuildContext context, {
  required String id,
  required String name,
  AggregatedItem? from,
}) async {
  final client = kostvMusicClientOf(from);
  if (client == null) return;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final done = await KostvMusicDislikesStore.instance.remove(client, id);
  _say(
    messenger,
    done ? l10n.kostvMusicUndisliked(name) : l10n.kostvMusicDislikeFailed,
  );
}
