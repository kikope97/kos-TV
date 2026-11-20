import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../models/aggregated_item.dart';
import 'moonbase_endpoint.dart';
import 'stremfin/stremfin_models.dart';

/// Kos TV: where the music the person is about to hear comes from, as the
/// server plugin notes it with what they listen to (`POST Music/Context`).
abstract final class KostvMusicSource {
  static const discovery = 'discovery';
  static const search = 'search';
  static const album = 'album';
  static const artist = 'artist';
  static const favorites = 'favorites';
  static const playlist = 'playlist';
  static const charts = 'charts';
  static const radio = 'radio';
  static const other = 'other';

  /// One of the person's daily mixes, by its id (`daily-2`).
  static String mix(String id) => 'mix:$id';

  /// The mix of the time of day, by its slot (`manana`, `tarde`, `noche`).
  static String moment(String slot) => 'moment:$slot';
}

/// Kos TV: what one of the plugin's routes gave: its [value] or, without
/// one, why not. [missing]: the plugin doesn't have the route (a 404,
/// remembered for a while): the page shows what it showed before it.
/// Otherwise it [failed] (no network, a 401 or 5xx, too slow, an answer
/// that isn't one): what is shown stays, and it is asked again next time.
@immutable
class KostvMusicAnswer<T extends Object> {
  const KostvMusicAnswer(T this.value) : missing = false;
  const KostvMusicAnswer.missing() : value = null, missing = true;
  const KostvMusicAnswer.failed() : value = null, missing = false;

  final T? value;
  final bool missing;

  bool get failed => value == null && !missing;
}

/// Kos TV: whether the plugin keeps what the person listens to, and how
/// much it has kept since when.
@immutable
class KostvMusicLearnState {
  const KostvMusicLearnState({
    required this.learn,
    this.listens = 0,
    this.since,
  });

  final bool learn;
  final int listens;

  /// The first listen kept, or null with none.
  final DateTime? since;

  static KostvMusicLearnState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final learn = raw['Learn'];
    if (learn is! bool) return null;
    final listens = raw['Listens'];
    final since = raw['Since'];
    return KostvMusicLearnState(
      learn: learn,
      listens: listens is num ? listens.toInt() : 0,
      since: since is String ? DateTime.tryParse(since)?.toLocal() : null,
    );
  }
}

/// Kos TV: one of the person's daily mixes, as the plugin made it today.
@immutable
class KostvDailyMix {
  const KostvDailyMix({
    required this.id,
    required this.items,
    this.genre,
    this.artists = const [],
  });

  final String id;
  final String? genre;

  /// Its artists, for its cover (the first three).
  final List<AggregatedItem> artists;

  /// Its songs, in the order they play.
  final List<AggregatedItem> items;
}

/// Kos TV: the person's daily mixes for [day].
@immutable
class KostvDailyMixes {
  const KostvDailyMixes({this.day, this.mixes = const []});

  final String? day;
  final List<KostvDailyMix> mixes;

  bool get isEmpty => mixes.isEmpty;

  static KostvDailyMixes? fromJson(Object? raw, String serverId) {
    if (raw is! Map) return null;
    final list = raw['Mixes'];
    if (list is! List) return null;
    return KostvDailyMixes(
      day: raw['Day']?.toString(),
      mixes: [
        for (final mix in list.whereType<Map>())
          if (mix['Id'] != null)
            KostvDailyMix(
              id: mix['Id'].toString(),
              genre: _text(mix['Genre']),
              artists: kostvMusicCards(mix['Artists'], serverId),
              items: kostvMusicCards(mix['Items'], serverId),
            ),
      ].where((mix) => mix.items.isNotEmpty).toList(),
    );
  }

  /// To keep on the device ([fromJson] reads it back), each card with only
  /// what the Music page uses of it.
  Map<String, Object?> toJson() => {
    'Day': day,
    'Mixes': [
      for (final mix in mixes)
        {
          'Id': mix.id,
          'Genre': mix.genre,
          'Artists': [for (final a in mix.artists.take(3)) _slim(a)],
          'Items': [for (final i in mix.items) _slim(i)],
        },
    ],
  };
}

/// Kos TV: what the plugin says of the person's weekly discovery: the
/// artists to ask the requests service with and, once one of the person's
/// devices picked them, the songs of the week.
@immutable
class KostvMusicDiscovery {
  const KostvMusicDiscovery({this.week, this.seeds = const [], this.songs});

