import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/repositories/multi_server_repository.dart';
import 'package:moonfin/data/repositories/user_views_repository.dart';
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

class _Views extends Mock implements UserViewsRepository {}

/// Hands back [cached] and notes what Home asked for and saved.
class _Cache extends Fake implements HomeRowCacheStore {
  _Cache([this.cached]);

  final List<HomeRow>? cached;
  final List<String> readKeys = [];
  final List<List<HomeRow>> writes = [];

  @override
  Future<List<HomeRow>?> read(String cacheKey) async {
    readKeys.add(cacheKey);
    return cached;
  }

  @override
  Future<void> write(String cacheKey, List<HomeRow> rows) async {
    writes.add(rows);
  }
}

HomeRow row(String id, HomeRowType type, {List<String>? items}) => HomeRow(
  id: id,
  title: id,
  rowType: type,
  items: [
    for (final item in items ?? ['$id-1'])
      AggregatedItem(id: item, serverId: 's', rawData: {'Name': item}),
  ],
  totalCount: (items ?? const ['']).length,
);

HomeSectionConfig collection(int n) => HomeSectionConfig.pluginDynamic(
  serverId: 'http://server',
  pluginSection: 'collection',
  pluginAdditionalData: 'c$n',
  pluginDisplayText: 'Collection $n',
  order: n,
);

