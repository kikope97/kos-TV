import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../auth/repositories/user_repository.dart';
import '../../data/models/aggregated_item.dart';
import '../../data/services/media_server_client_factory.dart';
import '../../util/server_url.dart';
import '../../util/signed_in_server_features.dart';
import 'kostv_collections.dart';
import 'socket_handler.dart';

/// Kos TV: whether [item] belongs to the server the person is signed in to.
/// Cards name their server by its address (Home rows, grids, detail pages)
/// or by the app's server id, so either counts. An item that names none is
/// taken as this server's.
bool isSignedInServerItem(
  AggregatedItem item, {
  required String? userServerId,
  required String baseUrl,
}) =>
    item.serverId.isEmpty ||
    isStoredServer(
      item.serverId,
      serverId: userServerId ?? '',
      baseUrl: baseUrl,
    );

/// Kos TV: whether the signed-in person may add [item] to a collection or
/// take it out of one. Jellyfin only lets those with «Manage collections»
/// (or an administrator) do it on their own server. Comparing the card's
/// server with the user's server id made everyone a manager, because the
/// cards name their server by its address.
bool canManageCollectionsFor(
  AggregatedItem item, {
  required MediaServerClient client,
  required String? userServerId,
  required bool userCanManageCollections,
  required bool isAdministrator,
}) {
  final requiresPermission =
      client.features.collectionsNeedPermission &&
      isSignedInServerItem(
        item,
        userServerId: userServerId,
        baseUrl: client.baseUrl,
      );
  return !requiresPermission || userCanManageCollections || isAdministrator;
}

class ItemPlaylistMembership {
  final String playlistId;
  final String playlistName;
  final String entryId;

