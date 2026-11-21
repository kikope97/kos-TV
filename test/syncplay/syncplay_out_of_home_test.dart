import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/syncplay/syncplay_manager.dart';

// Kos TV: the songs that aren't at home (heard through the requests
// service) aren't the home server's, which can't play them for the group.
void main() {
  String? idOf(Object? item) => item as String?;

  test('only the songs at home go, with the one sounding where it is', () {
    final queue = syncPlayQueueToSend(
      ['h1', 'stremfin:2', 'h3', 'stremfin:4', 'h5'],
      2,
      idOf,
    )!;
    expect(queue.ids, ['h1', 'h3', 'h5']);
    expect(queue.ids[queue.start], 'h3');
    final last = syncPlayQueueToSend(['stremfin:1', 'h2', 'h3'], 2, idOf)!;
    expect(last.ids[last.start], 'h3');
  });

  test('one that isn\'t at home sounding: nothing goes', () {
    expect(syncPlayQueueToSend(['h1', 'stremfin:2', 'h3'], 1, idOf), isNull);
  });

  test('nothing at home: nothing goes', () {
    expect(syncPlayQueueToSend(['stremfin:1'], -1, idOf), isNull);
    expect(syncPlayQueueToSend(<Object?>[], 0, idOf), isNull);
  });

  test('a queue at home only goes as before', () {
    final queue = syncPlayQueueToSend(['a', 'b', 'c'], 1, idOf)!;
    expect(queue.ids, ['a', 'b', 'c']);
    expect(queue.start, 1);
    // An index past the end clamps to the last, as before.
    expect(syncPlayQueueToSend(['a', 'b'], 9, idOf)!.start, 1);
    expect(syncPlayQueueToSend(['a', 'b'], -1, idOf)!.start, 0);
  });
}
