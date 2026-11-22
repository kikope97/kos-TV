import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../preference/user_preferences.dart';
import '../../util/app_distribution.dart';
import 'moonbase_endpoint.dart';

enum DesktopUpdateCheckStatus {
  updateAvailable,
  upToDate,
  checkFailed,
  unsupportedPlatform,
  managedByStore,
  disabledByPreference,
  rateLimited,
  alreadyNotified,
}

/// Kos TV: what the server plugin's update route answered.
enum PluginUpdateAnswer {
  /// It answered with what it has (an update, or `Available: false`).
  answered,

  /// It answered, but has nothing to say: a plugin without the route (404)
  /// or one that turned the request down (400). Nothing to update to, and
  /// asking again soon would get the same.
  noRoute,

  /// No usable answer: no network, no session, a server error.
  failed,
}

class DesktopUpdateCheckResult {
  final DesktopUpdateCheckStatus status;
  final DesktopUpdateInfo? update;

  const DesktopUpdateCheckResult({
    required this.status,
    this.update,
  });
}

class DesktopUpdateInfo {
  final String version;

  /// Kos TV: the Android version code of the update, as the plugin gives it.
  final int? versionCode;

  /// Kos TV: where the APK is downloaded from, on the home server.
  final Uri downloadUri;

  /// Kos TV: the headers the download goes with (the Jellyfin session's
  /// token): the plugin only serves the APK to a signed-in device.
  final Map<String, String> downloadHeaders;

  /// Kos TV: what is new in it, as written when it was published, if anything.
  final String? notes;

  /// Kos TV: what the plugin says the download weighs and its SHA-256 (in
  /// hex), so a download that doesn't match isn't installed.
  final int? size;
  final String? sha256;

  const DesktopUpdateInfo({
    required this.version,
    required this.downloadUri,
    this.versionCode,
    this.downloadHeaders = const {},
    this.notes,
    this.size,
    this.sha256,
  });
}