  /// `2026-W47`.
  final String? week;
  final List<String> seeds;

  /// Null until the week's are picked.
  final List<StremfinSong>? songs;

  static KostvMusicDiscovery? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final seeds = raw['Seeds'];
    final songs = raw['Songs'];
    return KostvMusicDiscovery(
      week: _text(raw['Week']),
      seeds: [
        if (seeds is List)
          for (final seed in seeds) ?_text(seed),
      ],
      songs: songs is List
          ? [for (final song in songs) ?StremfinSong.fromJson(song)]
          : null,
    );
  }
}

/// Kos TV: the mix of the time of day, once the plugin knows enough of what
/// the person listens to then.
@immutable
class KostvMusicMoment {
  const KostvMusicMoment({
    required this.slot,
    required this.ready,
    this.items = const [],
  });

  /// `manana`, `tarde` or `noche`.
  final String slot;
  final bool ready;
  final List<AggregatedItem> items;

  /// Whether it is shown: ready, with songs.
  bool get shows => ready && items.isNotEmpty;

  static KostvMusicMoment? fromJson(Object? raw, String serverId) {
    if (raw is! Map) return null;
    final slot = _text(raw['Slot']);
    if (slot == null) return null;
    return KostvMusicMoment(
      slot: slot,
      ready: raw['Ready'] == true,
      items: kostvMusicCards(raw['Items'], serverId),
    );
  }

  Map<String, Object?> toJson() => {
    'Slot': slot,
    'Ready': ready,
    'Items': [for (final i in items) _slim(i)],
  };
}

/// Kos TV: which of the Music page's rows from the plugin show. Each only
/// when the plugin answered with something in it: otherwise the page keeps
/// the row it had before them («Tus mezclas» for the daily mixes,
/// «Canciones para ti» for the discovery) and the moment's isn't there.
({bool dailyMixes, bool discovery, bool moment}) kostvMusicPluginRows({
  KostvDailyMixes? mixes,
  List<StremfinSong>? discovery,
  KostvMusicMoment? moment,
}) => (
  dailyMixes: mixes != null && !mixes.isEmpty,
  discovery: discovery != null && discovery.isNotEmpty,
  moment: moment?.shows ?? false,
);

/// Kos TV: the slot of the day [at] falls in, as the plugin counts them:
/// `manana` 6–12, `tarde` 12–20, `noche` 20–6.
String kostvMusicSlotAt(DateTime at) {
  final hour = at.hour;
  if (hour >= 6 && hour < 12) return 'manana';
  if (hour >= 12 && hour < 20) return 'tarde';
  return 'noche';
}

