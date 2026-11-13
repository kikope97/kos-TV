part of 'stremfin_models.dart';

// Kos TV: the music the requests service knows of (Deezer's albums and
// songs, Apple's charts for Spain), whether the home server has it, and what
// to ask for to get it. Songs are never asked for on their own: the house's
// rule is the whole album whenever there is one, and the service asks for it.

/// An album, EP or single.
enum StremfinAlbumKind {
  album,
  ep,
  single;

  static StremfinAlbumKind fromApi(Object? value) => switch (value) {
    'ep' => ep,
    'single' => single,
    _ => album,
  };
}

/// Where an album on its way to the home server is.
@immutable
class StremfinAlbumDownload {
  const StremfinAlbumDownload({this.phase, this.label, this.percent});

  /// `sent`, `queued`, `downloading`, `importing` or `failed`.
  final String? phase;

  /// The service's words for it.
  final String? label;
  final int? percent;

  bool get failed => phase == 'failed';

  static StremfinAlbumDownload? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return StremfinAlbumDownload(
      phase: _text(raw['phase']),
      label: _text(raw['label']),
      percent: _int(raw['percent'])?.clamp(0, 100),
    );
  }
}

/// An album as the service sees it (7.6 of its API).
@immutable
class StremfinAlbum {
  const StremfinAlbum({
    required this.title,
    this.deezerId,
    this.artist,
    this.cover,
    this.tracks,
    this.kind = StremfinAlbumKind.album,
    this.releaseDate,
    this.rank,
    this.inJellyfin = false,
    this.songInAlbum,
    this.download,
    this.contains,
    this.request,
    this.canRequest = false,
    this.upcoming = false,
    this.people,
    this.jellyfinId,
    this.reason,
  });

  /// Null for one Deezer doesn't have: it can't be asked for.
  final String? deezerId;
  final String title;
  final String? artist;
  final String? cover;
  final int? tracks;
  final StremfinAlbumKind kind;
  final String? releaseDate;
  final int? rank;

  /// On the home server (a single whose song is in an album there counts).
  final bool inJellyfin;

  /// A single whose song the home server has in an album: that album.
  final String? songInAlbum;

  /// On its way to the home server.
  final StremfinAlbumDownload? download;

  /// The song it comes up for (the one searched for, or a chart's).
  final String? contains;
  final StremfinRequestRef? request;

  /// It can be asked for, and the person hasn't yet.
  final bool canRequest;

  /// Announced, not out yet (the house's artists' releases).
  final bool upcoming;

  /// How many in the house asked for it (most requested).
  final int? people;

  /// Its id on the home server, to open it there (since 1.91.0). Null for a
  /// single that is only at home inside an album: play its song instead.
  final String? jellyfinId;

  /// Why it is recommended: «Porque escuchas a …».
  final String? reason;

  int? get year => int.tryParse((releaseDate ?? '').split('-').first);

  static StremfinAlbum? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = _text(raw['title']);
    if (title == null) return null;
    final library = raw['library'];
    return StremfinAlbum(
      deezerId: _text(raw['deezer_id']?.toString()),
      title: title,
      artist: _text(raw['artist']),
      cover: _https(raw['cover']),
      tracks: _int(raw['tracks']),
      kind: StremfinAlbumKind.fromApi(raw['kind']),
      releaseDate: _text(raw['release_date']),
      rank: _int(raw['rank']),
      inJellyfin: library is Map && library['in_jellyfin'] == true,
      songInAlbum: library is Map ? _text(library['song_in_album']) : null,
      download: StremfinAlbumDownload.fromJson(raw['download']),
      contains: _text(raw['contains']),
      request: StremfinRequestRef.fromJson(raw['request']),
      canRequest: raw['can_request'] == true,
      upcoming: raw['upcoming'] == true,
      people: _int(raw['people']),
      jellyfinId: library is Map
          ? _text(library['jellyfin_id']?.toString())
          : null,
      reason: _text(raw['reason']),
    );
  }
}

