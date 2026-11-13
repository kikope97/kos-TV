import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart' show PlaybackManager;

import 'music_preview/preview_engine.dart';

/// Kos TV: the thirty seconds of a song the home server doesn't have, to
/// hear it before asking for its album. One at a time; what the app was
/// playing pauses while it sounds.
class KostvMusicPreview extends ChangeNotifier {
  KostvMusicPreview({PreviewEngine? engine}) : _engineOf = engine;

  final PreviewEngine? _engineOf;
  PreviewEngine? _engine;

  /// The address sounding now, or null.
  String? get playing => _playing;
  String? _playing;

  bool isPlaying(String? url) => url != null && url == _playing;

  /// Plays [url], or stops it if it is the one sounding.
  /// Each play is counted, so one stopped while it was still opening
  /// doesn't start sounding afterwards.
  int _turn = 0;
  bool _disposed = false;

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  Future<void> toggle(String url) async {
    if (_playing == url) return stop();
    _pauseApp();
    final turn = ++_turn;
    _playing = url;
    _tell();
    void over() {
      if (turn != _turn || _playing != url) return;
      _playing = null;
      _tell();
      _resumeApp();
    }

    try {
      final engine = _engine ??= _engineOf ?? PreviewEngine();
      await engine.play(url, onEnd: over);
      // Stopped while it was opening: silenced as soon as it is open.
      if (turn != _turn) await engine.stop();
    } catch (e) {
      debugPrint('[MusicPreview] Could not play it: $e');
      over();
    }
  }

  Future<void> stop() async {
    _turn++;
    if (_playing == null) return;
    _playing = null;
    _tell();
    await _engine?.stop();
    _resumeApp();
  }

  // What the app was playing when a preview paused it, to go on with it
  // once the preview is over.
  dynamic _paused;

  void _pauseApp() {
    if (!GetIt.instance.isRegistered<PlaybackManager>()) return;
    final manager = GetIt.instance<PlaybackManager>();
    if (manager.state.isPlaying) {
      _paused = manager.queueService.currentItem;
      unawaited(manager.pause());
    }
  }

  void _resumeApp() {
    final paused = _paused;
    _paused = null;
    if (paused == null || !GetIt.instance.isRegistered<PlaybackManager>()) {
      return;
    }
    final manager = GetIt.instance<PlaybackManager>();
    // Only if it is still there, paused, and nothing else began meanwhile.
    if (identical(manager.queueService.currentItem, paused) &&
        !manager.state.isPlaying) {
      unawaited(manager.resume());
    }
  }

  /// Leaving the page while one sounds: it stops, and what the app was
  /// playing goes on.
  @override
  void dispose() {
    _disposed = true;
    _turn++;
    final engine = _engine;
    if (_playing != null) {
      _playing = null;
      _resumeApp();
    }
    unawaited(() async {
      await engine?.stop();
      await engine?.dispose();
    }());
    super.dispose();
  }
}
