import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/app_update_service.dart';
import 'package:moonfin/util/app_distribution.dart';

void main() {
  group('AppUpdateService.isStoreInstaller', () {
    test('recognizes the stores that redistribute the sideload APK', () {
      expect(AppUpdateService.isStoreInstaller('com.android.vending'), isTrue);
      expect(AppUpdateService.isStoreInstaller('com.amazon.venezia'), isTrue);
      expect(
        AppUpdateService.isStoreInstaller('com.sec.android.app.samsungapps'),
        isTrue,
      );
      expect(AppUpdateService.isStoreInstaller('org.fdroid.fdroid'), isTrue);
    });

    test('matches case-insensitively and ignores surrounding whitespace', () {
      expect(AppUpdateService.isStoreInstaller(' Com.Amazon.Venezia '), isTrue);
    });

    test('sideload installers do not count as stores', () {
      expect(AppUpdateService.isStoreInstaller(null), isFalse);
      expect(AppUpdateService.isStoreInstaller(''), isFalse);
      expect(
        AppUpdateService.isStoreInstaller('com.android.packageinstaller'),
        isFalse,
      );
      expect(
        AppUpdateService.isStoreInstaller(
          'com.google.android.packageinstaller',
        ),
        isFalse,
      );
      expect(AppUpdateService.isStoreInstaller('com.android.shell'), isFalse);
    });
  });

  group('AppUpdateService.androidApkFor', () {
    const release = [
      'KosTV_Android_v1.0.1.apk',
      'KosTV_AndroidTV_v1.0.1.apk',
    ];

    test('the TV build takes the Android TV APK', () {
      expect(
        AppUpdateService.androidApkFor(DistributionChannel.androidTvApk, release),
        'KosTV_AndroidTV_v1.0.1.apk',
      );
    });

    test('the phone build takes the other APK, despite "TV" in KosTV', () {
      expect(
        AppUpdateService.androidApkFor(DistributionChannel.apk, release),
        'KosTV_Android_v1.0.1.apk',
      );
    });

    test('neither build falls back to the other one\'s APK', () {
      expect(
        AppUpdateService.androidApkFor(
          DistributionChannel.androidTvApk,
          const ['KosTV_Android_v1.0.1.apk'],
        ),
        isNull,
      );
      expect(
        AppUpdateService.androidApkFor(
          DistributionChannel.apk,
          const ['KosTV_AndroidTV_v1.0.1.apk'],
        ),
        isNull,
      );
    });

    test('a release without APKs offers nothing', () {
      expect(
        AppUpdateService.androidApkFor(
          DistributionChannel.androidTvApk,
          const ['KosTV_AndroidTV_v1.0.1.aab', 'notes.txt'],
        ),
        isNull,
      );
    });
  });

  group('AppUpdateService.latestReleaseAnswerFor', () {
    test('a published release is read', () {
      expect(
        AppUpdateService.latestReleaseAnswerFor(200),
        LatestReleaseAnswer.release,
      );
    });

    test('no published release yet (404) is not a failure', () {
      // GitHub answers 404 while only pre-releases (the test builds) exist.
      expect(
        AppUpdateService.latestReleaseAnswerFor(404),
        LatestReleaseAnswer.noRelease,
      );
    });

    // Kos TV: a rate limit is an answer (asking again soon would be turned
    // down too), unlike a server error, which is tried again in minutes.
    test('rate limits are told apart from server errors', () {
      for (final status in [403, 429]) {
        expect(
          AppUpdateService.latestReleaseAnswerFor(status),
          LatestReleaseAnswer.rateLimited,
          reason: '$status',
        );
      }
      for (final status in [500, 502, 503]) {
        expect(
          AppUpdateService.latestReleaseAnswerFor(status),
          LatestReleaseAnswer.failed,
          reason: '$status',
        );
      }
    });
  });

  group('AppUpdateService.isCheckDue', () {
    final now = DateTime.utc(2026, 11, 19, 20);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

    test('a first check goes', () {
      expect(AppUpdateService.isCheckDue(now: now), isTrue);
    });

    test('an answer holds the next check back six hours', () {
      expect(
        AppUpdateService.isCheckDue(
          now: now,
          lastAnsweredMs: ago(const Duration(hours: 5)),
        ),
        isFalse,
      );
      expect(
        AppUpdateService.isCheckDue(
          now: now,
          lastAnsweredMs: ago(const Duration(hours: 6, minutes: 1)),
        ),
        isTrue,
      );
    });

    test('no answer only holds it back a few minutes', () {
      // The TV wakes up and the app checks before the wifi is back.
      expect(
        AppUpdateService.isCheckDue(
          now: now,
          lastAnsweredMs: ago(const Duration(days: 1)),
          lastFailedMs: ago(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(
        AppUpdateService.isCheckDue(
          now: now,
          lastAnsweredMs: ago(const Duration(days: 1)),
          lastFailedMs: ago(AppUpdateService.retryAfterFailure),
        ),
        isTrue,
      );
    });

    test('a time ahead of the clock doesn\'t hold it back', () {
      expect(
        AppUpdateService.isCheckDue(
          now: now,
          lastAnsweredMs: now.add(const Duration(days: 30)).millisecondsSinceEpoch,
        ),
        isTrue,
      );
    });
  });

  group('AppUpdateService.sha256FromDigest', () {
    const hex =
        '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

    test('reads the SHA-256 GitHub gives for a file', () {
      expect(AppUpdateService.sha256FromDigest('sha256:$hex'), hex);
      expect(
        AppUpdateService.sha256FromDigest('SHA256:${hex.toUpperCase()}'),
        hex,
      );
    });

    test('gives nothing for a missing or other digest', () {
      expect(AppUpdateService.sha256FromDigest(null), isNull);
      expect(AppUpdateService.sha256FromDigest(''), isNull);
      expect(AppUpdateService.sha256FromDigest('sha512:$hex'), isNull);
      expect(AppUpdateService.sha256FromDigest('sha256:abc'), isNull);
    });
  });
}
