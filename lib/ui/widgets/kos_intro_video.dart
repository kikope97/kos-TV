import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../util/platform_detection.dart';
import 'kos_intro.dart';

/// Kos TV: the opening, the "Power 4K" intro video exactly as it was made
/// (assets/intro/kostv_intro.mp4, 4K, with its sound). The app restores the
/// session and loads Home behind it, so it isn't time spent waiting.
///
/// Sound: on a TV always; on a phone only while its ringer is on (silent or
/// vibrate keeps it quiet); on the web never, since browsers refuse to start
/// a video with sound before the page is touched.
///
/// The last frame stays up until the screen goes, any key or a tap skips it,
/// and a device that can't play the video gets the drawn intro instead.
class KosIntroVideo extends StatefulWidget {
  const KosIntroVideo({super.key, this.onFinished, this.footer});

  /// Called once, when the video has ended or was skipped.
  final VoidCallback? onFinished;

  /// Shown over the bottom of the video, such as a message with a Retry
  /// button.
  final Widget? footer;

  static const asset = 'assets/intro/kostv_intro.mp4';

  /// How long the video may take to show its first frame before the drawn
  /// intro takes over.
  static const firstFrameTimeout = Duration(seconds: 4);

  /// Stops the video just short of its end, so its last frame stays.
  static const holdBeforeEnd = Duration(milliseconds: 120);

  @override
  State<KosIntroVideo> createState() => _KosIntroVideoState();
}

class _KosIntroVideoState extends State<KosIntroVideo> {
  static const _channel = MethodChannel('org.moonfin.androidtv/platform');

  Player? _player;
  VideoController? _controller;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _firstFrameTimer;
  bool _showing = false;
  bool _fallback = false;
  bool _finished = false;
  Duration _duration = Duration.zero;
  final _focusNode = FocusNode(debugLabel: 'kostvIntroVideo');

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final sound = await _soundAllowed();
      final player = Player(
        configuration: const PlayerConfiguration(title: 'kOS TV'),
      );
      _player = player;
      _controller = VideoController(player);
      _subscriptions
        ..add(player.stream.duration.listen((d) => _duration = d))
        ..add(player.stream.position.listen(_onPosition))
        ..add(player.stream.completed.listen((done) {
          if (done) _finish();
        }))
        ..add(player.stream.error.listen((_) => _useFallback()));
      _firstFrameTimer = Timer(KosIntroVideo.firstFrameTimeout, () {
        if (!_showing) _useFallback();
      });
      await player.setVolume(sound ? 100 : 0);
      await player.open(Media('asset:///${KosIntroVideo.asset}'));
      await _controller!.waitUntilFirstFrameRendered;
      if (!mounted || _fallback) return;
      _firstFrameTimer?.cancel();
      setState(() => _showing = true);
    } catch (e) {
      debugPrint('[KosIntroVideo] $e');
      _useFallback();
    }
  }

  /// On Android the platform says whether the ringer is on (a TV always
  /// plays it); the web stays silent.
  Future<bool> _soundAllowed() async {
    if (kIsWeb) return false;
    if (!PlatformDetection.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('introSoundAllowed') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  void _onPosition(Duration position) {
    if (_finished || _duration <= Duration.zero) return;
    if (position >= _duration - KosIntroVideo.holdBeforeEnd) {
      unawaited(_player?.pause());
      _finish();
    }
  }

  /// Only before the first frame: once the video shows, a passing error from
  /// the player doesn't swap it for the drawn intro.
  void _useFallback() {
    if (!mounted || _fallback || _finished || _showing) return;
    _firstFrameTimer?.cancel();
    unawaited(_release());
    setState(() => _fallback = true);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished?.call();
  }

  void _skip() {
    if (_finished || _fallback) return;
    unawaited(_player?.pause());
    _finish();
  }

  Future<void> _release() async {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    if (player != null) await player.dispose();
  }

  @override
  void dispose() {
    _firstFrameTimer?.cancel();
    _focusNode.dispose();
    unawaited(_release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) {
      return KosIntro(onFinished: _finish, footer: widget.footer);
    }
    final controller = _controller;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.footer == null,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && !_finished) {
          _skip();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (controller != null)
                AnimatedOpacity(
                  opacity: _showing ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Video(
                    controller: controller,
                    controls: NoVideoControls,
                    fill: Colors.black,
                    fit: BoxFit.contain,
                  ),
                ),
              if (widget.footer != null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 48,
                  child: Center(child: widget.footer),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
