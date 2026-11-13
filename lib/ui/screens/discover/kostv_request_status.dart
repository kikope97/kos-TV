import 'package:flutter/material.dart';

import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../l10n/app_localizations.dart';

/// Kos TV: how a request stands, in words, as a title's page and the
/// requests tray both say it.

/// The colour a state takes.
enum KostvTone { action, pending, progress, done, muted, failed }

/// A request's state: its words, its icon, its colour and how far it has
/// got (0 to 1).
@immutable
class KostvStatus {
  const KostvStatus({
    required this.label,
    this.icon,
    this.tone = KostvTone.action,
    this.progress,
  });

  final String label;
  final IconData? icon;
  final KostvTone tone;
  final double? progress;
}

/// Where an accepted request is.
KostvStatus kostvProgressStatus(
  AppLocalizations l10n,
  StremfinProgress? progress,
) {
  final state = progress?.state ?? StremfinProgressState.accepted;
  final transfer = progress?.transfer ?? const StremfinTransfer();
  switch (state) {
    case StremfinProgressState.accepted:
    case StremfinProgressState.unknown:
      return KostvStatus(
        label: l10n.kostvRequestAccepted,
        icon: Icons.check_rounded,
        tone: KostvTone.progress,
      );
    case StremfinProgressState.preparing:
      return KostvStatus(
        label: l10n.kostvRequestLookingForEpisodes,
        icon: Icons.travel_explore_rounded,
        tone: KostvTone.progress,
      );
    case StremfinProgressState.waitingVersion:
      return KostvStatus(
        label: l10n.kostvRequestWaitingVersion,
        icon: Icons.hourglass_empty_rounded,
        tone: KostvTone.pending,
      );
    case StremfinProgressState.attention:
      return KostvStatus(
        // Kos TV: tried again on its own, nobody has to do a thing.
        label: progress?.recheck != null
            ? l10n.kostvRequestRetrying
            : l10n.kostvRequestUnderReview,
        icon: progress?.recheck != null
            ? Icons.autorenew_rounded
            : Icons.report_outlined,
        tone: KostvTone.pending,
      );
    case StremfinProgressState.importing:
      return KostvStatus(
        label: l10n.kostvRequestMusicImporting,
        icon: Icons.library_add_rounded,
        tone: KostvTone.progress,
        progress: 1,
      );
    case StremfinProgressState.downloading:
      return kostvTransferStatus(l10n, transfer);
  }
}

KostvStatus kostvTransferStatus(
  AppLocalizations l10n,
  StremfinTransfer transfer,
) {
  final percent = transfer.percent;
  final fill = percent == null ? null : percent / 100;
  if (transfer.paused) {
    return KostvStatus(
      label: l10n.kostvRequestPaused,
      icon: Icons.pause_rounded,
      tone: KostvTone.progress,
      progress: fill,
    );
  }
  return switch (transfer.phase) {
    StremfinPhase.queued => KostvStatus(
      label: l10n.kostvRequestQueued,
      icon: Icons.schedule_rounded,
      tone: KostvTone.progress,
      progress: fill,
    ),
    StremfinPhase.preparing || null => KostvStatus(
      label: l10n.kostvRequestPreparing,
      icon: Icons.downloading_rounded,
      tone: KostvTone.progress,
      progress: fill,
    ),
    StremfinPhase.waitingFile => KostvStatus(
      label: l10n.kostvRequestWaitingFile,
      icon: Icons.hourglass_top_rounded,
      tone: KostvTone.progress,
      progress: fill,
    ),
    StremfinPhase.verifying => KostvStatus(
      label: l10n.kostvRequestVerifying,
      icon: Icons.fact_check_outlined,
      tone: KostvTone.progress,
      progress: 1,
    ),
    StremfinPhase.moving || StremfinPhase.completed => KostvStatus(
      label: l10n.kostvRequestMoving,
      icon: Icons.drive_file_move_outline,
      tone: KostvTone.progress,
      progress: 1,
    ),
    StremfinPhase.attention => KostvStatus(
      label: transfer.recheck != null
          ? l10n.kostvRequestRetrying
          : l10n.kostvRequestUnderReview,
      icon: transfer.recheck != null
          ? Icons.autorenew_rounded
          : Icons.report_outlined,
      tone: KostvTone.pending,
    ),
    StremfinPhase.sent => KostvStatus(
      label: l10n.kostvRequestMusicSent,
      icon: Icons.send_rounded,
      tone: KostvTone.progress,
      progress: fill,
    ),
    StremfinPhase.importing => KostvStatus(
      label: l10n.kostvRequestMusicImporting,
      icon: Icons.library_add_rounded,
      tone: KostvTone.progress,
      progress: 1,
    ),
    StremfinPhase.failed => KostvStatus(
      label: l10n.kostvRequestMusicFailed,
      icon: Icons.report_outlined,
      tone: KostvTone.pending,
    ),
    StremfinPhase.downloading || StremfinPhase.unknown => KostvStatus(
      label: percent == null
          ? l10n.kostvRequestDownloading
          : l10n.kostvRequestDownloadingPercent(percent),
      icon: Icons.download_rounded,
      tone: KostvTone.progress,
      progress: fill,
    ),
  };
}

/// How a request stands, whatever its state.
KostvStatus kostvRequestStatus(
  AppLocalizations l10n,
  StremfinRequest request,
) => switch (request.status) {
  StremfinRequestStatus.pending => KostvStatus(
    label: l10n.kostvRequestPending,
    icon: Icons.hourglass_top_rounded,
    tone: KostvTone.pending,
  ),
  StremfinRequestStatus.completed => KostvStatus(
    label: l10n.kostvRequestArrived,
    icon: Icons.check_circle_rounded,
    tone: KostvTone.done,
  ),
  // Kos TV: accepted and then cancelled (Stremfin 1.88).
  StremfinRequestStatus.rejected when request.cancelled => KostvStatus(
    label: l10n.kostvRequestCancelled,
    icon: Icons.do_not_disturb_on_outlined,
    tone: KostvTone.failed,
  ),
  StremfinRequestStatus.rejected => KostvStatus(
    label: switch (request.reason) {
      'quality' => l10n.kostvRequestRejectedQuality,
      'later' => l10n.kostvRequestRejectedLater,
      _ => l10n.kostvRequestRejected,
    },
    icon: Icons.do_not_disturb_on_outlined,
    tone: KostvTone.failed,
  ),
  _ => kostvProgressStatus(l10n, request.progress),
};
