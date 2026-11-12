part of 'stremfin_models.dart';

// Kos TV: what the requests service answers about one title and the
// requests for it: its page, whether it can be had and how fast, and how a
// request stands. Unknown fields are ignored and unknown values fall back to
// `unknown`, as its API asks.

/// What asking for a film does now.
enum StremfinRequestAction {
  /// Ask for it.
  request,

  /// It is already on its way: asking only puts the person on the list of
  /// who is told when it arrives.
  notify;

  static StremfinRequestAction? fromApi(Object? value) => switch (value) {
    'request' => request,
    'notify' => notify,
    _ => null,
  };
}

/// Whether the person may ask for a film, and why not.
@immutable
class StremfinCanRequest {
  const StremfinCanRequest({this.allowed = false, this.action, this.reason});

  final bool allowed;
  final StremfinRequestAction? action;

  /// Why not: `have` (it is there), `already` (they asked already), `busy`
  /// (it is downloading) or `unavailable` (it can't be had).
  final String? reason;

  static StremfinCanRequest fromJson(Object? raw) {
    if (raw is! Map) return const StremfinCanRequest();
    return StremfinCanRequest(
      allowed: raw['allowed'] == true,
      action: StremfinRequestAction.fromApi(raw['action']),
      reason: _text(raw['reason']),
    );
  }
}

/// When a film comes out to watch at home, if it hasn't yet.
@immutable
class StremfinRelease {
  const StremfinRelease({this.date, this.text});

  final DateTime? date;

  /// Ready to show: «Se estrena el 04/12/2026».
  final String? text;

  static StremfinRelease? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final date = _date(raw['date']);
    final text = _text(raw['text']);
    if (date == null && text == null) return null;
    return StremfinRelease(date: date, text: text);
  }
}

/// Where a download is.
enum StremfinPhase {
  queued,
  preparing,

  /// The download service is still getting the file ready.
  waitingFile,
  downloading,
  verifying,
  moving,

  /// It failed and the administrator has to choose.
  attention,

  /// Only of an episode: it is there.
  completed,
  unknown;

  static StremfinPhase? fromApi(Object? value) => switch (value) {
    null => null,
    'queued' => queued,
    'preparing' => preparing,
    'waiting_file' => waitingFile,
    'downloading' => downloading,
    'verifying' => verifying,
    'moving' => moving,
    'attention' => attention,
    'completed' => completed,
    _ => unknown,
  };
}

/// How far a download (of a film, a series or one episode) has got.
@immutable
class StremfinTransfer {
  const StremfinTransfer({
    this.phase,
    this.label,
    this.percent,
    this.downloadedBytes,
    this.totalBytes,
    this.speed,
    this.etaSeconds,
    this.waitingSince,
    this.paused = false,
  });

  /// Null while nothing is downloading yet.
  final StremfinPhase? phase;

  /// The service's own words for it, for a phase the app doesn't know.
  final String? label;

  /// 0 to 100; null before it starts coming down.
  final int? percent;
  final int? downloadedBytes;
  final int? totalBytes;

  /// Bytes a second while it comes down.
  final int? speed;
  final int? etaSeconds;

  /// Since when it waits for the file to be ready.
  final DateTime? waitingSince;

  /// The administrator paused every download.
  final bool paused;

  static StremfinTransfer fromJson(Map<Object?, Object?> raw) =>
      StremfinTransfer(
        phase: StremfinPhase.fromApi(raw['phase']),
        label: _text(raw['label']),
        percent: _int(raw['percent'])?.clamp(0, 100),
        downloadedBytes: _int(raw['downloaded_bytes']),
        totalBytes: _int(raw['total_bytes']),
        speed: _int(raw['speed']),
        etaSeconds: _int(raw['eta_seconds']),
        waitingSince: _date(raw['waiting_since']),
        paused: raw['paused'] == true,
      );
}

/// A film that is downloading, whoever asked for it.
@immutable
class StremfinMovieDownload {
  const StremfinMovieDownload({
    required this.attention,
    required this.transfer,
  });

