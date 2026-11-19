import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/widgets/music/kostv_queue_moves.dart';
import 'package:playback_core/playback_core.dart';

AggregatedItem _song(String id) => AggregatedItem(
  id: id,
  serverId: 'casa',
  rawData: {'Id': id, 'Name': id, 'Type': 'Audio', 'MediaType': 'Audio'},
);

/// Kos TV: «A continuación» with the remote: moving a song up or down and
/// taking it away.
void main() {
  late QueueService queue;
  late List<AggregatedItem> songs;

  List<String> upcomingIds() => [
    for (final entry in kostvUpcoming(queue)) entry.item.id,
  ];

  setUp(() {
    queue = QueueService();
    songs = [
      for (final id in ['a', 'b', 'c', 'd', 'e']) _song(id),
    ];
    // «b» is sounding: «c», «d» and «e» come next.
    queue.setQueue(songs, startIndex: 1);
  });

  test('the songs to come are the ones after the one sounding', () {
    expect(upcomingIds(), ['c', 'd', 'e']);
    expect(kostvUpcomingPosition(queue, songs[3]), 1);
    expect(kostvUpcomingPosition(queue, songs[0]), isNull);
    expect(kostvUpcomingPosition(queue, songs[1]), isNull);
  });

  test('up moves a song one place up, and says where it went', () {
    expect(kostvMoveUpcoming(queue, songs[4], up: true), 1);
    expect(upcomingIds(), ['c', 'e', 'd']);
    expect(kostvMoveUpcoming(queue, songs[4], up: true), 0);
    expect(upcomingIds(), ['e', 'c', 'd']);
    // Never past the one sounding.
    expect(kostvMoveUpcoming(queue, songs[4], up: true), isNull);
    expect(upcomingIds(), ['e', 'c', 'd']);
    expect(queue.currentItem, same(songs[1]));
  });

  test('down moves a song one place down, and not past the last', () {
    expect(kostvMoveUpcoming(queue, songs[2], up: false), 1);
    expect(upcomingIds(), ['d', 'c', 'e']);
    expect(kostvMoveUpcoming(queue, songs[2], up: false), 2);
    expect(upcomingIds(), ['d', 'e', 'c']);
    expect(kostvMoveUpcoming(queue, songs[2], up: false), isNull);
    expect(queue.currentItem, same(songs[1]));
  });

  test('a song is found again after the queue moved on', () {
    // «c» started by itself while its menu was open: «d» is now first.
    queue.next();
    expect(kostvUpcomingPosition(queue, songs[3]), 0);
    expect(kostvMoveUpcoming(queue, songs[2], up: false), isNull);
    expect(kostvRemoveUpcoming(queue, songs[2]), isNull);
    expect(upcomingIds(), ['d', 'e']);
  });

  test('taking a song away leaves the rest and the one sounding', () {
    expect(kostvRemoveUpcoming(queue, songs[3]), 1);
    expect(upcomingIds(), ['c', 'e']);
    expect(queue.currentItem, same(songs[1]));
    expect(kostvRemoveUpcoming(queue, songs[3]), isNull);
  });
}
