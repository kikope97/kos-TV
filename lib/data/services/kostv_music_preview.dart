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
  Future<void> toggle(String url) async {
    if (_playing == url) return stop();
    _pauseApp();
    _playing = url;
    notifyListeners();
    try {
      final engine = _engine ??= _engineOf ?? PreviewEngine();
      await engine.play(url, onEnd: () {
        if (_playing == url) {
          _playing = null;
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('[MusicPreview] Could not play it: $e');
      if (_playing == url) {
        _playing = null;
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    if (_playing == null) return;
    _playing = null;
    notifyListeners();
    await _engine?.stop();
  }

  void _pauseApp() {
    if (!GetIt.instance.isRegistered<PlaybackManager>()) return;
    final manager = GetIt.instance<PlaybackManager>();
    if (manager.state.isPlaying) unawaited(manager.pause());
  }

  @override
  void dispose() {
    unawaited(_engine?.dispose());
    super.dispose();
  }
}
