import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../models/aggregated_item.dart';
import 'kostv_music.dart' show KostvMusicTaste;
import 'kostv_music_plugin.dart';
import 'stremfin/kostv_stream_song.dart';
import 'stremfin/stremfin_models.dart';

/// Kos TV: what the person doesn't want to hear («No me gusta» of a song,
/// «No me pongas a este artista»), as the server plugin keeps it, read once
/// and kept here for whoever is signed in, so what plays by itself (the
/// radio, ∞, the mixes, «Para ti», the discovery) leaves it out at once.
///
/// What the person searched for, an album and the library still show it
/// all: only what the app picks by itself is filtered.
///
/// With a plugin from before it (404) [supported] is false and the app has
/// no «No me gusta» at all, as before.
class KostvMusicDislikesStore extends ChangeNotifier {
  KostvMusicDislikesStore([this._plugin]);

  /// The one the app uses; a test puts its own in.
  static KostvMusicDislikesStore instance = KostvMusicDislikesStore();

  final KostvMusicPlugin? _plugin;
  KostvMusicPlugin get plugin => _plugin ?? KostvMusicPlugin.instance;

  /// How long what was read is good for before it is read again (another
  /// device of the person may have changed it).
  static const fresh = Duration(minutes: 10);

  String? _for;
  KostvMusicDislikes _list = KostvMusicDislikes.empty;
  DateTime? _readAt;
  Future<KostvMusicAnswer<KostvMusicDislikes>>? _reading;

  /// Per server: whether its plugin has the route (null: not known yet).
  final Map<String, bool> _supported = {};

  /// Kos TV: the changes made here (a «No me gusta», a «Deshacer») and how
  /// many are still on their way to the plugin: a read that started before
  /// one of them landed doesn't overwrite it.
  int _changes = 0;
  int _sending = 0;

  /// Kos TV: after a read failed, how long [load] leaves it before trying
  /// again (a menu doesn't ask a server that isn't answering every time);
  /// longer each time it fails, up to [fresh].
  static const firstRetry = Duration(seconds: 30);
  String? _failedFor;
  DateTime? _failedAt;
  Duration _retryAfter = Duration.zero;

  static String _who(MediaServerClient client) =>
      '${client.baseUrl}|${client.userId}|${client.accessToken}';

  /// Whether [client]'s plugin keeps what the person doesn't want to hear,
  /// as far as is known: false until it answered once.
  bool supported(MediaServerClient? client) =>
      client != null && (_supported[client.baseUrl] ?? false);

  /// What is known now for [client]'s person (nothing for anyone else).
  KostvMusicDislikes of(MediaServerClient? client) =>
      client != null && _for == _who(client) ? _list : KostvMusicDislikes.empty;

  /// What [client]'s person doesn't want to hear: what was read lately, or
  /// read now ([force] always). A failure gives what was known (nothing for
  /// someone else).
  Future<KostvMusicDislikes> load(
    MediaServerClient client, {
    bool force = false,
  }) {
    final who = _who(client);
    final at = _readAt;
    if (!force &&
        _for == who &&
        at != null &&
        DateTime.now().difference(at) < fresh) {
      return Future.value(_list);
    }
    if (!force && _for == who && _reading != null) {
      return _reading!.then((_) => of(client));
    }
    // Kos TV: it failed a moment ago: what is known, without asking again.
    final failedAt = _failedAt;
    if (!force &&
        _failedFor == who &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < _retryAfter) {
      return Future.value(of(client));
    }
    final reading = refresh(client);
    _reading = reading;
    return reading
        .whenComplete(() {
          if (identical(_reading, reading)) _reading = null;
        })
        .then((_) => of(client));
  }

  /// Reads it now, whatever was read before: the plugin's answer
  /// ([KostvMusicAnswer.failed] when it couldn't be read: what was known
  /// stays).
  Future<KostvMusicAnswer<KostvMusicDislikes>> refresh(
    MediaServerClient client,
  ) async {
    final who = _who(client);
    final changes = _changes;
    final sending = _sending;
    final KostvMusicAnswer<KostvMusicDislikes> answer;
    try {
      answer = await plugin.dislikes(client);
    } catch (_) {
      if (_who(client) == who) _failed(who);
      rethrow;
    }
    // Kos TV: another person signed in on this client meanwhile (the
    // server's client is the same for everyone on it): this answer is the
    // last one's, and doesn't take the place of what is known for the new
    // one.
    if (_who(client) != who) return answer;
    if (answer.missing) {
      _readFine(who);
      _supported[client.baseUrl] = false;
      _set(who, KostvMusicDislikes.empty, read: true);
      return answer;
    }
    final value = answer.value;
    if (value == null) {
      _failed(who);
      return answer;
    }
    _readFine(who);
    _supported[client.baseUrl] = true;
    // Kos TV: a change made here while it was read (or still on its way
    // when it started) may not be in it: what is known here stays (and it
    // isn't taken as read just now).
    if (_for == who && (changes != _changes || sending > 0)) return answer;
    _set(who, value, read: true);
    return answer;
  }

