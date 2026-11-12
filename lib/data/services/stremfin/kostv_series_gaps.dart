import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../preference/user_preferences.dart';
import '../../models/aggregated_item.dart';
import 'stremfin_models.dart';
import 'stremfin_service.dart';

/// Kos TV: how an episode the home server lacks stands with the requests
/// service.
enum KostvGhostState {
  /// It can be asked for.
  requestable,

  /// Someone else asked for it: asking joins their request.
  joinable,

  /// The person asked for it (or for its season, or for all that's missing).
  requested,

  /// It is coming down.
  downloading,

  /// It hasn't been on yet.
  upcoming,

  /// It can't be had.
  unavailable,
}

/// Kos TV: an episode of a series at home that the home server doesn't have,
/// shown greyed among the ones it has.
@immutable
class KostvGhostEpisode {
  const KostvGhostEpisode({required this.season, required this.source});

  final int season;
  final StremfinEpisode source;

  int get number => source.number;
  String? get title => source.title;
  DateTime? get airDate => source.airDate;
  StremfinRequestRef? get request => source.request;

  KostvGhostState get state {
    if (!source.aired) return KostvGhostState.upcoming;
    if (source.downloading) return KostvGhostState.downloading;
    final request = source.request;
    if (request != null && request.mine) return KostvGhostState.requested;
    if (source.canRequest) {
      return request != null
          ? KostvGhostState.joinable
          : KostvGhostState.requestable;
    }
    if (request != null) return KostvGhostState.requested;
    return KostvGhostState.unavailable;
  }

  /// Whether asking for it is offered.
  bool get canAsk =>
      state == KostvGhostState.requestable || state == KostvGhostState.joinable;
}

/// Kos TV: a line of a season's episode list: an episode the home server
/// has, or one it lacks.
typedef KostvEpisodeEntry = ({
  AggregatedItem? episode,
  KostvGhostEpisode? ghost,
});

/// Kos TV: a season of a series at home as the requests service sees it,
/// next to what the home server has of it.
@immutable
class KostvSeasonGaps {
  const KostvSeasonGaps({
    required this.season,
    required this.missing,
    required this.upcoming,
    required this.atHome,
  });

  final StremfinSeason season;

  /// Episodes already on that the home server lacks, in order.
  final List<KostvGhostEpisode> missing;

  /// Episodes not on yet, in order: they go after everything else.
  final List<KostvGhostEpisode> upcoming;

  /// Whether the home server has any episode of it.
  final bool atHome;

  int get number => season.number;

  /// The missing ones that can still be asked for.
  int get askable => missing.where((g) => g.canAsk).length;

  /// The whole season (what's missing of it) can be asked for in one go.
  bool get canAskSeason => season.canRequest;

  /// The open request that covers the whole season, if any.
  StremfinRequestRef? get seasonRequest => season.request;

  /// Nothing of it has been on yet.
  bool get notOnYet => season.aired == 0;

  /// The day its first episode is on, when not on yet.
  DateTime? get premiere => upcoming.isEmpty ? null : upcoming.first.airDate;

  /// The season line by line: [episodes], the home server's in their order,
  /// with the missing ones in their place and those not on yet last. The
  /// home server's own placeholders for missing episodes give way to these.
  List<KostvEpisodeEntry> merge(Iterable<AggregatedItem> episodes) {
    final entries = <KostvEpisodeEntry>[];
    var next = 0;
    for (final episode in episodes) {
      if (!KostvSeriesGaps.isOnServer(episode)) continue;
      final number = episode.indexNumber;
      while (next < missing.length &&
          number != null &&
          missing[next].number < number) {
        entries.add((episode: null, ghost: missing[next++]));
      }
      entries.add((episode: episode, ghost: null));
    }
    while (next < missing.length) {
      entries.add((episode: null, ghost: missing[next++]));
    }
    for (final ghost in upcoming) {
      entries.add((episode: null, ghost: ghost));
    }
    return entries;
  }
}

