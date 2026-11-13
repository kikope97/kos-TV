import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../models/aggregated_item.dart';

/// Kos TV: what the person listens to on the home server, for the Music
/// page: what they played lately, who and what they listen to most, a mix
/// of an artist, and a search of the music at home.
class KostvMusicService {
  KostvMusicService(this._client);

  final MediaServerClient _client;

  static const _fields =
      'PrimaryImageAspectRatio,SortName,ProductionYear,AlbumArtist,Artists,'
      'ArtistItems,AlbumArtists,Genres,ChildCount,RunTimeTicks,UserData,Album,'
      'AlbumId,AlbumPrimaryImageTag,DateCreated';

  String get _serverId => _client.baseUrl;

  List<AggregatedItem> _items(Map<String, dynamic> response) => [
    for (final raw
        in ((response['Items'] as List?) ?? const []).whereType<Map>())
      if (raw['Id'] != null)
        AggregatedItem(
          id: raw['Id'].toString(),
          serverId: _serverId,
          rawData: raw.cast<String, dynamic>(),
        ),
  ];

  Future<List<AggregatedItem>> _get({
    required List<String> types,
    String? sortBy,
    bool descending = false,
    int? limit,
    String? searchTerm,
    List<String>? filters,
    List<String>? ids,
    List<String>? artistIds,
    List<String>? genres,
  }) async => _items(
    await _client.itemsApi.getItems(
      includeItemTypes: types,
      recursive: true,
      sortBy: sortBy,
      sortOrder: descending ? 'Descending' : 'Ascending',
      limit: limit,
      searchTerm: searchTerm,
      filters: filters,
      ids: ids,
      artistIds: artistIds,
      genres: genres,
      fields: _fields,
    ),
  );

  /// One of the home server's items by its id, or null.
  Future<AggregatedItem?> item(String id) async =>
      (await _get(types: const ['Audio', 'MusicAlbum'], ids: [id])).firstOrNull;

  /// Whether the home server has any music the person can play.
  Future<bool> hasMusic() async =>
      (await _get(types: const ['Audio'], limit: 1)).isNotEmpty;

  /// The albums of what the person played lately, the latest first.
  Future<List<AggregatedItem>> recentAlbums({int max = 12}) async {
    final songs = await _get(
      types: const ['Audio'],
      sortBy: 'DatePlayed',
      descending: true,
      filters: const ['IsPlayed'],
      limit: 120,
    );
    final ids = <String>[];
    for (final song in songs) {
      final album = song.rawData['AlbumId']?.toString();
      if (album != null && !ids.contains(album)) ids.add(album);
      if (ids.length >= max) break;
    }
    if (ids.isEmpty) return const [];
    final albums = await _get(types: const ['MusicAlbum'], ids: ids);
    final byId = {for (final album in albums) album.id: album};
    return [for (final id in ids) ?byId[id]];
  }

  /// What the person listens to most: their artists and genres, from the
  /// songs they played most.
  Future<KostvMusicTaste> taste() async {
    final songs = await _get(
      types: const ['Audio'],
      sortBy: 'PlayCount,DatePlayed',
      descending: true,
      filters: const ['IsPlayed'],
      limit: 300,
    );
    return KostvMusicTaste.of(songs);
  }

  /// The songs of the album [albumId], in their order.
  Future<List<AggregatedItem>> albumSongs(String albumId) async => _items(
    await _client.itemsApi.getItems(
      parentId: albumId,
      includeItemTypes: const ['Audio'],
      sortBy: 'ParentIndexNumber,IndexNumber,SortName',
      fields: _fields,
    ),
  );

  /// The songs the person marked with ♥, the ones played lately first.
  Future<List<AggregatedItem>> favoriteSongs({int limit = 60}) => _get(
    types: const ['Audio'],
    filters: const ['IsFavorite'],
    sortBy: 'DatePlayed,SortName',
    descending: true,
    limit: limit,
  );

