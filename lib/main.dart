import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moonfin_design/moonfin_design.dart' show LiquidGlassWidgets;
import 'package:playback_core/playback_core.dart';

import 'app.dart';
import 'data/models/aggregated_item.dart';
import 'background/watch_next_background.dart' as watch_next_bg;
import 'data/services/carplay_service.dart';
import 'data/services/cast/airplay_command_bridge.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'background/auto_download_background.dart';
import 'background/auto_download_background_main.dart' as auto_download_bg;
import 'data/services/auto_download_service.dart';
import 'data/services/background_download_coordinator.dart';
import 'data/services/download_notification_service.dart';
import 'data/services/push_messaging_service.dart';
import 'data/services/media_server_client_factory.dart';
import 'data/services/crash_report_service.dart';
import 'data/services/log_service.dart';
import 'data/services/storage_path_service.dart';
import 'util/kostv_intro_policy.dart';
import 'util/kostv_server.dart';
import 'util/scroll_sensitivity_binding.dart';
import 'util/silo_image_hooks.dart';
import 'data/services/theme_store_service.dart';
import 'di/injection.dart';
import 'playback/appletv_audio_now_playing_feeder.dart';
import 'playback/native_apple_player_backend.dart';
import 'playback/audio_capability_probe.dart';
import 'playback/audio_handler.dart';
import 'playback/codec_caps_repair.dart';
import 'playback/device_capability_cache.dart';
import 'playback/display_hdr_probe.dart';
import 'playback/media_browse_service.dart';
import 'playback/playback_lifecycle_handler.dart';
import 'playback/subtitle_fonts.dart';
import 'platform/background_refresh.dart';
import 'platform/web_runtime_config.dart';
import 'preference/preference_constants.dart';
import 'preference/user_preferences.dart';
import 'util/idiom/glass_capability.dart';
import 'util/http_overrides_stub.dart'
    if (dart.library.io) 'util/http_overrides_io.dart';
import 'util/game_core_licenses.dart';
import 'util/device_performance.dart';
import 'ui/navigation/app_router.dart';
import 'ui/screens/auth/startup_failure_screen.dart';
import 'ui/screensaver/screensaver_controller.dart';
import 'ui/widgets/reader/epub_js_view.dart';
import 'util/platform_detection.dart';
import 'util/process_exit_reporter.dart';
import 'util/system_ui.dart';
import 'util/tv_image_cache_stub.dart'
    if (dart.library.io) 'util/tv_image_cache_io.dart';

DateTime? _lastIosRouteResync;

/// iOS-only audio route handling: observe output route changes to (a) pause when
/// the current output device disappears (AirPods removed, cable unplugged) and
/// (b) re-sync A/V when the output switches mid-playback (a new device connects,
/// or AirPlay/HomePod is selected), which otherwise leaves the player writing
/// to a stale clock and drifts audio out of sync.
void _attachIosAudioRouteHandling() {
  final session = AVAudioSession();
  session.routeChangeStream.listen((change) async {
    final manager = GetIt.instance<PlaybackManager>();
    switch (change.reason) {
      case AVAudioSessionRouteChangeReason.oldDeviceUnavailable:
        manager.pause();
        break;
      case AVAudioSessionRouteChangeReason.newDeviceAvailable:
      case AVAudioSessionRouteChangeReason.override:
        if (!manager.state.isPlaying) return;
        final now = DateTime.now();
        final last = _lastIosRouteResync;
        if (last != null &&
            now.difference(last) < const Duration(milliseconds: 500)) {
          return;
        }
        _lastIosRouteResync = now;
        // A same-position seek re-primes the player's audio/video clock without
        // an audible pause, realigning A/V after the output switch.
        await manager.seekTo(manager.state.position);
        break;
      default:
        break;
    }
  });
}

/// What this device can afford. Its callers size themselves before dependency
/// injection runs, so it works off [_startupPerformanceMode] rather than off
/// UserPreferences.
DevicePerformanceTier _resolvedTier() => resolveDevicePerformanceTierFor(
  _startupPerformanceMode,
  PlatformDetection.deviceMemory,
);

// The entry counts are generous on purpose: a library grid shows dozens of
// posters at once, so a small count evicts them after about two screenfuls and
// scrolling back re-decodes everything. maximumSizeBytes is what really bounds
// memory here.
void _configureImageCache() {
  final imageCache = PaintingBinding.instance.imageCache;
  final tier = _resolvedTier();
  void apply(int entries, int bytes) {
    imageCache.maximumSize = entries;
    imageCache.maximumSizeBytes = imageCacheBytesFor(tier, bytes);
  }

  if (PlatformDetection.isWeb) {
    apply(400, 96 << 20);
    return;
  }
  if (PlatformDetection.isMobile) {
    apply(400, 120 << 20);
    return;
  }

  if (PlatformDetection.isTV) {
    apply(500, 96 << 20);
    return;
  }

  apply(600, 256 << 20);
}

