import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:playback_core/playback_core.dart';

import '../data/models/aggregated_item.dart';
import '../data/services/stremfin/kostv_stream_song.dart';
import '../data/services/stremfin/stremfin_client.dart';
import '../data/services/stremfin/stremfin_models.dart';

/// Kos TV: why an out-of-home song couldn't start.
enum KostvStreamFailure {
  /// Nobody can listen to it (404): it is skipped.
  notFound,

  /// The service or its sources didn't answer (503, no network, too many
  /// calls): to try later.
  unavailable,
}

/// Kos TV: an out-of-home song that couldn't start, and why.
class KostvStreamException implements Exception {
  const KostvStreamException(this.failure, [this.cause]);

  final KostvStreamFailure failure;
  final Object? cause;

  @override
  String toString() => 'KostvStreamException(${failure.name}, $cause)';
}

/// Kos TV: an out-of-home song that turned out to be at home, and the home
/// server's song it is.
typedef KostvStreamAtHome = ({AggregatedItem stream, AggregatedItem home});

/// Kos TV: in front of the usual resolver, the one for the songs that
/// aren't at home ([isKostvStream]). It asks the requests service where to
/// hear the song (`listen`, which waits until its sound is ready), keeps
/// that address until it expires and hands it to the player as a plain
/// file, without the home server's headers. When the service says the song
/// is at home now, it plays the home server's one instead (and says so in
/// [arrivals], for the queue to take it). Everything else goes on to the
/// usual resolver as before.
///
/// Its stream is never replanned nor renewed: it is a file of the service,
/// whose key in the address is the permission.
class StremfinStreamResolver extends MediaStreamResolver
    implements StreamReplanner, StreamCredentialRefresher {
  StremfinStreamResolver({
    required MediaStreamResolver inner,
    required Future<StremfinListen> Function(String deezerId) listen,
    required String? Function(String url) address,
    Future<AggregatedItem?> Function(String jellyfinId)? homeItem,
    Future<int?> Function(String url)? probe,
    @visibleForTesting DateTime Function()? now,
    @visibleForTesting Future<void> Function(Duration wait) pause = _pauseFor,
  }) : _inner = inner,
       _listen = listen,
       _address = address,
       _homeItem = homeItem,
       _probe = probe,
       _now = now ?? DateTime.now,
       _pause = pause;

  final MediaStreamResolver _inner;
  final Future<StremfinListen> Function(String deezerId) _listen;
  final String? Function(String url) _address;
  final Future<AggregatedItem?> Function(String jellyfinId)? _homeItem;

  /// The status a request for an address gets now (a 404 once it is no
  /// longer kept), or null when it couldn't be asked.
  final Future<int?> Function(String url)? _probe;
  final DateTime Function() _now;
  final Future<void> Function(Duration wait) _pause;

  static Future<void> _pauseFor(Duration wait) => Future.delayed(wait);

  // What follows outlives one resolver: a new one is made at every switch of
  // server or person, and the queue it plays goes on.

  /// The id of the out-of-home song whose sound is being prepared now (the
  /// service is getting it), for «Preparando la canción…». Null otherwise.
  static final preparing = ValueNotifier<String?>(null);

  /// The last failure of each out-of-home song, by its id in the queue.
  static final failures = <String, KostvStreamFailure>{};

  /// The out-of-home songs that are at home now, and the home server's song
  /// each one is, by the out-of-home one's id.
  static final atHome = <String, AggregatedItem>{};

  static final _arrivals = StreamController<KostvStreamAtHome>.broadcast();

  /// Out-of-home songs found at home (by `listen`, or by [noteAtHome]).
  static Stream<KostvStreamAtHome> get arrivals => _arrivals.stream;

  static final _cache = <String, _Heard>{};

  /// A cached address is asked about again once it is this old: the
  /// service may have stopped keeping the sound (its administrator, or the
  /// days going by), and then it answers 404 and `listen` is asked again.
  static const checkAfter = Duration(minutes: 10);

  /// Kos TV: an address is taken as expired this long before it says.
  static const _margin = Duration(minutes: 2);

  /// Kos TV: [stream] is [home] on the home server (the service said so):
  /// it plays from there from now on.
  static void noteAtHome(AggregatedItem stream, AggregatedItem home) {
    atHome[stream.id] = home;
    if (!_arrivals.isClosed) _arrivals.add((stream: stream, home: home));
  }

  /// Forgets the address kept for [deezerId] (the player couldn't open it):
  /// the next play asks `listen` again.
  static void forget(String deezerId) => _cache.remove(deezerId);

  @visibleForTesting
  static void debugReset() {
    preparing.value = null;
    failures.clear();
    atHome.clear();
    _cache.clear();
  }

  /// Whether [resolution] is an out-of-home song's stream.
  static bool isStreamResolution(StreamResolutionResult resolution) =>
      isKostvStreamId(resolution.mediaSourceId);

  /// The home server's song an out-of-home one turned into, else [item].
  static dynamic homeOf(dynamic item) =>
      item is AggregatedItem ? (atHome[item.id] ?? item) : item;

  @override
  Future<StreamResolutionResult> resolve(
    dynamic mediaItem, {
    Map<String, dynamic>? deviceProfile,
    int? maxStreamingBitrate,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startTimeTicks,
    String? mediaSourceId,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
  }) async {
    Future<StreamResolutionResult> usual(dynamic item) => _inner.resolve(
      item,
      deviceProfile: deviceProfile,
      maxStreamingBitrate: maxStreamingBitrate,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      startTimeTicks: startTimeTicks,
      mediaSourceId: isKostvStreamId(mediaSourceId) ? null : mediaSourceId,
      enableDirectPlay: enableDirectPlay,
      enableDirectStream: enableDirectStream,
      enableTranscoding: enableTranscoding,
    );
    if (!isKostvStream(mediaItem)) return usual(mediaItem);
    final item = mediaItem as AggregatedItem;
    final home = atHome[item.id];
    if (home != null) return usual(home);
    final deezerId = kostvStreamDeezerId(item)!;
    failures.remove(item.id);
    // A file of the service has nothing to convert: direct play is asked
    // for even when the player wanted it converted (enableDirectPlay false),
    // which only happens to find a way the file plays anyway.
    var heard = await _kept(deezerId);
    if (heard == null) {
      preparing.value = item.id;
      try {
        final listen = await _listenOnce(deezerId);
        if (listen.inJellyfin && listen.jellyfinId != null) {
          final found = await _home(listen.jellyfinId!);
          if (found != null) {
            noteAtHome(item, found);
            return await usual(found);
          }
        }
        final url = listen.url == null ? null : _address(listen.url!);
        if (url == null) {
          throw const KostvStreamException(KostvStreamFailure.unavailable);
        }
        heard = _Heard(
          url: url,
          type: listen.type,
          expiresAt: listen.expiresAt,
          at: _now(),
        );
        _cache[deezerId] = heard;
      } on KostvStreamException catch (e) {
        failures[item.id] = e.failure;
        rethrow;
      } finally {
        if (preparing.value == item.id) preparing.value = null;
      }
    }
    return StreamResolutionResult(
      streamUrl: heard.url,
      mediaSourceId: item.id,
      playMethod: StreamPlayMethod.directPlay,
      container: heard.container,
      mediaType: 'audio',
      mediaStreams: [
        {
          'Type': 'Audio',
          'Index': 0,
          'Codec': ?heard.codec,
          'IsDefault': true,
          'Channels': 2,
        },
      ],
      serverOfferedDirectPlay: true,
      directPlayRequested: true,
    );
  }

  /// The address kept for [deezerId] while it lasts: a while after it was
  /// given, the service is asked whether it still has it.
  Future<_Heard?> _kept(String deezerId) async {
    final kept = _cache[deezerId];
    if (kept == null) return null;
    final now = _now();
    final expires = kept.expiresAt;
    if (expires != null && !now.isBefore(expires.subtract(_margin))) {
      _cache.remove(deezerId);
      return null;
    }
    final probe = _probe;
    if (probe != null && now.difference(kept.at) >= checkAfter) {
      final status = await probe(kept.url).catchError((Object _) => null);
      if (status == 404) {
        _cache.remove(deezerId);
        return null;
      }
      if (status != null && status >= 200 && status < 400) {
        _cache[deezerId] = kept.checked(now);
      }
    }
    return _cache[deezerId];
  }

  /// `listen`, once more after a short wait the service asks for (429);
  /// its failures as a [KostvStreamException].
  Future<StremfinListen> _listenOnce(String deezerId) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _listen(deezerId);
      } on StremfinException catch (e) {
        if (e.isNotFound) {
          throw KostvStreamException(KostvStreamFailure.notFound, e);
        }
        final wait = e.retryAfter ?? const Duration(seconds: 2);
        if (e.isRateLimited &&
            attempt == 0 &&
            wait <= const Duration(seconds: 10)) {
          await _pause(wait);
          continue;
        }
        throw KostvStreamException(KostvStreamFailure.unavailable, e);
      } on KostvStreamException {
        rethrow;
      } catch (e) {
        throw KostvStreamException(KostvStreamFailure.unavailable, e);
      }
    }
  }

  Future<AggregatedItem?> _home(String jellyfinId) async {
    final find = _homeItem;
    if (find == null) return null;
    try {
      return await find(jellyfinId);
    } catch (_) {
      return null;
    }
  }

  @override
  bool canReplan(StreamResolutionResult current) {
    final inner = _inner;
    return !isStreamResolution(current) &&
        inner is StreamReplanner &&
        (inner as StreamReplanner).canReplan(current);
  }

  @override
  Future<StreamResolutionResult> replan(
    dynamic mediaItem,
    StreamResolutionResult current,
    ReplanRequest request,
  ) {
    final inner = _inner;
    if (inner is! StreamReplanner || isStreamResolution(current)) {
      throw StateError('${inner.runtimeType} cannot replan');
    }
    return (inner as StreamReplanner).replan(
      homeOf(mediaItem),
      current,
      request,
    );
  }

  @override
  Future<StreamCredentials?> currentCredentials(
    StreamResolutionResult current, {
    bool refresh = false,
  }) async {
    final inner = _inner;
    if (isStreamResolution(current) || inner is! StreamCredentialRefresher) {
      return null;
    }
    return (inner as StreamCredentialRefresher).currentCredentials(
      current,
      refresh: refresh,
    );
  }
}

/// An address the service gave for a song's sound.
@immutable
class _Heard {
  const _Heard({
    required this.url,
    required this.at,
    this.type,
    this.expiresAt,
  });

  final String url;
  final String? type;
  final DateTime? expiresAt;

  /// When it was given, or last found still there.
  final DateTime at;

  _Heard checked(DateTime now) =>
      _Heard(url: url, at: now, type: type, expiresAt: expiresAt);

  String get _type => (type ?? '').toLowerCase();

  /// From the service's `type` (since 1.98.1 mostly `audio/mpeg`, MP3, or
  /// `audio/mp4`, AAC); null when it says nothing known, for the player to
  /// find out.
  String? get container => switch (_type) {
    final t when t.contains('mpeg') || t.contains('mp3') => 'mp3',
    final t when t.contains('mp4') || t.contains('aac') => 'mp4',
    final t when t.contains('webm') => 'webm',
    final t when t.contains('ogg') => 'ogg',
    _ => null,
  };

  String? get codec => switch (container) {
    'mp3' => 'mp3',
    'mp4' => 'aac',
    'webm' || 'ogg' => 'opus',
    _ => null,
  };
}
