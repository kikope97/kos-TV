import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/media_bar_state.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/media_bar.dart';
import 'package:moonfin/ui/widgets/mediabar/media_bar_text.dart';

final es = lookupAppLocalizations(const Locale('es'));
final en = lookupAppLocalizations(const Locale('en'));

/// Kos TV: what every layout of the banner writes, in the person's language.
void main() {
  test('a length reads as on the title\'s page', () {
    expect(mediaBarRuntime(const Duration(minutes: 105), es), '1 h 45 min');
    expect(mediaBarRuntime(const Duration(minutes: 45), es), '45 min');
    expect(mediaBarRuntime(const Duration(minutes: 105), en), '1h 45m');
  });

  test('no titles with a backdrop is said in Spanish', () {
    expect(
      describeMediaBarError(const MediaBarNoBackdrops(), es),
      es.mediaBarNoBackdrops,
    );
    expect(es.mediaBarNoBackdrops, isNot(en.mediaBarNoBackdrops));
  });

  // Kos TV: on the TV and the web a trailer that failed was left out for the
  // whole session; now everywhere gets another try, as the phone did.
  test('a trailer that failed is tried again after a while', () {
    fakeAsync((async) {
      final failures = MediaBarTrailerFailures(
        retryAfter: const Duration(minutes: 5),
      );
      failures.mark('film');
      expect(failures.isBlocked('film'), isTrue);
      expect(failures.isBlocked('other'), isFalse);

      async.elapse(const Duration(minutes: 4));
      expect(failures.isBlocked('film'), isTrue);
      async.elapse(const Duration(minutes: 1));
      expect(failures.isBlocked('film'), isFalse);

      failures
        ..mark('gone')
        ..retainOnly(['film']);
      expect(failures.isBlocked('gone'), isFalse);
    });
  });
}
