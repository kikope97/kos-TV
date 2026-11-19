import 'dart:convert';

import 'package:drift/drift.dart';

part 'offline_database.g.dart';

extension DownloadedItemMetadata on DownloadedItem {
  Map<String, dynamic> get parsedMetadata {
    try {
      final raw = jsonDecode(metadataJson);
      if (raw is Map<String, dynamic>) return raw;
    } catch (_) {}
    return const {};
  }
}

class DownloadedItems extends Table {
  TextColumn get itemId => text()();
  TextColumn get serverId => text()();
  TextColumn get type => text()();
  TextColumn get name => text()();
  TextColumn get localFilePath => text().nullable()();
  TextColumn get metadataJson => text()();
  TextColumn get posterPath => text().nullable()();
  TextColumn get backdropPath => text().nullable()();
  TextColumn get logoPath => text().nullable()();
  TextColumn get thumbPath => text().nullable()();
  IntColumn get downloadStatus => integer()();
  RealColumn get downloadProgress => real().withDefault(const Constant(0.0))();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get playbackPositionTicks => integer().withDefault(const Constant(0))();
  BoolColumn get progressSynced => boolean().withDefault(const Constant(true))();
  DateTimeColumn get downloadedAt => dateTime().nullable()();
  TextColumn get qualityPreset => text().withDefault(const Constant('original'))();
  TextColumn get seriesId => text().nullable()();
  TextColumn get seasonId => text().nullable()();
  TextColumn get seriesName => text().nullable()();
  TextColumn get seasonName => text().nullable()();
  IntColumn get indexNumber => integer().nullable()();
  IntColumn get parentIndexNumber => integer().nullable()();

  /// Who queued the download: `manual` for the user, `auto` for an
  /// auto-download subscription. Only auto rows are ever removed by the
  /// subscription's delete-after-watched rule.
  TextColumn get downloadSource =>
      text().withDefault(const Constant('manual'))();

  /// Kos TV: whose watching left [playbackPositionTicks] unsynced, so the
  /// sync only sends it as that person. Null on rows from before it was
  /// kept, which sync with whoever is signed in, as they always did.
  TextColumn get progressUserId => text().nullable()();

  @override
  Set<Column> get primaryKey => {itemId, serverId};
}

/// Kos TV: one person's tie to one download: whether they downloaded it, and
/// where they are in it. Files are shared by everyone on the device, so who
/// downloaded something and how far each person watched it live here rather
/// than on the download's own row. [userId] is stored the way
/// `normalizeDownloadUserId` writes it (lower case, without dashes).
class DownloadedItemUsers extends Table {
  TextColumn get itemId => text()();
  TextColumn get serverId => text()();
  TextColumn get userId => text()();

  /// Whether this person downloaded it (by hand or through one of their
  /// auto-downloads). A download nobody owns predates owners and is
  /// everyone's.
  BoolColumn get isOwner => boolean().withDefault(const Constant(false))();

  /// Whether [positionTicks] and [played] hold this person's progress. A row
  /// kept only for ownership leaves the download's own progress in place.
  BoolColumn get hasProgress => boolean().withDefault(const Constant(false))();
  IntColumn get positionTicks => integer().withDefault(const Constant(0))();
  BoolColumn get played => boolean().withDefault(const Constant(false))();

  /// Whether the server already has [positionTicks]. Unsynced progress is
  /// only sent while this person is signed in.
  BoolColumn get progressSynced =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {itemId, serverId, userId};
}

/// A series the user asked to keep downloading new episodes for. One row per
/// series per server account; the keep/delete rules are global preferences.
class AutoDownloadSubscriptions extends Table {
  TextColumn get seriesId => text()();
  TextColumn get serverId => text()();
  TextColumn get userId => text()();
  TextColumn get seriesName => text()();
  TextColumn get qualityPreset => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastCheckedAt => dateTime().nullable()();
  IntColumn get lastQueuedCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {seriesId, serverId, userId};
}

@DriftDatabase(
  tables: [DownloadedItems, AutoDownloadSubscriptions, DownloadedItemUsers],
)
class OfflineDatabase extends _$OfflineDatabase {
  OfflineDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await _tolerateExisting(
          () => m.addColumn(downloadedItems, downloadedItems.downloadSource),
        );
        await _tolerateExisting(() => m.createTable(autoDownloadSubscriptions));
      }
      if (from < 3) {
        await _tolerateExisting(
          () => m.addColumn(downloadedItems, downloadedItems.progressUserId),
        );
      }
      if (from < 4) {
        await _tolerateExisting(() => m.createTable(downloadedItemUsers));
        // Kos TV: progress still waiting for the server that knows whose it
        // is becomes that person's own, so the next person to watch the
        // download no longer writes over it. Progress that knows nobody stays
        // on the download and syncs with whoever is signed in, as before.
        await customStatement('''
          INSERT OR IGNORE INTO downloaded_item_users
            (item_id, server_id, user_id, is_owner, has_progress,
             position_ticks, played, progress_synced)
          SELECT item_id, server_id,
                 lower(replace(progress_user_id, '-', '')),
                 0, 1, playback_position_ticks, 0, 0
          FROM downloaded_items
          WHERE progress_synced = 0
            AND progress_user_id IS NOT NULL AND progress_user_id != ''
        ''');
        await customStatement('''
          UPDATE downloaded_items SET progress_synced = 1
          WHERE progress_synced = 0
            AND progress_user_id IS NOT NULL AND progress_user_id != ''
        ''');
      }
    },
  );

  /// Runs one migration step, letting through only the failure that says the
  /// column or table is already there. A database from before the schema was
  /// versioned can already carry both, and adding them again throws.
  ///
  /// Anything else has to surface. Drift marks the upgrade done either way, so
  /// swallowing a locked file or a full disk would leave the schema half built
  /// and turn a startup failure into a query that fails much later with
  /// nothing to point at. The match is on the message because the database
  /// runs on a background isolate, which wraps whatever sqlite threw.
  static Future<void> _tolerateExisting(Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (!message.contains('duplicate column name') &&
          !message.contains('already exists')) {
        rethrow;
      }
    }
  }
}
