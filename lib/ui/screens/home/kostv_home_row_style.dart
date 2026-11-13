import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/home_row.dart';
import '../../widgets/kos_logo.dart';
import '../../../data/services/kostv_home.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/user_preferences.dart';

/// Kos TV: how a row of the recommended Home presents itself: an icon in its
/// own colour, its title with what it is about picked out, and a line saying
/// why it is there.
@immutable
class KostvHomeRowStyle {
  const KostvHomeRowStyle({
    required this.icon,
    required this.color,
    required this.before,
    required this.name,
    required this.after,
    required this.why,
    this.ranked = false,
    this.fresh = false,
  });

  final IconData icon;
  final Color color;

  /// The title in three parts: [name] is what the row is about («Cars» in
  /// «Porque viste Cars») and is drawn stronger; empty when it has none.
  final String before;
  final String name;
  final String after;

  /// A short line under the title.
  final String why;

  /// Its cards carry their place on the list (the tops).
  final bool ranked;

  /// Its cards carry a «Nuevo» tag (what the person asked for).
  final bool fresh;

  static const _rowPrefixes = ['kostvRec_', 'kostvMore_'];

  /// The style of [row], or null when it isn't one of the recommended Home's.
  static KostvHomeRowStyle? of(HomeRow row, AppLocalizations l10n) {
    if (row.id == KostvHomeRepository.arrivedRowId) {
      return KostvHomeRowStyle(
        icon: Icons.celebration_outlined,
        color: const Color(0xFF34D399),
        before: row.title,
        name: '',
        after: '',
        why: l10n.kostvHomeWhyArrived,
        fresh: true,
      );
    }
    // Shuffle closes every Home; in the recommended one it is dressed like
    // the rest.
    if (row.id == KostvHomeRepository.shuffleRowId &&
        GetIt.instance.isRegistered<UserPreferences>() &&
        GetIt.instance<UserPreferences>().kostvHomeActive) {
      return KostvHomeRowStyle(
        icon: Icons.shuffle_rounded,
        color: const Color(0xFFFBBF24),
        before: row.title,
        name: '',
        after: '',
        why: l10n.kostvShuffleWhy,
      );
    }
    // Carrying on is a row of every Home; in the recommended one it is
    // dressed like the rest.
    if (row.id == 'resume' &&
        GetIt.instance.isRegistered<UserPreferences>() &&
        GetIt.instance<UserPreferences>().kostvHomeActive) {
      return KostvHomeRowStyle(
        icon: Icons.play_arrow_rounded,
        color: AppColorScheme.accent,
        before: l10n.continueWatchingAndNextUp,
        name: '',
        after: '',
        why: l10n.kostvHomeWhyResume,
      );
    }
    final prefix = _rowPrefixes.where(row.id.startsWith).firstOrNull;
    if (prefix == null) return null;
    final rest = row.id.substring(prefix.length);
    final accent = AppColorScheme.accent;

    KostvHomeRowStyle about(
      IconData icon,
      Color color,
      String Function(String) title,
      String why,
    ) {
      // The words around the name, from the same text the title was made of.
      const mark = '\u0000';
      final parts = title(mark).split(mark);
      final before = parts.first;
      final after = parts.length > 1 ? parts.last : '';
      final fits =
          row.title.startsWith(before) &&
          row.title.endsWith(after) &&
          row.title.length >= before.length + after.length;
      return KostvHomeRowStyle(
        icon: icon,
        color: color,
        before: fits ? before : row.title,
        name: fits
            ? row.title.substring(
                before.length,
                row.title.length - after.length,
              )
            : '',
        after: fits ? after : '',
        why: why,
      );
    }

    if (rest == KostvHomeRepository.myListKind) {
      return KostvHomeRowStyle(
        icon: Icons.bookmark_rounded,
        color: const Color(0xFFF472B6),
        before: row.title,
        name: '',
        after: '',
        why: l10n.kostvMyListWhy,
      );
    }
    if (rest == KostvHomeRepository.newEpisodesKind) {
      return KostvHomeRowStyle(
        icon: Icons.new_releases_outlined,
        color: const Color(0xFF60A5FA),
        before: row.title,
        name: '',
        after: '',
        why: l10n.kostvHomeWhyNewEpisodes,
        fresh: true,
      );
    }
    if (rest.startsWith('top_')) {
      return KostvHomeRowStyle(
        icon: Icons.local_fire_department,
        color: const Color(0xFFFF7A45),
        before: row.title,
        name: '',
        after: '',
        why: l10n.kostvHomeWhyTop,
        ranked: true,
      );
    }
    if (rest.startsWith('because_watched')) {
      return about(
        Icons.history,
        accent,
        l10n.kostvHomeBecauseWatched,
        l10n.kostvHomeWhyBecause,
      );
    }
    if (rest.startsWith('because_watching')) {
      return about(
        Icons.play_circle_outline,
        accent,
        l10n.kostvHomeBecauseWatching,
        l10n.kostvHomeWhyBecause,
      );
    }
    if (rest.startsWith('with_person')) {
      return about(
        Icons.person_outline,
        const Color(0xFFC084FC),
        l10n.kostvHomeMoreFrom,
        l10n.kostvHomeWhyPerson,
      );
    }
    if (rest.startsWith('genre')) {
      return about(
        Icons.theaters_outlined,
        const Color(0xFFFBBF24),
        l10n.kostvHomeGenre,
        l10n.kostvHomeWhyGenre,
      );
    }
    if (rest.startsWith('hidden_gems')) {
      return KostvHomeRowStyle(
        icon: Icons.diamond_outlined,
        color: const Color(0xFF67E8F9),
        before: row.title,
        name: '',
        after: '',
        why: l10n.kostvHomeWhyGems,
      );
    }
    if (rest.startsWith('for_you')) {
      return KostvHomeRowStyle(
        icon: Icons.auto_awesome,
        color: accent,
        before: row.title,
        name: '',
        after: '',
        why: l10n.kostvHomeWhyForYou,
      );
    }
    return null;
  }
}

