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
/// the web alike), each song once.
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

/// Kos TV: [song] as the requests service writes it, for the week's list
/// kept in the plugin ([StremfinSong.fromJson] reads it back).
Map<String, Object?> kostvStremfinSongJson(StremfinSong song) => {
  'title': song.title,
  'deezer_id': ?song.deezerId,
  'artist': ?song.artist,
  'artist_deezer_id': ?song.artistDeezerId,
  'duration': ?song.duration,
  'preview': ?song.preview,
  'explicit': song.explicit,
  'cover': ?song.cover,
  if (song.albumTitle != null || song.albumDeezerId != null)
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

  /// What is about to play: as many songs as the plugin is told of.
  static const contextMax = 200;

  final Dio _dio;
  final Map<String, DateTime> _missingAt = {};

  static const _base = '/Moonfin/Kostv/Music';

  /// Whether [client]'s plugin was last seen without [route].
  bool knownMissing(MediaServerClient client, String route) {
    final at = _missingAt['${client.baseUrl}|$route'];
    return at != null && DateTime.now().difference(at) < _retryAfter;
  }

  /// Forgets which routes were missing (a test, a user switch).
  @visibleForTesting
  void reset() => _missingAt.clear();

  /// The answer of [route], or null when the plugin can't give it: missing
  /// (404, kept for a while), unreachable or not there at all. A status in
  /// [answers] is an answer too (409 of a week that is over), with its body.
  Future<({Object? data, int? status})?> _call(
    MediaServerClient client,
    String method,
    String route, {
    Object? body,
    Set<int> answers = const {},
  }) async {
    if (knownMissing(client, route)) return null;
    try {
      final ep = await moonbaseEndpoint(client, _dio);
      if (ep == null) return null;
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
      return (data: response.data, status: response.statusCode);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _missingAt['${client.baseUrl}|$route'] = DateTime.now();
      } else {
        debugPrint('[MusicPlugin] $method $route failed: ${e.message}');
      }
      return null;
    } catch (e) {
      debugPrint('[MusicPlugin] $method $route failed: $e');
      return null;
    }
  }

  /// Whether the plugin keeps what the person listens to; null without the
  /// route.
  Future<KostvMusicLearnState?> settings(MediaServerClient client) async =>
      KostvMusicLearnState.fromJson(
        (await _call(client, 'GET', 'Settings'))?.data,
      );

  /// Turns keeping what the person listens to on or off; the state after,
  /// or null when it couldn't be changed.
  Future<KostvMusicLearnState?> setLearn(
    MediaServerClient client,
    bool learn,
  ) async => KostvMusicLearnState.fromJson(
    (await _call(client, 'POST', 'Settings', body: {'Learn': learn}))?.data,
  );

  /// Forgets everything kept of what the person listened to. False when it
  /// couldn't.
  Future<bool> forgetListens(MediaServerClient client) async =>
      await _call(client, 'DELETE', 'Listens') != null;

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

  /// The person's daily mixes, or null without the route.
  Future<KostvDailyMixes?> mixes(MediaServerClient client) async =>
      KostvDailyMixes.fromJson(
        (await _call(client, 'GET', 'Mixes'))?.data,
        client.baseUrl,
      );

  /// The person's weekly discovery, or null without the route.
  Future<KostvMusicDiscovery?> discovery(MediaServerClient client) async =>
      KostvMusicDiscovery.fromJson(
        (await _call(client, 'GET', 'Discovery'))?.data,
      );

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
    if (answer == null) return (kept: false, week: null);
    if (answer.status == 409) {
      final data = answer.data;
      final now = data is Map ? _text(data['Week']) : null;
      return (kept: false, week: now == week ? null : now);
    }
    return (kept: true, week: null);
  }

  /// The mix of the time of day, or null without the route.
  Future<KostvMusicMoment?> moment(MediaServerClient client) async =>
      KostvMusicMoment.fromJson(
        (await _call(client, 'GET', 'Moment'))?.data,
        client.baseUrl,
      );
}

/// Kos TV: tells the server plugin where the music about to play comes from
/// ([KostvMusicSource]), with its songs. Fire and forget: it starts after
/// this returns and nothing waits for it, and nothing that fails in it (not
/// even finding [client], the server's) reaches whoever plays the music.
void kostvTellMusicSource(
  MediaServerClient? Function() client,
  String source,
  List<AggregatedItem> tracks,
) {
  final ids = [
    for (final track in tracks)
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
