import 'dart:ui';

import 'package:get_it/get_it.dart';

import '../preference/user_preferences.dart';
import 'app_localizations.dart';

/// The active [Locale] for code that runs without a [BuildContext].
/// Respects the user's language override in preferences, falling back
/// to the device locale resolved against supported locales.
Locale currentAppLocale([Locale? deviceLocale]) =>
    _overrideLocale() ?? _resolveSupportedLocale(deviceLocale ?? PlatformDispatcher.instance.locale);

/// Kos TV: the language a device falls back to when its own is neither
/// Spanish nor English.
const kostvFallbackLocale = Locale('es');

/// The locale MaterialApp runs in.
Locale resolveAppUiLocale(Locale? target) =>
    _resolveSupportedLocale(target ?? kostvFallbackLocale);

/// Matches the way Flutter resolves the app locale: exact, then language
/// alone (a Mexican or Argentinian device gets Spanish), then Spanish.
Locale _resolveSupportedLocale(Locale target) {
  const supported = AppLocalizations.supportedLocales;
  return supported.where((l) => l == target).firstOrNull ??
      supported
          .where((l) => l.languageCode == target.languageCode)
          .firstOrNull ??
      kostvFallbackLocale;
}

/// Localizations for code that runs without a [BuildContext]. The language
/// override wins over the device language, the same way MaterialApp resolves
/// it, so these strings read in the language the user picked rather than the
/// one the OS is set to.
AppLocalizations currentAppLocalizations() {
  final locale = currentAppLocale();
  try {
    return lookupAppLocalizations(locale);
  } catch (_) {
    return lookupAppLocalizations(kostvFallbackLocale);
  }
}

Locale? _overrideLocale() {
  final String override;
  try {
    override = GetIt.instance<UserPreferences>().get(
      UserPreferences.languageOverride,
    );
  } catch (_) {
    return null;
  }
  if (override == 'system') return null;

  for (final locale in AppLocalizations.supportedLocales) {
    if (locale.toLanguageTag() == override || locale.toString() == override) {
      return locale;
    }
  }
  return null;
}
