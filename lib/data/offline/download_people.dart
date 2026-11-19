import '../database/offline_database.dart';

/// Kos TV: a user id the way the downloads store keeps it. Jellyfin writes the
/// same id with and without dashes, in either case, depending on the call.
String normalizeDownloadUserId(String? id) =>
    (id ?? '').replaceAll('-', '').toLowerCase();

/// Kos TV: whose a download is, seen by the person signed in.
enum DownloadOwnership {
  /// They downloaded it.
  mine,

  /// Nobody is known to have downloaded it: it predates owners, so it is
  /// everyone's, as every download used to be.
  everyone,

  /// Somebody else downloaded it. It still plays, from the same file.
  others,
}

/// Kos TV: everyone tied to the downloads on this device, keyed by item and
/// server, as read from [DownloadedItemUsers].
class DownloadPeople {
  DownloadPeople(Iterable<DownloadedItemUser> rows) {
    for (final row in rows) {
      (_byItem[_key(row.itemId, row.serverId)] ??= {})[row.userId] = row;
    }
  }

  static final empty = DownloadPeople(const []);

  final _byItem = <String, Map<String, DownloadedItemUser>>{};

  static String _key(String itemId, String serverId) =>
      '$serverId\u0000$itemId';

  Map<String, DownloadedItemUser> _of(String itemId, String serverId) =>
      _byItem[_key(itemId, serverId)] ?? const {};

  /// Whose [row]'s download is for [userId].
  DownloadOwnership ownershipOf(DownloadedItem row, String? userId) =>
      ownershipFor(row.itemId, row.serverId, userId);

  DownloadOwnership ownershipFor(
    String itemId,
    String serverId,
    String? userId,
  ) {
    final people = _of(itemId, serverId);
    if (!people.values.any((p) => p.isOwner)) {
      return DownloadOwnership.everyone;
    }
    final me = people[normalizeDownloadUserId(userId)];
    return me?.isOwner == true
        ? DownloadOwnership.mine
        : DownloadOwnership.others;
  }

  /// Whether somebody other than [userId] downloaded [row]'s item, so
  /// deleting it takes it away from them too.
  bool hasOtherOwners(DownloadedItem row, String? userId) {
    final me = normalizeDownloadUserId(userId);
    return _of(
      row.itemId,
      row.serverId,
    ).values.any((p) => p.isOwner && p.userId != me);
  }

  /// [userId]'s own record for [row]'s item, if they have one.
  DownloadedItemUser? personOf(DownloadedItem row, String? userId) {
    if (userId == null || userId.isEmpty) return null;
    return _of(row.itemId, row.serverId)[normalizeDownloadUserId(userId)];
  }

  /// How far [userId] got in [row]'s item, as `(positionTicks, played)`.
  ///
  /// Their own progress when they have some. Otherwise, a download that is
  /// theirs or everyone's keeps what the download itself carries (what it
  /// always showed); someone else's starts from the beginning, so one
  /// person's watching never shows up as another's.
  ({int positionTicks, bool? played}) progressOf(
    DownloadedItem row,
    String? userId,
  ) {
    final me = personOf(row, userId);
    if (me != null && me.hasProgress) {
      return (
        positionTicks: me.played ? 0 : me.positionTicks,
        played: me.played,
      );
    }
    if (ownershipOf(row, userId) == DownloadOwnership.others) {
      return (positionTicks: 0, played: false);
    }
    return (positionTicks: row.playbackPositionTicks, played: null);
  }

  /// [row] as [userId] sees it: its position column holds their progress.
  DownloadedItem rowFor(DownloadedItem row, String? userId) {
    final progress = progressOf(row, userId);
    if (progress.positionTicks == row.playbackPositionTicks) return row;
    return row.copyWith(playbackPositionTicks: progress.positionTicks);
  }

  /// [metadata]'s `UserData` with [userId]'s progress on [row]'s item, for
  /// the screens that read played state and position from there. Null when
  /// the download's own progress stands, which the caller merges as before.
  Map<String, dynamic>? personalUserData(
    DownloadedItem row,
    Map<String, dynamic> metadata,
    String? userId,
  ) {
    final progress = progressOf(row, userId);
    if (progress.played == null) return null;
    final userData = <String, dynamic>{
      ...?(metadata['UserData'] as Map?)?.cast<String, dynamic>(),
    };
    final runtime = (metadata['RunTimeTicks'] as num?)?.toInt();
    final ticks = progress.positionTicks;
    if (progress.played! ||
        (ticks > 0 &&
            runtime != null &&
            runtime > 0 &&
            ticks >= runtime * 0.9)) {
      userData['Played'] = true;
      userData['PlaybackPositionTicks'] = 0;
      userData.remove('PlayedPercentage');
    } else {
      userData['Played'] = false;
      userData['PlaybackPositionTicks'] = ticks;
      if (ticks > 0 && runtime != null && runtime > 0) {
        userData['PlayedPercentage'] = (ticks / runtime) * 100.0;
      } else {
        userData.remove('PlayedPercentage');
      }
    }
    return userData;
  }
}

/// Kos TV: the saved media list as [userId] sees it: [mine] is what they
/// downloaded plus what predates owners (everyone's, as it always was), and
/// [others] what somebody else downloaded, which still plays from the same
/// file. Every row carries [userId]'s own progress.
///
/// In Kids Mode only [mine] is shown, without what [isBlocked] says the
/// ratings the device blocks leave out.
({List<DownloadedItem> mine, List<DownloadedItem> others}) splitDownloadsFor(
  List<DownloadedItem> items,
  DownloadPeople people,
  String? userId, {
  bool kidsMode = false,
  bool Function(DownloadedItem item)? isBlocked,
}) {
  final mine = <DownloadedItem>[];
  final others = <DownloadedItem>[];
  for (final item in items) {
    final ownership = people.ownershipOf(item, userId);
    if (kidsMode) {
      if (ownership == DownloadOwnership.others) continue;
      if (isBlocked?.call(item) ?? false) continue;
    }
    final row = people.rowFor(item, userId);
    (ownership == DownloadOwnership.others ? others : mine).add(row);
  }
  return (mine: mine, others: others);
}
