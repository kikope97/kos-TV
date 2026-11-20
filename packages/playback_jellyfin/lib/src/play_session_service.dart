import 'dart:convert';

import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import 'playback_exit_beacon.dart';

class PlaySessionService implements PlayerService {
  final MediaServerClient _client;

  PlaySessionService(this._client);

  /// Kos TV: the token each session was started with, keyed by
  /// [_sessionKey]. The Jellyfin client is one per server and switching
  /// person swaps its token in place, so a progress or stop for the person
  /// before (the manager sends a second stop once a late progress settles)
  /// would otherwise land in the new person's watch data. Entries outlive
  /// the first stop for that second one, so the map is capped instead.
  final Map<String, String?> _startTokens = {};
  static const _maxStartTokens = 64;

  String _sessionKey(dynamic mediaItem, StreamResolutionResult resolution) {
    final playSessionId = resolution.playSessionId;
    if (playSessionId != null && playSessionId.isNotEmpty) {
      return 'session:$playSessionId';
    }
    return 'item:${MediaStreamResolver.extractItemId(mediaItem)}'
        '|${resolution.mediaSourceId}';
  }

  void _rememberStartToken(
    dynamic mediaItem,
    StreamResolutionResult resolution,
  ) {
    final key = _sessionKey(mediaItem, resolution);
    _startTokens.remove(key);
    _startTokens[key] = _client.accessToken;
    while (_startTokens.length > _maxStartTokens) {
      _startTokens.remove(_startTokens.keys.first);
    }
  }

  /// True when [resolution] was started under another token than the
  /// client holds now: its person's stop already went out before the
  /// switch, and anything more would be reported as the new person.
  bool _startedByAnotherPerson(
    dynamic mediaItem,
    StreamResolutionResult resolution,
  ) {
    final key = _sessionKey(mediaItem, resolution);
    if (!_startTokens.containsKey(key)) return false;
    return _startTokens[key] != _client.accessToken;
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
    final report = PlaybackStartReport(
      itemId: MediaStreamResolver.extractItemId(mediaItem),
      mediaSourceId: resolution.mediaSourceId,
      playSessionId: resolution.playSessionId,
      playMethod: _toPlayMethod(resolution.playMethod),
      positionTicks: positionTicks,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      repeatMode: _repeatMode(queueModes),
      playbackOrder: _playbackOrder(queueModes),
    );
    _rememberStartToken(mediaItem, resolution);
    await _client.playbackApi.reportPlaybackStart(report.toJson());
    _armExitBeacon(mediaItem, resolution, positionTicks ?? 0);
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
    if (_startedByAnotherPerson(mediaItem, resolution)) return;
    final report = PlaybackProgressReport(
      itemId: MediaStreamResolver.extractItemId(mediaItem),
      mediaSourceId: resolution.mediaSourceId,
      playSessionId: resolution.playSessionId,
      positionTicks: position.inMicroseconds * 10,
      isPaused: isPaused,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      volumeLevel: volumeLevel,
      isMuted: isMuted ?? false,
      repeatMode: _repeatMode(queueModes),
      playbackOrder: _playbackOrder(queueModes),
    );
    await _client.playbackApi.reportPlaybackProgress(report.toJson());
    _armExitBeacon(mediaItem, resolution, position.inMicroseconds * 10);
  }

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
    bool failed = false,
  }) async {
    PlaybackExitBeacon.disarm();
    final report = _stopReport(
      mediaItem,
      resolution,
      position.inMicroseconds * 10,
      failed: failed,
    );
    final otherPerson = _startedByAnotherPerson(mediaItem, resolution);
    Object? reportError;
    StackTrace? reportStackTrace;
    try {
      if (!_isAudiobook(mediaItem) && !otherPerson) {
        await _client.playbackApi.reportPlaybackStopped(report.toJson());
      }
    } catch (error, stackTrace) {
      reportError = error;
      reportStackTrace = stackTrace;
    }

    final liveStreamId = resolution.liveStreamId;
    if (releaseLiveStream && liveStreamId != null && liveStreamId.isNotEmpty) {
      try {
        await _client.playbackApi.closeLiveStream(liveStreamId);
      } catch (_) {}
    }

    if (reportError != null) {
      Error.throwWithStackTrace(reportError, reportStackTrace!);
    }
  }

  @override
  Future<void> closeLiveStream(String liveStreamId) async {
    if (liveStreamId.isEmpty) return;
    try {
      await _client.playbackApi.closeLiveStream(liveStreamId);
    } catch (_) {}
  }

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {
    final playSessionId = resolution.playSessionId;
    if (playSessionId == null || playSessionId.isEmpty) return;
    try {
      await _client.playbackApi.stopActiveEncodings(
        deviceId: _client.deviceInfo.id,
        playSessionId: playSessionId,
      );
    } catch (_) {}
  }

  void _armExitBeacon(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    int positionTicks,
  ) {
    if (!PlaybackExitBeacon.supported || _isAudiobook(mediaItem)) {
      return;
    }
    final token = _client.accessToken;
    if (token == null || token.isEmpty) {
      return;
    }
    final report = _stopReport(mediaItem, resolution, positionTicks);
    PlaybackExitBeacon.arm(
      url: '${_client.baseUrl}/Sessions/Playing/Stopped?ApiKey=$token',
      body: jsonEncode(report.toJson()),
    );
  }

  PlaybackStopReport _stopReport(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    int positionTicks, {
    bool failed = false,
  }) {
    return PlaybackStopReport(
      itemId: MediaStreamResolver.extractItemId(mediaItem),
      mediaSourceId: resolution.mediaSourceId,
      playSessionId: resolution.playSessionId,
      positionTicks: positionTicks,
      failed: failed,
    );
  }

  /// Kos TV: the queue's modes as Jellyfin's play state names them, so the
  /// server plugin knows whether the music was on repeat or shuffled.
  static String? _repeatMode(PlaybackQueueModes? modes) =>
      switch (modes?.repeatMode) {
        null => null,
        RepeatMode.none => 'RepeatNone',
        RepeatMode.repeatAll => 'RepeatAll',
        RepeatMode.repeatOne => 'RepeatOne',
      };

  static String? _playbackOrder(PlaybackQueueModes? modes) => modes == null
      ? null
      : modes.shuffled
      ? 'Shuffle'
      : 'Default';

  static PlayMethod _toPlayMethod(StreamPlayMethod method) => switch (method) {
    StreamPlayMethod.directPlay => PlayMethod.directPlay,
    StreamPlayMethod.directStream => PlayMethod.directStream,
    StreamPlayMethod.transcode => PlayMethod.transcode,
  };

  bool _isAudiobook(dynamic mediaItem) {
    if (mediaItem is Map) {
      final type = mediaItem['Type']?.toString().toLowerCase();
      final mediaType = mediaItem['MediaType']?.toString().toLowerCase();
      return type == 'audiobook' || type == 'audio_book' || mediaType == 'audiobook';
    }
    try {
      final type = mediaItem.type?.toString().toLowerCase();
      final mediaType = mediaItem.mediaType?.toString().toLowerCase();
      return type == 'audiobook' || type == 'audio_book' || mediaType == 'audiobook';
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    PlaybackExitBeacon.disarm();
  }
}
