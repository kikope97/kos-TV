import 'user_preferences.dart';

/// Destinations of the menu that can sit between Home and You on the phone's
/// glass bar, or be reached from «Tú» and «Más».
enum BottomNavTab {
  search,

  /// Kos TV: what's on the streaming platforms (the requests service).
  kostvDiscover,
  libraries,
  favorites,

  /// Kos TV: the person's list, kept by the server plugin.
  myList,
  genres,
  liveTv,
  calendar,

  /// Kos TV: Music, the page of its own.
  kostvMusic,
}

/// Kos TV: how many tabs the glass bar shows between Home and You. Search
/// has its own round button beside the bar.
const int kBottomBarTabs = 2;

/// Kos TV: the bar's tabs, in the order they are taken: Descubrir and Música
/// (the approved design: Inicio · Descubrir · Música · Tú). Where one of
/// them is not offered (Kids Mode, a switch turned off, no requests service)
/// the next destination on offer takes its place, so the bar always has its
/// tabs. Favorites is never on the bar, only in «Tú».
const List<BottomNavTab> _barOrder = [
  BottomNavTab.kostvDiscover,
  BottomNavTab.kostvMusic,
  BottomNavTab.libraries,
  BottomNavTab.myList,
  BottomNavTab.liveTv,
  BottomNavTab.genres,
  BottomNavTab.calendar,
];

/// The settings that decide whether a [BottomNavTab] is on offer at all. Only
/// preferences and plugin state feed it, never loaded data, so the tabs don't
/// shift while libraries are still loading.
class BottomNavTabGates {
  final bool kidsMode;
  final bool showLibraries;
  final bool showFavorites;
  final bool showGenres;
  final bool showLiveTv;
  final bool showCalendar;
  final bool calendarAvailable;

  /// Kos TV: the Discover switch, and whether the requests service lets the
  /// signed-in person in.
  final bool showKostvDiscover;
  final bool kostvDiscoverAvailable;

  /// Kos TV: whether the server plugin keeps lists.
  final bool kostvMyListAvailable;

  /// Kos TV: the Music switch.
  final bool showKostvMusic;

  const BottomNavTabGates({
    this.kidsMode = false,
    this.showLibraries = true,
    this.showFavorites = true,
    this.showGenres = true,
    this.showLiveTv = false,
    this.showCalendar = true,
    this.calendarAvailable = false,
    this.showKostvDiscover = true,
    this.kostvDiscoverAvailable = false,
    this.kostvMyListAvailable = false,
    this.showKostvMusic = true,
  });

  factory BottomNavTabGates.fromPreferences(
    UserPreferences prefs, {
    bool calendarAvailable = false,
    bool kostvDiscoverAvailable = false,
  }) {
    return BottomNavTabGates(
      kidsMode: prefs.get(UserPreferences.kidsModeEnabled),
      showLibraries: prefs.get(UserPreferences.showLibrariesInToolbar),
      showFavorites: prefs.get(UserPreferences.showFavoritesButton),
      showGenres: prefs.get(UserPreferences.showGenresButton),
      showLiveTv: prefs.get(UserPreferences.showLiveTvButton),
      showCalendar: prefs.get(UserPreferences.showCalendarButton),
      calendarAvailable: calendarAvailable,
      showKostvDiscover: prefs.get(UserPreferences.showDiscoverButton),
      kostvDiscoverAvailable: kostvDiscoverAvailable,
      kostvMyListAvailable: prefs.get(UserPreferences.kostvMyListAvailable),
      showKostvMusic: prefs.get(UserPreferences.kostvShowMusicButton),
    );
  }

  // Kids Mode drops Libraries (the My Media row stands in), Live TV (its route
  // bounces home) and the calendar.
  bool offers(BottomNavTab tab) => switch (tab) {
        BottomNavTab.search => true,
        BottomNavTab.kostvDiscover =>
          !kidsMode && showKostvDiscover && kostvDiscoverAvailable,
        BottomNavTab.kostvMusic => !kidsMode && showKostvMusic,
        BottomNavTab.libraries => !kidsMode && showLibraries,
        // Kos TV: always there, in «Tú».
        BottomNavTab.favorites => true,
        BottomNavTab.myList => kostvMyListAvailable,
        BottomNavTab.genres => showGenres,
        BottomNavTab.liveTv => !kidsMode && showLiveTv,
        BottomNavTab.calendar => !kidsMode && showCalendar && calendarAvailable,
      };

  /// The tabs the glass bar shows between Home and You. [isAvailable] skips
  /// a destination whose data isn't there, like Libraries before any library
  /// has loaded, for the next one.
  List<BottomNavTab> barTabs({bool Function(BottomNavTab tab)? isAvailable}) =>
      _barOrder
          .where((t) => offers(t) && (isAvailable?.call(t) ?? true))
          .take(kBottomBarTabs)
          .toList();
}
