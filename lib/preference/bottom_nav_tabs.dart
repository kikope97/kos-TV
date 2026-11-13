import 'user_preferences.dart';

/// Destinations that can be pinned between Home and You on the mobile bottom
/// navbar. The names are the wire format of [UserPreferences.bottomNavbarTabs],
/// so renaming one breaks every synced profile that holds it.
enum BottomNavTab {
  search,

  /// Kos TV: what's on the streaming platforms (the requests service).
  kostvDiscover,

  /// Kos TV: Music, the page of its own.
  kostvMusic,
  libraries,
  favorites,

  /// Kos TV: the person's list, kept by the server plugin.
  myList,
  genres,
  liveTv,
  calendar,
}

const int kMaxPinnedBottomNavTabs = 3;

// Libraries sits second so a user on default settings keeps it on the bar.
// Kos TV: Discover goes before it, where the requests service lets the person
// in. Favorites is never on the bar, only in the You hub (see [pinnable]).
const List<BottomNavTab> _autoOrder = [
  BottomNavTab.search,
  BottomNavTab.kostvDiscover,
  BottomNavTab.kostvMusic,
  BottomNavTab.libraries,
  BottomNavTab.myList,
  BottomNavTab.liveTv,
  BottomNavTab.genres,
  BottomNavTab.calendar,
];

final Map<String, BottomNavTab> _byName = {
  for (final tab in BottomNavTab.values) tab.name.toLowerCase(): tab,
};

/// Reads a stored pin list. Unknown names, which a newer client may have
/// synced, are dropped along with duplicates and anything past the limit.
List<BottomNavTab> parsePinnedBottomNavTabs(String raw) {
  final pins = <BottomNavTab>[];
  for (final part in raw.split(',')) {
    final tab = _byName[part.trim().toLowerCase()];
    if (tab == null || pins.contains(tab)) continue;
    pins.add(tab);
    if (pins.length == kMaxPinnedBottomNavTabs) break;
  }
  return pins;
}

String serializePinnedBottomNavTabs(Iterable<BottomNavTab> tabs) =>
    tabs.take(kMaxPinnedBottomNavTabs).map((t) => t.name).join(',');

/// Whether [raw] leaves the pins to be picked automatically. A list whose
/// names are all unknown counts, so a profile from a newer client falls back
/// to something sensible instead of an empty bar.
bool isAutomaticBottomNavTabs(String raw) =>
    parsePinnedBottomNavTabs(raw).isEmpty;

/// The settings that decide whether a [BottomNavTab] is on offer at all. Only
/// preferences and plugin state feed it, never loaded data, so the pins and
/// their colours don't shift while libraries are still loading.
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

  /// Kos TV: whether [tab] can sit on the bar. Favorites lives in the You
  /// hub only.
  static bool pinnable(BottomNavTab tab) => tab != BottomNavTab.favorites;

  // Kids Mode drops Libraries (the My Media row stands in), Live TV (its route
  // bounces home) and the calendar.
  bool offers(BottomNavTab tab) => switch (tab) {
        BottomNavTab.search => true,
        BottomNavTab.kostvDiscover =>
          !kidsMode && showKostvDiscover && kostvDiscoverAvailable,
        BottomNavTab.kostvMusic => showKostvMusic,
        BottomNavTab.libraries => !kidsMode && showLibraries,
        // Kos TV: always there, in the You hub (with «Mi lista» on the bar
        // a Favorites tab too would only confuse).
        BottomNavTab.favorites => true,
        BottomNavTab.myList => kostvMyListAvailable,
        BottomNavTab.genres => showGenres,
        BottomNavTab.liveTv => !kidsMode && showLiveTv,
        BottomNavTab.calendar => !kidsMode && showCalendar && calendarAvailable,
      };

  /// The tabs the bar shows between Home and You. Automatic pins follow the
  /// nav button switches without anything being stored. Explicit pins are
  /// only filtered, never topped up, so turning a button off doesn't slip an
  /// unchosen tab onto the bar.
  List<BottomNavTab> resolvePins(String raw) {
    final explicit = parsePinnedBottomNavTabs(raw);
    if (explicit.isNotEmpty) {
      return explicit.where((t) => offers(t) && pinnable(t)).toList();
    }
    return _autoOrder.where(offers).take(kMaxPinnedBottomNavTabs).toList();
  }
}
