import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../models/aggregated_item.dart';
import 'kostv_music_catalog.dart';
import 'kostv_music_dislikes.dart';
import 'kostv_music_plugin.dart';
import 'stremfin/kostv_stream_song.dart';
import 'stremfin/stremfin_service.dart';

/// Kos TV: songs that aren't at home in the person's playlists and ♥
/// («Listas y ♥ con canciones de fuera», `docs/musica-toda-la-musica.md`
/// section 8). Jellyfin only keeps its own songs, so the server plugin keeps
/// «huecos» in Jellyfin's playlists (each after the item it follows) and a ♥
/// of its own; when the song arrives home, it moves it to Jellyfin itself.
///
/// With a plugin from before it (404) nothing of this is offered.

/// Where an out-of-home song of a playlist or of the ♥ keeps when it was
/// added, in its `rawData`.
const kostvAwayAddedKey = '__kostvAwayAdded';

/// Kos TV: one song that isn't at home as the plugin keeps it (`AwaySong`).
@immutable
class KostvAwaySong {
  const KostvAwaySong({
    required this.deezerId,
    required this.title,
    this.artist,
    this.album,
    this.albumDeezerId,
    this.artistDeezerId,
    this.cover,
    this.duration,
    this.explicit = false,
  });

  final String deezerId;
  final String title;
  final String? artist;
  final String? album;
  final String? albumDeezerId;
  final String? artistDeezerId;
  final String? cover;

  /// Its length, in seconds.
  final int? duration;
  final bool explicit;

  static String? _text(Object? raw) {
    final text = raw?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// A text as the plugin takes it (up to 200 characters).
  static String? _short(String? text) {
    final value = _text(text);
    if (value == null) return null;
    return value.length > 200 ? value.substring(0, 200) : value;
  }

  static KostvAwaySong? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _text(raw['DeezerId']);
    final title = _text(raw['Title']);
    if (id == null || title == null) return null;
    final duration = raw['Duration'];
    return KostvAwaySong(
      deezerId: id,
      title: title,
      artist: _text(raw['Artist']),
      album: _text(raw['Album']),
      albumDeezerId: _text(raw['AlbumDeezerId']),
      artistDeezerId: _text(raw['ArtistDeezerId']),
      cover: _text(raw['Cover']),
      duration: duration is num && duration > 0 ? duration.round() : null,
      explicit: raw['Explicit'] == true,
    );
  }

  /// [stream] (an out-of-home song of the queue) as the plugin keeps it, or
  /// null when it isn't one.
  static KostvAwaySong? ofItem(AggregatedItem stream) {
    final info = KostvStreamInfo.of(stream);
    if (info == null) return null;
    final seconds = stream.runtime?.inSeconds;
    return KostvAwaySong(
      deezerId: info.deezerId,
      title: stream.name,
      artist:
          stream.artists.where((a) => a.trim().isNotEmpty).firstOrNull ??
          stream.albumArtist,
      album: info.albumTitle ?? stream.album,
      albumDeezerId: info.albumDeezerId,
      artistDeezerId: info.artistDeezerId,
      cover: info.cover,
      duration: seconds != null && seconds > 0 ? seconds : null,
      explicit: info.explicit,
    );
  }

  /// The longest a song may be for the plugin (6 h).
  static const maxDuration = 6 * 3600;

  /// [cover] when the plugin takes it: an `http`/`https` address of up to
  /// 1000 characters (anything else would turn the whole song down).
  String? get _sentCover {
    final url = cover;
    if (url == null || url.length > 1000) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return url;
  }

  Map<String, Object?> toJson() => {
    'DeezerId': deezerId,
    'Title': _short(title) ?? deezerId,
    'Artist': ?_short(artist),
    'Album': ?_short(album),
    'AlbumDeezerId': ?albumDeezerId,
    'ArtistDeezerId': ?artistDeezerId,
    'Cover': ?_sentCover,
    if (duration case final d? when d > 0 && d <= maxDuration) 'Duration': d,
    'Explicit': explicit,
  };

