import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:moonfin/ui/widgets/music/music_navigation.dart';
import 'package:playback_core/playback_core.dart';

class _Manager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();

  @override
  bool get isOfflinePlayback => false;

  @override
  Map<String, dynamic>? get currentOfflineMetadata => null;
}

AggregatedItem _song(String id) => AggregatedItem(
  id: id,
  serverId: 'casa',
  rawData: {'Id': id, 'Name': 'Canción $id', 'Type': 'Audio'},
);

/// Kos TV: a song that isn't at home failing late, after another was put
/// on meanwhile, isn't told as «No se puede reproducir» over the new one.
void main() {
  late _Manager manager;

  setUp(() {
    manager = _Manager();
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
  });

  tearDown(() async {
    KostvNowPlaying.instance.debugReset();
    await GetIt.instance.reset();
  });

  test('told while it is still what was put on', () {
    final a = [_song('a1'), _song('a2')];
    final turn = kostvNextPlayTurn();
    manager.queueService.setQueue(a);
    expect(kostvStillPlaysWhatWasPut(turn, a), isTrue);
    // Nothing sounding (it failed before starting): told too.
    manager.queueService.setQueue([]);
    expect(kostvStillPlaysWhatWasPut(turn, a), isTrue);
  });

  test('not once something else was put on', () {
    final a = [_song('a1')];
    final turn = kostvNextPlayTurn();
    manager.queueService.setQueue(a);
    // Another pick from the Music pages.
    kostvNextPlayTurn();
    expect(kostvStillPlaysWhatWasPut(turn, a), isFalse);
  });

  test('not when another song sounds (put on some other way)', () {
    final a = [_song('a1')];
    final turn = kostvNextPlayTurn();
    manager.queueService.setQueue([_song('b1')]);
    expect(kostvStillPlaysWhatWasPut(turn, a), isFalse);
  });
}
