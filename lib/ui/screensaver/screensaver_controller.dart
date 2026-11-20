import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:playback_core/playback_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/models/aggregated_item.dart';
import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../../util/app_exit.dart';
import '../../util/platform_detection.dart';

class ScreensaverController {
  ScreensaverController(this._prefs, this._playbackManager) {
    _idleSince = clock.now();
    _lastInputAt = _idleSince;
    _listenForInput();
    if (PlatformDetection.isTV) {
      _enabledCache = _prefs.get(UserPreferences.screensaverEnabled);
      _timeoutCache = _prefs.get(UserPreferences.screensaverTimeout);
      _sleepAfterCache = _prefs.get(UserPreferences.sleepAfterIdle);
      _duringAudioCache = _prefs.get(UserPreferences.screensaverDuringAudio);
      _playingSub = _playbackManager.state.playingStream.listen(
        _onPlayingChanged,
      );
      _prefs.addListener(_onPrefsChanged);
      _restartIdleTimer();
      _restartSleepTimer();
    }
    visible.addListener(refreshWakeLock);
    _refreshWakeLock();
  }

  final UserPreferences _prefs;
  final PlaybackManager _playbackManager;

  @visibleForTesting
  Future<void> Function() exitApp = AppExit.closeApp;

  /// Apple discourages apps quitting themselves, so on Apple TV the screen
  /// goes back to tvOS's own screensaver and sleep while Moonfin stays open.
  @visibleForTesting
  bool handBackInsteadOfExit = PlatformDetection.isAppleTV;

  @visibleForTesting
  bool get holdsScreenOn => _wakeLockEnabled;

  final ValueNotifier<bool> visible = ValueNotifier(false);

  StreamSubscription<bool>? _playingSub;
  Timer? _idleTimer;
  Timer? _sleepTimer;
  int _sleepAfterCache = 0;
  bool _screenHandedBack = false;
  bool _duringAudioCache = false;
  final Set<LogicalKeyboardKey> _consumedKeys = {};
  bool _enabledCache = false;
  ScreensaverTimeout _timeoutCache = ScreensaverTimeout.m5;
  bool _activityPaused = false;
  bool _playbackActive = false;
  bool _streamPlaying = false;
  bool _trailerActive = false;
  bool _homePreviewActive = false;
  bool _nativePlayerPresented = false;
  bool _wakeLockEnabled = false;

  /// Kos TV: what the screensaver's wait counts from: the last press of the
  /// remote, or the last change that isn't a preview (main playback, the app
  /// coming back…). A preview starting or ending doesn't count, or the
  /// banner, putting on one trailer after another, would keep a TV nobody is
  /// watching from ever showing the screensaver or going to sleep.
  late DateTime _idleSince;

  /// Kos TV: the last real input (remote, keys, touch or pointer), on every
  /// platform, for how long a banner trailer may hold the screen on.
  late DateTime _lastInputAt;
  Timer? _trailerHoldTimer;
  bool _listeningForInput = false;

  /// Kos TV: how long after the last input a banner trailer, which starts on
  /// its own, still keeps the screen on. Past it the system's own screen
  /// timeout applies, so a banner cycling trailers all night lets the screen
  /// go. A card preview, started by the person, holds it as before.
  static const bannerTrailerHoldsScreenFor = Duration(minutes: 15);

  bool get activityPaused => _activityPaused;

  set activityPaused(bool value) {
    if (_activityPaused == value) return;
    _activityPaused = value;
    _refreshWakeLock();
    _onStateChanged();
  }

  void setPlaybackActive(bool value) {
    if (_playbackActive == value) return;
    _playbackActive = value;
    _refreshWakeLock();
    _onStateChanged();
  }

  /// Apple TV presents its player over the Flutter view, so our screensaver
  /// would draw underneath it and never be seen. While it is up the screen is
  /// left to tvOS, which means nothing is armed here and a paused player
  /// releases the idle timer so the system screensaver and sleep still work.
  void setNativePlayerPresented(bool value) {
    if (_nativePlayerPresented == value) return;
    _nativePlayerPresented = value;
    _refreshWakeLock();
    _onStateChanged();
  }

  void setMediaBarTrailerActive(bool value) {
    if (_trailerActive == value) return;
    _trailerActive = value;
    _refreshWakeLock();
    _onStateChanged(preview: true);
  }

