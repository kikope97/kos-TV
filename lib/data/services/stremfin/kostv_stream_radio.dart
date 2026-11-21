import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../models/aggregated_item.dart';
import '../kostv_music_dislikes.dart';
import '../kostv_music_plugin.dart' show KostvMusicDislikes;
import 'kostv_stream_song.dart';
import 'stremfin_models.dart';
import 'stremfin_service.dart';

/// Kos TV: the radio with what isn't at home («Toda la música»,
/// `docs/musica-toda-la-musica.md` §2): «Crear emisora», the endless play
/// (∞) and the daily mixes mix the home server's songs with those of the
/// requests service's radio (`GET /music/radio`, 8.34), so a station of an
/// artist the house has little of still goes on.
///
/// The service allows ten radios and recommendations a minute between them
/// all: each set of artists is asked once per session ([KostvStreamRadio]),
/// and each mix's extra songs once a day ([KostvMixExtras]).

/// Kos TV: the artist a song is told apart by when nothing of the same one
/// should sound twice in a row: its first own artist (its album's when it
/// names none), as the lists compare them.
String kostvSongArtistKey(AggregatedItem item) {
  final names = kostvMusicArtistNames(item);
  final name =
      names.firstOrNull ??
      item.artists.where((a) => a.trim().isNotEmpty).firstOrNull ??
      item.albumArtist ??
      '';
  return name.trim().toLowerCase();
}

/// Kos TV: what tells two songs apart across the home server and the
/// requests service (their ids differ): the title and the artist.
String kostvSongKey(AggregatedItem item) =>
    '${item.name.trim().toLowerCase()}|${kostvSongArtistKey(item)}';

/// Kos TV: [home] and [away] taken in turns (one of home, one from away…),
/// each song once (by id, and by title and artist), never two of the same
/// artist in a row when another can go there instead. What is left of one
/// when the other runs out goes after, with the same care.
List<AggregatedItem> kostvInterleaveRadio(
  List<AggregatedItem> home,
  List<AggregatedItem> away, {
  Set<String> skip = const {},
}) {
  final seenIds = {...skip};
  final seenKeys = <String>{};
  List<AggregatedItem> fresh(List<AggregatedItem> list) => [
    for (final item in list)
      if (seenIds.add(item.id) && seenKeys.add(kostvSongKey(item))) item,
  ];
  final lists = [fresh(home), fresh(away)];
  final result = <AggregatedItem>[];
  var turn = lists[0].isNotEmpty ? 0 : 1;
  String? last;
  while (lists[0].isNotEmpty || lists[1].isNotEmpty) {
    AggregatedItem? picked;
    for (final which in [turn, 1 - turn]) {
      final list = lists[which];
      final at = list.indexWhere((s) => kostvSongArtistKey(s) != last);
      if (at >= 0) {
        picked = list.removeAt(at);
        turn = 1 - which;
        break;
      }
    }
    if (picked == null) {
      // Only that artist left: it goes on anyway.
      final list = lists[turn].isNotEmpty ? lists[turn] : lists[1 - turn];
      picked = list.removeAt(0);
      turn = 1 - turn;
    }
    result.add(picked);
    last = kostvSongArtistKey(picked);
  }
  return result;
}

/// Kos TV: how many songs that aren't at home go into a mix of [homeSongs]
/// songs: about a quarter of the whole (one for every three of home), up
/// to twelve.
int kostvMixExtraCount(int homeSongs) => homeSongs < 3
    ? (homeSongs > 0 ? 1 : 0)
    : (homeSongs / 3).round().clamp(1, 12);

