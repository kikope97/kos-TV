import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/bottom_nav_tabs.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/ui/screens/browse/kostv_favorites_screen.dart';

void main() {
  group('KostvFavoritesKind', () {
    test('episodes are wide, people square, films posters', () {
      expect(
        KostvFavoritesKind.of(FavoriteTypeFilter.episode).aspect,
        greaterThan(1.5),
      );
      expect(KostvFavoritesKind.of(FavoriteTypeFilter.person).aspect, 1);
      expect(KostvFavoritesKind.of(FavoriteTypeFilter.movie).aspect, 2 / 3);
      expect(KostvFavoritesKind.of(FavoriteTypeFilter.musicAlbum).aspect, 1);
    });
  });

  group('Favourites on phones', () {
    const gates = BottomNavTabGates(showFavorites: false);

    test('never on the bar, even pinned', () {
      expect(BottomNavTabGates.pinnable(BottomNavTab.favorites), isFalse);
      expect(gates.resolvePins('favorites,search'), [BottomNavTab.search]);
      expect(gates.resolvePins(''), isNot(contains(BottomNavTab.favorites)));
    });

    test('always offered, so the You hub has it', () {
      expect(gates.offers(BottomNavTab.favorites), isTrue);
    });
  });
}