  /// A home card's preview, which can be a full trailer.
  void setHomePreviewActive(bool value) {
    if (_homePreviewActive == value) return;
    _homePreviewActive = value;
    _refreshWakeLock();
    _onStateChanged(preview: true);
  }

  bool get _armed =>
      PlatformDetection.isTV &&
      _enabledCache &&
      !_activityPaused &&
      !_playbackActive &&
      (!_streamPlaying || (_duringAudioCache && _playingAudio)) &&
      !_trailerActive &&
      !_homePreviewActive &&
      !_nativePlayerPresented;

  bool get _playingAudio {
    final item = _playbackManager.queueService.currentItem;
    return item is AggregatedItem && item.isAudioLike;
  }

  void notifyInteraction() {
    _noteInput();
    if (!PlatformDetection.isTV || visible.value) return;
    _idleSince = clock.now();
    _restartSleepTimer();
    if (_armed) {
      _restartIdleTimer();
    } else {
      _idleTimer?.cancel();
    }
  }

  void dismiss() {
    _noteInput();
    if (visible.value) {
      visible.value = false;
    }
    _restartIdleTimer();
    _restartSleepTimer();
  }

  /// Kos TV: every input reaches here, on top of what the app reports
  /// through [notifyInteraction], so a phone or the web know it too.
  void _listenForInput() {
    try {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
      HardwareKeyboard.instance.addHandler(_onKey);
      _listeningForInput = true;
    } catch (_) {
      // No binding (a bare unit test): nothing to hear.
    }
  }

  void _onPointer(PointerEvent event) => _noteInput();

  bool _onKey(KeyEvent event) {
    _noteInput();
    return false;
  }

  void _noteInput() {
    _lastInputAt = clock.now();
    // A trailer that had let the screen go holds it again.
    if (_trailerActive && _trailerHoldTimer == null) _refreshWakeLock();
  }

  bool get _bannerTrailerHoldsScreen =>
      _trailerActive &&
      clock.now().difference(_lastInputAt) < bannerTrailerHoldsScreenFor;

  /// Looks again when a banner trailer's hold on the screen runs out.
  void _scheduleTrailerHoldCheck() {
    _trailerHoldTimer?.cancel();
    _trailerHoldTimer = null;
    if (!_trailerActive) return;
    final left =
        bannerTrailerHoldsScreenFor - clock.now().difference(_lastInputAt);
    if (left <= Duration.zero) return;
    _trailerHoldTimer = Timer(left, () {
      _trailerHoldTimer = null;
      _refreshWakeLock();
    });
  }

  bool dismissIfVisible() {
    if (!visible.value) return false;
    dismiss();
    return true;
  }

  bool handleKeyEvent(KeyEvent event) {
    if (!visible.value) {
      if (event is KeyDownEvent) {
        notifyInteraction();
      }
      return false;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _consumedKeys.add(event.logicalKey);
      dismiss();
      return true;
    }
    return _consumedKeys.remove(event.logicalKey);
  }

  void _onPlayingChanged(bool playing) {
    if (_streamPlaying == playing) return;
    _streamPlaying = playing;
    _refreshWakeLock();
    _onStateChanged();
  }

  void _onPrefsChanged() {
    final enabled = _prefs.get(UserPreferences.screensaverEnabled);
    final timeout = _prefs.get(UserPreferences.screensaverTimeout);
    final sleepAfter = _prefs.get(UserPreferences.sleepAfterIdle);
    final duringAudio = _prefs.get(UserPreferences.screensaverDuringAudio);
    if (enabled == _enabledCache &&
        timeout == _timeoutCache &&
        sleepAfter == _sleepAfterCache &&
        duringAudio == _duringAudioCache) {
      return;
    }
    _enabledCache = enabled;
    _timeoutCache = timeout;
    _sleepAfterCache = sleepAfter;
    _duringAudioCache = duringAudio;
    _refreshWakeLock();
    _onStateChanged();
  }

  /// [preview] marks a trailer or card preview starting or ending, which
  /// neither starts the waits over nor gives the screensaver a full wait
  /// again: once the preview is over, it comes after what is left of it, or
  /// at once if that has run out meanwhile.
  void _onStateChanged({bool preview = false}) {
    if (!PlatformDetection.isTV) return;
    if (!preview) {
      _idleSince = clock.now();
      _restartSleepTimer();
    }
    if (!_armed) {
      _idleTimer?.cancel();
      if (visible.value) {
        visible.value = false;
      }
      return;
    }
    if (!visible.value) {
      _scheduleIdleTimer();
    }
  }

