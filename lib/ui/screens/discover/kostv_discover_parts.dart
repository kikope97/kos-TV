import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/image_fetch_priority.dart';
import '../../navigation/destinations.dart';
import '../../widgets/image_source.dart';
import '../../widgets/kos_logo.dart';

/// Kos TV: the small pieces Discover is made of: how a title stands at home,
/// the labels over a poster and the platform buttons.

/// The colours of how a title stands at home.
abstract final class KostvDiscoverColors {
  static const home = Color(0xFF2EAD5B);
  static const missingSeason = Color(0xFFE08A00);
  static const comingSoon = Color(0xFF1E88E5);
  static const requested = Color(0xFF6D4AFF);
}

/// How a title stands at home, as a label: arrived (with the season it
/// lacks, if it does), coming down, asked for, or not there yet.
@immutable
class KostvTitleStatus {
  const KostvTitleStatus(this.text, this.icon, this.color);

  final String text;
  final IconData? icon;

  /// Null for a title that isn't at home and nobody has asked for.
  final Color? color;

  /// Each label that applies, the main one first.
  static List<KostvTitleStatus> of(StremfinTitle title, AppLocalizations l10n) {
    final library = title.library;
    final request = title.request;
    if (library.status == StremfinLibraryStatus.partial &&
        library.season != null) {
      return [
        KostvTitleStatus(
          l10n.kostvStatAtHome,
          Icons.check_rounded,
          KostvDiscoverColors.home,
        ),
        KostvTitleStatus(
          l10n.kostvDiscoverMissingSeason(library.season!),
          Icons.hourglass_bottom_rounded,
          KostvDiscoverColors.missingSeason,
        ),
      ];
    }
    if (title.isInLibrary) {
      return [
        KostvTitleStatus(
          l10n.kostvStatAtHome,
          Icons.check_rounded,
          KostvDiscoverColors.home,
        ),
      ];
    }
    if (library.downloading ||
        library.status == StremfinLibraryStatus.downloading) {
      return [
        KostvTitleStatus(
          l10n.kostvDiscoverComingSoon,
          Icons.downloading_rounded,
          KostvDiscoverColors.comingSoon,
        ),
      ];
    }
    if (request != null) {
      return [
        KostvTitleStatus(
          request.mine
              ? l10n.kostvDiscoverRequestedByYou
              : l10n.kostvDiscoverRequested,
          Icons.schedule_rounded,
          KostvDiscoverColors.requested,
        ),
      ];
    }
    return [KostvTitleStatus(l10n.kostvRequestNotHomeYet, null, null)];
  }

  /// The band across the foot of a poster: only what isn't plain (a title
  /// at home has its tick, and one nobody asked for needs no band).
  static KostvTitleStatus? band(StremfinTitle title, AppLocalizations l10n) {
    final library = title.library;
    if (library.status == StremfinLibraryStatus.partial &&
        library.season != null) {
      return of(title, l10n).last;
    }
    if (title.isInLibrary) return null;
    final status = of(title, l10n).first;
    return status.color == null ? null : status;
  }
}

/// What is on the home server opens its page there. The rest, and a series
/// missing the season its card announces, opens its page to request it.
void kostvOpenTitle(BuildContext context, StremfinTitle title) {
  final itemId = title.library.itemId;
  final partial = title.library.status == StremfinLibraryStatus.partial;
  if (title.isInLibrary && itemId != null && !partial) {
    context.push(Destinations.item(itemId));
    return;
  }
  context.push(
    Destinations.kostvRequestOf(title.type.apiValue, title.tmdbId),
    extra: title,
  );
}

/// Over a poster, how its title stands at home: the tick of one that is
/// there (top right, or above the band), and a band across the foot for
/// what isn't plain (asked for, coming, missing a season).
List<Widget> kostvPosterStatus(
  StremfinTitle title,
  AppLocalizations l10n, {
  required double scale,
}) {
  final status = KostvTitleStatus.band(title, l10n);
  final bandHeight = 20 * scale;
  return [
    if (title.isInLibrary)
      Positioned(
        top: status == null ? 6 : null,
        bottom: status == null ? null : bandHeight + 4,
        right: 6,
        child: KostvHomeTick(scale: scale),
      ),
    if (status != null)
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          height: bandHeight,
          alignment: Alignment.center,
          color: status.color!.withValues(alpha: 0.92),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            status.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5 * scale,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
      ),
  ];
}

/// A status as a chip: filled with its colour, or a quiet outline for one
/// that isn't at home yet.
class KostvStatusChip extends StatelessWidget {
  const KostvStatusChip({super.key, required this.status, this.unit = 1});

  final KostvTitleStatus status;
  final double unit;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    final ink = color == null
        ? AppColorScheme.onBackground.withValues(alpha: 0.85)
        : Colors.white;
    return Container(
      padding: EdgeInsets.fromLTRB(
        (status.icon == null ? 11 : 8) * unit,
        4 * unit,
        11 * unit,
        4 * unit,
      ),
      decoration: BoxDecoration(
        color:
            color?.withValues(alpha: 0.9) ??
            Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color == null
              ? Colors.white.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.icon case final icon?) ...[
            Icon(icon, size: 15 * unit, color: ink),
            SizedBox(width: 5 * unit),
          ],
          Text(
            status.text,
            style: TextStyle(
              color: ink,
              fontSize: 12.5 * unit,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small label over a poster.
class KostvPosterPill extends StatelessWidget {
  const KostvPosterPill({
    super.key,
    required this.text,
    required this.color,
    required this.scale,
  });

  final String text;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6 * scale),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: 11.5 * scale,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
    ),
  );
}

/// The place on a most-watched list, as a tag in the corner of the poster.
class KostvRankTag extends StatelessWidget {
  const KostvRankTag({super.key, required this.rank, required this.scale});

