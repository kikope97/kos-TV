import 'package:flutter/material.dart';

import '../../../../util/focus/input_mode_tracker.dart';
import '../../../../util/platform_detection.dart';

/// Kos TV: the measures, colours and letters of Music's design
/// (`docs/diseno-musica/README.md`, «Piezas en la app»). The same pieces on
/// the TV, the phone and the web; only their sizes change with the screen.
abstract final class KostvMusicTokens {
  // --- Colours ---

  /// The page's background.
  static const background = Color(0xFF0B0B0F);

  /// Text and icons on it.
  static const ink = Color(0xFFF3F5FA);

  /// What goes under a title (62 %).
  static const muted = Color(0x9EF3F5FA);

  /// What says least (42 %).
  static const dim = Color(0x6BF3F5FA);

  /// The brand's three colours.
  static const cyan = Color(0xFF4FD8FF);
  static const violet = Color(0xFF8F6BFF);
  static const pink = Color(0xFFFF5CCF);

  /// The brand's gradient: only for what is pressed to play and for what
  /// sounds (the play button, the progress, the equalizer).
  static const gradient = LinearGradient(
    begin: Alignment(-0.9, -0.5),
    end: Alignment(0.9, 0.5),
    colors: [cyan, violet, pink],
    stops: [0, 0.52, 1],
  );

  /// A soft see-through white: tiles, round buttons, quiet pills.
  static Color glass([double alpha = 0.08]) =>
      Colors.white.withValues(alpha: alpha);

  /// The floating player's glass: opaque enough that what is behind
  /// doesn't show through.
  static const capsule = Color(0xEB1A1822);

  // --- Radii ---

  static const radiusRow = 10.0;
  static const radiusCover = 10.0;
  static const radiusSmallCover = 6.0;
  static const radiusTile = 8.0;

  // --- The remote's focus ---

  /// The white frame of what has the TV's focus, apart from it by [gap].
  static const focusFrame = 3.0;
  static const focusGap = 3.0;

  /// How much bigger a card is with the focus.
  static const focusScale = 1.07;

  /// A row grows less (it is wide).
  static const focusScaleRow = 1.02;

  static const focusDuration = Duration(milliseconds: 160);
  static const focusCurve = Curves.easeOutCubic;

  // --- Measures by screen ---

  static bool get _phone => PlatformDetection.useMobileUi;
  static bool get _tv => PlatformDetection.isTV;

  /// Kos TV: whether what shows only with the focus or the mouse over it
  /// (a card's ▶, the capsule's ✕) must show by itself: on the phone, and
  /// on the web while a finger is used (nothing hovers there). Listen to
  /// [InputModeTracker.touchInUse] to follow the web's change.
  static bool get touchFirst =>
      !_tv && (_phone || InputModeTracker.touchInUse.value);

  /// The page's side margins: 64 on the TV, 56 on the web, 16 on the phone.
  static double get margin => _phone ? 16 : (_tv ? 64 : 56);

  /// Between the cards of a shelf.
  static double get shelfGap => _phone ? 14 : 22;

  /// A shelf's card: 168–176 on the TV, 190 on the web, 140–150 on the
  /// phone.
  static double get card => _phone ? 150 : (_tv ? 172 : 190);

  /// The size of the text of a song's title in a row (16–17 on the TV, 15
  /// elsewhere).
  static double get rowText => _tv ? 16 : 15;

  /// A row's cover.
  static double get rowCover => _phone ? 44 : (_tv ? 52 : 44);

  /// A quick-access tile («Sigue escuchando»).
  static double get tileHeight => _phone ? 56 : 64;

  /// The title of a shelf (22–24) and of a page (40–44).
  static double get shelfTitle => _phone ? 21 : (_tv ? 23 : 24);
  static double get pageTitle => _phone ? 30 : (_tv ? 40 : 44);
}

/// Kos TV: the brand's letters for titles (Outfit Bold) and the rest's
/// (Roboto, the app's own).
abstract final class KostvMusicType {
  static const titleFamily = 'Outfit';

  /// A title in Outfit Bold, [size] high.
  static TextStyle title(double size, {Color color = KostvMusicTokens.ink}) =>
      TextStyle(
        fontFamily: titleFamily,
        fontWeight: FontWeight.w700,
        fontSize: size,
        height: 1.1,
        letterSpacing: -0.01 * size,
        color: color,
      );

  /// A line of text (a song's title).
  static TextStyle body(
    double size, {
    Color color = KostvMusicTokens.ink,
    FontWeight weight = FontWeight.w500,
  }) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.2);

  /// What goes under it (an artist, a duration).
  static TextStyle muted(double size) => TextStyle(
    fontSize: size,
    color: KostvMusicTokens.muted,
    height: 1.2,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Kos TV: paints [child] (a text or an icon) with the brand's gradient, as
/// the title of the song that sounds.
class KostvGradientText extends StatelessWidget {
  const KostvGradientText({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.srcIn,
    shaderCallback: KostvMusicTokens.gradient.createShader,
    child: child,
  );
}
