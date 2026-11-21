import 'package:playback_core/playback_core.dart';

import '../data/repositories/offline_repository.dart';
import '../data/services/stremfin/kostv_stream_song.dart';

/// Decorates the server play-session service so local-file playback keeps the
/// downloads DB position current (the source of truth for offline resume) and
/// only talks to the server when it's reachable.
///
/// The manager fires these callbacks unawaited, so server failures while
/// offline must be swallowed here. The sync service flushes the locally
/// recorded progress on reconnect.
class LocalAwarePlayerService implements PlayerService {
  final PlayerService _inner;
  final OfflineRepository _offlineRepo;
  final bool Function() _canReachServer;

  /// Kos TV: who is signed in, so progress kept for a download is synced
  /// later only as the person who watched it.
  final String? Function() _userId;

  /// Told which item stopped, how it played and where, once its stop has been
  /// reported, so whatever reacts to a finished episode reads the server's
  /// played state after it.
  final void Function(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position,
  )?
  _onStopped;

  /// Kos TV: told when a song that isn't at home ([isKostvStream]) stops,
  /// where and whether it failed. Nothing of it goes to the home server,
  /// which doesn't have it.
  final void Function(dynamic mediaItem, Duration position, bool failed)?
  _onStreamStopped;

  /// Kos TV: told when a song that isn't at home starts sounding, so only a
  /// song that started is told of when it stops (one left while it was
  /// being prepared never started).
  final void Function(dynamic mediaItem)? _onStreamStarted;

  /// Kos TV: the home server's song an out-of-home one turned out to be (the
  /// requests service said it is at home now), else the item itself.
  final dynamic Function(dynamic mediaItem) _homeOf;

  LocalAwarePlayerService(
    this._inner,
    this._offlineRepo, {
    required bool Function() canReachServer,
    String? Function()? userId,
    void Function(
      dynamic mediaItem,
      StreamResolutionResult resolution,
      Duration position,
    )?
    onStopped,
    void Function(dynamic mediaItem, Duration position, bool failed)?
    onStreamStopped,
    void Function(dynamic mediaItem)? onStreamStarted,
    dynamic Function(dynamic mediaItem)? homeOf,
  }) : _canReachServer = canReachServer,
       _userId = userId ?? (() => null),
       _onStopped = onStopped,
       _onStreamStopped = onStreamStopped,
       _onStreamStarted = onStreamStarted,
       _homeOf = homeOf ?? _same;

  static dynamic _same(dynamic item) => item;

  /// Kos TV: what the home server is told of [mediaItem] played as
  /// [resolution]: its home song when it has one, or null for an
  /// out-of-home song, which it isn't told of.
  dynamic _reported(dynamic mediaItem, StreamResolutionResult resolution) {
    if (isKostvStreamId(resolution.mediaSourceId)) return null;
    if (!isKostvStream(mediaItem)) return mediaItem;
    final home = _homeOf(mediaItem);
    return isKostvStream(home) ? null : home;
  }

  Future<void> _recordLocal(dynamic mediaItem, int positionTicks) async {
    try {
      final itemId = MediaStreamResolver.extractItemId(mediaItem);
      await _offlineRepo.updatePlaybackPosition(
        itemId,
        positionTicks,
        userId: _userId(),
      );
    } catch (_) {}
  }

  /// Sends [report] when the server is reachable, and says whether the
  /// server took it.
  Future<bool> _forward(Future<void> Function() report) async {
    if (!_canReachServer()) return false;
    try {
      await report();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    PlaybackQueueModes? queueModes,
  }) async {
    final reported = _reported(mediaItem, resolution);
    if (reported == null) {
      _onStreamStarted?.call(mediaItem);
      return;
    }
    mediaItem = reported;
    if (!resolution.isLocalMedia) {
      return _inner.onPlaybackStart(
        mediaItem,
        resolution,
        positionTicks: positionTicks,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        queueModes: queueModes,
      );
    }
    await _forward(
      () => _inner.onPlaybackStart(
        mediaItem,
        resolution,
        positionTicks: positionTicks,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        queueModes: queueModes,
      ),
    );
  }

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
  }) async {
    final reported = _reported(mediaItem, resolution);
    if (reported == null) return;
    mediaItem = reported;
    if (!resolution.isLocalMedia) {
      return _inner.onPlaybackProgress(
        mediaItem,
        resolution,
        position,
        isPaused: isPaused,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        volumeLevel: volumeLevel,
        isMuted: isMuted,
        queueModes: queueModes,
      );
    }
    await _recordLocal(mediaItem, position.inMicroseconds * 10);
    await _forward(
      () => _inner.onPlaybackProgress(
        mediaItem,
        resolution,
        position,
        isPaused: isPaused,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        volumeLevel: volumeLevel,
        isMuted: isMuted,
        queueModes: queueModes,
      ),
    );
  }

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
    bool failed = false,
  }) async {
    final reported = _reported(mediaItem, resolution);
    if (reported == null) {
      _onStreamStopped?.call(mediaItem, position, failed);
      return;
    }
    mediaItem = reported;
    try {
      if (!resolution.isLocalMedia) {
        return await _inner.onPlaybackStop(
          mediaItem,
          resolution,
          position,
          releaseLiveStream: releaseLiveStream,
          failed: failed,
        );
      }
      await _recordLocal(mediaItem, position.inMicroseconds * 10);
      final reported = await _forward(
        () => _inner.onPlaybackStop(
          mediaItem,
          resolution,
          position,
          releaseLiveStream: releaseLiveStream,
          failed: failed,
        ),
      );
      // Kos TV: the server already has this stop, so the next sync must not
      // send it again (as whoever is signed in by then).
      if (reported) {
        try {
          await _offlineRepo.markProgressSynced(
            MediaStreamResolver.extractItemId(mediaItem),
            userId: _userId(),
          );
        } catch (_) {}
      }
    } finally {
      _onStopped?.call(mediaItem, resolution, position);
    }
  }

  @override
  Future<void> closeLiveStream(String liveStreamId) =>
      _inner.closeLiveStream(liveStreamId);

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {
    if (resolution.isLocalMedia) return;
    if (isKostvStreamId(resolution.mediaSourceId)) return;
    return _inner.stopTranscoding(resolution);
  }

  @override
  void dispose() => _inner.dispose();
}