/// Kos TV: [base] (a mix, in its order) with [extras] spread through it
/// evenly, never at the start and, where it can be helped, with neither
/// neighbour by the same artist.
List<AggregatedItem> kostvSpreadExtras(
  List<AggregatedItem> base,
  List<AggregatedItem> extras,
) {
  if (extras.isEmpty || base.isEmpty) return [...base, ...extras];
  final result = [...base];
  final gap = base.length / extras.length;
  for (final (j, extra) in extras.indexed) {
    // Where it would go evenly, counting the extras already in.
    final wanted = (((j + 1) * gap).round() + j).clamp(1, result.length);
    final artist = kostvSongArtistKey(extra);
    bool fits(int at) =>
        (at == 0 || kostvSongArtistKey(result[at - 1]) != artist) &&
        (at >= result.length || kostvSongArtistKey(result[at]) != artist);
    var at = wanted;
    for (final shift in const [0, 1, -1, 2, -2, 3, -3]) {
      final candidate = wanted + shift;
      if (candidate < 1 || candidate > result.length) continue;
      if (fits(candidate)) {
        at = candidate;
        break;
      }
    }
    result.insert(at, extra);
  }
  return result;
}

/// Kos TV: the requests service's radio of a set of artists, asked once per
/// session for each set (the service allows ten a minute between radios
/// and recommendations): the endless play asks for it whenever the song
/// sounding changes artist. After it says no (too many asked, not
/// answering), it is left alone a minute.
class KostvStreamRadio {
  KostvStreamRadio({
    Future<StremfinRadio> Function(
      List<String> artists, {
      List<String> artistIds,
      String? only,
      int? limit,
    })?
    fetch,
    String Function()? who,
    DateTime Function()? clock,
  }) : _fetch = fetch ?? _serviceRadio,
       _who = who ?? _signedIn,
       _clock = clock ?? DateTime.now;

  static Future<StremfinRadio> _serviceRadio(
    List<String> artists, {
    List<String> artistIds = const [],
    String? only,
    int? limit,
  }) {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) {
      return Future.error(StateError('no requests service'));
    }
    return getIt<StremfinService>().musicRadio(
      artists,
      deezerArtistIds: artistIds,
      only: only,
      limit: limit,
    );
  }

  /// Whose the radios kept are: another person signed in gets their own.
  static String _signedIn() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<MediaServerClient>()) return '';
    final client = getIt<MediaServerClient>();
    return '${client.baseUrl}|${client.userId}';
  }

  /// The app's own; set up with the requests service at start.
  static KostvStreamRadio instance = KostvStreamRadio();

  final Future<StremfinRadio> Function(
    List<String> artists, {
    List<String> artistIds,
    String? only,
    int? limit,
  })
  _fetch;
  final String Function() _who;
  final DateTime Function() _clock;

  final _kept = <String, List<StremfinSong>>{};
  final _asking = <String, Future<List<StremfinSong>>>{};
  DateTime? _quietUntil;

  /// How long it is left alone after the service said no.
  static const quiet = Duration(minutes: 1);

  /// How many calls went to the service (for tests).
  @visibleForTesting
  int calls = 0;

  static String _fold(String s) => s.trim().toLowerCase();

  /// The songs of the radio of [artists] (names) and [artistIds] (Deezer's),
  /// [only] as the service takes it (`all`, `missing`, `available`). Empty
  /// when there is nothing to ask with; throws when the service couldn't
  /// answer (nothing is kept then).
  Future<List<StremfinSong>> songs({
    List<String> artists = const [],
    List<String> artistIds = const [],
    String only = 'all',
    int? limit,
  }) {
    final fetch = _fetch;
    final names = {
      for (final name in artists)
        if (name.trim().isNotEmpty) name.trim(),
    }.take(10).toList();
    final ids = {
      for (final id in artistIds)
        if (id.trim().isNotEmpty) id.trim(),
    }.take(10).toList();
    if (names.isEmpty && ids.isEmpty) {
      return Future.value(const []);
    }
    final key = [
      _who(),
      ([...names.map(_fold)]..sort()).join(','),
      ([...ids]..sort()).join(','),
      only,
      limit ?? '',
    ].join('|');
    final kept = _kept[key];
    if (kept != null) return Future.value(kept);
    final pending = _asking[key];
    if (pending != null) return pending;
    final quietUntil = _quietUntil;
    if (quietUntil != null && _clock().isBefore(quietUntil)) {
      return Future.error(StateError('radio resting'));
    }
    calls++;
    late final Future<List<StremfinSong>> future;
    future = fetch(names, artistIds: ids, only: only, limit: limit)
        .then((found) => _kept[key] = found.songs)
        .catchError((Object e) {
          _quietUntil = _clock().add(quiet);
          throw e;
        })
        .whenComplete(() {
          if (identical(_asking[key], future)) _asking.remove(key);
        });
    return _asking[key] = future;
  }

  @visibleForTesting
  void debugReset() {
    _kept.clear();
    _asking.clear();
    _quietUntil = null;
    calls = 0;
  }
}

