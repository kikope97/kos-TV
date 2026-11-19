import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../models/aggregated_library.dart';
import '../services/socket_handler.dart';

/// The user's own views. Anything hidden from My Media is left out unless
/// [includeHidden] is set, which callers that apply their own exclude
/// filtering pass so the list isn't filtered twice.
Future<List<AggregatedLibrary>> loadUserViews(
  MediaServerClient client, {
  bool includeHidden = false,
}) async => _parseUserViews(
  await client.userViewsApi.getUserViews(includeHidden: includeHidden),
);

List<AggregatedLibrary> _parseUserViews(Map<String, dynamic> response) {
  final items = response['Items'] as List? ?? [];

  return items.whereType<Map>().map((item) {
    final data = item.cast<String, dynamic>();
    return AggregatedLibrary(
      id: data['Id']?.toString() ?? '',
      name: data['Name']?.toString() ?? '',
      collectionType: data['CollectionType'] as String? ?? '',
      serverId: data['ServerId']?.toString() ?? '',
      primaryImageAspectRatio: (data['PrimaryImageAspectRatio'] as num?)
          ?.toDouble(),
      imageTags: data['ImageTags'] != null
          ? Map<String, dynamic>.from(data['ImageTags'] as Map)
          : null,
      backdropImageTags: (data['BackdropImageTags'] as List?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }).toList();
}

/// The My Media exclude list, or null when it can't be read.
Future<Set<String>?> _excludesFrom(Future<UserConfiguration> config) async {
  try {
    return (await config).myMediaExcludes.toSet();
  } catch (_) {
    return null;
  }
}

/// The views response with anything hidden from My Media removed. The server
/// filters by the exclude list itself, so ask for the full list and apply it
/// here instead. If the list can't be read, let the server filter so hidden
/// libraries don't leak through.
Future<Map<String, dynamic>> loadVisibleUserViews(
  MediaServerClient client,
) async {
  final viewsFuture = client.userViewsApi.getUserViews(includeHidden: true);
  final excludes = await _excludesFrom(client.usersApi.getUserConfiguration());
  final response = await viewsFuture;

  if (excludes == null) return client.userViewsApi.getUserViews();
  return _filterExcludedViews(response, excludes);
}

Map<String, dynamic> _filterExcludedViews(
  Map<String, dynamic> response,
  Set<String> excludes,
) {
  if (excludes.isEmpty) return response;
  final items = (response['Items'] as List? ?? [])
      .where(
        (item) => !excludes.contains(
          (item as Map<String, dynamic>)['Id']?.toString() ?? '',
        ),
      )
      .toList();
  return {...response, 'Items': items};
}

class UserViewsRepository extends ChangeNotifier {
  final MediaServerClient _client;
  UserConfiguration? _cachedConfig;

  /// Kos TV: how long a run of library changes (a scan) is let settle before
  /// the views are read again.
  @visibleForTesting
  static Duration changeSettle = const Duration(seconds: 5);

  StreamSubscription<ServerWebSocketMessage>? _eventsSub;
  StreamSubscription<void>? _connectionsSub;
  Timer? _checkTimer;
  bool _stopped = false;

  /// Set when following the session socket rather than streams handed in.
  bool _followsSessionSocket = false;

  // Concurrent callers share one in-flight request, so home mounting with
  // several rows and the nav chrome all asking at once costs one round trip
  // instead of a socket each.
  Future<List<AggregatedLibrary>>? _inFlightViews;
  Future<Map<String, dynamic>>? _inFlightHiddenResponse;
  Future<UserConfiguration>? _inFlightConfig;

  /// [serverEvents] and [reconnections] default to the session socket's.
  UserViewsRepository(
    this._client, {
    Stream<ServerWebSocketMessage>? serverEvents,
    Stream<void>? reconnections,
  }) {
    final socket =
        serverEvents == null && GetIt.instance.isRegistered<SocketHandler>()
        ? GetIt.instance<SocketHandler>()
        : null;
    _followsSessionSocket = socket != null;
    _eventsSub = (serverEvents ?? socket?.events)?.listen(_onServerEvent);
    _connectionsSub = (reconnections ?? socket?.connections)?.listen(
      (_) {
        if (!_replaced()) _scheduleCheck();
      },
    );
  }

  /// The session socket outlives this repository, which is replaced on a
  /// sign-out or user switch, so one left behind stops following it.
  bool _replaced() {
    if (_stopped) return true;
    if (!_followsSessionSocket) return false;
    if (GetIt.instance.isRegistered<UserViewsRepository>(instance: this)) {
      return false;
    }
    stopFollowingServer();
    return true;
  }

  /// Kos TV: the views and the configuration are kept for the session, so a
  /// change made on the server (a library the admin gave or took away, one
  /// the person hid or moved on another device) is picked up from the socket.
  void _onServerEvent(ServerWebSocketMessage event) {
    if (_replaced()) return;
    if (event is ServerEventMessage && event.type == 'UserUpdated') {
      final id = _normalizeId(event.data['Id']?.toString());
      final mine = _normalizeId(_client.userId);
      if (id == null || mine == null || id != mine) return;
      invalidateConfigCache();
      invalidateViews();
      return;
    }
    if (event is LibraryChangedMessage &&
        (event.itemsAdded.isNotEmpty || event.itemsRemoved.isNotEmpty)) {
      _scheduleCheck();
    }
  }

  static String? _normalizeId(String? id) {
    final normalized = id?.replaceAll('-', '').toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  /// Reads the views again once things settle, and tells the nav chrome only
  /// when the list changed. Nothing cached means the next read asks anyway.
  void _scheduleCheck() {
    if (_stopped) return;
    _checkTimer?.cancel();
    _checkTimer = Timer(changeSettle, () => unawaited(_checkForChanges()));
  }

  Future<void> _checkForChanges() async {
    final cachedViews = _hiddenResponseCache;
    final cachedConfig = _cachedConfig;
    if (cachedViews == null && cachedConfig == null) return;
    try {
      final results = await Future.wait<Object>([
        _client.userViewsApi.getUserViews(includeHidden: true),
        _client.usersApi.getUserConfiguration(),
      ]);
      if (_stopped) return;
      final views = results[0] as Map<String, dynamic>;
      final config = results[1] as UserConfiguration;
      final viewsChanged =
          cachedViews != null && !_sameViews(cachedViews, views);
      final excludesChanged =
          cachedConfig != null &&
          !listEquals(cachedConfig.myMediaExcludes, config.myMediaExcludes);
      // Only replace what is still the copy this check started from.
      if (identical(_cachedConfig, cachedConfig)) _cachedConfig = config;
      if (!viewsChanged && !excludesChanged) return;
      if (identical(_hiddenResponseCache, cachedViews)) {
        _hiddenResponseCache = views;
      }
      notifyListeners();
    } catch (_) {
      // Unreachable now; the next change or reconnect asks again.
    }
  }

  static bool _sameViews(Map<String, dynamic> a, Map<String, dynamic> b) {
    List<String> shape(Map<String, dynamic> response) => [
      for (final item in (response['Items'] as List? ?? const []))
        if (item is Map) '${item['Id']}|${item['Name']}|${item['CollectionType']}',
    ];
    return listEquals(shape(a), shape(b));
  }

  /// Stops following the server's changes. The repository stays usable,
  /// since nav chrome still mounted may hold it and remove its listener later.
  void stopFollowingServer() {
    _stopped = true;
    _checkTimer?.cancel();
    _eventsSub?.cancel();
    _connectionsSub?.cancel();
  }

  Future<List<AggregatedLibrary>> getAllViews() =>
      _inFlightViews ??= loadUserViews(
        _client,
      ).whenComplete(() => _inFlightViews = null);

  // Kept for the session, since every screen's nav chrome asks for the views
  // when it mounts. [invalidateViews] and a configuration change drop it.
  Map<String, dynamic>? _hiddenResponseCache;

  Future<Map<String, dynamic>> _hiddenResponse() {
    final cached = _hiddenResponseCache;
    if (cached != null) return Future.value(cached);
    return _inFlightHiddenResponse ??= _client.userViewsApi
        .getUserViews(includeHidden: true)
        .then((response) => _hiddenResponseCache = response)
        .whenComplete(() => _inFlightHiddenResponse = null);
  }

  /// Has the next read ask the server again, and tells the nav chrome to
  /// reload its libraries.
  void invalidateViews() {
    _hiddenResponseCache = null;
    notifyListeners();
  }

  Future<List<AggregatedLibrary>> getAllViewsIncludingHidden() async =>
      _parseUserViews(await _hiddenResponse());

  /// The raw views response with anything hidden from My Media removed, for
  /// callers that build rows straight from the server shape.
  Future<Map<String, dynamic>> getVisibleViewsResponse() async {
    final responseFuture = _hiddenResponse();
    final excludes = await _excludesFrom(cachedUserConfiguration());
    final response = await responseFuture;
    if (excludes == null) return _client.userViewsApi.getUserViews();
    return _filterExcludedViews(response, excludes);
  }

  Future<List<AggregatedLibrary>> getUserViews() async {
    final excludes = await _excludesFrom(cachedUserConfiguration());
    if (excludes == null) return getAllViews();

    final views = await getAllViewsIncludingHidden();
    if (excludes.isEmpty) return views;
    return views.where((v) => !excludes.contains(v.id)).toList();
  }

  /// The configuration as last read, fetching it once when nothing is cached.
  Future<UserConfiguration> cachedUserConfiguration() => _cachedConfig != null
      ? Future.value(_cachedConfig)
      : getUserConfiguration();

  /// What the user hid from My Media, read from the cached configuration so a
  /// caller can ask on every row without a round trip each time. Empty when
  /// nothing is hidden or the list cant be read.
  Future<Set<String>> getMyMediaExcludes() async =>
      await _excludesFrom(cachedUserConfiguration()) ?? const {};

  Future<UserConfiguration> getUserConfiguration() =>
      _inFlightConfig ??= _client.usersApi
          .getUserConfiguration()
          .then((config) => _cachedConfig = config)
          .whenComplete(() => _inFlightConfig = null);

  Future<void> updateUserConfiguration(UserConfiguration config) async {
    await _client.usersApi.updateUserConfiguration(config);
    _cachedConfig = config;
    // The server orders the views by this configuration.
    invalidateViews();
  }

  void invalidateConfigCache() => _cachedConfig = null;
}
