import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:server_core/server_core.dart';

import '../../auth/repositories/server_repository.dart';
import '../../auth/repositories/server_user_repository.dart';
import '../../auth/repositories/session_repository.dart';
import '../../auth/store/authentication_preferences.dart';
import '../../data/services/kostv_password_check.dart';
import '../../data/services/media_server_client_factory.dart';
import '../../data/services/pin_guard.dart';
import '../../data/services/server_pin_service.dart';
import '../../l10n/app_localizations.dart';
import '../../preference/user_preferences.dart';
import '../../util/pin_code_util.dart';
import 'kostv_pin_recovery_dialog.dart';
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
  final passed = await _askDevicePin(
    context,
    pin,
    userId: userId,
    kidsMode: true,
  );
  if (passed) _grantKidsModeExit(userId);
  return passed;
}

/// Kos TV: a PIN kept on the device (Kids Mode, Parental controls), asked
/// with its wait after wrong guesses. Typed right, the wrong guesses before it are forgotten, so the child's tries
/// don't keep costing the parent a wait.
///
/// Forgotten, the Jellyfin password of [userId]'s account is the way out
/// ([_recoverDevicePin]): it removes the PIN and lets through, and for the
/// Kids Mode PIN ([kidsMode]) also leaves the mode, as the PIN would in
/// Settings. Without the account stored here there is no such way.
Future<bool> _askDevicePin(
  BuildContext context,
  PinCodeUtil pin, {
  required String userId,
  required bool kidsMode,
}) async {
  final account = _pinAccount(userId);
  var forgot = false;
  final passed = await PinEntryDialog.show(
    context,
    mode: PinEntryMode.verify,
    onVerify: pin.verifyPin,
    onFailedAttempt: pin.registerFailedAttempt,
    lockoutRemaining: () => pin.lockoutRemaining,
    onForgotPin: account == null ? null : () => forgot = true,
  );
  if (passed) {
    await pin.clearFailedAttempts();
    return true;
  }
  if (!forgot || account == null || !context.mounted) return false;
  return _recoverDevicePin(context, pin, account, kidsMode: kidsMode);
}

/// Kos TV: the Jellyfin account [userId] is on this device, for the way out
/// of a forgotten PIN: the server's address, the id and the name it signs in
/// with. Null when it isn't stored here, or isn't on a Jellyfin server.
({String baseUrl, String userId, String name})? _pinAccount(String userId) {
  final getIt = GetIt.instance;
  if (userId.isEmpty ||
      !getIt.isRegistered<ServerRepository>() ||
      !getIt.isRegistered<ServerUserRepository>()) {
    return null;
  }
  var serverId = '';
  if (getIt.isRegistered<SessionRepository>()) {
    final session = getIt<SessionRepository>();
    if (session.activeUserId == userId) serverId = session.activeServerId ?? '';
  }
  if (serverId.isEmpty && getIt.isRegistered<AuthenticationPreferences>()) {
    final authPrefs = getIt<AuthenticationPreferences>();
    if (authPrefs.savedLastUserId.trim() == userId) {
      serverId = authPrefs.savedLastServerId.trim();
    }
  }
  if (serverId.isEmpty) return null;
  final server = getIt<ServerRepository>().getServer(serverId);
  if (server == null || server.serverType != ServerType.jellyfin) return null;
  final user = getIt<ServerUserRepository>()
      .getStoredServerUsers(serverId)
      .where((stored) => stored.id == userId)
      .firstOrNull;
  if (user == null || user.name.isEmpty) return null;
  // The address the session settled on, which may not be the stored one.
  final client = getIt.isRegistered<MediaServerClientFactory>()
      ? getIt<MediaServerClientFactory>().getClientIfExists(serverId)
      : null;
  return (
    baseUrl: client?.baseUrl ?? server.address,
    userId: userId,
    name: user.name,
  );
}

