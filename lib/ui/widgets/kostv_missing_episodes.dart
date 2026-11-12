import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../data/services/stremfin/kostv_series_gaps.dart';
import '../../data/services/stremfin/stremfin_client.dart';
import '../../data/services/stremfin/stremfin_models.dart';
import '../../l10n/app_localizations.dart';
import '../../util/platform_detection.dart';
import '../screens/detail/detail_layout_metrics.dart';
import 'focus/focusable_wrapper.dart';

/// Kos TV: what is said about an episode of a series at home that the home
/// server lacks, the same on every screen.
abstract final class KostvGhostTexts {
  static String _locale(BuildContext context) =>
      Localizations.localeOf(context).toLanguageTag();

  /// «20 de enero de 2008».
  static String longDate(BuildContext context, DateTime date) =>
      DateFormat.yMMMMd(_locale(context)).format(date);

  /// «3 mar», or «3 mar 2027» when it isn't this year.
  static String shortDate(BuildContext context, DateTime date) {
    final locale = _locale(context);
    return date.year == DateTime.now().year
        ? DateFormat.MMMd(locale).format(date)
        : DateFormat.yMMMd(locale).format(date);
  }

  /// «Se estrena hoy», «mañana», «el 3 mar», or «Próximamente».
  static String premiere(
    BuildContext context,
    DateTime? date, {
    bool long = false,
  }) {
    final l10n = AppLocalizations.of(context);
    if (date == null) return l10n.kostvGhostComingSoon;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final days = day.difference(today).inDays;
    if (days <= 0) return l10n.kostvGhostPremieresToday;
    if (days == 1) return l10n.kostvGhostPremieresTomorrow;
    return l10n.kostvGhostPremieres(
      long ? longDate(context, date) : shortDate(context, date),
    );
  }

  /// A line on how the episode stands.
  static String note(BuildContext context, KostvGhostEpisode ghost) {
    final l10n = AppLocalizations.of(context);
    return switch (ghost.state) {
      KostvGhostState.requestable => l10n.kostvGhostNotAtHome,
      KostvGhostState.joinable => l10n.kostvGhostAskedByOther,
      KostvGhostState.requested =>
        ghost.request?.isPending ?? true
            ? l10n.kostvGhostPending
            : l10n.kostvGhostAccepted,
      KostvGhostState.downloading => l10n.kostvGhostDownloadingNote,
      KostvGhostState.upcoming => l10n.kostvGhostNotOnYet,
      KostvGhostState.unavailable => l10n.kostvRequestUnavailable,
    };
  }

  /// A shorter line, for a phone's card and the player's list.
  static String shortNote(BuildContext context, KostvGhostEpisode ghost) {
    final l10n = AppLocalizations.of(context);
    return switch (ghost.state) {
      KostvGhostState.joinable => l10n.kostvGhostAskedByOtherShort,
      KostvGhostState.requested =>
        ghost.request?.isPending ?? true
            ? l10n.kostvGhostPendingShort
            : l10n.kostvGhostAcceptedShort,
      KostvGhostState.downloading => l10n.kostvGhostDownloadingShort,
      _ => note(context, ghost),
    };
  }

  /// What its button or badge says.
  static String? badge(BuildContext context, KostvGhostEpisode ghost) {
    final l10n = AppLocalizations.of(context);
    return switch (ghost.state) {
      KostvGhostState.requestable => l10n.kostvRequestAsk,
      KostvGhostState.joinable => l10n.kostvRequestMeToo,
      KostvGhostState.requested => l10n.kostvGhostRequested,
      KostvGhostState.downloading => l10n.kostvRequestDownloading,
      KostvGhostState.upcoming => premiere(context, ghost.airDate),
      KostvGhostState.unavailable => null,
    };
  }

  static IconData icon(KostvGhostEpisode ghost) => switch (ghost.state) {
    KostvGhostState.requestable => Icons.add_circle_outline,
    KostvGhostState.joinable => Icons.group_add_outlined,
    KostvGhostState.requested =>
      ghost.request?.isPending ?? true
          ? Icons.schedule
          : Icons.check_circle_outline,
    KostvGhostState.downloading => Icons.downloading,
    KostvGhostState.upcoming => Icons.event_outlined,
    KostvGhostState.unavailable => Icons.block,
  };

