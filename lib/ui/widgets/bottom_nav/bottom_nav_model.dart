import '../../../preference/bottom_nav_tabs.dart';
import '../../navigation/destinations.dart';

enum BottomNavItemKind { home, tab, you }

/// One tab of the glass bar.
class BottomNavBarItem {
  final BottomNavItemKind kind;
  final BottomNavTab? tab;

  const BottomNavBarItem._(this.kind, this.tab);

  const BottomNavBarItem.home() : this._(BottomNavItemKind.home, null);

  const BottomNavBarItem.tab(BottomNavTab tab)
      : this._(BottomNavItemKind.tab, tab);

  const BottomNavBarItem.you() : this._(BottomNavItemKind.you, null);

  String get id => switch (kind) {
        BottomNavItemKind.home => 'home',
        BottomNavItemKind.you => 'you',
        BottomNavItemKind.tab => tab!.name,
      };

  @override
  bool operator ==(Object other) =>
      other is BottomNavBarItem && other.kind == kind && other.tab == tab;

  @override
  int get hashCode => Object.hash(kind, tab);

  @override
  String toString() => 'BottomNavBarItem($id)';
}

/// Kos TV: Inicio, the bar's tabs (Descubrir and Música, see
/// [BottomNavTabGates.barTabs]) and Tú. Search has its own round button.
List<BottomNavBarItem> resolveBarItems(
  BottomNavTabGates gates, {
  bool Function(BottomNavTab tab)? isAvailable,
}) => [
  const BottomNavBarItem.home(),
  for (final tab in gates.barTabs(isAvailable: isAvailable))
    BottomNavBarItem.tab(tab),
  const BottomNavBarItem.you(),
];

/// Where each tab's own screens live, for lighting it up as the active one.
bool bottomNavTabMatchesRoute(BottomNavTab tab, String route) {
  bool under(String prefix) => route == prefix || route.startsWith('$prefix/');
  return switch (tab) {
    BottomNavTab.search => route == Destinations.search,
    BottomNavTab.kostvDiscover => route == Destinations.kostvDiscover,
    BottomNavTab.libraries => route == Destinations.kostvLibraries ||
        under('/library') ||
        under('/folder') ||
        under('/music') ||
        under('/books') ||
        under('/games'),
    BottomNavTab.favorites => route == Destinations.allFavorites,
    BottomNavTab.myList => route == Destinations.myList,
    BottomNavTab.kostvMusic => under(Destinations.kostvMusic),
    BottomNavTab.genres => route == Destinations.allGenres,
    BottomNavTab.liveTv => under(Destinations.liveTv),
    BottomNavTab.calendar => under(Destinations.calendar),
  };
}

/// The index of the item to highlight, or null when the screen belongs to
/// none of them, like an item's detail page.
int? activeBarIndex(List<BottomNavBarItem> items, String? activeRoute) {
  final route = activeRoute ?? '';
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final active = switch (item.kind) {
      BottomNavItemKind.you => route == Destinations.kostvYou,
      BottomNavItemKind.home => route == Destinations.home,
      BottomNavItemKind.tab => bottomNavTabMatchesRoute(item.tab!, route),
    };
    if (active) return i;
  }
  return null;
}
