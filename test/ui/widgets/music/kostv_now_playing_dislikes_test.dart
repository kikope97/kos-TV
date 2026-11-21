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
  int chapterNexts = 0;

  /// The song's next chapter first: not what «No me gusta» wants.
  @override
  Future<void> next() async => chapterNexts++;

  @override
  Future<void> nextInQueue() async {
    nexts++;
    queueService.next(manual: true);
  }

  @override
  Future<void> playFromQueue(int index) async => queueService.jumpTo(index);
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

List<String> _ids(QueueService queue) =>
    queue.items.map((s) => (s as AggregatedItem).id).toList();

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
    expect(music.leaveOutUpcoming((s) => s.id == 's2').length, 2);
    expect(_ids(manager.queueService), ['s1', 's3']);
  });

  test('the one sounding stays, and skips straight to the next song', () {
    manager.queueService.setQueue([_song('s1'), _song('s2')]);
    music.leaveOutUpcoming((s) => s.id == 's1');
    expect(manager.queueService.items, hasLength(2));
    expect(music.skipIfSounding('s1'), isNotNull);
    expect(manager.nexts, 1);
    // Not the song's next chapter.
    expect(manager.chapterNexts, 0);
    expect(music.skipIfSounding('s1'), isNull);
    expect(manager.nexts, 1);
  });

  test('with the whole queue on repeat, the ones before it go too', () {
    manager.queueService
      ..setQueue([
        _song('s2'),
        _song('s1'),
        _song('s3'),
        _song('s2'),
      ], startIndex: 2)
      ..toggleRepeat();
    expect(manager.queueService.repeatMode, RepeatMode.repeatAll);
    expect(music.leaveOutUpcoming((s) => s.id == 's2').length, 2);
    expect(_ids(manager.queueService), ['s1', 's3']);
    expect((manager.queueService.currentItem as AggregatedItem).id, 's3');
    // But never the one sounding.
    expect(music.leaveOutUpcoming((s) => s.id == 's3').length, 0);
  });

  test('without repeat, the ones already played stay', () {
    manager.queueService.setQueue([
      _song('s2'),
      _song('s1'),
      _song('s2'),
    ], startIndex: 1);
    expect(music.leaveOutUpcoming((s) => s.id == 's2').length, 1);
    expect(_ids(manager.queueService), ['s2', 's1']);
  });

  test('«Deshacer» puts it back where it was, and back to it if it was '
      'sounding', () async {
    final queue = [_song('s0'), _song('s1'), _song('s2'), _song('s1')];
    manager.queueService.setQueue(queue, startIndex: 1);
    final left = music.leaveOutUpcoming((s) => s.id == 's1');
    final skipped = music.skipIfSounding('s1');
    await Future<void>.delayed(Duration.zero);
    expect(_ids(manager.queueService), ['s0', 's1', 's2']);
    expect((manager.queueService.currentItem as AggregatedItem).id, 's2');
    music.putBack(left, skipped: skipped);
    await Future<void>.delayed(Duration.zero);
    expect(_ids(manager.queueService), ['s0', 's1', 's2', 's1']);
    expect(identical(manager.queueService.currentItem, queue[1]), isTrue);
  });

  test('«Deshacer» after picking another: back in the queue, the one '
      'picked goes on', () async {
    final queue = [_song('s1'), _song('s2'), _song('s3'), _song('s4')];
    manager.queueService.setQueue(queue);
    final left = music.leaveOutUpcoming((s) => s.id == 's1');
    final skipped = music.skipIfSounding('s1');
    await Future<void>.delayed(Duration.zero);
    // Another one, picked meanwhile.
    manager.queueService.jumpTo(3);
    music.putBack(left, skipped: skipped);
    await Future<void>.delayed(Duration.zero);
    expect(identical(manager.queueService.currentItem, queue[3]), isTrue);
  });

  test('«Deshacer» of one coming up: back where it was', () {
    final queue = [_song('s1'), _song('s2'), _song('s3'), _song('s2')];
    manager.queueService.setQueue(queue);
    final left = music.leaveOutUpcoming((s) => s.id == 's2');
    expect(_ids(manager.queueService), ['s1', 's3']);
    music.putBack(left);
    expect(_ids(manager.queueService), ['s1', 's2', 's3', 's2']);
    expect(identical(manager.queueService.currentItem, queue[0]), isTrue);
  });

  test('«Deshacer» with another queue on: nothing is put back', () {
    manager.queueService.setQueue([_song('s1'), _song('s2')]);
    final left = music.leaveOutUpcoming((s) => s.id == 's2');
    manager.queueService.setQueue([_song('x1'), _song('x2')]);
    music.putBack(left);
    expect(_ids(manager.queueService), ['x1', 'x2']);
  });

  test('an artist: only from what came by itself (a radio, ∞), and back '
      'with «Deshacer»', () {
    final queue = [
      _song('s1'),
      _song('s2', artist: 'a9'),
      _song('s3', artist: 'a9'),
      _song('s4', artist: 'a9'),
    ];
    manager.queueService.setQueue(queue);
    // An album the person put on: nothing of it is taken out.
    music.noteQueueSource(KostvMusicSource.album, queue);
    expect(music.leaveOutUpcoming(byA9, onlyAutomatic: true).length, 0);
    // A radio: its songs are.
    music.noteQueueSource(KostvMusicSource.radio, queue.take(3).toList());
    music.autoplayItems.add(queue[3]);
    final left = music.leaveOutUpcoming(byA9, onlyAutomatic: true);
    expect(left.length, 3);
    expect(manager.queueService.items, hasLength(1));
    music.putBack(left);
    expect(_ids(manager.queueService), ['s1', 's2', 's3', 's4']);
  });

  test('another queue with the same songs isn\'t taken as come by itself', () {
    final radio = [_song('s1'), _song('s2', artist: 'a9')];
    music.noteQueueSource(KostvMusicSource.radio, radio);
    // An album's page puts the same songs on, without telling.
    manager.queueService.setQueue([_song('s1'), _song('s2', artist: 'a9')]);
    expect(music.leaveOutUpcoming(byA9, onlyAutomatic: true).length, 0);
    expect(manager.queueService.items, hasLength(2));
  });

  test('the queue puts one back keeping the one sounding', () {
    final queue = QueueService()
      ..setQueue(['a', 'b', 'c'], startIndex: 1)
      ..insertAt(0, 'x');
    expect(queue.items, ['x', 'a', 'b', 'c']);
    expect(queue.currentItem, 'b');
    queue.insertAt(9, 'y');
    expect(queue.items.last, 'y');
    expect(queue.currentItem, 'b');
    queue.insertAt(3, 'z');
    expect(queue.items, ['x', 'a', 'b', 'z', 'c', 'y']);
    expect(queue.currentItem, 'b');
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
