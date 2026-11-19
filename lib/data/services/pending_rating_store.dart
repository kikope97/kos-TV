import 'dart:convert';

import 'package:jellyfin_preference/jellyfin_preference.dart';

/// A rating set while the server was unreachable, waiting to be pushed.
///
/// Exactly one of the shapes applies: [clear] removes the rating, [rating]
/// carries a numeric score out of 10, and [likes] carries a thumbs value.
class PendingRating {
  final String serverId;
  final String itemId;

  /// Kos TV: who rated it, so it is sent with their session and not with
  /// whoever is signed in when the connection comes back. Null on entries
  /// queued before this was kept.
  final String? userId;
  final bool? likes;
  final double? rating;
  final bool clear;

  const PendingRating({
    required this.serverId,
    required this.itemId,
    this.userId,
    this.likes,
    this.rating,
    this.clear = false,
  });

  /// Kos TV: whether [otherUserId] is who rated it. An entry from before
  /// the user was kept belongs to anyone, as it always did.
  bool isOf(String? otherUserId) =>
      userId == null || _sameId(userId, otherUserId);

  bool _sameOwner(PendingRating other) =>
      serverId == other.serverId &&
      itemId == other.itemId &&
      _sameId(userId, other.userId);

  static bool _sameId(String? a, String? b) =>
      (a ?? '').replaceAll('-', '').toLowerCase() ==
      (b ?? '').replaceAll('-', '').toLowerCase();

  Map<String, dynamic> toJson() => {
    'serverId': serverId,
    'itemId': itemId,
    if (userId != null) 'userId': userId,
    if (likes != null) 'likes': likes,
    if (rating != null) 'rating': rating,
    if (clear) 'clear': clear,
  };

  static PendingRating? fromJson(Map<String, dynamic> json) {
    final serverId = json['serverId'] as String?;
    final itemId = json['itemId'] as String?;
    if (serverId == null || itemId == null) return null;
    return PendingRating(
      serverId: serverId,
      itemId: itemId,
      userId: json['userId'] as String?,
      likes: json['likes'] as bool?,
      rating: (json['rating'] as num?)?.toDouble(),
      clear: json['clear'] as bool? ?? false,
    );
  }
}

/// Holds ratings set offline until [SyncService] replays them. One entry per
/// item and person, so rating twice offline pushes only the final value.
class PendingRatingStore {
  static const _storageKey = 'pending_ratings_v1';

  final PreferenceStore _store;

  PendingRatingStore(this._store);

  List<PendingRating> get all {
    final raw = _store.getStringList(_storageKey) ?? const <String>[];
    final entries = <PendingRating>[];
    for (final line in raw) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) continue;
        final entry = PendingRating.fromJson(decoded);
        if (entry != null) entries.add(entry);
      } catch (_) {}
    }
    return entries;
  }

  Future<void> put(PendingRating entry) async {
    final next = [
      for (final existing in all)
        if (!existing._sameOwner(entry)) existing,
      entry,
    ];
    await _save(next);
  }

  /// Drops the entry for [itemId] on [serverId]; with [userId], only that
  /// person's.
  Future<void> remove(String serverId, String itemId, {String? userId}) async {
    final probe = PendingRating(
      serverId: serverId,
      itemId: itemId,
      userId: userId,
    );
    final next = all
        .where(
          (e) => userId == null
              ? e.serverId != serverId || e.itemId != itemId
              : !e._sameOwner(probe),
        )
        .toList();
    await _save(next);
  }

  Future<void> _save(List<PendingRating> entries) async {
    await _store.setStringList(_storageKey, [
      for (final entry in entries) jsonEncode(entry.toJson()),
    ]);
  }
}
