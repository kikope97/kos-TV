import '../data/models/aggregated_item.dart';
import '../data/services/stremfin/kostv_stream_song.dart';
import '../l10n/app_localizations.dart';
import '../l10n/current_app_localizations.dart';

/// Kos TV: the artist line of [item] for the system's media controls (the
/// phone's notification and lock screen, Android Auto, the browser's Media
/// Session): «Los Faroleros · en streaming» for a song that isn't at home,
/// [artist] as it is for one at home. In the app's language ([l10n], or the
/// one picked in its settings).
String? kostvStreamArtistLine(
  AggregatedItem item,
  String? artist, [
  AppLocalizations? l10n,
]) {
  if (!isKostvStream(item)) return artist;
  final words = l10n ?? currentAppLocalizations();
  return kostvStreamMarkedArtist(
    item,
    artist,
    withArtist: words.kostvStreamArtistLine,
    alone: words.kostvStreamOnlyLine,
  );
}
