import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'preview_engine.dart';

/// Kos TV: previews through the browser's own audio.
class PlatformPreviewEngine implements PreviewEngine {
  web.HTMLAudioElement? _audio;
  StreamSubscription<web.Event>? _ended;

  @override
  Future<void> play(String url, {required void Function() onEnd}) async {
    final audio = _audio ??= web.HTMLAudioElement();
    await _ended?.cancel();
    _ended = web.EventStreamProvider<web.Event>('ended')
        .forTarget(audio)
        .listen((_) => onEnd());
    audio.src = url;
    await audio.play().toDart;
  }

  @override
  Future<void> stop() async => _audio?.pause();

  @override
  Future<void> dispose() async {
    await _ended?.cancel();
    _audio?.pause();
    _audio = null;
  }
}
