import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/ui/widgets/bottom_nav/bottom_mini_player.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:playback_core/playback_core.dart';

class _Manager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();

  Map<String, dynamic>? offline;

  @override
  Map<String, dynamic>? get currentOfflineMetadata => offline;
}

// Kos TV: a downloaded song plays from a file, not a library item, and the
// bar along the bottom didn't show it while the floating player stepped
// aside for the bar: nothing on screen to see or stop it.
void main() {
  late _Manager manager;

  setUp(() {
    manager = _Manager();
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
  });

  tearDown(() {
    KostvNowPlaying.instance.debugReset();
    return GetIt.instance.reset();
  });

  test('a downloaded song has the bar\'s player', () {
    manager.offline = {
      'Id': 'd1',
      'Name': 'Verano',
      'Type': 'Audio',
      'MediaType': 'Audio',
    };
    manager.queueService.setQueue(['/descargas/verano.flac']);
    expect(bottomMiniPlayerHasTrack(), isTrue);
  });

  test('a downloaded film does not', () {
    manager.offline = {'Id': 'f1', 'Name': 'Película', 'Type': 'Movie'};
    manager.queueService.setQueue(['/descargas/pelicula.mkv']);
    expect(bottomMiniPlayerHasTrack(), isFalse);
  });

  test('with nothing playing it does not', () {
    expect(bottomMiniPlayerHasTrack(), isFalse);
  });
}
