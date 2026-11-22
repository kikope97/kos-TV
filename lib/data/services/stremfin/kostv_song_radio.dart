import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../models/aggregated_item.dart';
import '../kostv_music_dislikes.dart';
import '../kostv_music_plugin.dart' show KostvMusicDislikes;
import 'kostv_stream_radio.dart';
import 'kostv_stream_song.dart';
import 'stremfin_client.dart' show StremfinException;
import 'stremfin_models.dart';
import 'stremfin_service.dart';

/// Kos TV: the requests service's radio of one song (`GET
/// /music/songs/{id}/radio`, `docs/stremfin-api.md` 8.40, since 1.101.0)
/// and the matching of a song at home to Deezer's (`POST
/// /music/songs/match`, 8.39, since 1.100.0), for «Crear emisora» and the
/// endless play (∞) with «Toda la música» (`docs/musica-radio.md`, «Orden
/// de las fuentes»).
///
/// A song's radio counts in the same ten a minute as the recommendations
/// and the artists' radio, so it is asked once for each station and each
/// time the ∞ adds more: each song's is kept an hour here (the service
/// keeps it a day), and after the service said no (too many, not
/// answering) it is left alone a while. A service from before it (a 404
/// for every song) is told apart from a song Deezer doesn't have by the
/// version `/me` gives.

/// Kos TV: a song sent to be matched.
typedef KostvMatchSong = ({String title, String artist, String? isrc});

/// Kos TV: the song radio couldn't be asked now (from before it, resting,
/// no such song): the station goes on with the server plugin's.
class KostvSongRadioUnavailable implements Exception {
  const KostvSongRadioUnavailable(this.why);

  /// `missing` (a service before it), `resting`, `not_there` (Deezer
  /// doesn't have the song) or `no_service`.
  final String why;

  @override
  String toString() => 'KostvSongRadioUnavailable($why)';
}

class KostvSongRadio {
  KostvSongRadio({
    Future<StremfinSongRadio> Function(
      String deezerId, {
      String? only,
      int? limit,
    })?
    fetch,
    Future<StremfinSongMatch> Function(List<KostvMatchSong> songs)? match,
    String? Function()? version,
    bool Function()? available,
    String Function()? who,
    DateTime Function()? clock,
    this.shares,
  }) : _fetch = fetch ?? _serviceRadio,
       _match = match ?? _serviceMatch,
       _version = version ?? _serviceVersion,
       _available = available ?? _serviceThere,
       _who = who ?? _signedIn,
       _clock = clock ?? DateTime.now;

  /// The app's own; set up with the requests service at start.
  static KostvSongRadio instance = KostvSongRadio();

  static StremfinService? _service() {
    final getIt = GetIt.instance;
    return getIt.isRegistered<StremfinService>()
        ? getIt<StremfinService>()
        : null;
  }

  static bool _serviceThere() => _service() != null;

  static Future<StremfinSongRadio> _serviceRadio(
    String deezerId, {
    String? only,
    int? limit,
  }) {
    final service = _service();
    if (service == null) {
      return Future.error(const KostvSongRadioUnavailable('no_service'));
    }
    return service.musicSongRadio(deezerId, only: only, limit: limit);
  }

  static Future<StremfinSongMatch> _serviceMatch(List<KostvMatchSong> songs) {
    final service = _service();
    if (service == null) {
      return Future.error(const KostvSongRadioUnavailable('no_service'));
    }
    return service.musicSongsMatch(songs);
  }

  static String? _serviceVersion() => _service()?.serverVersion;