/// A song: from Deezer (searches, an artist's top) or from one of Apple's
/// charts (no Deezer id, with the album to ask for).
@immutable
class StremfinSong {
  const StremfinSong({
    required this.title,
    this.deezerId,
    this.artist,
    this.artistDeezerId,
    this.duration,
    this.preview,
    this.explicit = false,
    this.cover,
    this.albumTitle,
    this.albumDeezerId,
    this.album,
    this.inJellyfin = false,
    this.inAlbum,
    this.rank,
    this.jellyfinId,
    this.albumJellyfinId,
    this.reason,
  });

  /// Deezer's id, for its page. Null for a chart's song.
  final String? deezerId;
  final String title;
  final String? artist;
  final String? artistDeezerId;

  /// Seconds.
  final int? duration;

  /// Thirty seconds to listen to before asking. Expires: use at once.
  final String? preview;
  final bool explicit;
  final String? cover;
  final String? albumTitle;
  final String? albumDeezerId;

  /// A chart's song: its album, to ask for (it may be a single, whose page
  /// says which album to ask for instead).
  final StremfinAlbum? album;

  /// The home server has it, and in which album.
  final bool inJellyfin;
  final String? inAlbum;

  /// Its place in a chart.
  final int? rank;

  /// The song and its album on the home server (since 1.91.0), to play it
  /// there at once.
  final String? jellyfinId;
  final String? albumJellyfinId;

  /// Why it is recommended.
  final String? reason;

  static StremfinSong? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = _text(raw['title']);
    if (title == null) return null;
    final small = raw['album'];
    // A chart's song brings its whole album (to ask for); a Deezer song only
    // where it sits.
    final album = small is Map && small.containsKey('can_request')
        ? StremfinAlbum.fromJson(small)
        : null;
    return StremfinSong(
      deezerId: _text(raw['deezer_id']?.toString()),
      title: title,
      artist: _text(raw['artist']),
      artistDeezerId: _text(raw['artist_deezer_id']?.toString()),
      duration: _int(raw['duration']),
      preview: _https(raw['preview']),
      explicit: raw['explicit'] == true,
      cover:
          _https(raw['cover']) ??
          (small is Map ? _https(small['cover']) : null),
      albumTitle: small is Map ? _text(small['title']) : null,
      albumDeezerId: small is Map
          ? _text(small['deezer_id']?.toString())
          : null,
      album: album,
      inJellyfin: raw['in_jellyfin'] == true,
      inAlbum: _text(raw['in_album']),
      rank: _int(raw['rank']),
      jellyfinId: _text(raw['jellyfin_id']?.toString()),
      albumJellyfinId: _text(raw['album_jellyfin_id']?.toString()),
      reason: _text(raw['reason']),
    );
  }
}

/// An artist.
@immutable
class StremfinArtist {
  const StremfinArtist({
    required this.deezerId,
    required this.name,
    this.picture,
    this.albums,
    this.fans,
  });

  final String deezerId;
  final String name;
  final String? picture;
  final int? albums;
  final int? fans;

  static StremfinArtist? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _text(raw['deezer_id']?.toString());
    final name = _text(raw['name']);
    if (id == null || name == null) return null;
    return StremfinArtist(
      deezerId: id,
      name: name,
      picture: _https(raw['picture']),
      albums: _int(raw['albums']),
      fans: _int(raw['fans']),
    );
  }
}

/// One of the charts there are.
@immutable
class StremfinChart {
  const StremfinChart({
    required this.id,
    required this.name,
    required this.songs,
    this.genre,
    this.played = true,
  });

  final String id;
  final String name;

  /// A chart of songs (each with its album), or of albums.
  final bool songs;
  final String? genre;

  /// The most listened to; otherwise the most bought (the genre charts).
  final bool played;