  /// The administrator has to look at it.
  final bool attention;
  final StremfinTransfer transfer;

  static StremfinMovieDownload? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return StremfinMovieDownload(
      attention: raw['status'] == 'attention',
      transfer: StremfinTransfer.fromJson(raw),
    );
  }
}

/// A film's page.
@immutable
class StremfinMovieDetail {
  const StremfinMovieDetail({
    required this.title,
    this.runtime,
    this.genres = const [],
    this.download,
    this.release,
    this.canRequest = const StremfinCanRequest(),
  });

  /// What a list says of it, with the overview and the reliable answer of
  /// whether it is on the home server.
  final StremfinTitle title;

  /// Minutes.
  final int? runtime;
  final List<String> genres;
  final StremfinMovieDownload? download;

  /// When it comes out, if it hasn't: it can be asked for all the same.
  final StremfinRelease? release;
  final StremfinCanRequest canRequest;

  static StremfinMovieDetail? fromJson(Object? raw) {
    final title = StremfinTitle.fromJson(raw);
    if (title == null || raw is! Map) return null;
    return StremfinMovieDetail(
      title: title,
      runtime: _int(raw['runtime']),
      genres: _texts(raw['genres']),
      download: StremfinMovieDownload.fromJson(raw['download']),
      release: StremfinRelease.fromJson(raw['release']),
      canRequest: StremfinCanRequest.fromJson(raw['can_request']),
    );
  }
}

/// Whether a film can be downloaded now.
enum StremfinAvailabilityStatus {
  ready,

  /// Not yet: asking leaves it waiting, and it comes down on its own once a
  /// good version shows up.
  waitingVersion,
  downloading,
  have,
  unavailable,
  unknown;

  static StremfinAvailabilityStatus fromApi(Object? value) => switch (value) {
    'ready' => ready,
    'waiting_version' => waitingVersion,
    'downloading' => downloading,
    'have' => have,
    'unavailable' => unavailable,
    _ => unknown,
  };
}

/// Whether a film can be downloaded now, and how fast.
@immutable
class StremfinAvailability {
  const StremfinAvailability({
    required this.status,
    this.reason,
    this.fast = false,
    this.cached,
    this.summary,
    this.resolution,
    this.hdr,
    this.language,
    this.sizeBytes,
    this.release,
    this.criterion,
    this.needsApproval = false,
  });

  final StremfinAvailabilityStatus status;

  /// Of [StremfinAvailabilityStatus.waitingVersion]: `not_released`,
  /// `quality` (none in the home's language and quality) or `no_links`.
  final String? reason;

  /// Ready at once at the download service: it starts straight away.
  final bool fast;
  final bool? cached;

  /// The version it would bring, ready to show: «1080p · Castellano · 9,0 GB».
  final String? summary;

  /// Of that version: «1080p», its HDR («HDR10», «Dolby Vision»), its main
  /// language («Castellano») and its size.
  final String? resolution;
  final String? hdr;
  final String? language;
  final int? sizeBytes;
  final StremfinRelease? release;

  /// What counts as a good version at home: «en castellano de 1080p o más».
  final String? criterion;

  /// Asking for it goes to the administrator, who decides.
  final bool needsApproval;

  static StremfinAvailability fromJson(Object? raw) {
    if (raw is! Map) {
      return const StremfinAvailability(
        status: StremfinAvailabilityStatus.unknown,
      );
    }
    final version = raw['version'];
    final status = StremfinAvailabilityStatus.fromApi(raw['status']);
    final cached = raw['cached'];
    return StremfinAvailability(
      status: status,
      reason: _text(raw['reason']),
      fast: raw['fast'] == true && status == StremfinAvailabilityStatus.ready,
      cached: cached is bool ? cached : null,
      summary: version is Map ? _text(version['summary']) : null,
      resolution: version is Map ? _text(version['resolution']) : null,
      hdr: version is Map ? _text(version['hdr']) : null,
      language: version is Map ? _text(version['language']) : null,
      sizeBytes: version is Map ? _int(version['size']) : null,
      release: StremfinRelease.fromJson(raw['release']),
      criterion: _text(raw['criterion']),
      needsApproval: raw['on_request'] == 'review',
    );
  }
}