  /// Its own title, or null when it has none: TMDB names an episode it
  /// knows nothing of «Episodio 7».
  static String? ownTitle(KostvGhostEpisode ghost) {
    final title = ghost.title?.trim();
    if (title == null || title.isEmpty) return null;
    if (_numberOnly.hasMatch(title)) return null;
    return title;
  }

  static final _numberOnly = RegExp(
    r'^(episodio|episode|cap[ií]tulo|ep\.?)\s*\d+$',
    caseSensitive: false,
  );

  /// Its title, or «Episodio 7».
  static String title(BuildContext context, KostvGhostEpisode ghost) =>
      ownTitle(ghost) ??
      AppLocalizations.of(context).episodeNumber(ghost.number);

  /// The service's word on a request, said for an episode or a season.
  static String outcome(
    BuildContext context,
    StremfinRequestResult result, {
    StremfinMe? me,
    required bool episode,
  }) {
    final l10n = AppLocalizations.of(context);
    return switch (result.outcome) {
      StremfinOutcome.created => l10n.kostvRequestOutcomeCreated,
      StremfinOutcome.started =>
        episode
            ? l10n.kostvGhostOutcomeStarted
            : l10n.kostvRequestOutcomeStarted,
      StremfinOutcome.joined =>
        episode ? l10n.kostvGhostOutcomeJoined : l10n.kostvRequestOutcomeJoined,
      StremfinOutcome.watching => l10n.kostvRequestOutcomeWatching,
      StremfinOutcome.included => l10n.kostvRequestOutcomeIncluded,
      StremfinOutcome.already => l10n.kostvRequestOutcomeAlready,
      StremfinOutcome.have => l10n.kostvRequestOutcomeHave,
      StremfinOutcome.busy => l10n.kostvRequestOutcomeBusy,
      StremfinOutcome.unavailable => l10n.kostvRequestUnavailable,
      StremfinOutcome.limit =>
        result.limit == 'daily' || me?.dailyLeft == 0
            ? l10n.kostvRequestAtLimitDaily
            : l10n.kostvRequestLimitReached,
      StremfinOutcome.unknown =>
        result.message ?? l10n.kostvRequestOutcomeCreated,
    };
  }
}

