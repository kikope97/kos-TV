import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../preference/user_preferences.dart';
import '../../util/app_distribution.dart';

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

/// Kos TV: what GitHub's latest-release endpoint answered.
enum LatestReleaseAnswer {
  /// A published release came back.
  release,

  /// The repository has no published release yet. GitHub answers 404, and
  /// pre-releases (the test builds) don't count: there is nothing to update to.
  noRelease,

  /// GitHub answered, but turned the request down for its rate limit (403 or
  /// 429). It did answer: asking again soon would only be turned down again.
  rateLimited,

  /// No usable answer: no network, a GitHub error.
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

  /// Direct download link for the matching release asset, or the releases page
  /// when there is no single asset to pick (e.g. Linux).
  final Uri downloadUri;
  final String releaseNotesUrl;

  /// Kos TV: what GitHub says the download weighs and its SHA-256 (in hex),
  /// when it says, so a download that doesn't match isn't installed.
  final int? size;
  final String? sha256;

  const DesktopUpdateInfo({
    required this.version,
    required this.downloadUri,
    required this.releaseNotesUrl,
    this.size,
    this.sha256,
  });
}

class AppUpdateService {
  AppUpdateService(this._store, this._userPreferences);

  /// Kos TV: GitHub repository whose latest release is checked for updates, as
  /// `owner/name` (Moonfin pointed at Moonfin-Client/Moonfin-Core). Empty
  /// disables update checks entirely. A release offers the APK whose name has
  /// "AndroidTV" to the TV build and the other APK to phones (see
  /// [_selectAsset]); build.yml's release job uploads both.
  static const String _releaseRepo = 'kikope97/kos-TV';

  static const _latestReleaseHost = 'api.github.com';
  static const _latestReleasePath = '/repos/$_releaseRepo/releases/latest';

  /// How often the automatic check may ask GitHub. Short enough that a new
  /// release reaches the TVs the same day, and well inside GitHub's 60
  /// unauthenticated requests an hour for a household on one address.
  static const _checkCooldown = Duration(hours: 6);

  /// Kos TV: after a check that got no answer (no network yet as the TV wakes
  /// up, a GitHub error), the next one may go this soon, instead of waiting
  /// the whole [_checkCooldown]. Long enough never to hammer GitHub.
  static const _retryAfterFailure = Duration(minutes: 5);

  /// When GitHub last answered a check.
  static const _lastCheckMsKey = 'app_update_last_check_ms';

  /// Kos TV: when a check last got no answer.
  static const _lastFailedCheckMsKey = 'kostv_update_last_failed_check_ms';
  static const _lastNotifiedVersionKey = 'app_update_last_notified_version';
  static const _lastNotifiedAtKey = 'kostv_update_last_offered_at';
  static const _offerAgainAfter = Duration(hours: 24);

