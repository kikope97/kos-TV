import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../../l10n/app_localizations.dart';
import '../models/aggregated_item.dart';
import '../models/home_row.dart';
import 'moonbase_endpoint.dart';
import 'stremfin/stremfin_models.dart';
import 'stremfin/stremfin_service.dart';

/// Kos TV: a row of the home page as the server plugin worked it out for the
/// signed-in person.
@immutable
class KostvHomeServerRow {
  const KostvHomeServerRow({
    required this.kind,
    required this.items,
    this.label,
    this.seedId,
  });

  /// `because_watched`, `because_watching`, `for_you`, `with_person`,
  /// `genre` or `hidden_gems`.
  final String kind;

  /// What the row is about: the title watched, the person or the genre.
  final String? label;
  final String? seedId;
  final List<AggregatedItem> items;

  /// The same for the same row on every load, so Home can tell its rows
  /// apart and keep them in place.
  String idWith(String prefix) =>
      '$prefix${kind}_${seedId ?? (label ?? '').hashCode.toRadixString(36)}';

  String title(AppLocalizations l10n) => switch (kind) {
    'because_watched' => l10n.kostvHomeBecauseWatched(label ?? ''),
    'because_watching' => l10n.kostvHomeBecauseWatching(label ?? ''),
    'with_person' => l10n.kostvHomeMoreFrom(label ?? ''),
    'genre' => l10n.kostvHomeGenre(label ?? ''),
    'hidden_gems' => l10n.kostvHomeGems,
    _ => l10n.kostvHomeForYou,
  };
}

