import 'package:get_it/get_it.dart';

import '../../data/services/stremfin/stremfin_service.dart';
import '../../preference/user_preferences.dart';

/// Kos TV: whether the signed-in person can have a requests tray: the
/// requests service lets them in, outside kids mode.
bool kostvRequestsTrayAvailable() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<StremfinService>()) return false;
  if (getIt.isRegistered<UserPreferences>() &&
      getIt<UserPreferences>().get(UserPreferences.kidsModeEnabled)) {
    return false;
  }
  return getIt<StremfinService>().isAllowed;
}