  static StremfinChart? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _text(raw['id']);
    final name = _text(raw['name']);
    if (id == null || name == null) return null;
    return StremfinChart(
      id: id,
      name: name,
      songs: raw['kind'] == 'songs',
      genre: _text(raw['genre']),
      played: raw['measure'] != 'sold',
    );
  }
}

/// A chart's places: songs or albums.
@immutable
class StremfinChartPage {
  const StremfinChartPage({
    required this.chart,
    this.songs = const [],
    this.albums = const [],
  });

  final StremfinChart chart;
  final List<StremfinSong> songs;
  final List<StremfinAlbum> albums;

  static StremfinChartPage? fromJson(Object? raw) {
    final chart = StremfinChart.fromJson(raw);
    if (chart == null || raw is! Map) return null;
    final items = raw['items'];
    return StremfinChartPage(
      chart: chart,
      songs: chart.songs
          ? [
              if (items is List)
                for (final item in items) ?StremfinSong.fromJson(item),
            ]
          : const [],
      albums: chart.songs
          ? const []
          : [
              if (items is List)
                for (final item in items) ?StremfinAlbum.fromJson(item),
            ],
    );
  }
}

/// A music search: the artists, songs and albums that match.
@immutable
class StremfinMusicSearch {
  const StremfinMusicSearch({
    this.artists = const [],
    this.songs = const [],
    this.albums = const [],
    this.nextCursor,
  });

  final List<StremfinArtist> artists;
  final List<StremfinSong> songs;
  final List<StremfinAlbum> albums;
  final String? nextCursor;

  static StremfinMusicSearch fromJson(Object? raw) {
    if (raw is! Map) return const StremfinMusicSearch();
    List<T> list<T>(Object? items, T? Function(Object?) of) => [
      if (items is List)
        for (final item in items) ?of(item),
    ];
    return StremfinMusicSearch(
      artists: list(raw['artists'], StremfinArtist.fromJson),
      songs: list(raw['songs'], StremfinSong.fromJson),
      albums: list(raw['items'], StremfinAlbum.fromJson),
      nextCursor: _text(raw['next_cursor']?.toString()),
    );
  }
}

/// One song of an album's page.
@immutable
class StremfinAlbumTrack {
  const StremfinAlbumTrack({
    required this.title,
    this.position,
    this.disc,
    this.artist,
    this.duration,
    this.inJellyfin = false,
    this.inAlbum,
    this.jellyfinId,
  });

  final String title;
  final int? position;
  final int? disc;
  final String? artist;
  final int? duration;
  final bool inJellyfin;
  final String? inAlbum;

  /// The song on the home server (since 1.91.0).
  final String? jellyfinId;

  static StremfinAlbumTrack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = _text(raw['title']);
    if (title == null) return null;
    return StremfinAlbumTrack(
      title: title,
      position: _int(raw['position']),
      disc: _int(raw['disc']),
      artist: _text(raw['artist']),
      duration: _int(raw['duration']),
      inJellyfin: raw['in_jellyfin'] == true,
      inAlbum: _text(raw['in_album']),
      jellyfinId: _text(raw['jellyfin_id']?.toString()),
    );
  }
}

/// An album's page: the album, its songs, and (for a single whose song is
/// in an album) the album to ask for instead.
@immutable
class StremfinAlbumDetail {
  const StremfinAlbumDetail({
    required this.album,
    this.artistDeezerId,
    this.label,
    this.genres = const [],
    this.duration,
    this.songs = const [],
    this.songsHave = 0,
    this.albumInstead,
  });

  final StremfinAlbum album;
  final String? artistDeezerId;
  final String? label;
  final List<String> genres;

  /// Seconds, all of it.
  final int? duration;
  final List<StremfinAlbumTrack> songs;
  final int songsHave;
  final StremfinAlbum? albumInstead;

