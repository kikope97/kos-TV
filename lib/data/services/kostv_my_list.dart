import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../preference/user_preferences.dart';
import '../models/aggregated_item.dart';
import 'moonbase_endpoint.dart';

/// Kos TV: what is on the person's list, in its three parts.
@immutable
class KostvMyListPage {
  const KostvMyListPage({
    this.watching = const [],
    this.toStart = const [],
    this.watched = const [],
  });

  /// What they are part way through, the last watched first.
  final List<AggregatedItem> watching;

  /// What they haven't started, the last added first.
  final List<AggregatedItem> toStart;

  /// What they have watched (films seen, series with nothing left).
  final List<AggregatedItem> watched;

  bool get isEmpty => watching.isEmpty && toStart.isEmpty && watched.isEmpty;
}

/// Kos TV: the person's list of what they want to watch («Mi lista»), kept by
/// the server plugin so it is the same on every device of theirs.
///
/// Knows which items are on it, for the buttons, and the list itself once
/// read. Episodes and seasons stand for their series.
class KostvMyListService extends ChangeNotifier {
  KostvMyListService({
    MediaServerClient Function()? client,
    UserPreferences? prefs,
    Dio? dio,
  }) : _clientOf = client ?? (() => GetIt.instance<MediaServerClient>()),
       _prefs = prefs ?? GetIt.instance<UserPreferences>(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 30),
             ),
           );

  final MediaServerClient Function() _clientOf;
  final UserPreferences _prefs;
  final Dio _dio;

  /// Whose list [_ids] and [page] are, so another person's never shows.
  String? _owner;
  Set<String> _ids = const {};
  KostvMyListPage? _page;

  /// Whether the server plugin keeps lists, as its last answer said.
  bool get available => _prefs.get(UserPreferences.kostvMyListAvailable);

  /// The list as last read, or null before it is.
  KostvMyListPage? get page {
    _checkOwner();
    return _page;
  }

  String _ownerNow() {
    final client = _clientOf();
    return '${client.baseUrl}|${client.userId}';
  }

  void _checkOwner() {
    final now = _ownerNow();
    if (now == _owner) return;
    _owner = now;
    _ids = const {};
    _page = null;
  }

  /// The id an item has on the list: its own, or its series'.
  static String? listIdOf(AggregatedItem item) => switch (item.type) {
    'Movie' || 'Series' => item.id,
    'Episode' || 'Season' => item.seriesId,
    _ => null,
  }?.replaceAll('-', '');

  /// Whether [item] can go on the list.
  bool canList(AggregatedItem item) => available && listIdOf(item) != null;

  /// Whether [item] (or its series) is on the list.
  bool contains(AggregatedItem item) {
    _checkOwner();
    final id = listIdOf(item);
    return id != null && _ids.contains(id);
  }

  /// The ids the home page read along with its rows.
  void noteIds(Iterable<String> ids) {
    _checkOwner();
    final next = {for (final id in ids) id.replaceAll('-', '')};
    if (setEquals(next, _ids)) return;
    _ids = next;
    notifyListeners();
  }

  /// Reads the list again. Null when the plugin can't be asked.
  Future<KostvMyListPage?> load() async {
    _checkOwner();
    final owner = _owner;
    try {
      final client = _clientOf();
      final ep = await moonbaseEndpoint(client, _dio);
      if (ep == null) return null;
      final response = await _dio.get<dynamic>(
        '${ep.base}/Moonfin/Kostv/MyList',
        options: Options(headers: ep.headers),
      );
      final data = response.data;
      if (data is! Map || owner != _owner) return null;
      List<AggregatedItem> cards(Object? raw) => [
        if (raw is List)
          for (final item in raw)
            if (item is Map && item['Id'] != null)
              AggregatedItem(
                id: item['Id'].toString().replaceAll('-', ''),
                serverId: client.baseUrl,
                rawData: item.cast<String, dynamic>(),
              ),
      ];
      _page = KostvMyListPage(
        watching: cards(data['Watching']),
        toStart: cards(data['ToStart']),
        watched: cards(data['Watched']),
      );
      _ids = {
        if (data['Ids'] case final List<dynamic> ids)
          for (final id in ids)
            if (id is String) id.replaceAll('-', ''),
      };
      notifyListeners();
      return _page;
    } catch (e) {
      debugPrint('[MyList] Reading the list failed: $e');
      return null;
    }
  }

  /// Puts [item] (or its series) on the list, or takes it off. Whether it is
  /// on the list afterwards; null when it couldn't be told.
  Future<bool?> set(AggregatedItem item, {required bool onList}) async {
    final id = listIdOf(item);
    if (id == null) return null;
    final answer = await _post(id, remove: !onList);
    if (answer == null) return null;
    unawaited(load());
    return answer;
  }

  /// Puts what the person asked for and has just arrived on their list, the
  /// first time only, so taking it off sticks.
  Future<void> addArrived(String itemId) async {
    if (!available) return;
    if (await _post(itemId.replaceAll('-', ''), arrived: true) ?? false) {
      unawaited(load());
    }
  }

  /// Takes off the list everything already watched.
  Future<bool> clearWatched() async {
    try {
      final ep = await moonbaseEndpoint(_clientOf(), _dio);
      if (ep == null) return false;
      await _dio.post<dynamic>(
        '${ep.base}/Moonfin/Kostv/MyList/ClearWatched',
        options: Options(headers: ep.headers),
      );
      await load();
      return true;
    } catch (e) {
      debugPrint('[MyList] Clearing what was watched failed: $e');
      return false;
    }
  }

  Future<bool?> _post(
    String itemId, {
    bool remove = false,
    bool arrived = false,
  }) async {
    _checkOwner();
    try {
      final ep = await moonbaseEndpoint(_clientOf(), _dio);
      if (ep == null) return null;
      final response = await _dio.post<dynamic>(
        '${ep.base}/Moonfin/Kostv/MyList',
        queryParameters: {
          'itemId': itemId,
          if (remove) 'remove': true,
          if (arrived) 'arrived': true,
        },
        options: Options(headers: ep.headers),
      );
      final data = response.data;
      if (data is! Map) return null;
      final onList = data['OnList'] == true;
      final listed = (data['ItemId'] as String?)?.replaceAll('-', '') ?? itemId;
      final next = Set.of(_ids);
      onList ? next.add(listed) : next.remove(listed);
      _ids = next;
      notifyListeners();
      return onList;
    } catch (e) {
      debugPrint('[MyList] Changing the list failed: $e');
      return null;
    }
  }
}
