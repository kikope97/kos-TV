import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../../util/server_url.dart';
import '../database/offline_database.dart';
import '../offline/offline_media_segments.dart';
import '../repositories/offline_repository.dart';
import 'pending_rating_store.dart';

enum SyncState { idle, syncing, done, error }

class SyncResult {
  final int synced;
  final int failed;
  const SyncResult({required this.synced, required this.failed});
}

class SyncService extends ChangeNotifier {
  final OfflineRepository _offlineRepo;
  final PendingRatingStore _pendingRatings;

  SyncState _state = SyncState.idle;
  SyncState get state => _state;

  Timer? _doneResetTimer;

  SyncService(this._offlineRepo, this._pendingRatings);

  /// Pushes ratings queued while offline through [client]. Item ids are only
  /// unique within one server, so [serverId] scopes the replay to the server
  /// the client talks to and everything else waits for its own reconnect.
  ///
  /// Runs before the metadata refresh on reconnect, so the refreshed items
  /// come back carrying the rating that was just pushed.
  Future<SyncResult> syncPendingRatings(
    MediaServerClient client, {
    required String? serverId,
  }) async {
    if (serverId == null) return const SyncResult(synced: 0, failed: 0);

    var synced = 0, failed = 0;
    for (final entry in _pendingRatings.all) {
      if (entry.serverId != serverId) continue;
      // Kos TV: someone else's waits until they are signed in again, so it
      // isn't set on this person's account.
      if (!entry.isOf(client.userId)) continue;
      try {
        if (entry.clear) {
          await client.userLibraryApi.deleteUserRating(entry.itemId);
        } else if (entry.rating != null) {
          await client.userLibraryApi.updateNumericUserRating(
            entry.itemId,
            rating: entry.rating!,
          );
        } else if (entry.likes != null) {
          await client.userLibraryApi.updateUserRating(
            entry.itemId,
            likes: entry.likes!,
          );
        }
        await _pendingRatings.remove(
          entry.serverId,
          entry.itemId,
          userId: entry.userId,
        );
        synced++;
      } catch (e) {
        debugPrint('[Sync] Failed to push rating for ${entry.itemId}: $e');
        failed++;
      }
    }
    return SyncResult(synced: synced, failed: failed);
  }

  /// Whether [row] was downloaded from the server [client] talks to, whose
  /// app server id is [serverId]. Most writers store that id, a few store the
  /// server's base URL instead, so a URL-shaped id is matched the way
  /// MediaServerClientFactory.getClientIfExists resolves one.
  static bool _isFromServer(
    DownloadedItem row,
    MediaServerClient client,
    String serverId,
  ) =>
      isStoredServer(row.serverId, serverId: serverId, baseUrl: client.baseUrl);

  /// Kos TV: whether progress kept for [progressUserId] may be sent as
  /// [signedInUserId]. A row from before the person was kept belongs to
  /// anyone, as it always did.
  @visibleForTesting
  static bool isProgressOf(String? progressUserId, String? signedInUserId) {
    if (progressUserId == null || progressUserId.isEmpty) return true;
    String normalize(String? id) =>
        (id ?? '').replaceAll('-', '').toLowerCase();
    return normalize(progressUserId) == normalize(signedInUserId);
  }