/// The TV builds draw with Skia, which sizes its GPU cache from the screen, and
/// Impeller builds ignore this call. It waits for the first frame so the view
/// has its real size.
void _capSkiaCache() {
  if (!PlatformDetection.isAndroid) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final size = WidgetsBinding.instance.platformDispatcher.implicitView
        ?.physicalSize;
    final cap = size == null ? null : skiaCacheCapFor(size.width * size.height);
    if (cap == null) return;
    unawaited(
      SystemChannels.skia
          .invokeMethod<void>('Skia.setResourceCacheMaxBytes', cap)
          .catchError((_) {}),
    );
  });
}

Timer? _crashFlushDebounce;

/// Routes uncaught Dart errors into the diagnostic buffer and the pending
/// crash store. Both handlers keep the console output they replace.
///
/// Kos TV: what they print goes without credentials. A URL in an error can
/// carry the session's token (`api_key=`, `ApiKey=`), and these lines reach
/// logcat or the browser console in release builds too.
void _installCrashHandlers() {
  FlutterError.onError = (details) {
    _presentErrorRedacted(details);
    _captureCrash(details.exception, details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    // Returning true marks the error handled, which drops the engine's print.
    debugPrint(redactCrashText('Uncaught: $error\n$stack'));
    _captureCrash(error, stack);
    return true;
  };
}

/// Credentials out of a line the crash handlers print.
String redactCrashText(String text) => LogService.redactCredentials(text);

/// [FlutterError.presentError], with what it prints passed through
/// [redactCrashText]. It prints through [debugPrint], which is swapped only
/// for the call.
void _presentErrorRedacted(FlutterErrorDetails details) {
  final print = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => print(
    message == null ? null : redactCrashText(message),
    wrapWidth: wrapWidth,
  );
  try {
    FlutterError.presentError(details);
  } finally {
    debugPrint = print;
  }
}

void _captureCrash(Object error, StackTrace? stack) {
  try {
    final errorLine = error.toString().split('\n').first;
    final frameLine = stack?.toString().split('\n').first.trim() ?? '';
    final signature = '$errorLine @ $frameLine';

    final crashes = GetIt.instance<CrashReportService>();
    if (!crashes.shouldCapture(signature)) return;

    final logs = GetIt.instance<LogService>();
    logs.logCrash(
      'Uncaught: $errorLine',
      stack == null ? error : '$error\n$stack',
    );
    unawaited(crashes.record(signature, logs.exportText(maxEntries: 300)));

    // Debounced so a burst of errors settles before the upload, and so a
    // crash during startup waits for the session rather than racing it.
    _crashFlushDebounce?.cancel();
    _crashFlushDebounce = Timer(const Duration(seconds: 5), () {
      unawaited(crashes.flushPending());
    });
  } catch (_) {
    // The crash handler must never become a second crash.
  }
}

void _startProcessExitReporter() {
  final reporter = ProcessExitReporter(
    GetIt.instance<LogService>(),
    GetIt.instance<CrashReportService>(),
  );
  unawaited(reporter.reportPreviousExits());
  reporter.watch(
    routeChanges: appRouter.routerDelegate,
    // A player is pushed over the tab that opened it, so the last match is
    // what's on screen.
    currentRoute: () {
      final matches = appRouter.routerDelegate.currentConfiguration.matches;
      return matches.isEmpty ? '' : matches.last.matchedLocation;
    },
    screensaverVisible: PlatformDetection.isTV
        ? GetIt.instance<ScreensaverController>().visible
        : null,
  );
}

/// Applies the stored layout override before anything reads the platform
/// flags. Reads its own store instance because dependency injection has not
/// happened yet this early in startup.
Future<void> _applyInterfaceLayoutOverride() async {
  try {
    final store = PreferenceStore();
    await store.init();
    PlatformDetection.setInterfaceLayout(
      store.get(UserPreferences.interfaceLayout),
    );
  } catch (_) {}
}

/// The user's performance choice, read the same way and for the same reason:
/// the tier is needed long before sign-in makes a per-user key readable, which
/// is also why this preference is never stored per server and user.
DevicePerformanceMode _startupPerformanceMode = DevicePerformanceMode.auto;

Future<void> _readPerformanceModeOverride() async {
  try {
    final store = PreferenceStore();
    await store.init();
    _startupPerformanceMode = store.get(UserPreferences.performanceMode);
  } catch (_) {}
}

/// Resolves whether this Android device is a TV, which decides the leanback UI
/// and the default playback engine.
Future<void> _detectAndSetTvMode() async {
  if (const bool.fromEnvironment('MOONFIN_FORCE_TV')) {
    PlatformDetection.setTvMode(true);
    return;
  }
  if (!PlatformDetection.isAndroid) return;
  const channel = MethodChannel('org.moonfin.androidtv/platform');
  const attempts = 3;
  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      final isTV = await channel.invokeMethod<bool>('isTvDevice');
      if (isTV != null) {
        PlatformDetection.setTvMode(isTV);
        return;
      }
    } catch (_) {}
    if (attempt < attempts - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  debugPrint(
    'TV detection failed after $attempts attempts, continuing as a non-TV device',
  );
}

/// Seeds the capability state from the last launch's good probe results.
///
/// On a cold boot the app can start before HDMI has finished negotiating, and
/// every probe then reports a device that can do nothing. Starting from the
/// persisted last-good answers means even the first playback of such a launch
/// gets a profile that matches the hardware. A probe that later succeeds
/// overwrites the seed in either direction.
Future<void> _seedCapabilitiesFromCache() async {
  final audio = await DeviceCapabilityCache.readMap(
    DeviceCapabilityCache.audioKey,
  );
  if (audio != null) {
    PlatformDetection.setAudioCapabilities(audio);
  }
  if (PlatformDetection.isAndroid) {
    // Read without the build key the probe path checks. Only a firmware
    // update can make this stale and the probe a moment later corrects it,
    // where a launch whose probe cant answer would otherwise run on the
    // H264 floor.
    final codecs = await DeviceCapabilityCache.readMap(
      DeviceCapabilityCache.codecKey,
    );
    if (codecs != null) {
      PlatformDetection.setMediaCodecCapabilities(codecs);
    }
  }
  if (PlatformDetection.isAndroid) {
    final memory = await DeviceCapabilityCache.readMap(
      DeviceCapabilityCache.deviceMemoryKey,
    );
    if (memory != null) {
      PlatformDetection.setDeviceMemory(memory);
    }
  }
  if (DisplayHdrProbe.isSupported) {
    // Null means the display has never answered. An empty list means it
    // answered and named nothing, which is a real result worth seeding.
    final hdrTypes = await DisplayHdrProbe.seedFromCache();
    if (hdrTypes != null) {
      PlatformDetection.setDisplayHdrTypes(hdrTypes);
    }
  }
}

/// Runs [attempt] with a doubling delay, first wait two seconds, and stops as
/// soon as one attempt reports done. An attempt that throws counts the same
/// as one that came up short, since a failed probe says nothing about the
/// next one.
Future<bool> _retryOffLaunchPath(Future<bool> Function() attempt) async {
  var delay = const Duration(seconds: 2);
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(delay);
    delay *= 2;
    try {
      if (await attempt()) return true;
    } catch (_) {}
  }
  return false;
}