/// How a season stands on the home server.
enum StremfinSeasonStatus {
  /// Nothing of it has been on yet.
  upcoming,
  complete,

  /// What is missing is downloading or waiting for an answer.
  downloading,
  partial,
  missing,
  unknown;

  static StremfinSeasonStatus fromApi(Object? value) => switch (value) {
    'upcoming' => upcoming,
    'complete' => complete,
    'downloading' => downloading,
    'partial' => partial,
    'missing' => missing,
    _ => unknown,
  };
}

/// One season of a series' page.
@immutable
class StremfinSeason {
  const StremfinSeason({
    required this.number,
    this.aired = 0,
    this.have = 0,
    this.missing = 0,
    this.downloading = 0,
    this.status = StremfinSeasonStatus.unknown,
    this.request,
    this.canRequest = false,
  });

  final int number;

  /// Episodes already on, of those the ones there, those missing and those
  /// coming down.
  final int aired;
  final int have;
  final int missing;
  final int downloading;
  final StremfinSeasonStatus status;

  /// The request that covers it (its own or the one for all that's missing).
  final StremfinRequestRef? request;

  /// Whether to offer asking for it (or joining someone else's request).
  final bool canRequest;

  static StremfinSeason? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final number = _int(raw['season']);
    // Specials (season 0) can't be asked for.
    if (number == null || number < 1) return null;
    return StremfinSeason(
      number: number,
      aired: _int(raw['aired']) ?? 0,
      have: _int(raw['have']) ?? 0,
      missing: _int(raw['missing']) ?? 0,
      downloading: _int(raw['downloading']) ?? 0,
      status: StremfinSeasonStatus.fromApi(raw['status']),
      request: StremfinRequestRef.fromJson(raw['request']),
      canRequest: raw['can_request'] == true,
    );
  }
}

/// A series' page, season by season.
@immutable
class StremfinSeriesDetail {
  const StremfinSeriesDetail({
    required this.title,
    this.years,
    this.genres = const [],
    this.aired = 0,
    this.have = 0,
    this.missing = 0,
    this.missingRequestable = 0,
    this.canRequestAll = false,
    this.seasons = const [],
  });

  final StremfinTitle title;

  /// «2008–2013».
  final String? years;
  final List<String> genres;

  /// Episodes on so far, of those the ones there and those missing, and of
  /// those the ones that can be asked for.
  final int aired;
  final int have;
  final int missing;
  final int missingRequestable;

  /// Whether to offer asking for all that is missing.
  final bool canRequestAll;
  final List<StremfinSeason> seasons;

  static StremfinSeriesDetail? fromJson(Object? raw) {
    final title = StremfinTitle.fromJson(raw);
    if (title == null || raw is! Map) return null;
    final summary = raw['summary'];
    final s = summary is Map ? summary : const {};
    final seasons = raw['seasons'];
    return StremfinSeriesDetail(
      title: title,
      years: _text(raw['years']),
      genres: _texts(raw['genres']),
      aired: _int(s['aired']) ?? 0,
      have: _int(s['have']) ?? 0,
      missing: _int(s['missing']) ?? 0,
      missingRequestable: _int(s['missing_requestable']) ?? 0,
      canRequestAll: raw['can_request_all'] == true,
      seasons: [
        if (seasons is List)
          for (final season in seasons) ?StremfinSeason.fromJson(season),
      ]..sort((a, b) => a.number.compareTo(b.number)),
    );
  }
}

/// Where a request is.
enum StremfinRequestStatus {
  /// Waiting for the administrator's answer.
  pending,

  /// Accepted: [StremfinProgress] says how far it has got.
  approved,
  rejected,

  /// On the home server.
  completed,
  unknown;

