import 'dart:async';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../kostv_now_playing.dart' show KostvCoverColors;
import 'kostv_music_tokens.dart';

/// Kos TV: the colours of a cover, for the backgrounds of an album, an
/// artist and the player (the cover sets the colour; the brand's gradient
/// is only for what plays).
///
/// Worked out once per picture and kept (the last [_keep]), from a small
/// copy of it, between the frames being drawn, so it never slows down a move of the
/// remote.
abstract final class KostvArtworkColors {
  static const _keep = 96;

  static final _known = <String, KostvCoverColors>{};
  static final _asking = <String, Future<KostvCoverColors>>{};

  /// What is already known of [url], at once (null while it isn't).
  static KostvCoverColors? cached(String? url) {
    if (url == null) return null;
    final found = _known.remove(url);
    if (found != null) _known[url] = found; // The most recent last.
    return found;
  }

  /// The colours of [url]'s picture: kept ones at once, otherwise worked
  /// out between frames. [KostvCoverColors.fallback] when it can't be
  /// read.
  static Future<KostvCoverColors> of(String url, {ImageProvider? image}) {
    final kept = cached(url);
    if (kept != null) return SynchronousFuture(kept);
    return _asking[url] ??= () async {
      try {
        // A task of its own between frames, never in the middle of one (at
        // an animation's priority: an idle one would wait for the player's
        // own animations to stop).
        await SchedulerBinding.instance.scheduleTask(() {}, Priority.animation);
        final found = await KostvCoverColors.of(image ?? NetworkImage(url));
        _known[url] = found;
        while (_known.length > _keep) {
          _known.remove(_known.keys.first);
        }
        return found;
      } catch (_) {
        return KostvCoverColors.fallback;
      } finally {
        scheduleMicrotask(() => _asking.remove(url));
      }
    }();
  }

  /// A page's background washed with [color] from its top ([at]), fading
  /// into Music's dark, as the album, the artist and the player have it.
  static BoxDecoration wash(
    Color color, {
    double strength = 0.55,
    Alignment at = const Alignment(-0.5, -1),
  }) => BoxDecoration(
    color: KostvMusicTokens.background,
    gradient: RadialGradient(
      center: at,
      radius: 1.1,
      colors: [
        color.withValues(alpha: strength),
        color.withValues(alpha: 0),
      ],
    ),
  );

  @visibleForTesting
  static void debugReset() {
    _known.clear();
    _asking.clear();
  }

  @visibleForTesting
  static void debugPut(String url, KostvCoverColors colors) =>
      _known[url] = colors;
}
