import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/cast/cast_provider.dart';
import 'package:moonfin/data/services/cast/cast_service.dart';
import 'package:moonfin/data/services/cast/cast_target.dart';
import 'package:moonfin/data/services/cast/cast_transport_controls.dart';

/// A receiver reached through the server, as a Jellyfin session is.
class _Receiver
    implements CastProvider, CastTransportControls, PollableRemoteState {
  /// What the next polls answer; null is the server not answering.
  RemotePlaybackSnapshot? snapshot = const RemotePlaybackSnapshot(
    state: 'playing',
  );
  bool stopFails = false;

  @override
  Set<CastTargetKind> get supportedKinds => {CastTargetKind.jellyfinSession};

  @override
  Set<CastTargetKind> get controllableKinds => {CastTargetKind.jellyfinSession};

  @override
  Future<List<CastTarget>> discoverTargets(AggregatedItem item) async =>
      const [];

  @override
  Future<void> playToTarget(
    CastTarget target, {
    required AggregatedItem item,
    List<AggregatedItem>? queueItems,
    int? startPositionTicks,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {}

  @override
  Future<RemotePlaybackSnapshot?> fetchRemoteSnapshot(
    CastTargetKind kind,
  ) async => snapshot;

  @override
  Future<void> stop(CastTargetKind kind) async {
    // A session that is gone: the server answers 404.
    if (stopFails) throw StateError('404');
  }

  @override
  Future<void> play(CastTargetKind kind) async {}

  @override
  Future<void> pause(CastTargetKind kind) async {}

  @override
  Future<void> seek(CastTargetKind kind, {required int positionTicks}) async {}

  @override
  Future<double?> getVolume(CastTargetKind kind) async => null;

  @override
  Future<void> setVolume(CastTargetKind kind, {required double volume}) async {}
}

const _target = CastTarget(
  id: 'living-room',
  kind: CastTargetKind.jellyfinSession,
  title: 'Salón',
);

final _item = AggregatedItem(
  id: 'movie',
  serverId: 'home',
  rawData: const {'Id': 'movie', 'Type': 'Movie'},
);

void main() {
  late _Receiver receiver;
  late CastService service;

  setUp(() {
    receiver = _Receiver();
    service = CastService([receiver]);
  });

  test('Stop clears the bar even when the receiver can\'t answer', () async {
    await service.playToTarget(_target, item: _item);
    expect(service.activeKind, CastTargetKind.jellyfinSession);
    receiver.stopFails = true;

    await expectLater(
      service.stop(CastTargetKind.jellyfinSession),
      throwsStateError,
    );
    expect(service.activeKind, isNull);
    expect(service.castItemNotifier.value, isNull);
  });

  test('a person switch forgets the cast', () async {
    await service.playToTarget(_target, item: _item);
    service.endForSessionChange();
    expect(service.activeKind, isNull);
    expect(service.activeTargetNotifier.value, isNull);
  });

  test('the cast ends by itself once the receiver is gone', () {
    fakeAsync((async) {
      service.playToTarget(_target, item: _item);
      async.flushMicrotasks();
      expect(service.remoteStateNotifier.value, 'playing');

      receiver.snapshot = const RemotePlaybackSnapshot(sessionGone: true);
      async.elapse(const Duration(seconds: 10));
      expect(service.activeKind, isNotNull);
      async.elapse(const Duration(seconds: 5));
      expect(service.activeKind, isNull);
    });
  });

  test('a receiver that stopped playing ends the cast too', () {
    fakeAsync((async) {
      service.playToTarget(_target, item: _item);
      async.flushMicrotasks();

      receiver.snapshot = const RemotePlaybackSnapshot();
      async.elapse(const Duration(seconds: 15));
      expect(service.activeKind, isNull);
    });
  });

  test('a server that doesn\'t answer for a while ends nothing', () {
    fakeAsync((async) {
      service.playToTarget(_target, item: _item);
      async.flushMicrotasks();

      receiver.snapshot = null;
      async.elapse(const Duration(minutes: 2));
      expect(service.activeKind, CastTargetKind.jellyfinSession);
    });
  });

  test('a title still opening there gets longer before it ends', () {
    fakeAsync((async) {
      receiver.snapshot = const RemotePlaybackSnapshot();
      service.playToTarget(_target, item: _item);
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 30));
      expect(service.activeKind, isNotNull);

      receiver.snapshot = const RemotePlaybackSnapshot(state: 'playing');
      async.elapse(const Duration(seconds: 5));
      expect(service.remoteStateNotifier.value, 'playing');

      async.elapse(const Duration(minutes: 5));
      expect(service.activeKind, isNotNull);
    });
  });
}
