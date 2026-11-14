import 'package:flutter/material.dart';

import '../../../widgets/adaptive/sf_symbol.dart';

import '../../../../data/models/aggregated_item.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../util/episode_code.dart';
import '../../../../util/playback_time_label.dart';

/// Kos TV: the brand's colours, for the details page's touches of colour.
const kostvCyan = Color(0xFF4FD8FF);
const kostvViolet = Color(0xFF8F6BFF);
const kostvPink = Color(0xFFFF5CCF);
const kostvGradient = LinearGradient(
  colors: [kostvCyan, kostvViolet, kostvPink],
);

/// Kos TV: the light fill of a lit button, as Play's.
const kostvLight = Color(0xFFF3F5FA);

/// Kos TV: the dark ink on a lit button.
const kostvOnLight = Color(0xFF14161C);

/// Kos TV: a glass button's face, as the navbar's capsule: a see-through
/// fill brighter at the top, with a pale rim. [lit] (focused, or the one
/// that matters most) turns it light, as Play is.
BoxDecoration kostvGlass({
  bool lit = false,
  bool enabled = true,
  double radius = 22,
}) => BoxDecoration(
  color: lit ? kostvLight : null,
  gradient: lit
      ? null
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: enabled ? 0.24 : 0.1),
            Colors.white.withValues(alpha: enabled ? 0.1 : 0.04),
          ],
        ),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(
    color: Colors.white.withValues(alpha: lit ? 0 : (enabled ? 0.32 : 0.14)),
  ),
  boxShadow: [
    if (lit)
      BoxShadow(color: kostvViolet.withValues(alpha: 0.4), blurRadius: 20),
  ],
);

/// The ink on [kostvGlass].
Color kostvGlassInk({bool lit = false, bool enabled = true}) => lit
    ? kostvOnLight
    : const Color(0xFFF3F5FA).withValues(alpha: enabled ? 1 : 0.5);

/// Kos TV: what Play says on the kOS TV details page, worked out from the
/// title: «Seguir viendo · Quedan 48 min» with how far it got, «Seguir con
/// T2:E5» for a series half watched, or the plain label with the runtime.
class KostvPlayText {
  final String title;
  final String? subtitle;
  final double? progress;

  const KostvPlayText(this.title, {this.subtitle, this.progress});

  static KostvPlayText of(
    AppLocalizations l10n,
    String label,
    AggregatedItem? item, {
    AggregatedItem? nextUp,
  }) {
    if (item == null) return KostvPlayText(label);
    final runtime = item.runtime;
    final position = item.playbackPosition ?? Duration.zero;
    if (runtime != null &&
        runtime > Duration.zero &&
        position > Duration.zero &&
        position < runtime) {
      final left = runtime - position;
      return KostvPlayText(
        l10n.kostvDetailContinue,
        subtitle: l10n.kostvDetailLeft(
          formatRuntimeShort(Duration(minutes: (left.inSeconds / 60).ceil())),
        ),
        progress: (position.inMilliseconds / runtime.inMilliseconds).clamp(
          0.0,
          1.0,
        ),
      );
    }
    final isShow = item.type == 'Series' || item.type == 'Season';
    final s = nextUp?.parentIndexNumber;
    final e = nextUp?.indexNumber;
    if (isShow && s != null && e != null && !(s == 1 && e == 1)) {
      final nextRuntime = nextUp!.runtime;
      final nextPosition = nextUp.playbackPosition ?? Duration.zero;
      final started =
          nextRuntime != null &&
          nextRuntime > Duration.zero &&
          nextPosition > Duration.zero &&
          nextPosition < nextRuntime;
      return KostvPlayText(
        l10n.kostvDetailContinueWith('$seasonMark$s:E$e'),
        subtitle: nextUp.name,
        progress: started
            ? (nextPosition.inMilliseconds / nextRuntime.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : null,
      );
    }
    if (runtime != null && runtime > Duration.zero && !isShow) {
      return KostvPlayText(label, subtitle: formatRuntimeShort(runtime));
    }
    return KostvPlayText(label);
  }
}

/// Kos TV: a button of the kOS TV details page. Play is a light pill that
/// says what it plays (and how far it got); the rest are glass circles with
/// their name always under them, so nobody has to guess an icon.
class KostvButtonFace extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Widget Function(double size, Color color)? iconBuilder;
  final bool isPrimary;
  final bool isActive;
  final Color? activeColor;
  final bool focused;

