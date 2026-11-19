import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/database/offline_database.dart';
import 'package:moonfin/data/offline/download_people.dart';
import 'package:moonfin/data/offline/offline_catalog.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';

const _min = 60 * 10000000;
const _runtime = 100 * _min;

/// Kos TV: downloads are shared files, but who downloaded each one and how
/// far each person got in it are kept per person.
void main() {
  late OfflineDatabase db;
  late OfflineRepository repo;

  setUp(() {
    db = OfflineDatabase(NativeDatabase.memory());
    repo = OfflineRepository(db);
  });

  tearDown(() => db.close());

  Future<void> download(String id, {int ticks = 0, bool played = false}) =>
      repo.upsertItem(
        DownloadedItemsCompanion(
          itemId: Value(id),
          serverId: const Value('s1'),
          type: const Value('Movie'),
          name: Value(id),
          metadataJson: Value(
            jsonEncode({
              'Id': id,
              'RunTimeTicks': _runtime,
              'UserData': {'PlaybackPositionTicks': ticks, 'Played': played},
            }),
          ),
          downloadStatus: const Value(2),
          fileSizeBytes: const Value(1000),
          playbackPositionTicks: Value(ticks),
        ),
      );

  Future<DownloadedItem> row(String id) async => (await repo.getItem(id))!;

  test('user ids match with or without dashes and in any case', () {
    expect(normalizeDownloadUserId('AB-cd-12'), 'abcd12');
    expect(normalizeDownloadUserId(null), '');
  });

  test('whose a download is, for each person', () async {
    await download('mine');
    await download('theirs');
    await download('old');
    await repo.addOwner('mine', 'Person-A');
    await repo.addOwner('theirs', 'person-b');

    final people = await repo.getPeople();
    expect(
      people.ownershipOf(await row('mine'), 'PERSONA'),
      DownloadOwnership.mine,
    );
    expect(
      people.ownershipOf(await row('theirs'), 'person-a'),
      DownloadOwnership.others,
    );
    expect(
      people.ownershipOf(await row('old'), 'person-a'),
      DownloadOwnership.everyone,
    );
    expect(people.hasOtherOwners(await row('theirs'), 'person-a'), isTrue);
    expect(people.hasOtherOwners(await row('mine'), 'person-a'), isFalse);
  });

  test('a download two people asked for is both people\'s', () async {
    await download('m');
    await repo.addOwner('m', 'person-a');
    await repo.addOwner('m', 'person-b');

    final people = await repo.getPeople();
    final m = await row('m');
    expect(people.ownershipOf(m, 'person-a'), DownloadOwnership.mine);
    expect(people.ownershipOf(m, 'person-b'), DownloadOwnership.mine);
    expect(people.hasOtherOwners(m, 'person-a'), isTrue);
  });

  test('the list splits into one\'s own and other people\'s', () async {
    await download('mine');
    await download('theirs');
    await download('old');
    await repo.addOwner('mine', 'person-a');
    await repo.addOwner('theirs', 'person-b');
    final items = await repo.getItems();
    final people = await repo.getPeople();

    final split = splitDownloadsFor(items, people, 'person-a');
    expect(split.mine.map((i) => i.itemId), unorderedEquals(['mine', 'old']));
    expect(split.others.map((i) => i.itemId), ['theirs']);

    final kids = splitDownloadsFor(
      items,
      people,
      'person-a',
      kidsMode: true,
      isBlocked: (item) => item.itemId == 'old',
    );
    expect(kids.mine.map((i) => i.itemId), ['mine']);
    expect(kids.others, isEmpty);
  });

  test('each person sees their own place in a shared download', () async {
    await download('m', ticks: 10 * _min);
    await repo.addOwner('m', 'person-a');
    await repo.updatePlaybackPosition('m', 30 * _min, userId: 'person-a');
    await repo.updatePlaybackPosition('m', 60 * _min, userId: 'person-b');
    final people = await repo.getPeople();
    final m = await row('m');

    expect(people.rowFor(m, 'person-a').playbackPositionTicks, 30 * _min);
    expect(people.rowFor(m, 'person-b').playbackPositionTicks, 60 * _min);
    // Someone who never watched the other's download starts at the top.
    expect(people.rowFor(m, 'person-c').playbackPositionTicks, 0);
  });

  test('an old download keeps showing its own place to everyone', () async {
    await download('m', ticks: 10 * _min);
    final people = await repo.getPeople();
    expect(
      people.rowFor(await row('m'), 'person-a').playbackPositionTicks,
      10 * _min,
    );
  });

  test(
    'the offline catalogue carries the signed-in person\'s progress',
    () async {
      await download('m', ticks: 10 * _min);
      await repo.addOwner('m', 'person-a');
      await repo.setUserSyncedProgress(
        'm',
        serverId: 's1',
        userId: 'person-a',
        positionTicks: 0,
        played: true,
      );
      var user = 'person-a';
      var kids = false;
      final catalog = OfflineCatalog(
        repo,
        userId: () => user,
        kidsMode: () => kids,
      );
      await catalog.warm();

      expect(catalog.byId('m')!.isPlayed, isTrue);

      // Switching person needs no new read.
      user = 'person-b';
      expect(catalog.byId('m')!.isPlayed, isFalse);
      expect(catalog.byId('m')!.userData!['PlaybackPositionTicks'], 0);

      // In Kids Mode someone else's download is left out.
      kids = true;
      expect(catalog.byId('m'), isNull);
      expect(catalog.entries, isEmpty);
      catalog.dispose();
    },
  );

  test(
    'synced progress from the server does not overwrite waiting progress',
    () async {
      await download('m');
      await repo.updatePlaybackPosition('m', 40 * _min, userId: 'person-a');
      await repo.setUserSyncedProgress(
        'm',
        serverId: 's1',
        userId: 'person-a',
        positionTicks: 5 * _min,
        played: false,
      );

      final waiting = await repo.getUnsyncedUserProgress('person-a');
      expect(waiting.single.positionTicks, 40 * _min);
    },
  );
}
