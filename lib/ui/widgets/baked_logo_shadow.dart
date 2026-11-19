import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Kos TV: the soft shadow under a title's logo, drawn once when the logo
/// loads instead of blurred again on every frame.
///
/// It is what an [ImageFiltered] blur of the logo tinted [color] (with
/// [blendMode], [BlendMode.srcATop] keeping the logo's shape) gave, laid
/// out in the same box as the logo. That live blur ran on every frame the
/// page painted: under a trailer or a backdrop that slowly zooms, all the
/// time, and on the web each frame is the whole screen drawn again.
///
/// The bake is as big as the box plus room for the blur to spread, at the
/// screen's pixel ratio, so it paints exactly where the live one did. While
/// the logo loads nothing is drawn, as before; if it fails, [fallback].
class BakedLogoShadow extends StatefulWidget {
  const BakedLogoShadow({
    super.key,
    required this.image,
    required this.color,
    this.sigma = 3,
    this.blendMode = BlendMode.srcATop,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.fallback,
  });

  final ImageProvider image;
  final Color color;

  /// In logical pixels, as the live blur's.
  final double sigma;
  final BlendMode blendMode;
  final BoxFit fit;
  final Alignment alignment;

  /// Shown when the logo can't be loaded.
  final Widget? fallback;

  @override
  State<BakedLogoShadow> createState() => _BakedLogoShadowState();
}

class _BakedLogoShadowState extends State<BakedLogoShadow> {
  late final _listener = ImageStreamListener(
    _onImage,
    onError: (_, _) {
      if (mounted) setState(() => _failed = true);
    },
  );
  ImageStream? _stream;
  ImageInfo? _source;
  bool _failed = false;
  ui.Image? _baked;
  (Size, double)? _bakedFor;

  /// How far the blur spreads past the logo, in logical pixels.
  double get _margin => widget.sigma * 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BakedLogoShadow old) {
    super.didUpdateWidget(old);
    if (widget.image != old.image) {
      _failed = false;
      _resolve();
    }
    if (widget.color != old.color ||
        widget.sigma != old.sigma ||
        widget.blendMode != old.blendMode ||
        widget.fit != old.fit ||
        widget.alignment != old.alignment) {
      _bakedFor = null;
    }
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool _) {
    if (!mounted) {
      info.dispose();
      return;
    }
    setState(() {
      _source?.dispose();
      _source = info;
      _failed = false;
      _bakedFor = null;
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _source?.dispose();
    _baked?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback ?? const SizedBox.shrink();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final source = _source;
        if (source == null || !size.isFinite || size.isEmpty) {
          return const SizedBox.shrink();
        }
        if (_bakedFor != (size, dpr)) {
          _baked?.dispose();
          _baked = _bake(source.image, size, dpr);
          _bakedFor = (size, dpr);
        }
        final m = _margin;
        return Stack(
          alignment: Alignment.topLeft,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -m,
              top: -m,
              right: -m,
              bottom: -m,
              child: RawImage(image: _baked, fit: BoxFit.fill),
            ),
          ],
        );
      },
    );
  }

  ui.Image _bake(ui.Image source, Size box, double dpr) {
    final m = _margin * dpr;
    final width = (box.width * dpr + m * 2).ceil();
    final height = (box.height * dpr + m * 2).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final sigma = widget.sigma * dpr;
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        ),
    );
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(m, m, box.width * dpr, box.height * dpr),
      image: source,
      fit: widget.fit,
      alignment: widget.alignment,
      colorFilter: ColorFilter.mode(widget.color, widget.blendMode),
      filterQuality: FilterQuality.medium,
    );
    canvas.restore();
    final picture = recorder.endRecording();
    final baked = picture.toImageSync(width, height);
    picture.dispose();
    return baked;
  }
}
