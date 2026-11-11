import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/l10n/app_localizations_es.dart';
import 'package:moonfin/l10n/current_app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';

/// Kos TV ships in Spanish and English only, and starts in Spanish.
void main() {
  const es = Locale('es');
  const en = Locale('en');

  test('the app knows Spanish and English', () {
    expect(AppLocalizations.supportedLocales, unorderedEquals([es, en]));
  });

  test('the app starts in Spanish, whatever the TV is set to', () {
    expect(UserPreferences.languageOverride.defaultValue, 'es');
  });

  group('resolveAppUiLocale', () {
    test('gives Spanish to any Spanish-speaking country', () {
      expect(resolveAppUiLocale(const Locale('es', 'ES')), es);
      expect(resolveAppUiLocale(const Locale('es', 'MX')), es);
      expect(resolveAppUiLocale(const Locale('es', 'AR')), es);
      expect(
        resolveAppUiLocale(
          const Locale.fromSubtags(languageCode: 'es', countryCode: '419'),
        ),
        es,
      );
    });

    test('keeps English for English', () {
      expect(resolveAppUiLocale(const Locale('en', 'US')), en);
      expect(resolveAppUiLocale(const Locale('en', 'GB')), en);
    });

    test('falls back to Spanish for every other language', () {
      expect(resolveAppUiLocale(const Locale('fr', 'FR')), es);
      expect(resolveAppUiLocale(const Locale('ca')), es);
      expect(resolveAppUiLocale(const Locale('zh', 'CN')), es);
      expect(resolveAppUiLocale(null), es);
    });
  });

  testWidgets('a TV in French shows the app in Spanish', (tester) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr', 'FR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeResolutionCallback: (locale, _) => resolveAppUiLocale(locale),
        home: const Scaffold(body: Text('kOS TV')),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.text('kOS TV'));
    expect(Localizations.localeOf(context), es);
    expect(AppLocalizations.of(context).runtimeType, AppLocalizationsEs);
  });
}
