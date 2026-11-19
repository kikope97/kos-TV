import 'package:playback_core/playback_core.dart';

import '../data/repositories/offline_repository.dart';

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
  }) : _canReachServer = canReachServer,
       _userId = userId ?? (() => null),
       _onStopped = onStopped;

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
  }) async {
    if (!resolution.isLocalMedia) {
      return _inner.onPlaybackStart(
        mediaItem,
        resolution,
        positionTicks: positionTicks,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
    }
    await _forward(
      () => _inner.onPlaybackStart(
        mediaItem,
        resolution,
        positionTicks: positionTicks,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
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
  }) async {
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
      ),
    );
  }

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
  }) async {
    try {
      if (!resolution.isLocalMedia) {
        return await _inner.onPlaybackStop(
          mediaItem,
          resolution,
          position,
          releaseLiveStream: releaseLiveStream,
        );
      }
      await _recordLocal(mediaItem, position.inMicroseconds * 10);
      final reported = await _forward(
        () => _inner.onPlaybackStop(
          mediaItem,
          resolution,
          position,
          releaseLiveStream: releaseLiveStream,
        ),
      );
      // Kos TV: the server already has this stop, so the next sync must not
      // send it again (as whoever is signed in by then).
      if (reported) {
        try {
          await _offlineRepo.markProgressSynced(
            MediaStreamResolver.extractItemId(mediaItem),
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
    return _inner.stopTranscoding(resolution);
  }

  @override
  void dispose() => _inner.dispose();
}
