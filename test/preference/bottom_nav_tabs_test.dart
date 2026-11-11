import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/bottom_nav_tabs.dart';
import 'package:moonfin/preference/preference_constants.dart';
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

  group('parsePinnedBottomNavTabs', () {
    test('reads names case-insensitively and ignores whitespace', () {
      expect(
        parsePinnedBottomNavTabs(' Search , LIVETV,Favorites'),
        [BottomNavTab.search, BottomNavTab.liveTv, BottomNavTab.favorites],
      );
    });

    test('drops a folders pin, which the bar no longer offers', () {
      expect(
        parsePinnedBottomNavTabs('search,folders,liveTv'),
        [BottomNavTab.search, BottomNavTab.liveTv],
      );
    });

    test('drops unknown names and duplicates', () {
      expect(
        parsePinnedBottomNavTabs('podcasts,favorites,favorites,,genres'),
        [BottomNavTab.favorites, BottomNavTab.genres],
      );
    });

    test('keeps at most three', () {
      expect(
        parsePinnedBottomNavTabs('search,libraries,favorites,genres'),
        hasLength(kMaxPinnedBottomNavTabs),
      );
    });

    test('round-trips through serialize', () {
      const tabs = [BottomNavTab.kostvDiscover, BottomNavTab.search];
      expect(
        parsePinnedBottomNavTabs(serializePinnedBottomNavTabs(tabs)),
        tabs,
      );
    });

    test('empty or all-unknown lists count as automatic', () {
      expect(isAutomaticBottomNavTabs(''), isTrue);
      expect(isAutomaticBottomNavTabs('podcasts,radio'), isTrue);
      expect(isAutomaticBottomNavTabs('search'), isFalse);
    });
  });

  group('automatic pins', () {
    test('default settings pin Search, Libraries and Favorites', () {
      expect(const BottomNavTabGates().resolvePins(''), [
        BottomNavTab.search,
        BottomNavTab.libraries,
        BottomNavTab.favorites,
      ]);
    });

    test('a turned off button is skipped for the next offered tab', () {
      const gates = BottomNavTabGates(showFavorites: false, showLiveTv: true);
      expect(gates.resolvePins(''), [
        BottomNavTab.search,
        BottomNavTab.libraries,
        BottomNavTab.liveTv,
      ]);
    });

    test('Kids Mode leaves out Libraries and Live TV', () {
      const gates = BottomNavTabGates(kidsMode: true, showLiveTv: true);
      expect(gates.resolvePins(''), [
        BottomNavTab.search,
        BottomNavTab.favorites,
        BottomNavTab.genres,
      ]);
    });
  });

  group('Kos TV: Discover', () {
    test('takes the second slot for someone the requests service lets in', () {
      const gates = BottomNavTabGates(kostvDiscoverAvailable: true);
      expect(gates.resolvePins(''), [
        BottomNavTab.search,
        BottomNavTab.kostvDiscover,
        BottomNavTab.libraries,
      ]);
    });

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

    test('its pin is stored by name', () {
      expect(parsePinnedBottomNavTabs('kostvDiscover,search'), [
        BottomNavTab.kostvDiscover,
        BottomNavTab.search,
      ]);
    });
  });

  group('explicit pins', () {
    test('keep their order', () {
      expect(const BottomNavTabGates().resolvePins('favorites,search'), [
        BottomNavTab.favorites,
        BottomNavTab.search,
      ]);
    });

    test('drop a tab that is no longer offered without topping up', () {
      const gates = BottomNavTabGates(showGenres: false);
      expect(gates.resolvePins('genres,search'), [BottomNavTab.search]);
    });

    test('Calendar needs the plugin, its button and no Kids Mode', () {
      const off = BottomNavTabGates();
      const on = BottomNavTabGates(calendarAvailable: true);
      expect(off.resolvePins('calendar,search'), [BottomNavTab.search]);
      expect(on.resolvePins('calendar,search'), [
        BottomNavTab.calendar,
        BottomNavTab.search,
      ]);
      expect(
        const BottomNavTabGates(calendarAvailable: true, showCalendar: false)
            .resolvePins('calendar'),
        isEmpty,
      );
      expect(
        const BottomNavTabGates(calendarAvailable: true, kidsMode: true)
            .offers(BottomNavTab.calendar),
        isFalse,
      );
      // It never takes an automatic slot ahead of the older tabs.
      expect(on.resolvePins(''), isNot(contains(BottomNavTab.calendar)));
    });
  });

  group('upgrading from the old bottom navbar', () {
    const signedIn = {
      'pref_last_server_id': 'srv',
      'pref_last_user_id': 'usr',
      'pref_navbar_position_srv_usr': 'bottom',
      'pref_show_favorites_button_srv_usr': false,
    };

    test('lands on Dock with pins from the toggles and writes nothing',
        () async {
      final store = await _store(signedIn);
      final prefs = UserPreferences(store);

      expect(prefs.get(UserPreferences.navbarPosition), NavbarPosition.bottom);
      expect(prefs.get(UserPreferences.bottomNavbarStyle),
          BottomNavbarStyle.dock);

      final gates = BottomNavTabGates.fromPreferences(prefs);
      expect(gates.resolvePins(prefs.get(UserPreferences.bottomNavbarTabs)), [
        BottomNavTab.search,
        BottomNavTab.libraries,
        BottomNavTab.genres,
      ]);

      // Other constructor steps seed their own keys, so only the navbar's
      // own keys are checked.
      expect(
        store.keys.where((k) => k.startsWith('pref_bottom_navbar')),
        isEmpty,
      );
      expect(prefs.containsPreference(UserPreferences.bottomNavbarStyle),
          isFalse);
      expect(prefs.containsPreference(UserPreferences.bottomNavbarTabs),
          isFalse);
    });

    test('both new preferences are stored per server and user', () async {
      final store = await _store(signedIn);
      final prefs = UserPreferences(store);

      await prefs.set(UserPreferences.bottomNavbarStyle,
          BottomNavbarStyle.strip);
      await prefs.set(UserPreferences.bottomNavbarTabs, 'search');

      expect(store.getString('pref_bottom_navbar_style_srv_usr'), 'strip');
      expect(store.getString('pref_bottom_navbar_tabs_srv_usr'), 'search');
    });
  });
}
