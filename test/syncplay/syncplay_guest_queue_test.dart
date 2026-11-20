import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/database/offline_database.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/offline/connectivity_aware_media_server_client.dart';
import 'package:moonfin/data/offline/offline_catalog.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/data/services/pending_rating_store.dart';
import 'package:moonfin/data/services/storage_path_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/syncplay/syncplay_manager.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestBackend extends Fake implements PlayerBackend {
  final positions = StreamController<Duration>.broadcast(sync: true);
  final playingController = StreamController<bool>.broadcast(sync: true);
  final bufferingController = StreamController<bool>.broadcast(sync: true);
  bool playing = false;
  Duration currentPosition = Duration.zero;
  Duration currentDuration = Duration.zero;

  void emitPosition(Duration position) {
    currentPosition = position;
    positions.add(position);
  }

  @override
  Duration get position => currentPosition;

  @override
  Duration get duration => currentDuration;

  @override
  Duration get buffer => Duration.zero;

  @override
  bool get isPlaying => playing;

  @override
  bool get playWhenReady => playing;

  @override
  double get playbackSpeed => 1.0;

  @override
  bool get isBuffering => false;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Stream<Duration> get durationStream => const Stream<Duration>.empty();

  @override
  Stream<Duration> get bufferStream => const Stream<Duration>.empty();

  @override
  Stream<bool> get playingStream => playingController.stream;

  @override
  Stream<bool> get bufferingStream => bufferingController.stream;

  @override
  Stream<bool> get completedStream => const Stream<bool>.empty();

  @override
  Stream<Map<String, dynamic>>? get errorStream => null;

  @override
  bool get supportsRuntimeTrackSelection => false;

  @override
  bool get supportsDirectPlayAudioSwitch => false;

  @override
  bool get canRenderBitmapSubtitles => false;

  @override
  bool get requiresStartupMediaReadyCheck => false;

  @override
  bool get nativelyHandlesStartPosition => true;

  @override
  Map<String, dynamic> getDeviceProfile({
    bool useProgressiveTranscode = false,
  }) => <String, dynamic>{};

  @override
  Future<void> play(
    dynamic mediaItem, {
    Duration startPosition = Duration.zero,
  }) async {
    currentPosition = startPosition;
    playing = true;
  }

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> resume() async => playing = true;

  @override
  Future<void> stop() async => playing = false;

  @override
  Future<void> setSubtitleRendererMode(SubtitleRendererMode mode) async {}

  @override
  Future<void> waitForTracksReady() async {}

  @override
  void dispose() {
    positions.close();
    playingController.close();
    bufferingController.close();
  }
}

class _TestResolver extends MediaStreamResolver {
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
  }) async => StreamResolutionResult(
    streamUrl: 'https://example.test/stream',
    mediaSourceId: 'source',
    playSessionId: 'session',
    playMethod: StreamPlayMethod.directStream,
  );
}

class _TestService extends Fake implements PlayerService {
  final stops = <Duration>[];

  @override
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    PlaybackQueueModes? queueModes,
  }) async {}

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
  }) async {}

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
    bool failed = false,
  }) async => stops.add(position);

  @override
  Future<void> closeLiveStream(String liveStreamId) async {}

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {}

  @override
  void dispose() {}
}

class _FakeSyncPlayApi extends Fake implements SyncPlayApi {
  final List<String> nextItemCalls = [];
  Object? nextError;
  Future<void> Function(String playlistItemId)? onNextItem;

  @override
  Future<UtcTimeResponse> getUtcTime() async => const UtcTimeResponse(
    requestReceptionTimeMs: 1000,
    responseTransmissionTimeMs: 1000,
  );

  @override
  Future<void> nextItem(String playlistItemId) async {
    nextItemCalls.add(playlistItemId);
    final handler = onNextItem;
    if (handler != null) {
      await handler(playlistItemId);
      return;
    }
    final error = nextError;
    if (error != null) throw error;
  }

  @override
  Future<void> sendPing(int ping) async {}

  @override
  Future<void> sendReady({
    required bool isPlaying,
    required String playlistItemId,
    required int positionTicks,
    DateTime? when,
  }) async {}

  @override
  Future<void> leaveGroup() async {}
}

class _FakeItemsApi extends Fake implements ItemsApi {
  final Map<String, Map<String, dynamic>> items = {
    'ep1': {'Id': 'ep1', 'Type': 'Episode', 'Name': 'Episode 1'},
    'ep2': {'Id': 'ep2', 'Type': 'Episode', 'Name': 'Episode 2'},
    'ep3': {'Id': 'ep3', 'Type': 'Episode', 'Name': 'Episode 3'},
  };
  Completer<void>? getItemGate;
  Future<void> Function(String itemId)? onGetItem;

