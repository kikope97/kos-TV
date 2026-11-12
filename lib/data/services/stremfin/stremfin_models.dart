import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

part 'stremfin_request_models.dart';

/// Kos TV: what the requests service (Stremfin) answers, as far as Discover
/// uses it. Unknown fields are ignored, as its API asks.

/// Whether a title is a film or a series.
enum StremfinTitleType {
  movie('movie'),
  series('series');

  const StremfinTitleType(this.apiValue);
  final String apiValue;

  static StremfinTitleType? fromApi(Object? value) => switch (value) {
    'movie' => movie,
    'series' => series,
    _ => null,
  };
}

/// Which list of a platform: the most watched or what has just come out.
enum StremfinTopList {
  popular('popular'),
  fresh('new');

  const StremfinTopList(this.apiValue);
  final String apiValue;
}

/// What the home server has of a title.
enum StremfinLibraryStatus {
  available,

  /// A series that is there, missing the season the card announces.
  partial,
  downloading,
  missing;

  static StremfinLibraryStatus fromApi(Object? value) => switch (value) {
    'available' => available,
    'partial' => partial,
    'downloading' => downloading,
    _ => missing,
  };
}

@immutable
class StremfinLibrary {
  const StremfinLibrary({
    this.status = StremfinLibraryStatus.missing,
    this.inLibrary = false,
    this.itemId,
    this.downloading = false,
    this.season,
    this.seasonEpisodesHave,
    this.seasonEpisodes,
  });

  final StremfinLibraryStatus status;

  /// It can be watched now (even when [itemId] is not known yet, for a
  /// minute or two after it arrives).
  final bool inLibrary;

  /// The item's id on the home server, to open its page.
  final String? itemId;
  final bool downloading;
  final int? season;
  final int? seasonEpisodesHave;
  final int? seasonEpisodes;

  static StremfinLibrary fromJson(Object? raw) {
    if (raw is! Map) return const StremfinLibrary();
    final id = raw['jellyfin_id'];
    return StremfinLibrary(
      status: StremfinLibraryStatus.fromApi(raw['status']),
      inLibrary: raw['in_jellyfin'] == true,
      itemId: id is String && id.isNotEmpty ? id : null,
      downloading: raw['downloading'] == true,
      season: _int(raw['season']),
      seasonEpisodesHave: _int(raw['season_episodes_have']),
      seasonEpisodes: _int(raw['season_episodes']),
    );
  }
}

/// The open request for a title, if someone has asked for it.
@immutable
class StremfinRequestRef {
  const StremfinRequestRef({
    required this.id,
    required this.status,
    this.statusLabel,
    this.mine = false,
    this.season,
    this.episode,
    this.direct = false,
    this.requesters = const [],
  });

  final int id;

  /// `pending` or `approved` (a title only carries open ones).
  final String status;
  final String? statusLabel;
  final bool mine;

  /// On a series: the season asked for, or null for all that is missing.
  final int? season;

  /// Kos TV: one episode of [season] asked for on its own, or null for the
  /// whole season.
  final int? episode;

  /// It was accepted on its own.
  final bool direct;

  /// Who asked for it.
  final List<String> requesters;

  bool get isPending => status == 'pending';

  static StremfinRequestRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _int(raw['id']);
    final status = raw['status'];
    if (id == null || status is! String) return null;
    final label = raw['status_label'];
    return StremfinRequestRef(
      id: id,
      status: status,
      statusLabel: label is String ? label : null,
      mine: raw['mine'] == true,
      season: _int(raw['season']),
      episode: _int(raw['episode']),
      direct: raw['direct'] == true,
      requesters: _texts(raw['requesters']),
    );
  }
}

/// One page of a search: films and series in TMDB's order of relevance.
@immutable
class StremfinSearchPage {
  const StremfinSearchPage({this.items = const [], this.nextCursor});

  final List<StremfinTitle> items;

  /// What to give back to read on, or null when there is no more. A page
  /// can come back short, or empty, and still have more after it.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  static StremfinSearchPage fromJson(Object? raw) {
    if (raw is! Map) return const StremfinSearchPage();
    final items = raw['items'];
    return StremfinSearchPage(
      items: [
        if (items is List)
          for (final item in items) ?StremfinTitle.fromJson(item),
      ],
      nextCursor: _text(raw['next_cursor']),
    );
  }
}

/// A film or series on one of the lists.
@immutable
class StremfinTitle {
  const StremfinTitle({
    required this.type,
    required this.tmdbId,
    required this.title,
    this.year,
    this.poster,
    this.backdrop,
    this.rating,
    this.rank,
    this.season,
    this.platform,
    this.library = const StremfinLibrary(),
    this.request,
    this.overview,
    this.originalTitle,
    this.age,
    this.ageLabel,
  });

  final StremfinTitleType type;
  final int tmdbId;
  final String title;
  final int? year;
  final String? poster;
  final String? backdrop;
  final double? rating;

  /// The place on a most-watched list (1 is the first).
  final int? rank;

  /// On a series that has just come out: the season it is about (1 is a new
  /// series).
  final int? season;

  /// On the "new" list of every platform together: which one it comes from.
  final String? platform;
  final StremfinLibrary library;
  final StremfinRequestRef? request;

  /// What it is about (the lists leave it out: it comes with its page).
  final String? overview;
  final String? originalTitle;

  /// Kos TV: the minimum age it is for, in years (0 is for everyone), or
  /// null when its rating isn't known (or the service is older than 1.81,
  /// which only gave it in places).
  final int? age;