  /// Pushes progress recorded offline through [client], furthest progress
  /// winning. Only rows from [serverId] are touched: a server answers a stop
  /// report for an item it does not have with success, so another server's
  /// row would be marked synced without its own server ever hearing of it.
  Future<SyncResult> syncPlaybackProgress(
    MediaServerClient client, {
    required String? serverId,
  }) async {
    if (serverId == null) return const SyncResult(synced: 0, failed: 0);
    if (_state == SyncState.syncing) {
      return const SyncResult(synced: 0, failed: 0);
    }

    _setState(SyncState.syncing);

    // Kos TV: a row someone else watched waits until they are signed in
    // again, so it never lands in this person's watch data.
    final unsynced = <_PendingProgress>[
      for (final row in await _offlineRepo.getUnsyncedProgress())
        if (_isFromServer(row, client, serverId) &&
            (row.progressUserId == null ||
                isProgressOf(row.progressUserId, client.userId)))
          _PendingProgress(row, row.playbackPositionTicks, null),
    ];
    // Kos TV: and the signed-in person's own progress on downloads.
    final userId = client.userId;
    if (userId != null && userId.isNotEmpty) {
      final own = await _offlineRepo.getUnsyncedUserProgress(userId);
      if (own.isNotEmpty) {
        final rows = {
          for (final row in await _offlineRepo.getItems())
            '${row.serverId}\u0000${row.itemId}': row,
        };
        for (final progress in own) {
          final row = rows['${progress.serverId}\u0000${progress.itemId}'];
          if (row == null || !_isFromServer(row, client, serverId)) continue;
          unsynced.add(_PendingProgress(row, progress.positionTicks, userId));
        }
      }
    }
    if (unsynced.isEmpty) {
      _setState(SyncState.done);
      _scheduleDoneReset();
      return const SyncResult(synced: 0, failed: 0);
    }

    int synced = 0, failed = 0;

    // A server that takes offline progress in one request (Silo) gets the
    // pushes together after the loop, instead of one call per item.
    final userLibrary = client.userLibraryApi;
    final bulk = userLibrary is OfflineProgressSyncApi
        ? userLibrary as OfflineProgressSyncApi
        : null;
    final bulkPushes = <(_PendingProgress, OfflineProgressEntry)>[];

    // Batch-fetch server progress for every unsynced item in one request
    // instead of a round-trip per item on reconnect.
    final serverUserData = await _fetchServerUserData(client, [
      for (final pending in unsynced) pending.row.itemId,
    ]);

    for (final pending in unsynced) {
      final item = pending.row;
      try {
        final userData = serverUserData[item.itemId];
        if (userData != null) {
          final serverPlayed = userData['Played'] as bool? ?? false;
          final serverTicks = userData['PlaybackPositionTicks'] as int? ?? 0;
          final localPlayed = pending.ticks == 0;

          if (serverPlayed) {
            // A played item is the furthest possible progress, so a server
            // completion wins even over a newer partial offline position.
            // Adopt the played state locally.
            await _adopt(pending, 0, played: true, userData: userData);
            synced++;
            continue;
          }

          // Otherwise furthest progress wins, but a local completion outranks
          // any partial server position, so leave it to be pushed below.
          if (!localPlayed && serverTicks > pending.ticks) {
            await _adopt(
              pending,
              serverTicks,
              played: false,
              userData: userData,
            );
            synced++;
            continue;
          }
        }

        final entry = bulk == null ? null : _offlineProgressEntry(pending);
        if (entry != null) {
          bulkPushes.add((pending, entry));
          continue;
        }
        if (pending.ticks == 0) {
          await client.userLibraryApi.markPlayed(item.itemId);
        } else {
          final report = PlaybackStopReport(
            itemId: item.itemId,
            mediaSourceId: item.itemId,
            positionTicks: pending.ticks,
            runTimeTicks: _runTimeTicks(item.metadataJson),
          );
          await client.playbackApi.reportPlaybackStopped(report.toJson());
        }
        await _markSynced(pending);
        synced++;
      } catch (e) {
        debugPrint('[Sync] Failed to sync progress for ${item.itemId}: $e');
        failed++;
      }
    }

    if (bulk != null && bulkPushes.isNotEmpty) {
      final limit = bulk.offlineProgressBatchLimit;
      for (var start = 0; start < bulkPushes.length; start += limit) {
        final batch = bulkPushes.sublist(
          start,
          min(start + limit, bulkPushes.length),
        );
        try {
          final taken = await bulk.syncOfflineProgress([
            for (final (_, entry) in batch) entry,
          ]);
          for (final (i, (pending, _)) in batch.indexed) {
            if (i < taken.length && taken[i]) {
              await _markSynced(pending);
              synced++;
            } else {
              debugPrint(
                '[Sync] Server refused progress for ${pending.row.itemId}',
              );
              failed++;
            }
          }
        } catch (e) {
          debugPrint('[Sync] Failed to sync a batch of progress: $e');
          failed += batch.length;
        }
      }
    }

    _setState(failed > 0 && synced == 0 ? SyncState.error : SyncState.done);
    _scheduleDoneReset();
    return SyncResult(synced: synced, failed: failed);
  }

  /// Kos TV: takes the server's progress for [pending], on the download for
  /// progress that knows nobody (with the metadata the UI reads, as always)
  /// and as the person's own otherwise.
  Future<void> _adopt(
    _PendingProgress pending,
    int ticks, {
    required bool played,
    required Map<String, dynamic> userData,
  }) {
    final row = pending.row;
    if (pending.userId == null) {
      return _offlineRepo.setSyncedPlaybackPosition(
        row.itemId,
        ticks,
        metadataJson: mergeServerUserData(row.metadataJson, userData),
      );
    }
    return _offlineRepo.setUserSyncedProgress(
      row.itemId,
      serverId: row.serverId,
      userId: pending.userId,
      positionTicks: ticks,
      played: played,
      force: true,
    );
  }

  Future<void> _markSynced(_PendingProgress pending) =>
      _offlineRepo.markProgressSynced(
        pending.row.itemId,
        userId: pending.userId,
      );