  void _failed(String who) {
    _retryAfter = _failedFor == who && _retryAfter > Duration.zero
        ? _retryAfter * 2
        : firstRetry;
    if (_retryAfter > fresh) _retryAfter = fresh;
    _failedFor = who;
    _failedAt = DateTime.now();
  }

  void _readFine(String who) {
    if (_failedFor != who) return;
    _failedFor = null;
    _failedAt = null;
    _retryAfter = Duration.zero;
  }

  void _set(String who, KostvMusicDislikes list, {bool read = false}) {
    // Someone else's list isn't read for this one.
    if (_for != who) _readAt = null;
    _for = who;
    _list = list;
    if (read) _readAt = DateTime.now();
    notifyListeners();
  }

  /// «No me gusta» of [song]: left out at once; false (and put back) when
  /// the plugin didn't keep it. Kos TV: one that isn't at home goes by its
  /// Deezer id (`stremfin:<DeezerId>`), with its name and artist.
  Future<bool> dislikeSong(MediaServerClient client, AggregatedItem song) {
    final deezerId = kostvStreamDeezerId(song);
    if (deezerId != null) {
      return dislikeStreamSong(
        client,
        deezerId: deezerId,
        name: song.name,
        artist: song.artists.firstOrNull ?? song.albumArtist,
      );
    }
    return _add(
      client,
      KostvMusicDisliked(
        id: song.id.replaceAll('-', ''),
        name: song.name,
        artistName: kostvMusicArtistNames(song).firstOrNull,
        artistId: kostvMusicArtistIds(song).firstOrNull,
        albumId: song.albumId,
        at: DateTime.now(),
      ),
    );
  }

  /// Kos TV: «No me gusta» of the song [deezerId] that isn't at home.
  Future<bool> dislikeStreamSong(
    MediaServerClient client, {
    required String deezerId,
    required String name,
    String? artist,
  }) => _add(
    client,
    KostvMusicDisliked(
      id: kostvStreamId(deezerId),
      deezerId: deezerId,
      name: name,
      artistName: artist,
      at: DateTime.now(),
    ),
  );

  /// «No me pongas a este artista» of the artist [id], named [name].
  Future<bool> dislikeArtist(
    MediaServerClient client, {
    required String id,
    required String name,
  }) => _add(
    client,
    KostvMusicDisliked(
      id: id.replaceAll('-', ''),
      name: name,
      artist: true,
      at: DateTime.now(),
    ),
  );

  /// Puts [entry] back (undoing taking it off, in Settings).
  Future<bool> restore(MediaServerClient client, KostvMusicDisliked entry) =>
      _add(client, entry);

  Future<bool> _add(MediaServerClient client, KostvMusicDisliked entry) async {
    final who = _who(client);
    final before = of(client);
    _change(who, before.withEntry(entry));
    final deezerId = entry.deezerId;
    final kept = await _send(
      () => deezerId != null
          ? plugin.sendStreamDislike(client, [
              (deezerId: deezerId, name: entry.name, artist: entry.artistName),
            ])
          : plugin.sendDislike(client, [entry.id], artist: entry.artist),
    );
    if (!kept && _for == who) _change(who, _list.without(entry.id));
    return kept;
  }

  /// Kos TV: a change made here, which a read on its way doesn't undo.
  void _change(String who, KostvMusicDislikes list) {
    _changes++;
    _set(who, list);
  }

  Future<bool> _send(Future<bool> Function() send) async {
    _sending++;
    try {
      return await send();
    } finally {
      _sending--;
    }
  }

  /// Takes [id] out (undoing it, or from Settings); false (and put back)
  /// when the plugin didn't.
  Future<bool> remove(MediaServerClient client, String id) async {
    final who = _who(client);
    final before = of(client);
    final entry = [
      ...before.songs,
      ...before.artists,
    ].where((e) => e.id == id.replaceAll('-', '')).firstOrNull;
    _change(who, before.without(id));
    final done = await _send(() => plugin.removeDislike(client, id));
    if (!done && entry != null && _for == who) {
      _change(who, _list.withEntry(entry));
    }
    return done;
  }

  /// Empties it; false (and put back) when the plugin didn't.
  Future<bool> clear(MediaServerClient client) async {
    final who = _who(client);
    final before = of(client);
    _change(who, KostvMusicDislikes.empty);
    final done = await _send(() => plugin.clearDislikes(client));
    if (!done && _for == who) _change(who, before);
    return done;
  }

