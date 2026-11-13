import 'preview_engine_io.dart'
    if (dart.library.js_interop) 'preview_engine_web.dart'
    as impl;

/// Kos TV: plays a song's thirty-second preview from its address, outside
/// the app's playback (it isn't on the home server).
abstract class PreviewEngine {
  factory PreviewEngine() = impl.PlatformPreviewEngine;

  /// Plays [url]; [onEnd] when it finishes on its own.
  Future<void> play(String url, {required void Function() onEnd});
  Future<void> stop();
  Future<void> dispose();
}
