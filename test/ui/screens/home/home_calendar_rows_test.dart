import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/repositories/multi_server_repository.dart';
import 'package:moonfin/data/services/home_row_cache_store.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/data/viewmodels/media_bar_view_model.dart';
import 'package:moonfin/preference/home_section_config.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _DataSource extends Mock implements RowDataSource {}

class _MediaBar extends Mock implements MediaBarViewModel {}

class _MultiServer extends Mock implements MultiServerRepository {}

class _PluginSync extends Mock implements PluginSyncService {}

class _Cache extends Fake implements HomeRowCacheStore {
  @override
  Future<List<HomeRow>?> read(String cacheKey) async => null;

  @override
  Future<void> write(String cacheKey, List<HomeRow> rows) async {}
}

/// Kos TV: the server plugin has no Sonarr or Radarr calendar, so Home doesn't
/// ask for those rows even when a setting brought over turns them on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserPreferences prefs;
  late _PluginSync pluginSync;
  late _DataSource source;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    await prefs.setHomeSectionsConfig([
      for (final cfg in HomeSectionConfig.defaults())
        cfg.copyWith(
          enabled:
              cfg.type == HomeSectionType.nextUp ||
              cfg.type == HomeSectionType.radarrCalendar ||
              cfg.type == HomeSectionType.sonarrCalendar,
        ),
    ]);
    await prefs.set(UserPreferences.enableRadarrCalendar, true);
    await prefs.set(UserPreferences.enableSonarrCalendar, true);
    await prefs.set(UserPreferences.mergeContinueWatchingNextUp, false);
    await prefs.set(UserPreferences.enableMultiServerLibraries, false);
    await prefs.set(
      UserPreferences.lastExternalRowsRefreshTime,
      DateTime.now().millisecondsSinceEpoch,
    );

    pluginSync = _PluginSync();
    when(() => pluginSync.pluginAvailable).thenReturn(false);
    when(() => pluginSync.calendarAvailable).thenReturn(false);
    GetIt.instance.registerSingleton<PluginSyncService>(pluginSync);

    source = _DataSource();
    when(() => source.loadNextUp('http://server')).thenAnswer(
      (_) async => HomeRow(
        id: 'nextUp',
        title: 'nextUp',
        rowType: HomeRowType.nextUp,
        totalCount: 1,
        items: [
          AggregatedItem(
            id: 'next',
            serverId: 'server',
            rawData: {'Name': 'x'},
          ),
        ],
      ),
    );
  });

  tearDown(() => GetIt.instance.reset());

  test('the calendar rows are not asked for without a calendar', () async {
    final client = _Client();
    when(() => client.userId).thenReturn('user');
    when(() => client.baseUrl).thenReturn('http://server');
    final mediaBar = _MediaBar();
    when(() => mediaBar.load(force: any(named: 'force')))
        .thenAnswer((_) async {});
    final vm = HomeViewModel(
      dataSource: source,
      prefs: prefs,
      client: client,
      mediaBarViewModel: mediaBar,
      multiServerRepo: _MultiServer(),
      cacheStore: _Cache(),
    );
    addTearDown(vm.dispose);

    await vm.load();

    expect(vm.rows.map((row) => row.id), ['nextUp']);
    verify(() => pluginSync.calendarAvailable).called(greaterThan(0));
    // The server plugin isn't even looked for, as loading those rows does.
    verifyNever(() => client.features);
    // Nothing was fetched for them, so nothing was noted as fetched either.
    expect(prefs.get(UserPreferences.lastRadarrCalendarFetchTime), 0);
    expect(prefs.get(UserPreferences.lastSonarrCalendarFetchTime), 0);
  });
}