  /// Forgets everything. Only for tests.
  @visibleForTesting
  void reset() {
    _for = null;
    _list = KostvMusicDislikes.empty;
    _readAt = null;
    _reading = null;
    _supported.clear();
    _changes = 0;
    _sending = 0;
    _failedFor = null;
    _failedAt = null;
    _retryAfter = Duration.zero;
  }
}

/// Kos TV: whether one of the home server's songs names its own artists
/// (not only its album's). As for the server plugin, a song is by its own
/// artists, and by the album's only when it names none: a compilation's
/// song isn't by «Various Artists».
bool _hasTrackArtists(AggregatedItem item) =>
    _artistMaps(item, 'ArtistItems').isNotEmpty ||
    item.artists.any((name) => name.isNotEmpty);

List<Map> _artistMaps(AggregatedItem item, String key) => [
  if (item.rawData[key] case final List list) ...list.whereType<Map>(),
];

/// Kos TV: the artists of one of the home server's songs as «No me gusta»
/// takes them: its own, or its album's when it names none.
List<Map> _songArtistMaps(AggregatedItem item) =>
    _artistMaps(item, _hasTrackArtists(item) ? 'ArtistItems' : 'AlbumArtists');

/// Kos TV: the ids of the artists of one of the home server's songs (its
/// own; its album's only when it names none, as the server plugin does).
List<String> kostvMusicArtistIds(AggregatedItem item) => [
  for (final artist in _songArtistMaps(item))
    if (artist['Id']?.toString() case final id? when id.isNotEmpty)
      id.replaceAll('-', ''),
];

/// Kos TV: the names of the artists of one of the home server's songs (its
/// own; its album's only when it names none, as the server plugin does).
///
/// Kos TV: each once (whatever the case), so a song «A feat. B» whose
/// `ArtistItems` names only A still gives `[A, B]`, not `[A, A, B]`.
List<String> kostvMusicArtistNames(AggregatedItem item) {
  final seen = <String>{};
  return [
    for (final name in [
      for (final artist in _songArtistMaps(item))
        if (artist['Name']?.toString() case final name? when name.isNotEmpty)
          name,
      if (_hasTrackArtists(item))
        ...item.artists.where((name) => name.isNotEmpty)
      else if (item.albumArtist case final artist? when artist.isNotEmpty)
        artist,
    ])
      if (seen.add(name.toLowerCase())) name,
  ];
}

/// Kos TV: the artist «No me pongas a …» offers for one of the home
/// server's songs: the first of its own (the album's only when it names
/// none), with the id the server plugin needs.
({String id, String name})? kostvMusicSongArtist(AggregatedItem item) {
  for (final artist in _songArtistMaps(item)) {
    final id = artist['Id']?.toString();
    final name = artist['Name']?.toString();
    if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
      return (id: id, name: name);
    }
  }
  return null;
}

/// Kos TV: one name as the lists compare them.
String _fold(String name) => name.trim().toLowerCase();

/// Kos TV: what [KostvMusicDislikes] leaves out of what plays by itself.
extension KostvMusicDislikesFilter on KostvMusicDislikes {
  Set<String> get _songIds => {for (final s in songs) s.id};
  Set<String> get _artistIds => {for (final a in artists) a.id};
  Set<String> get _artistNames => {
    for (final a in artists)
      if (a.name.isNotEmpty) _fold(a.name),
  };

  /// Whether the artist named [name] (a requests service's, which may name
  /// several: «A, B & C») is one the person doesn't want.
  bool artistNamedOut(String? name) {
    if (name == null || name.trim().isEmpty || artists.isEmpty) return false;
    final names = _artistNames;
    if (names.contains(_fold(name))) return true;
    return name
        .split(RegExp(r',|&| feat\.? | ft\.? ', caseSensitive: false))
        .any((part) => names.contains(_fold(part)));
  }

  /// Whether the home server's song [item] is out: itself, or by one of
  /// the artists.
  bool songOut(AggregatedItem item) {
    if (isEmpty) return false;
    if (_songIds.contains(item.id.replaceAll('-', ''))) return true;
    if (artists.isEmpty) return false;
    final ids = _artistIds;
    if (kostvMusicArtistIds(item).any(ids.contains)) return true;
    return kostvMusicArtistNames(item).any(artistNamedOut);
  }

  /// [items] without those out.
  List<AggregatedItem> songsIn(List<AggregatedItem> items) => isEmpty
      ? items
      : [
          for (final item in items)
            if (!songOut(item)) item,
        ];

  /// Whether the requests service's [song] is out: one of the home server
  /// by its id, or by one of the artists (by name).
  bool stremfinSongOut(StremfinSong song) {
    if (isEmpty) return false;
    final id = song.jellyfinId;
    if (id != null && _songIds.contains(id.replaceAll('-', ''))) return true;
    // Kos TV: one that isn't at home, by its Deezer id.
    final deezerId = song.deezerId;
    if (deezerId != null &&
        deezerId.isNotEmpty &&
        _songIds.contains(kostvStreamId(deezerId))) {
      return true;
    }
    return artistNamedOut(song.artist);
  }