  static StremfinAlbumDetail? fromJson(Object? raw) {
    final album = StremfinAlbum.fromJson(raw);
    if (album == null || raw is! Map) return null;
    final songs = raw['songs'];
    return StremfinAlbumDetail(
      album: album,
      artistDeezerId: _text(raw['artist_deezer_id']?.toString()),
      label: _text(raw['label']),
      genres: _texts(raw['genres']),
      duration: _int(raw['duration']),
      songs: [
        if (songs is List)
          for (final song in songs) ?StremfinAlbumTrack.fromJson(song),
      ],
      songsHave: _int(raw['songs_have']) ?? 0,
      albumInstead: StremfinAlbum.fromJson(raw['album_instead']),
    );
  }
}

/// An artist's page: who they are, their records, best songs and similar
/// artists.
@immutable
class StremfinArtistDetail {
  const StremfinArtistDetail({
    required this.artist,
    this.albums = const [],
    this.topSongs = const [],
    this.related = const [],
    this.have = 0,
    this.total = 0,
  });

  final StremfinArtist artist;
  final List<StremfinAlbum> albums;
  final List<StremfinSong> topSongs;
  final List<StremfinArtist> related;
  final int have;
  final int total;

  static StremfinArtistDetail? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final artist = StremfinArtist.fromJson(raw['artist']);
    if (artist == null) return null;
    final summary = raw['summary'];
    List<T> list<T>(Object? items, T? Function(Object?) of) => [
      if (items is List)
        for (final item in items) ?of(item),
    ];
    return StremfinArtistDetail(
      artist: artist,
      albums: list(raw['items'], StremfinAlbum.fromJson),
      topSongs: list(raw['top_songs'], StremfinSong.fromJson),
      related: list(raw['related'], StremfinArtist.fromJson),
      have: summary is Map ? _int(summary['have']) ?? 0 : 0,
      total: summary is Map ? _int(summary['total']) ?? 0 : 0,
    );
  }
}

/// A song's page: the album to ask for to have it.
@immutable
class StremfinSongDetail {
  const StremfinSongDetail({
    required this.song,
    this.album,
    this.albumInstead,
    this.ask,
  });

  final StremfinSong song;
  final StremfinAlbum? album;
  final StremfinAlbum? albumInstead;

  /// The Deezer id to ask for: the whole album when there is one.
  final String? ask;

  /// The album that is asked for.
  StremfinAlbum? get toAsk => albumInstead ?? album;

  static StremfinSongDetail? fromJson(Object? raw) {
    final song = StremfinSong.fromJson(raw);
    if (song == null || raw is! Map) return null;
    return StremfinSongDetail(
      song: song,
      album: StremfinAlbum.fromJson(raw['album']),
      albumInstead: StremfinAlbum.fromJson(raw['album_instead']),
      ask: _text(raw['ask']?.toString()),
    );
  }
}

/// Kos TV: «Para ti»: records and songs of artists like the ones the person
/// listens to, with why (since 1.91.0).
@immutable
class StremfinRecommendations {
  const StremfinRecommendations({
    this.seeds = const [],
    this.albums = const [],
    this.songs = const [],
  });

  /// The artists asked with, as Deezer knows them (id null when it doesn't).
  final List<({String name, String? deezerId})> seeds;
  final List<StremfinAlbum> albums;
  final List<StremfinSong> songs;

  static StremfinRecommendations fromJson(Object? raw) {
    if (raw is! Map) return const StremfinRecommendations();
    final seeds = raw['seeds'];
    final items = raw['items'];
    final songs = raw['songs'];
    return StremfinRecommendations(
      seeds: [
        if (seeds is List)
          for (final seed in seeds.whereType<Map>())
            if (_text(seed['name']) case final name?)
              (name: name, deezerId: _text(seed['deezer_id']?.toString())),
      ],
      albums: [
        if (items is List)
          for (final item in items) ?StremfinAlbum.fromJson(item),
      ],
      songs: [
        if (songs is List)
          for (final song in songs) ?StremfinSong.fromJson(song),
      ],
    );
  }
}