  const ItemPlaylistMembership({
    required this.playlistId,
    required this.playlistName,
    required this.entryId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemPlaylistMembership &&
          runtimeType == other.runtimeType &&
          playlistId == other.playlistId &&
          entryId == other.entryId;

  @override
  int get hashCode => playlistId.hashCode ^ entryId.hashCode;

  @override
  String toString() =>
      'ItemPlaylistMembership(playlistId: $playlistId, playlistName: $playlistName, entryId: $entryId)';
}

class ItemCollectionMembership {
  final String collectionId;
  final String collectionName;

  const ItemCollectionMembership({
    required this.collectionId,
    required this.collectionName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemCollectionMembership &&
          runtimeType == other.runtimeType &&
          collectionId == other.collectionId;

  @override
  int get hashCode => collectionId.hashCode;

  @override
  String toString() =>
      'ItemCollectionMembership(collectionId: $collectionId, collectionName: $collectionName)';
}

/// Discovers and caches whether an item belongs to any playlists or collections
/// on the media server (Jellyfin, Emby, Plex, Silo, etc.).
class ItemMembershipService {
  static final ItemMembershipService instance = ItemMembershipService._();
  ItemMembershipService._();
  factory ItemMembershipService() => instance;

  /// How long a scan holds without the server's change notices to say when
  /// it went stale. Kos TV: with them it holds for the session.
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// Kos TV: the session socket, whose library notices say when a scan went
  /// stale, so a menu doesn't scan every collection again every 5 minutes.
  StreamSubscription<ServerWebSocketMessage>? _libraryEvents;

  /// Kos TV: what the server plugin said about single items, by server and
  /// item: the collections holding each.
  final Map<String, Map<String, List<ItemCollectionMembership>>>
  _pluginCollections = {};

  int _sessionGeneration = 0;

  // canonicalServerKey -> (playlistId -> list of (itemId, entryId))
  final Map<String, Map<String, List<({String itemId, String entryId})>>>
      _playlistItems = {};
  // canonicalServerKey -> (playlistId -> playlistName)
  final Map<String, Map<String, String>> _playlistNames = {};
  final Map<String, DateTime> _playlistLastFetched = {};
  final Map<String, Completer<void>> _playlistInFlight = {};
  final Map<String, int> _playlistMutationGenerations = {};

  // canonicalServerKey -> (collectionId -> set of itemIds)
  final Map<String, Map<String, Set<String>>> _collectionMembers = {};
  // canonicalServerKey -> (collectionId -> collectionName)
  final Map<String, Map<String, String>> _collectionNames = {};
  final Map<String, DateTime> _collectionLastFetched = {};
  final Map<String, Completer<void>> _collectionInFlight = {};
  final Map<String, int> _collectionMutationGenerations = {};

  String _canonicalServerKey(String? serverId) {
    if (serverId == null || serverId.isEmpty || serverId == 'seerr') {
      if (GetIt.instance.isRegistered<MediaServerClient>()) {
        final client = GetIt.instance<MediaServerClient>();
        if (GetIt.instance.isRegistered<MediaServerClientFactory>()) {
          final factory = GetIt.instance<MediaServerClientFactory>();
          return factory.serverIdOf(client);
        }
        return client.baseUrl;
      }
      return '';
    }
    if (GetIt.instance.isRegistered<MediaServerClientFactory>()) {
      final factory = GetIt.instance<MediaServerClientFactory>();
      final client = factory.getClientIfExists(serverId);
      if (client != null) {
        return factory.serverIdOf(client);
      }
    }
    return serverId;
  }

  static bool _isExternal(AggregatedItem item) =>
      item.serverId == 'seerr' || item.id.startsWith('tt');

  MediaServerClient _getClient(String? serverId) {
    if (GetIt.instance.isRegistered<MediaServerClientFactory>()) {
      final factory = GetIt.instance<MediaServerClientFactory>();
      if (serverId != null && serverId.isNotEmpty && serverId != 'seerr') {
        final client = factory.getClientIfExists(serverId);
        if (client != null) return client;
      }
    }
    return GetIt.instance<MediaServerClient>();
  }

  bool _canManageCollections(AggregatedItem item) {
    if (!GetIt.instance.isRegistered<UserRepository>()) return false;
    final client = _getClient(item.serverId);
    final currentUser = GetIt.instance<UserRepository>().currentUser;
    return canManageCollectionsFor(
      item,
      client: client,
      userServerId: currentUser?.serverId,
      userCanManageCollections: currentUser?.canManageCollections == true,
      isAdministrator: currentUser?.isAdministrator ?? false,
    );
  }

  /// Kos TV: follows the session socket once, so the scans hold until the
  /// library changes instead of for a fixed time.
  void _followLibraryChanges() {
    if (_libraryEvents != null ||
        !GetIt.instance.isRegistered<SocketHandler>()) {
      return;
    }
    final socket = GetIt.instance<SocketHandler>();
    _libraryEvents = socket.events.listen((event) {
      if (event is LibraryChangedMessage) onLibraryChanged(event);
    });
    // Notices sent while the socket was down are lost: start again.
    socket.connections.listen((_) => _invalidateAll());
  }

  bool get _followsLibrary => _libraryEvents != null;

  bool _isFresh(DateTime? fetched) =>
      fetched != null &&
      (_followsLibrary || DateTime.now().difference(fetched) < _cacheTtl);

  /// Kos TV: the server says something changed. A new or removed item can be
  /// a new or removed collection or playlist; an updated one that is a known
  /// collection or playlist had its members changed.
  @visibleForTesting
  void onLibraryChanged(LibraryChangedMessage event) {
    if (event.itemsAdded.isNotEmpty || event.itemsRemoved.isNotEmpty) {
      _invalidateAll();
      return;
    }
    final updated = {
      for (final id in event.itemsUpdated) id.replaceAll('-', ''),
    };
    if (updated.isEmpty) return;
    bool touches(Map<String, Map<String, String>> byServer) => byServer.values
        .any((names) => names.keys.any(updated.contains));
    if (touches(_collectionNames)) {
      _collectionLastFetched.clear();
      _pluginCollections.clear();
    }
    if (touches(_playlistNames)) _playlistLastFetched.clear();
  }

  void _invalidateAll() {
    _collectionLastFetched.clear();
    _playlistLastFetched.clear();
    _pluginCollections.clear();
  }

  /// Immediately returns whatever playlist memberships are currently cached.
  List<ItemPlaylistMembership> getCachedPlaylistsContaining(
      AggregatedItem item) {
    if (_isExternal(item)) return const [];
    final serverKey = _canonicalServerKey(item.serverId);
    final pItems = _playlistItems[serverKey] ?? const {};
    final pNames = _playlistNames[serverKey] ?? const {};
    final result = <ItemPlaylistMembership>[];

    for (final entry in pItems.entries) {
      final playlistId = entry.key;
      final members = entry.value;
      for (final member in members) {
        if (member.itemId == item.id) {
          result.add(ItemPlaylistMembership(
            playlistId: playlistId,
            playlistName: pNames[playlistId] ?? '',
            entryId: member.entryId,
          ));
          break;
        }
      }
    }
    return result;
  }

  /// Immediately returns whatever collection memberships are currently cached.
  List<ItemCollectionMembership> getCachedCollectionsContaining(
      AggregatedItem item) {
    if (_isExternal(item)) return const [];
    final serverKey = _canonicalServerKey(item.serverId);
    // Kos TV: what the plugin said of this item, when it was asked.
    final fromPlugin = _pluginCollections[serverKey]?[item.id];
    if (fromPlugin != null) return List.of(fromPlugin);
    final cMembers = _collectionMembers[serverKey] ?? const {};
    final cNames = _collectionNames[serverKey] ?? const {};
    final result = <ItemCollectionMembership>[];

    for (final entry in cMembers.entries) {
      final collectionId = entry.key;
      final memberIds = entry.value;
      if (memberIds.contains(item.id)) {
        result.add(ItemCollectionMembership(
          collectionId: collectionId,
          collectionName: cNames[collectionId] ?? '',
        ));
      }
    }
    return result;
  }

  /// Returns all playlists containing [item] that the item can be removed from.
  Future<List<ItemPlaylistMembership>> getPlaylistsContaining(
    AggregatedItem item, {
    bool forceRefresh = false,
  }) async {
    if (_isExternal(item)) return const [];
    final serverKey = _canonicalServerKey(item.serverId);
    if (!itemServerSupports(item.serverId, (f) => f.supportsPlaylists)) {
      return const [];
    }

    _followLibraryChanges();
    final generation = _sessionGeneration;
    final isCached = _isFresh(_playlistLastFetched[serverKey]);

    if (forceRefresh || !isCached) {
      await _syncPlaylists(serverKey);
      if (generation != _sessionGeneration) return const [];
      if (!_playlistLastFetched.containsKey(serverKey)) {
        await _syncPlaylists(serverKey);
        if (generation != _sessionGeneration) return const [];
      }
    }

    return getCachedPlaylistsContaining(item);
  }

  // Scanning a large library at once would flood the server and the device.
  // Kos TV: fewer on the web, where a browser keeps only a few connections
  // to the server and the page's artwork waits behind them.
  static const _maxConcurrent = kIsWeb ? 4 : 8;

  static Future<void> _inBatches<T>(
    List<T> items,
    bool Function() isStale,
    Future<void> Function(T item) fetch,
  ) async {
    for (var i = 0; i < items.length; i += _maxConcurrent) {
      if (isStale()) return;
      await Future.wait(items.skip(i).take(_maxConcurrent).map(fetch));
    }
  }

  Future<void> _syncPlaylists(String serverKey) async {
    if (_playlistInFlight.containsKey(serverKey)) {
      return _playlistInFlight[serverKey]!.future;
    }

    final generation = _sessionGeneration;
    final mutationGeneration = _playlistMutationGenerations[serverKey] ?? 0;
    bool isStale() =>
        generation != _sessionGeneration ||
        mutationGeneration != (_playlistMutationGenerations[serverKey] ?? 0);

    final completer = Completer<void>();
    _playlistInFlight[serverKey] = completer;

    try {
      final client = _getClient(serverKey);
      final data = await client.itemsApi.getPlaylists();
      if (isStale()) return;
      final items = (data['Items'] as List?) ?? const [];

      final previous = _playlistItems[serverKey] ?? const {};
      final nameMap = <String, String>{};
      final itemMap = <String, List<({String itemId, String entryId})>>{};

      final ids = <String>[];
      for (final raw in items.whereType<Map>()) {
        final pl = raw.cast<String, dynamic>();
        final id = pl['Id']?.toString();
        final name = pl['Name']?.toString();
        if (id == null || id.isEmpty || name == null) continue;
        nameMap[id] = name;
        ids.add(id);
      }

      await _inBatches(ids, isStale, (id) async {
        try {
          final res = await client.itemsApi.getPlaylistItems(
            id,
            fields: 'PlaylistItemId',
          );
          final memberList = (res['Items'] as List?) ?? const [];
          final members = <({String itemId, String entryId})>[];
          for (final m in memberList.whereType<Map>()) {
            final map = m.cast<String, dynamic>();
            final itemId = map['Id']?.toString();
            final entryId = map['PlaylistItemId']?.toString();
            if (itemId != null && entryId != null) {
              members.add((itemId: itemId, entryId: entryId));
            }
          }
          itemMap[id] = members;
        } catch (_) {
          final old = previous[id];
          if (old != null) itemMap[id] = old;
        }
      });
      if (isStale()) return;

      _playlistNames[serverKey] = nameMap;
      _playlistItems[serverKey] = itemMap;
      _playlistLastFetched[serverKey] = DateTime.now();
    } catch (_) {
    } finally {
      if (identical(_playlistInFlight[serverKey], completer)) {
        _playlistInFlight.remove(serverKey);
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Returns all collections containing [item] that the item can be removed from.
  Future<List<ItemCollectionMembership>> getCollectionsContaining(
    AggregatedItem item, {
    bool forceRefresh = false,
  }) async {
    if (_isExternal(item)) return const [];
    if (!_canManageCollections(item)) {
      return const [];
    }

    _followLibraryChanges();
    final generation = _sessionGeneration;
    final serverKey = _canonicalServerKey(item.serverId);
    final client = _getClient(serverKey);

    // Kos TV: the server plugin answers for this one item in one request,
    // where the scan below reads every collection's members.
    final cachedFromPlugin = _pluginCollections[serverKey]?[item.id];
    if (cachedFromPlugin != null && !forceRefresh) {
      return List.of(cachedFromPlugin);
    }
    final mutationGeneration = _collectionMutationGenerations[serverKey] ?? 0;
    final fromPlugin = await KostvCollectionsLookup.instance.containing(
      client,
      item.id,
    );
    if (generation != _sessionGeneration) return const [];
    if (fromPlugin != null) {
      final found = [
        for (final raw in fromPlugin)
          if (raw['Id'] case final String id when id.isNotEmpty)
            ItemCollectionMembership(
              collectionId: id,
              collectionName: raw['Name']?.toString() ?? '',
            ),
      ];
      // A change made while asking would be overwritten by the old answer.
      if (mutationGeneration ==
          (_collectionMutationGenerations[serverKey] ?? 0)) {
        (_pluginCollections[serverKey] ??= {})[item.id] = found;
      }
      return found;
    }

    final isCached = _isFresh(_collectionLastFetched[serverKey]);

    // Check ancestors fast-path (Emby / older Jellyfin versions report BoxSets in Ancestors)
    // Kos TV: only when the scan runs; a fresh scan already knows.
    final ancestorBoxSets = <String, String>{};
    if (forceRefresh || !isCached) {
      try {
        final ancestors = await client.itemsApi.getAncestors(item.id);
        if (generation != _sessionGeneration) return const [];
        for (final ancestor in ancestors) {
          if (ancestor['Type'] == 'BoxSet') {
            final id = ancestor['Id']?.toString();
            final name = ancestor['Name']?.toString();
            if (id != null &&
                id.isNotEmpty &&
                name != null &&
                name.isNotEmpty) {
              ancestorBoxSets[id] = name;
            }
          }
        }
      } catch (_) {}
    }

    if (forceRefresh || !isCached) {
      await _syncCollections(serverKey);
      if (generation != _sessionGeneration) return const [];
      if (!_collectionLastFetched.containsKey(serverKey)) {
        await _syncCollections(serverKey);
        if (generation != _sessionGeneration) return const [];
      }
    }

    final results = <ItemCollectionMembership>[
      ...getCachedCollectionsContaining(item)
    ];

    // Merge any ancestors found directly after verifying direct child membership
    for (final entry in ancestorBoxSets.entries) {
      if (!results.any((c) => c.collectionId == entry.key)) {
        try {
          final data = await client.itemsApi.getItems(
            parentId: entry.key,
            fields: 'BasicSyncInfo',
          );
          if (generation != _sessionGeneration) return const [];
          final memberIds = ((data['Items'] as List?) ?? const [])
              .whereType<Map>()
              .map((member) => member['Id']?.toString())
              .whereType<String>()
              .toSet();
          if (!memberIds.contains(item.id)) continue;
        } catch (_) {
          continue;
        }
        results.add(ItemCollectionMembership(
          collectionId: entry.key,
          collectionName: entry.value,
        ));
      }
    }

    return results;
  }

  Future<void> _syncCollections(String serverKey) async {
    if (_collectionInFlight.containsKey(serverKey)) {
      return _collectionInFlight[serverKey]!.future;
    }

    final generation = _sessionGeneration;
    final mutationGeneration = _collectionMutationGenerations[serverKey] ?? 0;
    bool isStale() =>
        generation != _sessionGeneration ||
        mutationGeneration != (_collectionMutationGenerations[serverKey] ?? 0);

    final completer = Completer<void>();
    _collectionInFlight[serverKey] = completer;

    try {
      final client = _getClient(serverKey);
      final api = client.itemsApi;
      final List<dynamic> items;
      if (api is EditableCollectionsApi) {
        items = await (api as EditableCollectionsApi).getEditableCollections();
      } else {
        final data = await api.getItems(
          includeItemTypes: const ['BoxSet'],
          recursive: true,
          sortBy: 'SortName',
          fields: 'BasicSyncInfo',
        );
        items = (data['Items'] as List?) ?? const [];
      }
      if (isStale()) return;

      final previous = _collectionMembers[serverKey] ?? const {};
      final nameMap = <String, String>{};
      final memberMap = <String, Set<String>>{};
      final candidates = <({String id, String name})>[];

      for (final raw in items.whereType<Map>()) {
        final boxSet = raw.cast<String, dynamic>();
        final id = boxSet['Id']?.toString();
        final name = boxSet['Name']?.toString();
        if (id == null || id.isEmpty || name == null) continue;
        nameMap[id] = name;
        candidates.add((id: id, name: name));
      }

      await _inBatches(candidates, isStale, (candidate) async {
        try {
          final res = await api.getItems(
            parentId: candidate.id,
            fields: 'BasicSyncInfo',
          );
          final membersList = (res['Items'] as List?) ?? const [];
          final memberIds = <String>{};
          for (final m in membersList.whereType<Map>()) {
            final map = m.cast<String, dynamic>();
            final id = map['Id']?.toString();
            if (id != null) memberIds.add(id);
          }
          memberMap[candidate.id] = memberIds;
        } catch (_) {
          final old = previous[candidate.id];
          if (old != null) memberMap[candidate.id] = old;
        }
      });
      if (isStale()) return;

      _collectionNames[serverKey] = nameMap;
      _collectionMembers[serverKey] = memberMap;
      _collectionLastFetched[serverKey] = DateTime.now();
    } catch (_) {
    } finally {
      if (identical(_collectionInFlight[serverKey], completer)) {
        _collectionInFlight.remove(serverKey);
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Updates cache when an item is added to a playlist. The server assigns the
  /// entry id a removal needs, so the next lookup fetches it.
  void notifyItemAddedToPlaylist(
    String serverId,
    String playlistId,
    List<String> itemIds,
  ) {
    final serverKey = _canonicalServerKey(serverId);
    _playlistMutationGenerations[serverKey] =
        (_playlistMutationGenerations[serverKey] ?? 0) + 1;
    _playlistLastFetched.remove(serverKey);
  }

  /// Updates cache when an item is removed from a playlist.
  void notifyItemRemovedFromPlaylist(
    String serverId,
    String playlistId,
    String itemId,
  ) {
    final serverKey = _canonicalServerKey(serverId);
    _playlistMutationGenerations[serverKey] =
        (_playlistMutationGenerations[serverKey] ?? 0) + 1;
    final serverPlaylists = _playlistItems[serverKey];
    if (serverPlaylists != null && serverPlaylists.containsKey(playlistId)) {
      serverPlaylists[playlistId]?.removeWhere((m) => m.itemId == itemId);
    }
    _playlistLastFetched.remove(serverKey);
  }

  /// Updates cache when an item is added to a collection.
  void notifyItemAddedToCollection(
    String serverId,
    String collectionId,
    List<String> itemIds,
  ) {
    final serverKey = _canonicalServerKey(serverId);
    _collectionMutationGenerations[serverKey] =
        (_collectionMutationGenerations[serverKey] ?? 0) + 1;
    final serverCollections = _collectionMembers[serverKey];
    if (serverCollections != null &&
        serverCollections.containsKey(collectionId)) {
      serverCollections[collectionId]?.addAll(itemIds);
    }
    _collectionLastFetched.remove(serverKey);
    // Kos TV: the plugin is asked again for these.
    _pluginCollections[serverKey]?.removeWhere(
      (id, _) => itemIds.contains(id),
    );
  }

  /// Updates cache when an item is removed from a collection.
  void notifyItemRemovedFromCollection(
    String serverId,
    String collectionId,
    String itemId,
  ) {
    final serverKey = _canonicalServerKey(serverId);
    _collectionMutationGenerations[serverKey] =
        (_collectionMutationGenerations[serverKey] ?? 0) + 1;
    final serverCollections = _collectionMembers[serverKey];
    if (serverCollections != null &&
        serverCollections.containsKey(collectionId)) {
      serverCollections[collectionId]?.remove(itemId);
    }
    _collectionLastFetched.remove(serverKey);
    // Kos TV: the plugin is asked again for it.
    _pluginCollections[serverKey]?.remove(itemId);
  }

  /// Clears in-memory caches and invalidates any in-flight syncs (e.g. on account or server switch).
  void clearCache() {
    _sessionGeneration++;
    _playlistItems.clear();
    _playlistNames.clear();
    _playlistLastFetched.clear();
    _playlistMutationGenerations.clear();
    for (final c in _playlistInFlight.values) {
      if (!c.isCompleted) c.complete();
    }
    _playlistInFlight.clear();
    _collectionMembers.clear();
    _collectionNames.clear();
    _collectionLastFetched.clear();
    _collectionMutationGenerations.clear();
    for (final c in _collectionInFlight.values) {
      if (!c.isCompleted) c.complete();
    }
    _collectionInFlight.clear();
    _pluginCollections.clear();
  }
}
