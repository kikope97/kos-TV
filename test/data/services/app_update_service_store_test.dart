import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/app_update_service.dart';

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
}
