import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/playback/media3_player_backend.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _control = MethodChannel('moonfin/media3_video_control');
const _events = MethodChannel('moonfin/media3_video_events');

Future<void> _send(Map<String, dynamic> payload) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(payload),
        (_) {},
      );
}

const _song = <String, dynamic>{
  'url': 'https://server.test/a.flac',
  'mediaType': 'audio',
  'gaplessAudio': true,
};

const _next = <String, dynamic>{
  'url': 'https://server.test/b.flac',
  'mediaType': 'audio',
  'container': 'flac',
  'headers': {'Authorization': 'token'},
  'normalizationGainDb': -3.5,
  'audioCodec': 'flac',
};

/// Kos TV: the next song queued in Media3 for a move with no gap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Media3PlayerBackend backend;
  late UserPreferences prefs;
  late List<MethodCall> calls;
  late bool nativeTakes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    calls = <MethodCall>[];
    nativeTakes = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_control, (call) async {
          calls.add(call);
          return call.method == 'enqueueNext' ? nativeTakes : null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_events, (_) async => null);
    prefs = UserPreferences(store);
    backend = Media3PlayerBackend(prefs);
  });

  tearDown(() {
    backend.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_control, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_events, null);
  });

  Future<void> tick(int positionMs, {bool playing = true}) async {
    await _send(<String, dynamic>{
      'event': 'state',
      'positionMs': positionMs,
      'durationMs': 180000,
      'isPlaying': playing,
    });
    await pumpEventQueue();
  }

  test('music asks the native player to keep the offload gapless', () async {
    await backend.play(_song);
    final source = calls.firstWhere((c) => c.method == 'setSource');
    expect((source.arguments as Map)['gaplessAudio'], isTrue);
  });

  test('the next song goes over with its address, headers and gain', () async {
    await backend.play(_song);
    expect(await backend.preloadNext(_next), isTrue);

    final queued = calls.lastWhere((c) => c.method == 'enqueueNext');
    final args = queued.arguments as Map;
    expect(args['url'], 'https://server.test/b.flac');
    expect(args['headers'], {'Authorization': 'token'});
    expect(args['normalizationGainDb'], -3.5);
    expect(args['container'], 'flac');
    expect(args['mediaType'], 'audio');
  });

  test('a native player that refuses it leaves the end as it was', () async {
    nativeTakes = false;
    await backend.play(_song);
    expect(await backend.preloadNext(_next), isFalse);
    final completed = <bool>[];
    final sub = backend.completedStream.listen(completed.add);

    await tick(180000, playing: false);
    expect(completed, [true]);
    await sub.cancel();
  });

  test('with skip silence on nothing is queued', () async {
    await prefs.set(UserPreferences.media3SkipSilence, true);
    await backend.play(_song);
    expect(backend.canPreloadNext, isFalse);
    expect(await backend.preloadNext(_next), isFalse);
    expect(calls.where((c) => c.method == 'enqueueNext'), isEmpty);
  });

  test('video is never queued', () async {
    await backend.play(_song);
    expect(
      await backend.preloadNext({'url': 'https://server.test/film.mkv'}),
      isFalse,
    );
  });

  test('the end of the song with the next one queued is not the end, and '
      'the move to it is told with the new position', () async {
    await backend.play(_song);
    await backend.preloadNext(_next);
    final completed = <bool>[];
    final moved = <void>[];
    final subs = [
      backend.completedStream.listen(completed.add),
      backend.transitionedStream.listen(moved.add),
    ];

    // Waiting at the end for the next song to buffer.
    await tick(180000, playing: false);
    expect(completed, isNot(contains(true)));

    await _send(<String, dynamic>{
      'event': 'transitioned',
      'url': 'https://server.test/b.flac',
      'positionMs': 40,
      'durationMs': 240000,
    });
    await pumpEventQueue();
    expect(moved, hasLength(1));
    expect(backend.position, const Duration(milliseconds: 40));
    expect(backend.duration, const Duration(minutes: 4));

    // Nothing queued any more: the end of this one is the end.
    await _send(<String, dynamic>{
      'event': 'state',
      'positionMs': 240000,
      'durationMs': 240000,
      'isPlaying': false,
    });
    await pumpEventQueue();
    expect(completed, contains(true));
    for (final sub in subs) {
      await sub.cancel();
    }
  });

  test('taking it back tells the native player once', () async {
    await backend.play(_song);
    await backend.preloadNext(_next);
    await backend.cancelPreload();
    await backend.cancelPreload();
    expect(calls.where((c) => c.method == 'cancelNext'), hasLength(1));
  });

  test('the native player letting the queued song go is told once, and the '
      'end of this one is the end again', () async {
    await backend.play(_song);
    await backend.preloadNext(_next);
    final dropped = <bool>[];
    final completed = <bool>[];
    final subs = [
      backend.nextDroppedStream.listen(dropped.add),
      backend.completedStream.listen(completed.add),
    ];

    await _send(<String, dynamic>{'event': 'nextDropped', 'failed': true});
    await _send(<String, dynamic>{'event': 'nextDropped', 'failed': true});
    await pumpEventQueue();
    expect(dropped, [true]);
    // Nothing left to take back.
    await backend.cancelPreload();
    expect(calls.where((c) => c.method == 'cancelNext'), isEmpty);

    await tick(180000, playing: false);
    expect(completed, contains(true));
    for (final sub in subs) {
      await sub.cancel();
    }
  });
}
