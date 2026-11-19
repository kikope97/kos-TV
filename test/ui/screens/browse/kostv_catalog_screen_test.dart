import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/user_data_sync.dart';
import 'package:moonfin/data/utils/blocked_ratings.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/browse/kostv_catalog_screen.dart';
import 'package:server_core/server_core.dart';

import 'book_category_test_harness.dart';

/// A library of films, a page at a time, that can be told to fail.
class _Films extends Fake implements ItemsApi {
  _Films(this.films);

  final List<Map<String, dynamic>> films;

  /// The pages asked for, with what each asked.
  final pages = <Map<String, dynamic>>[];

  /// A page from this start on fails, once.
  int? failFrom;

  static String _named(Symbol symbol) {
    final text = symbol.toString();
    return text.substring(8, text.length - 2);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (_named(invocation.memberName) != 'getItems') {
      return Future.value(const {'Items': <dynamic>[], 'TotalRecordCount': 0});
    }
    final args = {
      for (final entry in invocation.namedArguments.entries)
        _named(entry.key): entry.value,
    };
    final types = (args['includeItemTypes'] as List?)?.cast<String>();
    final limit = args['limit'] as int? ?? 0;
    // The films/series count, to offer the choice.
    if (limit == 0) {
      return Future.value({
        'Items': const <dynamic>[],
        'TotalRecordCount': types?.contains('Movie') ?? false
            ? films.length
            : 0,
      });
    }
    pages.add(args);
    final start = args['startIndex'] as int? ?? 0;
    if (failFrom != null && start >= failFrom!) {
      failFrom = null;
      return Future<Map<String, dynamic>>.error(StateError('offline'));
    }
    final filters = (args['filters'] as List?)?.cast<String>() ?? const [];
    final shown = [
      for (final film in films)
        if (!filters.contains('IsUnplayed') ||
            (film['UserData'] as Map)['Played'] != true)
          film,
    ];
    return Future.value({
      'Items': shown.skip(start).take(limit).toList(),
      'TotalRecordCount': shown.length,
    });
  }
}

Map<String, dynamic> _film(int i, {String rating = 'PG'}) => {
  'Id': 'film-$i',
  'Name': 'Film $i',
  'Type': 'Movie',
  'OfficialRating': rating,
  'ServerId': 'server',
  'UserData': {'Played': false, 'IsFavorite': false},
};

class _Factory extends Fake implements MediaServerClientFactory {
  @override
  MediaServerClient clientForServerOrActive(String? serverId) =>
      GetIt.instance<MediaServerClient>();
}

void main() {
  late UserPreferences prefs;

  Future<_Films> setUpFilms(List<Map<String, dynamic>> films) async {
    final library = _Films(films);
    prefs = await setUpBookScreens(FakeBookLibrary());
    final getIt = GetIt.instance;
    final client = getIt<MediaServerClient>();
    when(() => client.itemsApi).thenReturn(library);
    getIt.unregister<MediaServerClientFactory>();
    getIt.registerSingleton<MediaServerClientFactory>(_Factory());
    return library;
  }

  tearDown(() async {
    userDataSync.reset();
    resetParentalFilterCache();
    await tearDownBookScreens();
  });

  Future<void> pumpCatalog(WidgetTester tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const KostvCatalogScreen(
            title: 'Películas',
            kicker: 'Biblioteca',
            activeRoute: '/libraries',
            parentId: 'lib',
          ),
        ),
      ],
      errorBuilder: (_, state) => Scaffold(body: Text(state.uri.toString())),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
  }

  // Kos TV: a page the device's parental control thinned out left a few
  // posters and a spinner for ever on the phone and the web, with nothing
  // to scroll to ask for more.
  testWidgets('a page parental control thins out asks for the next ones', (
    tester,
  ) async {
    final library = await setUpFilms([
      for (var i = 0; i < 180; i++) _film(i, rating: i % 20 == 0 ? 'PG' : 'R'),
    ]);
    await prefs.set(UserPreferences.blockedParentalRatings, 'R');

    await pumpCatalog(tester);

    expect(library.pages.length, greaterThan(1));
    expect(find.text('Film 0'), findsOneWidget);
    expect(find.text('Film 60'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a next page that fails says so and can be tried again', (
    tester,
  ) async {
    final library =
        await setUpFilms([
            for (var i = 0; i < 90; i++) _film(i, rating: i < 2 ? 'PG' : 'R'),
          ])
          ..failFrom = 60;
    await prefs.set(UserPreferences.blockedParentalRatings, 'R');

    await pumpCatalog(tester);
    expect(find.text('No se han podido cargar más títulos'), findsOneWidget);

    // Pressed where it is (scrolling down to it would ask again too).
    tester
        .widget<FilledButton>(
          find.ancestor(
            of: find.text('Reintentar'),
            matching: find.byType(FilledButton),
          ),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('No se han podido cargar más títulos'), findsNothing);
    expect(library.pages.last['startIndex'], 60);
  });

  testWidgets('a first page that fails can be tried again', (tester) async {
    final library = await setUpFilms([for (var i = 0; i < 3; i++) _film(i)])
      ..failFrom = 0;

    await pumpCatalog(tester);
    expect(find.text('No se ha podido cargar la biblioteca'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Film 2'), findsOneWidget);
    expect(library.pages, hasLength(2));
  });

  // Kos TV: Jellyfin doesn't group a query with these filters, so the
  // collection came beside its own films.
  testWidgets('with «Sin ver» the collections aren\'t asked for', (
    tester,
  ) async {
    final library = await setUpFilms([for (var i = 0; i < 3; i++) _film(i)]);
    await prefs.set(UserPreferences.groupItemsIntoCollections, true);

    await pumpCatalog(tester);
    expect(library.pages.last['includeItemTypes'], contains('BoxSet'));
    expect(library.pages.last['collapseBoxSetItems'], isTrue);

    await tester.tap(find.text('Sin ver'));
    await tester.pumpAndSettle();
    expect(library.pages.last['includeItemTypes'], isNot(contains('BoxSet')));
    expect(library.pages.last['collapseBoxSetItems'], isFalse);
  });

  // Kos TV: a film watched with «Sin ver» on stayed in the grid.
  testWidgets('with «Sin ver», a film watched leaves the grid', (tester) async {
    await setUpFilms([for (var i = 0; i < 3; i++) _film(i)]);

    await pumpCatalog(tester);
    await tester.tap(find.text('Sin ver'));
    await tester.pumpAndSettle();
    expect(find.text('Film 1'), findsOneWidget);
    expect(find.text('3 títulos'), findsOneWidget);

    userDataSync.publish('film-1', {'Played': true});
    await tester.pumpAndSettle();
    expect(find.text('Film 1'), findsNothing);
    expect(find.text('Film 2'), findsOneWidget);
    expect(find.text('2 títulos'), findsOneWidget);
  });
}
