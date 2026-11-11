import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/l10n/app_localizations_en.dart';
import 'package:moonfin/ui/util/home_row_title_localizer.dart';

final _l10n = AppLocalizationsEn();

// The data layer always titles these rows in English, so a translation with
// its own wording is the only way to tell the localized title from the input.
class _FrenchSinceYouWatched extends AppLocalizationsEn {
  @override
  String get sinceYouWatchedRowTitle => 'Parce que vous avez regardé';

  @override
  String sinceYouWatchedItemRowTitle(String title) =>
      'Parce que vous avez regardé « $title »';
}

void main() {
  group('a Since You Watched row', () {
    String titleOf(String rowTitle, {bool english = false}) =>
        localizeHomeRowTitle(
          row: HomeRow(
            id: 'sinceYouWatched2',
            title: rowTitle,
            rowType: HomeRowType.latestMedia,
          ),
          l10n: english ? _l10n : _FrenchSinceYouWatched(),
        );

    test('keeps the watched item in its translated title', () {
      expect(
        titleOf('Since you watched "Dune"'),
        'Parce que vous avez regardé « Dune »',
      );
    });

    test('keeps quotes that are part of the item name', () {
      expect(
        titleOf('Since you watched "The "Best" Movie"'),
        'Parce que vous avez regardé « The "Best" Movie »',
      );
    });

    test('reads plainly while its item is still loading', () {
      expect(titleOf('Since you watched'), 'Parce que vous avez regardé');
    });

    test('reads the same in English as before', () {
      expect(
        titleOf('Since you watched "Dune"', english: true),
        'Since you watched "Dune"',
      );
      expect(titleOf('Since you watched', english: true), 'Since you watched');
    });
  });
}