  /// The person's music playlists (Jellyfin's), the latest first.
  Future<List<AggregatedItem>> playlists({int limit = 30}) async {
    final found = await _get(
      types: const ['Playlist'],
      sortBy: 'DateCreated,SortName',
      descending: true,
      limit: limit,
    );
    return [
      for (final list in found)
        if (list.rawData['MediaType'] == null ||
            list.rawData['MediaType'] == 'Audio')
          list,
    ];
  }

  /// The albums added to the home server lately.
  Future<List<AggregatedItem>> newAlbums({int limit = 16}) => _get(
    types: const ['MusicAlbum'],
    sortBy: 'DateCreated,SortName',
    descending: true,
    limit: limit,
  );

  /// The home server's albums of [genre], in a different order each time.
  Future<List<AggregatedItem>> albumsOfGenre(String genre, {int limit = 16}) =>
      _get(
        types: const ['MusicAlbum'],
        sortBy: 'Random',
        genres: [genre],
        limit: limit,
      );

  /// The home server's albums of the artist [artistId].
  Future<List<AggregatedItem>> albumsOf(String artistId, {int limit = 16}) =>
      _get(
        types: const ['MusicAlbum'],
        sortBy: 'ProductionYear,SortName',
        descending: true,
        artistIds: [artistId],
        limit: limit,
      );

  /// A mix around [itemId] (an artist, an album or a song): songs that go
  /// with it, from the home server.
  Future<List<AggregatedItem>> mix(String itemId, {int limit = 60}) async =>
      _items(await _client.instantMixApi.getInstantMix(itemId, limit: limit));

  /// Songs, albums and artists of the home server matching [query].
  Future<KostvMusicAtHome> search(String query) async {
    final results = await Future.wait([
      _get(types: const ['Audio'], searchTerm: query, limit: 12),
      _get(types: const ['MusicAlbum'], searchTerm: query, limit: 16),
      _get(types: const ['MusicArtist'], searchTerm: query, limit: 8),
    ]);
    return KostvMusicAtHome(
      songs: results[0],
      albums: results[1],
      artists: results[2],
    );
  }

  /// The home server's copy of a song known by its [title] and [artist]
  /// (a chart's, which has no id of the home server), or null.
  Future<AggregatedItem?> findSong(String title, String? artist) async {
    final found = await _get(
      types: const ['Audio'],
      searchTerm: kostvMusicSearchable(title),
      limit: 20,
    );
    return kostvBestSong(found, title, artist);
  }
}

/// Kos TV: what the person listens to most.
@immutable
class KostvMusicTaste {
  const KostvMusicTaste({this.artists = const [], this.genres = const []});

  /// Their artists, the most played first: id and name.
  final List<({String id, String name})> artists;

  /// Their genres, the most played first.
  final List<String> genres;

  bool get isEmpty => artists.isEmpty && genres.isEmpty;

  /// Counted from [songs], each by how many times it was played.
  factory KostvMusicTaste.of(List<AggregatedItem> songs) {
    final artistPlays = <String, int>{};
    final artistNames = <String, String>{};
    final genrePlays = <String, int>{};
    for (final song in songs) {
      final data = song.rawData['UserData'];
      final plays = data is Map ? (data['PlayCount'] as num?)?.toInt() ?? 1 : 1;
      final artists =
          song.rawData['AlbumArtists'] ?? song.rawData['ArtistItems'];
      if (artists is List && artists.isNotEmpty && artists.first is Map) {
        final first = artists.first as Map;
        final id = first['Id']?.toString();
        final name = first['Name']?.toString();
        if (id != null && name != null && name.isNotEmpty) {
          artistPlays[id] = (artistPlays[id] ?? 0) + plays;
          artistNames[id] = name;
        }
      }
      final genres = song.rawData['Genres'];
      if (genres is List) {
        for (final genre in genres.whereType<String>()) {
          genrePlays[genre] = (genrePlays[genre] ?? 0) + plays;
        }
      }
    }
    List<String> ranked(Map<String, int> plays) =>
        (plays.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .map((e) => e.key)
            .toList();
    return KostvMusicTaste(
      artists: [
        for (final id in ranked(artistPlays)) (id: id, name: artistNames[id]!),
      ],
      genres: ranked(genrePlays),
    );
  }

  /// The charts' genre for the person's favourite genre, if there is one:
  /// `latino`, `pop`, `hiphop`, `rock`, `dance`, `electronica`,
  /// `alternativa`, `rnb`, `reggae` or `bandas-sonoras`.
  String? get chartGenre {
    for (final genre in genres) {
      final chart = kostvChartGenreOf(genre);
      if (chart != null) return chart;
    }
    return null;
  }
}

/// Kos TV: the music of the home server matching a search.
@immutable
class KostvMusicAtHome {
  const KostvMusicAtHome({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
  });