/// Kos TV: what a series at home lacks, worked out from the requests
/// service's page of it and the episodes the home server has.
///
/// The two number episodes their own way (TMDB for the service, whatever the
/// library uses for the home server), and anime or series ordered by TVDB can
/// disagree. So an episode only counts as missing when the service says it
/// isn't on the home server and the home server has no episode with that
/// number; and a season where the home server has more episodes than the
/// service knows of is taken as numbered differently and left alone.
/// Specials (season 0) are left out, as the service does.
@immutable
class KostvSeriesGaps {
  const KostvSeriesGaps({required this.tmdbId, required this.seasons});

  /// No gaps.
  static const none = KostvSeriesGaps(tmdbId: 0, seasons: {});

  final int tmdbId;
  final Map<int, KostvSeasonGaps> seasons;

  bool get isEmpty =>
      seasons.values.every((s) => s.missing.isEmpty && s.upcoming.isEmpty);

  KostvSeasonGaps? season(int number) => seasons[number];

  /// Seasons the home server has nothing of: missing ones, then the ones not
  /// on yet, in order.
  List<KostvSeasonGaps> get seasonsNotAtHome => [
    for (final s in seasons.values)
      if (!s.atHome && (s.missing.isNotEmpty || s.upcoming.isNotEmpty)) s,
  ]..sort((a, b) => a.number.compareTo(b.number));

  /// For the player: the episodes already on that the home server lacks
  /// right after episode [episode] of season [season], up to (not including)
  /// [nextSeason]·[nextEpisode] when there is a next one at home, else up to
  /// the end of that season.
  List<KostvGhostEpisode> missingAfter({
    required int season,
    required int episode,
    int? nextSeason,
    int? nextEpisode,
  }) {
    final gaps = seasons[season];
    if (gaps == null) return const [];
    // Only the run that follows on directly: with the very next one at home
    // there's no gap to speak of, whatever is missing further on.
    final run = <KostvGhostEpisode>[];
    var expected = episode + 1;
    for (final ghost in gaps.missing) {
      if (ghost.number < expected) continue;
      if (ghost.number > expected) break;
      if (nextSeason == season &&
          nextEpisode != null &&
          ghost.number >= nextEpisode) {
        break;
      }
      run.add(ghost);
      expected++;
    }
    return run;
  }

  static KostvSeriesGaps compute({
    required StremfinSeriesDetail detail,
    required Iterable<AggregatedItem> episodes,
  }) {
    // The episode numbers the home server has, season by season (a double
    // episode counts for both).
    final have = <int, Set<int>>{};
    for (final episode in episodes) {
      if (!isOnServer(episode)) continue;
      final season = episode.parentIndexNumber;
      final first = episode.indexNumber;
      if (season == null || first == null) continue;
      final last = _int(episode.rawData['IndexNumberEnd']) ?? first;
      final numbers = have.putIfAbsent(season, () => <int>{});
      for (var n = first; n <= last && n - first < 50; n++) {
        numbers.add(n);
      }
    }

    final seasons = <int, KostvSeasonGaps>{};
    for (final season in detail.seasons) {
      if (season.number < 1) continue;
      final atHome = have[season.number] ?? const <int>{};
      // Numbered differently from the service: no guessing.
      if (season.episodes.isNotEmpty &&
          atHome.length > season.episodes.length) {
        continue;
      }
      final missing = <KostvGhostEpisode>[];
      final upcoming = <KostvGhostEpisode>[];
      for (final episode in season.episodes) {
        if (atHome.contains(episode.number) || episode.inLibrary) continue;
        final ghost = KostvGhostEpisode(season: season.number, source: episode);
        (episode.aired ? missing : upcoming).add(ghost);
      }
      seasons[season.number] = KostvSeasonGaps(
        season: season,
        missing: missing,
        upcoming: upcoming,
        atHome: atHome.isNotEmpty,
      );
    }
    return KostvSeriesGaps(tmdbId: detail.title.tmdbId, seasons: seasons);
  }

  /// Whether [episode] is really on the home server, not a placeholder it
  /// lists for a missing one.
  static bool isOnServer(AggregatedItem episode) {
    final raw = episode.rawData;
    final location = (raw['LocationType'] as String?)?.toLowerCase();
    return location != 'virtual' &&
        raw['IsMissing'] != true &&
        raw['IsVirtualItem'] != true &&
        raw['IsPlaceholder'] != true;
  }

