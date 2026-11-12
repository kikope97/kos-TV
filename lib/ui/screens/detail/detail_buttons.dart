import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/services/incomplete_recordings_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/button_layout.dart';
import '../../../preference/user_preferences.dart';
import '../../../syncplay/syncplay_manager.dart';
import '../../../watch_party/silo_watch_party_manager.dart';
import '../../../util/platform_detection.dart';
import '../../../util/signed_in_server_features.dart';
import '../../widgets/live_tv/incomplete_recording.dart';

/// The details screen action buttons a user can arrange. Play is absent on
/// purpose, it always leads the row because it renders as the primary button
/// and anchors the focus the screen hands out.
///
/// Ids are what gets stored, so renaming one drops whatever the user had
/// arranged for it.
enum DetailButton {
  shuffle('shuffle'),
  restart('restart', canHide: false),
  audio('audio'),
  subtitles('subtitles'),
  version('version'),
  cast('cast'),
  trailer('trailer'),
  // Kos TV: the person's list.
  myList('myList'),
  watchWithGroup('watchWithGroup'),
  watched('watched'),
  favorite('favorite'),
  personalRating('personalRating'),
  playlist('playlist'),
  download('download'),
  deleteFiles('deleteFiles'),
  goToSeries('goToSeries'),
  keepAsComplete('keepAsComplete'),
  admin('admin');

  const DetailButton(this.id, {this.canHide = true});

  final String id;

  /// A button the row always keeps. It still moves, it just has no switch.
  final bool canHide;

  /// Whether this device can put the button on screen at all. A button that
  /// never gets drawn here isn't worth offering a switch for.
  bool get isOffered {
    if (_kidsModeOn && !_kidsModeAllowed.contains(this)) {
      return false;
    }
    return switch (this) {
      DetailButton.cast => !PlatformDetection.isTV,
      DetailButton.download ||
      DetailButton.deleteFiles => PlatformDetection.supportsOfflineDownloads,
      DetailButton.watchWithGroup => _syncPlayAvailable,
      DetailButton.keepAsComplete =>
        _incompleteRecordingsSupported && canManageLiveTv(),
      // Not when no signed-in server has playlists (all Silo, say).
      DetailButton.playlist => playlistsOnAnySignedInServer(),
      DetailButton.myList => _myListAvailable,
      _ => true,
    };
  }

  /// The only buttons Kids Mode offers, alongside Play.
  ///
  /// An allow list rather than a block list, so a button added later stays out
  /// until someone decides a child should have it. Keeping the row short is
  /// half the point: anything that doesn't fit folds into an overflow menu,
  /// which hands back everything the mode meant to put away.
  static const _kidsModeAllowed = <DetailButton>{
    DetailButton.restart,
    DetailButton.shuffle,
    DetailButton.favorite,
  };

  /// The order Kids Mode puts them in. The saved arrangement belongs to the
  /// parent and is one of the things the mode sets aside, so the allow list's
  /// own order is the order.
  static List<DetailButton> get kidsModeOrder => _kidsModeAllowed.toList();

  /// Defensive like [_syncPlayAvailable], because [isOffered] is reached from
  /// widgets that can build before the preferences are registered. No
  /// preferences means no Kids Mode to be in.
  static bool get _kidsModeOn {
    try {
      if (!GetIt.instance.isRegistered<UserPreferences>()) return false;
      return GetIt.instance<UserPreferences>().get(
        UserPreferences.kidsModeEnabled,
      );
    } catch (_) {
      return false;
    }
  }

  /// Only the Moonfin plugin's Jellyfin build can mark recordings incomplete.
  static bool get _incompleteRecordingsSupported {
    try {
      return GetIt.instance.isRegistered<IncompleteRecordingsService>() &&
          GetIt.instance<IncompleteRecordingsService>().supported;
    } catch (_) {
      return false;
    }
  }

  /// Kos TV: whether the server plugin keeps lists.
  static bool get _myListAvailable {
    try {
      return GetIt.instance.isRegistered<UserPreferences>() &&
          GetIt.instance<UserPreferences>().get(
            UserPreferences.kostvMyListAvailable,
          );
    } catch (_) {
      return false;
    }
  }

  static bool get _syncPlayAvailable {
    try {
      if (GetIt.instance.isRegistered<SyncPlayManager>()) {
        final syncPlay = GetIt.instance<SyncPlayManager>();
        // Silo and Moonbase have their own rooms, under the same switch.
        final party = GetIt.instance<SiloWatchPartyManager>();
        return syncPlay.syncPlayEnabled ||
            (syncPlay.syncPlayConfigured &&
                (party.activeSiloClient != null || party.moonbaseAvailable));
      }
      return GetIt.instance<UserPreferences>().get(UserPreferences.syncPlayEnabled);
    } catch (_) {
      return false;
    }
  }

  IconData get icon => switch (this) {
    DetailButton.shuffle => Icons.shuffle_rounded,
    DetailButton.restart => Icons.restart_alt,
    DetailButton.audio => Icons.audiotrack,
    DetailButton.subtitles => Icons.subtitles,
    DetailButton.version => Icons.video_file,
    DetailButton.cast => Icons.cast,
    DetailButton.trailer => Icons.movie_outlined,
    DetailButton.myList => Icons.bookmark_add_outlined,
    DetailButton.watchWithGroup => Icons.groups_rounded,
    DetailButton.watched => Icons.check_circle_outline,
    DetailButton.favorite => Icons.favorite_border,
    DetailButton.personalRating => Icons.star_outline,
    DetailButton.playlist => Icons.playlist_add,
    DetailButton.download => Icons.download_for_offline,
    DetailButton.deleteFiles => Icons.delete_outline,
    DetailButton.goToSeries => Icons.tv,
    DetailButton.keepAsComplete => Icons.task_alt,
    DetailButton.admin => Icons.settings,
  };

  String label(AppLocalizations l10n) => switch (this) {
    DetailButton.shuffle => l10n.shuffle,
    DetailButton.restart => l10n.restart,
    DetailButton.audio => l10n.audio,
    DetailButton.subtitles => l10n.subtitles,
    DetailButton.version => l10n.version,
    DetailButton.cast => l10n.cast,
    DetailButton.trailer => l10n.trailer,
    DetailButton.myList => l10n.kostvMyList,
    DetailButton.watchWithGroup => l10n.watchWithGroup,
    DetailButton.watched => l10n.watched,
    DetailButton.favorite => l10n.favorite,
    DetailButton.personalRating => l10n.rate,
    DetailButton.playlist => l10n.addToPlaylist,
    DetailButton.download => l10n.download,
    DetailButton.deleteFiles => l10n.deleteDownloadedFiles,
    DetailButton.goToSeries => l10n.goToSeries,
    DetailButton.keepAsComplete => l10n.keepAsComplete,
    DetailButton.admin => l10n.admin,
  };
}

final detailButtonLayout = ButtonLayout(
  hiddenTv: UserPreferences.hiddenDetailButtonsTv,
  hiddenMobile: UserPreferences.hiddenDetailButtonsMobile,
  hiddenDesktop: UserPreferences.hiddenDetailButtonsDesktop,
  orderTv: UserPreferences.detailButtonOrderTv,
  orderMobile: UserPreferences.detailButtonOrderMobile,
  orderDesktop: UserPreferences.detailButtonOrderDesktop,
);
