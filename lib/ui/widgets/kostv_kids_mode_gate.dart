import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../../auth/repositories/server_repository.dart';
import '../../auth/repositories/server_user_repository.dart';
import '../../auth/repositories/session_repository.dart';
import '../../data/services/pin_guard.dart';
import '../../data/services/server_pin_service.dart';
import '../../preference/user_preferences.dart';
import '../../util/pin_code_util.dart';
import 'pin_entry_dialog.dart';

/// Kos TV: in Kids Mode, whatever would take the child out of their profile
/// (another account, signing out, adding a user) asks first for the mode's
/// PIN, the same as leaving the mode in Settings. Outside Kids Mode it lets
/// through.
Future<bool> kostvKidsModeLetsOut(BuildContext context) async {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<UserPreferences>() ||
      !getIt<UserPreferences>().get(UserPreferences.kidsModeEnabled)) {
    return true;
  }
  final userId = getIt.isRegistered<SessionRepository>()
      ? getIt<SessionRepository>().activeUserId ?? ''
      : '';
  final pin = PinCodeUtil.kidsMode(getIt<PreferenceStore>(), userId);
  // As leaving the mode does: without a PIN there is nothing to ask.
  if (!pin.isPinEnabled) return true;
  return PinEntryDialog.show(
    context,
    mode: PinEntryMode.verify,
    onVerify: pin.verifyPin,
    onFailedAttempt: pin.registerFailedAttempt,
    lockoutRemaining: () => pin.lockoutRemaining,
  );
}

/// Kos TV: what changes the limits of whoever is signed in (Parental
/// controls) asks first for their account's PIN, when it has one, so someone
/// with an age limit can't lift it from their own profile. Without a PIN it
/// lets through, as before.
Future<bool> kostvAccountPinLetsIn(BuildContext context) async {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<SessionRepository>() ||
      !getIt.isRegistered<PreferenceStore>() ||
      !getIt.isRegistered<ServerPinService>()) {
    return true;
  }
  final session = getIt<SessionRepository>();
  final userId = session.activeUserId ?? '';
  if (userId.isEmpty) return true;
  final serverId = session.activeServerId;
  final guard = PinGuard.forAccount(
    store: getIt<PreferenceStore>(),
    service: getIt<ServerPinService>(),
    userId: userId,
    server: serverId == null || !getIt.isRegistered<ServerRepository>()
        ? null
        : getIt<ServerRepository>().getServer(serverId),
    accessToken: serverId == null || !getIt.isRegistered<ServerUserRepository>()
        ? null
        : getIt<ServerUserRepository>()
              .getStoredServerUsers(serverId)
              .where((stored) => stored.id == userId)
              .map((stored) => stored.accessToken)
              .firstOrNull,
  );
  // Set or removed on another device since: the server knows.
  try {
    await guard.refresh();
  } catch (_) {}
  if (!guard.pin.isPinEnabled) return true;
  if (!context.mounted) return false;
  return PinEntryDialog.show(
    context,
    mode: PinEntryMode.verify,
    onVerifyAsync: guard.verify,
  );
}