  /// It as an out-of-home song for the lists and the queue, [serverId]'s.
  AggregatedItem toItem(String serverId) => kostvStreamItem(
    deezerId: deezerId,
    title: title,
    serverId: serverId,
    artist: artist,
    album: album,
    durationSeconds: duration,
    cover: cover,
    albumDeezerId: albumDeezerId,
    artistDeezerId: artistDeezerId,
    explicit: explicit,
  );
}

/// Kos TV: an out-of-home song of a playlist: what follows ([after]: the id
/// of the item before it in the whole list, Jellyfin's or
/// `stremfin:<DeezerId>`; null for the first) and when it was added.
@immutable
class KostvAwayEntry {
  const KostvAwayEntry({required this.song, this.after, this.added});

  final KostvAwaySong song;
  final String? after;
  final DateTime? added;

  static KostvAwayEntry? fromJson(Object? raw) {
    final song = KostvAwaySong.fromJson(raw);
    if (song == null || raw is! Map) return null;
    final after = raw['After']?.toString().trim();
    final added = raw['Added'];
    return KostvAwayEntry(
      song: song,
      after: after == null || after.isEmpty ? null : after,
      added: added is String ? DateTime.tryParse(added) : null,
    );
  }

  /// The entries of a playlist's answer (`{ "Entries": [...] }`), or null
  /// when it isn't one.
  static List<KostvAwayEntry>? listOf(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['Entries'];
    if (list == null) return const [];
    if (list is! List) return null;
    return [for (final e in list) ?KostvAwayEntry.fromJson(e)];
  }
}

/// Kos TV: an out-of-home song with the person's ♥, and since when.
@immutable
class KostvAwayFavorite {
  const KostvAwayFavorite({required this.song, this.added});

  final KostvAwaySong song;
  final DateTime? added;

  /// The ♥ of the answer (`{ "Songs": [...] }`), the latest first, or null
  /// when it isn't one.
  static List<KostvAwayFavorite>? listOf(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['Songs'];
    if (list == null) return const [];
    if (list is! List) return null;
    final found = <KostvAwayFavorite>[];
    for (final e in list) {
      final song = KostvAwaySong.fromJson(e);
      if (song == null || e is! Map) continue;
      final added = e['Added'];
      found.add(
        KostvAwayFavorite(
          song: song,
          added: added is String ? DateTime.tryParse(added) : null,
        ),
      );
    }
    return found;
  }
}

// ---------------------------------------------------------------- the lists

String _key(String id) => isKostvStreamId(id)
    ? id.toLowerCase()
    : id.replaceAll('-', '').toLowerCase();

/// Kos TV: [home] (a playlist's songs, as Jellyfin gives them, in order)
/// with its out-of-home songs [away] in their places: each right after the
/// item its `After` names (Jellyfin's, or another out-of-home one), the
/// first ones before everything; those whose `After` isn't in the list any
/// more go at the end, in their order. Each one is an out-of-home song of
/// [serverId] with `PlaylistItemId` `stremfin:<DeezerId>`, so the list takes
/// it as one of its entries.
///
/// With [hideExplicit] (someone with a limit) the explicit ones aren't
/// there, but those that follow them still keep their places.
List<AggregatedItem> kostvMergeAway(
  List<AggregatedItem> home,
  List<KostvAwayEntry> away, {
  required String serverId,
  bool hideExplicit = false,
}) {
  if (away.isEmpty) return home;
  final after = <String, List<KostvAwayEntry>>{};
  final seen = <String>{};
  final entries = <KostvAwayEntry>[];
  for (final entry in away) {
    // The same song twice is one.
    if (!seen.add(entry.song.deezerId)) continue;
    entries.add(entry);
    after.putIfAbsent(_key(entry.after ?? ''), () => []).add(entry);
  }
  final out = <AggregatedItem>[];
  final placed = <String>{};
  void add(KostvAwayEntry entry) {
    if (!(hideExplicit && entry.song.explicit)) {
      out.add(kostvAwayItem(entry, serverId: serverId));
    }
  }

  // The out-of-home songs right after [key], and those after each of them.
  void placeAfter(String key) {
    for (final entry in after[key] ?? const <KostvAwayEntry>[]) {
      if (!placed.add(entry.song.deezerId)) continue;
      add(entry);
      placeAfter(_key(kostvStreamId(entry.song.deezerId)));
    }
  }

  placeAfter('');
  for (final item in home) {
    out.add(item);
    placeAfter(_key(item.id));
    final entryId = item.rawData['PlaylistItemId']?.toString();
    if (entryId != null && entryId.isNotEmpty) placeAfter(_key(entryId));
  }
  // Those whose place went (or a loop of them): at the end, in their order.
  for (final entry in entries) {
    if (!placed.add(entry.song.deezerId)) continue;
    add(entry);
    placeAfter(_key(kostvStreamId(entry.song.deezerId)));
  }
  return out;
}

