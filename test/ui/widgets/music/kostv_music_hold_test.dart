import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/widgets/music/kostv_music_hold.dart';
import 'package:playback_core/playback_core.dart';

class _Manager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();

  int pauses = 0;
  int resumes = 0;

  @override
  Future<void> pause() async {
    pauses++;
    state.setPlaying(false);
  }

  @override
  Future<void> resume() async {
    resumes++;
    state.setPlaying(true);
  }
}

AggregatedItem _item(String id, String type) => AggregatedItem(
  id: id,
  serverId: 'casa',
  rawData: {
    'Id': id,
    'Name': id,
    'Type': type,
    if (type == 'Audio') 'MediaType': 'Audio',
  },
);

/// Kos TV: a full-screen trailer pauses the music and it goes on after.
void main() {
  late _Manager manager;

  setUp(() {
    manager = _Manager();
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
  });

  tearDown(() => GetIt.instance.reset());

  test('music playing pauses, and goes on after', () {
    manager.queueService.setQueue([_item('s1', 'Audio')]);
    manager.state.setPlaying(true);
    final hold = KostvMusicHold()..pause();
    expect(manager.pauses, 1);
    expect(manager.queueService.currentItem, isNotNull);
    hold.resume();
    expect(manager.resumes, 1);
    // Only once.
    hold.resume();
    expect(manager.resumes, 1);
  });

  test('music already paused stays paused', () {
    manager.queueService.setQueue([_item('s1', 'Audio')]);
    final hold = KostvMusicHold()..pause();
    expect(manager.pauses, 0);
    hold.resume();
    expect(manager.resumes, 0);
  });

  test('a film sounding is not the hold\'s', () {
    manager.queueService.setQueue([_item('m1', 'Movie')]);
    manager.state.setPlaying(true);
    KostvMusicHold()
      ..pause()
      ..resume();
    expect(manager.pauses, 0);
    expect(manager.resumes, 0);
  });

  test('something else put on meanwhile is not resumed', () {
    manager.queueService.setQueue([_item('s1', 'Audio')]);
    manager.state.setPlaying(true);
    final hold = KostvMusicHold()..pause();
    manager.queueService.setQueue([_item('s2', 'Audio')]);
    hold.resume();
    expect(manager.resumes, 0);
  });
}
