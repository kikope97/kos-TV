import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../data/services/installed_apps_service.dart';

/// Kos TV: the colour an app is known by (Netflix red, Jellyfin blue,
/// SoundCloud orange…), read from its own banner or icon, so it works for
/// whatever is installed. All apps tints its background with it and the
/// focused card glows in it.
///
/// Read once per app and kept for the app's life. An app drawn only in greys
/// (black and white logos) has none: [neutral] stands in for it.
abstract final class AppAccentColors {
  /// For an app with no colour of its own, and for the TV settings card.
  static const neutral = Color(0xFFB4C0D3);

  static final Map<String, Color?> _known = {};
  static final Map<String, Future<Color?>> _reading = {};

  static String _key(InstalledApp app) =>
      '${app.packageName}:${app.art?.length ?? 0}';

  /// The colour already read for [app], or null when it hasn't been read yet
  /// or the app has none ([isKnown] tells which).
  static Color? cached(InstalledApp app) => _known[_key(app)];

  static bool isKnown(InstalledApp app) => _known.containsKey(_key(app));

  /// The colour of [app], reading its art the first time.
  static Future<Color?> of(InstalledApp app) {
    final key = _key(app);
    if (_known.containsKey(key)) return SynchronousFuture(_known[key]);
    return _reading[key] ??= _read(app.art).then((color) {
      _known[key] = color;
      _reading.remove(key);
      return color;
    });
  }

  @visibleForTesting
  static void clearForTesting() {
    _known.clear();
    _reading.clear();
  }

  static Future<Color?> _read(Uint8List? art) async {
    if (art == null || art.isEmpty) return null;
    try {
      // A few dozen pixels across are plenty to tell a colour.
      final codec = await ui.instantiateImageCodec(art, targetWidth: 48);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();
      if (data == null) return null;
      return accentFromRgba(data.buffer.asUint8List());
    } catch (e) {
      debugPrint('[AppAccentColors] $e');
      return null;
    }
  }
}

/// The most striking colour in [rgba] (four bytes a pixel), made bright
/// enough to show on a dark screen, or null when the picture is all greys.
///
/// Vivid pixels are grouped by hue and the group with the most of them wins,
/// so a red logo on black reads as red, not as black.
@visibleForTesting
Color? accentFromRgba(Uint8List rgba) {
  const groups = 24; // 15 degrees of hue each
  final weight = List<double>.filled(groups, 0);
  final red = List<double>.filled(groups, 0);
  final green = List<double>.filled(groups, 0);
  final blue = List<double>.filled(groups, 0);
  var opaque = 0;

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    opaque++;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final value = max / 255;
    if (max == 0 || value < 0.2) continue;
    final saturation = (max - min) / max;
    if (saturation < 0.3) continue;
    final hue = HSVColor.fromColor(Color.fromARGB(255, r, g, b)).hue;
    final group = (hue / (360 / groups)).floor() % groups;
    final w = saturation * saturation * value;
    weight[group] += w;
    red[group] += r * w;
    green[group] += g * w;
    blue[group] += b * w;
  }
  if (opaque == 0) return null;

  var best = -1;
  var bestWeight = 0.0;
  for (var k = 0; k < groups; k++) {
    final around =
        weight[k] +
        0.5 * (weight[(k + groups - 1) % groups] + weight[(k + 1) % groups]);
    if (around > bestWeight) {
      bestWeight = around;
      best = k;
    }
  }
  // Too little colour to call it the app's: a few stray pixels in a grey
  // logo, or none at all.
  if (best < 0 || weight[best] == 0 || bestWeight / opaque < 0.008) return null;

  final w = weight[best];
  final color = Color.fromARGB(
    255,
    (red[best] / w).round().clamp(0, 255),
    (green[best] / w).round().clamp(0, 255),
    (blue[best] / w).round().clamp(0, 255),
  );
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withSaturation(math.max(hsl.saturation, 0.6))
      .withLightness(hsl.lightness.clamp(0.48, 0.62))
      .toColor();
}
