import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../../auth/repositories/server_repository.dart';
import '../../auth/repositories/server_user_repository.dart';
import '../../auth/repositories/session_repository.dart';
import '../../auth/store/authentication_preferences.dart';
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
  final passed = await _askKidsModePin(context, pin);
  if (passed) _grantKidsModeExit(userId);
  return passed;
}

/// Kos TV: the Kids Mode PIN, asked with its wait after wrong guesses. Typed
/// right, the wrong guesses before it are forgotten, so the child's tries
/// don't keep costing the parent a wait.
Future<bool> _askKidsModePin(BuildContext context, PinCodeUtil pin) async {
  final passed = await PinEntryDialog.show(
    context,
    mode: PinEntryMode.verify,
    onVerify: pin.verifyPin,
    onFailedAttempt: pin.registerFailedAttempt,
    lockoutRemaining: () => pin.lockoutRemaining,
  );
  if (passed) await pin.clearFailedAttempts();
  return passed;
}

/// Kos TV: who typed the Kids Mode PIN to leave, and when, so the user picker
/// opened right after doesn't ask for it again.
String? _exitGrantedTo;
Stopwatch? _exitGrantedSince;
const _exitGrantLasts = Duration(minutes: 2);

void _grantKidsModeExit(String userId) {
  _exitGrantedTo = userId;
  _exitGrantedSince = Stopwatch()..start();
}

/// Kos TV: takes the way out [kostvKidsModeLetsOut] just granted [userId], if
/// it was granted lately. Taken once: the next picker asks again.
bool kostvTakeKidsModeExit(String userId) {
  final since = _exitGrantedSince;
  final granted =
      _exitGrantedTo == userId &&
      since != null &&
      since.elapsed < _exitGrantLasts;
  _exitGrantedTo = null;
  _exitGrantedSince = null;
  return granted;
}

/// Kos TV: the profile in Kids Mode on this device, as the user picker sees
/// it: the one last signed in here, when it has the mode on. Null otherwise.
/// It stays the one in the mode until someone leaves it with the PIN, so the
/// picker can't be the way out (the "time's up" screen opens it, a web address
/// reaches it, and so does a start with automatic sign-in off).
String? kostvKidsModeHolder() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<UserPreferences>() ||
      !getIt.isRegistered<AuthenticationPreferences>() ||
      !getIt<UserPreferences>().get(UserPreferences.kidsModeEnabled)) {
    return null;
  }
  final userId = getIt<AuthenticationPreferences>().savedLastUserId.trim();
  return userId.isEmpty ? null : userId;
}

/// Kos TV: whether the user picker may take [pickedUserId] (or, without one,
/// a sign-in or server of someone's choosing) while [holder] is in Kids Mode
/// on this device. The child's own profile goes through; anyone else needs
/// the mode's PIN, as switching from the menu does. [granted] is the way out
/// already given by the PIN on the way to the picker.
Future<bool> kostvKidsModeLetsPick(
  BuildContext context, {
  required String? holder,
  String? pickedUserId,
  bool granted = false,
}) async {
  if (holder == null || granted || pickedUserId == holder) return true;
  final pin = PinCodeUtil.kidsMode(GetIt.instance<PreferenceStore>(), holder);
  // As leaving the mode does: without a PIN there is nothing to ask.
  if (!pin.isPinEnabled) return true;
  return _askKidsModePin(context, pin);
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
