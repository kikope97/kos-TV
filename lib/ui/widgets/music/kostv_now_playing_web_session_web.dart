import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'kostv_now_playing.dart';

bool _attached = false;

/// Tells the browser what music sounds, so the iPhone's and Android's lock
/// screen and the computer's media keys show its title and cover, and their
/// play, pause, previous and next reach the app.
void attachKostvWebMediaSession(KostvNowPlaying music) {
  if (_attached) return;
  _attached = true;
  final web.MediaSession session;
  try {
    session = web.window.navigator.mediaSession;
    void handle(String action, void Function() run) {
      session.setActionHandler(
        action,
        ((JSAny? _) {
          run();
        }).toJS,
      );
    }

    handle('play', () {
      if (!music.playing) music.playPause();
    });
    handle('pause', () {
      if (music.playing) music.playPause();
    });
    handle('previoustrack', music.previous);
    handle('nexttrack', music.next);
  } catch (_) {
    // A browser without the Media Session API.
    return;
  }

  String? shownId;
  void update() {
    try {
      final item = music.item;
      if (item == null) {
        if (shownId != null) {
          shownId = null;
          session.metadata = null;
        }
        session.playbackState = 'none';
        return;
      }
      if (item.id != shownId) {
        shownId = item.id;
        final art = music.artUrl(item, maxHeight: 512);
        session.metadata = web.MediaMetadata(
          web.MediaMetadataInit(
            title: item.name,
            // Kos TV: only the artist, at home or not.
            artist: music.artistOf(item),
            album: item.album ?? '',
            artwork: <web.MediaImage>[
              if (art != null) web.MediaImage(src: art, sizes: '512x512'),
            ].toJS,
          ),
        );
      }
      session.playbackState = music.playing ? 'playing' : 'paused';
    } catch (_) {}
  }

  music.addListener(update);
  update();
}
