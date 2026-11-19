import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/ui/screens/home/home_screen.dart';

HomeRow _row(String id, {bool empty = false, bool loading = false}) => HomeRow(
  id: id,
  title: id,
  rowType: HomeRowType.latestMedia,
  isLoading: loading,
  items: empty
      ? const []
      : const [AggregatedItem(id: '1', serverId: 'server', rawData: {})],
);

bool _focusable(HomeRow row) => !row.isLoading && row.items.isNotEmpty;

/// Kos TV: when the row the remote is on leaves Home (as «Quiero verlo» does
/// once its last title is watched or taken off), the focus goes next door.
void main() {
  int? after(String goneId, List<String> before, List<HomeRow> rows) =>
      homeRowAfterFocusedRowLeft(
        goneId: goneId,
        before: before,
        rows: rows,
        focusable: _focusable,
      );

  test('the row that took its place gets the focus', () {
    final rows = [_row('resume'), _row('pelis'), _row('series')];
    expect(after('mylist', ['resume', 'mylist', 'pelis', 'series'], rows), 1);
  });

  test('the last row going hands it to the one above', () {
    final rows = [_row('resume'), _row('pelis')];
    expect(after('mylist', ['resume', 'pelis', 'mylist'], rows), 1);
  });

  test('rows with nothing to focus are passed over', () {
    final rows = [
      _row('resume'),
      _row('empty', empty: true),
      _row('loading', loading: true),
    ];
    expect(after('mylist', ['resume', 'mylist', 'empty', 'loading'], rows), 0);
  });

  test('an emptied row still listed is not chosen again', () {
    final rows = [_row('mylist', empty: true), _row('pelis')];
    expect(after('mylist', ['mylist', 'pelis'], rows), 1);
  });

  test('a row inserted where it was takes its place', () {
    final rows = [_row('resume'), _row('nuevo'), _row('pelis')];
    expect(after('mylist', ['resume', 'mylist', 'pelis'], rows), 1);
  });

  test('none left: null, for the banner or the navbar', () {
    expect(after('mylist', ['mylist'], const []), isNull);
    expect(
      after('mylist', ['mylist', 'empty'], [_row('empty', empty: true)]),
      isNull,
    );
  });
}
