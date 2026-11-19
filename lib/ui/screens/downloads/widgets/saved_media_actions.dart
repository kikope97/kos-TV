import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../data/database/offline_database.dart';
import '../../../../data/models/aggregated_item.dart';
import '../../../../data/models/download_quality.dart';
import '../../../../data/repositories/offline_repository.dart';
import '../../../../data/services/download_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../util/download_grouping.dart';
import '../../../navigation/destinations.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';
import '../../../widgets/overlay_sheet.dart';

/// The metadata line under a saved item's title.
///
/// Outside a show an episode has to say which show it belongs to, because the
/// list mixes every library together. Inside one that is already the heading,
/// so the line gives the numbering and the quality instead.
String savedMediaSubtitle(
  AppLocalizations l10n,
  DownloadedItem item, {
  bool insideShow = false,
}) {
  final numberLabel = episodeNumberLabel(item);
  if (item.type == 'Episode') {
    if (insideShow) {
      // Kos TV: the preset's label, not its stored name.
      return [
        ?numberLabel,
        DownloadQuality.fromName(item.qualityPreset).label(l10n),
      ].join(' • ');
    }
    return [
      if (item.seriesName?.isNotEmpty ?? false) item.seriesName!,
      ?numberLabel,
    ].join(' • ');
  }

  final metadata = AggregatedItem.fromOffline(item);
  return [
    if (metadata.productionYear != null) '${metadata.productionYear}',
    if (metadata.officialRating?.isNotEmpty ?? false) metadata.officialRating!,
    ?savedMediaTypeLabel(l10n, item.type),
  ].join(' • ');
}

/// Kos TV: a saved item's type in the app's language, rather than the
/// server's type name; null for a type with no label.
String? savedMediaTypeLabel(AppLocalizations l10n, String type) =>
    switch (type) {
      'Movie' => l10n.movie,
      'Episode' => l10n.episode,
      'Audio' => l10n.kostvSavedTypeSong,
      'AudioBook' => l10n.kostvSavedTypeAudiobook,
      'Book' => l10n.kostvSavedTypeBook,
      'MusicVideo' => l10n.kostvSavedTypeMusicVideo,
      'Video' => l10n.video,
      _ => null,
    };

/// The line under a saved show's title: how much of it is actually here, which
/// a list of episode names never answered.
String savedShowSubtitle(AppLocalizations l10n, DownloadGroup group) {
  final metadata = AggregatedItem.fromOffline(group.first);
  return [
    if (metadata.productionYear != null) '${metadata.productionYear}',
    l10n.episodeCount(group.items.length),
  ].join(' • ');
}

IconData savedMediaFallbackIcon(String type) => switch (type) {
  'Audio' || 'AudioBook' => Icons.music_note_outlined,
  'Book' => Icons.menu_book_outlined,
  'Episode' => Icons.live_tv_outlined,
  _ => Icons.movie_outlined,
};

/// A book opens a reader rather than a player, so it never offers Play.
bool savedMediaIsPlayable(DownloadedItem item) => item.type != 'Book';

/// Closes the downloads panel, which lives on the root navigator.
void closeDownloadsPanel(BuildContext context) {
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  if (rootNavigator.canPop()) rootNavigator.pop();
}

/// Opens the item with autoplay rather than starting playback here, so the
/// detail screen still decides the resume position and the track selection,
/// and playback stays local first and picks up the downloaded copy.
void openSavedItem(
  BuildContext context,
  DownloadedItem item, {
  bool autoPlay = true,
}) {
  closeDownloadsPanel(context);
  context.navigateTopLevel(
    Destinations.item(item.itemId, serverId: item.serverId, autoPlay: autoPlay),
  );
}

/// Asks before removing files, then deletes them through the download service
/// so staging files and empty season folders are cleaned up too.
Future<bool> deleteSavedItems(
  BuildContext context, {
  required String title,
  required String message,
  required List<String> itemIds,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showFocusRestoringDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog.adaptive(
      title: Text(title),
      content: Text(message),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(
            foregroundColor: AppColorScheme.statusRequested,
          ),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final repo = GetIt.instance<OfflineRepository>();
  final downloadService = GetIt.instance<DownloadService>();
  var allDeleted = true;
  for (final itemId in itemIds) {
    final row = await repo.getItem(itemId);
    if (row == null) continue;
    final deleted = await downloadService.deleteDownloadedFiles(
      AggregatedItem.fromOffline(row),
    );
    if (!deleted) allDeleted = false;
  }
  // Kos TV: a file that could not go keeps its row, so say so rather than
  // leave it in the list without a word.
  if (!allDeleted && context.mounted) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(l10n.failedToDeleteFiles)));
  }
  return true;
}
