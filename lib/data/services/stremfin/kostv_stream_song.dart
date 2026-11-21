import 'package:flutter/foundation.dart';

import '../../models/aggregated_item.dart';
import 'stremfin_models.dart';

/// Kos TV: songs that aren't at home, played through the requests service
/// («Escuchar mientras llega», `docs/stremfin-api.md` 8.35–8.38).
///
/// They go into the player's queue as ordinary songs ([AggregatedItem]s of
/// type `Audio`) with an id of their own, `stremfin:<deezerId>`, their title,
/// artists, album, length and Deezer's cover, so the floating player,
/// «Reproduciendo», the phone's notification and the queue show them as any
/// other. What only the requests service knows of them (to listen to them,
/// to ask for their album) goes with them under [kostvStreamKey].

/// The start of a song's id that isn't at home.
const kostvStreamIdPrefix = 'stremfin:';

/// Where an out-of-home song's own details go in its `rawData`.
const kostvStreamKey = '__kostvStream';

/// Whether [item] is a song that isn't at home (it sounds through the
/// requests service, not the home server).
bool isKostvStream(Object? item) =>
    item is AggregatedItem && isKostvStreamId(item.id);

/// Whether [id] is an out-of-home song's.
bool isKostvStreamId(String? id) =>
    id != null &&
    id.length > kostvStreamIdPrefix.length &&
    id.startsWith(kostvStreamIdPrefix);

/// The id in the queue of the out-of-home song [deezerId].
String kostvStreamId(String deezerId) => '$kostvStreamIdPrefix$deezerId';

/// What the requests service knows of an out-of-home song in the queue.
@immutable
class KostvStreamInfo {
  const KostvStreamInfo({
    required this.deezerId,
    this.cover,
    this.albumDeezerId,
    this.albumTitle,
    this.artistDeezerId,
    this.explicit = false,
    this.listenReady = false,
  });

  final String deezerId;

  /// Deezer's cover of its album.
  final String? cover;

  /// The album to ask for to have it at home, and its name.
  final String? albumDeezerId;
  final String? albumTitle;
  final String? artistDeezerId;
  final bool explicit;

  /// Its sound was already kept when it was put on (it starts at once).
  final bool listenReady;

