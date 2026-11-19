import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/database/offline_database.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';

/// Kos TV: schema 3 keeps who watched a download, and a database from
/// schema 2 keeps its rows, which belong to nobody in particular.
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

    await repo.updatePlaybackPosition('m', 1200, userId: 'person-a');
    final unsynced = await repo.getUnsyncedProgress();
    expect(unsynced.single.progressUserId, 'person-a');
    expect(unsynced.single.playbackPositionTicks, 1200);
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
