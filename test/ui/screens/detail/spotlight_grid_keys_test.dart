// The Spotlight modal grids key every cell so a rebuild reuses the elements
// already on screen. Those keys have to stay unique, because the lists behind
// them can name the same title or person more than once and Flutter asserts
// on duplicate keys among siblings.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/detail/spotlight/widgets/spotlight_modal_grids.dart';

void main() {
  group('spotlightCellKeys', () {
    test('leaves distinct ids alone', () {
      expect(spotlightCellKeys(['a', 'b', 'c']), ['a', 'b', 'c']);
    });

    test('gives every repeat its own key', () {
      expect(spotlightCellKeys(['a', 'b', 'a', 'a']), [
        'a',
        'b',
        'a#1',
        'a#2',
      ]);
    });

    test('the same list always produces the same keys', () {
      const ids = ['x', 'y', 'x'];
      expect(spotlightCellKeys(ids), spotlightCellKeys(ids));
    });
  });

  group('spotlightDedupePeople', () {
    test('folds a repeated person into one entry and joins their roles', () {
      final people = spotlightDedupePeople([
        {'Id': 'p1', 'Name': 'Ripley', 'Role': 'Ellen Ripley'},
        {'Id': 'p1', 'Name': 'Ripley', 'Role': 'Narrator'},
        {'Id': 'p2', 'Name': 'Hicks', 'Role': 'Corporal'},
      ]);

      expect(people, hasLength(2));
      expect(people.first['Role'], 'Ellen Ripley · Narrator');
      expect(people.last['Role'], 'Corporal');
    });

    test('drops entries with nothing to key on', () {
      expect(spotlightDedupePeople([{'Role': 'Extra'}]), isEmpty);
    });
  });
}