  final List<AggregatedItem> songs;
  final List<AggregatedItem> albums;
  final List<AggregatedItem> artists;

  bool get isEmpty => songs.isEmpty && albums.isEmpty && artists.isEmpty;
}

/// Kos TV: the charts' genre for one of the home server's genre names
/// (they come from the files' tags, in any language), or null.
String? kostvChartGenreOf(String genre) {
  final g = genre.toLowerCase();
  bool any(List<String> words) => words.any(g.contains);
  if (any([
    'latin',
    'reggaeton',
    'reguet',
    'urbano',
    'bachata',
    'salsa',
    'cumbia',
    'flamenco',
  ])) {
    return 'latino';
  }
  if (any(['hip hop', 'hip-hop', 'hiphop', 'rap', 'trap'])) return 'hiphop';
  if (any(['r&b', 'rnb', 'soul'])) return 'rnb';
  if (any(['reggae'])) return 'reggae';
  if (any(['soundtrack', 'banda sonora', 'bandas sonoras', 'score'])) {
    return 'bandas-sonoras';
  }
  if (any(['electro', 'techno', 'house', 'edm'])) return 'electronica';
  if (any(['dance', 'disco'])) return 'dance';
  if (any(['alternativ', 'indie'])) return 'alternativa';
  if (any(['rock', 'metal', 'punk'])) return 'rock';
  if (any(['pop'])) return 'pop';
  return null;
}

/// Kos TV: a title as the home server's search finds it: without what is
/// in brackets («(feat. …)», «[Remastered]») nor what follows a dash.
String kostvMusicSearchable(String title) {
  var t = title.replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), '');
  final dash = t.indexOf(' - ');
  if (dash > 0) t = t.substring(0, dash);
  return t.trim().isEmpty ? title : t.trim();
}

String _fold(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[áàä]'), 'a')
    .replaceAll(RegExp('[éèë]'), 'e')
    .replaceAll(RegExp('[íìï]'), 'i')
    .replaceAll(RegExp('[óòö]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .replaceAll(RegExp(r'[^a-z0-9ñ]+'), ' ')
    .trim();

/// Kos TV: of [found], the song that is [title] by [artist], or null.
@visibleForTesting
AggregatedItem? kostvBestSong(
  List<AggregatedItem> found,
  String title,
  String? artist,
) {
  final wanted = _fold(kostvMusicSearchable(title));
  // A chart names everyone on it («KAROL G, Judeline & rusowsky»).
  final wantedArtists = artist == null
      ? const <String>[]
      : [
          for (final name in artist.split(
            RegExp(r',|&| x | y | feat\.? | ft\.? '),
          ))
            if (_fold(name).isNotEmpty) _fold(name),
        ];
  AggregatedItem? sameTitle;
  for (final song in found) {
    if (_fold(kostvMusicSearchable(song.name)) != wanted) continue;
    sameTitle ??= song;
    final names = [
      ...?(song.rawData['Artists'] as List?)?.whereType<String>(),
      ?song.rawData['AlbumArtist']?.toString(),
    ].map(_fold).join(' ');
    if (wantedArtists.isEmpty || wantedArtists.any(names.contains)) {
      return song;
    }
  }
  return wantedArtists.isEmpty ? sameTitle : null;
}