  /// Installers that deliver their own updates. The distribution channel only
  /// records which artifact a build came from, and stores that redistribute the
  /// sideload APK unchanged (the Amazon Appstore does) would otherwise offer a
  /// GitHub download they can never install.
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
    if (_releaseRepo.isEmpty || !AppDistribution.supportsInAppUpdates) {
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

    final fetched = await _fetchLatestRelease();
    // Kos TV: the long wait starts once GitHub has answered. A check that got
    // no answer (the wifi still coming back as the TV wakes up) only holds the
    // next one back a few minutes.
    if (fetched.answer == LatestReleaseAnswer.failed) {
      await _store.setInt(_lastFailedCheckMsKey, now.millisecondsSinceEpoch);
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.checkFailed,
      );
    }
    await _store.setInt(_lastCheckMsKey, now.millisecondsSinceEpoch);
    await _store.remove(_lastFailedCheckMsKey);
    if (fetched.answer == LatestReleaseAnswer.rateLimited) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.checkFailed,
      );
    }
    final release = fetched.release;
    if (release == null) {
      // Kos TV: nothing published yet, so this build is the newest there is.
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.upToDate,
      );
    }

    final currentVersion = await _currentAppVersion();
    if (!_isNewerVersion(release.version, currentVersion)) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.upToDate,
      );
    }

    final asset = _selectAsset(release.assets);
    // Kos TV: an Android build only offers a release that carries its own APK.
    // A release whose files are still uploading (or that has none for this
    // build) is not an update yet, and isn't recorded as notified, so the
    // next check offers it once the APK is there.
    if (asset == null && _isAndroidApkChannel) {
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
        _normalizeVersion(lastNotified) == _normalizeVersion(release.version)) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.alreadyNotified,
      );
    }

    await _store.setString(_lastNotifiedVersionKey, release.version);
    await _store.setString(
      _lastNotifiedAtKey,
      DateTime.now().toIso8601String(),
    );

    return DesktopUpdateCheckResult(
      status: DesktopUpdateCheckStatus.updateAvailable,
      update: DesktopUpdateInfo(
        version: release.version,
        downloadUri: asset != null
            ? Uri.parse(asset.downloadUrl)
            : Uri.parse(release.releaseNotesUrl),
        releaseNotesUrl: release.releaseNotesUrl,
        size: asset?.size,
        sha256: asset?.sha256,
      ),
    );
  }

  /// Kos TV: whether the automatic check may ask GitHub at [now]: once
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

  static bool get _isAndroidApkChannel =>
      AppDistribution.channel == DistributionChannel.apk ||
      AppDistribution.channel == DistributionChannel.androidTvApk;

  /// Whether a store installed this copy. Only the Android APK channels can end
  /// up store-installed while still carrying the in-app updater.
  Future<bool> _isStoreInstalled() async {
    final channel = AppDistribution.channel;
    if (channel != DistributionChannel.apk &&
        channel != DistributionChannel.androidTvApk) {
      return false;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return isStoreInstaller(packageInfo.installerStore);
    } catch (_) {
      return false;
    }
  }

  Future<String> _currentAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      if (version.isNotEmpty) {
        return version;
      }
    } catch (_) {}
    return '0.0.0';
  }

  /// Kos TV: what a status code from the latest-release endpoint means.
  @visibleForTesting
  static LatestReleaseAnswer latestReleaseAnswerFor(int statusCode) =>
      switch (statusCode) {
        >= 200 && < 300 => LatestReleaseAnswer.release,
        404 => LatestReleaseAnswer.noRelease,
        403 || 429 => LatestReleaseAnswer.rateLimited,
        _ => LatestReleaseAnswer.failed,
      };

  static const _fetchFailed = (
    answer: LatestReleaseAnswer.failed,
    release: null,
  );

  Future<({LatestReleaseAnswer answer, _LatestRelease? release})>
  _fetchLatestRelease() async {
    final client = HttpClient()
      ..userAgent = 'KosTVUpdateChecker/1.0'
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(Uri.https(_latestReleaseHost, _latestReleasePath));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');

      final response = await request.close().timeout(const Duration(seconds: 10));
      final answer = latestReleaseAnswerFor(response.statusCode);
      if (answer != LatestReleaseAnswer.release) {
        await response.drain<void>();
        return (answer: answer, release: null);
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return _fetchFailed;
      }

      final tagName = decoded['tag_name']?.toString();
      if (tagName == null || tagName.trim().isEmpty) {
        return _fetchFailed;
      }

      final htmlUrl = decoded['html_url']?.toString() ??
          'https://github.com/$_releaseRepo/releases/latest';

      final assetsJson = decoded['assets'];
      final assets = <_ReleaseAsset>[];
      if (assetsJson is List) {
        for (final asset in assetsJson) {
          if (asset is! Map) {
            continue;
          }
          final name = asset['name']?.toString();
          final downloadUrl = asset['browser_download_url']?.toString();
          if (name == null || name.isEmpty || downloadUrl == null || downloadUrl.isEmpty) {
            continue;
          }
          final size = asset['size'];
          assets.add(
            _ReleaseAsset(
              name: name,
              downloadUrl: downloadUrl,
              size: size is int && size > 0 ? size : null,
              sha256: sha256FromDigest(asset['digest']?.toString()),
            ),
          );
        }
      }

      return (
        answer: LatestReleaseAnswer.release,
        release: _LatestRelease(
          version: tagName,
          assets: assets,
          releaseNotesUrl: htmlUrl,
        ),
      );
    } catch (_) {
      return _fetchFailed;
    } finally {
      client.close(force: true);
    }
  }

  /// Asset to download for this build's channel, or null when none matched.
  /// Kos TV: only the Android builds download their update; no desktop build
  /// is made.
  _ReleaseAsset? _selectAsset(List<_ReleaseAsset> assets) {
    if (assets.isEmpty) return null;
    final name = androidApkFor(
      AppDistribution.channel,
      [for (final asset in assets) asset.name],
    );
    return name == null
        ? null
        : assets.firstWhere((asset) => asset.name == name);
  }

  /// Kos TV: the hex SHA-256 in an asset's `digest` as GitHub gives it
  /// (`sha256:…`), or null when it gives none or another kind.
  @visibleForTesting
  static String? sha256FromDigest(String? digest) {
    final value = digest?.trim().toLowerCase() ?? '';
    if (!value.startsWith('sha256:')) return null;
    final hex = value.substring('sha256:'.length);
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
  }

  /// Kos TV: the release file the Android build on [channel] installs, or
  /// null when the release carries none for it. The phone and TV builds share
  /// one application id, so each only ever takes its own APK: installing the
  /// other would replace it. "KosTV" itself contains "tv", hence "androidtv".
  @visibleForTesting
  static String? androidApkFor(
    DistributionChannel channel,
    Iterable<String> names,
  ) {
    final apks = names.where((n) => n.toLowerCase().endsWith('.apk'));
    bool isTv(String name) => name.toLowerCase().contains('androidtv');
    return switch (channel) {
      DistributionChannel.androidTvApk => apks.where(isTv).firstOrNull,
      DistributionChannel.apk => apks.where((n) => !isTv(n)).firstOrNull,
      _ => null,
    };
  }

  bool _isNewerVersion(String candidate, String current) {
    final candidateParts = _parseSemverCore(candidate);
    final currentParts = _parseSemverCore(current);
    final maxLength = candidateParts.length > currentParts.length
        ? candidateParts.length
        : currentParts.length;

    for (var i = 0; i < maxLength; i++) {
      final left = i < candidateParts.length ? candidateParts[i] : 0;
      final right = i < currentParts.length ? currentParts[i] : 0;
      if (left > right) {
        return true;
      }
      if (left < right) {
        return false;
      }
    }
    return false;
  }

  List<int> _parseSemverCore(String raw) {
    final normalized = _normalizeVersion(raw);
    if (normalized.isEmpty) {
      return const [0, 0, 0];
    }

    final core = normalized.split('-').first.split('+').first;
    final pieces = core.split('.');
    final numbers = <int>[];
    for (final piece in pieces) {
      final value = int.tryParse(piece.replaceAll(RegExp(r'[^0-9]'), ''));
      numbers.add(value ?? 0);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers;
  }

  String _normalizeVersion(String? raw) {
    if (raw == null) {
      return '';
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }
}

class _LatestRelease {
  final String version;
  final List<_ReleaseAsset> assets;
  final String releaseNotesUrl;

  const _LatestRelease({
    required this.version,
    required this.assets,
    required this.releaseNotesUrl,
  });
}

class _ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int? size;
  final String? sha256;

  const _ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.size,
    this.sha256,
  });
}
