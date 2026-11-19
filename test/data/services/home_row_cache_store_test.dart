import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/services/home_row_cache_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

HomeRow _row(String id, HomeRowType type) => HomeRow(
  id: id,
  title: id,
  rowType: type,
  items: [
    AggregatedItem(
      id: '$id-item',
      serverId: 'server',
      rawData: {'Name': id, 'Type': 'Program'},
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late HomeRowCacheStore store;

  setUp(() {
    support = Directory.systemTemp.createTempSync('moonfin_home_rows');
    PathProviderPlatform.instance = _FakePathProvider(support.path);
    store = HomeRowCacheStore();
  });

  tearDown(() {
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  test('does not persist the time-bound On Now row', () async {
    await store.write('key', [
      _row('liveTvOnNow', HomeRowType.liveTvOnNow),
      _row('resume', HomeRowType.resume),
    ]);

    final rows = await store.read('key');

    expect(rows?.map((r) => r.rowType), [HomeRowType.resume]);
  });

  // The home saves once its sections load and again when the resume row
  // refreshes behind them, and the bigger first save takes longer to encode.
  test('a newer save lands after an older one still encoding', () async {
    final older = store.write('key', [
      for (var i = 0; i < 400; i++) _row('latest$i', HomeRowType.latestMedia),
      _row('stale', HomeRowType.resume),
    ]);
    final newer = store.write('key', [_row('fresh', HomeRowType.resume)]);
    await Future.wait([older, newer]);

    final rows = await store.read('key');

    expect(rows?.map((r) => r.id), ['fresh']);
  });

  test('a home that loaded empty drops its saved rows', () async {
    await store.write('key', [_row('resume', HomeRowType.resume)]);

    await store.write('key', const []);

    expect(await store.read('key'), isNull);
  });

  test('an empty home leaves rows saved under another key alone', () async {
    await store.write('online', [_row('resume', HomeRowType.resume)]);

    await store.write('offline', const []);

    expect((await store.read('online'))?.map((r) => r.id), ['resume']);
  });

  // Kos TV: on a TV the family shares, each person starts with their rows.
  group('one slot per person', () {
    test('each person keeps their own rows', () async {
      final mum = HomeRowCacheStore(owner: 'server|mum');
      final kid = HomeRowCacheStore(owner: 'server|kid');
      await mum.write('mum-key', [_row('mum', HomeRowType.resume)]);
      await kid.write('kid-key', [_row('kid', HomeRowType.resume)]);

      expect((await mum.read('mum-key'))?.map((r) => r.id), ['mum']);
      expect((await kid.read('kid-key'))?.map((r) => r.id), ['kid']);
      expect(await kid.read('mum-key'), isNull);
    });

    test('only the last few people are kept', () async {
      for (var i = 0; i < 6; i++) {
        await HomeRowCacheStore(owner: 'server|$i')
            .write('key$i', [_row('row$i', HomeRowType.resume)]);
        // Told apart by when they were written.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final files = support.listSync().whereType<File>().where(
        (f) => f.path.contains('home_rows_cache_'),
      );

      expect(files, hasLength(4));
      expect(
        await HomeRowCacheStore(owner: 'server|5').read('key5'),
        isNotNull,
      );
      expect(await HomeRowCacheStore(owner: 'server|0').read('key0'), isNull);
    });

    test('the rows a build with a single slot saved are still read, and '
        'go with the next write', () async {
      final legacy = File('${support.path}/home_rows_cache.json');
      await HomeRowCacheStore(owner: 'old')
          .write('old-key', [_row('old', HomeRowType.resume)]);
      support.listSync().whereType<File>().single.renameSync(legacy.path);
      final store = HomeRowCacheStore(owner: 'server|mum');

      expect((await store.read('old-key'))?.map((r) => r.id), ['old']);
      await store.write('mum-key', [_row('mum', HomeRowType.resume)]);
      expect(legacy.existsSync(), isFalse);
    });
  });

  test('keeps whether a row is of music and its subtitle', () async {
    await store.write('key', [
      HomeRow(
        id: 'albums',
        title: 'Albums',
        subtitle: 'Lately',
        rowType: HomeRowType.audioAlbums,
        isAudio: true,
        items: [AggregatedItem(id: 'a', serverId: 's', rawData: const {})],
      ),
      _row('resume', HomeRowType.resume),
    ]);

    final rows = await store.read('key');

    expect(rows?.first.isAudio, isTrue);
    expect(rows?.first.subtitle, 'Lately');
    expect(rows?.last.isAudio, isFalse);
    expect(rows?.last.subtitle, isNull);
  });
}
