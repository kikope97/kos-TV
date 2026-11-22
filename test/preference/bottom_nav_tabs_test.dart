import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/bottom_nav_tabs.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PreferenceStore> _store([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final store = PreferenceStore();
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Kos TV: the glass bar's tabs (docs/diseno-menu): Inicio · Descubrir ·
  // Música · Tú, with Search on a round button of its own. The tabs aren't
  // a setting: where Descubrir or Música isn't offered, the next destination
  // on offer takes its place.
  group('the glass bar\'s tabs', () {
    test('Descubrir and Música for someone the requests service lets in', () {
      const gates = BottomNavTabGates(kostvDiscoverAvailable: true);
      expect(gates.barTabs(), [
        BottomNavTab.kostvDiscover,
        BottomNavTab.kostvMusic,
      ]);
    });

    test('without Discover, Libraries comes after Música', () {
      expect(const BottomNavTabGates().barTabs(), [
        BottomNavTab.kostvMusic,
        BottomNavTab.libraries,
      ]);
    });

    test('Search and Favorites are never tabs', () {
      const gates = BottomNavTabGates(
        kostvDiscoverAvailable: true,
        showKostvMusic: false,
        showLibraries: false,
        showGenres: false,
      );
      expect(gates.barTabs(), isNot(contains(BottomNavTab.search)));
      expect(gates.barTabs(), isNot(contains(BottomNavTab.favorites)));
    });

    test('Kids Mode leaves out Discover, Music, Libraries and Live TV', () {
      const gates = BottomNavTabGates(
        kidsMode: true,
        showLiveTv: true,
        kostvDiscoverAvailable: true,
        kostvMyListAvailable: true,
      );
      expect(gates.barTabs(), [BottomNavTab.myList, BottomNavTab.genres]);
    });

    test('a destination without its data is skipped for the next one', () {
      const gates = BottomNavTabGates(showKostvMusic: false);
      expect(
        gates.barTabs(isAvailable: (t) => t != BottomNavTab.libraries),
        [BottomNavTab.genres],
      );
    });
  });

  group('Kos TV: Discover', () {
    test('is not offered without access, in Kids Mode or switched off', () {
      expect(
        const BottomNavTabGates().offers(BottomNavTab.kostvDiscover),
        isFalse,
      );
      expect(
        const BottomNavTabGates(kostvDiscoverAvailable: true, kidsMode: true)
            .offers(BottomNavTab.kostvDiscover),
        isFalse,
      );
      expect(
        const BottomNavTabGates(
          kostvDiscoverAvailable: true,
          showKostvDiscover: false,
        ).offers(BottomNavTab.kostvDiscover),
        isFalse,
      );
    });
  });

  test('Calendar needs the plugin, its button and no Kids Mode', () {
    expect(const BottomNavTabGates().offers(BottomNavTab.calendar), isFalse);
    expect(
      const BottomNavTabGates(calendarAvailable: true)
          .offers(BottomNavTab.calendar),
      isTrue,
    );
    expect(
      const BottomNavTabGates(calendarAvailable: true, showCalendar: false)
          .offers(BottomNavTab.calendar),
      isFalse,
    );
    expect(
      const BottomNavTabGates(calendarAvailable: true, kidsMode: true)
          .offers(BottomNavTab.calendar),
      isFalse,
    );
  });

  // Kos TV: the old menu's choices (position, bottom style, pinned tabs,
  // colour, opacity, labels) are gone; values stored by an older version
  // are left where they are, read by nothing, and change nothing.
  test('values the old menu stored are ignored harmlessly', () async {
    final store = await _store({
      'pref_last_server_id': 'srv',
      'pref_last_user_id': 'usr',
      'pref_navbar_position_srv_usr': 'left',
      'pref_bottom_navbar_style_srv_usr': 'strip',
      'pref_bottom_navbar_tabs_srv_usr': 'favorites,calendar,search',
      'navbarColor_srv_usr': 'purple',
      'navbarOpacity_srv_usr': 10,
      'pref_navbar_always_expanded_srv_usr': true,
      'pref_glass_quality_srv_usr': 'full',
      'pref_kostv_discover_available': true,
    });
    final prefs = UserPreferences(store);
    final gates = BottomNavTabGates.fromPreferences(
      prefs,
      kostvDiscoverAvailable: true,
    );
    expect(gates.barTabs(), [
      BottomNavTab.kostvDiscover,
      BottomNavTab.kostvMusic,
    ]);
  });
}
