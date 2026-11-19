import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

/// The three time slots that sit above or below a playback progress bar.
///
/// With a center label each slot takes an equal third, so it stays centered
/// whatever its neighbours hold. Without one, the two ends share the width by
/// how much they say, so a long label («Ends at 21:13») isn't squeezed into
/// a third of a phone. A label that still doesn't fit wraps to a second line
/// rather than losing the time at its end.
class PlaybackTimeRow extends StatelessWidget {
  const PlaybackTimeRow({
    super.key,
    required this.left,
    required this.center,
    required this.right,
    this.bold = false,
  });

  final String left;
  final String center;
  final String right;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white70,
      fontSize: AppTypography.fontSizeXs,
      fontWeight: bold ? FontWeight.w600 : null,
    );
    Widget label(String text, TextAlign align) => Text(
      text,
      style: style,
      textAlign: align,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    if (center.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: math.max(1, left.length),
            child: label(left, TextAlign.left),
          ),
          const SizedBox(width: AppSpacing.spaceSm),
          Flexible(
            flex: math.max(1, right.length),
            child: label(right, TextAlign.right),
          ),
        ],
      );
    }
    Widget cell(String text, TextAlign align) =>
        Expanded(child: label(text, align));
    return Row(
      children: [
        cell(left, TextAlign.left),
        cell(center, TextAlign.center),
        cell(right, TextAlign.right),
      ],
    );
  }
}
