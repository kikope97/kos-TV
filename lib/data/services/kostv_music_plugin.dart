import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../models/aggregated_item.dart';
import 'kostv_music.dart' show KostvMusicTaste;
import 'kostv_music_away.dart';
import 'moonbase_endpoint.dart';
import 'stremfin/kostv_stream_song.dart';
import 'stremfin/stremfin_client.dart';
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

  /// Kos TV: whether music from [source] is picked by the app rather than
  /// the person (a radio, a mix, the discovery): what «No me gusta» leaves
  /// out.
  static bool automatic(String source) =>
      source == radio ||
      source == discovery ||
      source.startsWith('mix:') ||
      source.startsWith('moment:');
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
    this.catalog,
  });

  final bool learn;
  final int listens;

  /// Kos TV: «Qué música enseñar» (`Catalog`): `all` (all the music, the
  /// default) or `home` (only what is at home). Null with a plugin from
  /// before it: the device keeps it then.
  final String? catalog;

  /// The first listen kept, or null with none.
  final DateTime? since;

  static KostvMusicLearnState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final learn = raw['Learn'];
    if (learn is! bool) return null;
    final listens = raw['Listens'];
    final since = raw['Since'];
    final catalog = raw['Catalog'];
    return KostvMusicLearnState(
      learn: learn,
      listens: listens is num ? listens.toInt() : 0,
      since: since is String ? DateTime.tryParse(since)?.toLocal() : null,
      catalog: catalog == 'all' || catalog == 'home' ? catalog as String : null,
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
    this.because = const [],
  });

  final String id;
  final String? genre;

  /// Kos TV: the artists that weigh most in it, by name, for «Con X, Y y
  /// más» (a plugin from before them gives none).
  final List<String> because;

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
              because: _texts(mix['Because']),
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
          if (mix.because.isNotEmpty) 'Because': mix.because,
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
    this.because = const [],
  });

  /// `manana`, `tarde` or `noche`.
  final String slot;
  final bool ready;
  final List<AggregatedItem> items;

  /// Kos TV: the artists that weigh most in it, as [KostvDailyMix.because].
  final List<String> because;

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
      because: _texts(raw['Because']),
    );
  }

  Map<String, Object?> toJson() => {
    'Slot': slot,
    'Ready': ready,
    'Items': [for (final i in items) _slim(i)],
    if (because.isNotEmpty) 'Because': because,
  };
}

/// Kos TV: what the person said they don't want to hear in anything that
/// plays by itself (`GET Music/Dislikes`): songs and artists, the latest
/// first. Kept apart from what is learnt: it holds with «Aprender» off and
/// «Borrar mi historial» doesn't take it away.
@immutable
class KostvMusicDislikes {
  const KostvMusicDislikes({this.songs = const [], this.artists = const []});

  static const empty = KostvMusicDislikes();

  final List<KostvMusicDisliked> songs;
  final List<KostvMusicDisliked> artists;

  bool get isEmpty => songs.isEmpty && artists.isEmpty;

  /// Whether [id] (a song's or an artist's) is in it.
  bool has(String id) {
    final wanted = _plainId(id);
    return songs.any((s) => s.id == wanted) ||
        artists.any((a) => a.id == wanted);
  }

  /// With [entry] in it, the latest first, once.
  KostvMusicDislikes withEntry(KostvMusicDisliked entry) => entry.artist
      ? KostvMusicDislikes(
          songs: songs,
          artists: [entry, ...artists.where((a) => a.id != entry.id)],
        )
      : KostvMusicDislikes(
          songs: [entry, ...songs.where((s) => s.id != entry.id)],
          artists: artists,
        );

  /// Without [id].
  KostvMusicDislikes without(String id) {
    final wanted = _plainId(id);
    return KostvMusicDislikes(
      songs: [
        for (final s in songs)
          if (s.id != wanted) s,
      ],
      artists: [
        for (final a in artists)
          if (a.id != wanted) a,
      ],
    );
  }

  static KostvMusicDislikes? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final songs = raw['Songs'];
    final artists = raw['Artists'];
    if (songs is! List && artists is! List) return null;
    return KostvMusicDislikes(
      songs: [
        if (songs is List)
          for (final song in songs) ?KostvMusicDisliked._of(song, false),
      ],
      artists: [
        if (artists is List)
          for (final artist in artists) ?KostvMusicDisliked._of(artist, true),
      ],
    );
  }
}

