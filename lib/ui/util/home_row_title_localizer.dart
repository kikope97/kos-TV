import '../../data/models/home_row.dart';
import '../../l10n/app_localizations.dart';
import '../../preference/preference_constants.dart';

/// The seasonal row is titled after the holiday Moonbase picked, which it names
/// by id.
String seasonalHolidayTitle(String holiday, AppLocalizations l10n) =>
    switch (holiday) {
      'newYear' => l10n.holidayNewYear,
      'valentines' => l10n.holidayValentines,
      'easter' => l10n.holidayEaster,
      'pride' => l10n.holidayPride,
      'halloween' => l10n.holidayHalloween,
      'thanksgiving' => l10n.holidayThanksgiving,
      'christmas' => l10n.holidayChristmas,
      'lunarNewYear' => l10n.holidayLunarNewYear,
      'diwali' => l10n.holidayDiwali,
      _ => l10n.seasonalRow,
    };

String localizeHomeRowTitle({
  required HomeRow row,
  required AppLocalizations l10n,
  bool mergeContinueWatchingAndNextUp = false,
}) {
  switch (row.id) {
    case 'resume':
      return mergeContinueWatchingAndNextUp
          ? l10n.continueWatchingAndNextUp
          : l10n.continueWatching;
    case 'resumeAudio':
      return l10n.continueListening;
    case 'nextUp':
      return l10n.nextUp;
    case 'latestMedia':
      return l10n.latestMedia;
    case 'playlists':
      return l10n.playlists;
    case 'audioPlaylists':
      return l10n.audioPlaylists;
    case 'audioArtists':
      return l10n.artists;
    case 'audioAlbums':
      return l10n.albums;
    case 'collections':
      return l10n.collections;
    case 'genres':
      return l10n.genres;
    case 'libraryTiles':
    case 'libraryTilesSmall':
      return l10n.myMedia;
    case 'liveTv':
      return l10n.liveTv;
    case 'onNow':
    case 'liveTvOnNow':
      return l10n.onNow;
    case 'liveTvFavorites':
      return l10n.favoriteChannels;
    case 'activeRecordings':
      return l10n.activeRecordings;
    case 'radarr_calendar':
      return l10n.radarrCalendarRow;
    case 'sonarr_calendar':
      return l10n.sonarrCalendarRow;
    case 'merged_calendar':
      return l10n.mergedCalendarRow;
    case 'rewatch':
      return 'Rewatch';
    case 'mdblist_watching_now':
      return l10n.mdblistWatchingNow;
  }

  if (row.id.startsWith('resume_')) return l10n.continueWatching;
  if (row.id.startsWith('nextUp_')) return l10n.nextUp;
  if (row.id.startsWith('lastPlayed_')) return l10n.lastPlayed;
  if (row.id.startsWith('albumartist_')) return l10n.albumArtists;
  if (row.id.startsWith('musicartist_')) return l10n.artists;
  if (row.id.startsWith('musicalbum_')) return l10n.albums;
  if (row.id.startsWith('latestBooks_')) return l10n.latestBooks;
  if (row.id.startsWith('latestAudiobooks_')) return l10n.latestAudiobooks;
  if (row.id.startsWith('latestComics_')) return l10n.latestComics;

  if (row.id.startsWith('latest_')) {
    return _localizeLatestRowTitle(row.title, l10n);
  }

  if (row.id.startsWith('sinceYouWatched')) {
    return _localizeSinceYouWatchedTitle(row.title, l10n);
  }

  if (row.id.startsWith('imdb_')) {
    return row.title.replaceAll('IMDb ', '').replaceAll('IMDb', '').trim();
  }
  return row.title;
}

/// The data layer has no localizations, so it titles the row in English with the
/// watched item in quotes, and the item is read back out here.
String _localizeSinceYouWatchedTitle(String title, AppLocalizations l10n) {
  const itemPrefix = 'Since you watched "';
  if (title.startsWith(itemPrefix) && title.endsWith('"')) {
    return l10n.sinceYouWatchedItemRowTitle(
      title.substring(itemPrefix.length, title.length - 1),
    );
  }
  return l10n.sinceYouWatchedRowTitle;
}

String _localizeLatestRowTitle(String title, AppLocalizations l10n) {
  const latestPrefix = 'Latest ';
  if (!title.startsWith(latestPrefix)) return title;
  final libraryName = title.substring(latestPrefix.length);
  return l10n.latestLibraryName(libraryName);
}
