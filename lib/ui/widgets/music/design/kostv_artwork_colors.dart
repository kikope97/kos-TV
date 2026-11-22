import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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
/// copy of it, between the frames being drawn, so it never slows down a move
/// of the remote.
///
/// Kos TV: kept by the picture, whatever size the page asked for it at (the
/// album's 600 px cover and the player's 96 px are the same picture), and
/// read from a small copy of it ([smallUrl]) through the app's image cache
/// (on the disk where there is one), not the big one again. A picture that
/// can't be read is remembered as such for a while ([_failedFor]).
abstract final class KostvArtworkColors {
  static const _keep = 96;

  /// How long a picture that couldn't be read isn't tried again.
  static const _failedFor = Duration(minutes: 10);

  /// The side of the copy the colour is read from.
  static const _small = 96;

  static final _known = <String, KostvCoverColors>{};
  static final _failed = <String, DateTime>{};
  static final _asking = <String, Future<KostvCoverColors>>{};

  // Sizes in a home server's picture address (the rest says which picture).
  static const _sizeParams = {
    'maxwidth',
    'maxheight',
    'fillwidth',
    'fillheight',
    'width',
    'height',
  };

  // The size in a Deezer picture's name: «…/1000x1000-000000-80-0-0.jpg».
  static final _deezerSize = RegExp(r'/(\d+)x(\d+)-');

  /// Kos TV: [url] asked for small: a home server's picture with
  /// `maxHeight=96` (and no other size), a Deezer one at its 120 px copy
  /// (one of the sizes it keeps); any other as it is. The same for every
  /// size of the same picture, so it is also the key it is kept under.
  static String smallUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.host.contains('dzcdn.net') && _deezerSize.hasMatch(uri.path)) {
      return url.replaceFirst(_deezerSize, '/120x120-');
    }
    if (!uri.path.contains('/Images/')) return url;
    final query = <String, String>{
      for (final entry in uri.queryParameters.entries)
        if (!_sizeParams.contains(entry.key.toLowerCase()))
          entry.key: entry.value,
      'maxHeight': '$_small',
    };
    final keys = query.keys.toList()..sort();
    return uri
        .replace(queryParameters: {for (final key in keys) key: query[key]!})
        .toString();
  }

  /// What is already known of [url], at once (null while it isn't).
  static KostvCoverColors? cached(String? url) {
    if (url == null) return null;
    final key = smallUrl(url);
    final found = _known.remove(key);
    if (found != null) _known[key] = found; // The most recent last.
    return found;
  }

  /// The colours of [url]'s picture: kept ones at once, otherwise worked
  /// out between frames. [KostvCoverColors.fallback] when it can't be
  /// read (at once, for a while, once it couldn't).
  static Future<KostvCoverColors> of(String url, {ImageProvider? image}) {
    final kept = cached(url);
    if (kept != null) return SynchronousFuture(kept);
    final key = smallUrl(url);
    final failed = _failed[key];
    if (failed != null) {
      if (DateTime.now().difference(failed) < _failedFor) {
        return SynchronousFuture(KostvCoverColors.fallback);
      }
      _failed.remove(key);
    }
    return _asking[key] ??= () async {
      try {
        // A task of its own between frames, never in the middle of one (at
        // an animation's priority: an idle one would wait for the player's
        // own animations to stop).
        await SchedulerBinding.instance.scheduleTask(() {}, Priority.animation);
        final found = await KostvCoverColors.of(
          image ?? CachedNetworkImageProvider(key),
        );
        _known[key] = found;
        while (_known.length > _keep) {
          _known.remove(_known.keys.first);
        }
        return found;
      } catch (_) {
        _failed[key] = DateTime.now();
        while (_failed.length > _keep) {
          _failed.remove(_failed.keys.first);
        }
        return KostvCoverColors.fallback;
      } finally {
        scheduleMicrotask(() => _asking.remove(key));
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
    _failed.clear();
    _asking.clear();
  }

  @visibleForTesting
  static void debugPut(String url, KostvCoverColors colors) =>
      _known[smallUrl(url)] = colors;

  /// Kos TV: [url]'s picture as if it had failed to be read just now.
  @visibleForTesting
  static void debugFail(String url) => _failed[smallUrl(url)] = DateTime.now();
}
