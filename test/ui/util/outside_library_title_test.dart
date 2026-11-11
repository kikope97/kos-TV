import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/ui/util/outside_library_title.dart';
import 'package:server_core/server_core.dart';

class _Client extends Mock implements MediaServerClient {}

class _Items extends Mock implements ItemsApi {}

/// Kos TV: a title from an outside list opens the server's own copy when it
/// has one, found by its TMDB or IMDb id.
void main() {
  late _Client client;
  late _Items items;
  late List<String?> asked;

  setUp(() {
    client = _Client();
    items = _Items();
    asked = [];
    when(() => client.itemsApi).thenReturn(items);
    when(
      () => items.getItems(
        anyProviderIdEquals: any(named: 'anyProviderIdEquals'),
        includeItemTypes: any(named: 'includeItemTypes'),
        recursive: any(named: 'recursive'),
        limit: any(named: 'limit'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#anyProviderIdEquals] as String?;
      asked.add(key);
      return key == 'imdb.tt0111161'
          ? {
              'Items': [
                {'Id': 'abc', 'Name': 'Cadena perpetua'},
              ],
            }
          : {'Items': <Object>[]};
    });
  });

  test('finds it by its TMDB id, then by its IMDb id', () async {
    final id = await findInLibrary(
      tmdbId: '278',
      imdbId: 'tt0111161',
      series: false,
      client: client,
    );

    expect(id, 'abc');
    expect(asked, ['tmdb.278', 'imdb.tt0111161']);
  });

  test('a title the server lacks finds nothing', () async {
    final id = await findInLibrary(tmdbId: '999', client: client);

    expect(id, isNull);
    expect(asked, ['tmdb.999']);
  });

  test('without ids it asks nothing', () async {
    expect(await findInLibrary(client: client), isNull);
    expect(asked, isEmpty);
  });
}
