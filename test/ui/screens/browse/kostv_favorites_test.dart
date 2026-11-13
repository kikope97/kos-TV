import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/viewmodels/favorites_view_model.dart';
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

  group('KostvFavoritesOrder', () {
    test('newest in the library first by default', () {
      final first = KostvFavoritesOrder.all.first;
      expect(first.sortBy, LibrarySortBy.dateAdded);
      expect(first.direction, SortDirection.descending);
    });

    test('names go A to Z, plays and dates high to low', () {
      expect(
        KostvFavoritesOrder.of(LibrarySortBy.name).direction,
        SortDirection.ascending,
      );
      expect(
        KostvFavoritesOrder.of(LibrarySortBy.playCount).direction,
        SortDirection.descending,
      );
      expect(
        KostvFavoritesOrder.of(LibrarySortBy.premiereDate).direction,
        SortDirection.descending,
      );
    });

    test('«Añadidos a favoritos» goes by the plugin, newest first', () {
      expect(KostvFavoritesOrder.favorited.sortBy, isNull);
      expect(
        KostvFavoritesOrder.favorited.direction,
        SortDirection.descending,
      );
      expect(KostvFavoritesOrder.all, isNot(contains(KostvFavoritesOrder.favorited)));
    });

    test('an order this page doesn\'t offer falls back to the first', () {
      expect(
        KostvFavoritesOrder.of(LibrarySortBy.genre),
        KostvFavoritesOrder.all.first,
      );
    });
  });

  group('FavoritesViewModel.sortValueFor', () {
    test('people keep to their names for orders they have nothing for', () {
      for (final by in [
        LibrarySortBy.premiereDate,
        LibrarySortBy.playCount,
        LibrarySortBy.communityRating,
        LibrarySortBy.runtime,
      ]) {
        expect(
          FavoritesViewModel.sortValueFor(FavoriteTypeFilter.person, by),
          LibrarySortBy.name.apiValue,
        );
      }
      expect(
        FavoritesViewModel.sortValueFor(
          FavoriteTypeFilter.person,
          LibrarySortBy.random,
        ),
        LibrarySortBy.random.apiValue,
      );
    });

    test('everything else sorts as asked', () {
      expect(
        FavoritesViewModel.sortValueFor(
          FavoriteTypeFilter.movie,
          LibrarySortBy.premiereDate,
        ),
        LibrarySortBy.premiereDate.apiValue,
      );
    });
  });
}