/// Kos TV: a station around a seed, mixing the home server's own mix
/// ([homeMix], Jellyfin's InstantMix of a song at home; none for one that
/// isn't) with the requests service's radio of the seed's artists
/// ([artists] by name, [artistIds] by Deezer's id). With [includeAway] (the
/// person listens to all the music) the radio's songs that aren't at home
/// go in too; otherwise only those of it that are at home. Without what the
/// person doesn't want to hear ([dislikes]) nor, for someone with a limit
/// ([hideExplicit]), what is explicit and not at home; [skip] are ids
/// already in the queue. The seed itself isn't in it.
Future<List<AggregatedItem>> kostvStationOf({
  required KostvStreamRadio radio,
  required String serverId,
  required bool includeAway,
  required bool hideExplicit,
  required Future<List<AggregatedItem>> Function(List<String> ids) homeItems,
  KostvMusicDislikes dislikes = KostvMusicDislikes.empty,
  Future<List<AggregatedItem>> Function()? homeMix,
  List<String> artists = const [],
  List<String> artistIds = const [],
  AggregatedItem? seed,
  Set<String> skip = const {},
}) async {
  final mixing = homeMix == null
      ? Future.value(const <AggregatedItem>[])
      : homeMix().catchError((Object _) => const <AggregatedItem>[]);
  final radioing = radio
      .songs(
        artists: artists,
        artistIds: artistIds,
        only: includeAway ? 'all' : 'available',
      )
      .catchError((Object _) => const <StremfinSong>[]);
  final mix = await mixing;
  final found = dislikes.stremfinSongsIn(await radioing);
  // The radio's songs at home, as the home server's; the rest as songs that
  // aren't at home (with «Toda la música»).
  final queued = await kostvQueueOf(
    [
      for (final song in found)
        if (includeAway || kostvSongWayOf(song) == KostvSongWay.home)
          KostvQueueSong.ofSong(song, serverId: serverId),
    ],
    hideExplicit: hideExplicit,
    homeItems: homeItems,
  );
  final radioHome = [
    for (final item in queued.items)
      if (!isKostvStream(item)) item,
  ];
  final radioAway = [
    for (final item in queued.items)
      if (isKostvStream(item)) item,
  ];
  final skipAll = {...skip, ?seed?.id};
  final seedKey = seed == null ? null : kostvSongKey(seed);
  bool keep(AggregatedItem item) =>
      !dislikes.songOut(item) && kostvSongKey(item) != seedKey;
  // The home server's own mix first, its songs from the radio after them.
  final home = [...mix, ...radioHome].where(keep).toList();
  final away = radioAway.where(keep).toList();
  return kostvInterleaveRadio(home, away, skip: skipAll);
}

/// Kos TV: the extra songs that aren't at home each daily mix (and the mix
/// of the time of day) gets with «Toda la música»: about a quarter of it,
/// from the requests service's radio of the artists the mix is of (its
/// `Because`), not at home, not already in it. Picked once a day for each
/// mix and kept on the device ([load], [save]: the person's own notes of
/// the Music page), so the mix doesn't change every time it is opened and
/// the radio is asked once a day for it at most, also when it gave
/// nothing.
class KostvMixExtras {
  KostvMixExtras({required this.radio, this.load, this.save});

  final KostvStreamRadio radio;