/// How much RAM this device has. Fixed for the life of the device, so one
/// attempt with a deadline and no retry, and a cached answer stands in when the
/// channel cant reach the platform side. Its own try/catch matters: this runs
/// inside a Future.wait, which gives up on every sibling the moment one throws.
Future<void> _detectAndSetDeviceMemory() async {
  if (!PlatformDetection.isAndroid) return;
  try {
    const channel = MethodChannel('org.moonfin.androidtv/platform');
    final raw = await channel
        .invokeMethod<Map<dynamic, dynamic>>('deviceMemory')
        .timeout(const Duration(seconds: 2));
    if (raw == null) return;
    final memory = raw.map((key, value) => MapEntry(key.toString(), value));
    PlatformDetection.setDeviceMemory(memory);
    // The facts go in, never the verdict, so moving the threshold later
    // re-decides an old device instead of reading back a stale answer.
    unawaited(
      DeviceCapabilityCache.writeMap(
        DeviceCapabilityCache.deviceMemoryKey,
        memory,
      ),
    );
  } catch (_) {}
}

/// Runs before the first frame, so only the single attempt is awaited here.
/// The retries and the listener are deliberately left to run on their own: a
/// box whose TV is still asleep would otherwise hold the launch for the whole
/// half-minute retry window.
Future<void> _detectAndSetDisplayCapabilities() async {
  if (!DisplayHdrProbe.isSupported) return;
  // Its own try/catch for the same reason the memory probe has one: this runs
  // inside a Future.wait, which gives up on every sibling the moment one
  // throws.
  try {
    final snapshot = await DisplayHdrProbe.query(trigger: 'launch');
    DisplayHdrProbe.apply(snapshot);
    if (snapshot == null ||
        snapshot.verdict == DisplayHdrVerdict.cannotAnswer) {
      unawaited(DisplayHdrProbe.queryWithRetry().then(DisplayHdrProbe.apply));
    }
    // A chain that is still asleep when the retries run out heals from here
    // instead of waiting for the app to be restarted.
    DisplayHdrProbe.listenForDisplayChanges();
  } catch (_) {}
}

Future<Map<String, dynamic>?> _queryCodecCaps(MethodChannel channel) async {
  final raw = await channel.invokeMethod<Map<dynamic, dynamic>>(
    'mediaCodecCapabilities',
    <String, dynamic>{
      'includeSoftwareDecoders': !PlatformDetection.isTV,
    },
  );
  return raw?.map((key, value) => MapEntry(key.toString(), value));
}

/// Re-probes in the background when the startup probe threw or came back
/// looking wrong. The native query enumerates codecs on the platform main
/// thread, so the retries must never extend the launch path. The device
/// profile is built per playback, so a corrected result applied here still
/// fixes the next playback without a restart.
///
/// Backs off between attempts, since enumeration loses the race when the
/// device is busiest right after boot. Every sound result is applied as it
/// arrives, and the retries only stop early once one carries HEVC, since a
/// result without it is either a partial enumeration worth another look or a
/// device that really lacks the decoder and loses nothing to the re-probes.
Future<void> _retryCodecCapsOffLaunchPath(MethodChannel channel) =>
    _retryOffLaunchPath(() => _applyCodecProbe(channel));