/// Kos TV: the home page built around the person: what they asked for and
/// has arrived, and rows of what they'd like, worked out by the server plugin
/// from what they watched, with what is most watched now in between. All of
/// it is on the home server; nothing here is to ask for.
class KostvHomeRepository {
  KostvHomeRepository(this._client, {Dio? dio, this.stremfin})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              // The first build of a person's page asks TMDB, so it can take a
              // while.
              receiveTimeout: const Duration(seconds: 60),
            ),
          );

  final MediaServerClient _client;
  final Dio _dio;
  final StremfinService? stremfin;

  /// Rows from the server at a time: the first batch with Home, the rest
  /// when the person scrolls down to them.
  static const firstBatch = 5;
  static const moreBatch = 20;

  /// What a person asked for stays at the top this long after it arrives.
  static const arrivedFor = Duration(days: 2);

  /// A row of what is most watched needs this many titles at home.
  static const minTopRow = 4;

  String get _serverId => _client.baseUrl;

  List<AggregatedItem> _cards(Object? raw) => [
    if (raw is List)
      for (final item in raw)
        if (item is Map && item['Id'] != null)
          AggregatedItem(
            id: item['Id'].toString().replaceAll('-', ''),
            serverId: _serverId,
            rawData: item.cast<String, dynamic>(),
          ),
  ];

  /// The person's rows from [start], or null when the plugin can't be asked.
  Future<({List<KostvHomeServerRow> rows, int total})?> rows({
    required int start,
    required int limit,
    bool refresh = false,
  }) async {
    final ep = await moonbaseEndpoint(_client, _dio);
    if (ep == null) return null;
    final response = await _dio.get<dynamic>(
      '${ep.base}/Moonfin/Kostv/Home',
      queryParameters: {
        'start': start,
        'limit': limit,
        if (refresh) 'refresh': true,
      },
      options: Options(headers: ep.headers),
    );
    final data = response.data;
    if (data is! Map) return null;
    final rows = <KostvHomeServerRow>[
      if (data['Rows'] case final List<dynamic> list)
        for (final row in list)
          if (row is Map && row['Kind'] is String)
            KostvHomeServerRow(
              kind: row['Kind'] as String,
              label: row['Label'] as String?,
              seedId: row['SeedId'] as String?,
              items: _cards(row['Items']),
            ),
    ];
    return (rows: rows, total: (data['Total'] as num?)?.toInt() ?? rows.length);
  }

  /// Which of these TMDB titles are on the home server, in the order given.
  Future<List<AggregatedItem>> atHome(
    Iterable<({StremfinTitleType type, int tmdbId})> titles,
  ) async {
    final keys = [
      for (final t in titles)
        '${t.type == StremfinTitleType.series ? 'tv' : 'movie'}:${t.tmdbId}',
    ];
    if (keys.isEmpty) return const [];
    final ep = await moonbaseEndpoint(_client, _dio);
    if (ep == null) return const [];
    final response = await _dio.get<dynamic>(
      '${ep.base}/Moonfin/Kostv/Home/Lookup',
      queryParameters: {'keys': keys.toSet().join(',')},
      options: Options(headers: ep.headers),
    );
    final data = response.data;
    if (data is! Map || data['Items'] is! List) return const [];
    return _cards([
      for (final entry in data['Items'] as List)
        if (entry is Map) entry['Item'],
    ]);
  }

  /// The requests service once it has said whether it lets the person in
  /// (Home can load before it has), or null when it doesn't.
  Future<StremfinService?> allowedStremfin() async {
    final stremfin = this.stremfin;
    if (stremfin == null) return null;
    if (!stremfin.isAllowed) {
      try {
        await stremfin.refreshAccess();
      } catch (_) {
        return null;
      }
    }
    return stremfin.isAllowed ? stremfin : null;
  }

  static bool _unplayed(AggregatedItem item) {
    final data = item.rawData['UserData'];
    return data is! Map || data['Played'] != true;
  }

  /// What the person asked for that arrived in the last two days and they
  /// haven't watched yet; null when there's nothing.
  Future<HomeRow?> arrived(AppLocalizations l10n, {DateTime? now}) async {
    final stremfin = await allowedStremfin();
    if (stremfin == null) return null;
    if (!stremfin.inbox.isLoaded) await stremfin.inbox.sync();
    final recent = arrivedTitles(
      stremfin.inbox.finished,
      now ?? DateTime.now(),
    );
    if (recent.isEmpty) return null;
    final items = (await atHome(recent)).where(_unplayed).toList();
    if (items.isEmpty) return null;
    return HomeRow(
      id: arrivedRowId,
      title: l10n.kostvHomeArrived,
      rowType: HomeRowType.latestMedia,
      items: items,
      totalCount: items.length,
    );
  }

  static const arrivedRowId = 'kostvArrived';

  /// The titles of the person's own requests that got home within
  /// [arrivedFor] of [now], the newest first.
  @visibleForTesting
  static List<({StremfinTitleType type, int tmdbId})> arrivedTitles(
    Iterable<StremfinRequest> finished,
    DateTime now,
  ) {
    final recent = [
      for (final r in finished)
        if (r.mine &&
            r.status == StremfinRequestStatus.completed &&
            r.type != null &&
            r.tmdbId != null &&
            r.completedAt != null &&
            now.difference(r.completedAt!) <= arrivedFor)
          r,
    ]..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    return [for (final r in recent) (type: r.type!, tmdbId: r.tmdbId!)];
  }

  /// What is most watched now on [platform] (`all` for every one), of what
  /// is at home and the person hasn't watched: films and series by turns, in
  /// their order on the list. Null when too few are at home.
  Future<HomeRow?> top({
    required String platform,
    required String id,
    required String title,
  }) async {
    final stremfin = await allowedStremfin();
    if (stremfin == null) return null;
    final lists = await Future.wait([
      for (final type in StremfinTitleType.values)
        stremfin
            .top(platform: platform, type: type, list: StremfinTopList.popular)
            .catchError((Object _) => const <StremfinTitle>[]),
    ]);
    final ranked = byTurns([
      for (final list in lists)
        [
          for (final t in list)
            if (t.library.inLibrary) t,
        ],
    ]);
    if (ranked.length < minTopRow) return null;
    final items = (await atHome([
      for (final t in ranked) (type: t.type, tmdbId: t.tmdbId),
    ])).where(_unplayed).toList();
    if (items.length < minTopRow) return null;
    return HomeRow(
      id: id,
      title: title,
      rowType: HomeRowType.latestMedia,
      items: items,
      totalCount: items.length,
    );
  }

  /// One from each list by turns, so a row of two lists carries both.
  static List<T> byTurns<T>(List<List<T>> lists) {
    final out = <T>[];
    final longest = lists.fold(0, (n, l) => l.length > n ? l.length : n);
    for (var i = 0; i < longest; i++) {
      for (final list in lists) {
        if (i < list.length) out.add(list[i]);
      }
    }
    return out;
  }

  /// Home rows from the plugin's, with [tops] slipped in: the first after the
  /// first row, then one every [every] rows.
  static List<HomeRow> weave(
    List<HomeRow> rows,
    List<HomeRow> tops, {
    int every = 2,
  }) {
    final out = <HomeRow>[];
    var next = 0;
    for (final (index, row) in rows.indexed) {
      out.add(row);
      if (next < tops.length && (index == 0 || (index % every) == 0)) {
        out.add(tops[next++]);
      }
    }
    out.addAll(tops.skip(next));
    return out;
  }
}