/// Kos TV: the recommended Home's rows, and what Home keeps of them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(HomeSectionPluginSource.collections);
    registerFallbackValue(
      const HomeRow(id: 'row', title: 'row', rowType: HomeRowType.resume),
    );
  });
  tearDown(() => GetIt.instance.reset());

  final moreId = const HomeSectionConfig(type: HomeSectionType.kostvForYouMore)
      .stableId;

  Future<UserPreferences> prefsWith(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    final store = PreferenceStore();
    await store.init();
    final p = UserPreferences(store);
    await p.set(UserPreferences.enableMultiServerLibraries, false);
    await p.set(
      UserPreferences.lastExternalRowsRefreshTime,
      DateTime.now().millisecondsSinceEpoch,
    );
    return p;
  }

  HomeViewModel model(
    UserPreferences prefs,
    RowDataSource source,
    HomeRowCacheStore cache,
  ) {
    final pluginSync = _PluginSync();
    when(() => pluginSync.pluginAvailable).thenReturn(false);
    if (!GetIt.instance.isRegistered<PluginSyncService>()) {
      GetIt.instance.registerSingleton<PluginSyncService>(pluginSync);
    }
    final client = _Client();
    when(() => client.userId).thenReturn('user');
    when(() => client.baseUrl).thenReturn('http://server');
    final mediaBar = _MediaBar();
    when(() => mediaBar.load(force: any(named: 'force')))
        .thenAnswer((_) async {});
    return HomeViewModel(
      dataSource: source,
      prefs: prefs,
      client: client,
      mediaBarViewModel: mediaBar,
      multiServerRepo: _MultiServer(),
      cacheStore: cache,
    );
  }

  group('recently added beside the recommended rows', () {
    test('the latest media section claims none of the rows made for the '
        'person', () {
      final configs = [
        const HomeSectionConfig(type: HomeSectionType.latestMedia, order: 0),
        const HomeSectionConfig(type: HomeSectionType.kostvArrived, order: 1),
        const HomeSectionConfig(type: HomeSectionType.kostvForYou, order: 2),
        const HomeSectionConfig(
          type: HomeSectionType.kostvForYouMore,
          order: 3,
        ),
      ];
      HomeSectionType? owner(String id) => HomeViewModel.sectionConfigForRow(
        row(id, HomeRowType.latestMedia),
        configs,
      )?.type;

      expect(owner('kostvArrived'), HomeSectionType.kostvArrived);
      expect(owner('kostvRec_for_you_x'), HomeSectionType.kostvForYou);
      expect(owner('kostvRec_loading'), HomeSectionType.kostvForYou);
      expect(owner('kostvMore_genre_y'), HomeSectionType.kostvForYouMore);
      expect(owner(moreId), HomeSectionType.kostvForYouMore);
      expect(owner('latest_lib'), HomeSectionType.latestMedia);
    });

    test('rows from the cache keep their order, each once', () async {
      final prefs = await prefsWith({
        'kostv_home_available': true,
        'kostv_home_show_recent': true,
      });
      final vm = model(
        prefs,
        _DataSource(),
        _Cache([
          row('kostvArrived', HomeRowType.latestMedia),
          row('resume', HomeRowType.resume),
          row('kostvRec_for_you_x', HomeRowType.latestMedia),
          row('latest_lib', HomeRowType.latestMedia),
        ]),
      );
      await vm.load();
      await pumpEventQueue();

      final ids = vm.rows.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, ['resume', 'kostvRec_for_you_x', moreId, 'latest_lib']);
    });

    test(
      'recently added loading doesn\'t take the recommended rows away',
      () async {
        final prefs = await prefsWith({
          'kostv_home_available': true,
          'kostv_home_show_recent': true,
        });
        final views = _Views();
        when(() => views.getAllViewsIncludingHidden()).thenAnswer(
          (_) async => [
            const AggregatedLibrary(
              id: 'lib',
              name: 'Pelis',
              collectionType: 'movies',
              serverId: 's',
            ),
          ],
        );
        when(() => views.cachedUserConfiguration())
            .thenAnswer((_) => Future.error('x'));
        GetIt.instance.registerSingleton<UserViewsRepository>(views);
        final source = _DataSource();
        when(() => source.loadLatestMedia(any(), any(), any(), any()))
            .thenAnswer((_) async {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return row('latest_lib', HomeRowType.latestMedia);
            });
        final vm = model(
          prefs,
          source,
          _Cache([
            row('resume', HomeRowType.resume),
            row('kostvRec_for_you_x', HomeRowType.latestMedia),
            row('kostvRec_genre_y', HomeRowType.latestMedia),
            row('latest_lib', HomeRowType.latestMedia),
          ]),
        );
        await vm.load();
        await pumpEventQueue();

        expect(vm.rows.map((r) => r.id), [
          'resume',
          'kostvRec_for_you_x',
          'kostvRec_genre_y',
          moreId,
          'latest_lib',
        ]);
      },
    );
  });

  group('the row cache', () {
    test('the recommended Home, the Home of sections and Kids Mode each '
        'have their own', () async {
      Future<String> keyFor(Map<String, Object> saved) async {
        final prefs = await prefsWith(saved);
        final cache = _Cache();
        final vm = model(prefs, _DataSource(), cache);
        await vm.load();
        await pumpEventQueue();
        GetIt.instance.reset();
        return cache.readKeys.first;
      }

      final recommended = await keyFor({'kostv_home_available': true});
      final withRecent = await keyFor({
        'kostv_home_available': true,
        'kostv_home_show_recent': true,
      });
      final sections = await keyFor({});
      final kids = await keyFor({'pref_kids_mode': true});

      expect(
        {recommended, withRecent, sections, kids}.length,
        4,
        reason: 'each Home its own cache',
      );
    });

    test('a title turned down isn\'t saved with the rows', () async {
      final prefs = await prefsWith({'kostv_home_available': true});
      final cache = _Cache([
        row('resume', HomeRowType.resume),
        row('kostvRec_for_you_x', HomeRowType.latestMedia, items: ['a', 'b']),
      ]);
      final vm = model(prefs, _DataSource(), cache);
      await vm.load();
      await pumpEventQueue();
      final shown = vm.rows.firstWhere((r) => r.id == 'kostvRec_for_you_x');

      vm.kostvNotInterested(shown.items.first);
      await vm.refresh();
      await pumpEventQueue();

      final saved = cache.writes.last.firstWhere(
        (r) => r.id == 'kostvRec_for_you_x',
      );
      expect(saved.items.map((i) => i.id), ['b']);
      vm.retire();
    });

    test('the same rows aren\'t written again', () async {
      final prefs = await prefsWith({});
      await prefs.set(UserPreferences.mergeContinueWatchingNextUp, false);
      await prefs.setHomeSectionsConfig([
        for (final cfg in HomeSectionConfig.defaults())
          cfg.copyWith(enabled: false),
        collection(0),
      ]);
      await prefs.set(UserPreferences.displayCollectionsRows, true);
      final source = _DataSource();
      final first = row(collection(0).stableId, HomeRowType.pluginDynamic);
      when(
        () => source.loadDynamicSection(
          rowId: any(named: 'rowId'),
          section: any(named: 'section'),
          title: any(named: 'title'),
          serverId: any(named: 'serverId'),
          additionalData: any(named: 'additionalData'),
          pluginSource: any(named: 'pluginSource'),
          forceRefresh: any(named: 'forceRefresh'),
        ),
      ).thenAnswer((_) async => first);
      final cache = _Cache();
      final vm = model(prefs, source, cache);
      await vm.load();
      await pumpEventQueue();
      expect(cache.writes, hasLength(1));

      // Back from a title, with no row to carry on with: nothing changed.
      await vm.refreshResumeAndNextUp();
      await pumpEventQueue();

      expect(cache.writes, hasLength(1));
    });

    test('a Home whose person signed out saves nothing more', () async {
      final prefs = await prefsWith({});
      await prefs.setHomeSectionsConfig([
        for (final cfg in HomeSectionConfig.defaults())
          cfg.copyWith(enabled: false),
        collection(0),
      ]);
      await prefs.set(UserPreferences.displayCollectionsRows, true);
      final gate = Completer<void>();
      final source = _DataSource();
      when(
        () => source.loadDynamicSection(
          rowId: any(named: 'rowId'),
          section: any(named: 'section'),
          title: any(named: 'title'),
          serverId: any(named: 'serverId'),
          additionalData: any(named: 'additionalData'),
          pluginSource: any(named: 'pluginSource'),
          forceRefresh: any(named: 'forceRefresh'),
        ),
      ).thenAnswer((inv) async {
        await gate.future;
        return row(
          inv.namedArguments[#rowId] as String,
          HomeRowType.pluginDynamic,
        );
      });
      final cache = _Cache();
      final vm = model(prefs, source, cache);
      final loading = vm.load();
      await pumpEventQueue();

      vm.retire();
      gate.complete();
      await loading;
      await pumpEventQueue();

      expect(cache.writes, isEmpty);
    });
  });

  test('a collection further down that came back empty once is asked for '
      'again', () async {
    final prefs = await prefsWith({});
    await prefs.setHomeSectionsConfig([
      for (final cfg in HomeSectionConfig.defaults())
        cfg.copyWith(enabled: false),
      for (var n = 0; n < 10; n++) collection(n),
    ]);
    await prefs.set(UserPreferences.displayCollectionsRows, true);
    final source = _DataSource();
    var emptyNine = true;
    final loaded = <String>[];
    when(
      () => source.loadDynamicSection(
        rowId: any(named: 'rowId'),
        section: any(named: 'section'),
        title: any(named: 'title'),
        serverId: any(named: 'serverId'),
        additionalData: any(named: 'additionalData'),
        pluginSource: any(named: 'pluginSource'),
        forceRefresh: any(named: 'forceRefresh'),
      ),
    ).thenAnswer((inv) async {
      final id = inv.namedArguments[#rowId] as String;
      loaded.add(id);
      if (id == collection(9).stableId && emptyNine) {
        return HomeRow(id: id, title: id, rowType: HomeRowType.pluginDynamic);
      }
      return row(id, HomeRowType.pluginDynamic);
    });
    final vm = model(prefs, source, _Cache());
    await vm.load();
    vm.loadSectionsNear(vm.rows);
    await pumpEventQueue();
    expect(vm.rows.any((r) => r.id == collection(9).stableId), isFalse);

    emptyNine = false;
    await vm.refresh();
    loaded.clear();
    vm.loadSectionsNear(vm.rows);
    await pumpEventQueue();

    expect(loaded, contains(collection(9).stableId));
    expect(vm.rows.any((r) => r.id == collection(9).stableId), isTrue);
  });

  group('the rows made for the person failing', () {
    test(
      'with none on screen, Home is told, so it can offer to try again',
      () async {
        final prefs = await prefsWith({'kostv_home_available': true});
        final vm = model(prefs, _DataSource(), _Cache());
        // The server plugin can't be reached here, so its rows fail.
        await vm.load();
        await pumpEventQueue();
        expect(vm.kostvForYouFailures, 1);

        await vm.retryKostvForYou();
        await pumpEventQueue();
        expect(vm.kostvForYouFailures, 2);
        vm.retire();
      },
    );

    test('with theirs from before on screen, nothing to say', () async {
      final prefs = await prefsWith({'kostv_home_available': true});
      final vm = model(
        prefs,
        _DataSource(),
        _Cache([row('kostvRec_for_you_x', HomeRowType.latestMedia)]),
      );
      await vm.load();
      await pumpEventQueue();

      expect(vm.kostvForYouFailures, 0);
      expect(vm.rows.any((r) => r.id == 'kostvRec_for_you_x'), isTrue);
    });
  });

  test('back from a title, carrying on refreshes without waiting for a slow '
      'row', () async {
    final prefs = await prefsWith({});
    await prefs.set(UserPreferences.mergeContinueWatchingNextUp, false);
    await prefs.setHomeSectionsConfig([
      for (final cfg in HomeSectionConfig.defaults())
        cfg.copyWith(enabled: cfg.type == HomeSectionType.resume),
      collection(0),
    ]);
    await prefs.set(UserPreferences.displayCollectionsRows, true);
    final slow = Completer<void>();
    final source = _DataSource();
    var resumeLoads = 0;
    when(() => source.loadResume(any(), startIndex: any(named: 'startIndex')))
        .thenAnswer((_) async {
          resumeLoads++;
          return row('resume', HomeRowType.resume, items: ['r$resumeLoads']);
        });
    when(
      () => source.loadDynamicSection(
        rowId: any(named: 'rowId'),
        section: any(named: 'section'),
        title: any(named: 'title'),
        serverId: any(named: 'serverId'),
        additionalData: any(named: 'additionalData'),
        pluginSource: any(named: 'pluginSource'),
        forceRefresh: any(named: 'forceRefresh'),
      ),
    ).thenAnswer((inv) async {
      await slow.future;
      return row(
        inv.namedArguments[#rowId] as String,
        HomeRowType.pluginDynamic,
      );
    });
    final vm = model(prefs, source, _Cache());
    final loading = vm.load();
    await pumpEventQueue();
    expect(vm.isLoading, isTrue);

    await vm.refreshResumeAndNextUp().timeout(const Duration(seconds: 1));

    expect(resumeLoads, 2);
    expect(vm.rows.firstWhere((r) => r.id == 'resume').items.map((i) => i.id), [
      'r2',
    ]);
    slow.complete();
    await loading;
  });

  test('a title turned down that the server didn\'t hear of stays off the '
      'next Home', () async {
    final prefs = await prefsWith({'kostv_home_available': true});
    List<HomeRow> cached() => [
      row('kostvRec_for_you_x', HomeRowType.latestMedia, items: ['a', 'b']),
    ];
    final first = model(prefs, _DataSource(), _Cache(cached()));
    await first.load();
    await pumpEventQueue();
    first.kostvNotInterested(
      first.rows.firstWhere((r) => r.id == 'kostvRec_for_you_x').items.first,
    );
    // Another person signs in within the undo time: it isn't sent then.
    first.retire();
    GetIt.instance.reset();

    final next = model(prefs, _DataSource(), _Cache(cached()));
    await next.load();
    await pumpEventQueue();

    expect(
      next.rows
          .firstWhere((r) => r.id == 'kostvRec_for_you_x')
          .items
          .map((i) => i.id),
      ['b'],
    );
    next.retire();
  });

  test('a page that comes after its row was refreshed is dropped', () async {
    final prefs = await prefsWith({});
    await prefs.set(UserPreferences.mergeContinueWatchingNextUp, false);
    await prefs.setHomeSectionsConfig([
      for (final cfg in HomeSectionConfig.defaults())
        cfg.copyWith(enabled: cfg.type == HomeSectionType.resume),
    ]);
    final source = _DataSource();
    var resumeLoads = 0;
    when(() => source.loadResume(any(), startIndex: any(named: 'startIndex')))
        .thenAnswer((_) async {
          resumeLoads++;
          return HomeRow(
            id: 'resume',
            title: 'resume',
            rowType: HomeRowType.resume,
            items: [
              for (var i = 0; i < 15; i++)
                AggregatedItem(
                  id: 'r$resumeLoads-$i',
                  serverId: 's',
                  rawData: const {},
                ),
            ],
            totalCount: 40,
          );
        });
    final page = Completer<(List<AggregatedItem>, int)>();
    when(
      () => source.loadMore(
        row: any(named: 'row'),
        serverId: any(named: 'serverId'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) => page.future);
    final vm = model(prefs, source, _Cache());
    await vm.load();
    await pumpEventQueue();
    final old = vm.rows.firstWhere((r) => r.id == 'resume');

    final paging = vm.loadMoreForRow(vm.rows.indexOf(old));
    await vm.refreshResumeAndNextUp();
    page.complete((
      [
        ...old.items,
        for (var i = 0; i < 15; i++)
          AggregatedItem(id: 'p-$i', serverId: 's', rawData: const {}),
      ],
      40,
    ));
    await paging;

    final now = vm.rows.firstWhere((r) => r.id == 'resume');
    expect(now.items.first.id, 'r2-0');
    expect(now.items, hasLength(15));
  });
}