/// One probe: applies a sound answer and persists a complete one. Returns
/// true once the answer carries HEVC and throws when the channel does.
Future<bool> _applyCodecProbe(MethodChannel channel) async {
  final caps = await _queryCodecCaps(channel);
  if (caps == null || codecCapsLookDegenerate(caps)) return false;
  PlatformDetection.setMediaCodecCapabilities(caps);
  if (codecCapsLookIncomplete(caps)) return false;
  await _cacheCodecCaps(channel, caps);
  return true;
}

/// The OS build fingerprint, which is the key the codec cache is valid under.
/// Codec support only changes with a firmware update, and a firmware update
/// always changes the fingerprint.
Future<String?> _androidBuildFingerprint(MethodChannel channel) async {
  try {
    return await channel.invokeMethod<String>('buildFingerprint');
  } catch (_) {
    return null;
  }
}

Future<void> _cacheCodecCaps(
  MethodChannel channel,
  Map<String, dynamic> caps,
) async {
  final build = await _androidBuildFingerprint(channel);
  if (build == null) return;
  await DeviceCapabilityCache.writeMap(
    DeviceCapabilityCache.codecKey,
    caps,
    build: build,
  );
}

/// Some Amlogic and MediaTek audio drivers misbehave once a device has been up
/// for a long time, so the diagnostic report says how long that's been.
Future<void> _detectAndSetSystemUptime() async {
  if (!PlatformDetection.isAndroid) return;
  try {
    const channel = MethodChannel('org.moonfin.androidtv/platform');
    final uptimeMs = await channel
        .invokeMethod<int>('uptimeMillis')
        .timeout(const Duration(seconds: 2));
    if (uptimeMs != null) PlatformDetection.setSystemUptime(uptimeMs);
  } catch (_) {}
}

/// The renderer is fixed before Dart runs, so the diagnostic report asks the
/// platform side what it chose.
Future<void> _detectAndSetRenderer() async {
  if (!PlatformDetection.isAndroid) return;
  try {
    const channel = MethodChannel('org.moonfin.androidtv/platform');
    PlatformDetection.setRenderer(
      await channel
          .invokeMethod<String>('renderer')
          .timeout(const Duration(seconds: 2)),
    );
  } catch (_) {}
}

Future<void> _detectAndSetCodecCapabilities() async {
  if (!PlatformDetection.isAndroid) return;
  const channel = MethodChannel('org.moonfin.androidtv/platform');

  // What a chip decodes only changes with its firmware, so a sound result
  // saved under this build is the answer and the enumeration, the slowest
  // probe of the launch, is skipped entirely.
  final build = await _androidBuildFingerprint(channel);
  if (build != null) {
    final cached = await DeviceCapabilityCache.readMap(
      DeviceCapabilityCache.codecKey,
      build: build,
    );
    if (cached != null) {
      PlatformDetection.setMediaCodecCapabilities(cached);
      return;
    }
  }

  try {
    final codecCaps = await _queryCodecCaps(channel);
    if (codecCaps != null) {
      // A degenerate cold-start result would otherwise poison the device
      // profile until app restart, leaving playback broken rather than just
      // inefficient.
      final degenerate = codecCapsLookDegenerate(codecCaps);
      PlatformDetection.setMediaCodecCapabilities(
        degenerate ? withAvcFloor(codecCaps) : codecCaps,
      );
      // A result that cleared the AVC check can still be a partial
      // enumeration, seen in the field as a box whose HEVC decoder vanished
      // for one launch and every HEVC library transcoding until a restart.
      if (degenerate || codecCapsLookIncomplete(codecCaps)) {
        unawaited(_retryCodecCapsOffLaunchPath(channel));
      } else {
        unawaited(_cacheCodecCaps(channel, codecCaps));
      }
      return;
    }

    final legacyDvCaps = await channel.invokeMethod<Map<dynamic, dynamic>>(
      'dolbyVisionCodecCapabilities',
    );
    PlatformDetection.setDolbyVisionCodecCapabilities(
      legacyDvCaps?.map(
        (key, value) => MapEntry(key.toString(), value == true),
      ),
    );
  } catch (_) {
    // A probe that never answered, like a channel hit before the plugin
    // registered, leaves every codec flag false and the profile claiming the
    // device decodes nothing. The floor only lands when the seed left nothing
    // to keep, and the retries are the same recovery a degenerate answer gets.
    PlatformDetection.setMediaCodecCapabilities(
      codecCapsWithoutAProbe(PlatformDetection.mediaCodecCapabilitiesSnapshot),
    );
    unawaited(_retryCodecCapsOffLaunchPath(channel));
  }
}

