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

    test('rate limits and server errors are failures', () {
      for (final status in [403, 429, 500, 503]) {
        expect(
          AppUpdateService.latestReleaseAnswerFor(status),
          LatestReleaseAnswer.failed,
          reason: '$status',
        );
      }
    });
  });
}
