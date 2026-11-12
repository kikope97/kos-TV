import 'dart:async';
import 'dart:math' as math;

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
/// The video is drawn as part of the app's own picture, so a TV that draws
/// its interface in 1080p (almost all, whatever the panel) gets the same
/// video in 1080p: the same frames and sound, a quarter of the work, and a
/// size any TV decodes in hardware. Decoding the 4K one there showed nothing
/// more and, on some TVs, played it in slow motion and held the app back.
/// And should a TV still not keep up, the opening gives way to the app.
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

  /// The same video in 1080p.
  static const asset1080 = 'assets/intro/kostv_intro_1080.mp4';

  /// The copy for a screen of [physicalSize] pixels: the 4K one only where
  /// the app itself is drawn in 4K.
  @visibleForTesting
  static String assetFor(Size physicalSize) =>
      math.max(physicalSize.width, physicalSize.height) > 2560
      ? asset
      : asset1080;

  /// Frames dropped, or seconds the picture runs behind the sound, past
  /// which the device isn't keeping up.
  static const maxDroppedFrames = 12;
  static const maxBehindSound = 0.35;

  /// Whether the device is struggling to play it.
  @visibleForTesting
  static bool isStruggling({required int dropped, required double behind}) =>
      dropped > maxDroppedFrames || behind.abs() > maxBehindSound;

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
  Timer? _watchdog;
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
        ..add(
          player.stream.completed.listen((done) {
            if (done) _finish();
          }),
        )
        ..add(player.stream.error.listen((_) => _useFallback()));
      _firstFrameTimer = Timer(KosIntroVideo.firstFrameTimeout, () {
        if (!_showing) _useFallback();
      });
      await player.setVolume(sound ? 100 : 0);
      final views = WidgetsBinding.instance.platformDispatcher.views;
      final screen = views.isEmpty ? Size.zero : views.first.physicalSize;
      await player.open(Media('asset:///${KosIntroVideo.assetFor(screen)}'));
      await _controller!.waitUntilFirstFrameRendered;
      if (!mounted || _fallback) return;
      _firstFrameTimer?.cancel();
      setState(() => _showing = true);
      _watch(player);
    } catch (e) {
      debugPrint('[KosIntroVideo] $e');
      _useFallback();
    }
  }

  /// Every half second, how the device keeps up. One that can't (the
  /// picture drops frames or falls behind the sound, in slow motion) gives
  /// way to the app rather than holding it back.
  void _watch(Player player) {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    // Called through dynamic, as elsewhere in the app: the web build's
    // NativePlayer is a stub without it.
    final dynamic native = platform;
    Future<String> read(String name) async =>
        '${await native.getProperty(name, waitForInitialization: false)}';
    _watchdog = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_finished || !mounted) {
        _watchdog?.cancel();
        return;
      }
      try {
        final dropped =
            (int.tryParse(await read('frame-drop-count')) ?? 0) +
            (int.tryParse(await read('decoder-frame-drop-count')) ?? 0);
        final behind = double.tryParse(await read('avsync')) ?? 0;
        if (KosIntroVideo.isStruggling(dropped: dropped, behind: behind)) {
          debugPrint(
            '[KosIntroVideo] not keeping up ($dropped dropped, '
            '${behind.toStringAsFixed(2)} s): on to the app',
          );
          _watchdog?.cancel();
          _skip();
        }
      } catch (_) {
        // The player went meanwhile.
      }
    });
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
    _watchdog?.cancel();
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
    _watchdog?.cancel();
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
