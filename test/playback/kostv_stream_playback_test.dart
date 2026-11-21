import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/playback/kostv_stream_playback.dart';
import 'package:moonfin/playback/last_playback_session_store.dart';
import 'package:moonfin/playback/local_aware_player_service.dart';
import 'package:moonfin/playback/stremfin_stream_resolver.dart';
import 'package:playback_core/playback_core.dart';

const _server = 'https://casa.example';

AggregatedItem _stream(String deezerId, {bool ready = false, int? seconds}) =>
    kostvStreamItem(
      deezerId: deezerId,
      title: 'Canción $deezerId',
      serverId: _server,
      artist: 'Lola',
      album: 'Disco',
      durationSeconds: seconds ?? 200,
      cover: 'https://cdn.example/$deezerId.jpg',
      albumDeezerId: 'al$deezerId',
      listenReady: ready,
    );

AggregatedItem _home(String id) => AggregatedItem(
  id: id,
  serverId: _server,
  rawData: {'Id': id, 'Name': id, 'Type': 'Audio', 'RunTimeTicks': 2000000000},
);

/// The usual resolver: notes what it was asked to resolve.
class _Usual extends MediaStreamResolver implements StreamReplanner {
  final resolved = <String>[];

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
    final id = MediaStreamResolver.extractItemId(mediaItem);
    resolved.add(id);
    return StreamResolutionResult(
      streamUrl: 'https://casa.example/Audio/$id/stream',
      mediaSourceId: id,
      playMethod: StreamPlayMethod.directPlay,
      requestHeaders: const {'Authorization': 'MediaBrowser Token=t'},
      mediaType: 'audio',
    );
  }

  @override
  bool canReplan(StreamResolutionResult current) => true;

  @override
  Future<StreamResolutionResult> replan(
    dynamic mediaItem,
    StreamResolutionResult current,
    ReplanRequest request,
  ) => resolve(mediaItem);
}

StremfinListen _heard(
  String id, {
  DateTime? expires,
  String type = 'audio/mp4',
}) => StremfinListen(
  deezerId: id,
  url: '/api/v1/music/listen?k=$id',
  type: type,
  expiresAt: expires,
  ready: true,
);

