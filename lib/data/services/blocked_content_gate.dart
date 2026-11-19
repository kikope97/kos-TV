import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../preference/user_preferences.dart';
import '../models/aggregated_item.dart';
import '../offline/offline_catalog.dart';
import '../utils/blocked_ratings.dart';

/// Decides whether an item may be opened or played.
///
/// The list filters answer from a rating in hand. This has the harder job: an
/// episode usually carries no rating of its own while its series does, so the
/// series has to be found before the answer is known.
///
/// Fails open on genuine uncertainty. A server that rates nothing can't be told
/// apart from an item nobody rated, and blanking the app is worse than the gap.
/// The one exception is a series already seen carrying a blocked rating, which
/// stays blocked so a dropped connection can't undo a refusal.
class BlockedContentGate {
  final MediaServerClient _client;
  final UserPreferences _prefs;

  final Map<String, String?> _seriesRating = {};
  final Map<String, Future<String?>> _inFlight = {};

  BlockedContentGate(this._client, this._prefs);

  static const _lookupTimeout = Duration(seconds: 3);

  Set<String> get _stickyBlocked {
    final csv = _prefs.get(UserPreferences.blockedSeriesIds);
    if (csv.trim().isEmpty) return const {};
    return csv.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  /// Remembers any series rating the app happens to parse, so the common path
  /// never needs a lookup.
  void observe(AggregatedItem item) {
    if (item.type != 'Series') return;
    final rating = item.officialRating?.trim();
    if (item.id.isEmpty) return;
    _seriesRating[item.id] = (rating != null && rating.isNotEmpty) ? rating : null;
  }

  /// Answers from what is already in hand. No network, so a whole queue can be
  /// strained through it. A miss reads as allowed and is caught later by
  /// [isBlocked] for the one item about to play.
  bool isBlockedNow(AggregatedItem item) {
    final own = item.officialRating?.trim();
    if (own != null && own.isNotEmpty) return isRatingBlocked(own);

    final seriesId = item.seriesId;
    if (seriesId == null || seriesId.isEmpty) return false;
    if (_stickyBlocked.contains(seriesId)) return true;

    final cached = _seriesRating[seriesId] ?? _offlineSeriesRating(seriesId);
    return cached == null ? false : isRatingBlocked(cached);
  }

  /// The authoritative answer for the one item about to open or play. Resolves
  /// the series over the network when it has to.
  Future<bool> isBlocked(AggregatedItem item) async {
    final own = item.officialRating?.trim();
    if (own != null && own.isNotEmpty) return isRatingBlocked(own);

    final seriesId = item.seriesId;
    if (seriesId == null || seriesId.isEmpty) return false;

    final (rating, resolved) = await _resolveSeriesRating(seriesId);
    // A lookup that worked always wins, so unblocking a rating releases the
    // series rather than leaving it refused forever.
    if (resolved) {
      final blocked = rating != null && isRatingBlocked(rating);
      await _rememberSeries(seriesId, blocked: blocked);
      return blocked;
    }

    // Nothing to go on, so fall back to what this device last knew.
    return _stickyBlocked.contains(seriesId);
  }

  /// Kos TV: [items] without the episodes and seasons whose series carries a
  /// rating blocked on this device, judged as [isBlocked] judges one about to
  /// play: their own rating first, then the series'. For the lists that mix
  /// titles of many series (Continue Watching, Next Up, the search, a person's
  /// titles), whose episodes rarely carry a rating of their own.
  ///
  /// The series not known yet are asked for in one request, and only while a
  /// rating is blocked. One that can't be found out stays listed unless this
  /// device already refused it, as [isBlocked] does.
  Future<List<AggregatedItem>> withoutBlockedSeriesItems(
    List<AggregatedItem> items,
  ) async {
    if (!activeParentalFilter.isActive || items.isEmpty) return items;

    final unknown = <String>{
      for (final item in items)
        if (_unratedSeriesId(item) case final seriesId?)
          if (!_seriesRating.containsKey(seriesId) &&
              _offlineSeriesRating(seriesId) == null)
            seriesId,
    };
    if (unknown.isNotEmpty) await _lookUpSeries(unknown);

    final sticky = _stickyBlocked;
    final kept = items.where((item) {
      final own = item.officialRating?.trim();
      if (own != null && own.isNotEmpty) return !isRatingBlocked(own);
      final seriesId = _unratedSeriesId(item);
      if (seriesId == null) return true;
      final rating = _seriesRating.containsKey(seriesId)
          ? _seriesRating[seriesId]
          : _offlineSeriesRating(seriesId);
      if (rating != null) return !isRatingBlocked(rating);
      // Known to have no rating, so nothing to block it by.
      if (_seriesRating.containsKey(seriesId)) return true;
      return !sticky.contains(seriesId);
    }).toList();
    return kept.length == items.length ? items : kept;
  }

  /// The series [item] has to be judged by: an episode's or season's, when it
  /// carries no rating of its own.
  static String? _unratedSeriesId(AggregatedItem item) {
    final own = item.officialRating?.trim();
    if (own != null && own.isNotEmpty) return null;
    final seriesId = item.seriesId;
    return seriesId == null || seriesId.isEmpty ? null : seriesId;
  }

  /// Asks for the ratings of [seriesIds] at once and remembers them, also on
  /// this device's list of refused series, as [isBlocked] does. A failed
  /// request leaves them unknown.
  Future<void> _lookUpSeries(Set<String> seriesIds) async {
    final Map<String, dynamic> data;
    try {
      data = await _client.itemsApi
          .getItems(
            ids: seriesIds.toList(),
            fields: 'OfficialRating',
            enableTotalRecordCount: false,
          )
          .timeout(_lookupTimeout);
    } catch (_) {
      return;
    }
    final sticky = _stickyBlocked;
    final next = sticky.toSet();
    for (final raw in (data['Items'] as List? ?? const []).whereType<Map>()) {
      final id = raw['Id']?.toString();
      if (id == null || !seriesIds.contains(id)) continue;
      final rating = raw['OfficialRating']?.toString().trim();
      final known = rating != null && rating.isNotEmpty ? rating : null;
      _seriesRating[id] = known;
      if (known != null && isRatingBlocked(known)) {
        next.add(id);
      } else {
        next.remove(id);
      }
    }
    if (next.length != sticky.length || !next.containsAll(sticky)) {
      await _prefs.set(UserPreferences.blockedSeriesIds, next.join(','));
    }
  }

  String? _offlineSeriesRating(String seriesId) {
    if (!GetIt.instance.isRegistered<OfflineCatalog>()) return null;
    final entry = GetIt.instance<OfflineCatalog>().byId(seriesId);
    final rating = entry?.metadata['OfficialRating']?.toString().trim();
    return (rating != null && rating.isNotEmpty) ? rating : null;
  }

  /// The series' rating, and whether the question could be answered at all.
  ///
  /// A lookup that failed isn't the same as a series with no rating, and
  /// conflating them would cache the failure for the rest of the session.
  Future<(String?, bool)> _resolveSeriesRating(String seriesId) async {
    if (_seriesRating.containsKey(seriesId)) {
      return (_seriesRating[seriesId], true);
    }
    final offline = _offlineSeriesRating(seriesId);
    if (offline != null) {
      _seriesRating[seriesId] = offline;
      return (offline, true);
    }

    // One request even when a whole season is queued.
    final pending = _inFlight[seriesId] ??= () async {
      final data = await _client.itemsApi
          .getItem(seriesId)
          .timeout(_lookupTimeout);
      final rating = data['OfficialRating']?.toString().trim();
      return (rating != null && rating.isNotEmpty) ? rating : null;
    }();

    try {
      final rating = await pending;
      _seriesRating[seriesId] = rating;
      return (rating, true);
    } catch (_) {
      return (null, false);
    } finally {
      _inFlight.remove(seriesId);
    }
  }

  Future<void> _rememberSeries(String seriesId, {required bool blocked}) async {
    final current = _stickyBlocked;
    if (blocked == current.contains(seriesId)) return;
    final next = current.toSet();
    if (blocked) {
      next.add(seriesId);
    } else {
      next.remove(seriesId);
    }
    await _prefs.set(UserPreferences.blockedSeriesIds, next.join(','));
  }
}

/// Kos TV: [items] without what [BlockedContentGate.withoutBlockedSeriesItems]
/// leaves out, or [items] as they are when there is no gate (a test, or a
/// boot ordering this knows nothing about) or it can't answer.
Future<List<AggregatedItem>> withoutBlockedSeriesItems(
  List<AggregatedItem> items,
) async {
  if (!activeParentalFilter.isActive || items.isEmpty) return items;
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<BlockedContentGate>()) return items;
  try {
    return await getIt<BlockedContentGate>().withoutBlockedSeriesItems(items);
  } catch (_) {
    return items;
  }
}
