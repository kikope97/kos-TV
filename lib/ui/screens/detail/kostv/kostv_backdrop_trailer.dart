import 'dart:async';

import 'package:flutter/foundation.dart';
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
/// another title) stops it for good. Scrolled out of sight ([outOfSight]) it
/// only waits: held where it was, it plays on once the art is back in view.
///
/// Follows the same setting as the home banner's trailer, which also keeps it
/// off on devices too slow for it.
class KostvBackdropTrailer extends StatefulWidget {
  final AggregatedItem item;
  final UserPreferences prefs;
  final Duration delay;

  /// Kos TV: whether the art it plays over has been scrolled off the screen.
  final ValueListenable<bool>? outOfSight;

  const KostvBackdropTrailer({
    super.key,
    required this.item,
    required this.prefs,
    this.delay = const Duration(seconds: 4),
    this.outOfSight,
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

class _KostvBackdropTrailerState extends State<KostvBackdropTrailer>
    with WidgetsBindingObserver {
  static const _fade = Duration(milliseconds: 900);

  Timer? _timer;
  String? _videoId;
  bool _visible = false;
  bool _finished = false;
  bool _current = true;

  /// Out of sight for now: covered by another page or a menu, or the app
  /// sent to the background. The player goes; if it hadn't shown yet, it
  /// waits its few seconds again on coming back.
  bool _away = false;

  /// Scrolled off the screen with the art. Playing, it's held where it is
  /// and plays on when the art is back, which doesn't count as seen; not
  /// started yet, it waits its few seconds again then.
  bool _scrolledOff = false;

  /// Bumped whenever it goes out of sight or comes back, and by each look
  /// for a trailer, so a look that ends after that can't put one up without
  /// its wait.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.outOfSight?.addListener(_onScroll);
    _scrolledOff = widget.outOfSight?.value ?? false;
    if (KostvBackdropTrailer.supported &&
        widget.prefs.resolveMediaBarTrailerPreview()) {
      if (!_scrolledOff) _timer = Timer(widget.delay, _find);
    } else {
      _finished = true;
    }
  }

  @override
  void didUpdateWidget(KostvBackdropTrailer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.outOfSight != widget.outOfSight) {
      oldWidget.outOfSight?.removeListener(_onScroll);
      widget.outOfSight?.addListener(_onScroll);
      _onScroll();
    }
  }

  void _onScroll() {
    final off = widget.outOfSight?.value ?? false;
    if (off == _scrolledOff || !mounted) return;
    _scrolledOff = off;
    _attempt++;
    if (_finished) return;
    if (off) {
      _timer?.cancel();
      // Not on screen yet: let go of the player, and start over on return.
      if (!_visible && _videoId != null) setState(() => _videoId = null);
      if (_visible) setState(() {});
      return;
    }
    if (_visible && _videoId != null) {
      setState(() {});
    } else if (!_away && KostvBackdropTrailer.supported) {
      _videoId = null;
      _timer?.cancel();
      _timer = Timer(widget.delay, _find);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current == _current) return;
    _current = current;
    // Covered by the player, another page or a menu: its sound-free video
    // mustn't run underneath.
    _setAway(!current);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On a TV's Home button the app stays alive in the background: the
    // video mustn't go on playing there. Only a moment «inactive» (a
    // browser window without the focus, the phone's notifications pulled
    // down) isn't away: it's still in sight.
    final hidden =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    _setAway(hidden || !_current);
    if (mounted) setState(() {});
  }

  void _setAway(bool away) {
    if (away == _away) return;
    _away = away;
    _attempt++;
    if (away) {
      // Seen, all or part of it: it plays once, so back on top the art
      // stays. Not yet started: its wait starts over on coming back.
      if (_visible) _finished = true;
      _visible = false;
      _timer?.cancel();
      return;
    }
    if (_finished) {
      _videoId = null;
      return;
    }
    _videoId = null;
    _timer?.cancel();
    // Scrolled off, it waits for the art to be back instead.
    if (KostvBackdropTrailer.supported && !_scrolledOff) {
      _timer = Timer(widget.delay, _find);
    }
  }

  Future<void> _find() async {
    if (_away || _scrolledOff) return;
    final attempt = ++_attempt;
    final item = widget.item;
    try {
      final trailers = await KostvTrailers.sorted(
        itemType: item.type,
        tmdbId: item.tmdbId,
        server: item.remoteTrailers,
      );
      // Gone out of sight and back meanwhile: that return's own wait looks
      // again.
      if (!mounted || attempt != _attempt) return;
      if (_finished || _away) return;
      for (final trailer in trailers) {
        final url = trailer['Url'];
        if (url is! String) continue;
        final id = YouTubeStreamResolver.extractVideoId(url);
        if (id != null) {
          setState(() => _videoId = id);
          return;
        }
      }
    } catch (_) {
      if (!mounted || attempt != _attempt) return;
    }
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
    // Done from now: scrolling away and back while it fades mustn't start
    // it over.
    _finished = true;
    Timer(_fade, _stop);
  }

  void _stop() {
    _timer?.cancel();
    _finished = true;
    if (mounted && _videoId != null) setState(() => _videoId = null);
  }

  @override
  void dispose() {
    widget.outOfSight?.removeListener(_onScroll);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _videoId;
    if (id == null || _away) return const SizedBox.shrink();
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
                  paused: _scrolledOff,
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
