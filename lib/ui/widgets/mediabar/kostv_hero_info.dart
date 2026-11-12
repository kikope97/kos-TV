import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/media_bar_slide_item.dart';
import '../../../data/services/kostv_home.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/overview_text.dart';
import 'media_bar_new_release_label.dart';

/// Kos TV: what the banner of the recommended Home says of a pick. A small
/// block low on the left of a picture that fills the screen: its logo, why it
/// is there, a line of facts and a couple of lines of what it is about. No
/// card behind it, so the picture stays whole and the first row can show
/// under it.
class KostvHeroInfo extends StatelessWidget {
  const KostvHeroInfo({
    super.key,
    required this.item,
    required this.logo,
    this.compact = false,
  });

  final MediaBarSlideItem item;

  /// The pick's logo, or its title drawn large when it has none.
  final Widget logo;

  /// While a trailer plays: no description, so more of it shows.
  final bool compact;

  static const logoHeight = 92.0;

  /// The line of facts: «2024 · 16 · 1h 45m · Thriller · Drama».
  static String facts(MediaBarSlideItem item) {
    final runtime = item.runtime;
    return [
      if (item.year != null) '${item.year}',
      if (item.officialRating?.isNotEmpty == true) item.officialRating!,
      if (item.itemType != 'Series' && runtime != null)
        runtime.inHours > 0
            ? '${runtime.inHours}h ${runtime.inMinutes.remainder(60)}m'
            : '${runtime.inMinutes}m',
      ...item.genres.take(2),
    ].join('  •  ');
  }

  /// Why the pick is on the banner, or null when it isn't from the
  /// recommended rows.
  static String? why(MediaBarSlideItem item, AppLocalizations l10n) {
    final kind = item.kostvKind;
    if (kind == null) return null;
    return KostvHomeServerRow(
      kind: kind,
      label: item.kostvLabel,
      items: const [],
    ).title(l10n);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = AppColorScheme.onSurface;
    final shadows = [
      Shadow(blurRadius: 6, color: AppColorScheme.scrim.withValues(alpha: 0.6)),
    ];
    final reason = why(item, AppLocalizations.of(context));
    final line = facts(item);
    final rating = item.communityRating;
    final overview = cleanOverview(item.overview);
    final factStyle = theme.textTheme.bodySmall?.copyWith(
      color: ink.withValues(alpha: 0.85),
      fontWeight: FontWeight.w600,
      shadows: shadows,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: logoHeight, width: 300, child: logo),
        if (item.newRelease case final release?) ...[
          const SizedBox(height: 8),
          MediaBarNewReleaseLine(release: release),
        ],
        if (reason != null) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 15, color: AppColorScheme.accent),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    shadows: shadows,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (line.isNotEmpty || rating != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rating != null) ...[
                const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: Color(0xFFFBBF24),
                ),
                const SizedBox(width: 3),
                Text(rating.toStringAsFixed(1), style: factStyle),
                if (line.isNotEmpty) Text('  •  ', style: factStyle),
              ],
              Flexible(
                child: Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: factStyle,
                ),
              ),
            ],
          ),
        ],
        if (!compact && overview.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            overview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ink.withValues(alpha: 0.82),
              height: 1.35,
              shadows: shadows,
            ),
          ),
        ],
      ],
    );
  }
}

/// Kos TV: which pick the banner is on, as a short run of bars in a corner.
class KostvHeroDots extends StatelessWidget {
  const KostvHeroDots({super.key, required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final ink = AppColorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: i == current ? 0.95 : 0.4),
              borderRadius: AppRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
