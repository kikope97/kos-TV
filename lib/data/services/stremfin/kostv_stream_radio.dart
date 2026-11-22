import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../models/aggregated_item.dart';
import '../kostv_music_dislikes.dart';
import '../kostv_music_plugin.dart' show KostvMusicDislikes, KostvMusicStation;
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
/// all: each set of artists is asked once an hour ([KostvStreamRadio]),
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

/// Kos TV: [songs] of a station in their own order (home and away as the
/// station puts them, never taken in turns: `docs/musica-radio.md`, fase
/// 1), each song once (by id, and by title and artist), and never two of
/// the same artist in a row when another can go there instead: the first
/// one after it by someone else goes first, the rest keep their order.
/// [skip] are ids and [skipKeys] [kostvSongKey]s already in the queue.
List<AggregatedItem> kostvRadioInOrder(
  List<AggregatedItem> songs, {
  Set<String> skip = const {},
  Set<String> skipKeys = const {},
}) {
  final seenIds = {...skip};
  final seenKeys = {...skipKeys};
  final left = [
    for (final item in songs)
      if (seenIds.add(item.id) && seenKeys.add(kostvSongKey(item))) item,
  ];
  final result = <AggregatedItem>[];
  String? last;
  while (left.isNotEmpty) {
    final at = left.indexWhere((s) => kostvSongArtistKey(s) != last);
    // Only that artist left: it goes on anyway.
    final picked = left.removeAt(at < 0 ? 0 : at);
    result.add(picked);
    last = kostvSongArtistKey(picked);
  }
  return result;
}

/// Kos TV: the songs of a station the server plugin made ([station],
/// `GET Music/Station`) as the queue takes them: each `Card` as the home
/// server's song, each `Away` (with «Toda la música», [includeAway]) as a
/// song that isn't at home, sounding through the requests service. The
/// plugin leaves out what the person can't or doesn't want to hear; this
/// keeps the app's own guard too: nothing of [dislikes], and for someone
/// with a limit ([hideExplicit]) nothing from away that is explicit or
/// doesn't say. Without the seed and what is in the queue ([skip] ids,
/// [skipKeys] [kostvSongKey]s), in the station's order ([kostvRadioInOrder]).
List<AggregatedItem> kostvStationFromPlugin(
  KostvMusicStation station, {
  required String serverId,
  required bool includeAway,
  required bool hideExplicit,
  KostvMusicDislikes dislikes = KostvMusicDislikes.empty,
  AggregatedItem? seed,
  Set<String> skip = const {},
  Set<String> skipKeys = const {},
}) {
  final seedKey = seed == null ? null : kostvSongKey(seed);
  final songs = <AggregatedItem>[];
  for (final entry in station.entries) {
    AggregatedItem? item = entry.card;
    final away = entry.away;
    if (item == null && away != null && includeAway) {
      if (hideExplicit && away.explicit != false) continue;
      final song = away.toSong();
      if (dislikes.stremfinSongOut(song)) continue;
      item = kostvStreamItemFromSong(song, serverId: serverId);
    }
    if (item == null || dislikes.songOut(item)) continue;
    if (kostvSongKey(item) == seedKey) continue;
    songs.add(item);
  }
  return kostvRadioInOrder(
    songs,
    skip: {...skip, ?seed?.id},
    skipKeys: skipKeys,
  );
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

/// Kos TV: the requests service's radio of a set of artists, asked once an
/// hour for each set (the service allows ten a minute between radios and
/// recommendations): the endless play asks for it whenever the song
/// sounding changes artist. After it says no (too many asked, not
/// answering), it is left alone a minute. What is kept is the person's as
/// the service says now (their age limit, once read, asks again: the
/// service keeps the radio itself an hour, so that costs no call).
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

  /// Whose the radios kept are: another person signed in gets their own,
  /// and so does the same one once their age limit is known (what was kept
  /// was cleaned with the limit of then).
  static String _signedIn() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<MediaServerClient>()) return '';
    final client = getIt<MediaServerClient>();
    final service = getIt.isRegistered<StremfinService>()
        ? getIt<StremfinService>()
        : null;
    return [
      client.baseUrl,
      client.userId,
      service?.generation ?? '',
      service?.hidesExplicitMusic ?? '',
    ].join('|');
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

  final _kept = <String, ({DateTime at, List<StremfinSong> songs})>{};
  final _asking = <String, Future<List<StremfinSong>>>{};
  DateTime? _quietUntil;

  /// How long it is left alone after the service said no.
  static const quiet = Duration(minutes: 1);

  /// How long a radio is kept: what comes home meanwhile is told then.
  static const keep = Duration(hours: 1);

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
    if (kept != null && _clock().difference(kept.at) < keep) {
      return Future.value(kept.songs);
    }
    final pending = _asking[key];
    if (pending != null) return pending;
    final quietUntil = _quietUntil;
    if (quietUntil != null && _clock().isBefore(quietUntil)) {
      return Future.error(StateError('radio resting'));
    }
    calls++;
    late final Future<List<StremfinSong>> future;
    future = fetch(names, artistIds: ids, only: only, limit: limit)
        .then((found) {
          // Kos TV: what has expired goes, rather than staying for good on a
          // TV left on for days (each set of artists, person and limit).
          final now = _clock();
          _kept
            ..removeWhere((_, v) => now.difference(v.at) >= keep)
            ..[key] = (at: now, songs: found.songs);
          return found.songs;
        })
        .catchError((Object e) {
          _quietUntil = _clock().add(quiet);
          throw e;
        })
        .whenComplete(() {
          if (identical(_asking[key], future)) _asking.remove(key);
        });
    return _asking[key] = future;
  }

  /// How many radios are kept (for tests).
  @visibleForTesting
  int get debugKeptCount => _kept.length;

  @visibleForTesting
  void debugReset() {
    _kept.clear();
    _asking.clear();
    _quietUntil = null;
    calls = 0;
  }
}

