import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/settings/parental_settings_screen.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _Items extends Mock implements ItemsApi {}

// Kos TV: the ratings to block come from the server's own list of every
// rating in the library, in one request, rather than from the first items.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Items items;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<PreferenceStore>(store);
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    items = _Items();
    final client = _Client();
    when(() => client.itemsApi).thenReturn(items);
    GetIt.instance.registerSingleton<MediaServerClient>(client);
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ParentalSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every rating the server lists is offered, in one request', (
    tester,
  ) async {
    when(
      () => items.getQueryFilters(
        includeItemTypes: any(named: 'includeItemTypes'),
      ),
    ).thenAnswer(
      (_) async => const QueryFilterValues(officialRatings: ['es-18', 'TV-MA']),
    );

    await pump(tester);

    expect(find.text('ES-18'), findsOneWidget);
    expect(find.text('TV-MA'), findsOneWidget);
    verifyNever(
      () => items.getItems(
        includeItemTypes: any(named: 'includeItemTypes'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
      ),
    );
  });

  testWidgets('a server that lists none still has its items read', (
    tester,
  ) async {
    when(
      () => items.getQueryFilters(
        includeItemTypes: any(named: 'includeItemTypes'),
      ),
    ).thenAnswer((_) async => const QueryFilterValues());
    when(
      () => items.getItems(
        includeItemTypes: any(named: 'includeItemTypes'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {'OfficialRating': 'PG-13'},
        ],
        'TotalRecordCount': 1,
      },
    );

    await pump(tester);

    expect(find.text('PG-13'), findsOneWidget);
  });
}
