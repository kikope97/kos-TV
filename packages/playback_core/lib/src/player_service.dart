import 'queue_service.dart';
import 'stream_resolution_result.dart';

/// Kos TV: the queue's repeat and shuffle modes, as a music report carries
/// them to the server (which keeps them in the session's play state). Null
/// in a report that doesn't carry them (anything but music).
class PlaybackQueueModes {
  const PlaybackQueueModes({required this.repeatMode, required this.shuffled});

  final RepeatMode repeatMode;
  final bool shuffled;

  @override
  bool operator ==(Object other) =>
      other is PlaybackQueueModes &&
      other.repeatMode == repeatMode &&
      other.shuffled == shuffled;

  @override
  int get hashCode => Object.hash(repeatMode, shuffled);
}

abstract class PlayerService {
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    PlaybackQueueModes? queueModes,
  });

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
  });

  /// Reports the stop and, when [releaseLiveStream] is set, closes the
  /// session's server live stream. A stop can be reported more than once for
  /// one session, but a shared live stream counts every close as a viewer
  /// leaving, so the caller sets it on at most one release attempt.
  ///
  /// Kos TV: [failed] when it stopped because it failed to play (only set
  /// for music: the server then keeps no watch data of it).
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
    bool failed = false,
  });

  /// Closes an opened server-side live stream session by id. Used to release the
  /// server's upstream connection when the client is playing the live source
  /// directly (so only one upstream connection remains). Default: no-op.
  Future<void> closeLiveStream(String liveStreamId) async {}

  /// Kills the server-side transcode job for [resolution]'s play session so a
  /// track-switch restart never races the old encoder. Default: no-op.
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {}

  void dispose();
}
