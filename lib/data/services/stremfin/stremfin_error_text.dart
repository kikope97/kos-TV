import '../../../l10n/app_localizations.dart';
import 'stremfin_client.dart';

/// Kos TV: what to tell the person when the requests service said no, by
/// its error code, in the app's language (the service's own words come only
/// in Spanish). [fallback] for anything else, as each screen words it.
String kostvStremfinErrorText(
  AppLocalizations l10n,
  Object error, {
  required String fallback,
}) {
  if (error is! StremfinException) return fallback;
  switch (error.code) {
    case 'unauthenticated' || 'invalid_token':
      return l10n.kostvStremfinErrorSession;
    case 'not_linked':
      return l10n.kostvStremfinErrorNotLinked;
    case 'no_access':
      return l10n.kostvStremfinErrorNoAccess;
    case 'not_yours':
      return l10n.kostvStremfinErrorNotYours;
    case 'not_found':
      return l10n.kostvStremfinErrorNotFound;
    case 'already_answered':
      return l10n.kostvStremfinErrorAlreadyAnswered;
    case 'api_disabled':
      return l10n.kostvStremfinErrorDisabled;
    case 'jellyfin_not_configured':
      return l10n.kostvStremfinErrorNotConnected;
    case 'jellyfin_unavailable':
      return l10n.kostvStremfinErrorServerUnavailable;
    case 'source_unavailable':
      return l10n.kostvStremfinErrorSourceUnavailable;
    case 'busy':
      return l10n.kostvStremfinErrorBusy;
    case 'server_error':
      return l10n.kostvStremfinErrorServerError;
    case 'network':
      return l10n.kostvStremfinErrorUnreachable;
  }
  // Too many at once (too_many_requests, too_many_attempts): wait a moment.
  if (error.status == 429) return l10n.kostvRequestTooFast;
  return fallback;
}
