import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../../auth/repositories/session_repository.dart';
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