class AppUpdateService {
  /// Kos TV: [endpoint], [dio], [channel], [installedVersionCode] and
  /// [storeInstalled] are for tests; they default to the signed-in server's
  /// plugin, the build's channel and the installed package.
  AppUpdateService(
    this._store,
    this._userPreferences, {
    Future<MoonbaseEndpoint?> Function()? endpoint,
    Dio? dio,
    DistributionChannel? channel,
    Future<int?> Function()? installedVersionCode,
    Future<bool> Function()? storeInstalled,
  }) : _dio =
           dio ??
           moonbaseDio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 10),
             ),
           ),
       _endpointOverride = endpoint,
       _channel = channel ?? AppDistribution.channel,
       _installedVersionCode = installedVersionCode ?? _packageVersionCode,
       _storeInstalledOverride = storeInstalled;

  /// Kos TV: the server plugin's route that says whether there is a newer
  /// APK for this kind of device (see docs/actualizaciones-servidor.md,
  /// «Contrato app ↔ complemento»). The app asks nobody else: GitHub is not
  /// asked any more.
  static const updatePath = '/Moonfin/Kostv/Update';

  /// How often the automatic check may ask the plugin. Short enough that a new
  /// version reaches the TVs the same day.
  static const _checkCooldown = Duration(hours: 6);

  /// Kos TV: after a check that got no answer (no network yet as the TV wakes
  /// up, a server error), the next one may go this soon, instead of waiting
  /// the whole [_checkCooldown].
  static const _retryAfterFailure = Duration(minutes: 5);

  /// When the plugin last answered a check.
  static const _lastCheckMsKey = 'app_update_last_check_ms';

  /// Kos TV: when a check last got no answer.
  static const _lastFailedCheckMsKey = 'kostv_update_last_failed_check_ms';
  static const _lastNotifiedVersionKey = 'app_update_last_notified_version';
  static const _lastNotifiedAtKey = 'kostv_update_last_offered_at';
  static const _offerAgainAfter = Duration(hours: 24);

  /// Installers that deliver their own updates. The distribution channel only
  /// records which artifact a build came from, and stores that redistribute the
  /// sideload APK unchanged (the Amazon Appstore does) would otherwise offer a
  /// download they can never install.
  static const _storeInstallerPackages = <String>{
    'com.android.vending',
    'com.amazon.venezia',
    'com.sec.android.app.samsungapps',
    'com.huawei.appmarket',
    'com.xiaomi.mipicks',
    'org.fdroid.fdroid',
  };

  static bool isStoreInstaller(String? installer) {
    return _storeInstallerPackages.contains(
      installer?.trim().toLowerCase() ?? '',
    );
  }

  final PreferenceStore _store;
  final UserPreferences _userPreferences;
  final Dio _dio;
  final Future<MoonbaseEndpoint?> Function()? _endpointOverride;
  final DistributionChannel _channel;
  final Future<int?> Function() _installedVersionCode;
  final Future<bool> Function()? _storeInstalledOverride;

  Future<DesktopUpdateInfo?> checkForUpdateIfDue() async {
    final result = await checkForUpdateIfDueDetailed();
    return result.update;
  }

  /// Kos TV: [checkForUpdateIfDue] saying how it went, so a check that got no
  /// answer can be tried again soon.
  Future<DesktopUpdateCheckResult> checkForUpdateIfDueDetailed() {
    return _checkForUpdate(
      enforceCooldown: true,
      respectNotificationPreference: true,
      suppressIfAlreadyNotified: true,
    );
  }

  /// Kos TV: how long after a check that got no answer the automatic one may
  /// go again.
  static Duration get retryAfterFailure => _retryAfterFailure;

  Future<DesktopUpdateInfo?> checkForUpdateNow() async {
    final result = await checkForUpdateNowDetailed();
    return result.update;
  }

  Future<DesktopUpdateCheckResult> checkForUpdateNowDetailed() {
    return _checkForUpdate(
      enforceCooldown: false,
      respectNotificationPreference: false,
      suppressIfAlreadyNotified: false,
    );
  }

  Future<DesktopUpdateCheckResult> _checkForUpdate({
    required bool enforceCooldown,
    required bool respectNotificationPreference,
    required bool suppressIfAlreadyNotified,
  }) async {
    // Kos TV: only the Android sideload builds update themselves, through
    // the plugin; the web and iOS have no updater.
    final kind = updateKindFor(_channel);
    if (kind == null) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.unsupportedPlatform,
      );
    }

    if (await _isStoreInstalled()) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.managedByStore,
      );
    }

    if (respectNotificationPreference) {
      final notificationsEnabled = _userPreferences.get(UserPreferences.updateNotificationsEnabled);
      if (!notificationsEnabled) {
        return const DesktopUpdateCheckResult(
          status: DesktopUpdateCheckStatus.disabledByPreference,
        );
      }
    }

    final now = DateTime.now().toUtc();
    if (enforceCooldown &&
        !isCheckDue(
          now: now,
          lastAnsweredMs: _store.getInt(_lastCheckMsKey),
          lastFailedMs: _store.getInt(_lastFailedCheckMsKey),
        )) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.rateLimited,
      );
    }

    final installedCode = await _installedVersionCode() ?? 0;
    final fetched = await _fetchUpdate(kind, installedCode);
    // Kos TV: the long wait starts once the plugin has answered. A check that
    // got no answer (the wifi still coming back as the TV wakes up) only
    // holds the next one back a few minutes.
    if (fetched.answer == PluginUpdateAnswer.failed) {
      await _store.setInt(_lastFailedCheckMsKey, now.millisecondsSinceEpoch);
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.checkFailed,
      );
    }
    await _store.setInt(_lastCheckMsKey, now.millisecondsSinceEpoch);
    await _store.remove(_lastFailedCheckMsKey);
    final update = fetched.update;
    if (update == null) {
      // Kos TV: nothing newer published (or a plugin without the route).
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.upToDate,
      );
    }

    final lastNotified = _store.getString(_lastNotifiedVersionKey);
    // Kos TV: a version turned down for now (Cancel, a failed download, the
    // installer closed) is offered again the next day, not never.
    final lastAt = DateTime.tryParse(
      _store.getString(_lastNotifiedAtKey) ?? '',
    );
    final offeredLately =
        lastAt != null &&
        DateTime.now().difference(lastAt) < _offerAgainAfter;
    if (suppressIfAlreadyNotified &&
        offeredLately &&
        lastNotified?.trim() == update.version) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.alreadyNotified,
      );
    }

    await _store.setString(_lastNotifiedVersionKey, update.version);
    await _store.setString(
      _lastNotifiedAtKey,
      DateTime.now().toIso8601String(),
    );

    return DesktopUpdateCheckResult(
      status: DesktopUpdateCheckStatus.updateAvailable,
      update: update,
    );
  }

  /// Kos TV: whether the automatic check may ask the plugin at [now]: once
  /// [_checkCooldown] has gone by since it last answered, and
  /// [_retryAfterFailure] since a check last got no answer.
  @visibleForTesting
  static bool isCheckDue({
    required DateTime now,
    int? lastAnsweredMs,
    int? lastFailedMs,
  }) {
    bool within(int? ms, Duration wait) {
      if (ms == null || ms <= 0) return false;
      final at = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      final since = now.difference(at);
      // A time ahead of the clock (the clock set back) doesn't hold it back.
      return !since.isNegative && since < wait;
    }

    return !within(lastAnsweredMs, _checkCooldown) &&
        !within(lastFailedMs, _retryAfterFailure);
  }

  /// Kos TV: which APK the plugin is asked for: the TV build's (`tv`) or the
  /// phone build's (`phone`). They share one application id, so each only
  /// ever takes its own: installing the other would replace it. Null for
  /// every build that doesn't update itself.
  @visibleForTesting
  static String? updateKindFor(DistributionChannel channel) =>
      switch (channel) {
        DistributionChannel.androidTvApk => 'tv',
        DistributionChannel.apk => 'phone',
        _ => null,
      };

  /// Whether a store installed this copy. Only the Android APK channels can end
  /// up store-installed while still carrying the in-app updater.
  Future<bool> _isStoreInstalled() async {
    final override = _storeInstalledOverride;
    if (override != null) return override();
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return isStoreInstaller(packageInfo.installerStore);
    } catch (_) {
      return false;
    }
  }

  /// Kos TV: the installed Android version code (`versionCode`), which the
  /// plugin compares against.
  static Future<int?> _packageVersionCode() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return int.tryParse(packageInfo.buildNumber.trim());
    } catch (_) {
      return null;
    }
  }

  /// Kos TV: what a status code from the plugin's update route means.
  @visibleForTesting
  static PluginUpdateAnswer answerFor(int statusCode) => switch (statusCode) {
    >= 200 && < 300 => PluginUpdateAnswer.answered,
    // An older plugin has no such route; 400 is a kind it doesn't take.
    404 || 400 => PluginUpdateAnswer.noRoute,
    _ => PluginUpdateAnswer.failed,
  };

  Future<MoonbaseEndpoint?> _endpoint() {
    final override = _endpointOverride;
    if (override != null) return override();
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<MediaServerClient>()) return Future.value();
    return moonbaseEndpoint(getIt<MediaServerClient>(), _dio);
  }

  static const _fetchFailed = (answer: PluginUpdateAnswer.failed, update: null);

  Future<({PluginUpdateAnswer answer, DesktopUpdateInfo? update})>
  _fetchUpdate(String kind, int installedCode) async {
    try {
      // Kos TV: asked with the session of whoever is signed in to the home
      // server; signed out there is no one to ask yet.
      final ep = await _endpoint();
      if (ep == null) return _fetchFailed;
      final response = await _dio.get<dynamic>(
        '${_trimSlash(ep.base)}$updatePath',
        queryParameters: {'kind': kind, 'versionCode': '$installedCode'},
        options: Options(
          headers: ep.headers,
          validateStatus: (_) => true,
          responseType: ResponseType.json,
        ),
      );
      final answer = answerFor(response.statusCode ?? 0);
      if (answer != PluginUpdateAnswer.answered) {
        return (answer: answer, update: null);
      }
      return (
        answer: PluginUpdateAnswer.answered,
        update: parseUpdate(
          response.data,
          serverBase: ep.base,
          headers: ep.headers,
          installedVersionCode: installedCode,
        ),
      );
    } catch (e) {
      debugPrint('[AppUpdateService] update check failed: $e');
      return _fetchFailed;
    }
  }

  /// Kos TV: the update the plugin's answer [data] offers, or null when it
  /// offers none (`Available: false`) or what it offers can't be trusted: not
  /// newer than [installedVersionCode], no SHA-256, or a download that isn't
  /// an `.apk` path on the home server ([serverBase]). [headers] go with the
  /// download.
  @visibleForTesting
  static DesktopUpdateInfo? parseUpdate(
    Object? data, {
    required String serverBase,
    required Map<String, String> headers,
    required int installedVersionCode,
  }) {
    var map = data;
    if (map is String) {
      try {
        map = jsonDecode(map);
      } catch (_) {
        return null;
      }
    }
    if (map is! Map) return null;
    Object? field(String name) =>
        map is Map
            ? (map[name] ??
                  map['${name[0].toLowerCase()}${name.substring(1)}'])
            : null;

    if (field('Available') != true) return null;
    final versionName = field('VersionName')?.toString().trim() ?? '';
    final code = field('VersionCode');
    final versionCode = code is int ? code : int.tryParse('${code ?? ''}');
    final sha = field('Sha256')?.toString().trim().toLowerCase() ?? '';
    final url = field('Url')?.toString().trim() ?? '';
    final size = field('Size');
    final notes = field('Notes')?.toString().trim();
    if (versionName.isEmpty ||
        versionCode == null ||
        versionCode <= installedVersionCode ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      return null;
    }
    final download = downloadUriFor(serverBase, url);
    if (download == null) return null;
    return DesktopUpdateInfo(
      version: versionName,
      versionCode: versionCode,
      downloadUri: download,
      downloadHeaders: Map.unmodifiable(headers),
      notes: notes == null || notes.isEmpty ? null : notes,
      size: size is int && size > 0 ? size : null,
      sha256: sha,
    );
  }

  /// Kos TV: where the APK at [url] (a path the plugin gives, relative to the
  /// server) is on the home server at [serverBase], or null when it isn't
  /// such a path: an address elsewhere would get the session's token, and
  /// only an `.apk` is handed to the installer. Plain http only when the
  /// server itself is reached that way (a household server on the LAN).
  @visibleForTesting
  static Uri? downloadUriFor(String serverBase, String url) {
    if (!url.startsWith('/') || url.startsWith('//') || url.contains('\\')) {
      return null;
    }
    final base = Uri.tryParse(_trimSlash(serverBase));
    if (base == null ||
        !(base.isScheme('https') || base.isScheme('http')) ||
        base.host.isEmpty) {
      return null;
    }
    final download = Uri.tryParse('${_trimSlash(serverBase)}$url');
    if (download == null ||
        download.scheme != base.scheme ||
        download.host != base.host ||
        download.port != base.port ||
        download.path.split('/').contains('..') ||
        !download.path.toLowerCase().endsWith('.apk')) {
      return null;
    }
    return download;
  }

  static String _trimSlash(String value) {
    var out = value.trim();
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }
}
