import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/recent_searches_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the recent searches are each person's, and none in Kids Mode.
void main() {
  late PreferenceStore store;
  var person = 'casa|papa';
  var kids = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // The old list, of everyone on the device.
      'flutter.recent_searches_v1': ['de antes'],
    });
    store = PreferenceStore();
    await store.init();
    person = 'casa|papa';
    kids = false;
  });

  RecentSearchesStore create() =>
      RecentSearchesStore(store, scope: () => person, paused: () => kids);

  test('one person never sees what another searched', () async {
    final recent = create();
    expect(recent.recent, isEmpty, reason: 'the shared list is dropped');

    await recent.add('terror');
    expect(recent.recent, ['terror']);

    person = 'casa|nino';
    expect(recent.recent, isEmpty);
    await recent.add('dibujos');
    expect(recent.recent, ['dibujos']);

    person = 'casa|papa';
    expect(recent.recent, ['terror']);
  });

  test('in Kids Mode nothing is kept or offered', () async {
    final recent = create();
    await recent.add('terror');
    kids = true;
    expect(recent.recent, isEmpty);
    await recent.add('dibujos');
    kids = false;
    expect(recent.recent, ['terror']);
  });
}