/// Kos TV: how long a playlist waits for its songs that aren't at home
/// before it shows Jellyfin's alone.
const kostvAwayWait = Duration(seconds: 8);

/// Kos TV: [home] (the songs of [client]'s playlist [playlistId] in
/// Jellyfin) with the ones that aren't at home merged in ([kostvMergeAway],
/// as [serverId]'s). As it was for a playlist that isn't of music
/// ([mediaType], or a song that isn't one), with a plugin from before it, or
/// when they can't be read.
Future<List<AggregatedItem>> kostvPlaylistWithAway(
  MediaServerClient client,
  String playlistId,
  List<AggregatedItem> home, {
  String? serverId,
  Object? mediaType,
  KostvMusicAwayStore? store,
}) async {
  if (mediaType != null && mediaType != 'Audio' && mediaType != 'Unknown') {
    return home;
  }
  if (home.any((t) => t.type != 'Audio')) return home;
  final away = store ?? KostvMusicAwayStore.instance;
  // Whether the plugin keeps them at all, for the songs' menus.
  unawaited(away.load(client).then((_) {}, onError: (Object _) {}));
  try {
    final entries = await away
        .playlist(client, playlistId)
        .timeout(kostvAwayWait);
    if (entries == null || entries.isEmpty) return home;
    return kostvMergeAway(
      home,
      entries,
      serverId: serverId ?? client.baseUrl,
      hideExplicit: kostvAwayHidesExplicit(),
    );
  } catch (_) {
    return home;
  }
}

/// Kos TV: [entry] as one of its playlist's songs (see [kostvMergeAway]).
AggregatedItem kostvAwayItem(KostvAwayEntry entry, {required String serverId}) {
  final item = entry.song.toItem(serverId);
  item.rawData['PlaylistItemId'] = item.id;
  final added = entry.added;
  if (added != null) item.rawData[kostvAwayAddedKey] = added.toIso8601String();
  return item;
}

/// Kos TV: the whole order of a playlist's [tracks] as the plugin takes it
/// (`POST Away/Playlist/{id}/Order`): Jellyfin's ids and `stremfin:<id>`.
List<String> kostvAwayOrderIds(List<AggregatedItem> tracks) => [
  for (final track in tracks) track.id,
];

/// Kos TV: where Jellyfin puts a song of its own that is now at [position]
/// of [tracks] (the whole list): among its own songs only.
int kostvHomeIndexAt(List<AggregatedItem> tracks, int position) {
  var index = 0;
  for (var i = 0; i < position && i < tracks.length; i++) {
    if (!isKostvStream(tracks[i])) index++;
  }
  return index;
}

/// Kos TV: whether someone isn't shown the explicit songs that aren't at
/// home (no requests service known: they aren't).
bool kostvAwayHidesExplicit() =>
    !GetIt.instance.isRegistered<StremfinService>() ||
    GetIt.instance<StremfinService>().hidesExplicitMusic;

