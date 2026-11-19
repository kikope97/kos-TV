import 'dart:async';

import 'offline_aware_image.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class FullscreenBackdropSwitcher extends StatefulWidget {
  final String? imageUrl;
  final Duration duration;
  final Alignment alignment;
  final Duration fadeInDuration;
  final Widget Function(String imageUrl)? imageBuilder;

  /// A full-screen backdrop is the one image the screen is about, so its
  /// fetch goes ahead of the cards built alongside it. Callers that supply
  /// [imageBuilder] set the lane on their own image.
  final ImageFetchPriority priority;

  const FullscreenBackdropSwitcher({
    super.key,
    required this.imageUrl,
    required this.duration,
    this.alignment = Alignment.topCenter,
    // The load fade. The crossfade between two backdrops is [duration].
    this.fadeInDuration = Duration.zero,
    this.imageBuilder,
    this.priority = ImageFetchPriority.high,
  });

  @override
  State<FullscreenBackdropSwitcher> createState() =>
      _FullscreenBackdropSwitcherState();
}

class _FullscreenBackdropSwitcherState extends State<FullscreenBackdropSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  String? _currentUrl;
  String? _incomingUrl;
  String? _pendingUrl;

  /// Kos TV: the backdrop that was showing before [_currentUrl], kept
  /// underneath it while the new one has not painted yet, so a slow load
  /// does not leave the bare background colour between the two.
  String? _outgoingUrl;
  Timer? _outgoingCheck;
  int _outgoingChecks = 0;

  // How often, and for how long at most, the held backdrop waits for the
  // new one to paint before it goes anyway.
  static const Duration _outgoingCheckInterval = Duration(milliseconds: 100);
  static const int _maxOutgoingChecks = 150;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: widget.duration);

    _currentUrl = widget.imageUrl;

    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) {
        return;
      }

      final pending = _pendingUrl;

      final shouldContinue = pending != null && pending != _incomingUrl;
      final previous = _currentUrl;
      final incoming = _incomingUrl;
      // Hold the old backdrop under the new one only while the new one is
      // still loading, and not when another one is about to fade in.
      final hold =
          !shouldContinue &&
          previous != null &&
          incoming != null &&
          previous != incoming &&
          !_hasPainted(incoming);

      setState(() {
        _dropOutgoing();
        _outgoingUrl = hold ? previous : null;
        _currentUrl = incoming;
        _incomingUrl = shouldContinue ? pending : null;
        _pendingUrl = null;
      });

      if (hold) {
        _outgoingCheck = Timer.periodic(
          _outgoingCheckInterval,
          (_) => _checkOutgoing(),
        );
      }

      if (shouldContinue) {
        _controller.forward(from: 0);
      }
    });
  }

  void _checkOutgoing() {
    if (!mounted) return;
    _outgoingChecks++;
    final current = _currentUrl;
    if (current == null ||
        _outgoingChecks >= _maxOutgoingChecks ||
        _hasPainted(current)) {
      setState(_dropOutgoing);
    }
  }

  void _dropOutgoing() {
    _outgoingCheck?.cancel();
    _outgoingCheck = null;
    _outgoingChecks = 0;
    _outgoingUrl = null;
  }

  /// Whether the layer showing [url] has something on screen: true once an
  /// image in it has a frame, and also when it holds no image at all (an
  /// error placeholder, a custom builder), since then there is nothing to
  /// wait for.
  bool _hasPainted(String url) {
    final key = ValueKey<String?>(url);
    Element? layer;
    void findLayer(Element element) {
      if (layer != null) return;
      if (element.widget is KeyedSubtree && element.widget.key == key) {
        layer = element;
        return;
      }
      element.visitChildren(findLayer);
    }

    (context as Element).visitChildren(findLayer);
    final root = layer?.renderObject;
    if (root == null) return true;

    var sawImage = false;
    var painted = false;
    void walk(RenderObject object) {
      if (painted) return;
      if (object is RenderImage) {
        sawImage = true;
        if (object.image != null) {
          painted = true;
          return;
        }
      }
      object.visitChildren(walk);
    }

    walk(root);
    return painted || !sawImage;
  }

  @override
  void didUpdateWidget(FullscreenBackdropSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }

    final next = widget.imageUrl;
    final shown = _incomingUrl ?? _currentUrl;

    if (next == shown) {
      _pendingUrl = null;
      return;
    }

    if (next == _pendingUrl) {
      return;
    }

    if (next == null) {
      // Cleared: drop all backdrop state immediately.
      _controller.stop();

      setState(() {
        _dropOutgoing();
        _currentUrl = null;
        _incomingUrl = null;
        _pendingUrl = null;
      });

      return;
    }

    if (_controller.isAnimating) {
      _pendingUrl = next;
      return;
    }

    setState(() {
      // A held backdrop only bridges one load; the next fade starts from
      // what is showing now.
      _dropOutgoing();
      _incomingUrl = next;
    });

    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _outgoingCheck?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildImage(String imageUrl) {
    return widget.imageBuilder?.call(imageUrl) ??
        OfflineAwareImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          alignment: widget.alignment,
          fadeInDuration: widget.fadeInDuration,
          // A backdrop covers the whole screen, so on a portrait phone it
          // paints far wider than the screen. The aspect lets the decode
          // bound follow the painted width instead of the box width.
          sourceAspectRatio: 16 / 9,
          maxDecodeWidth: ArtworkDecode.maxSourceWidth,
          priority: widget.priority,
          errorWidget: (_, _, _) => const SizedBox.shrink(),
        );
  }

  /// Kos TV: every layer has the same shape, keyed on the outside, so when
  /// the incoming backdrop becomes the current one Flutter finds it among
  /// its siblings and keeps it: a blurred backdrop is not baked a second
  /// time and an animated one does not restart.
  Widget _layer(String url, Animation<double> opacity) {
    return KeyedSubtree(
      key: ValueKey<String?>(url),
      child: FadeTransition(opacity: opacity, child: _buildImage(url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_outgoingUrl != null)
          _layer(_outgoingUrl!, kAlwaysCompleteAnimation),
        if (_currentUrl != null) _layer(_currentUrl!, kAlwaysCompleteAnimation),
        if (_incomingUrl != null) _layer(_incomingUrl!, _controller),
      ],
    );
  }
}