/// Kos TV: a station around a seed, as the app makes it when the server
/// plugin can't ([kostvStationFromPlugin]): the requests service's radio of
/// the seed's artists ([artists] by name, [artistIds] by Deezer's id), in
/// its order, and after it the home server's own mix ([homeMix],
/// Jellyfin's InstantMix of a song at home; none for one that isn't). With [includeAway] (the
/// person listens to all the music) the radio's songs that aren't at home
/// go in too; otherwise only those of it that are at home. Without what the
/// person doesn't want to hear ([dislikes]) nor, for someone with a limit
/// ([hideExplicit]), what is explicit and not at home; [skip] are ids
/// already in the queue, [skipKeys] their [kostvSongKey]s (the same song in
/// its other version). The seed itself isn't in it. Throws when a source
/// didn't answer and nothing came, so it is asked again.
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
  Set<String> skipKeys = const {},
}) async {
  Object? failure;
  final mixing = homeMix == null
      ? Future.value(const <AggregatedItem>[])
      : homeMix().catchError((Object e) {
          failure = e;
          return const <AggregatedItem>[];
        });
  final radioing = radio
      .songs(
        artists: artists,
        artistIds: artistIds,
        only: includeAway ? 'all' : 'available',
      )
      .catchError((Object e) {
        failure = e;
        return const <StremfinSong>[];
      });
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
    // Kos TV: only for someone with all the music and no limit.
    streamWhenHomeFails: includeAway && !hideExplicit,
  );
  final skipAll = {...skip, ?seed?.id};
  final seedKey = seed == null ? null : kostvSongKey(seed);
  bool keep(AggregatedItem item) =>
      !dislikes.songOut(item) && kostvSongKey(item) != seedKey;
  // Kos TV: the radio in its own order (what is at home and what isn't as
  // it gives them, not taken in turns), and the home server's own mix,
  // random within the genre, only after it: the last resort
  // (`docs/musica-radio.md`, fase 1).
  final station = kostvRadioInOrder(
    [...queued.items, ...mix].where(keep).toList(),
    skip: skipAll,
    skipKeys: skipKeys,
  );
  final failed = failure;
  if (station.isEmpty && failed != null) throw failed;
  return station;
}

/// Kos TV: the extra songs that aren't at home each daily mix (and the mix
/// of the time of day) gets with «Toda la música»: about a quarter of it,
/// from the requests service's radio of the artists the mix is of (its
/// `Because`), not at home, not already in it. Picked once a day for each
/// mix and kept on the device ([load], [save]: the person's own notes of
/// the Music page), so the mix doesn't change every time it is opened and
/// the radio is asked once a day for it at most, also when it gave
/// nothing.
///
/// Kos TV: each mix keeps the day it was picked for (the daily mixes' day
/// starts at 5:00, the moment's at midnight: neither undoes the other), and
/// each person's are read from and kept in their own note ([who] is the
/// person signed in now, whose note [load] and [save] go to).
class KostvMixExtras {
  KostvMixExtras({required this.radio, this.load, this.save, this.who});