Future<void> _detectAndSetAetherCapabilities() async {
  const channel = MethodChannel('moonfin/ios_aether_control');
  final caps = await _queryAppleVideoCaps(channel);

  // Fallback mirrors AetherEngine's guaranteed baseline on the hardware the
  // deployment floors allow (iOS 16, macOS 14).
  PlatformDetection.setMediaCodecCapabilities(
    caps ??
        const {
          'supportsAvc': true,
          'avcMainLevel': 52,
          'supportsAvcHigh10': true,
          'avcHigh10Level': 52,
          'supportsHevc': true,
          'hevcMainLevel': 153,
          'supportsHevcMain10': true,
          'hevcMain10Level': 153,
          'supportsHevcDolbyVision': true,
          'supportsHevcHdr10': true,
          'supportsDvP5': true,
          'supportsDvP7': true,
          'supportsDvP8': true,
          'supportsAv1': true,
          'supportsAv1Main10': true,
          'maxResolutionAvc': {'width': 3840, 'height': 2160},
          'maxResolutionHevc': {'width': 3840, 'height': 2160},
          'maxResolutionAv1': {'width': 1920, 'height': 1080},
        },
  );
}

/// Queries an Apple video capability channel, preferring the last good
/// answer over the static baseline when the probe fails. Keyed to the OS
/// version, since that is what changes what these decoders can do.
Future<Map<String, dynamic>?> _queryAppleVideoCaps(
  MethodChannel channel,
) async {
  final build = PlatformDetection.osVersion;
  try {
    final raw = await channel.invokeMethod<Map<dynamic, dynamic>>(
      'getCapabilities',
    );
    if (raw != null) {
      final caps = raw.map((key, value) => MapEntry(key.toString(), value));
      unawaited(
        DeviceCapabilityCache.writeMap(
          DeviceCapabilityCache.appleVideoKey,
          caps,
          build: build,
        ),
      );
      return caps;
    }
  } catch (_) {}
  return DeviceCapabilityCache.readMap(
    DeviceCapabilityCache.appleVideoKey,
    build: build,
  );
}

Future<void> _detectAndSetAppleTvCapabilities() async {
  const channel = MethodChannel('moonfin/native_apple_player_control');
  final caps = await _queryAppleVideoCaps(channel);

  PlatformDetection.setMediaCodecCapabilities(
    caps ??
        const {
          'supportsAvc': true,
          'avcMainLevel': 52,
          'supportsAvcHigh10': true,
          'avcHigh10Level': 52,
          'supportsHevc': true,
          'hevcMainLevel': 153,
          'supportsHevcMain10': true,
          'hevcMain10Level': 153,
          'supportsHevcDolbyVision': true,
          'supportsHevcHdr10': true,
          'supportsDvP5': true,
          'supportsDvP8': true,
          'maxResolutionAvc': {'width': 3840, 'height': 2160},
          'maxResolutionHevc': {'width': 3840, 'height': 2160},
        },
  );
}

Future<void> _detectAndApplyAudioCapabilities(UserPreferences prefs) async {
  if (!AudioCapabilityProbe.isSupported) return;
  try {
    // Probe with a retry window sized against an HDMI handshake, then publish
    // so getDeviceProfile() picks it up.
    final profile = await AudioCapabilityProbe.queryWithRetry();
    AudioCapabilityProbe.apply(profile);

    // A launch that still has no real answer keeps trying with a longer
    // backoff, since a box powered on with the app can take a while to bring
    // its audio outputs up.
    if (profile == null || AudioCapabilityProbe.looksEmpty(profile)) {
      unawaited(_retryAudioCapsOffLaunchPath());
    }

    // Installs migrated into manual mode carry only the toggles they had set
    // by hand, so fill the rest from the probe and every switch has a real
    // value.
    if (profile != null &&
        prefs.get(UserPreferences.audioPassthroughMode) ==
            AudioPassthroughMode.manual) {
      await prefs.seedAbsentPassthroughToggles();
    }

    // Re-probe whenever the audio route changes (e.g. the AVR is powered on
    // after launch) so detection self-heals without an app restart.
    AudioCapabilityProbe.listenForRouteChanges();
  } catch (_) {}
}

Future<void> _retryAudioCapsOffLaunchPath() =>
    _retryOffLaunchPath(() async {
      final profile = await AudioCapabilityProbe.query();
      if (profile == null || AudioCapabilityProbe.looksEmpty(profile)) {
        return false;
      }
      AudioCapabilityProbe.apply(profile);
      return true;
    });

void _sweepImageCache(UserPreferences prefs, {bool throttle = false}) {
  final mb = prefs.get(UserPreferences.imageCacheLimitMb);
  unawaited(enforceImageCacheBudget(mb * 1024 * 1024, throttle: throttle));
  unawaited(enforceGameArtworkCacheBudget(throttle: throttle));
}

/// Runs an auto-download check when the app comes back to the foreground;
/// the service throttles resumes that follow a recent check.
class _AutoDownloadResumeObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!GetIt.instance.isRegistered<AutoDownloadService>()) return;
    GetIt.instance<AutoDownloadService>().onAppResumed();
  }
}

class _ImageCacheSweepObserver with WidgetsBindingObserver {
  _ImageCacheSweepObserver(this._prefs);

  final UserPreferences _prefs;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _sweepImageCache(_prefs, throttle: true);
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // The index is written on a timer. A process killed in the
        // background never reaches it, so write on the way out.
        unawaited(flushImageCacheIndex());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }
}