/// Kos TV: asks for the Jellyfin password of [account] in place of a
/// forgotten [pin] and, once the server accepts it, removes the PIN (and,
/// for [kidsMode], leaves the mode). A wrong password counts as a wrong
/// guess at the PIN, with the same wait; without the server there is no way
/// to tell, so it says so.
Future<bool> _recoverDevicePin(
  BuildContext context,
  PinCodeUtil pin,
  ({String baseUrl, String userId, String name}) account, {
  required bool kidsMode,
}) async {
  final getIt = GetIt.instance;
  final KostvPasswordCheck checker;
  final ownChecker = !getIt.isRegistered<KostvPasswordCheck>();
  if (!ownChecker) {
    checker = getIt<KostvPasswordCheck>();
  } else if (getIt.isRegistered<DeviceInfo>()) {
    checker = KostvPasswordCheck(deviceInfo: getIt<DeviceInfo>());
  } else {
    return false;
  }
  final l10n = AppLocalizations.of(context);
  try {
    return await KostvPinRecoveryDialog.show(
      context,
      username: account.name,
      leavesKidsMode: kidsMode,
      onSubmit: (password) async {
        final locked = pin.lockoutRemaining;
        if (locked > Duration.zero) {
          return l10n.pinTryAgainIn(PinEntryDialog.formatWait(locked));
        }
        final verdict = await checker.check(
          baseUrl: account.baseUrl,
          userId: account.userId,
          username: account.name,
          password: password,
        );
        switch (verdict) {
          case KostvPasswordVerdict.accepted:
            if (kidsMode && getIt.isRegistered<UserPreferences>()) {
              await getIt<UserPreferences>().set(
                UserPreferences.kidsModeEnabled,
                false,
              );
            }
            await pin.removePin();
            return null;
          case KostvPasswordVerdict.wrong:
            final wait = await pin.registerFailedAttempt();
            return wait > Duration.zero
                ? l10n.pinTryAgainIn(PinEntryDialog.formatWait(wait))
                : l10n.kostvPinRecoveryWrong;
          case KostvPasswordVerdict.unreachable:
            return l10n.kostvPinRecoveryNeedsServer;
        }
      },
    );
  } finally {
    if (ownChecker) checker.close();
  }
}

/// Kos TV: asks for the Kids Mode [pin] of [userId] before the mode is left
/// in Settings, with the way out of a forgotten one (which leaves the mode
/// itself).
Future<bool> kostvAskKidsModePin(
  BuildContext context,
  PinCodeUtil pin, {
  required String userId,
}) => _askDevicePin(context, pin, userId: userId, kidsMode: true);

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
  return _askDevicePin(context, pin, userId: holder, kidsMode: true);
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

/// Kos TV: the Parental controls PIN of whoever is signed in, kept on this
/// device as the ratings filter it guards is. Null with nobody signed in.
PinCodeUtil? kostvParentalPin() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<PreferenceStore>()) return null;
  final userId = getIt.isRegistered<SessionRepository>()
      ? getIt<SessionRepository>().activeUserId ?? ''
      : '';
  if (userId.isEmpty) return null;
  return PinCodeUtil.parental(getIt<PreferenceStore>(), userId);
}

/// Kos TV: asks for [pin], the Parental controls PIN of whoever is signed
/// in, with its wait after wrong guesses and the way out of a forgotten one
/// (which removes it).
Future<bool> kostvAskDevicePin(BuildContext context, PinCodeUtil pin) =>
    _askDevicePin(context, pin, userId: _activeUserId(), kidsMode: false);

String _activeUserId() {
  final getIt = GetIt.instance;
  return getIt.isRegistered<SessionRepository>()
      ? getIt<SessionRepository>().activeUserId ?? ''
      : '';
}

/// Kos TV: what opens Parental controls asks first for their own PIN, when
/// one is set, which whoever uses the profile needn't know. Without one it
/// asks for the account's PIN, as before ([kostvAccountPinLetsIn]).
Future<bool> kostvParentalControlsLetIn(BuildContext context) async {
  final pin = kostvParentalPin();
  if (pin == null || !pin.isPinEnabled) return kostvAccountPinLetsIn(context);
  return kostvAskDevicePin(context, pin);
}
