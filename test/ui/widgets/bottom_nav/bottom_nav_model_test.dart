import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/bottom_nav_tabs.dart';
import 'package:moonfin/ui/widgets/bottom_nav/bottom_nav_model.dart';

void main() {
  group('resolveBarItems', () {
    test('Inicio, Descubrir, Música and Tú', () {
      final items = resolveBarItems(
        const BottomNavTabGates(kostvDiscoverAvailable: true),
      );
      expect(items, const [
        BottomNavBarItem.home(),
        BottomNavBarItem.tab(BottomNavTab.kostvDiscover),
        BottomNavBarItem.tab(BottomNavTab.kostvMusic),
        BottomNavBarItem.you(),
      ]);
    });

    test('a destination waiting on its data gives way to the next one', () {
      final items = resolveBarItems(
        const BottomNavTabGates(),
        isAvailable: (tab) => tab != BottomNavTab.libraries,
      );
      expect(items.map((i) => i.id), [
        'home',
        'kostvMusic',
        'genres',
        'you',
      ]);
    });
  });

  group('activeBarIndex', () {
    final items = resolveBarItems(
      const BottomNavTabGates(kostvDiscoverAvailable: true),
    );

    test('matches each tab on its own screens', () {
      expect(activeBarIndex(items, '/home'), 0);
      expect(activeBarIndex(items, '/discover'), 1);
      expect(activeBarIndex(items, '/musica'), 2);
      expect(activeBarIndex(items, '/musica/album/12'), 2);
      // Kos TV: «Tú» is a page of its own.
      expect(activeBarIndex(items, '/tu'), 3);
    });

    test('lights nothing on a screen that belongs to no tab', () {
      expect(activeBarIndex(items, '/item/abc'), isNull);
      expect(activeBarIndex(items, null), isNull);
    });

    test('a route that only starts with a tab name doesn\'t match it', () {
      expect(activeBarIndex(items, '/musicas'), isNull);
    });

    test('Kos TV: Discover lights up on its own screen only', () {
      expect(activeBarIndex(items, '/discover/movie/12'), isNull);
    });
  });
}
