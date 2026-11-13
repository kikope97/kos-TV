import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'preview_engine.dart';

/// Kos TV: previews through media_kit, as the trailers.
class PlatformPreviewEngine implements PreviewEngine {
  Player? _player;
  StreamSubscription<bool>? _ended;

  @override
  Future<void> play(String url, {required void Function() onEnd}) async {
    final player = _player ??= Player();
    await _ended?.cancel();
    _ended = player.stream.completed.listen((done) {
      if (done) onEnd();
    });
    await player.open(Media(url));
  }

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> dispose() async {
    await _ended?.cancel();
    await _player?.dispose();
    _player = null;
  }
}