/// Kos TV: one song or artist of [KostvMusicDislikes].
@immutable
class KostvMusicDisliked {
  const KostvMusicDisliked({
    required this.id,
    required this.name,
    this.artist = false,
    this.artistName,
    this.artistId,
    this.albumId,
    this.at,
    this.deezerId,
  });

  /// The home server's id, without dashes. Kos TV: a song that isn't at
  /// home, `stremfin:<DeezerId>`, as it goes in the queue.
  final String id;

  /// Kos TV: Deezer's id of a song that isn't at home («Toda la música»).
  final String? deezerId;

  /// Kos TV: whether it is a song that isn't at home.
  bool get outOfHome => deezerId != null;
  final String name;

  /// An artist rather than a song.
  final bool artist;

  /// A song's artist.
  final String? artistName;
  final String? artistId;
  final String? albumId;
  final DateTime? at;

  static KostvMusicDisliked? _of(Object? raw, bool artist) {
    if (raw is! Map) return null;
    // Kos TV: a song that isn't at home comes with its DeezerId and no Id.
    final deezerId = artist ? null : _text(raw['DeezerId']);
    final id =
        _text(raw['Id']) ?? (deezerId == null ? null : kostvStreamId(deezerId));
    if (id == null) return null;
    final at = raw['At'];
    return KostvMusicDisliked(
      deezerId: _text(raw['Id']) == null ? deezerId : null,
      id: _plainId(id),
      name: _text(raw['Name']) ?? '',
      artist: artist,
      artistName: artist ? null : _text(raw['Artist']),
      artistId: artist ? null : _text(raw['ArtistId'])?.replaceAll('-', ''),
      albumId: artist ? null : _text(raw['AlbumId'])?.replaceAll('-', ''),
      at: at is String ? DateTime.tryParse(at)?.toLocal() : null,
    );
  }
}

String _plainId(String id) => id.replaceAll('-', '');

/// Kos TV: the person's one taste, as the plugin works it out
/// (`GET Music/Taste`): their artists of always and of lately, and their
/// genres, without the artists they said no to.
@immutable
class KostvMusicPluginTaste {
  const KostvMusicPluginTaste({
    this.learned = 0,
    this.artists = const [],
    this.recent = const [],
    this.genres = const [],
  });

  /// How much comes from what was learnt (1) rather than Jellyfin's plays
  /// (0).
  final double learned;
  final List<({String id, String name})> artists;
  final List<({String id, String name})> recent;
  final List<String> genres;

  bool get isEmpty => artists.isEmpty && recent.isEmpty;

  static KostvMusicPluginTaste? fromJson(Object? raw) {
    if (raw is! Map) return null;
    List<({String id, String name})> people(Object? list) => [
      if (list is List)
        for (final a in list.whereType<Map>())
          if ((_text(a['Id']), _text(a['Name'])) case (final id?, final name?))
            (id: _plainId(id), name: name),
    ];
    final artists = raw['Artists'];
    final recent = raw['Recent'];
    if (artists is! List && recent is! List) return null;
    final genres = raw['Genres'];
    final learned = raw['Learned'];
    return KostvMusicPluginTaste(
      learned: learned is num ? learned.toDouble().clamp(0.0, 1.0) : 0,
      artists: people(artists),
      recent: people(recent),
      genres: [
        if (genres is List)
          for (final g in genres) ?_text(g is Map ? g['Name'] : g),
      ],
    );
  }

