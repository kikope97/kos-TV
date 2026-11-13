import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../preference/user_preferences.dart';

/// Kos TV: when the opening animation plays.
///
/// It plays when the app is opened after being closed: the first time, after
/// leaving it on purpose (Back out of Home and Exit, or the screensaver
/// closing it) and after a long time away. It doesn't when the app comes back
/// from the background, not even when the TV had to close it meanwhile to
/// make room for another app (which on a TV happens often, and starts the
/// app afresh), nor when switching user.
abstract final class KostvIntroPolicy {
  static const _lastSeenKey = 'kostv_intro_last_seen_ms';
  static const _closedKey = 'kostv_intro_closed';

  /// Away from the app for longer than this, it opens with the animation again.
  static const longAway = Duration(hours: 6);

  static bool _playsThisLaunch = true;
  static bool _taken = false;
  static AppLifecycleListener? _listener;

  /// Decides, once at start, whether this launch is an opening, and from
  /// then on notes when the app goes to the background.
  static Future<void> init({@visibleForTesting DateTime? now}) async {
    final at = now ?? DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getInt(_lastSeenKey);
      // Opened before (it noted when): an install from when the animation
      // was on by default keeps it on; only a new one starts without it.
      if (lastSeen != null) _keepIntroOn();
      _playsThisLaunch = decide(
        closed: prefs.getBool(_closedKey) ?? false,
        lastSeen: lastSeen == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastSeen),
        now: at,
      );
      // Not waited for: the decision is made, the values are read back from
      // memory, and this sits on the way to the first frame.
      unawaited(prefs.setBool(_closedKey, false).catchError(_writeFailed));
      unawaited(
        prefs
            .setInt(_lastSeenKey, at.millisecondsSinceEpoch)
            .catchError(_writeFailed),
      );
    } catch (e) {
      debugPrint('[KostvIntroPolicy] $e');
      _playsThisLaunch = true;
    }
    _taken = false;
    _listener ??= AppLifecycleListener(onHide: _noteSeen, onPause: _noteSeen);
  }

  static void _keepIntroOn() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<UserPreferences>()) return;
    final prefs = getIt<UserPreferences>();
    if (prefs.containsPreference(UserPreferences.kostvIntroEnabled)) return;
    prefs.set(UserPreferences.kostvIntroEnabled, true);
  }

  static bool _writeFailed(Object e) {
    debugPrint('[KostvIntroPolicy] $e');
    return false;
  }

  /// Whether a launch is an opening: the app was closed on purpose, has never
  /// been opened, or hasn't been seen for [longAway] (or the clock went back).
  @visibleForTesting
  static bool decide({
    required bool closed,
    required DateTime? lastSeen,
    required DateTime now,
  }) =>
      closed ||
      lastSeen == null ||
      now.isBefore(lastSeen) ||
      now.difference(lastSeen) > longAway;

  /// Whether the start screen plays the animation. True at most once a launch,
  /// so a later visit to the start screen (switching user) goes without it.
  static bool takeIntro() {
    if (_taken) return false;
    _taken = true;
    return _playsThisLaunch;
  }

  /// The app is being closed on purpose: it opens with the animation next time.
  static Future<void> markClosed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_closedKey, true);
    } catch (e) {
      debugPrint('[KostvIntroPolicy] $e');
    }
  }

  static void _noteSeen() => unawaited(() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSeenKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }());

  @visibleForTesting
  static void resetForTesting() {
    _listener?.dispose();
    _listener = null;
    _playsThisLaunch = true;
    _taken = false;
  }
}
