import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/multi_server_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/services/row_data_source.dart';
import 'package:moonfin/data/viewmodels/media_bar_view_model.dart';
import 'package:moonfin/preference/home_section_config.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/navigation/home_refresh_bus.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDataSource extends Mock implements RowDataSource {}

class _MockClient extends Mock implements MediaServerClient {}

class _MockMediaBar extends Mock implements MediaBarViewModel {}

class _MockMultiServer extends Mock implements MultiServerRepository {}

class _MockSync extends Mock implements PluginSyncService {}

/// Kos TV: Home loads behind the intro video, and Home, as it comes up,
/// shows that load instead of starting it all again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeViewModel.preload', () {
    late _MockMediaBar mediaBar;
    late HomeViewModel model;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      final prefs = UserPreferences(store);
      await prefs.setHomeSectionsConfig([
        for (final config in HomeSectionConfig.defaults())
          config.copyWith(enabled: false),
      ]);
      await prefs.set(
        UserPreferences.lastExternalRowsRefreshTime,
        DateTime.now().millisecondsSinceEpoch,
      );

      final sync = _MockSync();
      when(() => sync.pluginAvailable).thenReturn(false);
      GetIt.instance.registerSingleton<PluginSyncService>(sync);

      final client = _MockClient();
      when(() => client.userId).thenReturn('user');
      when(() => client.baseUrl).thenReturn('http://server.test');
      mediaBar = _MockMediaBar();
      when(() => mediaBar.load(force: any(named: 'force')))
          .thenAnswer((_) async {});
      model = HomeViewModel(
        dataSource: _MockDataSource(),
        prefs: prefs,
        client: client,
        mediaBarViewModel: mediaBar,
        multiServerRepo: _MockMultiServer(),
      );
    });

    tearDown(() async {
      model.dispose();
      debugDefaultTargetPlatformOverride = null;
      await GetIt.instance.reset();
    });

    test('while the intro load is under way, Home takes it', () async {
      final preloading = model.preload();
      expect(model.isLoading, isTrue);
      expect(model.takePreload(), isTrue);
      // Only once: a later Home loads as usual.
      expect(model.takePreload(), isFalse);
      await preloading;
    });

    test('once the intro load is done, Home shows it', () async {
      await model.preload();
      expect(model.rows, isNotEmpty);
      expect(model.takePreload(), isTrue);
    });

    test('with no intro load, Home loads on its own', () {
      expect(model.takePreload(), isFalse);
    });

    test(
      'once Home has started loading, the intro does not load again',
      () async {
        final loading = model.load();
        await model.preload();
        await loading;
        expect(model.takePreload(), isFalse);
        final withPreload = verify(
          () => mediaBar.load(force: any(named: 'force')),
        ).callCount;

        // A load on its own asks the media bar as often: nothing more ran.
        await model.load();
        final alone = verify(() => mediaBar.load(force: any(named: 'force')))
            .callCount;
        expect(withPreload, alone);
      },
    );
  });
}