  /// A phone: Play across the width, smaller circles.
  final bool compact;
  final KostvPlayText? play;

  const KostvButtonFace({
    super.key,
    required this.label,
    required this.icon,
    required this.iconBuilder,
    required this.isPrimary,
    required this.isActive,
    required this.activeColor,
    required this.focused,
    required this.compact,
    this.play,
  });

  static const _duration = Duration(milliseconds: 160);

  @override
  Widget build(BuildContext context) {
    return isPrimary ? _primary(context) : _circle(context);
  }

  Widget _primary(BuildContext context) {
    final text = play ?? KostvPlayText(label);
    const ink = Color(0xFF0B0B12);
    final height = compact ? 56.0 : 72.0;
    final title = Text(
      text.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: ink,
        fontSize: compact ? 17 : 21,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
    );
    final subtitle = text.subtitle == null
        ? null
        : Text(
            text.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFF55566A),
              fontSize: compact ? 13 : 15,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          );
    final bar = text.progress == null
        ? null
        : Container(
            height: 4,
            width: compact ? 150 : 170,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: text.progress,
              child: Container(
                decoration: BoxDecoration(
                  color: kostvViolet,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );

    final content = compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AdaptiveIcon(icon ?? Icons.play_arrow, color: ink, size: 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        text: text.title,
                        children: [
                          if (text.subtitle != null)
                            TextSpan(
                              text: ' · ${text.subtitle}',
                              style: const TextStyle(
                                color: Color(0xFF55566A),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (bar != null) ...[const SizedBox(height: 6), bar],
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdaptiveIcon(icon ?? Icons.play_arrow, color: ink, size: 30),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      subtitle,
                    ],
                    if (bar != null) ...[const SizedBox(height: 6), bar],
                  ],
                ),
              ),
            ],
          );

    return AnimatedScale(
      scale: focused && !compact ? 1.04 : 1,
      duration: _duration,
      child: AnimatedContainer(
        duration: _duration,
        height: height,
        width: compact ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 30),
        // Only the phone's spans the width; elsewhere it's as wide as what it
        // says.
        alignment: compact ? Alignment.center : null,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F5FA),
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: focused ? kostvViolet : Colors.transparent,
            width: 3.5,
          ),
          boxShadow: [
            BoxShadow(
              color: focused
                  ? kostvViolet.withValues(alpha: 0.5)
                  : Colors.black.withValues(alpha: 0.35),
              blurRadius: focused ? 28 : 18,
              offset: focused ? Offset.zero : const Offset(0, 8),
            ),
          ],
        ),
        child: content,
      ),
    );
  }

  Widget _circle(BuildContext context) {
    final size = compact ? 46.0 : 64.0;
    final Color color;
    if (isActive && icon == Icons.favorite) {
      color = const Color(0xFFFF375F);
    } else if (isActive) {
      color = activeColor ?? kostvCyan;
    } else {
      color = focused ? const Color(0xFF0B0B12) : const Color(0xFFF3F5FA);
    }
    final circle = AnimatedContainer(
      duration: _duration,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: focused
            ? const Color(0xFFF3F5FA)
            : Colors.white.withValues(alpha: 0.12),
        border: Border.all(
          color: focused ? kostvViolet : Colors.white.withValues(alpha: 0.18),
          width: focused ? 3 : 1,
        ),
        boxShadow: [
          if (focused)
            BoxShadow(
              color: kostvViolet.withValues(alpha: 0.45),
              blurRadius: 22,
            ),
        ],
      ),
      child: Center(
        child: iconBuilder != null
            ? iconBuilder!(compact ? 22 : 28, color)
            : AdaptiveIcon(icon!, color: color, size: compact ? 21 : 27),
      ),
    );
    return SizedBox(
      width: compact ? 66 : 96,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: focused && !compact ? 1.08 : 1,
            duration: _duration,
            child: circle,
          ),
          SizedBox(height: compact ? 6 : 9),
          // Two lines' room for every label, so the circles stay in line.
          SizedBox(
            height:
                MediaQuery.textScalerOf(context).scale(compact ? 11.5 : 14) *
                    1.15 *
                    2 +
                2,
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: focused
                    ? const Color(0xFFF3F5FA)
                    : const Color(0xFFF3F5FA).withValues(alpha: 0.7),
                fontSize: compact ? 11.5 : 14,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