  static StremfinRequestStatus fromApi(Object? value) => switch (value) {
    'pending' => pending,
    'approved' => approved,
    'rejected' => rejected,
    'completed' => completed,
    _ => unknown,
  };

  bool get isOpen => this == pending || this == approved;
}

/// Where an accepted request is.
enum StremfinProgressState {
  /// Accepted, nothing downloading yet.
  accepted,

  /// A series: looking for its episodes.
  preparing,

  /// A film: no version in the home's language and quality yet (or it
  /// hasn't come out). It comes down as soon as there is one.
  waitingVersion,
  downloading,

  /// The download needs the administrator to choose another version.
  attention,
  unknown;

  static StremfinProgressState fromApi(Object? value) => switch (value) {
    'accepted' => accepted,
    'preparing' => preparing,
    'waiting_version' => waitingVersion,
    'downloading' => downloading,
    'attention' => attention,
    _ => unknown,
  };
}

/// How far an accepted request has got.
@immutable
class StremfinProgress {
  const StremfinProgress({
    required this.state,
    this.label,
    this.transfer = const StremfinTransfer(),
    this.episodesDone,
    this.episodesTotal,
    this.episodesAttention,
  });

  final StremfinProgressState state;

  /// The service's own words for it.
  final String? label;

  /// The download: of a series, all its episodes together.
  final StremfinTransfer transfer;

  /// Of a series: episodes there, in all and that the administrator has to
  /// look at.
  final int? episodesDone;
  final int? episodesTotal;
  final int? episodesAttention;

  static StremfinProgress? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return StremfinProgress(
      state: StremfinProgressState.fromApi(raw['state']),
      label: _text(raw['label']),
      transfer: StremfinTransfer.fromJson(raw),
      episodesDone: _int(raw['episodes_done']),
      episodesTotal: _int(raw['episodes_total']),
      episodesAttention: _int(raw['episodes_attention']),
    );
  }
}

/// A request, all of it.
@immutable
class StremfinRequest {
  const StremfinRequest({
    required this.id,
    required this.status,
    this.type,
    this.tmdbId,
    this.title,
    this.displayTitle,
    this.season,
    this.wholeSeries = false,
    this.statusLabel,
    this.reason,
    this.reasonLabel,
    this.direct = false,
    this.mine = false,
    this.requesters = const [],
    this.canWithdraw = false,
    this.progress,
    this.updatedAt,
    this.poster,
    this.year,
    this.requestedAt,
    this.decidedAt,
    this.completedAt,
  });

  final int id;
  final StremfinRequestStatus status;
  final StremfinTitleType? type;
  final int? tmdbId;
  final String? title;

  /// Ready to show: «Dune (2021)», «Severance · Temporada 2».
  final String? displayTitle;

  /// Of a series: the season asked for, or [wholeSeries] for all that's
  /// missing.
  final int? season;
  final bool wholeSeries;
  final String? statusLabel;

  /// Why it was turned down: `quality` (no good version yet) or `later`.
  final String? reason;
  final String? reasonLabel;
  final bool direct;
  final bool mine;
  final List<String> requesters;

  /// It is theirs and still waits for an answer.
  final bool canWithdraw;

  /// Only while accepted.
  final StremfinProgress? progress;
  final DateTime? updatedAt;

  /// Its cover, and the title's year.
  final String? poster;
  final int? year;
  final DateTime? requestedAt;
  final DateTime? decidedAt;
  final DateTime? completedAt;

