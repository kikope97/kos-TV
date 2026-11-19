import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/synced_fields.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kos TV: the one-time move from the old default details page (Frost on a TV,
// Modern on a phone) to the kOS TV page must never undo a style picked by hand.

late PreferenceStore _store;

Future<UserPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'pref_last_server_id': 'srv1',
    'pref_last_user_id': 'usr1',
  });
  _store = PreferenceStore();
  await _store.init();
  return UserPreferences(_store);
}

/// Writes [value] the way an apply from the server profile does: straight to
/// the store, never through [UserPreferences.set].
Future<void> _fromServer<T>(
  UserPreferences prefs,
  Preference<T> pref,
  T value,
) => _store.set(prefs.getEffectivePreference(pref), value);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('an old default still moves to the kOS TV page once', () async {
    final prefs = await _prefs();
    await _fromServer(
      prefs,
      UserPreferences.detailScreenStyle,
      DetailScreenStyle.frost,
    );

    expect(prefs.effectiveDetailScreenStyle, DetailScreenStyle.kostv);
    await _settle();
    expect(
      prefs.get(UserPreferences.detailScreenStyle),
      DetailScreenStyle.kostv,
    );
    expect(prefs.get(UserPreferences.kostvDetailAdopted), isTrue);
  });

  test('a style picked before opening any page is kept', () async {
    final prefs = await _prefs();
    await prefs.set(
      UserPreferences.detailScreenStyle,
      DetailScreenStyle.modern,
    );

    expect(prefs.get(UserPreferences.kostvDetailAdopted), isTrue);
    expect(prefs.effectiveDetailScreenStyle, DetailScreenStyle.modern);
    await _settle();
    expect(
      prefs.get(UserPreferences.detailScreenStyle),
      DetailScreenStyle.modern,
    );
  });

  test(
    'a picked style that arrives with its mark is not moved again',
    () async {
      // A new phone or browser reading what the TV chose by hand.
      final prefs = await _prefs();
      await _fromServer(
        prefs,
        UserPreferences.detailScreenStyle,
        DetailScreenStyle.frost,
      );
      await _fromServer(prefs, UserPreferences.kostvDetailAdopted, true);

      expect(prefs.effectiveDetailScreenStyle, DetailScreenStyle.frost);
      await _settle();
      expect(
        prefs.get(UserPreferences.detailScreenStyle),
        DetailScreenStyle.frost,
      );
    },
  );

  test('the mark syncs next to the style', () {
    final field = syncedFields.singleWhere(
      (f) => f.pref == UserPreferences.kostvDetailAdopted,
    );
    expect(field.serverKey, 'kostvDetailAdopted');
    expect(field.codec, SyncCodec.boolean);
    expect(field.receiveOnly, isFalse);
  });
}
