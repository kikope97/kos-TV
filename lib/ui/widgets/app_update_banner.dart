import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../data/services/app_update_service.dart';
import '../navigation/app_router.dart';
import '../navigation/destinations.dart';
import 'app_update_dialog.dart';

/// Offers a newer GitHub release when the app starts and whenever it comes
/// back to the foreground, in the update dialog. Draws nothing itself.
///
/// Kos TV: the floating pill Moonfin showed on desktop is gone, since only the
/// Android builds update themselves here and they always ask in the dialog,
/// which the remote can answer.
class AppUpdateBanner extends StatefulWidget {
  /// Overrides the update lookup in tests. Defaults to the registered
  /// [AppUpdateService]'s cooldown-respecting check.
  final Future<DesktopUpdateCheckResult> Function()? checkForUpdate;

  /// Offers the update, for a test. Defaults to the update dialog.
  final Future<void> Function(DesktopUpdateInfo update)? showUpdate;

  /// Whether something plays full screen and whether the app is still
  /// opening, and what tells either changed, for a test. Default to the
  /// app's router and player.
  final bool Function()? isWatching;
  final bool Function()? isOpening;
  final Listenable? routeChanges;

  /// How soon a check that got no answer is tried again, for a test.
  final Duration? retryAfterFailure;

  const AppUpdateBanner({
    super.key,
    this.checkForUpdate,
    this.showUpdate,
    this.isWatching,
    this.isOpening,
    this.routeChanges,
    this.retryAfterFailure,
  });

  @override
  State<AppUpdateBanner> createState() => _AppUpdateBannerState();
}

class _AppUpdateBannerState extends State<AppUpdateBanner> {
  /// Kos TV: TVs keep the app open for days, so the check also runs whenever
  /// it comes back to the foreground (the service's cooldown still applies).
  AppLifecycleListener? _lifecycle;
  bool _checking = false;

  /// Kos TV: an update found while something was playing, offered once the
  /// player closes.
  DesktopUpdateInfo? _held;

  /// Kos TV: what the check waits on (the opening to end, the player to
  /// close), while it waits.
  Listenable? _waitingOn;
  VoidCallback? _onWaitOver;

  Timer? _retry;
  Timer? _settle;

  bool get _real => widget.checkForUpdate == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_check());
    });
    if (_real) {
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(_check()));
      // Kos TV: the APK of the update this run started with is done with.
      unawaited(discardLeftoverUpdateDownload());
    }
  }

  @override
  void dispose() {
    _stopWaiting();
    _lifecycle?.dispose();
    _retry?.cancel();
    _settle?.cancel();
    super.dispose();
  }

  Listenable get _routeChanges =>
      widget.routeChanges ??
      Listenable.merge([
        appRouter.routerDelegate,
        PlayerRouteObserver.instance.isPlayerActive,
      ]);

  bool _watching() => (widget.isWatching ?? _isWatching)();
  bool _opening() => (widget.isOpening ?? _isOpening)();

  /// Kos TV: whether something is playing full screen right now, which an
  /// update prompt shouldn't interrupt. Checked before asking the service and
  /// again before offering what it found, since the answer can take a while.
  static bool _isWatching() {
    try {
      // The player is pushed over the page it was opened from, which the
      // address keeps naming: the page on screen is the last match.
      if (PlayerRouteObserver.instance.isPlayerActive.value) return true;
      final matches = appRouter.routerDelegate.currentConfiguration.matches;
      final path = matches.isEmpty
          ? appRouter.routerDelegate.currentConfiguration.uri.path
          : matches.last.matchedLocation;
      return path.startsWith('/player') ||
          path.startsWith('/live-tv/player') ||
          path.startsWith('/game-player');
    } catch (_) {
      return false;
    }
  }

  /// Kos TV: whether the app is still opening (the intro, signing in). The
  /// opening ends by replacing its page with Home, which takes away any
  /// dialog over it: an update offered then lost its progress window halfway
  /// and never reached the installer.
  static bool _isOpening() {
    try {
      final path = appRouter.routerDelegate.currentConfiguration.uri.path;
      return Destinations.isSignedOutRoute(path);
    } catch (_) {
      return true;
    }
  }

  /// Kos TV: waits for the app to be on a page an update can be offered over
  /// (not opening, nothing playing), then gives it a moment to settle and
  /// goes on: offering what it holds, or checking.
  void _waitForCalm() {
    if (_waitingOn != null) return;
    final changes = _routeChanges;
    void onChange() {
      if (_opening() || _watching()) return;
      _stopWaiting();
      _settle?.cancel();
      _settle = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        if (_held != null) {
          unawaited(_offerHeld());
        } else {
          unawaited(_check());
        }
      });
    }

    _waitingOn = changes;
    _onWaitOver = onChange;
    changes.addListener(onChange);
  }

  void _stopWaiting() {
    final changes = _waitingOn;
    final listener = _onWaitOver;
    if (changes != null && listener != null) changes.removeListener(listener);
    _waitingOn = null;
    _onWaitOver = null;
  }

  Future<void> _check() async {
    if (_checking || _held != null) return;
    if (_opening() || _watching()) {
      _waitForCalm();
      return;
    }
    _checking = true;
    try {
      final check =
          widget.checkForUpdate ??
          GetIt.instance<AppUpdateService>().checkForUpdateIfDueDetailed;
      final result = await check();
      if (!mounted) return;
      // Kos TV: no answer (the wifi still coming back as the TV wakes up):
      // tried again in a few minutes rather than at the next resume, which on
      // a TV can be hours away.
      if (result.status == DesktopUpdateCheckStatus.checkFailed) {
        _retry?.cancel();
        _retry = Timer(
          widget.retryAfterFailure ?? AppUpdateService.retryAfterFailure,
          () {
            if (mounted) unawaited(_check());
          },
        );
      }
      final update = result.update;
      if (update == null) return;
      _held = update;
      await _offerHeld();
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  /// Kos TV: offers the update held, unless something started playing in the
  /// meantime: then it waits for the player to close.
  Future<void> _offerHeld() async {
    final update = _held;
    if (update == null || !mounted) return;
    if (_opening() || _watching()) {
      _waitForCalm();
      return;
    }
    _held = null;
    final show = widget.showUpdate ?? _showDialog;
    await show(update);
  }

  static Future<void> _showDialog(DesktopUpdateInfo update) async {
    final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    await showAppUpdateDialog(navContext, update);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
