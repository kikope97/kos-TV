import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../models/aggregated_item.dart';
import 'kostv_music.dart' show KostvMusicTaste;
import 'kostv_music_plugin.dart';
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
    final answer = await plugin.dislikes(client);
    if (answer.missing) {
      _supported[client.baseUrl] = false;
      _set(who, KostvMusicDislikes.empty, read: true);
      return answer;
    }
    final value = answer.value;
    if (value == null) return answer;
    _supported[client.baseUrl] = true;
    _set(who, value, read: true);
    return answer;
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
  /// the plugin didn't keep it.
  Future<bool> dislikeSong(MediaServerClient client, AggregatedItem song) =>
      _add(
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
    _set(who, before.withEntry(entry));
    final kept = await plugin.sendDislike(client, [
      entry.id,
    ], artist: entry.artist);
    if (!kept && _for == who) _set(who, _list.without(entry.id));
    return kept;
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
    _set(who, before.without(id));
    final done = await plugin.removeDislike(client, id);
    if (!done && entry != null && _for == who) {
      _set(who, _list.withEntry(entry));
    }
    return done;
  }

  /// Empties it; false (and put back) when the plugin didn't.
  Future<bool> clear(MediaServerClient client) async {
    final who = _who(client);
    final before = of(client);
    _set(who, KostvMusicDislikes.empty);
    final done = await plugin.clearDislikes(client);
    if (!done && _for == who) _set(who, before);
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
  }
}

/// Kos TV: the ids of the artists of one of the home server's songs.
List<String> kostvMusicArtistIds(AggregatedItem item) => [
  for (final key in const ['AlbumArtists', 'ArtistItems'])
    if (item.rawData[key] case final List list)
      for (final artist in list.whereType<Map>())
        if (artist['Id']?.toString() case final id? when id.isNotEmpty)
          id.replaceAll('-', ''),
];

/// Kos TV: the names of the artists of one of the home server's songs.
List<String> kostvMusicArtistNames(AggregatedItem item) => [
  for (final key in const ['AlbumArtists', 'ArtistItems'])
    if (item.rawData[key] case final List list)
      for (final artist in list.whereType<Map>())
        if (artist['Name']?.toString() case final name? when name.isNotEmpty)
          name,
  ...item.artists,
  if (item.albumArtist case final artist? when artist.isNotEmpty) artist,
];

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
({List<AggregatedItem> tracks, int startIndex}) kostvMusicLeaveOut(
  KostvMusicDislikes dislikes,
  List<AggregatedItem> tracks, {
  int startIndex = 0,
}) {
  if (dislikes.isEmpty || tracks.isEmpty) {
    return (tracks: tracks, startIndex: startIndex);
  }
  final kept = <AggregatedItem>[];
  var start = 0;
  for (final (i, track) in tracks.indexed) {
    if (i == startIndex) {
      start = kept.length;
      kept.add(track);
    } else if (!dislikes.songOut(track)) {
      kept.add(track);
    }
  }
  return (tracks: kept, startIndex: start);
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