  static KostvStreamInfo? of(Object? item) {
    if (!isKostvStream(item)) return null;
    final song = item! as AggregatedItem;
    final raw = song.rawData[kostvStreamKey];
    final map = raw is Map ? raw : const {};
    String? text(String key) {
      final value = map[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return KostvStreamInfo(
      deezerId:
          text('deezerId') ?? song.id.substring(kostvStreamIdPrefix.length),
      cover: text('cover'),
      albumDeezerId: text('albumDeezerId'),
      albumTitle: text('albumTitle'),
      artistDeezerId: text('artistDeezerId'),
      explicit: map['explicit'] == true,
      listenReady: map['listenReady'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'deezerId': deezerId,
    'cover': ?cover,
    'albumDeezerId': ?albumDeezerId,
    'albumTitle': ?albumTitle,
    'artistDeezerId': ?artistDeezerId,
    'explicit': explicit,
    'listenReady': listenReady,
  };
}

/// The Deezer id of [item] when it is an out-of-home song.
String? kostvStreamDeezerId(Object? item) => KostvStreamInfo.of(item)?.deezerId;

/// An out-of-home song for the player's queue. [serverId] is the home
/// server's (the one signed in), so whatever goes by it (the player's
/// resolver, who it belongs to) treats it as one of that server's.
AggregatedItem kostvStreamItem({
  required String deezerId,
  required String title,
  required String serverId,
  String? artist,
  String? album,
  String? albumArtist,
  int? durationSeconds,
  String? cover,
  String? albumDeezerId,
  String? artistDeezerId,
  bool explicit = false,
  bool listenReady = false,
}) {
  final id = kostvStreamId(deezerId);
  final artists = [
    if (artist != null && artist.trim().isNotEmpty) artist.trim(),
  ];
  return AggregatedItem(
    id: id,
    serverId: serverId,
    rawData: <String, dynamic>{
      'Id': id,
      'Name': title,
      'Type': 'Audio',
      'MediaType': 'Audio',
      'Artists': artists,
      'AlbumArtist': ?(albumArtist ?? artists.firstOrNull),
      'Album': ?album,
      if (durationSeconds != null && durationSeconds > 0)
        'RunTimeTicks': durationSeconds * 10000000,
      'UserData': const <String, dynamic>{},
      kostvStreamKey: KostvStreamInfo(
        deezerId: deezerId,
        cover: cover,
        albumDeezerId: albumDeezerId,
        albumTitle: album,
        artistDeezerId: artistDeezerId,
        explicit: explicit,
        listenReady: listenReady,
      ).toJson(),
    },
  );
}

/// How a song the requests service gives is played (8.38's rule): from
/// home when it is there, through the service when it has a Deezer id,
/// otherwise not at all (its album can only be asked for).
enum KostvSongWay { home, stream, none }

/// [KostvSongWay] of a song with these details. A song at home without its
/// home id (an older service) goes through the service, which says where it
/// is when asked to listen to it.
KostvSongWay kostvSongWay({
  required bool inJellyfin,
  String? jellyfinId,
  String? deezerId,
}) {
  if (jellyfinId != null && jellyfinId.isNotEmpty) return KostvSongWay.home;
  if (deezerId != null && deezerId.isNotEmpty) return KostvSongWay.stream;
  return KostvSongWay.none;
}

/// [KostvSongWay] of [song].
KostvSongWay kostvSongWayOf(StremfinSong song) => kostvSongWay(
  inJellyfin: song.inJellyfin,
  jellyfinId: song.jellyfinId,
  deezerId: song.deezerId,
);

/// [KostvSongWay] of [track].
KostvSongWay kostvTrackWayOf(StremfinAlbumTrack track) => kostvSongWay(
  inJellyfin: track.inJellyfin,
  jellyfinId: track.jellyfinId,
  deezerId: track.deezerId,
);

/// Whether an out-of-home song may sound for the person: an explicit one
/// isn't for anyone with a limit ([kostvMusicHidesExplicit]). What is at
/// home is left to the home server's own parental control.
bool kostvStreamAllowed({required bool explicit, required bool hideExplicit}) =>
    !hideExplicit || !explicit;

/// [song] as an out-of-home song for the queue, or null when it can't be
/// one (no Deezer id).
AggregatedItem? kostvStreamItemFromSong(
  StremfinSong song, {
  required String serverId,
}) {
  final deezerId = song.deezerId;
  if (deezerId == null || deezerId.isEmpty) return null;
  return kostvStreamItem(
    deezerId: deezerId,
    title: song.title,
    serverId: serverId,
    artist: song.artist,
    album: song.albumTitle ?? song.album?.title,
    albumArtist: song.album?.artist ?? song.artist,
    durationSeconds: song.duration,
    cover: song.cover ?? song.album?.cover,
    albumDeezerId: song.albumDeezerId ?? song.album?.deezerId,
    artistDeezerId: song.artistDeezerId,
    explicit: song.explicit,
    listenReady: song.listenReady,
  );
}

/// [track] of [album]'s page as an out-of-home song, or null when it can't
/// be one (no Deezer id).
AggregatedItem? kostvStreamItemFromTrack(
  StremfinAlbumTrack track,
  StremfinAlbum album, {
  required String serverId,
  String? artistDeezerId,
}) {
  final deezerId = track.deezerId;
  if (deezerId == null || deezerId.isEmpty) return null;
  return kostvStreamItem(
    deezerId: deezerId,
    title: track.title,
    serverId: serverId,
    artist: track.artist ?? album.artist,
    album: album.title,
    albumArtist: album.artist,
    durationSeconds: track.duration,
    cover: album.cover,
    albumDeezerId: album.deezerId,
    artistDeezerId: artistDeezerId,
    listenReady: track.listenReady,
  );
}

/// One song to put in a queue, from wherever it comes: its home id (when
/// it is at home) and, otherwise, how it is made an out-of-home song.
@immutable
class KostvQueueSong {
  const KostvQueueSong({
    required this.way,
    this.jellyfinId,
    this.stream,
    this.explicit = false,
  });

  final KostvSongWay way;
  final String? jellyfinId;

  /// The out-of-home song, also when it is at home (in case its home copy
  /// can't be found any more).
  final AggregatedItem? stream;
  final bool explicit;

  static KostvQueueSong ofSong(StremfinSong song, {required String serverId}) =>
      KostvQueueSong(
        way: kostvSongWayOf(song),
        jellyfinId: song.jellyfinId,
        stream: kostvStreamItemFromSong(song, serverId: serverId),
        explicit: song.explicit,
      );

  static KostvQueueSong ofTrack(
    StremfinAlbumTrack track,
    StremfinAlbum album, {
    required String serverId,
    String? artistDeezerId,
  }) => KostvQueueSong(
    way: kostvTrackWayOf(track),
    jellyfinId: track.jellyfinId,
    stream: kostvStreamItemFromTrack(
      track,
      album,
      serverId: serverId,
      artistDeezerId: artistDeezerId,
    ),
  );
}

/// The queue that plays [songs] from [startIndex]: those at home as the
/// home server's (asked for at once with [homeItems], in one go), the rest
/// as out-of-home songs, in their order. Those that can't sound (no Deezer
/// id, or explicit for someone with a limit) are left out, and the start
/// moves with them: to the next one that can when the one picked can't.
Future<({List<AggregatedItem> items, int startIndex})> kostvQueueOf(
  List<KostvQueueSong> songs, {
  int startIndex = 0,
  required bool hideExplicit,
  required Future<List<AggregatedItem>> Function(List<String> ids) homeItems,
}) async {
  final homeIds = [
    for (final song in songs)
      if (song.way == KostvSongWay.home) song.jellyfinId!,
  ];
  var home = const <String, AggregatedItem>{};
  if (homeIds.isNotEmpty) {
    try {
      final found = await homeItems(homeIds.toSet().toList());
      home = {for (final item in found) _plain(item.id): item};
    } catch (_) {
      // Without the home server, what can sound through the service does.
    }
  }
  final items = <AggregatedItem>[];
  var start = -1;
  for (final (i, song) in songs.indexed) {
    AggregatedItem? item;
    if (song.way == KostvSongWay.home) {
      item = home[_plain(song.jellyfinId!)];
    }
    if (item == null &&
        song.stream != null &&
        kostvStreamAllowed(
          explicit: song.explicit,
          hideExplicit: hideExplicit,
        )) {
      item = song.stream;
    }
    if (item == null) continue;
    if (start < 0 && i >= startIndex) start = items.length;
    items.add(item);
  }
  if (start < 0) start = items.isEmpty ? 0 : items.length - 1;
  return (items: items, startIndex: start);
}

String _plain(String id) => id.replaceAll('-', '').toLowerCase();