  static int? _int(Object? raw) => switch (raw) {
    final int value => value,
    final num value => value.toInt(),
    final String value => int.tryParse(value),
    _ => null,
  };
}

/// Kos TV: the requests service's page of a series at home, for its missing
/// episodes, on the series' page and in the player.
///
/// The page is one of the service's costly calls, so it is read only when a
/// season or an episode of the series is shown, and kept a while for every
/// screen of the same series.
class KostvSeriesGapsController extends ChangeNotifier {
  KostvSeriesGapsController({
    StremfinService? service,
    UserPreferences? prefs,
    @visibleForTesting Future<String?> Function(AggregatedItem item)? tmdbIdOf,
  }) : _service =
           service ??
           (GetIt.instance.isRegistered<StremfinService>()
               ? GetIt.instance<StremfinService>()
               : null),
       _prefs =
           prefs ??
           (GetIt.instance.isRegistered<UserPreferences>()
               ? GetIt.instance<UserPreferences>()
               : null),
       _tmdbIdOf = tmdbIdOf ?? _seriesTmdbId {
    _service?.addListener(_onService);
  }

  final StremfinService? _service;
  final UserPreferences? _prefs;
  final Future<String?> Function(AggregatedItem item) _tmdbIdOf;

  /// How long a series' page is kept.
  static const lifetime = Duration(minutes: 10);

  // Kept for the person it was read for: a series' page says which requests
  // are theirs.
  static final Map<int, ({DateTime at, StremfinSeriesDetail detail})> _kept =
      {};
  static final Map<int, Future<StremfinSeriesDetail>> _reading = {};
  static Object? _keptFor;

  static void _keepFor(StremfinService service) {
    final person = service.me?.name;
    if (identical(_keptFor, service) && _keptPerson == person) return;
    _keptFor = service;
    _keptPerson = person;
    _kept.clear();
    _reading.clear();
  }

  static String? _keptPerson;

  @visibleForTesting
  static void clearKept() {
    _kept.clear();
    _reading.clear();
  }

  int? _tmdbId;
  StremfinSeriesDetail? _detail;
  bool _disposed = false;

  // Bumped by every load, so an answer for a series the screen has moved on
  // from is dropped.
  int _load = 0;

  /// Something is being asked for now.
  bool sending = false;

  int? get tmdbId => _tmdbId;
  StremfinSeriesDetail? get detail => _detail;

  /// Whether missing episodes are shown at all: someone the service lets in,
  /// outside kids mode, and a series their age limit allows.
  bool get enabled {
    final service = _service;
    if (service == null || !service.isAllowed) return false;
    if (_prefs?.get(UserPreferences.kidsModeEnabled) ?? false) return false;
    final detail = _detail;
    return detail == null || service.allows(detail.title);
  }

  /// The person as the service sees them: their limits.
  StremfinMe? get me => _service?.me;

  /// The person has reached their limit of requests.
  bool get atLimit => me?.atLimit ?? false;

  /// What the series lacks next to [episodes], the ones the home server has.
  KostvSeriesGaps gapsFor(Iterable<AggregatedItem> episodes) {
    final detail = _detail;
    if (detail == null || !enabled || episodes.isEmpty) {
      return KostvSeriesGaps.none;
    }
    return KostvSeriesGaps.compute(detail: detail, episodes: episodes);
  }

  void _onService() {
    if (!_disposed) notifyListeners();
  }

  /// Reads the service's page of the series [item] belongs to (a series, a
  /// season or an episode). Quietly does nothing for a series the service
  /// can't place or a person it doesn't let in.
  Future<void> loadFor(AggregatedItem item, {bool refresh = false}) async {
    final service = _service;
    if (service == null) return;
    final load = ++_load;
    if (!service.isAllowed) await service.refreshAccess();
    if (_disposed || load != _load || !service.isAllowed) return;
    final tmdb = int.tryParse((await _tmdbIdOf(item)) ?? '');
    if (_disposed || load != _load) return;
    if (tmdb != _tmdbId) {
      // Another series (or one the service can't place): the last one's
      // page says nothing of it.
      _tmdbId = tmdb;
      _detail = null;
      notifyListeners();
    }
    if (tmdb == null) return;
    try {
      final detail = await _read(service, tmdb, refresh: refresh);
      if (_disposed || load != _load) return;
      _detail = detail;
      notifyListeners();
    } catch (e) {
      debugPrint('[KostvSeriesGaps] Could not read series $tmdb: $e');
    }
  }

