import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/util/playback_time_label.dart';
import 'package:moonfin/util/rating_format.dart';

void main() {
  final es = lookupAppLocalizations(const Locale('es'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('formatRuntimeShort', () {
    test('reads in Spanish the same way as the banner', () {
      expect(formatRuntimeShort(const Duration(minutes: 44), es), '44 min');
      expect(
        formatRuntimeShort(const Duration(hours: 1, minutes: 35), es),
        '1 h 35 min',
      );
      expect(formatRuntimeShort(const Duration(hours: 2), es), '2 h');
    });

    test('keeps the short English form', () {
      expect(formatRuntimeShort(const Duration(minutes: 44), en), '44m');
      expect(
        formatRuntimeShort(const Duration(hours: 1, minutes: 35), en),
        '1h 35m',
      );
      expect(formatRuntimeShort(const Duration(hours: 2), en), '2h');
    });

    test('treats a negative runtime as zero', () {
      expect(formatRuntimeShort(const Duration(minutes: -5), en), '0m');
    });
  });

  group('formatRatingValue', () {
    test('uses a comma in Spanish', () {
      expect(formatRatingValue(7.1, 'es'), '7,1');
      expect(formatRatingValue(8, 'es'), '8,0');
      expect(formatRatingValue(6.46, es.localeName), '6,5');
    });

    test('uses a point in English', () {
      expect(formatRatingValue(7.1, 'en'), '7.1');
      expect(formatRatingValue(8, en.localeName), '8.0');
    });
  });
}