/// Re-probes display, decoder and audio capabilities when the app comes back
/// to the foreground, which on a TV covers being woken from standby, the
/// moment the HDMI chain has just renegotiated, and is also the first moment
/// an engine that launched without an Activity has a platform channel to ask.
/// Only answers that carry something are applied here: an empty answer
/// mid-renegotiation must not clobber a good snapshot.
class _CapabilityRefreshObserver with WidgetsBindingObserver {
  static const _throttle = Duration(seconds: 30);
  DateTime? _lastRefresh;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    final last = _lastRefresh;
    if (last != null && now.difference(last) < _throttle) return;
    _lastRefresh = now;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (DisplayHdrProbe.isSupported) {
      DisplayHdrProbe.apply(await DisplayHdrProbe.query(trigger: 'resume'));
    }
    // The launch retries all run inside the first half minute, which covers
    // a slow enumeration but not an engine that had no Activity to answer
    // the probe until now. A device with no HEVC decoder pays one
    // enumeration per resume for this and keeps its answer.
    if (PlatformDetection.isAndroid &&
        codecCapsLookIncomplete(
          PlatformDetection.mediaCodecCapabilitiesSnapshot,
        )) {
      try {
        await _applyCodecProbe(
          const MethodChannel('org.moonfin.androidtv/platform'),
        );
      } catch (_) {}
    }
    if (AudioCapabilityProbe.isSupported) {
      // The guard inside apply keeps a null or unenumerated answer from
      // touching the last detection.
      AudioCapabilityProbe.apply(await AudioCapabilityProbe.query());
    }
  }
}

/// Desktop is the only place a mouse wheel is the main way to scroll, so the
/// setting stays inert elsewhere.
void _bindScrollSensitivity(UserPreferences prefs) {
  if (!PlatformDetection.useDesktopUi) return;
  void apply() {
    (WidgetsBinding.instance as ScrollSensitivityBinding).multiplier =
        prefs.get(UserPreferences.desktopScrollSensitivity) / 100;
  }

  apply();
  prefs.addListener(apply);
}

class _PreferenceWriteFlushObserver with WidgetsBindingObserver {
  _PreferenceWriteFlushObserver(this._prefs);

  final UserPreferences _prefs;
  bool _flushInProgress = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushPendingWrites());
    }
  }

  Future<void> _flushPendingWrites() async {
    if (_flushInProgress) {
      return;
    }
    _flushInProgress = true;
    try {
      await _prefs.flushPendingWrites();
    } catch (_) {
    } finally {
      _flushInProgress = false;
    }
  }
}

@pragma('vm:entry-point')
Future<void> watchNextBackgroundMain() => watch_next_bg.watchNextBackgroundMain();

/// Entry for the Android auto-download worker's headless engine.
@pragma('vm:entry-point')
Future<void> autoDownloadBackgroundMain() =>
    auto_download_bg.autoDownloadBackgroundMain();

void main() async {
  configureHttpOverrides();
  ScrollSensitivityBinding.ensureInitialized();
  // Kos TV: first, so a failure anywhere in startup is caught and printed
  // (without its credentials). It is recorded once the services that keep
  // reports exist; until then capturing it does nothing.
  _installCrashHandlers();

  // Pre-warms the liquid_glass_widgets shader programs so the first glass
  // pane doesn't white-flash. Started now and awaited before runApp only
  // when the glass tier uses the package renderer, so TV and web (sheen)
  // don't wait on shaders they never draw with. The Impeller pipeline
  // warm-up is deferred past the first frame internally.
  // Kos TV: the web never draws with them (its glass is always the sheen),
  // and compiling them there takes the one thread the app has.
  final Future<void> glassWarmUp = PlatformDetection.isWeb
      ? Future<void>.value()
      : LiquidGlassWidgets.initialize();
  // Kos TV: the web's config.json asked for at once, while the rest gets
  // ready (it is waited for further down, where it was).
  final Future<void>? webConfig = PlatformDetection.isWeb
      ? loadWebRuntimeConfig()
      : null;
  // Kos TV: and, alongside it, the two files the app version is read from,
  // which are two more trips to the server there.
  final appInfo = PlatformDetection.isWeb ? startAppInfoLoad() : null;

  registerGameCoreLicenses();
  registerEpubJsLicenses();

  if (PlatformDetection.isAppleTV) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: const Color(0xF2000000),
          padding: const EdgeInsets.all(28),
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            child: Text(
              '${details.exceptionAsString()}\n\n${details.stack ?? ''}',
              style: const TextStyle(color: Color(0xFFFF6E6E), fontSize: 15),
            ),
          ),
        ),
      );
    };
  }

  await _startApp(
    glassWarmUp: glassWarmUp,
    webConfig: webConfig,
    appInfo: appInfo,
  );
}

/// Kos TV: how far a launch got, so Retry after a startup failure picks up
/// where it stopped instead of hooking everything up a second time.
bool _platformPrepared = false;
bool _dependenciesAttempted = false;
bool _dependenciesReady = false;

