import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/data/models/media_bar_state.dart';
import 'package:moonfin/data/repositories/mdblist_repository.dart';
import 'package:moonfin/data/repositories/media_bar_repository.dart';
import 'package:moonfin/data/services/plugin_sync_service.dart';
import 'package:moonfin/data/viewmodels/media_bar_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repository extends Mock implements MediaBarRepository {}

class _MdbList extends Mock implements MdbListRepository {}

class _Client extends Mock implements MediaServerClient {}

class _Items extends Mock implements ItemsApi {}

class _Sync extends ChangeNotifier implements PluginSyncService {
  bool available = false;

  @override
  bool get pluginAvailable => available;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late UserPreferences prefs;
  late _Repository repository;
  late _Sync sync;
  late List<Completer<MediaBarState>> loads;

  setUpAll(() => registerFallbackValue(<MediaBarSlideItem>[]));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    sync = _Sync();
    GetIt.instance.registerSingleton<PluginSyncService>(sync);
    loads = [];
    repository = _Repository();
    when(() => repository.loadItems()).thenAnswer((_) {
      final load = Completer<MediaBarState>();
      loads.add(load);
      return load.future;
    });
    when(
      () => repository.loadNewReleases(any()),
    ).thenAnswer((_) async => const {});
  });

  tearDown(() => GetIt.instance.reset());

  MediaBarViewModel create({MediaServerClient? client}) =>
      MediaBarViewModel(repository, _MdbList(), prefs, client ?? _Client());

  test('a source change made during a load runs once that load ends', () async {
    final viewModel = create();
    unawaited(viewModel.load());
    await prefs.set(UserPreferences.mediaBarLibraryIds, 'lib');
    expect(loads, hasLength(1));

    loads.first.complete(const MediaBarDisabled());
    await pumpEventQueue();

    expect(loads, hasLength(2));
  });

  test('the bar shows before its new release labels, which follow', () async {
    const series = MediaBarSlideItem(
      itemId: 'series',
      serverId: 'server',
      title: 'Show',
      itemType: 'Series',
    );
    const movie = MediaBarSlideItem(
      itemId: 'movie',
      serverId: 'server',
      title: 'Film',
    );
    final labels = Completer<Map<String, MediaBarNewReleaseInfo>>();
    when(
      () => repository.loadNewReleases(any()),
    ).thenAnswer((_) => labels.future);
    final viewModel = create();
    unawaited(viewModel.load());
    loads.first.complete(const MediaBarReady([series, movie]));
    await pumpEventQueue();

    expect(viewModel.state, isA<MediaBarReady>());
    expect(viewModel.items.map((item) => item.newRelease), [null, null]);

    labels.complete({
      'series': const MediaBarNewReleaseInfo(
        kind: MediaBarNewRelease.newSeason,
        season: 2,
      ),
    });
    await pumpEventQueue();

    expect(viewModel.items.first.newRelease?.kind, MediaBarNewRelease.newSeason);
    expect(viewModel.items.last.newRelease, isNull);
    viewModel.dispose();
  });

  test('a title turned down goes off the banner at once, and comes back '
      'if taken back', () async {
    const a = MediaBarSlideItem(itemId: 'a', serverId: 'server', title: 'A');
    const b = MediaBarSlideItem(itemId: 'b', serverId: 'server', title: 'B');
    final viewModel = create();
    unawaited(viewModel.load());
    loads.first.complete(const MediaBarReady([a, b]));
    await pumpEventQueue();
    expect(viewModel.items.map((i) => i.itemId), ['a', 'b']);

    viewModel.kostvHide('a');
    expect(viewModel.items.map((i) => i.itemId), ['b']);

    // A load meanwhile still leaves it off.
    unawaited(viewModel.load(force: true));
    loads.last.complete(const MediaBarReady([a, b]));
    await pumpEventQueue();
    expect(viewModel.items.map((i) => i.itemId), ['b']);

    viewModel.kostvUnhide('a');
    expect(viewModel.items.map((i) => i.itemId), ['a', 'b']);
    viewModel.dispose();
  });

  test('picked lists load again once Moonbase answers', () async {
    await prefs.set(UserPreferences.mediaBarExternalLists, 'imdb_top_250_movies');
    final viewModel = create();
    unawaited(viewModel.load());
    loads.first.complete(const MediaBarDisabled());
    await pumpEventQueue();

    sync
      ..available = true
      ..notifyListeners();
    await pumpEventQueue();

    expect(loads, hasLength(2));
    viewModel.dispose();
  });

  // Kos TV: taking a title off the banner (or back) rebuilds it from the
  // loaded list, which didn't carry the labels.
  test('the new release labels stay when a title is turned down', () async {
    const series = MediaBarSlideItem(
      itemId: 'series',
      serverId: 'server',
      title: 'Show',
      itemType: 'Series',
    );
    const movie = MediaBarSlideItem(
      itemId: 'movie',
      serverId: 'server',
      title: 'Film',
    );
    when(() => repository.loadNewReleases(any())).thenAnswer(
      (_) async => {
        'series': const MediaBarNewReleaseInfo(
          kind: MediaBarNewRelease.newEpisodes,
          season: 1,
          episode: 4,
        ),
      },
    );
    final viewModel = create();
    unawaited(viewModel.load());
    loads.first.complete(const MediaBarReady([series, movie]));
    await pumpEventQueue();
    expect(viewModel.items.first.newRelease, isNotNull);

    viewModel.kostvHide('movie');
    expect(viewModel.items.single.newRelease?.kind, MediaBarNewRelease.newEpisodes);

    viewModel.kostvUnhide('movie');
    expect(viewModel.items.first.newRelease, isNotNull);
    expect(viewModel.items.last.newRelease, isNull);
    viewModel.dispose();
  });

  test('labels that come after a title was turned down still go on', () async {
    const series = MediaBarSlideItem(
      itemId: 'series',
      serverId: 'server',
      title: 'Show',
      itemType: 'Series',
    );
    const movie = MediaBarSlideItem(
      itemId: 'movie',
      serverId: 'server',
      title: 'Film',
    );
    final labels = Completer<Map<String, MediaBarNewReleaseInfo>>();
    when(
      () => repository.loadNewReleases(any()),
    ).thenAnswer((_) => labels.future);
    final viewModel = create();
    unawaited(viewModel.load());
    loads.first.complete(const MediaBarReady([series, movie]));
    await pumpEventQueue();

    viewModel.kostvHide('movie');
    labels.complete({
      'series': const MediaBarNewReleaseInfo(
        kind: MediaBarNewRelease.newSeason,
        season: 2,
      ),
    });
    await pumpEventQueue();

    expect(viewModel.items.map((item) => item.itemId), ['series']);
    expect(viewModel.items.single.newRelease?.kind, MediaBarNewRelease.newSeason);
    viewModel.dispose();
  });

  group('the gallery card', () {
    late _Client client;
    late _Items itemsApi;

    setUp(() {
      client = _Client();
      itemsApi = _Items();
      when(() => client.itemsApi).thenReturn(itemsApi);
    });

    test('of an outside title is empty at once, with nothing asked', () async {
      const outside = MediaBarSlideItem(
        itemId: '603',
        serverId: MediaBarSlideItem.externalServerId,
        title: 'Outside',
      );
      final viewModel = create(client: client);
      unawaited(viewModel.load());
      loads.first.complete(const MediaBarReady([outside]));
      await pumpEventQueue();

      await viewModel.ensureGalleryDetail('603');
      expect(viewModel.galleryDetailFor('603')?.isEmpty, isTrue);
      verifyNever(() => itemsApi.getItem(any()));
      viewModel.dispose();
    });

    test('whose page can\'t be read is empty, and not asked again on every '
        'redraw', () async {
      const film = MediaBarSlideItem(
        itemId: 'film',
        serverId: 'server',
        title: 'Film',
      );
      when(() => itemsApi.getItem(any())).thenThrow(Exception('offline'));
      final viewModel = create(client: client);
      unawaited(viewModel.load());
      loads.first.complete(const MediaBarReady([film]));
      await pumpEventQueue();

      await viewModel.ensureGalleryDetail('film');
      await viewModel.ensureGalleryDetail('film');
      expect(viewModel.galleryDetailFor('film')?.isEmpty, isTrue);
      verify(() => itemsApi.getItem('film')).called(1);
      viewModel.dispose();
    });
  });
}