/// Kos TV: the day of the daily mixes [at] falls in (`2026-11-20`): as the
/// plugin counts it, a day starts at 5:00 (by the house's clock there; by
/// the device's here, which is near enough).
String kostvMusicDayAt(DateTime at) {
  final day = at.subtract(const Duration(hours: 5));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

/// Kos TV: the daily mixes kept on the device ([KostvDailyMixes.toJson]),
/// unless they are another day's.
KostvDailyMixes? kostvKeptMixes(
  Object? raw,
  String serverId, {
  required DateTime now,
}) {
  final mixes = KostvDailyMixes.fromJson(raw, serverId);
  if (mixes == null) return null;
  final day = mixes.day;
  if (day != null && day != kostvMusicDayAt(now)) return null;
  return mixes;
}

/// Kos TV: the week's discovery as kept on the device: the week it is of
/// and its songs ([kostvKeptDiscovery] reads it back).
Map<String, Object?> kostvDiscoveryNote(
  String week,
  List<StremfinSong> songs,
) => {
  'Week': week,
  'Songs': [for (final song in songs) kostvStremfinSongJson(song)],
};

/// Kos TV: the week's discovery kept on the device, only when it is this
/// week's (a list from before the week was kept with it isn't shown).
List<StremfinSong>? kostvKeptDiscovery(Object? raw, {required DateTime now}) {
  if (raw is! Map || raw['Week'] != kostvIsoWeek(now)) return null;
  final songs = raw['Songs'];
  if (songs is! List) return null;
  return [for (final song in songs) ?StremfinSong.fromJson(song)];
}

/// Kos TV: the ISO week of [at] (`2026-W47`), for when the plugin doesn't
/// say it.
String kostvIsoWeek(DateTime at) {
  final date = DateTime.utc(at.year, at.month, at.day);
  final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
  final first = DateTime.utc(thursday.year);
  final week = thursday.difference(first).inDays ~/ 7 + 1;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

/// Kos TV: the week's songs of discovery out of [songs]: up to [count],
/// always the same for the same [user] and [week] (on the TV, the phone and
/// the web alike), each song once, and only songs the house doesn't have
/// yet (the plan's «que no tienes»).
List<StremfinSong> kostvWeeklyPick(
  List<StremfinSong> songs, {
  required String user,
  required String week,
  int count = 20,
}) {
  String keyOf(StremfinSong song) =>
      song.deezerId ??
      '${song.title.toLowerCase()}|${(song.artist ?? '').toLowerCase()}';
  final unique = <String, StremfinSong>{};
  for (final song in songs) {
    if (song.inJellyfin || song.jellyfinId != null) continue;
    unique.putIfAbsent(keyOf(song), () => song);
  }
  final ranked =
      [
        for (final entry in unique.entries)
          (
            key: entry.key,
            rank: kostvStableHash('$user|$week|${entry.key}'),
            song: entry.value,
          ),
      ]..sort((a, b) {
        final byRank = a.rank.compareTo(b.rank);
        return byRank != 0 ? byRank : a.key.compareTo(b.key);
      });
  return [for (final entry in ranked.take(count)) entry.song];
}

/// Kos TV: FNV-1a of [text], the same on every platform (the web's numbers
/// included, where `String.hashCode` differs).
int kostvStableHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    // × 16777619 as 2^24 + 403, so it stays exact as a web number.
    hash = (((hash << 24) & 0xffffffff) + hash * 403) & 0xffffffff;
  }
  return hash;
}

/// Kos TV: [songs] each with its whole album out of [albums] (a
/// recommendation's songs only say where they sit; its albums say whether
/// they can be asked for, are asked for or on their way), as a chart's.
List<StremfinSong> kostvSongsWithAlbums(
  List<StremfinSong> songs,
  List<StremfinAlbum> albums,
) {
  final byId = <String, StremfinAlbum>{
    for (final album in albums) ?album.deezerId: album,
  };
  return [
    for (final song in songs)
      song.album != null || byId[song.albumDeezerId] == null
          ? song
          : StremfinSong(
              title: song.title,
              deezerId: song.deezerId,
              artist: song.artist,
              artistDeezerId: song.artistDeezerId,
              duration: song.duration,
              preview: song.preview,
              explicit: song.explicit,
              cover: song.cover,
              albumTitle: song.albumTitle,
              albumDeezerId: song.albumDeezerId,
              album: byId[song.albumDeezerId],
              inJellyfin: song.inJellyfin,
              rank: song.rank,
              jellyfinId: song.jellyfinId,
              albumJellyfinId: song.albumJellyfinId,
              reason: song.reason,
            ),
  ];
}

/// Kos TV: [song] as the requests service writes it, for the week's list
/// kept in the plugin ([StremfinSong.fromJson] reads it back). With its
/// whole album, what [StremfinAlbum.fromJson] needs for its mark too.
Map<String, Object?> kostvStremfinSongJson(StremfinSong song) => {
  'title': song.title,
  'deezer_id': ?song.deezerId,
  'artist': ?song.artist,
  'artist_deezer_id': ?song.artistDeezerId,
  'duration': ?song.duration,
  'preview': ?song.preview,
  'explicit': song.explicit,
  'cover': ?song.cover,
  if (song.album case final album?)
    'album': _albumJson(album, song.cover)
  else if (song.albumTitle != null || song.albumDeezerId != null)
    'album': {
      'title': ?song.albumTitle,
      'deezer_id': ?song.albumDeezerId,
      'cover': ?song.cover,
    },
  'in_jellyfin': song.inJellyfin,
  'jellyfin_id': ?song.jellyfinId,
  'album_jellyfin_id': ?song.albumJellyfinId,
  'reason': ?song.reason,
};

