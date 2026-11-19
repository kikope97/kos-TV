import 'package:flutter/widgets.dart' show AppLifecycleState;

/// Kos TV: whether coming back to the app reloads Home. Only when the app
/// really was away (in the background, or the web page hidden): a
/// notification shade, a system dialog or, on the web, the window getting
/// its focus back only make it inactive for a moment, and reloading every
/// row then was all cost.
class HomeAppReturn {
  bool _wasAway = false;

  /// Notes [state], and whether Home reloads at it.
  bool reloadsAt(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final reload = _wasAway;
        _wasAway = false;
        return reload;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _wasAway = true;
        return false;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        return false;
    }
  }
}