/// Kos TV: runs startup, and if any of it throws, says so on screen with a
/// Retry button. It used to leave the native splash up on every launch, with
/// nothing recorded anywhere (a full disk, a damaged downloads database), and
/// the only way out was clearing the app's data.
Future<void> _startApp({
  required Future<void> glassWarmUp,
  required Future<void>? webConfig,
  required Future<(void, String)>? appInfo,
}) async {
  try {
    await _bootstrap(
      glassWarmUp: glassWarmUp,
      webConfig: webConfig,
      appInfo: appInfo,
    );
  } catch (error, stack) {
    _reportStartupFailure(error, stack);
    runApp(
      StartupFailureApp(
        onRetry: () => _startApp(
          glassWarmUp: glassWarmUp,
          webConfig: webConfig,
          appInfo: appInfo,
        ),
      ),
    );
  }
}

void _reportStartupFailure(Object error, StackTrace stack) {
  debugPrint(redactCrashText('Startup failed: $error\n$stack'));
  _captureCrash(error, stack);
}

Future<void> _bootstrap({
  required Future<void> glassWarmUp,
  required Future<void>? webConfig,
  required Future<(void, String)>? appInfo,
}) async {
  if (!_platformPrepared) {
    await _preparePlatform(webConfig);
    _platformPrepared = true;
  }

  if (!_dependenciesReady) {
    // A Retry after a failure halfway through: start the container over.
    if (_dependenciesAttempted) await GetIt.instance.reset();
    _dependenciesAttempted = true;
    await configureDependencies(appInfo: appInfo);
    _dependenciesReady = true;
    // Kos TV: what startup got past (a downloads database that could not be
    // opened), recorded now that there is somewhere to record it.
    for (final (error, stack) in takeDeferredStartupErrors()) {
      _reportStartupFailure(error, stack);
    }
    _bindAppServices();
  }

  // Register Theme Store themes before the active theme is resolved so a
  // store-saved theme applies on launch.
  await ThemeStoreService(
    GetIt.instance<StoragePathService>(),
  ).loadAndRegister();

  // tvOS: keep the system Now Playing card fed for music (the native
  // NowPlayingController handles video; audio has no view controller to feed it).
  if (PlatformDetection.isAppleTV &&
      !GetIt.instance.isRegistered<AppleTvAudioNowPlayingFeeder>()) {
    try {
      final feeder = AppleTvAudioNowPlayingFeeder(
        manager: GetIt.instance<PlaybackManager>(),
        clientFactory: GetIt.instance<MediaServerClientFactory>(),
        backend: GetIt.instance<NativeApplePlayerBackend>(),
      )..start();
      GetIt.instance.registerSingleton<AppleTvAudioNowPlayingFeeder>(feeder);
    } catch (_) {}
  }

  if (!GetIt.instance.isRegistered<PlaybackLifecycleHandler>()) {
    GetIt.instance.registerSingleton<PlaybackLifecycleHandler>(
      PlaybackLifecycleHandler(GetIt.instance<PlaybackManager>()),
    );
  }

  try {
    GetIt.instance<AirPlayCommandBridge>().start();
  } catch (_) {}

  // Kos TV: whether this launch opens with the opening animation.
  await KostvIntroPolicy.init();
  // Kos TV: where the requests service was last time (the plugin says).
  await KostvRequestsAddress.load();

  // Same tier the app shell applies on its first build. If it later moves
  // to a blur tier the warm-up has long finished, and the package loads any
  // missing shader on first use anyway.
  final glassTier = GlassCapability.resolve();
  if (!GlassCapability.useLegacyGlass &&
      (glassTier == GlassTier.liquid || glassTier == GlassTier.frost)) {
    await glassWarmUp;
  } else {
    unawaited(glassWarmUp.catchError((Object _) {}));
  }

  runApp(const MoonfinApp());
}

/// What the device is and what it can do, read before the container is
/// built, and the caches sized from it.
Future<void> _preparePlatform(Future<void>? webConfig) async {
  if (webConfig != null) {
    await webConfig;
  }

  // Apple runs entirely on AetherEngine, so media_kit isn't initialized there
  // and its native libs are out of those builds.
  if (!PlatformDetection.isAppleTV && !PlatformDetection.isIOS) {
    MediaKit.ensureInitialized();
  }

  await _applyInterfaceLayoutOverride();
  await _readPerformanceModeOverride();
  await _detectAndSetTvMode();
  await _seedCapabilitiesFromCache();
  await Future.wait([
    _detectAndSetDisplayCapabilities(),
    _detectAndSetCodecCapabilities(),
    _detectAndSetDeviceMemory(),
    _detectAndSetSystemUptime(),
    _detectAndSetRenderer(),
  ]);

  if (PlatformDetection.isAppleTV) {
    await _detectAndSetAppleTvCapabilities();
  }
  if (PlatformDetection.isIOS) {
    await _detectAndSetAetherCapabilities();
  }

  _configureImageCache();
  installSiloImageHooks();
  _capSkiaCache();
  await configureImageDiskCache(tier: _resolvedTier());

  // tvOS loads its fonts asynchronously, and the first frame can render
  // before MaterialIcons and the rest are ready, leaving icons blank. Pumping
  // a warm-up frame gives the font loader time to finish.
  if (PlatformDetection.isAppleTV) {
    WidgetsBinding.instance.scheduleWarmUpFrame();
  }

  if (PlatformDetection.isMobile) {
    SystemUi.install();

    // Registered before runApp so a background/terminated push can be handled.
    // The handler itself is a no-op; the OS draws these notifications.
    // Kos TV: only while push is on, which it isn't yet.
    if (PushMessagingService.enabled) {
      try {
        FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
      } catch (_) {}
    }
  }
}