  @override
  Future<Map<String, dynamic>> getItem(
    String itemId, {
    String? mediaSourceId,
    String? fields,
  }) async {
    await onGetItem?.call(itemId);
    await getItemGate?.future;
    return items[itemId] ?? {'Id': itemId, 'Type': 'Episode'};
  }
}

class _MockMediaServerClient extends Mock implements MediaServerClient {}

class _FakeImageApi extends Fake implements ImageApi {}

class _FakeClientFactory extends Fake implements MediaServerClientFactory {
  _FakeClientFactory(this._clients);

  final Map<String, MediaServerClient> _clients;

  @override
  Map<String, MediaServerClient> get clients => _clients;

  // Like the real factory, a connectivity wrapper matches the client inside it.
  @override
  String serverIdOf(MediaServerClient client) {
    final target = client is ConnectivityAwareMediaServerClient
        ? client.onlineClient
        : client;
    for (final entry in _clients.entries) {
      if (identical(entry.value, target)) return entry.key;
    }
    return client.baseUrl;
  }
}

class _FakeUserPreferences extends Fake implements UserPreferences {
  @override
  T get<T>(Preference<T> preference) => preference.defaultValue;
}

void main() {
  late PlaybackManager playbackManager;
  late SyncPlayManager syncPlayManager;
  late _MockMediaServerClient raw;

  setUp(() async {
    await GetIt.instance.reset();
    playbackManager = PlaybackManager()
      ..setBackend(_TestBackend())
      ..setResolver(_TestResolver())
      ..setPlayerService(_TestService());
    raw = _MockMediaServerClient();
    when(() => raw.baseUrl).thenReturn('http://jf');
    when(() => raw.serverType).thenReturn(ServerType.jellyfin);
    when(() => raw.syncPlayApi).thenReturn(_FakeSyncPlayApi());
    when(() => raw.itemsApi).thenReturn(_FakeItemsApi());
    when(() => raw.imageApi).thenReturn(_FakeImageApi());
    GetIt.instance.registerSingleton<MediaServerClientFactory>(
      _FakeClientFactory({'server1': raw}),
    );
    syncPlayManager = SyncPlayManager(playbackManager, _FakeUserPreferences());
  });

  tearDown(() async {
    syncPlayManager.dispose();
    playbackManager.dispose();
    await GetIt.instance.reset();
  });

  // Kos TV: adapted from upstream f846a8e66.
  test('a guest loads the queue the host starts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferenceStore();
    await prefs.init();
    final db = OfflineDatabase(DatabaseConnection(NativeDatabase.memory()));
    final repo = OfflineRepository(db);
    final catalog = OfflineCatalog(repo);
    addTearDown(() async {
      catalog.dispose();
      await db.close();
    });

    // The app registers its own wrapper around the factory's client and never
    // hands the manager a client.
    GetIt.instance.registerSingleton<MediaServerClient>(
      ConnectivityAwareMediaServerClient(
        raw,
        useOffline: () => false,
        catalog: catalog,
        storagePath: StoragePathService(),
        pendingRatings: PendingRatingStore(prefs),
        offlineRepo: repo,
      ),
    );
    syncPlayManager.setActiveClient(null);

    syncPlayManager.handleGroupUpdate(
      const SyncPlayGroupUpdate(
        groupId: 'g2',
        type: SyncPlayGroupUpdateType.groupJoined,
        payload: SyncPlayGroupJoinedPayload(
          SyncPlayGroupInfo(
            groupId: 'g2',
            groupName: 'Group',
            state: SyncPlayGroupState.idle,
          ),
        ),
      ),
    );
    syncPlayManager.handleGroupUpdate(
      const SyncPlayGroupUpdate(
        groupId: 'g2',
        type: SyncPlayGroupUpdateType.playQueue,
        payload: SyncPlayPlayQueuePayload(
          SyncPlayPlayQueueUpdate(
            reason: SyncPlayQueueUpdateReason.newPlaylist,
            lastUpdate: '2026-01-01T00:01:00.000Z',
            playlist: [SyncPlayQueueItem(itemId: 'ep3', playlistItemId: 'pl3')],
            playingItemIndex: 0,
            startPositionTicks: 0,
            isPlaying: false,
            shuffleMode: SyncPlayShuffleMode.sorted,
            repeatMode: SyncPlayRepeatMode.repeatNone,
          ),
        ),
      ),
    );
    await pumpEventQueue();

    expect(
      playbackManager.queueService.currentItem,
      isA<AggregatedItem>().having((item) => item.id, 'id', 'ep3'),
    );
  });
}
