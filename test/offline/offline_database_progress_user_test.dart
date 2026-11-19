import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/database/offline_database.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';

/// Kos TV: schema 3 keeps who watched a download, and a database from
/// schema 2 keeps its rows, which belong to nobody in particular. Schema 4
/// keeps each person's progress and who downloaded what apart.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('kostv_offline_db');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  DownloadedItemsCompanion row(String id) => DownloadedItemsCompanion(
    itemId: Value(id),
    serverId: const Value('server-a'),
    type: const Value('Movie'),
    name: Value(id),
    metadataJson: const Value('{}'),
    downloadStatus: const Value(2),
  );

  test('a schema 2 database keeps its rows and gains the column', () async {
    final file = File('${dir.path}/offline.sqlite');

    // Built at the current schema, then taken back to what schema 2 had.
    final old = OfflineDatabase(NativeDatabase(file));
    await OfflineRepository(old).upsertItem(row('m'));
    await old.customStatement(
      'ALTER TABLE downloaded_items DROP COLUMN progress_user_id',
    );
    await old.customStatement('PRAGMA user_version = 2');
    await old.close();

    final db = OfflineDatabase(NativeDatabase(file));
    final repo = OfflineRepository(db);
    final kept = await repo.getItem('m');
    expect(kept, isNotNull);
    expect(kept!.progressUserId, isNull);

    // Kos TV: since schema 4 a person's progress is kept as their own.
    await repo.updatePlaybackPosition('m', 1200, userId: 'person-a');
    expect(await repo.getUnsyncedProgress(), isEmpty);
    final unsynced = await repo.getUnsyncedUserProgress('person-a');
    expect(unsynced.single.positionTicks, 1200);
    await db.close();
  });

  test(
    'a schema 3 database hands each person their waiting progress',
    () async {
      final file = File('${dir.path}/offline.sqlite');

      // Built at the current schema, then taken back to what schema 3 had,
      // with one row someone watched and one nobody is known to have.
      final old = OfflineDatabase(NativeDatabase(file));
      final oldRepo = OfflineRepository(old);
      await oldRepo.upsertItem(row('a'));
      await oldRepo.upsertItem(row('n'));
      await old.customStatement(
        "UPDATE downloaded_items SET playback_position_ticks = 1200, "
        "progress_synced = 0, progress_user_id = 'AB-CD' WHERE item_id = 'a'",
      );
      await old.customStatement(
        'UPDATE downloaded_items SET playback_position_ticks = 2400, '
        "progress_synced = 0 WHERE item_id = 'n'",
      );
      await old.customStatement('DROP TABLE downloaded_item_users');
      await old.customStatement('PRAGMA user_version = 3');
      await old.close();

      final db = OfflineDatabase(NativeDatabase(file));
      final repo = OfflineRepository(db);

      final own = await repo.getUnsyncedUserProgress('abcd');
      expect(own.single.itemId, 'a');
      expect(own.single.positionTicks, 1200);
      // What nobody is known to have watched stays on the download.
      final legacy = await repo.getUnsyncedProgress();
      expect(legacy.single.itemId, 'n');
      expect(legacy.single.playbackPositionTicks, 2400);
      // Old downloads belong to nobody, so everyone keeps seeing them.
      final people = await repo.getPeople();
      expect(people.hasOtherOwners((await repo.getItem('a'))!, 'x'), isFalse);
      await db.close();
    },
  );

  test('deleting a download forgets who had it', () async {
    final db = OfflineDatabase(NativeDatabase.memory());
    final repo = OfflineRepository(db);
    await repo.upsertItem(row('m'));
    await repo.addOwner('m', 'person-a');
    await repo.updatePlaybackPosition('m', 1200, userId: 'person-b');

    await repo.deleteItem('m');
    await repo.upsertItem(row('m'));

    final people = await repo.getPeople();
    final again = (await repo.getItem('m'))!;
    expect(people.personOf(again, 'person-a'), isNull);
    expect(people.personOf(again, 'person-b'), isNull);
    await db.close();
  });

  test('progress recorded without a person stays anyone\'s', () async {
    final db = OfflineDatabase(NativeDatabase.memory());
    final repo = OfflineRepository(db);
    await repo.upsertItem(row('m'));

    await repo.updatePlaybackPosition('m', 1200, userId: 'person-a');
    await repo.updatePlaybackPosition('m', 2400);

    expect((await repo.getItem('m'))!.progressUserId, isNull);
    await db.close();
  });
}
