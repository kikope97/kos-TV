import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';

import '../../../data/models/aggregated_item.dart';

/// Kos TV: the music (or audiobook) sounding, paused while something else
/// plays over it (a full-screen trailer) and back on after, only if it was
/// playing and nothing else began meanwhile.
class KostvMusicHold {
  Object? _paused;

  PlaybackManager? get _manager =>
      GetIt.instance.isRegistered<PlaybackManager>()
      ? GetIt.instance<PlaybackManager>()
      : null;

  /// Pauses what sounds, if it is music and it is playing.
  void pause() {
    final manager = _manager;
    if (manager == null) return;
    final current = manager.queueService.currentItem;
    if (current is AggregatedItem &&
        current.isAudioLike &&
        manager.state.isPlaying) {
      _paused = current;
      unawaited(manager.pause());
    }
  }

  /// Goes on with what [pause] paused: only if it is still there, paused.
  void resume() {
    final paused = _paused;
    _paused = null;
    final manager = _manager;
    if (paused == null || manager == null) return;
    if (identical(manager.queueService.currentItem, paused) &&
        !manager.state.isPlaying) {
      unawaited(manager.resume());
    }
  }
}
