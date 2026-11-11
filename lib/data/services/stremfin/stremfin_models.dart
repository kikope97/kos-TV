import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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
  });

  final int id;
  final String status;
  final String? statusLabel;
  final bool mine;

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

  /// Shown in colour: it is on the home server.
  bool get isInLibrary => library.inLibrary;

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
  const StremfinMe({required this.role, required this.canRequest});

  /// `admin`, `member` or `none`.
  final String role;
  final bool canRequest;

  /// Whether they may see the platform lists.
  bool get canDiscover => role == 'admin' || canRequest;

  static StremfinMe fromJson(Object? raw) {
    if (raw is! Map) return const StremfinMe(role: 'none', canRequest: false);
    final user = raw['user'];
    final access = raw['access'];
    final role = user is Map && user['role'] is String
        ? user['role'] as String
        : 'none';
    return StremfinMe(
      role: role,
      canRequest: access is Map && access['can_request'] == true,
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

/// Images load straight from TMDB or JustWatch, always over https.
String? _https(Object? raw) =>
    raw is String && raw.startsWith('https://') ? raw : null;