  void _restartIdleTimer() {
    _idleSince = clock.now();
    _scheduleIdleTimer();
  }

  void _scheduleIdleTimer() {
    _idleTimer?.cancel();
    if (!_armed) return;
    final left =
        Duration(minutes: _timeoutCache.minutes) -
        clock.now().difference(_idleSince);
    _idleTimer = Timer(left.isNegative ? Duration.zero : left, () {
      if (_armed && !visible.value) {
        visible.value = true;
      }
    });
  }

  static bool get sleepAfterIdleSupported =>
      PlatformDetection.isTV &&
      (PlatformDetection.isAndroid || PlatformDetection.isAppleTV);

  /// A paused player counts as idle too, since it holds the screen on just
  /// like the screensaver does.
  bool get _sleepArmed =>
      sleepAfterIdleSupported &&
      _sleepAfterCache > 0 &&
      !_activityPaused &&
      !_streamPlaying;

  void _restartSleepTimer() {
    _sleepTimer?.cancel();
    if (_screenHandedBack) {
      _screenHandedBack = false;
      _refreshWakeLock();
    }
    if (!_sleepArmed) return;
    _sleepTimer = Timer(
      Duration(minutes: _sleepAfterCache),
      () => unawaited(_letTvSleep()),
    );
  }

  Future<void> _letTvSleep() async {
    if (!_sleepArmed) return;
    if (handBackInsteadOfExit) {
      _screenHandedBack = true;
      _refreshWakeLock();
      return;
    }
    if (_playbackManager.queueService.currentItem != null) {
      await _playbackManager.stop(userInitiated: false);
      await _playbackManager.lastStopReport.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    }
    await exitApp();
  }

  static const _systemChannel = MethodChannel('moonfin/appletv_system');

  Future<void> _setWakeLockEnabled(bool enabled) async {
    try {
      if (PlatformDetection.isAppleTV) {
        await _systemChannel.invokeMethod('setIdleTimerDisabled', enabled);
      } else if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  @visibleForTesting
  static bool wakeLockNeeded({
    required bool activityPaused,
    required bool playbackActive,
    required bool streamPlaying,
    required bool trailerActive,
    required bool screensaverVisible,
    required bool isTv,
    required bool screensaverEnabled,
    required bool nativePlayerPresented,
  }) {
    if (activityPaused) return false;
    return playbackActive ||
        streamPlaying ||
        trailerActive ||
        screensaverVisible ||
        (isTv && screensaverEnabled && !nativePlayerPresented);
  }

  // Browsers only offer a wake lock in a secure context. Without one
  // wakelock_plus plays a hidden video with sound instead, and iOS pauses our
  // own video or music to play it.
  static bool get _wakeLockWouldPauseMedia {
    if (!kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    final page = Uri.base;
    return page.scheme != 'https' &&
        !const {'localhost', '127.0.0.1', '::1'}.contains(page.host);
  }

  void _refreshWakeLock({bool force = false}) {
    final shouldEnable =
        !_wakeLockWouldPauseMedia &&
        !_screenHandedBack &&
        wakeLockNeeded(
          activityPaused: _activityPaused,
          playbackActive: _playbackActive,
          streamPlaying: _streamPlaying,
          trailerActive: _bannerTrailerHoldsScreen || _homePreviewActive,
          screensaverVisible: visible.value,
          isTv: PlatformDetection.isTV,
          screensaverEnabled: _enabledCache,
          nativePlayerPresented: _nativePlayerPresented,
        );
    _scheduleTrailerHoldCheck();
    if (_wakeLockEnabled == shouldEnable && !force) {
      return;
    }
    _wakeLockEnabled = shouldEnable;
    unawaited(_setWakeLockEnabled(shouldEnable));
  }

  void refreshWakeLock() {
    _refreshWakeLock(force: true);
  }

  void dispose() {
    visible.removeListener(refreshWakeLock);
    _playingSub?.cancel();
    _idleTimer?.cancel();
    _sleepTimer?.cancel();
    _trailerHoldTimer?.cancel();
    _trailerHoldTimer = null;
    if (_listeningForInput) {
      _listeningForInput = false;
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    _prefs.removeListener(_onPrefsChanged);
    _wakeLockEnabled = false;
    unawaited(_setWakeLockEnabled(false));
  }
}