  static StremfinRequest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['id']);
    if (id == null) return null;
    final status = StremfinRequestStatus.fromApi(raw['status']);
    return StremfinRequest(
      id: id,
      status: status,
      type: StremfinTitleType.fromApi(raw['type']),
      tmdbId: _int(raw['tmdb_id']),
      title: _text(raw['title']),
      displayTitle: _text(raw['display_title']),
      season: _int(raw['season']),
      wholeSeries: raw['whole_series'] == true,
      statusLabel: _text(raw['status_label']),
      reason: _text(raw['reason']),
      reasonLabel: _text(raw['reason_label']),
      direct: raw['direct'] == true,
      mine: raw['mine'] == true,
      requesters: _texts(raw['requesters']),
      canWithdraw: raw['can_withdraw'] == true,
      progress: status == StremfinRequestStatus.approved
          ? StremfinProgress.fromJson(raw['progress'])
          : null,
      updatedAt: _date(raw['updated_at']),
      poster: _https(raw['poster']),
      year: _int(raw['year']),
      requestedAt: _date(raw['requested_at']),
      decidedAt: _date(raw['decided_at']),
      completedAt: _date(raw['completed_at']),
    );
  }

  /// When it last changed, as far as is known: for putting the latest first.
  DateTime? get lastChange =>
      updatedAt ?? completedAt ?? decidedAt ?? requestedAt;

  /// The short form a title carries, for the lists to show it.
  StremfinRequestRef? get asRef => status.isOpen
      ? StremfinRequestRef(
          id: id,
          status: status == StremfinRequestStatus.pending
              ? 'pending'
              : 'approved',
          statusLabel: statusLabel,
          mine: mine,
          season: season,
          direct: direct,
          requesters: requesters,
        )
      : null;
}

/// What asking for something did.
enum StremfinOutcome {
  /// New, waiting for the administrator's answer.
  created,

  /// Accepted on its own and under way.
  started,

  /// Someone had asked for it: the person is added to that request.
  joined,

  /// A film already downloading: the person is told when it arrives.
  watching,

  /// A season, while all that's missing was asked for already.
  included,

  /// They had asked for it already.
  already,

  /// It is on the home server.
  have,

  /// It is downloading already.
  busy,
  unavailable,

  /// They reached their limit (see [StremfinRequestResult.limit]).
  limit,
  unknown;

  static StremfinOutcome fromApi(Object? value) => switch (value) {
    'created' => created,
    'started' => started,
    'joined' => joined,
    'watching' => watching,
    'included' => included,
    'already' => already,
    'have' => have,
    'busy' => busy,
    'unavailable' => unavailable,
    'limit' => limit,
    _ => unknown,
  };
}

/// The answer to asking for something.
@immutable
class StremfinRequestResult {
  const StremfinRequestResult({
    required this.outcome,
    this.message,
    this.request,
    this.limit,
    this.retryAfter,
  });

  final StremfinOutcome outcome;

  /// The service's words, for an outcome the app doesn't know.
  final String? message;

  /// The request it belongs to now, when there is one.
  final StremfinRequest? request;

  /// Which limit: `pending` (too many waiting for an answer) or `daily`.
  final String? limit;

  /// Of the daily limit: when it frees up.
  final Duration? retryAfter;

  static StremfinRequestResult fromJson(Object? raw, {Duration? retryAfter}) {
    final body = raw is Map ? raw : const {};
    return StremfinRequestResult(
      outcome: StremfinOutcome.fromApi(body['outcome']),
      message: _text(body['message']),
      request: StremfinRequest.fromJson(body['request']),
      limit: _text(body['limit']),
      retryAfter: retryAfter,
    );
  }
}

/// One page of the person's requests, and what changed.
@immutable
class StremfinRequestPage {
  const StremfinRequestPage({
    this.now,
    this.items = const [],
    this.removedIds = const [],
  });

  /// The service's own clock: given back as `since` next time, to hear only
  /// what changed meanwhile.
  final String? now;
  final List<StremfinRequest> items;

  /// Requests gone since then (taken back, joined with another).
  final List<int> removedIds;

  static StremfinRequestPage fromJson(Object? raw) {
    if (raw is! Map) return const StremfinRequestPage();
    final items = raw['items'];
    final removed = raw['removed_ids'];
    return StremfinRequestPage(
      now: _text(raw['now']),
      items: [
        if (items is List)
          for (final item in items) ?StremfinRequest.fromJson(item),
      ],
      removedIds: [
        if (removed is List)
          for (final id in removed) ?_int(id),
      ],
    );
  }
}