  static int? _runTimeTicks(String metadataJson) {
    try {
      return (jsonDecode(metadataJson) as Map)['RunTimeTicks'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// [pending]'s offline progress for a bulk sync, or null when it can't be
  /// expressed there: a played item needs its runtime (it is sent as having
  /// reached the end), so one without falls back to marking it played.
  ///
  /// The store keeps no time for offline progress, so it is stamped now. The
  /// server's own newer progress was already preferred above.
  OfflineProgressEntry? _offlineProgressEntry(_PendingProgress pending) {
    final item = pending.row;
    var runtimeTicks = 0;
    try {
      final metadata = jsonDecode(item.metadataJson) as Map<String, dynamic>;
      runtimeTicks = (metadata['RunTimeTicks'] as num?)?.toInt() ?? 0;
    } catch (_) {}
    final played = pending.ticks == 0;
    if (played && runtimeTicks <= 0) return null;
    return OfflineProgressEntry(
      itemId: item.itemId,
      position: Duration(microseconds: pending.ticks ~/ 10),
      runtime: Duration(microseconds: runtimeTicks ~/ 10),
      played: played,
      recordedAt: DateTime.now(),
    );
  }

  /// Returns [metadataJson] with its `UserData` replaced by the server's, so
  /// the offline UI (which reads played/position from metadata) reflects the
  /// adopted progress immediately rather than waiting for a metadata refresh.
  static String mergeServerUserData(
    String metadataJson,
    Map<String, dynamic> userData,
  ) {
    try {
      final decoded = jsonDecode(metadataJson) as Map<String, dynamic>;
      decoded['UserData'] = userData;
      return jsonEncode(decoded);
    } catch (_) {
      return metadataJson;
    }
  }

  /// Fetches the server's `UserData` for [itemIds] in a single query, keyed by
  /// item id. Returns an empty map on failure so callers fall back to pushing
  /// local progress. Ids are stringified because Emby returns them numerically.
  Future<Map<String, Map<String, dynamic>>> _fetchServerUserData(
    MediaServerClient client,
    List<String> itemIds,
  ) async {
    final result = <String, Map<String, dynamic>>{};
    if (itemIds.isEmpty) return result;
    try {
      final response = await client.itemsApi.getItems(
        ids: itemIds,
        fields: 'UserData',
      );
      final items = response['Items'] as List<dynamic>?;
      if (items != null) {
        for (final raw in items) {
          final map = raw as Map<String, dynamic>;
          final id = map['Id']?.toString();
          final userData = map['UserData'] as Map<String, dynamic>?;
          if (id != null && userData != null) {
            result[id] = userData;
          }
        }
      }
    } catch (_) {}
    return result;
  }

  /// Refreshes the metadata of [serverId]'s completed downloads from
  /// [client], media segments included, and pulls newer server progress into
  /// rows with nothing left to push. Other servers' rows wait for their own
  /// server.
  Future<void> refreshMetadata(
    MediaServerClient client, {
    required String? serverId,
  }) async {
    if (serverId == null) return;
    final items = await _offlineRepo.getItems(onlyCompleted: true);
    for (final item in items.where((i) => _isFromServer(i, client, serverId))) {
      try {
        final serverData = await withMediaSegments(
          client.itemsApi,
          item.itemId,
          await client.itemsApi.getItem(item.itemId),
          fallback: () => storedMediaSegmentsJson(item.metadataJson),
        );
        final userData = serverData['UserData'] as Map<String, dynamic>?;
        int? serverTicks;
        if (userData != null) {
          final serverPlayed = userData['Played'] as bool? ?? false;
          serverTicks = serverPlayed ? 0 : (userData['PlaybackPositionTicks'] as int? ?? 0);
        }

        final localItem = await _offlineRepo.getItem(item.itemId);
        if (localItem == null) continue;
        final shouldUpdateTicks = localItem.progressSynced && serverTicks != null;

        // Kos TV: written in place rather than deleted and reinserted, so
        // the columns not refreshed here (whose progress it is, above all)
        // keep their value.
        await _offlineRepo.refreshItemMetadata(
          localItem.itemId,
          serverId: localItem.serverId,
          metadataJson: jsonEncode(serverData),
          syncedPositionTicks: shouldUpdateTicks ? serverTicks : null,
        );
        // Kos TV: the server's answer is the signed-in person's own
        // progress, kept as theirs so whoever is signed in next doesn't see
        // it (unless they still have some of their own to send).
        if (userData != null) {
          await _offlineRepo.setUserSyncedProgress(
            localItem.itemId,
            serverId: localItem.serverId,
            userId: client.userId,
            positionTicks: serverTicks ?? 0,
            played: userData['Played'] as bool? ?? false,
          );
        }
        // Silo's item doesn't list the subtitles saved beside its download,
        // so their streams are carried over.
        final stored = jsonDecode(localItem.metadataJson) as Map<String, dynamic>;
        await _offlineRepo.addMediaStreams(localItem.itemId, [
          for (final s in stored['MediaStreams'] as List? ?? const [])
            if (s is Map<String, dynamic> && s['Type'] == 'Subtitle') s,
        ]);
      } catch (e) {
        debugPrint('[Sync] Failed to refresh metadata for ${item.itemId}: $e');
      }
    }
  }

  void _setState(SyncState newState) {
    _state = newState;
    notifyListeners();
  }

  void _scheduleDoneReset() {
    _doneResetTimer?.cancel();
    _doneResetTimer = Timer(const Duration(seconds: 5), () {
      if (_state == SyncState.done) {
        _setState(SyncState.idle);
      }
    });
  }

  @override
  void dispose() {
    _doneResetTimer?.cancel();
    super.dispose();
  }
}

/// Kos TV: progress waiting to be sent: [ticks] on [row]'s download, either
/// the download's own ([userId] null) or [userId]'s.
class _PendingProgress {
  const _PendingProgress(this.row, this.ticks, this.userId);

  final DownloadedItem row;
  final int ticks;
  final String? userId;
}