  /// Its rating as given (`12`, `PG-13`…), for the app's own parental
  /// control.
  final String? ageLabel;

  /// Shown in colour: it is on the home server.
  bool get isInLibrary => library.inLibrary;

  /// The same title as it stands now on the home server and in the
  /// requests, keeping what its list said of it (place, season, platform).
  StremfinTitle copyWith({
    StremfinLibrary? library,
    StremfinRequestRef? Function()? request,
  }) => StremfinTitle(
    type: type,
    tmdbId: tmdbId,
    title: title,
    year: year,
    poster: poster,
    backdrop: backdrop,
    rating: rating,
    rank: rank,
    season: season,
    platform: platform,
    library: library ?? this.library,
    request: request == null ? this.request : request(),
    overview: overview,
    originalTitle: originalTitle,
    age: age,
    ageLabel: ageLabel,
  );

  static StremfinTitle? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = StremfinTitleType.fromApi(raw['type']);
    final tmdbId = _int(raw['tmdb_id']);
    final title = raw['title'];
    if (type == null || tmdbId == null || title is! String || title.isEmpty) {
      return null;
    }
    return StremfinTitle(
      type: type,
      tmdbId: tmdbId,
      title: title,
      year: _int(raw['year']),
      poster: _https(raw['poster']),
      backdrop: _https(raw['backdrop']),
      rating: _double(raw['rating']),
      rank: _int(raw['rank']),
      season: _int(raw['season']),
      platform: raw['platform'] is String ? raw['platform'] as String : null,
      library: StremfinLibrary.fromJson(raw['library']),
      request: StremfinRequestRef.fromJson(raw['request']),
      overview: _text(raw['overview']),
      originalTitle: _text(raw['original_title']),
      age: _int(raw['age']),
      ageLabel: raw['age_rating'] is Map
          ? _text((raw['age_rating'] as Map)['label'])
          : null,
    );
  }
}

/// A streaming platform with lists (or "all" of them together).
@immutable
class StremfinPlatform {
  const StremfinPlatform({required this.id, required this.name, this.color});

  /// `all`, `netflix`, `disney` or `prime`.
  final String id;
  final String name;

  /// Its brand colour.
  final Color? color;

  bool get isAll => id == allId;

  static const allId = 'all';

  /// What the app shows if the list of platforms can't be read.
  static const defaults = [
    StremfinPlatform(id: allId, name: ''),
    StremfinPlatform(id: 'netflix', name: 'Netflix', color: Color(0xFFE50914)),
    StremfinPlatform(id: 'disney', name: 'Disney+', color: Color(0xFF113CCF)),
    StremfinPlatform(
      id: 'prime',
      name: 'Prime Video',
      color: Color(0xFF00A8E1),
    ),
  ];

  static StremfinPlatform? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty) return null;
    return StremfinPlatform(
      id: id,
      name: name is String ? name : id,
      color: parseColor(raw['color']),
    );
  }

  /// `#e50914` → a colour; anything else → null.
  @visibleForTesting
  static Color? parseColor(Object? raw) {
    if (raw is! String) return null;
    final hex = raw.startsWith('#') ? raw.substring(1) : raw;
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }
}

/// Who the signed-in person is to the requests service.
@immutable
class StremfinMe {
  const StremfinMe({
    required this.role,
    required this.canRequest,
    this.name,
    this.mode,
    this.limit,
    this.pending,
    this.dailyLeft,
    this.atLimit = false,
  });

  /// `admin`, `member` or `none`.
  final String role;
  final bool canRequest;

  /// The name the service knows them by.
  final String? name;

  /// What asking does: `admin` and `direct` start it at once, `review`
  /// waits for the administrator.
  final String? mode;

  /// How many of theirs may wait for an answer at once (0: no limit), and
  /// how many do.
  final int? limit;
  final int? pending;

  /// New requests left in the last 24 hours (null: no limit).
  final int? dailyLeft;

  /// They can't ask for more right now.
  final bool atLimit;

  /// What they ask for waits for the administrator's answer.
  bool get needsApproval => mode == 'review';

  /// Whether they may see the platform lists.
  bool get canDiscover => role == 'admin' || canRequest;

  static StremfinMe fromJson(Object? raw) {
    if (raw is! Map) return const StremfinMe(role: 'none', canRequest: false);
    final user = raw['user'];
    final access = raw['access'];
    final role = user is Map && user['role'] is String
        ? user['role'] as String
        : 'none';
    final a = access is Map ? access : const {};
    return StremfinMe(
      role: role,
      canRequest: a['can_request'] == true,
      name: user is Map ? _text(user['name']) : null,
      mode: _text(a['mode']),
      limit: _int(a['limit']),
      pending: _int(a['pending']),
      dailyLeft: _int(a['daily_left']),
      atLimit: a['at_limit'] == true,
    );
  }
}

int? _int(Object? raw) => switch (raw) {
  final int value => value,
  final num value => value.toInt(),
  final String value => int.tryParse(value),
  _ => null,
};

double? _double(Object? raw) => raw is num ? raw.toDouble() : null;

String? _text(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

List<String> _texts(Object? raw) => [
  if (raw is List)
    for (final entry in raw)
      if (entry is String && entry.isNotEmpty) entry,
];

DateTime? _date(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;

/// Images load straight from TMDB or JustWatch, always over https.
String? _https(Object? raw) =>
    raw is String && raw.startsWith('https://') ? raw : null;
