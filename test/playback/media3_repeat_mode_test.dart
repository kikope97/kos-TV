import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/playback/media3_player_backend.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:playback_core/playback_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _control = MethodChannel('moonfin/media3_video_control');
const _events = MethodChannel('moonfin/media3_video_events');

// Kos TV: ExoPlayer only holds the item playing, so its own repeat-all looped
// that one song and the queue never moved on; and a mode left on carried over
// to the next film. The queue does the repeating, the engine never does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Media3PlayerBackend backend;
  late List<String?> sent;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    sent = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_control, (call) async {
          if (call.method == 'setRepeatMode') {
            sent.add((call.arguments as Map)['mode'] as String?);
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_events, (_) async => null);
    backend = Media3PlayerBackend(UserPreferences(store));
  });

  tearDown(() {
    backend.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_control, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_events, null);
  });

  for (final mode in RepeatMode.values) {
    test('the engine never repeats for ${mode.name}', () async {
      await backend.setRepeatMode(mode);
      expect(sent, ['off']);
    });
  }

  test('an item opened after repeat was on does not repeat', () async {
    await backend.setRepeatMode(RepeatMode.repeatAll);
    sent.clear();

    await backend.play('https://server.test/episode.mp4');

    expect(sent, isNotEmpty);
    expect(sent, everyElement('off'));
  });
}