Map<String, Object?> _albumJson(StremfinAlbum album, String? cover) {
  final request = album.request;
  final download = album.download;
  return {
    'title': album.title,
    'deezer_id': ?album.deezerId,
    'artist': ?album.artist,
    'cover': ?(album.cover ?? cover),
    'library': {
      'in_jellyfin': album.inJellyfin,
      'jellyfin_id': ?album.jellyfinId,
      'song_in_album': ?album.songInAlbum,
    },
    if (request != null)
      'request': {
        'id': request.id,
        'status': request.status,
        'status_label': ?request.statusLabel,
        'mine': request.mine,
      },
    if (download != null)
      'download': {
        'phase': ?download.phase,
        'label': ?download.label,
        'percent': ?download.percent,
      },
    'can_request': album.canRequest,
  };
}

/// Kos TV: the plugin's cards ([ItemCardDtoMapper]'s, as Home's) as the
/// app's items, ids without dashes as the server's own lists write them.
List<AggregatedItem> kostvMusicCards(Object? raw, String serverId) => [
  if (raw is List)
    for (final card in raw.whereType<Map>())
      if (card['Id'] != null)
        () {
          final data = card.cast<String, dynamic>();
          final id = data['Id'].toString().replaceAll('-', '');
          final album = data['AlbumId']?.toString().replaceAll('-', '');
          return AggregatedItem(
            id: id,
            serverId: serverId,
            rawData: {...data, 'Id': id, 'AlbumId': ?album},
          );
        }(),
];

/// What the Music page reads of a card: kept on the device without the rest.
const _cardFields = {
  'Id',
  'Name',
  'Type',
  'MediaType',
  'ServerId',
  'ImageTags',
  'AlbumId',
  'Album',
  'AlbumPrimaryImageTag',
  'AlbumArtist',
  'Artists',
  'RunTimeTicks',
  'IndexNumber',
  'ParentIndexNumber',
  'Genres',
  'ProductionYear',
  'UserData',
};

Map<String, Object?> _slim(AggregatedItem item) => {
  for (final entry in item.rawData.entries)
    if (_cardFields.contains(entry.key)) entry.key: entry.value,
};

