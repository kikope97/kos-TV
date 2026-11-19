import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../preference/user_preferences.dart';
import 'destinations.dart';
import 'route_gates.dart';

/// Kos TV: the router's Kids Mode gate only runs on navigating, so a page it
/// blocks that was already open (Discover, Music, Apps, the Live TV guide,
/// with Settings opened over it to turn the mode on) would stay there in
/// use. This takes the person to Home as the mode goes on.
///
/// It reads the router's whole stack, not its address: on a TV or a phone
/// menu pages are pushed over Home and the address stays on /home. While
/// Settings is open (the mode is turned on from there) it waits for the
/// panel to close, so the panel isn't torn away mid PIN.
class KidsModePageGuard {
  KidsModePageGuard({
    required this.prefs,
    required this.router,
    required this.settingsOpen,
  }) {
    _wasOn = _kidsMode;
    prefs.addListener(_onPrefsChanged);
  }

  final UserPreferences prefs;
  final GoRouter router;

  /// Whether Settings is open over the page.
  final ValueListenable<bool> settingsOpen;
  late bool _wasOn;
  bool _waitingForSettings = false;

  bool get _kidsMode => prefs.get(UserPreferences.kidsModeEnabled);

  void _onPrefsChanged() {
    final on = _kidsMode;
    if (on == _wasOn) return;
    _wasOn = on;
    if (on) _leaveBlockedPages();
  }

  void _leaveBlockedPages() {
    if (settingsOpen.value) {
      if (_waitingForSettings) return;
      _waitingForSettings = true;
      settingsOpen.addListener(_onSettingsOpenChanged);
      return;
    }
    if (!_kidsMode) return;
    final matches = router.routerDelegate.currentConfiguration.matches;
    if (matches.any((m) => kidsModeClosesPath(m.matchedLocation))) {
      router.go(Destinations.home);
    }
  }

  void _onSettingsOpenChanged() {
    if (settingsOpen.value) return;
    _stopWaiting();
    _leaveBlockedPages();
  }

  void _stopWaiting() {
    if (!_waitingForSettings) return;
    _waitingForSettings = false;
    settingsOpen.removeListener(_onSettingsOpenChanged);
  }

  void dispose() {
    prefs.removeListener(_onPrefsChanged);
    _stopWaiting();
  }
}
