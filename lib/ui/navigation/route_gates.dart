import 'package:get_it/get_it.dart';

import '../../data/services/connectivity_service.dart';
import '../../data/services/installed_apps_service.dart';
import '../../preference/user_preferences.dart';
import 'destinations.dart';

/// Kos TV: the gates the router's redirect applies, kept apart so the menu
/// and the Kids Mode switch can ask them too.

/// Whether Kids Mode keeps [path] out of reach. Hiding a nav entry is
/// presentation, but a deep link (or an address typed on the web) reaches
/// these screens without one.
bool kidsModeBlocksPath(String path) =>
    path.startsWith('/admin') ||
    path.startsWith('/live-tv') ||
    // Kos TV: Discover and asking for titles are hidden in Kids Mode. Music
    // too: it asks for albums and plays the charts' previews.
    path.startsWith(Destinations.kostvDiscover) ||
    path.startsWith(Destinations.kostvMusic) ||
    // Kos TV: the calendar lists every upcoming title, unfiltered.
    path.startsWith(Destinations.calendar) ||
    // Kos TV: book Discover (Open Library, LibriVox) is outside catalogs no
    // parental rating reaches. The games stay; their RomM account doesn't.
    _bookDiscoverPath.hasMatch(path) ||
    path.startsWith(Destinations.rommAccount);

/// A book library's Discover, `/books/<library>/discover`.
final _bookDiscoverPath = RegExp(r'^/books/[^/]+/discover/?$');

/// Surfaces that genuinely need the server. Everything else works offline
/// against the downloads catalog.
bool offlineBlocksPath(String path) =>
    path.startsWith('/live-tv') ||
    path.startsWith('/admin') ||
    path.startsWith('/games');

/// Whether a page at [path] may not stay open in Kids Mode: the pages
/// [kidsModeBlocksPath] covers, and the TV's apps.
bool kidsModeClosesPath(String path) =>
    kidsModeBlocksPath(path) || path == Destinations.apps;

/// Whether the router would send [path] elsewhere right now, for one of the
/// menu's pages: Kids Mode, no server to reach, or no TV apps to list.
/// Navigating to it would only land on another Home.
bool menuPageDivertedNow(String path) {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<UserPreferences>() &&
      getIt<UserPreferences>().get(UserPreferences.kidsModeEnabled) &&
      kidsModeBlocksPath(path)) {
    return true;
  }
  if (getIt.isRegistered<ConnectivityService>() &&
      !getIt<ConnectivityService>().canReachServer &&
      offlineBlocksPath(path)) {
    return true;
  }
  if (path == Destinations.apps && !kostvAppsAvailable()) return true;
  return false;
}

/// The screens before Home: signing in, picking the server, setting up.
const _beforeHome = <String>{
  Destinations.startup,
  Destinations.serverSelect,
  Destinations.webDiagnostics,
  Destinations.server,
  Destinations.login,
  Destinations.setup,
};

/// Whether Back on the web, with nothing under the page on screen at
/// [path], takes the person to Home: from any page once signed in, as on a
/// TV or a phone; never on Home itself, nor before Home.
bool webBackGoesHome(String path, {required bool signedIn}) =>
    signedIn &&
    path.isNotEmpty &&
    path != Destinations.home &&
    !_beforeHome.contains(path);
