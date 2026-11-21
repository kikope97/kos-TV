import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
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

  int nexts = 0;

  @override
  Future<void> next() async => nexts++;
}

AggregatedItem _song(String id, {String artist = 'a1'}) => AggregatedItem(
  id: id,
  serverId: 'casa',
  rawData: {
    'Id': id,
    'Name': 'Canción $id',
    'Type': 'Audio',
    'MediaType': 'Audio',
    'AlbumArtists': [
      {'Id': artist, 'Name': 'Artista $artist'},
    ],
  },
);

/// Kos TV: «No me gusta» on what is still to play.
void main() {
  late _Manager manager;
  final music = KostvNowPlaying.instance;

  setUp(() {
    manager = _Manager();
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
  });

  tearDown(() {
    music.debugReset();
    return GetIt.instance.reset();
  });

  bool byA9(AggregatedItem song) =>
      (song.rawData['AlbumArtists'] as List).first['Id'] == 'a9';

  test('a song goes from what is still to play, wherever it came from', () {
    manager.queueService.setQueue([
      _song('s1'),
      _song('s2'),
      _song('s3'),
      _song('s2'),
    ]);
    expect(music.leaveOutUpcoming((s) => s.id == 's2'), 2);
    expect(manager.queueService.items.map((s) => (s as AggregatedItem).id), [
      's1',
      's3',
    ]);
  });

  test('the one sounding stays, and skips to the next', () {
    manager.queueService.setQueue([_song('s1'), _song('s2')]);
    music.leaveOutUpcoming((s) => s.id == 's1');
    expect(manager.queueService.items, hasLength(2));
    music.skipIfSounding('s1');
    expect(manager.nexts, 1);
    music.skipIfSounding('s2');
    expect(manager.nexts, 1);
  });

  test('an artist: only from what came by itself (a radio, ∞)', () {
    final queue = [
      _song('s1'),
      _song('s2', artist: 'a9'),
      _song('s3', artist: 'a9'),
      _song('s4', artist: 'a9'),
    ];
    manager.queueService.setQueue(queue);
    // An album the person put on: nothing of it is taken out.
    music.noteQueueSource(KostvMusicSource.album, queue);
    expect(music.leaveOutUpcoming(byA9, onlyAutomatic: true), 0);
    // A radio: its songs are.
    music.noteQueueSource(KostvMusicSource.radio, queue.take(3).toList());
    music.autoplayIds.add('s4');
    expect(music.leaveOutUpcoming(byA9, onlyAutomatic: true), 3);
    expect(manager.queueService.items, hasLength(1));
  });

  test('which sources are picked by the app', () {
    expect(KostvMusicSource.automatic(KostvMusicSource.radio), isTrue);
    expect(KostvMusicSource.automatic(KostvMusicSource.mix('daily-1')), isTrue);
    expect(
      KostvMusicSource.automatic(KostvMusicSource.moment('noche')),
      isTrue,
    );
    expect(KostvMusicSource.automatic(KostvMusicSource.discovery), isTrue);
    expect(KostvMusicSource.automatic(KostvMusicSource.search), isFalse);
    expect(KostvMusicSource.automatic(KostvMusicSource.album), isFalse);
  });
}
