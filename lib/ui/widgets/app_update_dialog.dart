import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/app_update_service.dart';
import '../../l10n/app_localizations.dart';
import '../../util/platform_detection.dart';
import '../navigation/app_router.dart';
import 'track_selector_dialog.dart';

/// Checks for an update and shows the dialog or an appropriate snackbar.
Future<void> checkAndShowUpdateResult(BuildContext context) async {
  final result =
      await GetIt.instance<AppUpdateService>().checkForUpdateNowDetailed();
  if (!context.mounted) return;

  final update = result.update;
  if (update != null) {
    await showAppUpdateDialog(context, update);
    return;
  }

  final l10n = AppLocalizations.of(context);
  final message = switch (result.status) {
    DesktopUpdateCheckStatus.upToDate => l10n.youAreUpToDate,
    DesktopUpdateCheckStatus.checkFailed => l10n.couldNotCheckForUpdates,
    DesktopUpdateCheckStatus.unsupportedPlatform => l10n.updateChecksNotSupported,
    DesktopUpdateCheckStatus.managedByStore => l10n.updateChecksNotSupported,
    DesktopUpdateCheckStatus.disabledByPreference => l10n.updateNotificationsDisabled,
    DesktopUpdateCheckStatus.rateLimited => l10n.pleaseWaitBeforeChecking,
    DesktopUpdateCheckStatus.alreadyNotified => l10n.latestUpdateAlreadyShown,
    DesktopUpdateCheckStatus.updateAvailable => l10n.updateAvailable,
  };
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}

/// Kos TV: the Android side of in-app updates (UpdateInstaller.kt).
const _platformChannel = MethodChannel('org.moonfin.androidtv/platform');

/// Kos TV: whether [update] is an APK this Android build can download and
/// install by itself, phones and TVs alike.
bool canInstallUpdateInApp(DesktopUpdateInfo update) =>
    !kIsWeb &&
    Platform.isAndroid &&
    update.downloadUri.isScheme('https') &&
    update.downloadUri.path.toLowerCase().endsWith('.apk');

