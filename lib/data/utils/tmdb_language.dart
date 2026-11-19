import 'dart:ui';

import '../../l10n/current_app_localizations.dart';

/// Kos TV: the language TMDB is asked in, which is the app's own. TMDB wants a
/// region with it and answers in English when none is given, so a bare
/// language gets the region the family uses (Spanish from Spain).
String tmdbLanguage([Locale? locale]) {
  final resolved = locale ?? currentAppLocale();
  final country = resolved.countryCode;
  if (country != null && country.isNotEmpty) {
    return '${resolved.languageCode}-$country';
  }
  return switch (resolved.languageCode) {
    'es' => 'es-ES',
    'en' => 'en-US',
    final code => code,
  };
}
