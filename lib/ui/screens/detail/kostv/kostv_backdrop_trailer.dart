import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../data/models/aggregated_item.dart';
import '../../../../data/services/stremfin/kostv_trailers.dart';
import '../../../../data/services/youtube_stream_resolver.dart';
import '../../../../preference/user_preferences.dart';
import '../../../../util/platform_detection.dart';
import '../../../widgets/web_youtube_trailer.dart';

/// Kos TV: the title's trailer, without sound, over its art.
///
/// It waits a few seconds on the page first, so passing through doesn't set
/// it off, takes the first YouTube trailer of the list with the Spanish ones
/// first, and fades in once it really plays. It plays once: at the end, or if
/// it can't play, the art comes back and stays. Leaving the page (the player,
/// another title) stops it for good.
///
/// Follows the same setting as the home banner's trailer, which also keeps it
/// off on devices too slow for it.
class KostvBackdropTrailer extends StatefulWidget {
  final AggregatedItem item;
  final UserPreferences prefs;
  final Duration delay;

  const KostvBackdropTrailer({
    super.key,
    required this.item,
    required this.prefs,
    this.delay = const Duration(seconds: 4),
  });

  /// Whether this device plays the trailer at all: the embedded YouTube
  /// player is there on the web and on Android, the TV included.
  static bool get supported =>
      PlatformDetection.isWeb ||
      PlatformDetection.isAndroid ||
      PlatformDetection.isIOS;

  @override
  State<KostvBackdropTrailer> createState() => _KostvBackdropTrailerState();
}

class _KostvBackdropTrailerState extends State<KostvBackdropTrailer> {
  static const _fade = Duration(milliseconds: 900);

  Timer? _timer;
  String? _videoId;
  bool _visible = false;
  bool _finished = false;
  bool _current = true;

  @override
  void initState() {
    super.initState();
    if (KostvBackdropTrailer.supported &&
        widget.prefs.resolveMediaBarTrailerPreview()) {
      _timer = Timer(widget.delay, _find);
    } else {
      _finished = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current == _current) return;
    _current = current;
    // Covered by the player or another page: the trailer is over for this
    // visit, and its sound-free video mustn't run underneath.
    if (!current) _stop();
  }

  Future<void> _find() async {
    final item = widget.item;
    try {
      final trailers = await KostvTrailers.sorted(
        itemType: item.type,
        tmdbId: item.tmdbId,
        server: item.remoteTrailers,
      );
      if (!mounted || _finished) return;
      for (final trailer in trailers) {
        final url = trailer['Url'];
        if (url is! String) continue;
        final id = YouTubeStreamResolver.extractVideoId(url);
        if (id != null) {
          setState(() => _videoId = id);
          return;
        }
      }
    } catch (_) {}
    _finished = true;
  }

  void _started() {
    if (!mounted || _finished) return;
    setState(() => _visible = true);
  }

  /// Fades the video out, then lets go of the player.
  void _end() {
    if (!mounted || _finished) return;
    setState(() => _visible = false);
    Timer(_fade, _stop);
  }

  void _stop() {
    _timer?.cancel();
    _finished = true;
    if (mounted && _videoId != null) setState(() => _videoId = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _videoId;
    if (id == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedOpacity(
        // The browser only builds the player once it's painted, and nothing
        // at a zero opacity is: there it waits all but invisible instead.
        opacity: _visible ? 1 : (PlatformDetection.isWeb ? 0.01 : 0),
        duration: _fade,
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // A 16:9 picture that covers the whole frame, a little larger
              // so YouTube's black edges never show; on a phone's taller art
              // the sides are cut.
              const overscan = 1.04;
              final cover =
                  constraints.maxWidth / constraints.maxHeight > 16 / 9
                  ? constraints.maxWidth
                  : constraints.maxHeight * 16 / 9;
              final w = cover * overscan;
              final h = w * 9 / 16;
              return OverflowBox(
                minWidth: w,
                minHeight: h,
                maxWidth: w,
                maxHeight: h,
                child: WebYouTubeTrailer(
                  key: ValueKey(id),
                  videoId: id,
                  muted: true,
                  showControls: false,
                  loop: false,
                  ignorePointer: true,
                  onPlaybackStarted: _started,
                  onCompleted: _end,
                  onAutoplayFailed: _end,
                  onEmbeddedUnavailable: _end,
                  autoplayTimeout: const Duration(seconds: 8),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