/// Kos TV: whether an out-of-home song of a list sounds now: with «Toda la
/// música», and not explicit for someone with a limit. With «Solo la de
/// casa» it is there, in grey, but doesn't sound.
bool kostvAwayPlayable(
  AggregatedItem item, {
  bool? catalogAll,
  bool? hideExplicit,
}) {
  final info = KostvStreamInfo.of(item);
  if (info == null) return true;
  if (!(catalogAll ?? kostvMusicCatalogAll())) return false;
  return kostvStreamAllowed(
    explicit: info.explicit,
    hideExplicit: hideExplicit ?? kostvAwayHidesExplicit(),
  );
}

MediaServerClient? _signedIn() =>
    GetIt.instance.isRegistered<MediaServerClient>()
    ? GetIt.instance<MediaServerClient>()
    : null;

/// Kos TV: [tracks] of a playlist (or of «Tus favoritas») as they play
/// from [startIndex]: without the out-of-home ones that can't sound
/// ([kostvAwayPlayable]) and without what the person doesn't want to hear
/// ([dislikes]), but the one picked ([picked]); the start moves with them,
/// to the next one that sounds when the one picked can't. A list without
/// any of that plays as it is.
({List<AggregatedItem> tracks, int startIndex}) kostvPlaylistToPlay(
  List<AggregatedItem> tracks, {
  int startIndex = 0,
  bool picked = true,
  bool? catalogAll,
  bool? hideExplicit,
  KostvMusicDislikes? dislikes,
}) {
  final out = dislikes ?? KostvMusicDislikesStore.instance.of(_signedIn());
  if (out.isEmpty && !tracks.any(isKostvStream)) {
    return (tracks: tracks, startIndex: startIndex);
  }
  final all = catalogAll ?? kostvMusicCatalogAll();
  final hide = hideExplicit ?? kostvAwayHidesExplicit();
  final kept = <AggregatedItem>[];
  var start = -1;
  for (final (i, track) in tracks.indexed) {
    if (!kostvAwayPlayable(track, catalogAll: all, hideExplicit: hide)) {
      continue;
    }
    if (start < 0 && i >= startIndex) start = kept.length;
    kept.add(track);
  }
  if (start < 0) start = kept.isEmpty ? 0 : kept.length - 1;
  // The one picked is the one at [startIndex] only when it can sound.
  final keepStart =
      picked &&
      startIndex >= 0 &&
      startIndex < tracks.length &&
      kostvAwayPlayable(
        tracks[startIndex],
        catalogAll: all,
        hideExplicit: hide,
      );
  final left = kostvMusicLeaveOut(
    out,
    kept,
    startIndex: start,
    keepStart: keepStart,
  );
  return (tracks: left.tracks, startIndex: left.startIndex);
}

