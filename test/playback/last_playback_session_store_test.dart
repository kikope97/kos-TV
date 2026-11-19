import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/last_playback_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _session = LastPlaybackSession(
  serverId: 'home',
  itemIds: ['book'],
  index: 0,
  positionMs: 1000,
  title: 'Audiobook',
  isAudiobook: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Kos TV: a headset's Play or Android's resume card after a person switch
  // must not bring back the last person's queue.
  test('only the person who left the queue gets it back', () async {
    String? person = 'adult';
    final store = LastPlaybackSessionStore(currentUserId: () => person);
    await store.save(_session);

    expect((await store.load())?.currentItemId, 'book');
    expect(await store.asRecentMediaItems(), hasLength(1));

    person = 'child';
    expect(await store.load(), isNull);
    expect(await store.asRecentMediaItems(), isEmpty);

    person = null;
    expect(await store.load(), isNull);
  });

  test('a queue saved before it carried its owner is not offered', () async {
    SharedPreferences.setMockInitialValues({
      'last_playback_session':
          '{"serverId":"home","itemIds":["song"],"index":0,'
          '"positionMs":0,"title":"Song"}',
    });
    final store = LastPlaybackSessionStore(currentUserId: () => 'adult');
    expect(await store.load(), isNull);
  });
}