/// Kos TV: asks for one missing episode, or for what's missing of a season
/// when [episode] is null, and says how it went.
Future<StremfinRequestResult?> kostvAskMissing(
  BuildContext context,
  KostvSeriesGapsController controller, {
  required int season,
  int? episode,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  void say(String text) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  try {
    final result = await controller.ask(season: season, episode: episode);
    if (result != null && context.mounted) {
      say(
        KostvGhostTexts.outcome(
          context,
          result,
          me: controller.me,
          episode: episode != null,
        ),
      );
    }
    return result;
  } on StremfinException catch (e) {
    say(e.status == 429 ? l10n.kostvRequestTooFast : l10n.kostvRequestFailed);
  } catch (_) {
    say(l10n.kostvRequestFailed);
  }
  return null;
}

/// Kos TV: where a missing episode's still would be: its number, large and
/// faint, and how it stands in a corner.
class KostvGhostThumb extends StatelessWidget {
  const KostvGhostThumb({
    super.key,
    required this.ghost,
    required this.width,
    required this.radius,
    required this.ink,
    this.height,
    this.label,
  });

  final KostvGhostEpisode ghost;
  final double width;
  final double? height;
  final double radius;

  /// What it says instead of the episode's number («7–8» for several).
  final String? label;

  /// The colour drawn on the page's background.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final height = this.height ?? width * 9 / 16;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.05),
        borderRadius: AppRadius.circular(radius),
        border: Border.all(color: ink.withValues(alpha: 0.12), width: 1.2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            label ?? '${ghost.number}',
            style: TextStyle(
              color: ink.withValues(alpha: 0.3),
              fontSize: height * 0.42,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          Positioned(
            right: height * 0.08,
            bottom: height * 0.08,
            child: Icon(
              KostvGhostTexts.icon(ghost),
              color: ink.withValues(alpha: 0.55),
              size: (height * 0.2).clamp(14, 26),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kos TV: a missing episode among the home server's on the series' page of
/// the Modern look, the same size as theirs and greyed.
class KostvGhostEpisodeCard extends StatelessWidget {
  const KostvGhostEpisodeCard({
    super.key,
    required this.ghost,
    required this.controller,
    this.focusNode,
    this.onNavigateUp,
  });

  final KostvGhostEpisode ghost;
  final KostvSeriesGapsController controller;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;

  @override
  Widget build(BuildContext context) {
    final compact = detailIsCompact(context);
    final scale = compact ? 1.0 : detailDesktopScale();
    final ink = AppColorScheme.onSurface;
    final theme = Theme.of(context).textTheme;
    final badge = KostvGhostTexts.badge(context, ghost);
    final asks = ghost.canAsk && !controller.atLimit;
    final upcoming = ghost.state == KostvGhostState.upcoming;
    return FocusableWrapper(
      focusNode: focusNode,
      onNavigateUp: onNavigateUp,
      onSelect: () =>
          showKostvGhostSheet(context, controller: controller, ghost: ghost),
      borderRadius: 8,
      child: Container(
        height: compact ? 90 : 110 * scale,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: AppRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Opacity(
              opacity: 0.8,
              child: KostvGhostThumb(
                ghost: ghost,
                width: compact ? 160 : 196 * scale,
                height: compact ? 90 : 110 * scale,
                radius: 8,
                ink: ink,
              ),
            ),
            SizedBox(width: 16 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    switch (KostvGhostTexts.ownTitle(ghost)) {
                      final title? => 'E${ghost.number}: $title',
                      null => AppLocalizations.of(
                        context,
                      ).episodeLabel(ghost.number),
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleSmall?.copyWith(
                      color: ink.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    upcoming
                        ? KostvGhostTexts.premiere(context, ghost.airDate)
                        : KostvGhostTexts.shortNote(context, ghost),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(
                      color: ink.withValues(alpha: 0.45),
                    ),
                  ),
                  if (badge != null && !upcoming) ...[
                    const SizedBox(height: 7),
                    _GhostPill(
                      label: badge,
                      icon: KostvGhostTexts.icon(ghost),
                      action: asks,
                      ink: ink,
                      scale: scale,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 12 * scale),
          ],
        ),
      ),
    );
  }
}

/// A missing episode's button (when it can be asked for) or its badge.
class _GhostPill extends StatelessWidget {
  const _GhostPill({
    required this.label,
    required this.icon,
    required this.action,
    required this.ink,
    required this.scale,
  });

  final String label;
  final IconData icon;
  final bool action;
  final Color ink;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final accent = AppColorScheme.accent;
    final color = action ? accent : ink.withValues(alpha: 0.55);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9 * scale, vertical: 3 * scale),
      decoration: BoxDecoration(
        color: action ? accent.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: AppRadius.circular(12 * scale),
        border: action
            ? null
            : Border.all(color: ink.withValues(alpha: 0.18), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5 * scale,
        children: [
          Icon(icon, size: 14 * scale, color: color),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12 * scale,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kos TV: the bar above a season's episodes when several are missing, or
/// over a season that isn't at home at all, in the Modern look.
class KostvSeasonAskBar extends StatelessWidget {
  const KostvSeasonAskBar({
    super.key,
    required this.season,
    required this.controller,
    this.focusNode,
    this.onNavigateUp,
  });

  final KostvSeasonGaps season;
  final KostvSeriesGapsController controller;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;

  @override
  Widget build(BuildContext context) {
    final ask = KostvSeasonAsk.of(context, season, controller);
    if (ask == null) return const SizedBox.shrink();
    final ink = AppColorScheme.onSurface;
    final accent = AppColorScheme.accent;
    final theme = Theme.of(context).textTheme;
    final row = Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.05),
        borderRadius: AppRadius.circular(10),
        border: Border.all(color: ink.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(ask.icon, size: 20, color: ink.withValues(alpha: 0.6)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ask.text,
              style: theme.bodyMedium?.copyWith(
                color: ink.withValues(alpha: 0.75),
              ),
            ),
          ),
          if (ask.button case final label?) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: ask.enabled ? accent : ink.withValues(alpha: 0.1),
                borderRadius: AppRadius.circular(16),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: ask.enabled
                      ? AppColorScheme.onAccent
                      : ink.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ] else if (ask.status case final status?) ...[
            const SizedBox(width: 10),
            Text(
              status,
              style: theme.bodySmall?.copyWith(
                color: ink.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
    if (ask.button == null) return row;
    return FocusableWrapper(
      focusNode: focusNode,
      onNavigateUp: onNavigateUp,
      borderRadius: 10,
      onSelect: ask.enabled
          ? () => kostvAskMissing(context, controller, season: season.number)
          : null,
      child: row,
    );
  }
}

/// Kos TV: what the bar over a season's episodes says and offers, the same
/// for every look.
@immutable
class KostvSeasonAsk {
  const KostvSeasonAsk({
    required this.text,
    required this.icon,
    this.button,
    this.status,
    this.enabled = true,
  });

  final String text;
  final IconData icon;

  /// The button's label, when the season can be asked for.
  final String? button;

  /// What it says instead, when it can't.
  final String? status;
  final bool enabled;

  /// Null when there's nothing to say: a season at home missing fewer than
  /// two episodes that can be asked for.
  static KostvSeasonAsk? of(
    BuildContext context,
    KostvSeasonGaps season,
    KostvSeriesGapsController controller,
  ) {
    final l10n = AppLocalizations.of(context);
    final asked = season.seasonRequest;
    final atLimit = controller.atLimit || controller.sending;
    if (!season.atHome) {
      if (season.notOnYet) {
        return KostvSeasonAsk(
          text: l10n.kostvGhostSeasonNotAtHome,
          icon: Icons.event_outlined,
          status: KostvGhostTexts.premiere(context, season.premiere),
        );
      }
      if (season.canAskSeason) {
        return KostvSeasonAsk(
          text: l10n.kostvGhostSeasonNotAtHome,
          icon: Icons.playlist_add,
          button: asked != null && !asked.mine
              ? l10n.kostvRequestMeToo
              : l10n.kostvGhostAskSeason,
          enabled: !atLimit,
        );
      }
      return KostvSeasonAsk(
        text: l10n.kostvGhostSeasonNotAtHome,
        icon: asked != null ? Icons.schedule : Icons.block,
        status: asked != null
            ? l10n.kostvGhostSeasonRequested
            : (season.missing.any((g) => g.state == KostvGhostState.downloading)
                  ? l10n.kostvRequestSeasonOnItsWay
                  : null),
      );
    }
    final askable = season.askable;
    if (askable < 2 || !season.canAskSeason) return null;
    return KostvSeasonAsk(
      text: l10n.kostvGhostSeasonMissing(season.missing.length),
      icon: Icons.playlist_add,
      button: l10n.kostvGhostAskMissing(askable),
      enabled: !atLimit,
    );
  }
}

/// Kos TV: a missing episode's sheet, with asking for it when it can be.
/// A dialog on a TV or a big screen, a sheet from the bottom on a phone.
Future<void> showKostvGhostSheet(
  BuildContext context, {
  required KostvSeriesGapsController controller,
  required KostvGhostEpisode ghost,
}) async {
  final l10n = AppLocalizations.of(context);
  final upcoming = ghost.state == KostvGhostState.upcoming;
  final atLimit = controller.atLimit;
  final asks = ghost.canAsk && !atLimit;
  final date = ghost.airDate;
  final ask = await _showSheet(
    context,
    eyebrow:
        '${l10n.seasonNumber(ghost.season)} · '
        '${l10n.episodeNumber(ghost.number)}',
    title: KostvGhostTexts.title(context, ghost),
    lines: [
      if (upcoming)
        (
          Icons.event_outlined,
          KostvGhostTexts.premiere(context, date, long: true),
          false,
        )
      else if (date != null)
        (
          Icons.event_outlined,
          l10n.kostvGhostAired(KostvGhostTexts.longDate(context, date)),
          false,
        ),
      if (!upcoming)
        (
          KostvGhostTexts.icon(ghost),
          KostvGhostTexts.note(context, ghost),
          false,
        ),
      if (ghost.canAsk && atLimit)
        (Icons.hourglass_empty, l10n.kostvRequestLimitReached, true),
    ],
    action: asks
        ? (
            KostvGhostTexts.icon(ghost),
            ghost.state == KostvGhostState.joinable
                ? l10n.kostvRequestMeToo
                : l10n.kostvGhostAskEpisode,
          )
        : null,
  );
  if (ask == true && context.mounted) {
    await kostvAskMissing(
      context,
      controller,
      season: ghost.season,
      episode: ghost.number,
    );
  }
}

/// Kos TV: the sheet of a season that isn't at home, with asking for it
/// when it can be.
Future<void> showKostvSeasonSheet(
  BuildContext context, {
  required KostvSeriesGapsController controller,
  required KostvSeasonGaps season,
}) async {
  final l10n = AppLocalizations.of(context);
  final ask = KostvSeasonAsk.of(context, season, controller);
  final aired = season.missing.length;
  final confirmed = await _showSheet(
    context,
    eyebrow: l10n.seasonNumber(season.number),
    title: ask?.text ?? l10n.kostvGhostSeasonNotAtHome,
    lines: [
      if (season.notOnYet)
        (
          Icons.event_outlined,
          KostvGhostTexts.premiere(context, season.premiere, long: true),
          false,
        )
      else
        (
          Icons.video_library_outlined,
          l10n.kostvSeasonEpisodeCount(aired),
          false,
        ),
      if (ask?.status case final status?) (Icons.schedule, status, false),
      if (ask?.button != null && !ask!.enabled)
        (Icons.hourglass_empty, l10n.kostvRequestLimitReached, true),
    ],
    action: ask?.button != null && ask!.enabled
        ? (Icons.playlist_add, ask.button!)
        : null,
  );
  if (confirmed == true && context.mounted) {
    await kostvAskMissing(context, controller, season: season.number);
  }
}

/// A line of a sheet: its icon, its text and whether it's a warning.
typedef _SheetLine = (IconData, String, bool);

Future<bool?> _showSheet(
  BuildContext context, {
  required String eyebrow,
  required String title,
  required List<_SheetLine> lines,
  required (IconData, String)? action,
}) {
  final compact = detailIsCompact(context) && !PlatformDetection.isTV;
  Widget body(bool compact) => _SheetBody(
    eyebrow: eyebrow,
    title: title,
    lines: lines,
    action: action,
    compact: compact,
  );
  if (compact) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColorScheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.circular(24)
            .copyWith(bottomLeft: Radius.zero, bottomRight: Radius.zero),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: body(true),
        ),
      ),
    );
  }
  return showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppColorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 32, 36, 28),
          child: body(false),
        ),
      ),
    ),
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.eyebrow,
    required this.title,
    required this.lines,
    required this.action,
    required this.compact,
  });

  final String eyebrow;
  final String title;
  final List<_SheetLine> lines;
  final (IconData, String)? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ink = AppColorScheme.onSurface;
    final accent = AppColorScheme.accent;

    Widget line(_SheetLine line) {
      final (icon, text, warning) = line;
      final color = warning
          ? AppColorScheme.statusPending
          : ink.withValues(alpha: 0.8);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: 19,
              color: warning ? color : ink.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: compact ? 15 : 17,
                height: 1.3,
              ),
            ),
          ),
        ],
      );
    }

    final action = this.action;
    final primary = action == null
        ? null
        : FilledButton.icon(
            autofocus: true,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: AppColorScheme.onAccent,
              padding: EdgeInsets.symmetric(
                horizontal: 22,
                vertical: compact ? 14 : 16,
              ),
              textStyle: TextStyle(
                fontSize: compact ? 15 : 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: Icon(action.$1, size: 20),
            label: Text(action.$2),
          );
    final secondary = TextButton(
      autofocus: primary == null,
      style: TextButton.styleFrom(
        foregroundColor: ink.withValues(alpha: 0.85),
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: compact ? 14 : 16,
        ),
        textStyle: TextStyle(fontSize: compact ? 15 : 17),
      ),
      onPressed: () => Navigator.of(context).pop(false),
      child: Text(primary == null ? l10n.close : l10n.cancel),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: TextStyle(
            color: ink.withValues(alpha: 0.55),
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(
            color: ink,
            fontSize: compact ? 22 : 28,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        SizedBox(height: compact ? 16 : 20),
        for (final (index, entry) in lines.indexed) ...[
          if (index > 0) const SizedBox(height: 10),
          line(entry),
        ],
        SizedBox(height: compact ? 22 : 28),
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [?primary, secondary],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 12,
            children: [secondary, ?primary],
          ),
      ],
    );
  }
}
