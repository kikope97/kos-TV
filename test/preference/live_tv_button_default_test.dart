import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/live_tv_library.dart';

AggregatedLibrary _lib(String id, String type) =>
    AggregatedLibrary(id: id, name: id, collectionType: type, serverId: 's1');

void main() {
  test('the live tv button starts on for whoever starts afresh', () {
    // Kos TV: the channels the home server has are in sight. The button only
    // shows when the server offers Live TV, and a value already saved stays.
    expect(UserPreferences.showLiveTvButton.defaultValue, isTrue);
    expect(UserPreferences.showLiveTvButton.key, 'pref_show_live_tv_button');
  });

  test('the guide is still reachable with the button off', () {
    // Turning the button off puts the library tile back rather than taking
    // Live TV out of the nav, so there is always exactly one way in.
    final libraries = [_lib('movies', 'movies'), _lib('guide', 'livetv')];

    expect(
      librariesForNav(libraries, false).map((lib) => lib.id),
      ['movies', 'guide'],
    );
  });
}