void main() {
  setUp(StremfinStreamResolver.debugReset);

  group('StremfinStreamResolver', () {
    test('a song that isn\'t at home: listen, a plain file without the '
        'home server\'s headers, and its address kept', () async {
      final usual = _Usual();
      var listens = 0;
      final preparing = <String?>[];
      void note() => preparing.add(StremfinStreamResolver.preparing.value);
      StremfinStreamResolver.preparing.addListener(note);
      addTearDown(() => StremfinStreamResolver.preparing.removeListener(note));
      final resolver = StremfinStreamResolver(
        inner: usual,
        listen: (id) async {
          listens++;
          return _heard(id, type: 'audio/webm');
        },
        address: (url) => 'https://requests.example.org$url',
      );
      final song = _stream('1');
      final result = await resolver.resolve(song, enableDirectPlay: false);
      expect(
        result.streamUrl,
        'https://requests.example.org/api/v1/music/listen?k=1',
      );
      expect(result.requestHeaders, isEmpty);
      expect(result.playMethod, StreamPlayMethod.directPlay);
      expect(result.mediaType, 'audio');
      expect(result.container, 'webm');
      expect(result.mediaStreams.single['Codec'], 'opus');
      for (final (type, container, codec) in [
        ('audio/mpeg', 'mp3', 'mp3'),
        ('audio/mp4', 'mp4', 'aac'),
        ('application/octet-stream', null, null),
      ]) {
        StremfinStreamResolver.forget('t$type');
        final typed = await StremfinStreamResolver(
          inner: usual,
          listen: (id) async => _heard(id, type: type),
          address: (url) => url,
        ).resolve(_stream('t$type'));
        expect(typed.container, container, reason: type);
        expect(typed.mediaStreams.single['Codec'], codec, reason: type);
      }
      expect(StremfinStreamResolver.isStreamResolution(result), isTrue);
      expect(preparing.take(2), ['stremfin:1', null]);
      // Played again: no second listen while the address lasts.
      await resolver.resolve(song);
      expect(listens, 1);
      expect(usual.resolved, isEmpty);
      // Its stream is never replanned nor renewed; the usual ones are.
      expect(resolver.canReplan(result), isFalse);
      expect(await resolver.currentCredentials(result), isNull);
      final homeResult = await resolver.resolve(_home('h1'));
      expect(usual.resolved, ['h1']);
      expect(resolver.canReplan(homeResult), isTrue);
    });

    test('an address about to expire is asked for again', () async {
      var now = DateTime.utc(2026, 11, 21, 10);
      var listens = 0;
      final resolver = StremfinStreamResolver(
        inner: _Usual(),
        listen: (id) async {
          listens++;
          return _heard(id, expires: DateTime.utc(2026, 11, 21, 22));
        },
        address: (url) => url,
        now: () => now,
      );
      await resolver.resolve(_stream('1'));
      now = DateTime.utc(2026, 11, 21, 21, 59);
      await resolver.resolve(_stream('1'));
      expect(listens, 2);
    });

    test('a kept address the service no longer has (404) is asked for '
        'again, once', () async {
      var now = DateTime.utc(2026, 11, 21, 10);
      var listens = 0;
      final probed = <String>[];
      final resolver = StremfinStreamResolver(
        inner: _Usual(),
        listen: (id) async {
          listens++;
          return _heard('$id-$listens');
        },
        address: (url) => url,
        probe: (url) async {
          probed.add(url);
          return url.endsWith('-1') ? 404 : 206;
        },
        now: () => now,
      );
      await resolver.resolve(_stream('1'));
      // Fresh: not asked about.
      await resolver.resolve(_stream('1'));
      expect(probed, isEmpty);
      now = now.add(StremfinStreamResolver.checkAfter);
      final again = await resolver.resolve(_stream('1'));
      expect(probed, ['/api/v1/music/listen?k=1-1']);
      expect(listens, 2);
      expect(again.streamUrl, '/api/v1/music/listen?k=1-2');
    });

    test('at home now: the home server\'s song plays, and the queue hears '
        'of it', () async {
      final usual = _Usual();
      final arrivals = <KostvStreamAtHome>[];
      final sub = StremfinStreamResolver.arrivals.listen(arrivals.add);
      addTearDown(sub.cancel);
      final resolver = StremfinStreamResolver(
        inner: usual,
        listen: (id) async =>
            StremfinListen(deezerId: id, inJellyfin: true, jellyfinId: 'j$id'),
        address: (url) => url,
        homeItem: (id) async => _home(id),
      );
      final song = _stream('7');
      final result = await resolver.resolve(song);
      expect(usual.resolved, ['j7']);
      expect(result.requestHeaders, isNotEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(arrivals.single.stream.id, 'stremfin:7');
      expect(arrivals.single.home.id, 'j7');
      expect(StremfinStreamResolver.homeOf(song).id, 'j7');
      // From then on straight from home.
      await resolver.resolve(song);
      expect(usual.resolved, ['j7', 'j7']);
    });

    test('404: nobody can listen to it; 503: later; 429: once more after '
        'the wait it asks for', () async {
      Future<KostvStreamFailure?> failure(Object error) async {
        // Each on its own (a 404 is the answer for a while).
        StremfinStreamResolver.debugReset();
        final resolver = StremfinStreamResolver(
          inner: _Usual(),
          listen: (_) async => throw error,
          address: (url) => url,
          pause: (_) async {},
        );
        try {
          await resolver.resolve(_stream('1'));
        } on KostvStreamException catch (e) {
          expect(StremfinStreamResolver.failures['stremfin:1'], e.failure);
          expect(StremfinStreamResolver.preparing.value, isNull);
          return e.failure;
        }
        return null;
      }

      expect(
        await failure(const StremfinException(code: 'not_found', status: 404)),
        KostvStreamFailure.notFound,
      );
      expect(
        await failure(
          const StremfinException(code: 'source_unavailable', status: 503),
        ),
        KostvStreamFailure.unavailable,
      );
      expect(
        await failure(const StremfinException(code: 'network')),
        KostvStreamFailure.unavailable,
      );
      var tries = 0;
      final waited = <Duration>[];
      final resolver = StremfinStreamResolver(
        inner: _Usual(),
        listen: (id) async {
          if (tries++ == 0) {
            throw const StremfinException(
              code: 'too_many_requests',
              status: 429,
              retryAfter: Duration(seconds: 3),
            );
          }
          return _heard(id);
        },
        address: (url) => url,
        pause: (wait) async => waited.add(wait),
      );
      await resolver.resolve(_stream('2'));
      expect(tries, 2);
      expect(waited, [const Duration(seconds: 3)]);
    });

    test('a 404 a moment ago (asked ahead) is the answer at its start, '
        'without asking again; later it is asked again', () async {
      var now = DateTime.utc(2026, 11, 21, 10);
      var listens = 0;
      final resolver = StremfinStreamResolver(
        inner: _Usual(),
        listen: (_) async {
          listens++;
          throw const StremfinException(code: 'not_found', status: 404);
        },
        address: (url) => url,
        now: () => now,
      );
      Future<KostvStreamFailure?> start() async {
        try {
          await resolver.resolve(_stream('4'));
        } on KostvStreamException catch (e) {
          return e.failure;
        }
        return null;
      }

      expect(await start(), KostvStreamFailure.notFound);
      now = now.add(const Duration(seconds: 25));
      expect(await start(), KostvStreamFailure.notFound);
      expect(listens, 1);
      expect(
        StremfinStreamResolver.failures['stremfin:4'],
        KostvStreamFailure.notFound,
      );
      now = now.add(StremfinStreamResolver.goneFor);
      expect(await start(), KostvStreamFailure.notFound);
      expect(listens, 2);
    });

    test('what is kept of the songs heard is each person\'s', () async {
      var person = 'ana';
      final listened = <String>[];
      final resolver = StremfinStreamResolver(
        inner: _Usual(),
        listen: (id) async {
          listened.add('$person $id');
          return _heard(id);
        },
        address: (url) => url,
        person: () => person,
      );
      await resolver.resolve(_stream('1'));
      await resolver.resolve(_stream('1'));
      expect(listened, ['ana 1']);
      StremfinStreamResolver.noteAtHome(_stream('2'), _home('j2'));
      StremfinStreamResolver.failures['stremfin:3'] =
          KostvStreamFailure.unavailable;

      // Another person on the same device: their own listen, nothing of
      // the one before.
      person = 'luis';
      await resolver.resolve(_stream('1'));
      expect(listened, ['ana 1', 'luis 1']);
      expect(StremfinStreamResolver.atHome, isEmpty);
      expect(StremfinStreamResolver.failures, isEmpty);
      // Back to the first: asked again as theirs.
      person = 'ana';
      await resolver.resolve(_stream('1'));
      expect(listened, ['ana 1', 'luis 1', 'ana 1']);
    });
  });

  group('the home server isn\'t told of them', () {
    test('no report of a song that isn\'t at home: it goes to the plugin '
        'instead; one at home now goes as the home one', () async {
      final events = <String>[];
      final stopped = <String>[];
      final started = <String>[];
      final service = LocalAwarePlayerService(
        _Server(events),
        _Offline(),
        canReachServer: () => true,
        onStreamStopped: (item, position, failed) =>
            stopped.add('${item.id} ${position.inSeconds} $failed'),
        onStreamStarted: (item) => started.add('${item.id}'),
        homeOf: (item) => item is AggregatedItem && item.id == 'stremfin:9'
            ? _home('j9')
            : item,
      );
      final stream = _stream('1');
      const streamed = StreamResolutionResult(
        streamUrl: 'https://requests.example.org/api/v1/music/listen?k=1',
        mediaSourceId: 'stremfin:1',
        playMethod: StreamPlayMethod.directPlay,
      );
      await service.onPlaybackStart(stream, streamed);
      await service.onPlaybackProgress(stream, streamed, Duration.zero);
      await service.onPlaybackStop(
        stream,
        streamed,
        const Duration(seconds: 42),
      );
      await service.stopTranscoding(streamed);
      expect(events, isEmpty);
      expect(started, ['stremfin:1']);
      expect(stopped, ['stremfin:1 42 false']);
      const home = StreamResolutionResult(
        streamUrl: 'https://casa.example/Audio/j9/stream',
        mediaSourceId: 'j9',
        playMethod: StreamPlayMethod.directPlay,
      );
      await service.onPlaybackStart(_stream('9'), home);
      await service.onPlaybackStop(_stream('9'), home, Duration.zero);
      expect(events, ['start j9', 'stop j9']);
      expect(started, hasLength(1));
      expect(stopped, hasLength(1));
    });
  });

  group('asking ahead (§3)', () {
    late QueueService queue;
    late List<String> asked;
    late Map<String, StremfinPrefetchState> states;
    late KostvStreamPlayback playback;
    var duration = const Duration(seconds: 200);

    setUp(() {
      queue = QueueService();
      asked = [];
      states = {};
      duration = const Duration(seconds: 200);
      playback = KostvStreamPlayback(
        prefetch: (id) async {
          asked.add(id);
          return StremfinPrefetch(
            deezerId: id,
            state: states[id] ?? StremfinPrefetchState.queued,
          );
        },
        report: (_) async => true,
      );
      playback.attach(
        queue: queue,
        positions: const Stream.empty(),
        duration: () => duration,
        playing: () => true,
      );
    });

    tearDown(() => playback.detach());

    test('at half the song, the next one; not before, not twice', () async {
      queue.setQueue([_home('a'), _stream('2'), _stream('3')]);
      playback.onProgress(const Duration(seconds: 60));
      await pumpEventQueue();
      expect(asked, isEmpty);
      playback.onProgress(const Duration(seconds: 100));
      await pumpEventQueue();
      expect(asked, ['2']);
      playback.onProgress(const Duration(seconds: 150));
      await pumpEventQueue();
      expect(asked, ['2']);
    });

    test('half, or 90 s left, whichever comes first', () async {
      duration = const Duration(minutes: 10);
      queue.setQueue([_home('a'), _stream('2')]);
      playback.onProgress(
        const Duration(minutes: 5) - const Duration(seconds: 1),
      );
      await pumpEventQueue();
      expect(asked, isEmpty);
      // Half comes first on a long song (90 s left would be at 8:30).
      playback.onProgress(const Duration(minutes: 5));
      await pumpEventQueue();
      expect(asked, ['2']);
      final short = KostvStreamPlayback(
        prefetch: (id) async {
          asked.add('short $id');
          return StremfinPrefetch(
            deezerId: id,
            state: StremfinPrefetchState.queued,
          );
        },
        report: (_) async => true,
      );
      final q = QueueService()..setQueue([_home('b'), _stream('4')]);
      short.attach(
        queue: q,
        positions: const Stream.empty(),
        duration: () => const Duration(seconds: 120),
        playing: () => true,
      );
      // 30 s into 2 minutes: 90 s left, before its half.
      short.onProgress(const Duration(seconds: 30));
      await pumpEventQueue();
      expect(asked.last, 'short 4');
      short.detach();
    });

    test('what is at home or ready is skipped for the one after; never '
        'further', () async {
      queue.setQueue([
        _home('a'),
        _stream('2', ready: true),
        _stream('3'),
        _stream('4'),
      ]);
      playback.onProgress(const Duration(seconds: 100));
      await pumpEventQueue();
      expect(asked, ['3']);
      final other = QueueService()
        ..setQueue([_home('a'), _home('b'), _home('c'), _stream('5')]);
      playback.attach(
        queue: other,
        positions: const Stream.empty(),
        duration: () => duration,
        playing: () => true,
      );
      playback.onProgress(const Duration(seconds: 100));
      await pumpEventQueue();
      expect(asked, ['3']);
    });

    test('the next one changing (a song put next, shuffle) asks for the '
        'new one; one that can\'t be had leaves the queue', () async {
      states['9'] = StremfinPrefetchState.unavailable;
      queue.setQueue([_home('a'), _stream('2'), _home('b')]);
      playback.onProgress(const Duration(seconds: 100));
      await pumpEventQueue();
      expect(asked, ['2']);
      queue.insertNext(_stream('9'));
      await pumpEventQueue();
      expect(asked, ['2', '9']);
      expect(queue.items.map((e) => (e as AggregatedItem).id), [
        'a',
        'stremfin:2',
        'b',
      ]);
    });

    test('a song rested on 2–3 s, not one passed by', () {
      fakeAsync((async) {
        playback.prefetchSoon('1');
        async.elapse(const Duration(seconds: 1));
        playback.prefetchSoon('2');
        async.elapse(const Duration(seconds: 2));
        expect(asked, isEmpty);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(asked, ['2']);
        playback.prefetchSoon('3', listenReady: true);
        playback.prefetchSoon('4', atHome: true);
        async.elapse(const Duration(seconds: 5));
        playback.prefetchSoon('5');
        playback.cancelSoon();
        async.elapse(const Duration(seconds: 5));
        expect(asked, ['2']);
      });
    });

    test('songs rested on one after another: one at a time, one every 10 s, '
        'and the next of the queue never waits for them', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 11, 21, 10);
        final asking = <String, Completer<StremfinPrefetch>>{};
        final paced = KostvStreamPlayback(
          prefetch: (id) {
            asked.add(id);
            return (asking[id] = Completer<StremfinPrefetch>()).future;
          },
          report: (_) async => true,
          now: () => start.add(async.elapsed),
        );
        final q = QueueService()..setQueue([_home('a'), _stream('9')]);
        paced.attach(
          queue: q,
          positions: const Stream.empty(),
          duration: () => const Duration(seconds: 200),
          playing: () => true,
        );
        void answer(String id) => asking[id]!.complete(
          StremfinPrefetch(deezerId: id, state: StremfinPrefetchState.queued),
        );

        paced.prefetchSoon('1');
        async.elapse(const Duration(milliseconds: 2500));
        expect(asked, ['1']);
        // Resting on another while the first is still being asked for.
        paced.prefetchSoon('2');
        async.elapse(const Duration(seconds: 3));
        expect(asked, ['1']);
        // The queue's next goes at once all the same.
        paced.onProgress(const Duration(seconds: 100));
        async.flushMicrotasks();
        expect(asked, ['1', '9']);
        answer('1');
        async.flushMicrotasks();
        // Still within 10 s of the first (asked at 2.5 s).
        async.elapse(const Duration(seconds: 3));
        expect(asked, ['1', '9']);
        async.elapse(const Duration(seconds: 4));
        expect(asked, ['1', '9', '2']);
        answer('2');
        answer('9');
        async.flushMicrotasks();
        paced.detach();
      });
    });

    test('one that got no answer (too many calls, no network) is asked for '
        'again; a 404 is not', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 11, 21, 10);
        final errors = <String, Object>{
          '1': const StremfinException(code: 'too_many_requests', status: 429),
          '3': const StremfinException(code: 'not_found', status: 404),
        };
        final retrying = KostvStreamPlayback(
          prefetch: (id) async {
            asked.add(id);
            final error = errors.remove(id);
            if (error != null) throw error;
            return StremfinPrefetch(
              deezerId: id,
              state: StremfinPrefetchState.queued,
            );
          },
          report: (_) async => true,
          now: () => start.add(async.elapsed),
        );
        retrying.prefetchSoon('1');
        async.elapse(const Duration(seconds: 3));
        expect(asked, ['1']);
        async.elapse(const Duration(seconds: 10));
        retrying.prefetchSoon('1');
        async.elapse(const Duration(seconds: 3));
        expect(asked, ['1', '1']);
        async.elapse(const Duration(seconds: 10));
        retrying.prefetchSoon('3');
        async.elapse(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 10));
        retrying.prefetchSoon('3');
        async.elapse(const Duration(seconds: 13));
        expect(asked, ['1', '1', '3']);

        // The queue's next: once more a while later, for the same song.
        errors['8'] = const StremfinException(code: 'network');
        final q = QueueService()..setQueue([_home('a'), _stream('8')]);
        retrying.attach(
          queue: q,
          positions: const Stream.empty(),
          duration: () => const Duration(seconds: 200),
          playing: () => true,
        );
        retrying.onProgress(const Duration(seconds: 100));
        async.flushMicrotasks();
        expect(asked.last, '8');
        async.elapse(const Duration(seconds: 16));
        expect(asked.where((id) => id == '8'), hasLength(2));
        retrying.detach();
      });
    });
  });

  group('what was heard, for the plugin (stream_listen)', () {
    test('how much, of how long, how it ended, from where', () {
      fakeAsync((async) {
        final reports = <KostvStreamListen>[];
        final queue = QueueService();
        final playback = KostvStreamPlayback(
          prefetch: (id) async => StremfinPrefetch(
            deezerId: id,
            state: StremfinPrefetchState.ready,
          ),
          report: (listen) async {
            reports.add(listen);
            return true;
          },
        );
        playback.attach(
          queue: queue,
          positions: const Stream.empty(),
          duration: () => const Duration(seconds: 200),
          playing: () => true,
          source: () => 'search',
        );
        final first = _stream('1');
        queue.setQueue([first, _stream('2')]);
        playback.started(first);
        for (var s = 0; s <= 30; s++) {
          playback.onProgress(Duration(seconds: s));
        }
        // A jump forward isn't heard.
        playback.onProgress(const Duration(seconds: 120));
        playback.stopped(first, const Duration(seconds: 120), false);
        queue.next(manual: true);
        async.elapse(const Duration(seconds: 1));
        expect(reports.single.deezerId, '1');
        expect(reports.single.played, closeTo(30, 0.01));
        expect(reports.single.duration, 200);
        expect(reports.single.endedBy, 'next');
        expect(reports.single.source, 'search');
        expect(reports.single.artist, 'Lola');
        expect(reports.single.album, 'Disco');
        final second = queue.currentItem as AggregatedItem;
        playback.started(second);
        playback.stopped(second, const Duration(seconds: 199), false);
        expect(reports.last.endedBy, 'natural');
        playback.started(second);
        playback.stopped(second, const Duration(seconds: 50), true);
        expect(reports.last.endedBy, 'error');
        playback.started(second);
        playback.stopped(second, const Duration(seconds: 50), false);
        queue.clear();
        async.elapse(const Duration(seconds: 1));
        expect(reports.last.endedBy, 'stop');
        // One that never started has nothing to tell; a home one isn't
        // the plugin's.
        final count = reports.length;
        playback.stopped(_stream('3'), Duration.zero, true);
        playback.stopped(_home('h'), const Duration(seconds: 50), false);
        async.elapse(const Duration(seconds: 1));
        expect(reports, hasLength(count));
        playback.detach();
      });
    });

    late List<KostvStreamListen> reports;
    late QueueService queue;
    late KostvStreamPlayback playback;
    var restarting = false;

    void attachPlayback(FakeAsync async) {
      reports = [];
      restarting = false;
      queue = QueueService();
      final start = DateTime.utc(2026, 11, 21, 10);
      playback = KostvStreamPlayback(
        prefetch: (id) async =>
            StremfinPrefetch(deezerId: id, state: StremfinPrefetchState.ready),
        report: (listen) async {
          reports.add(listen);
          return true;
        },
        now: () => start.add(async.elapsed),
      );
      playback.attach(
        queue: queue,
        positions: const Stream.empty(),
        duration: () => const Duration(seconds: 200),
        playing: () => true,
        restarting: () => restarting,
      );
    }

    void hear(int from, int to) {
      for (var s = from; s <= to; s++) {
        playback.onProgress(Duration(seconds: s));
      }
    }

    test('one left while it was being prepared (it never started) is not '
        'told, also when it was skipped; one started is', () {
      fakeAsync((async) {
        attachPlayback(async);
        final first = _stream('1');
        queue.setQueue([first, _stream('2'), _stream('3')]);
        async.flushMicrotasks();
        // «Siguiente» while «Preparando…»: the manager closes the session it
        // abandoned with a stop at 0, which isn't a skip.
        playback.stopped(first, Duration.zero, false);
        queue.next(manual: true);
        async.elapse(const Duration(seconds: 1));
        expect(reports, isEmpty);
        // The one prepared ahead that never came to sound, likewise.
        playback.stopped(_stream('3'), Duration.zero, false);
        async.elapse(const Duration(seconds: 1));
        expect(reports, isEmpty);

        final second = queue.currentItem as AggregatedItem;
        playback.started(second);
        async.flushMicrotasks();
        hear(0, 20);
        playback.stopped(second, const Duration(seconds: 20), false);
        queue.next(manual: true);
        async.elapse(const Duration(seconds: 1));
        expect(reports.single.endedBy, 'next');
        expect(reports.single.played, closeTo(20, 0.01));
        // Told once: a second stop of the same start says nothing.
        playback.stopped(second, const Duration(seconds: 20), false);
        async.elapse(const Duration(seconds: 1));
        expect(reports, hasLength(1));
        playback.detach();
      });
    });

    test('asked again for its sound (an error recovered, another track): '
        'one listen with all that was heard', () {
      fakeAsync((async) {
        attachPlayback(async);
        final song = _stream('1');
        queue.setQueue([song, _stream('2')]);
        async.flushMicrotasks();
        playback.started(song);
        hear(0, 30);
        // The manager stops it and opens it again; `listen` takes a while.
        restarting = true;
        playback.stopped(song, const Duration(seconds: 30), false);
        async.elapse(const Duration(seconds: 8));
        expect(reports, isEmpty);
        restarting = false;
        playback.started(song);
        async.elapse(const Duration(seconds: 1));
        expect(reports, isEmpty);
        hear(30, 199);
        playback.stopped(song, const Duration(seconds: 199), false);
        expect(reports.single.endedBy, 'natural');
        expect(reports.single.played, closeTo(199, 0.01));

        // Opened again at once, before the queue is looked at.
        playback.started(song);
        hear(0, 10);
        playback.stopped(song, const Duration(seconds: 10), false);
        playback.started(song);
        async.elapse(const Duration(seconds: 1));
        hear(10, 40);
        queue.next(manual: true);
        playback.stopped(song, const Duration(seconds: 40), false);
        async.elapse(const Duration(seconds: 1));
        expect(reports, hasLength(2));
        expect(reports.last.endedBy, 'next');
        expect(reports.last.played, closeTo(40, 0.01));
        playback.detach();
      });
    });

    test('stopped for good while the player was busy still goes as a stop, '
        'in the end', () {
      fakeAsync((async) {
        attachPlayback(async);
        final song = _stream('1');
        queue.setQueue([song]);
        async.flushMicrotasks();
        playback.started(song);
        hear(0, 30);
        restarting = true;
        playback.stopped(song, const Duration(seconds: 30), false);
        async.elapse(const Duration(seconds: 20));
        expect(reports, isEmpty);
        async.elapse(const Duration(seconds: 12));
        expect(reports.single.endedBy, 'stop');
        expect(reports.single.played, closeTo(30, 0.01));
        playback.detach();
      });
    });

    test('its album\'s genre goes with it, when the service said it', () {
      fakeAsync((async) {
        attachPlayback(async);
        final song = kostvStreamItem(
          deezerId: '5',
          title: 'Canción 5',
          serverId: _server,
          artist: 'Lola',
          durationSeconds: 200,
          genres: const [' ', 'Pop', 'Dance'],
        );
        queue.setQueue([song]);
        async.flushMicrotasks();
        playback.started(song);
        playback.stopped(song, const Duration(seconds: 199), false);
        expect(reports.single.genre, 'Pop');
        playback.started(_stream('6'));
        playback.stopped(_stream('6'), const Duration(seconds: 199), false);
        expect(reports.last.genre, isNull);
        playback.detach();
      });
    });
  });

  group('the queue kept for later', () {
    test('keeps what the songs that aren\'t at home were', () {
      final song = _stream('1');
      final session = LastPlaybackSession(
        serverId: _server,
        itemIds: ['h', song.id],
        index: 1,
        positionMs: 3000,
        title: song.name,
        streamItems: {song.id: song.rawData},
      );
      final back = LastPlaybackSession.fromJson(session.toJson())!;
      final raw = back.streamItems[song.id]!;
      final again = AggregatedItem(
        id: song.id,
        serverId: _server,
        rawData: raw,
      );
      expect(isKostvStream(again), isTrue);
      expect(KostvStreamInfo.of(again)!.cover, 'https://cdn.example/1.jpg');
      expect(again.name, 'Canción 1');
      final plain = LastPlaybackSession.fromJson({
        'serverId': _server,
        'itemIds': ['h'],
      })!;
      expect(plain.streamItems, isEmpty);
      expect(plain.toJson().containsKey('streamItems'), isFalse);
    });
  });

  group('QueueService.replaceAt', () {
    test('in its place, also for when shuffle is turned off', () {
      final queue = QueueService();
      final a = _home('a');
      final b = _stream('2');
      final c = _home('c');
      queue.setQueue([a, b, c], startIndex: 1);
      queue.toggleShuffle();
      final at = queue.items.indexOf(b);
      final home = _home('j2');
      queue.replaceAt(at, home);
      expect(queue.items, contains(home));
      expect(queue.items, isNot(contains(b)));
      expect(queue.currentItem, home);
      queue.toggleShuffle();
      expect(queue.items, [a, home, c]);
      expect(queue.currentIndex, 1);
    });
  });
}

class _Server extends Fake implements PlayerService {
  _Server(this.events);

  final List<String> events;

  @override
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    PlaybackQueueModes? queueModes,
  }) async => events.add('start ${mediaItem.id}');

  @override
  Future<void> onPlaybackProgress(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool isPaused = false,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? volumeLevel,
    bool? isMuted,
    PlaybackQueueModes? queueModes,
  }) async => events.add('progress ${mediaItem.id}');

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
    bool failed = false,
  }) async => events.add('stop ${mediaItem.id}');

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async =>
      events.add('transcoding');
}

class _Offline extends Fake implements OfflineRepository {}
