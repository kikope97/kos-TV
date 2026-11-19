import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kos TV: clearing a person's track choice only leaves a mark behind when a
// choice kept for the whole device would otherwise come back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const signedIn = {
    'pref_last_server_id': 'srv1',
    'pref_last_user_id': 'user1',
  };

  Future<(UserPreferences, PreferenceStore)> open(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
    final store = PreferenceStore();
    await store.init();
    return (UserPreferences(store), store);
  }

  test('clearing with nothing kept for the device leaves no key', () async {
    final (prefs, store) = await open({...signedIn});

    await prefs.setItemSubtitleStreamIndex('item1', null);
    await prefs.setItemAudioStreamIndex('item1', null);

    expect(store.keys.where((k) => k.startsWith('pref_item_')), isEmpty);
    expect(prefs.getItemSubtitleStreamIndex('item1'), -2);
  });

  test('clearing over a device-wide choice still hides it', () async {
    final (prefs, store) = await open({
      ...signedIn,
      'pref_item_subtitle_index_item1': 3,
    });

    await prefs.setItemSubtitleStreamIndex('item1', null);

    expect(prefs.getItemSubtitleStreamIndex('item1'), -2);
    expect(
      store.containsKey('pref_item_subtitle_index_srv1_user1_item1'),
      isTrue,
    );
  });

  test('clearing a choice of its own removes it', () async {
    final (prefs, store) = await open({...signedIn});

    await prefs.setItemSubtitleStreamIndex('item1', 2);
    expect(prefs.getItemSubtitleStreamIndex('item1'), 2);
    await prefs.setItemSubtitleStreamIndex('item1', null);

    expect(prefs.getItemSubtitleStreamIndex('item1'), -2);
    expect(
      store.containsKey('pref_item_subtitle_index_srv1_user1_item1'),
      isFalse,
    );
  });

  test('marks written before with nothing to hide go once at start', () async {
    final (prefs, store) = await open({
      ...signedIn,
      // Nothing for the device behind these.
      'pref_item_subtitle_index_srv1_user1_item1': -3,
      'pref_item_audio_index_srv1_user1_item1': -3,
      // This one still hides a device-wide choice.
      'pref_item_subtitle_index_srv1_user1_item2': -3,
      'pref_item_subtitle_index_item2': 4,
      // A real choice is never touched.
      'pref_item_audio_index_srv1_user1_item3': 1,
    });

    expect(
      store.containsKey('pref_item_subtitle_index_srv1_user1_item1'),
      isFalse,
    );
    expect(
      store.containsKey('pref_item_audio_index_srv1_user1_item1'),
      isFalse,
    );
    expect(
      store.containsKey('pref_item_subtitle_index_srv1_user1_item2'),
      isTrue,
    );
    expect(prefs.getItemSubtitleStreamIndex('item2'), -2);
    expect(prefs.getItemAudioStreamIndex('item3'), 1);
  });
}