  /// As the Music page asks for what goes with it («Para ti»): a few of
  /// lately's artists first ([recentFirst]), then those of always, then the
  /// rest of lately's, each once.
  KostvMusicTaste toTaste({int recentFirst = 4}) {
    final seen = <String>{};
    return KostvMusicTaste(
      artists: [
        for (final a in [
          ...recent.take(recentFirst),
          ...artists,
          ...recent.skip(recentFirst),
        ])
          if (seen.add(a.id)) a,
      ],
      genres: genres,
    );
  }
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
  final unique = <String, StremfinSong>{};
  for (final song in songs) {
    if (song.inJellyfin || song.jellyfinId != null) continue;
    unique.putIfAbsent(_songKey(song), () => song);
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

/// The same song, wherever it comes from (the radio, a recommendation).
String _songKey(StremfinSong song) =>
    song.deezerId ??
    '${song.title.toLowerCase()}|${(song.artist ?? '').toLowerCase()}';

/// Kos TV: how many songs the week's discovery has.
const kostvDiscoveryCount = 20;

/// Kos TV: the week's songs of discovery: [kostvWeeklyPick] of the radio's
/// [radio] songs and, when they are fewer than [count] once picked, as many
/// more as it takes out of the recommendation's [recommended] songs (picked
/// the same way, without any already in). Each with its whole album.
List<StremfinSong> kostvDiscoveryPick({
  required List<StremfinSong> radio,
  required StremfinRecommendations? recommended,
  required String user,
  required String week,
  int count = kostvDiscoveryCount,
}) {
  final songs = kostvWeeklyPick(radio, user: user, week: week, count: count);
  if (songs.length >= count || recommended == null) return songs;
  final taken = {for (final song in songs) _songKey(song)};
  return [
    ...songs,
    ...kostvWeeklyPick(
      [
        for (final song in kostvSongsWithAlbums(
          recommended.songs,
          recommended.albums,
        ))
          if (!taken.contains(_songKey(song))) song,
      ],
      user: user,
      week: week,
      count: count - songs.length,
    ),
  ];
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
          : song.withAlbum(byId[song.albumDeezerId]),
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
  'listen_ready': song.listenReady,
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

/// Kos TV: a list of names, without empty or repeated ones.
List<String> _texts(Object? raw) => [
  if (raw is List) ...{for (final item in raw) ?_text(item)},
];

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
    Map<String, Object?>? query,
    Set<int> answers = const {},
    bool keepMissing = true,
    Duration? receiveTimeout,
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
        queryParameters: query,
        options: Options(
          method: method,
          headers: ep.headers,
          receiveTimeout: receiveTimeout,
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
        // Kos TV: a 404 of something new on an old route (an event of a
        // kind it doesn't know) doesn't take the route away.
        if (keepMissing) {
          _missingAt['${client.baseUrl}|$route'] = DateTime.now();
        }
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

  /// Kos TV: «Qué música enseñar» ([catalog] `all` or `home`), the
  /// person's; the state after, or null when the plugin couldn't keep it
  /// (one from before it answers 400: the device keeps it then).
  Future<KostvMusicLearnState?> setCatalog(
    MediaServerClient client,
    String catalog,
  ) async {
    final state = KostvMusicLearnState.fromJson(
      (await _call(
        client,
        'POST',
        'Settings',
        body: {'Catalog': catalog},
        keepMissing: false,
      )).data,
    );
    return state?.catalog == null ? null : state;
  }

  /// Kos TV: a song that isn't at home was listened to through the requests
  /// service (`stream_listen`): [played] seconds of its [duration], how it
  /// ended ([endedBy]: `natural`, `next`, `stop`, `closed` or `error`), where
  /// it came from ([source], a [KostvMusicSource]) and whether on shuffle.
  /// A plugin from before it answers 400 or 404: nothing more is done (the
  /// route stays for the other events).
  ///
  /// Kos TV: the texts go cut to what the plugin takes (200 characters), and
  /// one without a title or an artist, which the plugin turns down, isn't
  /// sent (false).
  Future<bool> sendStreamListen(
    MediaServerClient client, {
    required String deezerId,
    required String title,
    String? artist,
    String? album,
    String? genre,
    required double played,
    int? duration,
    required String endedBy,
    required String source,
    bool shuffle = false,
  }) async {
    if (deezerId.isEmpty) return false;
    final name = _short(title);
    final by = _short(artist);
    if (name == null || by == null) return false;
    final reply = await _call(
      client,
      'POST',
      'Event',
      body: {
        'Type': 'stream_listen',
        'DeezerId': deezerId,
        'Title': name,
        'Artist': by,
        'Album': ?_short(album),
        'Genre': ?_short(genre),
        'Played': double.parse(played.toStringAsFixed(1)),
        'Duration': ?duration,
        'EndedBy': endedBy,
        'Source': source,
        'Shuffle': shuffle,
      },
      keepMissing: false,
    );
    return reply.ok;
  }

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

  /// Tells the plugin of something the person did that the server doesn't
  /// see (`POST Music/Event`). Never waited for, like [sendContext].
  Future<void> _sendEvent(
    MediaServerClient client,
    Map<String, Object?> body,
  ) async {
    await _call(client, 'POST', 'Event', body: body);
  }

  /// The songs [items] were added to a playlist.
  Future<void> sendPlaylistAdd(
    MediaServerClient client,
    Iterable<String> items,
  ) async {
    final ids = <String>{
      for (final id in items)
        if (id.isNotEmpty) id,
    }.take(contextMax).toList();
    if (ids.isEmpty) return;
    await _sendEvent(client, {'Type': 'playlist_add', 'ItemIds': ids});
  }

  /// An album was asked for from the requests service (Stremfin).
  Future<void> sendAlbumRequest(
    MediaServerClient client, {
    required String deezerAlbumId,
    String? album,
    String? artist,
  }) async {
    if (deezerAlbumId.isEmpty) return;
    await _sendEvent(client, {
      'Type': 'request',
      'Album': ?_text(album),
      'Artist': ?_text(artist),
      'DeezerAlbumId': deezerAlbumId,
    });
  }

  /// «No me gusta» of the songs [items] or, with [artist], «No me pongas a
  /// este artista» of the artists [items]. Kept by the plugin apart from
  /// what is learnt. False when it couldn't be kept.
  Future<bool> sendDislike(
    MediaServerClient client,
    Iterable<String> items, {
    bool artist = false,
  }) async {
    final ids = <String>{
      for (final id in items)
        if (id.isNotEmpty) id,
    }.take(contextMax).toList();
    if (ids.isEmpty) return false;
    final reply = await _call(
      client,
      'POST',
      'Event',
      body: {
        'Type': 'dislike',
        'ItemIds': ids,
        'Kind': artist ? 'artist' : 'song',
      },
    );
    return reply.ok;
  }

  /// Kos TV: «No me gusta» of [songs] that aren't at home (`Songs` of the
  /// event, each with its DeezerId, name and artist). False when the
  /// plugin didn't keep it.
  Future<bool> sendStreamDislike(
    MediaServerClient client,
    Iterable<({String deezerId, String name, String? artist})> songs,
  ) async {
    final list = [
      for (final song in songs)
        if (song.deezerId.isNotEmpty)
          {
            'DeezerId': song.deezerId,
            'Name': ?_short(song.name),
            'Artist': ?_short(song.artist),
          },
    ].take(contextMax).toList();
    if (list.isEmpty) return false;
    final reply = await _call(
      client,
      'POST',
      'Event',
      body: {'Type': 'dislike', 'Songs': list, 'Kind': 'song'},
    );
    return reply.ok;
  }

  /// Kos TV: a name as the plugin takes it (up to 200 characters), or null.
  static String? _short(String? name) {
    final text = _text(name);
    if (text == null) return null;
    return text.length > 200 ? text.substring(0, 200) : text;
  }

  /// What the person doesn't want to hear. [KostvMusicAnswer.missing] with
  /// a plugin from before it: there is no «No me gusta» then.
  Future<KostvMusicAnswer<KostvMusicDislikes>> dislikes(
    MediaServerClient client,
  ) => _read(client, 'Dislikes', KostvMusicDislikes.fromJson);

  /// Takes [itemId] out of what the person doesn't want to hear (to undo
  /// it, or from Settings). False when it couldn't.
  Future<bool> removeDislike(MediaServerClient client, String itemId) async {
    if (itemId.isEmpty) return false;
    final route = 'Dislikes/${Uri.encodeComponent(itemId)}';
    return (await _call(client, 'DELETE', route)).ok;
  }

  /// Empties what the person doesn't want to hear. False when it couldn't.
  Future<bool> clearDislikes(MediaServerClient client) async =>
      (await _call(client, 'DELETE', 'Dislikes')).ok;

  /// The person's taste as the plugin works it out.
  Future<KostvMusicAnswer<KostvMusicPluginTaste>> taste(
    MediaServerClient client,
  ) => _read(client, 'Taste', KostvMusicPluginTaste.fromJson);

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

  /// Kos TV: the station of a song (`GET Music/Station`,
  /// `docs/musica-radio.md`, «Contrato de la emisora»): what people in
  /// general listen to with it, in the plugin's order. [seed] is the home
  /// id of a song at home or `stremfin:<DeezerId>` of one that isn't
  /// ([title] and [artist] help the plugin with that one); [away] false
  /// («Solo la de casa») asks only for what is at home. A plugin from
  /// before it answers 404 ([KostvMusicAnswer.missing], kept for a while):
  /// the app makes the station as before then.
  Future<KostvMusicAnswer<KostvMusicStation>> station(
    MediaServerClient client, {
    required String seed,
    String? title,
    String? artist,
    int limit = 50,
    required bool away,
  }) async {
    if (seed.isEmpty) return const KostvMusicAnswer.failed();
    final reply = await _call(
      client,
      'GET',
      'Station',
      query: {
        'seed': seed,
        'title': ?_short(title),
        'artist': ?_short(artist),
        'limit': limit,
        'away': away,
      },
      // Kos TV: a new seed is worked out from the outside sources when
      // asked; a slow one gives way to the app's own station.
      receiveTimeout: const Duration(seconds: 20),
    );
    if (reply.missing) return const KostvMusicAnswer.missing();
    final value = reply.ok
        ? KostvMusicStation.fromJson(reply.data, client.baseUrl)
        : null;
    return value == null
        ? const KostvMusicAnswer.failed()
        : KostvMusicAnswer(value);
  }

  // Kos TV: songs that aren't at home in playlists and ♥ (plan section 8).

  static String _playlistRoute(String playlistId) =>
      'Away/Playlist/${Uri.encodeComponent(playlistId)}';

  /// The out-of-home songs of the playlist [playlistId]. A 404 is a plugin
  /// from before it or a list the person can't see ([KostvMusicAnswer
  /// .missing] either way); it doesn't take the routes away (another list
  /// may be seen).
  Future<KostvMusicAnswer<List<KostvAwayEntry>>> awayPlaylist(
    MediaServerClient client,
    String playlistId,
  ) async {
    if (playlistId.isEmpty) return const KostvMusicAnswer.failed();
    final reply = await _call(
      client,
      'GET',
      _playlistRoute(playlistId),
      keepMissing: false,
    );
    if (reply.missing) return const KostvMusicAnswer.missing();
    final value = reply.ok ? KostvAwayEntry.listOf(reply.data) : null;
    return value == null
        ? const KostvMusicAnswer.failed()
        : KostvMusicAnswer(value);
  }

  /// Adds [songs] to the playlist [playlistId] after [after] (an id of the
  /// list, null for the first) or, with [atEnd], at the end. Its entries
  /// after, or none when it couldn't ([forbidden]: 403, the person can't
  /// change it; [full]: 400, which for songs the app sends well formed is
  /// the plugin's limit of 500 in a list).
  Future<({List<KostvAwayEntry>? entries, bool forbidden, bool full})>
  addAwayToPlaylist(
    MediaServerClient client,
    String playlistId,
    List<KostvAwaySong> songs, {
    String? after,
    bool atEnd = true,
  }) async {
    if (playlistId.isEmpty || songs.isEmpty) {
      return (entries: null, forbidden: false, full: false);
    }
    final reply = await _call(
      client,
      'POST',
      _playlistRoute(playlistId),
      body: {
        'Songs': [for (final song in songs) song.toJson()],
        if (!atEnd) 'After': after,
      },
      answers: const {400, 403},
      keepMissing: false,
    );
    if (reply.status == 403) {
      return (entries: null, forbidden: true, full: false);
    }
    if (reply.status == 400) {
      return (entries: null, forbidden: false, full: true);
    }
    if (!reply.ok) return (entries: null, forbidden: false, full: false);
    return (
      entries: KostvAwayEntry.listOf(reply.data) ?? const <KostvAwayEntry>[],
      forbidden: false,
      full: false,
    );
  }

  /// Kos TV: what came of a change to a playlist's songs that aren't at
  /// home (a 403: the person can't change it).
  static KostvAwayEdit _edit(
    ({bool ok, bool missing, Object? data, int? status}) reply,
  ) => reply.status == 403
      ? KostvAwayEdit.forbidden
      : reply.ok
      ? KostvAwayEdit.done
      : KostvAwayEdit.failed;

  /// Takes the out-of-home song [deezerId] out of the playlist.
  Future<KostvAwayEdit> removeAwayFromPlaylist(
    MediaServerClient client,
    String playlistId,
    String deezerId,
  ) async {
    if (playlistId.isEmpty || deezerId.isEmpty) return KostvAwayEdit.failed;
    final route =
        '${_playlistRoute(playlistId)}/${Uri.encodeComponent(deezerId)}';
    return _edit(
      await _call(
        client,
        'DELETE',
        route,
        answers: const {403},
        keepMissing: false,
      ),
    );
  }

  /// The whole order of the playlist [playlistId] ([ids]: Jellyfin's and
  /// `stremfin:<DeezerId>`), for the plugin to place its songs again.
  Future<KostvAwayEdit> orderAwayPlaylist(
    MediaServerClient client,
    String playlistId,
    List<String> ids,
  ) async {
    if (playlistId.isEmpty || ids.isEmpty) return KostvAwayEdit.failed;
    return _edit(
      await _call(
        client,
        'POST',
        '${_playlistRoute(playlistId)}/Order',
        body: {'Ids': ids},
        answers: const {403},
        keepMissing: false,
      ),
    );
  }

  /// Kos TV: which of the playlists [ids] the person may change (theirs, or
  /// shared with them to edit), as Jellyfin's ids without dashes in lower
  /// case; null when it isn't known (a plugin from before it, or no
  /// answer).
  Future<Set<String>?> editableAwayPlaylists(
    MediaServerClient client,
    List<String> ids,
  ) async {
    final asked = [
      for (final id in ids)
        if (id.isNotEmpty) id,
    ];
    if (asked.isEmpty) return <String>{};
    final reply = await _call(
      client,
      'POST',
      'Away/Playlists/Editable',
      body: {'Ids': asked},
    );
    final data = reply.data;
    final list = reply.ok && data is Map ? data['Ids'] : null;
    if (list is! List) return null;
    return {
      for (final id in list)
        if (id != null) id.toString().replaceAll('-', '').toLowerCase(),
    };
  }

  /// The person's out-of-home ♥, the latest first. [KostvMusicAnswer
  /// .missing] with a plugin from before it: nothing of this is offered.
  Future<KostvMusicAnswer<List<KostvAwayFavorite>>> awayFavorites(
    MediaServerClient client,
  ) => _read(client, 'Away/Favorites', KostvAwayFavorite.listOf);

  /// Gives [song] the person's ♥: the plugin's status (2xx kept; 400 for a
  /// song sent well formed is its limit of 2000), null when it didn't
  /// answer.
  Future<int?> addAwayFavorite(
    MediaServerClient client,
    KostvAwaySong song,
  ) async => (await _call(
    client,
    'POST',
    'Away/Favorites',
    body: song.toJson(),
    answers: const {400},
    keepMissing: false,
  )).status;

  /// Takes the ♥ of [deezerId] away. False when it couldn't.
  Future<bool> removeAwayFavorite(
    MediaServerClient client,
    String deezerId,
  ) async {
    if (deezerId.isEmpty) return false;
    final route = 'Away/Favorites/${Uri.encodeComponent(deezerId)}';
    return (await _call(client, 'DELETE', route, keepMissing: false)).ok;
  }

  /// The out-of-home song [deezerId] is at home now as [jellyfinId].
  Future<bool> sendAwayArrived(
    MediaServerClient client, {
    required String deezerId,
    required String jellyfinId,
  }) async => (await _call(
    client,
    'POST',
    'Away/Arrived',
    body: {'DeezerId': deezerId, 'JellyfinId': jellyfinId},
    keepMissing: false,
  )).ok;
}

/// Kos TV: what came of a change to a playlist's songs that aren't at home.
enum KostvAwayEdit {
  done,

  /// The person can't change the playlist (shared with them only to see).
  forbidden,
  failed,
}

/// Kos TV: a song of a station that isn't at home (`Away` of
/// `GET Music/Station`): to sound through the requests service
/// («Escuchar mientras llega») by its Deezer id.
@immutable
class KostvStationAway {
  const KostvStationAway({
    required this.title,
    required this.deezerId,
    this.artist,
    this.album,
    this.explicit,
    this.cover,
    this.duration,
    this.artistDeezerId,
    this.albumDeezerId,
  });

  final String title;
  final String deezerId;
  final String? artist;
  final String? album;

  /// Null when the plugin didn't say.
  final bool? explicit;

  /// Kos TV: its album's cover (https only), its length in seconds, and
  /// its album's and artist's ids on Deezer: a plugin from before them
  /// doesn't give them.
  final String? cover;
  final int? duration;
  final String? artistDeezerId;
  final String? albumDeezerId;

  static KostvStationAway? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = _text(raw['Title']);
    final deezerId = _text(raw['DeezerId']);
    if (title == null || deezerId == null) return null;
    final explicit = raw['Explicit'];
    final duration = raw['Duration'];
    final cover = _text(raw['Cover']);
    return KostvStationAway(
      title: title,
      deezerId: deezerId,
      artist: _text(raw['Artist']),
      album: _text(raw['Album']),
      explicit: explicit is bool ? explicit : null,
      cover: cover != null && cover.startsWith('https://') ? cover : null,
      duration: duration is num ? duration.round() : null,
      artistDeezerId: _text(raw['ArtistDeezerId']),
      albumDeezerId: _text(raw['AlbumDeezerId']),
    );
  }

  /// As the requests service's song (not at home), for the queue.
  StremfinSong toSong() => StremfinSong(
    title: title,
    deezerId: deezerId,
    artist: artist,
    albumTitle: album,
    explicit: explicit ?? false,
    cover: cover,
    duration: duration,
    artistDeezerId: artistDeezerId,
    albumDeezerId: albumDeezerId,
  );
}

/// Kos TV: one song of a station: at home ([card], the plugin's card as
/// the app's item) or not ([away]); [why] is the source it came from.
@immutable
class KostvStationEntry {
  const KostvStationEntry({this.card, this.away, this.why});

  final AggregatedItem? card;
  final KostvStationAway? away;
  final String? why;
}

/// Kos TV: a song's station as the plugin made it (`GET Music/Station`):
/// its songs in order and where they came from ([source]: `listenbrainz`,
/// `lastfm` or `fallback`).
@immutable
class KostvMusicStation {
  const KostvMusicStation({
    this.entries = const [],
    this.source,
    this.seedTitle,
    this.seedArtist,
    this.partial,
  });

  final List<KostvStationEntry> entries;
  final String? source;
  final String? seedTitle;
  final String? seedArtist;

  /// Kos TV: whether the plugin is still working it out (`Partial`); null
  /// from a plugin that doesn't say (see [unfinished]).
  final bool? partial;

  /// Kos TV: whether asking again in a while gives more: as the plugin says
  /// it, or (one that doesn't say) when it came from the fallback. A whole
  /// station of only Deezer's radio is `fallback` and not partial.
  bool get unfinished => partial ?? source == 'fallback';

  static KostvMusicStation? fromJson(Object? raw, String serverId) {
    if (raw is! Map) return null;
    final items = raw['Items'];
    if (items is! List) return null;
    final seed = raw['Seed'];
    return KostvMusicStation(
      source: _text(raw['Source']),
      partial: raw['Partial'] is bool ? raw['Partial'] as bool : null,
      seedTitle: seed is Map ? _text(seed['Title']) : null,
      seedArtist: seed is Map ? _text(seed['Artist']) : null,
      entries: [
        for (final item in items.whereType<Map>())
          if ((
                kostvMusicCards([?item['Card']], serverId).firstOrNull,
                KostvStationAway.fromJson(item['Away']),
              )
              case (final card, final away) when card != null || away != null)
            KostvStationEntry(
              card: card,
              away: card == null ? away : null,
              why: _text(item['Why']),
            ),
      ],
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
/// the first time this week, those of Deezer's radio of the plugin's artists
/// ([radio]: only what the house hasn't, without those artists' own songs,
/// up to 50), topped up from [recommend] when they are fewer than 20, picked
/// the same on every device ([kostvDiscoveryPick]) and kept in the plugin.
/// A requests service without the radio (404, from before 1.93.0), or no
/// [radio] at all: [recommend]'s songs alone, as before it. Any other
/// failure of the radio is a failure: thrown, what is shown stays.
///
/// [clean] takes out what the person isn't shown (explicit songs, for
/// someone with a limit): before the pick, so the week's are all clean, and
/// from a list the plugin kept (another device may have picked it).
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
  Future<StremfinRadio> Function(
    List<String> artists, {
    String? only,
    bool excludeSeedArtists,
    int? limit,
  })?
  radio,
  List<StremfinSong> Function(List<StremfinSong> songs)? clean,
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
  List<StremfinSong> shown(List<StremfinSong> songs) =>
      clean == null ? songs : clean(songs);

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
    if (found.songs case final songs?) {
      return (songs: shown(songs), week: week);
    }
    if (found.seeds.isEmpty) return (songs: null, week: week);
    final seeds = found.seeds.take(10).toList();
    // Kept an hour by the service (and here): asked once a week.
    List<StremfinSong>? fromRadio;
    if (radio != null) {
      try {
        fromRadio = shown(
          (await radio(
            seeds,
            only: 'missing',
            excludeSeedArtists: true,
            limit: 50,
          )).songs,
        );
      } on StremfinException catch (e) {
        // A service from before the radio: the recommendations, as then.
        if (e.status != 404) rethrow;
      }
      if (!still()) return null;
    }
    var songs = kostvDiscoveryPick(
      radio: fromRadio ?? const [],
      recommended: null,
      user: user ?? '',
      week: week,
    );
    // Without the radio, or short of songs from it: the recommendations'.
    if (fromRadio == null || songs.length < kostvDiscoveryCount) {
      final recommended = await recommend(seeds);
      if (!still()) return null;
      songs = kostvDiscoveryPick(
        radio: fromRadio ?? const [],
        recommended: StremfinRecommendations(
          seeds: recommended.seeds,
          albums: recommended.albums,
          songs: shown(recommended.songs),
        ),
        user: user ?? '',
        week: week,
      );
    }
    if (songs.isEmpty) return (songs: songs, week: week);
    // Another of the person's devices may have kept the week's while this
    // one picked: theirs, so every device shows the same.
    final again = await read();
    if (!still()) return null;
    if (again?.week == week && again?.songs != null) {
      return (songs: shown(again!.songs!), week: week);
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
      // Kos TV: not the songs that aren't at home: the plugin only knows the
      // home server's (it hears of those as stream_listen).
      if (track.type == 'Audio' && !isKostvStream(track)) track.id,
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

/// Kos TV: runs [send] with the server's plugin once the caller has gone
/// on, and nothing that fails in it (not even finding [client]) reaches
/// whoever did what it tells.
void _kostvTellLater(
  MediaServerClient? Function() client,
  Future<void> Function(KostvMusicPlugin plugin, MediaServerClient server) send,
) {
  Timer.run(() {
    try {
      final server = client();
      if (server == null) return;
      unawaited(
        Future<void>.sync(() => send(KostvMusicPlugin.instance, server))
            .catchError((Object e) {
              debugPrint('[MusicPlugin] Not told what the person did: $e');
            }),
      );
    } catch (e) {
      debugPrint('[MusicPlugin] Not told what the person did: $e');
    }
  });
}

/// Kos TV: the songs a playlist add tells the server plugin of: the song
/// itself, or an album's songs ([tracks] when they are at hand, otherwise
/// asked of the server after the add). Null for anything else (a film, an
/// episode, an artist): nothing is told then.
Future<Iterable<String>> Function(MediaServerClient server)?
kostvPlaylistSongsOf(AggregatedItem item, {List<AggregatedItem>? tracks}) {
  switch (item.type) {
    case 'Audio':
      return (_) async => [item.id];
    case 'MusicAlbum':
      if (tracks != null && tracks.isNotEmpty) {
        final ids = [
          for (final track in tracks)
            if (track.type == 'Audio') track.id,
        ];
        return (_) async => ids;
      }
      return (server) async {
        final data = await server.itemsApi.getItems(
          parentId: item.id,
          includeItemTypes: const ['Audio'],
          recursive: true,
          limit: KostvMusicPlugin.contextMax,
          enableTotalRecordCount: false,
        );
        return [
          for (final raw in (data['Items'] as List?) ?? const [])
            if (raw is Map && raw['Id'] != null) raw['Id'].toString(),
        ];
      };
    default:
      return null;
  }
}

/// Kos TV: tells the server plugin the person added songs to a playlist
/// (`playlist_add`), those [songs] gives. Fire and forget, like
/// [kostvTellMusicSource]: the add is done and shown whatever happens here.
void kostvTellPlaylistAdd(
  MediaServerClient? Function() client,
  Future<Iterable<String>> Function(MediaServerClient server) songs,
) => _kostvTellLater(client, (plugin, server) async {
  // Not even an album's songs asked for when nobody would be told.
  if (!server.features.supportsMoonfinPlugin ||
      plugin.knownMissing(server, 'Event')) {
    return;
  }
  await plugin.sendPlaylistAdd(server, await songs(server));
});

/// Kos TV: whether asking for an album with this answer tells the server
/// plugin: not when nothing was asked (at their limit, not to be had, or
/// already at home).
bool kostvMusicRequestCounts(StremfinOutcome outcome) => switch (outcome) {
  StremfinOutcome.limit ||
  StremfinOutcome.unavailable ||
  StremfinOutcome.have => false,
  _ => true,
};

/// Kos TV: tells the server plugin the person asked the requests service
/// for an album (`request`). Fire and forget.
void kostvTellMusicRequest(
  MediaServerClient? Function() client, {
  required String deezerAlbumId,
  String? album,
  String? artist,
}) => _kostvTellLater(
  client,
  (plugin, server) => plugin.sendAlbumRequest(
    server,
    deezerAlbumId: deezerAlbumId,
    album: album,
    artist: artist,
  ),
);
