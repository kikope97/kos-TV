import 'package:get_it/get_it.dart';

import '../../data/services/saved_media_presence.dart';
import '../../preference/user_preferences.dart';
import '../../util/download_utils.dart';
import '../../util/platform_detection.dart';

/// Downloads in the menu (Kos TV: in «Más» and «Tú»): offered where
/// downloads make sense and the person left the button on, shown only while
/// something is saved, so the menu never offers a way into an empty screen.
abstract final class DownloadsNavSlot {
  /// Whether the entry could ever show here.
  static bool isOffered() =>
      GetIt.instance<UserPreferences>().get(
        UserPreferences.showDownloadsButton,
      ) &&
      isSupported();

  /// Whether this device keeps downloads at all.
  static bool isSupported() =>
      PlatformDetection.supportsOfflineDownloads && !PlatformDetection.isWeb;

  /// Whether this device and the signed in user can download at all.
  static bool isAvailable() => !PlatformDetection.isWeb && userCanDownload();

  /// Whether there is anything saved to show right now.
  static bool hasSavedMedia() {
    if (!GetIt.instance.isRegistered<SavedMediaPresence>()) return false;
    return GetIt.instance<SavedMediaPresence>().hasSavedMedia;
  }
}
