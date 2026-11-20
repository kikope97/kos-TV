import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockItemsApi extends Mock implements ItemsApi {}

// Jellyfin's /Studios ignores SortBy and always lists by name, so the row
// has to put the studios in the chosen order itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockItemsApi itemsApi;
  late RowDataSource source;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));

    itemsApi = _MockItemsApi();
    // What Jellyfin answers whatever the sort: name order.
    when(
      () => itemsApi.getStudios(
        parentId: any(named: 'parentId'),
        userId: any(named: 'userId'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          {'Id': 'a', 'Name': 'A24', 'DateCreated': '2020-01-01T00:00:00Z'},
          {
            'Id': 'b',
            'Name': 'Blumhouse',
            'DateCreated': '2024-01-01T00:00:00Z',
          },
          {
            'Id': 'c',
            'Name': 'Cartoon Saloon',
            'DateCreated': '2022-01-01T00:00:00Z',
          },
        ],
        'TotalRecordCount': 3,
      },
    );
    final client = _MockClient();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.userId).thenReturn('user');
    source = RowDataSource(client);
  });

  tearDown(() => GetIt.instance.reset());

  test('picked studios follow the date added order', () async {
    final row = await source.loadStudios(
      'srv1',
      sortBy: 'DateCreated,SortName',
      sortOrder: 'Descending',
      selectedIds: 'a,b,c',
    );

    expect(row.items.map((item) => item.id), ['b', 'c', 'a']);
  });

  test('with nothing picked, Z to A reads the names backwards', () async {
    final row = await source.loadStudios(
      'srv1',
      sortBy: 'SortName',
      sortOrder: 'Descending',
    );

    expect(row.items.map((item) => item.id), ['c', 'b', 'a']);
    // The page is asked for by name, which is all Jellyfin honours.
    verify(
      () => itemsApi.getStudios(
        parentId: any(named: 'parentId'),
        userId: any(named: 'userId'),
        sortBy: 'SortName',
        sortOrder: 'Ascending',
        recursive: any(named: 'recursive'),
        startIndex: any(named: 'startIndex'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
      ),
    ).called(1);
  });
}
