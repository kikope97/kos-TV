import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/bottom_nav_tabs.dart';
import '../../navigation/destinations.dart';
import '../../navigation/home_refresh_bus.dart';
import '../../navigation/menu_preview.dart';
import '../adaptive/sf_symbol.dart';

String bottomNavTabLabel(AppLocalizations l10n, BottomNavTab tab) =>
    switch (tab) {
      BottomNavTab.search => l10n.search,
      BottomNavTab.kostvDiscover => l10n.kostvDiscover,
      BottomNavTab.kostvMusic => l10n.kostvMusic,
      BottomNavTab.libraries => l10n.libraries,
      BottomNavTab.favorites => l10n.kostvMyFavorites,
      BottomNavTab.myList => l10n.kostvMyList,
      BottomNavTab.genres => l10n.genres,
      BottomNavTab.liveTv => l10n.liveTv,
      BottomNavTab.calendar => l10n.calendar,
    };

/// Filled when active and outlined when not, the way both platforms mark
/// the current tab. Genres keeps the artwork the other menus use, so only
/// its colour changes.
Widget bottomNavTabIconWidget(
  BottomNavTab tab, {
  required bool active,
  required double size,
  required Color color,
}) {
  Widget adaptive(IconData filled, IconData outlined) =>
      AdaptiveIcon(active ? filled : outlined, size: size, color: color);

  return switch (tab) {
    BottomNavTab.search =>
      adaptive(Icons.search_rounded, Icons.search_rounded),
    BottomNavTab.kostvDiscover =>
      adaptive(Icons.explore_rounded, Icons.explore_outlined),
    BottomNavTab.kostvMusic =>
      adaptive(Icons.music_note_rounded, Icons.music_note_outlined),
    BottomNavTab.libraries =>
      adaptive(Icons.video_library_rounded, Icons.video_library_outlined),
    BottomNavTab.favorites =>
      adaptive(Icons.favorite_rounded, Icons.favorite_border_rounded),
    BottomNavTab.myList =>
      adaptive(Icons.bookmark_rounded, Icons.bookmark_border_rounded),
    BottomNavTab.liveTv =>
      adaptive(Icons.live_tv_rounded, Icons.live_tv_outlined),
    BottomNavTab.genres => Image.asset(
        'assets/icons/genres.png',
        width: size,
        height: size,
        color: color,
        fit: BoxFit.contain,
      ),
    BottomNavTab.calendar =>
      adaptive(Icons.calendar_month_rounded, Icons.calendar_month_outlined),
  };
}

/// The route of [tab]'s page.
String bottomNavTabRoute(BottomNavTab tab) => switch (tab) {
  BottomNavTab.search => Destinations.search,
  BottomNavTab.kostvDiscover => Destinations.kostvDiscover,
  BottomNavTab.kostvMusic => Destinations.kostvMusic,
  BottomNavTab.favorites => Destinations.allFavorites,
  BottomNavTab.myList => Destinations.myList,
  BottomNavTab.genres => Destinations.allGenres,
  BottomNavTab.liveTv => Destinations.liveTvGuide,
  BottomNavTab.calendar => Destinations.calendar,
  // Kos TV: Libraries has a page of its own.
  BottomNavTab.libraries => Destinations.kostvLibraries,
};

/// Opens [tab]'s screen.
void openBottomNavTab(BuildContext context, BottomNavTab tab) =>
    openBottomNavPage(context, bottomNavTabRoute(tab));

/// Opens one of the menu's pages from the glass bar, «Tú» or «Más».
void openBottomNavPage(BuildContext context, String route) {
  // As the TV's menu does: one menu page takes the place of another, a page
  // opened inside one (a genre, an album) goes back to it, so Back always
  // goes to Home.
  if (Destinations.isMenuPage(route)) {
    MenuPreview.open(context, route);
  } else {
    context.navigateTopLevel(route);
  }
}

/// Home refreshes when tapped where it already is. Otherwise a Home built
/// afresh refreshes on arrival, and one kept underneath stays as it was.
void openBottomNavHome(BuildContext context, {required bool alreadyHome}) {
  if (alreadyHome) {
    homeRefreshBus.request(newMediaBar: true);
    return;
  }
  homeRefreshBus.requestOnArrival();
  context.go(Destinations.home);
}