/// Kos TV: the title of a row of the recommended Home.
class KostvHomeRowTitle extends StatelessWidget {
  const KostvHomeRowTitle({
    super.key,
    required this.style,
    this.compact = false,
  });

  final KostvHomeRowStyle style;

  /// On a phone: smaller, the same shape.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ink = AppColorScheme.onSurface;
    final base = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: compact ? 16 : null,
      color: ink.withValues(alpha: style.name.isEmpty ? 1 : 0.72),
      fontWeight: style.name.isEmpty ? FontWeight.w700 : FontWeight.w500,
    );
    // No taller than the title's line, so the row keeps its height.
    final chip = compact ? 22.0 : 24.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: chip,
          height: chip,
          decoration: BoxDecoration(
            color: style.color.withValues(alpha: 0.16),
            borderRadius: AppRadius.circular(7),
            border: Border.all(color: style.color.withValues(alpha: 0.35)),
          ),
          child: Icon(style.icon, size: chip * 0.66, color: style.color),
        ),
        SizedBox(width: compact ? 9 : 11),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: style.before,
              children: [
                if (style.name.isNotEmpty)
                  TextSpan(
                    text: style.name,
                    style: TextStyle(color: ink, fontWeight: FontWeight.w800),
                  ),
                if (style.after.isNotEmpty) TextSpan(text: style.after),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base,
          ),
        ),
      ],
    );
  }
}

/// Kos TV: a card of the recommended Home with its place on a top, or its
/// «Nuevo» tag, in its corner.
///
/// The place is a big number standing on the bottom left of the poster, as
/// streaming apps show their top ten: dark, outlined in white, hanging a
/// little off the edge.
class KostvHomeCardTag extends StatelessWidget {
  const KostvHomeCardTag({
    super.key,
    required this.child,
    this.rank,
    this.label,
    this.color,
    this.imageHeight,
  });

  final Widget child;

  /// From 1; null for no number.
  final int? rank;
  final String? label;
  final Color? color;

  /// How tall the card's picture is, which the number stands on. Without it
  /// the number goes small in the top corner.
  final double? imageHeight;

  @override
  Widget build(BuildContext context) {
    final rank = this.rank;
    final label = this.label;
    if (rank == null && label == null) return child;
    final color = this.color ?? AppColorScheme.accent;
    final height = imageHeight;
    if (rank != null && height != null) {
      final size = height * (rank >= 10 ? 0.4 : 0.48);
      TextStyle style(Paint? paint, {Color? fill}) => TextStyle(
        fontFamily: KosBrand.fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: size,
        height: 1,
        letterSpacing: -size * 0.06,
        foreground: paint,
        color: paint == null ? fill : null,
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            left: -size * 0.07,
            top: height - size * 0.86,
            child: IgnorePointer(
              child: Stack(
                children: [
                  Text(
                    '$rank',
                    style: style(
                      Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = (size * 0.06).clamp(2.0, 6.0)
                        ..strokeJoin = StrokeJoin.round
                        ..color = Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                  Text(
                    '$rank',
                    style: style(null, fill: const Color(0xF20B0D12)).copyWith(
                      shadows: [
                        Shadow(
                          color: color.withValues(alpha: 0.55),
                          blurRadius: size * 0.18,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: 6,
          top: 6,
          child: IgnorePointer(
            child: rank != null
                ? Container(
                    constraints: const BoxConstraints(minWidth: 28),
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [color, Color.lerp(color, Colors.black, 0.35)!],
                      ),
                      borderRadius: AppRadius.circular(9),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 6),
                      ],
                    ),
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: AppRadius.circular(7),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 6),
                      ],
                    ),
                    child: Text(
                      label!.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF04261A),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        height: 1.1,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
