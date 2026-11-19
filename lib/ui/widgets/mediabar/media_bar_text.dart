import '../../../data/models/media_bar_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../util/error_message.dart';

/// Kos TV: a title's length as every layout of the banner shows it, the
/// same as its page does: «1 h 45 min», or «45 min» under an hour.
String mediaBarRuntime(Duration runtime, AppLocalizations l10n) =>
    runtime.inHours > 0
    ? l10n.kostvHeroRuntime(runtime.inHours, runtime.inMinutes.remainder(60))
    : l10n.durationMinutes(runtime.inMinutes);

/// Kos TV: what went wrong loading the banner, in the person's language.
String describeMediaBarError(Object error, AppLocalizations l10n) =>
    error is MediaBarNoBackdrops
    ? l10n.mediaBarNoBackdrops
    : describeError(error, l10n);
