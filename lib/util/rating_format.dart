import 'package:intl/intl.dart';

import '../l10n/current_app_localizations.dart';

/// Kos TV: a rating with one decimal in the app's language, «7,1» in
/// Spanish and «7.1» in English. [localeName] defaults to the language the
/// app is shown in; pass `AppLocalizations.localeName` when a context is at
/// hand.
String formatRatingValue(num value, [String? localeName]) => NumberFormat(
  '0.0',
  localeName ?? currentAppLocalizations().localeName,
).format(value);
