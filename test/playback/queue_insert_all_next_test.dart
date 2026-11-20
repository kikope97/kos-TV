import 'package:flutter_test/flutter_test.dart';
import 'package:playback_core/playback_core.dart';

void main() {
  test('a whole list goes right after the current one, in its order, as '
      'one change', () async {
    final queue = QueueService()..setQueue(['a', 'b', 'c'], startIndex: 1);
    var changes = 0;
    final listening = queue.queueChangedStream.listen((_) => changes++);
    queue.insertAllNext(['m1', 'm2', 'm3']);
    await pumpEventQueue();
    expect(queue.items, ['a', 'b', 'm1', 'm2', 'm3', 'c']);
    expect(queue.currentIndex, 1);
    expect(changes, 1);
    await listening.cancel();
  });

  test('shuffled and back: the list is still in its order', () {
    final queue = QueueService()..setQueue(['a', 'b'], startIndex: 0);
    queue.insertAllNext(['m1', 'm2', 'm3']);
    queue.toggleShuffle();
    queue.toggleShuffle();
    final items = queue.items;
    expect(items.where((i) => '$i'.startsWith('m')).toList(), [
      'm1',
      'm2',
      'm3',
    ]);
  });

  test('nothing to insert changes nothing', () async {
    final queue = QueueService()..setQueue(['a']);
    var changes = 0;
    final listening = queue.queueChangedStream.listen((_) => changes++);
    queue.insertAllNext(const []);
    await pumpEventQueue();
    expect(queue.items, ['a']);
    expect(changes, 0);
    await listening.cancel();
  });
}