  final KostvStreamRadio radio;

  /// Reads and keeps the picked songs on the device.
  final Future<Object?> Function()? load;
  final void Function(Object value)? save;

  /// The person signed in now (as [mixWith]'s `person`); null: whoever
  /// [mixWith] is asked for.
  final String Function()? who;

  /// Each person's mixes: the day each was picked for and its songs (as
  /// the queue takes them).
  final _people = <String, Map<String, _KeptMix>>{};
  final _loaded = <String, Future<void>>{};
  final _asking = <String, Future<void>>{};

  /// The note's name on the device.
  static const note = 'mix-extras';

  Map<String, _KeptMix> _mixesOf(String person) =>
      _people.putIfAbsent(person, () => {});

  bool _isNow(String person) => who == null || who!() == person;

  // Kos TV: only the note of the person it is read for, and nothing is
  // taken as read for someone who isn't signed in now (their note is read
  // when they are).
  Future<void> _ensureLoaded(String person) => !_isNow(person)
      ? Future.value()
      : _loaded[person] ??= () async {
          try {
            final raw = await load?.call();
            if (raw is! Map || raw['mixes'] is! Map) return;
            // A note of before kept one day for all its mixes.
            final noteDay = raw['day'];
            final mixes = _mixesOf(person);
            for (final entry in (raw['mixes'] as Map).entries) {
              final value = entry.value;
              final day = value is Map ? value['day'] : noteDay;
              final list = value is Map ? value['songs'] : value;
              if (day is! String || list is! List) continue;
              mixes.putIfAbsent(
                '${entry.key}',
                () => (
                  day: day,
                  songs: [
                    for (final song in list.whereType<Map>())
                      song.map((k, v) => MapEntry('$k', v)),
                  ],
                ),
              );
            }
          } catch (_) {}
        }();

  /// Keeps [person]'s mixes in their note: those of [day] and the day
  /// before (the two ways of counting days), not older ones.
  void _keep(String person, String day) {
    if (!_isNow(person)) return;
    final parsed = DateTime.tryParse(day);
    final before = parsed == null
        ? day
        : kostvDayOf(parsed.subtract(const Duration(days: 1)));
    final mixes = _mixesOf(person)
      ..removeWhere((_, mix) => mix.day.compareTo(before) < 0);
    save?.call({
      'mixes': {
        for (final MapEntry(:key, :value) in mixes.entries)
          key: {'day': value.day, 'songs': value.songs},
      },
    });
  }

  /// [mix] (its [items] at home, by the artists [because]) with its extra
  /// songs for [day] spread through it. As it is when there is nothing to
  /// add or the radio can't be asked. [person] is whose mix it is.
  Future<List<AggregatedItem>> mixWith({
    required String mixId,
    required String day,
    required List<String> because,
    required List<AggregatedItem> items,
    required String serverId,
    required bool hideExplicit,
    KostvMusicDislikes dislikes = KostvMusicDislikes.empty,
    String person = '',
  }) async {
    if (items.isEmpty) return items;
    await _ensureLoaded(person);
    final mixes = _mixesOf(person);
    if (mixes[mixId]?.day != day && because.isNotEmpty) {
      final key = '$person|$mixId|$day';
      await (_asking[key] ??=
          _pick(
            person: person,
            mixId: mixId,
            day: day,
            because: because,
            items: items,
            serverId: serverId,
          ).whenComplete(() {
            _asking.remove(key);
          }));
    }
    final mix = mixes[mixId];
    final kept = mix != null && mix.day == day
        ? mix.songs
        : const <Map<String, Object?>>[];
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
    required String person,
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
    _mixesOf(person)[mixId] = (day: day, songs: picked);
    _keep(person, day);
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
    _people.clear();
    _loaded.clear();
    _asking.clear();
  }
}

/// A mix's extra songs and the day they were picked for.
typedef _KeptMix = ({String day, List<Map<String, Object?>> songs});

/// Kos TV: [day] as the mixes write it (`2026-11-21`).
String kostvDayOf(DateTime day) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}