  List<StremfinSong> stremfinSongsIn(List<StremfinSong> songs) => isEmpty
      ? songs
      : [
          for (final song in songs)
            if (!stremfinSongOut(song)) song,
        ];

  List<StremfinAlbum> stremfinAlbumsIn(List<StremfinAlbum> albums) =>
      artists.isEmpty
      ? albums
      : [
          for (final album in albums)
            if (!artistNamedOut(album.artist)) album,
        ];

  /// «Para ti» without what is out.
  StremfinRecommendations recommendationsIn(StremfinRecommendations found) =>
      isEmpty
      ? found
      : StremfinRecommendations(
          seeds: found.seeds,
          albums: stremfinAlbumsIn(found.albums),
          songs: stremfinSongsIn(found.songs),
        );

  /// [mix] without what is out.
  KostvDailyMixes mixesIn(KostvDailyMixes mixes) => isEmpty
      ? mixes
      : KostvDailyMixes(
          day: mixes.day,
          mixes: [
            for (final mix in mixes.mixes)
              if (songsIn(mix.items) case final items when items.isNotEmpty)
                KostvDailyMix(
                  id: mix.id,
                  genre: mix.genre,
                  artists: [
                    for (final a in mix.artists)
                      if (!_artistIds.contains(a.id) && !artistNamedOut(a.name))
                        a,
                  ],
                  items: items,
                  because: [
                    for (final name in mix.because)
                      if (!artistNamedOut(name)) name,
                  ],
                ),
          ],
        );

  KostvMusicMoment momentIn(KostvMusicMoment moment) => isEmpty
      ? moment
      : KostvMusicMoment(
          slot: moment.slot,
          ready: moment.ready,
          items: songsIn(moment.items),
          because: [
            for (final name in moment.because)
              if (!artistNamedOut(name)) name,
          ],
        );

  /// [taste] without the artists that are out.
  KostvMusicTaste tasteIn(KostvMusicTaste taste) => artists.isEmpty
      ? taste
      : KostvMusicTaste(
          artists: [
            for (final a in taste.artists)
              if (!_artistIds.contains(a.id.replaceAll('-', '')) &&
                  !artistNamedOut(a.name))
                a,
          ],
          genres: taste.genres,
        );
}

/// Kos TV: [tracks] about to play by themselves (a radio, a mix), without
/// what the person doesn't want to hear, but always with the one at
/// [startIndex], which they picked: its new place.
///
/// Kos TV: with [keepStart] false nothing was picked (an artist's radio, a
/// whole mix): the one at [startIndex] goes too if it is out, and the music
/// starts with the first one kept.
({List<AggregatedItem> tracks, int startIndex}) kostvMusicLeaveOut(
  KostvMusicDislikes dislikes,
  List<AggregatedItem> tracks, {
  int startIndex = 0,
  bool keepStart = true,
}) {
  if (dislikes.isEmpty || tracks.isEmpty) {
    return (tracks: tracks, startIndex: startIndex);
  }
  final kept = <AggregatedItem>[];
  var start = 0;
  for (final (i, track) in tracks.indexed) {
    if (!keepStart) {
      if (i == startIndex) start = kept.length;
      if (!dislikes.songOut(track)) kept.add(track);
    } else if (i == startIndex) {
      start = kept.length;
      kept.add(track);
    } else if (!dislikes.songOut(track)) {
      kept.add(track);
    }
  }
  return (
    tracks: kept,
    startIndex: kept.isEmpty ? 0 : start.clamp(0, kept.length - 1),
  );
}

/// Kos TV: the person's taste, for «Para ti» and the rows that go with it:
/// the server plugin's one (`GET Music/Taste`, the same as its mixes')
/// when it has it, otherwise the app's own ([fallback], as before it: a
/// plugin without the route, failing, or with nothing learnt yet). Either
/// way without the artists the person doesn't want ([dislikes]). Throws
/// what [fallback] throws.
Future<KostvMusicTaste> kostvLoadMusicTaste(
  KostvMusicPlugin plugin,
  MediaServerClient client, {
  required Future<KostvMusicTaste> Function() fallback,
  Future<KostvMusicDislikes> Function()? dislikes,
}) async {
  final out = dislikes == null
      ? Future.value(KostvMusicDislikes.empty)
      : dislikes().catchError((Object _) => KostvMusicDislikes.empty);
  KostvMusicTaste? taste;
  try {
    final found = (await plugin.taste(client)).value;
    if (found != null && !found.isEmpty) taste = found.toTaste();
  } catch (_) {}
  taste ??= await fallback();
  return (await out).tasteIn(taste);
}