/// The listeners and observers that follow the container's services for the
/// life of the app, bound once it is built.
void _bindAppServices() {
  if (PlatformDetection.isAndroid) _startProcessExitReporter();
  // When the system runs the auto-download refresh task against this
  // engine, the native side retries its call until this handler is bound.
  if (AutoDownloadService.isSupportedPlatform) {
    BackgroundRefresh.instance.bind(runAutoDownloadBackgroundRefresh);
  }

  // Registered before runApp so a CarPlay-only launch (no window scene, no
  // widgets) can browse and start playback.
  if (PlatformDetection.isIOS && !GetIt.instance.isRegistered<CarPlayService>()) {
    try {
      final carPlayService = CarPlayService(
        browse: GetIt.instance<MediaBrowseService>(),
        manager: GetIt.instance<PlaybackManager>(),
      )..start();
      GetIt.instance.registerSingleton<CarPlayService>(carPlayService);
    } catch (_) {}
  }

  final prefs = GetIt.instance<UserPreferences>();
  _bindScrollSensitivity(prefs);
  WidgetsBinding.instance.addObserver(_PreferenceWriteFlushObserver(prefs));
  WidgetsBinding.instance.addObserver(_ImageCacheSweepObserver(prefs));
  WidgetsBinding.instance.addObserver(_CapabilityRefreshObserver());
  WidgetsBinding.instance.addObserver(_AutoDownloadResumeObserver());
  // Not on the first frame: the first screens are busy decoding artwork, and
  // a cache over budget a little longer costs nothing.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Timer(const Duration(seconds: 20), () => _sweepImageCache(prefs));
  });

  GetIt.instance<PlaybackManager>().queueService.queueChangedStream.listen((_) {
    final activeItem = GetIt.instance<PlaybackManager>().queueService.currentItem;
    if (activeItem is AggregatedItem) {
      prefs.unhideFromContinueWatching(activeItem.id);
      if (activeItem.seriesId != null && activeItem.seriesId!.isNotEmpty) {
        prefs.unhideFromContinueWatching(activeItem.seriesId!);
        prefs.unhideFromNextUp(activeItem.seriesId!);
      }
    }
  });

  // Audio and notification services are only needed once playback or a
  // download can happen, so they initialize after the first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initDeferredStartupServices(prefs));
  });
}

/// Startup work that runs after the first frame. The internal order matters:
/// the Android audio session configuration must follow initAudioService.
Future<void> _initDeferredStartupServices(UserPreferences prefs) async {
  if (PlatformDetection.isMobile ||
      (PlatformDetection.isAndroid && PlatformDetection.isTV)) {
    try {
      await initAudioService(
        manager: GetIt.instance<PlaybackManager>(),
        clientFactory: GetIt.instance<MediaServerClientFactory>(),
      );
    } catch (e, st) {
      debugPrint('initAudioService failed (lock-screen controls disabled): $e\n$st');
    }
  }

  // Kos TV: not waited for. Its retries ride out an HDMI handshake (several
  // seconds on a TV), and nothing below needs what it finds: reattaching the
  // downloads that ran while the app was closed and the headphones-out pause
  // used to wait on it.
  unawaited(_detectAndApplyAudioCapabilities(prefs));

  unawaited(SubtitleFonts.instance.follow(prefs));

  try {
    await GetIt.instance<DownloadNotificationService>().initialize();
  } catch (_) {}

  // Starts the native download engine and re-attaches to any downloads that
  // ran while the app was suspended or dead. No-op where unsupported.
  try {
    await GetIt.instance<BackgroundDownloadCoordinator>().ensureInitialized();
  } catch (_) {}

  if (PlatformDetection.isMobile) {
    try {
      await GetIt.instance<PushMessagingService>().initialize();
    } catch (_) {}
  }

  // Audio session ownership differs per platform:
  // - Android: MoonfinAudioHandler acquires audio focus per playback, and skips
  //   it when the backend manages focus itself like media3. We only configure
  //   the attributes here so the becomingNoisy handler below can pause on
  //   headphone unplug. We deliberately do not setActive(true) at startup: that
  //   focus grab goes stale before playback begins, which left Android Auto
  //   music muted, and it fights ExoPlayer's own focus.
  // - iOS: MoonfinAudioHandler claims a non-mixing `.playback` session when
  //   playback starts and releases it on stop, so the in-app player owns Control
  //   Center / lock-screen Now Playing and AirPods/remote controls. Here we only
  //   attach route handling (pause on disconnect, A/V re-sync on connect).
  if (PlatformDetection.isAndroid) {
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      ));
      session.becomingNoisyEventStream.listen((_) {
        GetIt.instance<PlaybackManager>().pause();
      });
    } catch (_) {}
  } else if (PlatformDetection.isIOS) {
    try {
      _attachIosAudioRouteHandling();
    } catch (_) {}
  }
}