  /// Reads and keeps the picked songs on the device.
  final Future<Object?> Function()? load;
  final void Function(Object value)? save;

  /// The day kept and each mix's songs of it (as the queue takes them).
  String? _day;
  final _mixes = <String, List<Map<String, Object?>>>{};
  Future<void>? _loaded;
  final _asking = <String, Future<void>>{};

  /// The note's name on the device.
  static const note = 'mix-extras';

  Future<void> _ensureLoaded() => _loaded ??= () async {
    try {
      final raw = await load?.call();
      if (raw is Map && raw['day'] is String && raw['mixes'] is Map) {
        _day = raw['day'] as String;
        for (final entry in (raw['mixes'] as Map).entries) {
          final list = entry.value;
          if (list is! List) continue;
          _mixes['${entry.key}'] = [
            for (final song in list.whereType<Map>())
              song.map((k, v) => MapEntry('$k', v)),
          ];
        }
      }
    } catch (_) {}
  }();

  void _keep() {
    final day = _day;
    if (day == null) return;
    save?.call({'day': day, 'mixes': _mixes});
  }

  /// [mix] (its [items] at home, by the artists [because]) with its extra
  /// songs for [day] spread through it. As it is when there is nothing to
  /// add or the radio can't be asked.
  Future<List<AggregatedItem>> mixWith({
    required String mixId,
    required String day,
    required List<String> because,
    required List<AggregatedItem> items,
    required String serverId,
    required bool hideExplicit,
    KostvMusicDislikes dislikes = KostvMusicDislikes.empty,
  }) async {
    if (items.isEmpty) return items;
    await _ensureLoaded();
    if (_day != day) {
      _day = day;
      _mixes.clear();
    }
    if (!_mixes.containsKey(mixId) && because.isNotEmpty) {
      await (_asking[mixId] ??=
          _pick(
            mixId: mixId,
            day: day,
            because: because,
            items: items,
            serverId: serverId,
          ).whenComplete(() {
            _asking.remove(mixId);
          }));
    }
    final kept = _mixes[mixId] ?? const [];
    final known = {for (final item in items) kostvSongKey(item)};
    final extras = <AggregatedItem>[];
    for (final raw in kept) {
      final item = _itemOf(raw, serverId);
      if (item == null) continue;
      final info = KostvStreamInfo.of(item);
      if (hideExplicit && (info?.explicit ?? false)) continue;
      if (dislikes.songOut(item) || !known.add(kostvSongKey(item))) continue;
      extras.add(item);
    }
    return kostvSpreadExtras(items, extras);
  }

  Future<void> _pick({
    required String mixId,
    required String day,
    required List<String> because,
    required List<AggregatedItem> items,
    required String serverId,
  }) async {
    final List<StremfinSong> found;
    try {
      found = await radio.songs(artists: because, only: 'missing');
    } catch (_) {
      // Not answered: asked again next time (the radio rests a minute).
      return;
    }
    if (_day != day) return;
    final known = {for (final item in items) kostvSongKey(item)};
    final wanted = kostvMixExtraCount(items.length);
    final picked = <Map<String, Object?>>[];
    for (final song in found) {
      if (picked.length >= wanted) break;
      if (song.atHome) continue;
      final item = kostvStreamItemFromSong(song, serverId: serverId);
      if (item == null || !known.add(kostvSongKey(item))) continue;
      picked.add({'id': item.id, 'raw': item.rawData});
    }
    _mixes[mixId] = picked;
    _keep();
  }

  static AggregatedItem? _itemOf(Map<String, Object?> raw, String serverId) {
    final id = raw['id'];
    final data = raw['raw'];
    if (id is! String || !isKostvStreamId(id) || data is! Map) return null;
    return AggregatedItem(
      id: id,
      serverId: serverId,
      rawData: data.map((k, v) => MapEntry('$k', v)),
    );
  }

  @visibleForTesting
  void debugReset() {
    _day = null;
    _mixes.clear();
    _loaded = null;
    _asking.clear();
  }
}
