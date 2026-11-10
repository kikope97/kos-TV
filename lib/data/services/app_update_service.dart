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

  const DesktopUpdateInfo({
    required this.version,
    required this.downloadUri,
    required this.releaseNotesUrl,
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

  static const _lastCheckMsKey = 'app_update_last_check_ms';
  static const _lastNotifiedVersionKey = 'app_update_last_notified_version';

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
    final result = await _checkForUpdate(
      enforceCooldown: true,
      respectNotificationPreference: true,
      suppressIfAlreadyNotified: true,
    );
    return result.update;
  }

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
    final lastCheckMs = _store.getInt(_lastCheckMsKey);
    if (enforceCooldown && lastCheckMs != null && lastCheckMs > 0) {
      final lastCheckAt = DateTime.fromMillisecondsSinceEpoch(lastCheckMs, isUtc: true);
      if (now.difference(lastCheckAt) < _checkCooldown) {
        return const DesktopUpdateCheckResult(
          status: DesktopUpdateCheckStatus.rateLimited,
        );
      }
    }

    await _store.setInt(_lastCheckMsKey, now.millisecondsSinceEpoch);

    final release = await _fetchLatestRelease();
    if (release == null) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.checkFailed,
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
    if (suppressIfAlreadyNotified &&
        _normalizeVersion(lastNotified) == _normalizeVersion(release.version)) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.alreadyNotified,
      );
    }

    await _store.setString(_lastNotifiedVersionKey, release.version);

    return DesktopUpdateCheckResult(
      status: DesktopUpdateCheckStatus.updateAvailable,
      update: DesktopUpdateInfo(
        version: release.version,
        downloadUri: asset != null
            ? Uri.parse(asset.downloadUrl)
            : Uri.parse(release.releaseNotesUrl),
        releaseNotesUrl: release.releaseNotesUrl,
      ),
    );
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

  Future<_LatestRelease?> _fetchLatestRelease() async {
    final client = HttpClient()
      ..userAgent = 'KosTVUpdateChecker/1.0'
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(Uri.https(_latestReleaseHost, _latestReleasePath));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');

      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final tagName = decoded['tag_name']?.toString();
      if (tagName == null || tagName.trim().isEmpty) {
        return null;
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
          assets.add(_ReleaseAsset(name: name, downloadUrl: downloadUrl));
        }
      }

      return _LatestRelease(version: tagName, assets: assets, releaseNotesUrl: htmlUrl);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Asset to download for this build's channel, or null when there is no
  /// single asset to pick (Linux) or none matched.
  _ReleaseAsset? _selectAsset(List<_ReleaseAsset> assets) {
    if (assets.isEmpty) return null;

    switch (AppDistribution.channel) {
      case DistributionChannel.apk:
      case DistributionChannel.androidTvApk:
        final name = androidApkFor(
          AppDistribution.channel,
          [for (final asset in assets) asset.name],
        );
        return name == null
            ? null
            : assets.firstWhere((asset) => asset.name == name);
      case DistributionChannel.macosDmg:
        return _firstByExtension(assets, const ['.dmg']);
      case DistributionChannel.windows:
        final isArm64 = Platform.version.toLowerCase().contains('windows_arm64');
        if (isArm64) {
          return _firstWhere(assets, '.exe', requireSubstring: 'arm64') ??
              _firstByExtension(assets, const ['.exe']);
        } else {
          return _firstWhere(assets, '.exe', excludeSubstring: 'arm64') ??
              _firstByExtension(assets, const ['.exe']);
        }
      default:
        return null;
    }
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

  _ReleaseAsset? _firstWhere(
    List<_ReleaseAsset> assets,
    String extension, {
    String? requireSubstring,
    String? excludeSubstring,
  }) {
    for (final asset in assets) {
      final lower = asset.name.toLowerCase();
      if (!lower.endsWith(extension)) continue;
      if (requireSubstring != null && !lower.contains(requireSubstring)) continue;
      if (excludeSubstring != null && lower.contains(excludeSubstring)) continue;
      return asset;
    }
    return null;
  }

  _ReleaseAsset? _firstByExtension(List<_ReleaseAsset> assets, List<String> preferredExtensions) {
    for (final extension in preferredExtensions) {
      for (final asset in assets) {
        if (asset.name.toLowerCase().endsWith(extension)) {
          return asset;
        }
      }
    }
    return null;
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

  const _ReleaseAsset({required this.name, required this.downloadUrl});
}