/// Kos TV: «Tus favoritas»: the home server's ♥ songs [home] (as it gives
/// them, by when they were last played) with the out-of-home ones [away]
/// (the latest ♥ first), merged by date when the home ones have one (their
/// last play; Jellyfin doesn't say when a ♥ was given), otherwise after
/// them. Explicit ones aren't there for someone with a limit
/// ([hideExplicit]).
List<AggregatedItem> kostvMergeFavorites(
  List<AggregatedItem> home,
  List<KostvAwayFavorite> away, {
  required String serverId,
  bool hideExplicit = false,
}) {
  final shown = [
    for (final f in away)
      if (!(hideExplicit && f.song.explicit)) f,
  ];
  if (shown.isEmpty) return home;
  DateTime? dateOf(AggregatedItem item) {
    final data = item.rawData['UserData'];
    final raw = data is Map ? data['LastPlayedDate'] : null;
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  AggregatedItem itemOf(KostvAwayFavorite f) {
    final item = f.song.toItem(serverId);
    final added = f.added;
    if (added != null) {
      item.rawData[kostvAwayAddedKey] = added.toIso8601String();
    }
    return item;
  }

  final out = <AggregatedItem>[];
  var a = 0;
  for (final item in home) {
    final date = dateOf(item);
    // Without a date on the home one, the out-of-home ones wait for one
    // that has it (or the end).
    if (date != null) {
      while (a < shown.length &&
          shown[a].added != null &&
          !shown[a].added!.isBefore(date)) {
        out.add(itemOf(shown[a++]));
      }
    }
    out.add(item);
  }
  while (a < shown.length) {
    out.add(itemOf(shown[a++]));
  }
  return out;
}

// ---------------------------------------------------------------- the store

/// Kos TV: the person's out-of-home ♥ (read once and kept for whoever is
/// signed in) and whether their server's plugin keeps them at all, plus the
/// playlist routes and the arrivals told once.
class KostvMusicAwayStore extends ChangeNotifier {
  KostvMusicAwayStore([this._plugin]);

  /// The one the app uses; a test puts its own in.
  static KostvMusicAwayStore instance = KostvMusicAwayStore();

  final KostvMusicPlugin? _plugin;
  KostvMusicPlugin get plugin => _plugin ?? KostvMusicPlugin.instance;

  /// How long what was read is good for before it is read again.
  static const fresh = Duration(minutes: 10);

  String? _for;
  List<KostvAwayFavorite> _favorites = const [];
  DateTime? _readAt;
  Future<void>? _reading;
  int _changes = 0;

  /// Per server: whether its plugin has the routes (null: not known yet).
  final Map<String, bool> _supported = {};

  /// Kos TV: the arrivals already told, this session, for [_arrivedFor].
  final Set<String> _arrived = {};
  String? _arrivedFor;

  static String _who(MediaServerClient client) =>
      '${client.baseUrl}|${client.userId}|${client.accessToken}';

  /// Whether [client]'s plugin keeps songs that aren't at home in playlists
  /// and ♥, as far as is known: false until it answered once.
  bool supported(MediaServerClient? client) =>
      client != null && (_supported[client.baseUrl] ?? false);

  /// Whether [client]'s plugin is known to be one from before it.
  bool knownMissing(MediaServerClient? client) =>
      client != null && _supported[client.baseUrl] == false;

  /// The out-of-home ♥ known now for [client]'s person, the latest first
  /// (nothing for anyone else).
  List<KostvAwayFavorite> favoritesOf(MediaServerClient? client) =>
      client != null && _for == _who(client) ? _favorites : const [];

  /// Whether [client]'s person gave [deezerId] a ♥.
  bool isFavorite(MediaServerClient? client, String deezerId) =>
      favoritesOf(client).any((f) => f.song.deezerId == deezerId);

  /// Reads the person's out-of-home ♥ (and so whether the plugin keeps
  /// them) unless it was read lately; [force] always. A failure keeps what
  /// was known.
  Future<List<KostvAwayFavorite>> load(
    MediaServerClient client, {
    bool force = false,
  }) async {
    final who = _who(client);
    final at = _readAt;
    if (!force &&
        _for == who &&
        at != null &&
        DateTime.now().difference(at) < fresh) {
      return _favorites;
    }
    if (!force && _for == who && _reading != null) {
      await _reading;
      return favoritesOf(client);
    }
    final reading = _read(client, who);
    _reading = reading;
    try {
      await reading;
    } finally {
      if (identical(_reading, reading)) _reading = null;
    }
    return favoritesOf(client);
  }

  Future<void> _read(MediaServerClient client, String who) async {
    final changes = _changes;
    final answer = await plugin.awayFavorites(client);
    // Another person signed in meanwhile: not theirs.
    if (_who(client) != who) return;
    if (answer.missing) {
      _supported[client.baseUrl] = false;
      _set(who, const [], read: true);
      return;
    }
    final value = answer.value;
    if (value == null) return;
    _supported[client.baseUrl] = true;
    // A ♥ given here while it was read may not be in it.
    if (_for == who && changes != _changes) return;
    _set(who, value, read: true);
  }

  void _set(String who, List<KostvAwayFavorite> list, {bool read = false}) {
    if (_for != who) {
      _readAt = null;
      _arrived.clear();
      _arrivedFor = who;
    }
    _for = who;
    _favorites = list;
    if (read) _readAt = DateTime.now();
    notifyListeners();
  }

  /// Gives [stream] (an out-of-home song) the person's ♥ ([on]) or takes it
  /// away: at once here, put back when the plugin didn't keep it ([done]
  /// false; [full]: the person already has as many as the plugin keeps).
  Future<({bool done, bool full})> setFavorite(
    MediaServerClient client,
    AggregatedItem stream, {
    required bool on,
  }) async {
    final song = KostvAwaySong.ofItem(stream);
    if (song == null) return (done: false, full: false);
    final who = _who(client);
    final before = favoritesOf(client);
    final without = [
      for (final f in before)
        if (f.song.deezerId != song.deezerId) f,
    ];
    _changes++;
    _set(
      who,
      on
          ? [KostvAwayFavorite(song: song, added: DateTime.now()), ...without]
          : without,
    );
    var full = false;
    final bool done;
    if (on) {
      final status = await plugin.addAwayFavorite(client, song);
      done = status != null && status >= 200 && status < 300;
      // Kos TV: a 400 of a song the app sends well formed is the limit.
      full = status == 400;
    } else {
      done = await plugin.removeAwayFavorite(client, song.deezerId);
    }
    if (!done && _for == who) {
      _changes++;
      _set(who, before);
    }
    return (done: done, full: full);
  }

  /// The out-of-home songs of the playlist [playlistId], or null when there
  /// are none to show (a plugin from before it, one that can't be read, or
  /// the person can't see it).
  Future<List<KostvAwayEntry>?> playlist(
    MediaServerClient client,
    String playlistId,
  ) async {
    if (knownMissing(client)) return null;
    final answer = await plugin.awayPlaylist(client, playlistId);
    return answer.value;
  }

  /// Adds [songs] at the end of the playlist [playlistId]: its entries
  /// after, or null when it couldn't ([forbidden]: the person can't change
  /// it; [full]: it already has as many as the plugin keeps).
  Future<({List<KostvAwayEntry>? entries, bool forbidden, bool full})>
  addToPlaylist(
    MediaServerClient client,
    String playlistId,
    List<AggregatedItem> songs, {
    String? after,
    bool atEnd = true,
  }) => plugin.addAwayToPlaylist(
    client,
    playlistId,
    [for (final s in songs) ?KostvAwaySong.ofItem(s)],
    after: after,
    atEnd: atEnd,
  );

  /// Takes the out-of-home song [deezerId] out of the playlist.
  Future<bool> removeFromPlaylist(
    MediaServerClient client,
    String playlistId,
    String deezerId,
  ) => plugin.removeAwayFromPlaylist(client, playlistId, deezerId);

  /// Tells the plugin the whole order of the playlist.
  Future<bool> order(
    MediaServerClient client,
    String playlistId,
    List<AggregatedItem> tracks,
  ) => plugin.orderAwayPlaylist(client, playlistId, kostvAwayOrderIds(tracks));

  /// Kos TV: the out-of-home song [deezerId] is at home now as [jellyfinId]
  /// (the requests service said so): the plugin is told, once for each
  /// song this session (for the person signed in), so it moves it into
  /// Jellyfin's lists and ♥. Its ♥ here goes (it is Jellyfin's now).
  /// Nothing with a plugin from before it.
  void arrived(MediaServerClient? client, String deezerId, String jellyfinId) {
    if (client == null || deezerId.isEmpty || jellyfinId.isEmpty) return;
    if (knownMissing(client)) return;
    final who = _who(client);
    if (_arrivedFor != who) {
      _arrived.clear();
      _arrivedFor = who;
    }
    if (!_arrived.add(deezerId)) return;
    unawaited(
      plugin.sendAwayArrived(
        client,
        deezerId: deezerId,
        jellyfinId: jellyfinId,
      ),
    );
    if (_for == who && isFavorite(client, deezerId)) {
      _changes++;
      _set(who, [
        for (final f in _favorites)
          if (f.song.deezerId != deezerId) f,
      ]);
    }
  }

  /// Forgets everything. Only for tests.
  @visibleForTesting
  void reset() {
    _for = null;
    _favorites = const [];
    _readAt = null;
    _reading = null;
    _changes = 0;
    _supported.clear();
    _arrived.clear();
    _arrivedFor = null;
  }
}
