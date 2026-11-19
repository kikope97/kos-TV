import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Paints [image] blurred, drawing the blur once when the source loads.
///
/// An ImageFiltered blur runs on the GPU every time its layer is drawn, so a
/// full-screen backdrop under a crossfade or a scrolling row pays for it on
/// every frame. Baked, the backdrop is a plain image, and a fade over it can
/// apply its opacity straight to the image draw.
class BakedBlurImage extends StatefulWidget {
  const BakedBlurImage({
    super.key,
    required this.image,
    required this.sigma,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.tileMode = TileMode.decal,
    this.cropToBox = false,
    this.opacity = 1.0,
    this.colorFilter,
  });

  /// Kos TV: a filter (the grey of a title not at home) baked into the
  /// blurred copy, instead of a ColorFiltered layer over it every frame.
  final ColorFilter? colorFilter;

  /// Kos TV: drawn this see-through, straight on the image, which is what an
  /// Opacity around it gives without a layer of its own on every frame.
  final double opacity;

  final ImageProvider image;

  /// In logical pixels of the painted box, the unit an ImageFiltered around
  /// the image would use.
  final double sigma;

  final BoxFit fit;
  final Alignment alignment;

  /// What the blur reads past the source's edges: transparent by default,
  /// or the edge pixels again ([TileMode.clamp]) to match an ImageFiltered
  /// blur, whose default that is.
  final TileMode tileMode;

  /// Blurs only the part of the source the box shows, so the blur meets the
  /// box's edges rather than the source's: what an ImageFiltered around a
  /// cover-fit image gives. Off, the whole source is blurred and then fit.
  final bool cropToBox;

  @override
  State<BakedBlurImage> createState() => _BakedBlurImageState();
}

class _BakedBlurImageState extends State<BakedBlurImage> {
  // A failed load paints nothing.
  late final _listener = ImageStreamListener(_onImage, onError: (_, _) {});
  ImageStream? _stream;
  ImageInfo? _source;
  ui.Image? _baked;
  Size? _bakedSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BakedBlurImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) _resolve();
    if (widget.sigma != oldWidget.sigma ||
        widget.fit != oldWidget.fit ||
        widget.tileMode != oldWidget.tileMode ||
        widget.cropToBox != oldWidget.cropToBox ||
        widget.colorFilter != oldWidget.colorFilter ||
        (widget.cropToBox && widget.alignment != oldWidget.alignment)) {
      _bakedSize = null;
    }
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool _) {
    setState(() {
      _source?.dispose();
      _source = info;
      _bakedSize = null;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final source = _source;
        if (source != null &&
            size != _bakedSize &&
            size.isFinite &&
            !size.isEmpty) {
          _baked?.dispose();
          _baked = _bake(source.image, size);
          _bakedSize = size;
        }
        return RawImage(
          image: _baked,
          fit: widget.fit,
          alignment: widget.alignment,
          opacity: widget.opacity < 1
              ? AlwaysStoppedAnimation<double>(widget.opacity)
              : null,
        );
      },
    );
  }

  /// Kos TV: on the web the source arrives at the size the server sent it,
  /// which for a backdrop is a full screen of pixels. A blur this soft looks
  /// the same drawn from a smaller copy, so there the bake is done at the
  /// size that keeps the blur this many pixels wide, and the result is
  /// stretched back over the box. Elsewhere the decode is already small.
  static const double _webBakedSigma = 12;

  ui.Image _bake(ui.Image source, Size box) {
    final sourceSize = Size(source.width.toDouble(), source.height.toDouble());
    final fitted = applyBoxFit(widget.fit, sourceSize, box);
    // The blur runs on the decoded pixels, which are scaled up or down to
    // the box, so the sigma follows that scale.
    final sourceSigma =
        widget.sigma * fitted.source.width / fitted.destination.width;
    final reduce = kIsWeb && sourceSigma > _webBakedSigma
        ? _webBakedSigma / sourceSigma
        : 1.0;
    final sigma = sourceSigma * reduce;
    final filter = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: widget.tileMode,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final int width;
    final int height;
    // Smoothed when drawn smaller, so the copy the blur reads is not
    // aliased.
    final draw = Paint()
      ..filterQuality = reduce < 1 ? FilterQuality.medium : FilterQuality.none
      ..colorFilter = widget.colorFilter;
    if (widget.cropToBox) {
      // The shown part, in source pixels, blurred as a layer of its own so
      // nothing past its edges reaches the blur.
      final shown = widget.alignment.inscribe(
        fitted.source,
        Offset.zero & sourceSize,
      );
      width = math.max(1, (shown.width * reduce).round());
      height = math.max(1, (shown.height * reduce).round());
      final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      canvas
        ..saveLayer(bounds, Paint()..imageFilter = filter)
        ..drawImageRect(source, shown, bounds, draw)
        ..restore();
    } else if (reduce < 1) {
      width = math.max(1, (source.width * reduce).round());
      height = math.max(1, (source.height * reduce).round());
      final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      canvas
        ..saveLayer(bounds, Paint()..imageFilter = filter)
        ..drawImageRect(source, Offset.zero & sourceSize, bounds, draw)
        ..restore();
    } else {
      width = source.width;
      height = source.height;
      canvas.drawImage(
        source,
        Offset.zero,
        Paint()
          ..imageFilter = filter
          ..colorFilter = widget.colorFilter,
      );
    }
    final picture = recorder.endRecording();
    final baked = picture.toImageSync(width, height);
    picture.dispose();
    return baked;
  }
}