String? _text(Object? raw) {
  final text = raw?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// Kos TV: the server plugin's routes for what the Music page learns from
/// what each person listens to (`/Moonfin/Kostv/Music/...`): whether it
/// keeps it, where what is about to play comes from, the daily mixes, the
/// weekly discovery and the mix of the time of day.
///
/// A plugin from before them answers 404: that route is then left alone
/// for [_retryAfter], and the page shows what it showed before them.
class KostvMusicPlugin {
  KostvMusicPlugin({Dio? dio})
    : _dio =
          dio ??
          moonbaseDio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              // The first mixes of the day are worked out when asked for.
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  /// The one the app asks through; a test puts its own in.
  static KostvMusicPlugin instance = KostvMusicPlugin();

  /// How long a route the plugin lacks is left alone. Short enough that
  /// updating the plugin shows without restarting the app.
  static const _retryAfter = Duration(minutes: 30);

  /// What is about to play: as many songs as the plugin is told of (its
  /// own limit).
  static const contextMax = 500;

  final Dio _dio;
  final Map<String, DateTime> _missingAt = {};

  static const _base = '/Moonfin/Kostv/Music';

  /// Whether [client]'s plugin was last seen without [route].
  bool knownMissing(MediaServerClient client, String route) {
    final at = _missingAt['${client.baseUrl}|$route'];
    return at != null && DateTime.now().difference(at) < _retryAfter;
  }

  /// Forgets which routes were missing. Only for tests: what is missing is
  /// the server's plugin, the same whoever uses it, so a switch of person
  /// keeps it.
  @visibleForTesting
  void reset() => _missingAt.clear();

  /// The answer of [route]: its body, or why there is none ([missing]: the
  /// plugin lacks it, a 404 kept for a while; otherwise it failed). A status
  /// in [answers] is an answer too (409 of a week that is over), with its
  /// body.
  Future<({bool ok, bool missing, Object? data, int? status})> _call(
    MediaServerClient client,
    String method,
    String route, {
    Object? body,
    Set<int> answers = const {},
  }) async {
    const failed = (ok: false, missing: false, data: null, status: null);
    const missing = (ok: false, missing: true, data: null, status: null);
    if (knownMissing(client, route)) return missing;
    // A server without the plugin's kind of routes at all.
    if (!client.features.supportsMoonfinPlugin) return missing;
    try {
      final ep = await moonbaseEndpoint(client, _dio);
      if (ep == null) return failed;
      final response = await _dio.request<dynamic>(
        '${ep.base}$_base/$route',
        data: body,
        options: Options(
          method: method,
          headers: ep.headers,
          validateStatus: (status) =>
              status != null &&
              (status >= 200 && status < 300 || answers.contains(status)),
        ),
      );
      return (
        ok: true,
        missing: false,
        data: response.data,
        status: response.statusCode,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _missingAt['${client.baseUrl}|$route'] = DateTime.now();
        return missing;
      }
      debugPrint('[MusicPlugin] $method $route failed: ${e.message}');
      return failed;
    } catch (e) {
      debugPrint('[MusicPlugin] $method $route failed: $e');
      return failed;
    }
  }

  /// [route]'s answer read by [read]; an answer it can't read is a failure.
  Future<KostvMusicAnswer<T>> _read<T extends Object>(
    MediaServerClient client,
    String route,
    T? Function(Object? data) read,
  ) async {
    final reply = await _call(client, 'GET', route);
    if (reply.missing) return const KostvMusicAnswer.missing();
    final value = reply.ok ? read(reply.data) : null;
    return value == null
        ? const KostvMusicAnswer.failed()
        : KostvMusicAnswer(value);
  }

  /// Whether the plugin keeps what the person listens to.
  Future<KostvMusicAnswer<KostvMusicLearnState>> settings(
    MediaServerClient client,
  ) => _read(client, 'Settings', KostvMusicLearnState.fromJson);

  /// Turns keeping what the person listens to on or off; the state after,
  /// or null when it couldn't be changed.
  Future<KostvMusicLearnState?> setLearn(
    MediaServerClient client,
    bool learn,
  ) async => KostvMusicLearnState.fromJson(
    (await _call(client, 'POST', 'Settings', body: {'Learn': learn})).data,
  );

  /// Forgets everything kept of what the person listened to. False when it
  /// couldn't.
  Future<bool> forgetListens(MediaServerClient client) async =>
      (await _call(client, 'DELETE', 'Listens')).ok;

  /// Tells the plugin where the songs [items] about to play come from.
  /// Never waited for: whatever happens to it, the music plays.
  Future<void> sendContext(
    MediaServerClient client,
    String source,
    Iterable<String> items,
  ) async {
    final ids = <String>{
      for (final id in items)
        if (id.isNotEmpty) id,
    }.take(contextMax).toList();
    if (ids.isEmpty) return;
    await _call(
      client,
      'POST',
      'Context',
      body: {'Source': source, 'ItemIds': ids},
    );
  }

  /// The person's daily mixes.
  Future<KostvMusicAnswer<KostvDailyMixes>> mixes(MediaServerClient client) {
    final server = client.baseUrl;
    return _read(
      client,
      'Mixes',
      (data) => KostvDailyMixes.fromJson(data, server),
    );
  }

  /// The person's weekly discovery.
  Future<KostvMusicAnswer<KostvMusicDiscovery>> discovery(
    MediaServerClient client,
  ) => _read(client, 'Discovery', KostvMusicDiscovery.fromJson);

  /// Keeps the week's songs, so every device of the person shows the same.
  ///
  /// [kept] false when they couldn't be kept. [week] is the plugin's week
  /// when [week] was already over by the house's clock (409): the list is
  /// then to be read and picked again for that one.
  Future<({bool kept, String? week})> keepDiscovery(
    MediaServerClient client,
    String week,
    List<StremfinSong> songs,
  ) async {
    final answer = await _call(
      client,
      'PUT',
      'Discovery',
      body: {
        'Week': week,
        'Songs': [
          for (final song in songs.take(30)) kostvStremfinSongJson(song),
        ],
      },
      answers: const {409},
    );
    if (!answer.ok) return (kept: false, week: null);
    if (answer.status == 409) {
      final data = answer.data;
      final now = data is Map ? _text(data['Week']) : null;
      return (kept: false, week: now == week ? null : now);
    }
    return (kept: true, week: null);
  }

  /// The mix of the time of day.
  Future<KostvMusicAnswer<KostvMusicMoment>> moment(MediaServerClient client) {
    final server = client.baseUrl;
    return _read(
      client,
      'Moment',
      (data) => KostvMusicMoment.fromJson(data, server),
    );
  }
}

/// Kos TV: the plugin didn't answer (or failed): what is shown stays.
class KostvMusicUnanswered implements Exception {
  const KostvMusicUnanswered(this.route);

  final String route;

  @override
  String toString() => 'The music plugin\'s $route didn\'t answer';
}

/// Kos TV: the week's discovery as the plugin has it now: [songs] to show
/// (null when it has none to give: the page shows «Canciones para ti») and
/// the [week] they are of.
typedef KostvWeekDiscovery = ({List<StremfinSong>? songs, String week});

/// Kos TV: the week's discovery: the songs the plugin kept for this week or,
/// the first time this week, those [recommend] gives for the plugin's
/// artists, picked the same on every device ([kostvWeeklyPick]) and kept in
/// the plugin.
///
/// The person and their session are taken at the start: if either changes
/// under [client] while it works (the server's client is the same for
/// everyone on it), or [wanted] says the page is gone, it stops after the
/// wait it was in and gives null, without keeping one person's list with
/// another's session. Throws [KostvMusicUnanswered] when the plugin failed
/// (not when it lacks the route: then the songs are null), and whatever
/// [recommend] throws. [onWeek] hears the plugin's week as soon as it says
/// it.
Future<KostvWeekDiscovery?> kostvLoadWeeklyDiscovery(
  KostvMusicPlugin plugin,
  MediaServerClient client, {
  required Future<StremfinRecommendations> Function(List<String> seeds)
  recommend,
  bool Function()? wanted,
  void Function(String week)? onWeek,
  DateTime Function()? now,
}) async {
  final user = client.userId;
  final token = client.accessToken;
  bool still() =>
      (wanted?.call() ?? true) &&
      client.userId == user &&
      client.accessToken == token;
  final today = now ?? DateTime.now;

  Future<KostvMusicDiscovery?> read() async {
    final answer = await plugin.discovery(client);
    if (answer.failed) throw const KostvMusicUnanswered('Discovery');
    return answer.value;
  }

  KostvWeekDiscovery? picked;
  // A second go only when the week turned while it was picked (the plugin
  // answers which one it is now).
  for (var attempt = 0; attempt < 2; attempt++) {
    final found = await read();
    if (!still()) return null;
    if (found == null) return (songs: null, week: kostvIsoWeek(today()));
    final week = found.week ?? kostvIsoWeek(today());
    onWeek?.call(week);
    if (found.songs case final songs?) return (songs: songs, week: week);
    if (found.seeds.isEmpty) return (songs: null, week: week);
    // Kept an hour by the service (and here): asked once a week.
    final recommended = await recommend(found.seeds.take(10).toList());
    if (!still()) return null;
    final songs = kostvWeeklyPick(
      kostvSongsWithAlbums(recommended.songs, recommended.albums),
      user: user ?? '',
      week: week,
    );
    if (songs.isEmpty) return (songs: songs, week: week);
    // Another of the person's devices may have kept the week's while this
    // one picked: theirs, so every device shows the same.
    final again = await read();
    if (!still()) return null;
    if (again?.week == week && again?.songs != null) {
      return (songs: again!.songs, week: week);
    }
    picked = (songs: songs, week: week);
    final kept = await plugin.keepDiscovery(client, week, songs);
    if (!still()) return null;
    // Kept, or not and not for a week that is over: shown all the same.
    if (kept.week == null) return picked;
  }
  return picked;
}

/// Kos TV: tells the server plugin where the music about to play comes from
/// ([KostvMusicSource]), with its songs. Fire and forget: it starts after
/// this returns and nothing waits for it, and nothing that fails in it (not
/// even finding [client], the server's) reaches whoever plays the music.
///
/// [startIndex] is the song it starts at: the plugin is told of those from
/// it on first (the ones that sound), then those before it, as many as it
/// takes ([KostvMusicPlugin.contextMax]).
void kostvTellMusicSource(
  MediaServerClient? Function() client,
  String source,
  List<AggregatedItem> tracks, {
  int startIndex = 0,
}) {
  final start = startIndex.clamp(0, tracks.length);
  final ids = [
    for (final track in [...tracks.skip(start), ...tracks.take(start)])
      if (track.type == 'Audio') track.id,
  ];
  if (ids.isEmpty) return;
  // After the caller goes on to play: nothing of this runs before it.
  Timer.run(() {
    try {
      final server = client();
      if (server == null) return;
      unawaited(
        KostvMusicPlugin.instance
            .sendContext(server, source, ids)
            .catchError((Object _) {}),
      );
    } catch (e) {
      debugPrint('[MusicPlugin] Not told where the music comes from: $e');
    }
  });
}