Future<void> showAppUpdateDialog(
  BuildContext context,
  DesktopUpdateInfo update,
) async {
  final l10n = AppLocalizations.of(context);
  final inApp = canInstallUpdateInApp(update);

  final choice = await showStyledPlayerDialog<String>(
    context,
    title: l10n.updateAvailableTitle(update.version),
    showCancel: true,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (inApp)
          _UpdateOption(
            icon: Icons.system_update_alt_rounded,
            label: l10n.updateNow,
            value: 'install',
            autofocus: true,
          )
        else if (!PlatformDetection.isTV)
          _UpdateOption(
            icon: Icons.download_rounded,
            label: l10n.download,
            value: 'download',
          ),
        // A TV has no browser to read the notes in.
        if (!PlatformDetection.isTV || !inApp)
          _UpdateOption(
            icon: Icons.article_outlined,
            label: l10n.readReleaseNotes,
            value: 'notes',
            autofocus: !inApp,
          ),
      ],
    ),
  );

  if (choice == null || !context.mounted) return;

  if (choice == 'install') {
    await _downloadAndInstallAndroidUpdate(context, update);
    return;
  }

  if (choice == 'download' &&
      Platform.isWindows &&
      update.downloadUri.isScheme('https')) {
    await _downloadAndInstallWindowsUpdate(context, update);
    return;
  }

  final uri =
      choice == 'notes' ? Uri.parse(update.releaseNotesUrl) : update.downloadUri;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _downloadAndInstallWindowsUpdate(
  BuildContext context,
  DesktopUpdateInfo update,
) async {
  final l10n = AppLocalizations.of(context);
  final valueNotifier = ValueNotifier<double>(0.0);
  final errorNotifier = ValueNotifier<String?>(null);

  showStyledPlayerDialog<void>(
    context,
    title: l10n.updating,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: AnimatedBuilder(
          animation: Listenable.merge([valueNotifier, errorNotifier]),
          builder: (context, child) {
            final error = errorNotifier.value;
            if (error != null) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        l10n.close,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            }

            final progress = valueNotifier.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  try {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}${Platform.pathSeparator}moonfin_updater.exe');
    if (await file.exists()) {
      await file.delete();
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);

    try {
      final request = await client.getUrl(update.downloadUri);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Server returned status code ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      var downloaded = 0;
      final sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          valueNotifier.value = downloaded / contentLength;
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }

    await Process.start(
      file.path,
      [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  } catch (e) {
    debugPrint('Windows in-app update failed: $e');
    errorNotifier.value = l10n.updateDownloadFailed;
  }
}

/// Kos TV: downloads the APK, makes sure the app may install packages (asking
/// once, through the system setting), then hands it to the system installer.
/// The installer replaces the app in place, since releases share its key.
Future<void> _downloadAndInstallAndroidUpdate(
  BuildContext context,
  DesktopUpdateInfo update,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void tell(String message) => messenger?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
  );

  final progress = ValueNotifier<double?>(null);
  final failed = ValueNotifier<String?>(null);
  // Its own route, to close that one and no other, wherever it ended up.
  Route<dynamic>? progressRoute;
  var progressOpen = true;
  unawaited(
    showStyledPlayerDialog<void>(
      context,
      title: l10n.updating,
      barrierDismissible: false,
      builder: (dialogContext) {
        progressRoute ??= ModalRoute.of(dialogContext);
        return PopScope(
          // Back doesn't hide it while it downloads; once it failed, it does.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && failed.value != null) {
              Navigator.of(dialogContext).pop();
            }
          },
          child: _UpdateProgressBody(progress: progress, failed: failed),
        );
      },
    ).whenComplete(() => progressOpen = false),
  );

  String? path;
  try {
    path = await _platformChannel.invokeMethod<String>('updateDownloadPath');
    if (path == null) throw StateError('no download path');
    await _downloadTo(update.downloadUri, File(path), progress);
  } catch (e) {
    debugPrint('Android in-app update download failed: $e');
    failed.value = l10n.updateDownloadFailed;
    return;
  }
  final route = progressRoute;
  if (progressOpen && route != null && route.isActive) {
    route.navigator?.removeRoute(route);
  }

  // The page the update was offered on may be gone by now (it takes a
  // while): what follows doesn't depend on it.
  var allowed =
      await _platformChannel.invokeMethod<bool>('canInstallPackages') ?? false;
  if (!allowed) {
    final here = context.mounted ? context : _appContext();
    if (here == null) return;
    final open = await showStyledPlayerDialog<String>(
      // ignore: use_build_context_synchronously, mounted checked just above
      here,
      title: l10n.updateInstallPermissionTitle,
      showCancel: true,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Text(
              l10n.updateInstallPermissionBody,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ),
          _UpdateOption(
            icon: Icons.settings_rounded,
            label: l10n.updateOpenSettings,
            value: 'settings',
            autofocus: true,
          ),
        ],
      ),
    );
    if (open != 'settings') return;
    final opened = await _platformChannel.invokeMethod<bool>(
          'openInstallPermissionSettings',
        ) ??
        false;
    if (opened) await _untilAppResumes();
    allowed =
        await _platformChannel.invokeMethod<bool>('canInstallPackages') ??
            false;
    if (!allowed) {
      tell(l10n.updateInstallPermissionMissing);
      return;
    }
  }

  final started = await _platformChannel.invokeMethod<bool>(
        'installApk',
        {'path': path},
      ) ??
      false;
  if (started) return;
  // Said where it can't be missed: a passing message was easy not to see.
  final here = context.mounted ? context : _appContext();
  if (here == null) return tell(l10n.updateInstallFailed);
  await showStyledPlayerDialog<void>(
    // ignore: use_build_context_synchronously, mounted checked just above
    here,
    title: l10n.updateInstallFailed,
    builder: (dialogContext) => Align(
      alignment: Alignment.bottomRight,
      child: TextButton(
        autofocus: true,
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: Text(l10n.close, style: const TextStyle(color: Colors.white)),
      ),
    ),
  );
}

Future<void> _downloadTo(
  Uri uri,
  File file,
  ValueNotifier<double?> progress,
) async {
  if (await file.exists()) await file.delete();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode != 200) {
      throw HttpException('status ${response.statusCode}', uri: uri);
    }
    final total = response.contentLength;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (total > 0 && received != total) {
      throw HttpException('incomplete download', uri: uri);
    }
  } finally {
    client.close(force: true);
  }
}

/// The app's own navigator, always there.
BuildContext? _appContext() {
  final context = appRouter.routerDelegate.navigatorKey.currentContext;
  return context != null && context.mounted ? context : null;
}

/// Completes once the app comes back to the foreground after leaving it (the
/// user went to Settings and returned), or after ten minutes.
Future<void> _untilAppResumes() {
  final done = Completer<void>();
  var left = false;
  final listener = AppLifecycleListener(
    onStateChange: (state) {
      if (state != AppLifecycleState.resumed) {
        left = true;
      } else if (left && !done.isCompleted) {
        done.complete();
      }
    },
  );
  return done.future
      .timeout(const Duration(minutes: 10), onTimeout: () {})
      .whenComplete(listener.dispose);
}

class _UpdateProgressBody extends StatelessWidget {
  const _UpdateProgressBody({required this.progress, required this.failed});

  final ValueNotifier<double?> progress;
  final ValueNotifier<String?> failed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: AnimatedBuilder(
        animation: Listenable.merge([progress, failed]),
        builder: (context, _) {
          final error = failed.value;
          if (error != null) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.bottomRight,
                  child: TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.close,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          }
          final value = progress.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                value == null ? '' : '${(value * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UpdateOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool autofocus;

  const _UpdateOption({
    required this.icon,
    required this.label,
    required this.value,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      autofocus: autofocus,
      focusColor: Colors.white24,
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Colors.white70),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(fontSize: 15, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