  static Future<StremfinSeriesDetail> _read(
    StremfinService service,
    int tmdb, {
    bool refresh = false,
  }) {
    _keepFor(service);
    final kept = _kept[tmdb];
    if (!refresh &&
        kept != null &&
        DateTime.now().difference(kept.at) < lifetime) {
      return Future.value(kept.detail);
    }
    final pending = _reading[tmdb];
    // A read asked for after a request must not settle for one from before.
    if (pending != null && !refresh) return pending;
    final future = service
        .series(tmdb)
        .then((detail) {
          _kept[tmdb] = (at: DateTime.now(), detail: detail);
          return detail;
        })
        .whenComplete(() {
          _reading.remove(tmdb);
        });
    return _reading[tmdb] = future;
  }

  /// Asks for one episode, or for what's missing of a whole season when
  /// [episode] is null. Gives back the service's word on it to show.
  Future<StremfinRequestResult?> ask({
    required int season,
    int? episode,
  }) async {
    final service = _service;
    final tmdb = _tmdbId;
    if (service == null || tmdb == null || sending || !enabled) return null;
    sending = true;
    notifyListeners();
    try {
      final result = await service.createRequest(
        type: StremfinTitleType.series,
        tmdbId: tmdb,
        season: season,
        episode: episode,
      );
      await _rereadAfterAsking(service, tmdb);
      return result;
    } finally {
      sending = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// The request went through; the page is read again to show it. If that
  /// fails the request still stands, so it isn't told as a failure.
  Future<void> _rereadAfterAsking(StremfinService service, int tmdb) async {
    try {
      final detail = await _read(service, tmdb, refresh: true);
      if (!_disposed && tmdb == _tmdbId) _detail = detail;
    } catch (e) {
      _kept.remove(tmdb);
      debugPrint('[KostvSeriesGaps] Could not read series $tmdb again: $e');
    }
  }

  /// Asks for several missing episodes of season [season] one by one, and
  /// reads the series again once. Gives back the service's word on the last.
  Future<StremfinRequestResult?> askEpisodes({
    required int season,
    required List<int> episodes,
  }) async {
    final service = _service;
    final tmdb = _tmdbId;
    if (service == null ||
        tmdb == null ||
        sending ||
        !enabled ||
        episodes.isEmpty) {
      return null;
    }
    sending = true;
    notifyListeners();
    try {
      StremfinRequestResult? last;
      for (final episode in episodes) {
        last = await service.createRequest(
          type: StremfinTitleType.series,
          tmdbId: tmdb,
          season: season,
          episode: episode,
        );
        if (last.outcome == StremfinOutcome.limit) break;
      }
      await _rereadAfterAsking(service, tmdb);
      return last;
    } finally {
      sending = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _service?.removeListener(_onService);
    super.dispose();
  }

  /// The TMDB id of the series [item] belongs to: its own on a series, the
  /// series' (read from the home server) on a season or an episode.
  static Future<String?> _seriesTmdbId(AggregatedItem item) async {
    if (item.type == 'Series') return item.tmdbId;
    final seriesId = item.seriesId;
    if (seriesId == null || !GetIt.instance.isRegistered<MediaServerClient>()) {
      return null;
    }
    try {
      final raw = await GetIt.instance<MediaServerClient>().itemsApi.getItem(
        seriesId,
        fields: 'ProviderIds',
      );
      final ids = raw['ProviderIds'];
      if (ids is! Map) return null;
      final tmdb = ids['Tmdb'] ?? ids['tmdb'] ?? ids['TMDB'];
      return tmdb?.toString();
    } catch (_) {
      return null;
    }
  }
}