  final int rank;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = 26 * scale;
    final top = rank <= 3;
    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: EdgeInsets.symmetric(horizontal: 6 * scale),
      decoration: BoxDecoration(
        gradient: top
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [KosBrand.violet, Color(0xFF5B3FD6)],
              )
            : null,
        color: top ? null : Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          '$rank',
          style: TextStyle(
            color: Colors.white,
            fontFamily: KosBrand.fontFamily,
            fontSize: 14.5 * scale,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// The tick of a title that is at home.
class KostvHomeTick extends StatelessWidget {
  const KostvHomeTick({super.key, required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: AppLocalizations.of(context).kostvDiscoverInLibrary,
    child: Container(
      width: 26 * scale,
      height: 26 * scale,
      decoration: const BoxDecoration(
        color: KostvDiscoverColors.home,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
      ),
      child: Icon(Icons.check_rounded, color: Colors.white, size: 18 * scale),
    ),
  );
}

/// The platforms' white logos, from TMDB's images (nothing is bundled with
/// the app).
const kostvPlatformLogos = {
  'netflix': 'https://image.tmdb.org/t/p/w500_filter(duotone,ffffff,bababa)/wwemzKWzjKYJFfCeiB57q3r4Bcm.png',
  'disney': 'https://image.tmdb.org/t/p/w500_filter(duotone,ffffff,bababa)/gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png',
  'prime': 'https://image.tmdb.org/t/p/w500_filter(duotone,ffffff,bababa)/ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png',
};

/// A platform's button: a pill with its logo, filled with its colour when
/// it is the one chosen.
class KostvPlatformPill extends StatelessWidget {
  const KostvPlatformPill({
    super.key,
    required this.platform,
    required this.width,
    required this.height,
    required this.selected,
    required this.focused,
    required this.focusColor,
    required this.onTap,
  });

  final StremfinPlatform platform;
  final double width;
  final double height;
  final bool selected;
  final bool focused;
  final Color focusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final logo = kostvPlatformLogos[platform.id];
    final Widget content;
    if (platform.isAll) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KosRingMark(size: height * 0.5),
          SizedBox(width: height * 0.2),
          Text(
            l10n.kostvDiscoverAll,
            style: TextStyle(
              color: Colors.white,
              fontFamily: KosBrand.fontFamily,
              fontSize: height * 0.4,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      );
    } else {
      final name = Text(
        platform.name,
        maxLines: 1,
        style: TextStyle(
          color: Colors.white,
          fontSize: height * 0.36,
          fontWeight: FontWeight.w800,
        ),
      );
      final logoHeight = height * (platform.id == 'netflix' ? 0.42 : 0.56);
      // Decoded at the height it paints, not the source's, and kept on disk.
      content = logo == null
          ? name
          : ArtworkBound(
              height: logoHeight,
              builder: (context, width, decodeHeight) => Image(
                image: ArtworkDecode.provider(
                  logo,
                  width: width,
                  height: decodeHeight,
                  headers: artworkFetchHeaders(logo, ImageFetchPriority.high),
                ),
                height: logoHeight,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => name,
              ),
            );
    }

    final base = platform.isAll
        ? KosBrand.violet
        : (platform.color ?? const Color(0xFF2A2140));
    final lit = selected || focused;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: focused ? 1.07 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: width,
            height: height,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: height * 0.4),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: platform.isAll
                          ? const [KosBrand.violet, Color(0xFF4A2FB8)]
                          : [base, Color.lerp(base, Colors.black, 0.4)!],
                    )
                  : null,
              color: selected
                  ? null
                  : Colors.white.withValues(alpha: focused ? 0.16 : 0.07),
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(
                color: focused
                    ? focusColor
                    : Colors.white.withValues(alpha: selected ? 0.3 : 0.12),
                width: focused ? 2.5 : 1,
              ),
              boxShadow: [
                if (selected)
                  BoxShadow(
                    color: base.withValues(alpha: 0.45),
                    blurRadius: height * 0.5,
                    offset: Offset(0, height * 0.08),
                  ),
                if (focused)
                  BoxShadow(
                    color: focusColor.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
              ],
            ),
            child: AnimatedOpacity(
              opacity: lit ? 1 : 0.62,
              duration: const Duration(milliseconds: 160),
              child: FittedBox(fit: BoxFit.scaleDown, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// From grey ([amount] 0, a little dimmed) to its own colour (1).
ColorFilter kostvSaturation(double amount) {
  final s = amount.clamp(0.0, 1.0);
  final dim = lerpDouble(0.72, 1, s)!;
  const r = 0.2126, g = 0.7152, b = 0.0722;
  List<double> row(int channel) {
    final values = [r * (1 - s), g * (1 - s), b * (1 - s)];
    values[channel] += s;
    return [for (final v in values) v * dim, 0, 0];
  }

  return ColorFilter.matrix([...row(0), ...row(1), ...row(2), 0, 0, 0, 1, 0]);
}

/// The grey of a title that isn't at home.
final kostvMissingFilter = kostvSaturation(0);