  /// Whose the radios kept are (as [KostvStreamRadio]'s): another person
  /// signed in, or the same one once their age limit is known, gets their
  /// own.
  static String _signedIn() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<MediaServerClient>()) return '';
    final client = getIt<MediaServerClient>();
    final service = _service();
    return [
      client.baseUrl,
      client.userId,
      service?.generation ?? '',
      service?.hidesExplicitMusic ?? '',
    ].join('|');
  }

  final Future<StremfinSongRadio> Function(
    String deezerId, {
    String? only,
    int? limit,
  })
  _fetch;
  final Future<StremfinSongMatch> Function(List<KostvMatchSong> songs) _match;
  final String? Function() _version;
  final bool Function() _available;
  final String Function() _who;
  final DateTime Function() _clock;

  /// The artists' radio, which shares the same ten a minute
  /// ([KostvStreamRadio.instance] when null): it rests too when the service
  /// says «too many» here.
  final KostvStreamRadio? shares;

  /// How long a song's radio is kept here (the service keeps it a day;
  /// what comes home meanwhile is told then).
  static const keep = Duration(hours: 1);

  /// How long it is left alone after the service said no.
  static const quiet = Duration(minutes: 1);

  /// How long a service without the route is left alone, so updating it
  /// shows without restarting the app.
  static const missingFor = Duration(minutes: 30);

  /// How long a song Deezer doesn't have isn't asked about again.
  static const notThereFor = Duration(hours: 6);

  /// How long a song at home matched to Deezer's (or to none) is kept, as
  /// the service keeps it.
  static const matchedFor = Duration(days: 7);
  static const unmatchedFor = Duration(hours: 6);

  final _kept = <String, ({DateTime at, List<StremfinSong> songs})>{};
  final _asking = <String, Future<List<StremfinSong>>>{};
  final _notThere = <String, DateTime>{};
  final _matched = <String, ({DateTime at, String? deezerId})>{};
  final _matching = <String, Future<String?>>{};
  DateTime? _quietUntil;
  DateTime? _missingAt;
  DateTime? _matchQuietUntil;
  DateTime? _matchMissingAt;

  /// 404s in a row while the service's version isn't known: two of
  /// different songs read as a service without the route.
  final _unknown404 = <String>{};

  /// How many calls went to the service (for tests).
  @visibleForTesting
  int calls = 0;
  @visibleForTesting
  int matchCalls = 0;

  bool _fresh(DateTime? at, Duration lasts) =>
      at != null && _clock().difference(at) < lasts;

  /// Whether a song's radio can be asked for at all now (the service is
  /// there and not one from before it).
  bool get usable =>
      _available() &&
      !_fresh(_missingAt, missingFor) &&
      kostvServiceAtLeast(_version(), '1.101.0') != false;

  String _key(String deezerId, String only, int limit) =>
      '${_who()}|$deezerId|$only|$limit';

  /// Whether the radio of [deezerId] is kept here (asking for it costs no
  /// call).
  bool keeps(String deezerId, {String only = 'all', int limit = 50}) {
    final kept = _kept[_key(deezerId, only, limit)];
    return kept != null && _fresh(kept.at, keep);
  }

  /// The songs of the radio of the song [deezerId] (`only` as the service
  /// takes it). Throws when it can't be asked now
  /// ([KostvSongRadioUnavailable]) or the service didn't answer (nothing is
  /// kept then).
  Future<List<StremfinSong>> songs(
    String deezerId, {
    String only = 'all',
    int limit = 50,
  }) {
    final key = _key(deezerId, only, limit);
    final kept = _kept[key];
    if (kept != null && _fresh(kept.at, keep)) return Future.value(kept.songs);
    final pending = _asking[key];
    if (pending != null) return pending;
    if (!_available()) {
      return Future.error(const KostvSongRadioUnavailable('no_service'));
    }
    if (!usable) {
      return Future.error(const KostvSongRadioUnavailable('missing'));
    }
    if (_fresh(_notThere[deezerId], notThereFor)) {
      return Future.error(const KostvSongRadioUnavailable('not_there'));
    }
    final quietUntil = _quietUntil;
    if (quietUntil != null && _clock().isBefore(quietUntil)) {
      return Future.error(const KostvSongRadioUnavailable('resting'));
    }
    calls++;
    late final Future<List<StremfinSong>> future;
    future = _fetch(deezerId, only: only, limit: limit)
        .then((found) {
          final now = _clock();
          _unknown404.clear();
          _missingAt = null;
          _kept
            ..removeWhere((_, v) => now.difference(v.at) >= keep)
            ..[key] = (at: now, songs: found.songs);
          // What it says is at home is matched for later seeds: the ∞
          // going on from one of them needs no call to match it.
          for (final song in [?found.seed, ...found.songs]) {
            note(song);
          }
          return found.songs;
        })
        .catchError((Object e) {
          _failed(e, deezerId);
          throw e;
        })
        .whenComplete(() {
          if (identical(_asking[key], future)) _asking.remove(key);
        });
    return _asking[key] = future;
  }

  void _failed(Object e, String deezerId) {
    final now = _clock();
    if (e is StremfinException && e.isNotFound) {
      // Kos TV: the route's 404 and a song's say the same (`not_found`):
      // the service's version tells them apart; not known, two songs in a
      // row without one.
      final newEnough = kostvServiceAtLeast(_version(), '1.101.0');
      if (newEnough == false) {
        _missingAt = now;
      } else {
        _notThere[deezerId] = now;
        if (newEnough == null) {
          _unknown404.add(deezerId);
          if (_unknown404.length >= 2) {
            _missingAt = now;
            _unknown404.clear();
          }
        }
      }
      return;
    }
    if (e is KostvSongRadioUnavailable) return;
    final wait = e is StremfinException && e.isRateLimited
        ? (e.retryAfter ?? quiet)
        : quiet;
    _quietUntil = now.add(wait);
    if (e is StremfinException && e.isRateLimited) {
      (shares ?? KostvStreamRadio.instance).restFor(wait);
    }
  }

  static String _plain(String id) => id.replaceAll('-', '').toLowerCase();

  String _matchKey(String jellyfinId) => '${_who()}|${_plain(jellyfinId)}';

  /// Kos TV: [song] of the service, at home: its Deezer id is kept as that
  /// home song's, so a station from it needs no call to match it.
  void note(StremfinSong song) {
    final home = song.jellyfinId;
    final deezer = song.deezerId;
    if (home == null || deezer == null || deezer.isEmpty) return;
    _matched[_matchKey(home)] = (at: _clock(), deezerId: deezer);
  }

  /// Kos TV: the ISRC the home server has of [song], if any.
  static String? isrcOf(AggregatedItem song) {
    for (final MapEntry(:key, :value) in song.providerIds.entries) {
      if (key.toLowerCase() == 'isrc' && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  /// Kos TV: Deezer's id of the song [seed]: its own for one that isn't at
  /// home; for one at home, matched once by its title, artist and ISRC
  /// ([artist], its first own) and kept. Null when it can't be known now
  /// (Deezer doesn't have it, the service didn't answer or is resting):
  /// never throws.
  Future<String?> deezerIdOf(AggregatedItem seed, {String? artist}) async {
    if (isKostvStream(seed)) return kostvStreamDeezerId(seed);
    final name = artist?.trim() ?? '';
    final title = seed.name.trim();
    if (title.isEmpty || name.isEmpty) return null;
    final key = _matchKey(seed.id);
    final known = _matched[key];
    if (known != null &&
        _fresh(known.at, known.deezerId == null ? unmatchedFor : matchedFor)) {
      return known.deezerId;
    }
    if (!_available() ||
        _fresh(_matchMissingAt, missingFor) ||
        kostvServiceAtLeast(_version(), '1.100.0') == false) {
      return null;
    }
    final quietUntil = _matchQuietUntil;
    if (quietUntil != null && _clock().isBefore(quietUntil)) return null;
    final pending = _matching[key];
    if (pending != null) return pending;
    matchCalls++;
    final future = _match([(title: title, artist: name, isrc: isrcOf(seed))])
        .then<String?>((found) {
          // Deezer didn't answer for it now: asked again another time.
          if (found.failed.contains(0)) return null;
          final song = found.songs.firstOrNull;
          final id = song?.deezerId;
          _matched[key] = (at: _clock(), deezerId: id);
          if (song != null) note(song);
          return id;
        })
        .catchError((Object e) {
          final now = _clock();
          if (e is StremfinException && e.isNotFound) {
            // Kos TV: a POST without ids in its path: only a service
            // before it answers 404.
            _matchMissingAt = now;
          } else if (e is StremfinException && e.isRateLimited) {
            _matchQuietUntil = now.add(e.retryAfter ?? quiet);
          } else {
            _matchQuietUntil = now.add(quiet);
          }
          return null;
        })
        .whenComplete(() {
          _matching.remove(key);
        });
    return _matching[key] = future;
  }

  @visibleForTesting
  void debugReset() {
    _kept.clear();
    _asking.clear();
    _notThere.clear();
    _matched.clear();
    _matching.clear();
    _unknown404.clear();
    _quietUntil = null;
    _missingAt = null;
    _matchQuietUntil = null;
    _matchMissingAt = null;
    calls = 0;
    matchCalls = 0;
  }
}

/// Kos TV: the songs of a song's radio ([songs], in its order) as the
/// queue takes them: what it says is at home ([StremfinSong.jellyfinId]) as
/// the home server's song, asked for with [homeItems] in one go (one the
/// home server doesn't give the person is left out, never streamed
/// instead: its parental control), the rest as songs that aren't at home
/// sounding through the service. Without what the person doesn't want to
/// hear ([dislikes]), for someone with a limit ([hideExplicit]) nothing
/// from away that is explicit, without the seed and what is in the queue
/// ([skip] ids, [skipKeys] [kostvSongKey]s), never two of the same artist
/// in a row ([kostvRadioInOrder]).
Future<List<AggregatedItem>> kostvStationFromSongRadio(
  List<StremfinSong> songs, {
  required String serverId,
  required bool hideExplicit,
  required Future<List<AggregatedItem>> Function(List<String> ids) homeItems,
  KostvMusicDislikes dislikes = KostvMusicDislikes.empty,
  AggregatedItem? seed,
  Set<String> skip = const {},
  Set<String> skipKeys = const {},
}) async {
  final found = dislikes.stremfinSongsIn(songs);
  final queued = await kostvQueueOf(
    [for (final song in found) KostvQueueSong.ofSong(song, serverId: serverId)],
    hideExplicit: hideExplicit,
    homeItems: homeItems,
  );
  final seedKey = seed == null ? null : kostvSongKey(seed);
  return kostvRadioInOrder(
    [
      for (final item in queued.items)
        if (!dislikes.songOut(item) && kostvSongKey(item) != seedKey) item,
    ],
    skip: {...skip, ?seed?.id},
    skipKeys: skipKeys,
  );
}
