import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../preference/user_preferences.dart';
import '../models/aggregated_item.dart';
import '../utils/blocked_ratings.dart';
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

  /// Kos TV: the same page with only what [keep] says is still on the list.
  KostvMyListPage _where(bool Function(AggregatedItem item) keep) {
    List<AggregatedItem> part(List<AggregatedItem> items) {
      final kept = items.where(keep).toList();
      return kept.length == items.length ? items : kept;
    }

    final w = part(watching);
    final t = part(toStart);
    final d = part(watched);
    if (identical(w, watching) &&
        identical(t, toStart) &&
        identical(d, watched)) {
      return this;
    }
    return KostvMyListPage(watching: w, toStart: t, watched: d);
  }
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

  /// Kos TV: which read of the list is the newest, so an older answer that
  /// lands last doesn't put back what the list was before.
  int _loadTurn = 0;

  /// Kos TV: what was already told to the plugin as having arrived, by
  /// person, so each Home load doesn't send it (and read the list) again.
  final Map<String, Set<String>> _arrivedSent = {};

  /// Kos TV: «Clear watched», waiting out its few seconds to take it back,
  /// and until the server has answered, the watched ones kept off the page.
  Timer? _clearTimer;
  Completer<bool>? _clearDone;
  bool _clearHides = false;

  /// How long «Clear watched» waits before telling the server, for the person
  /// to take it back.
  static const clearUndoTime = Duration(seconds: 5);

  /// Whether the server plugin keeps lists, as its last answer said.
  bool get available => _prefs.get(UserPreferences.kostvMyListAvailable);

  /// The list as last read, or null before it is. While «Clear watched» waits
  /// to be taken back, without the watched ones.
  KostvMyListPage? get page {
    _checkOwner();
    final page = _page;
    if (page == null || !_clearHides || page.watched.isEmpty) return page;
    return KostvMyListPage(watching: page.watching, toStart: page.toStart);
  }

  /// Whether «Clear watched» is waiting out its time to be taken back.
  bool get clearPending => _clearTimer != null;

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
    _loadTurn++;
    // Kos TV: a clear the last person could still take back is dropped: sent
    // later it would clear the list of whoever is signed in by then.
    _dropClear();
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
    // Kos TV: the page read earlier keeps only what is still on the list, so
    // what listens (Home's row) never puts back a title taken off since.
    final page = _page;
    if (page != null) {
      _page = page._where((item) => next.contains(listIdOf(item) ?? item.id));
    }
    notifyListeners();
  }

  /// Reads the list again. Null when the plugin can't be asked.
  Future<KostvMyListPage?> load() async {
    _checkOwner();
    final owner = _owner;
    final turn = ++_loadTurn;
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
      // A newer read is under way or done: this answer is older than it.
      if (turn != _loadTurn) return page;
      // Parental control: what the device blocks stays off the page too,
      // as off Home's row.
      List<AggregatedItem> cards(Object? raw) => withoutBlockedItems([
        if (raw is List)
          for (final item in raw)
            if (item is Map && item['Id'] != null)
              AggregatedItem(
                id: item['Id'].toString().replaceAll('-', ''),
                serverId: client.baseUrl,
                rawData: item.cast<String, dynamic>(),
              ),
      ]);
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
  ///
  /// Kos TV: Home calls this for every arrived title on every load. Each is
  /// sent once per person in a session, and the list is read again only when
  /// it went on now, not when it was on it already.
  Future<void> addArrived(String itemId) async {
    if (!available) return;
    _checkOwner();
    final id = itemId.replaceAll('-', '');
    final sent = _arrivedSent.putIfAbsent(_owner!, () => <String>{});
    if (!sent.add(id)) return;
    final wasOn = _ids.contains(id);
    final onList = await _post(id, arrived: true);
    // Not told: tried again on the next load.
    if (onList == null) sent.remove(id);
    if ((onList ?? false) && !wasOn) unawaited(load());
  }

  /// Kos TV: takes the watched ones off the page at once and tells the server
  /// after [clearUndoTime], unless [undoClearWatched] comes first. Whether
  /// the server took it; false when it couldn't or it was taken back.
  Future<bool> clearWatchedLater() {
    _checkOwner();
    final pending = _clearDone;
    if (pending != null) return pending.future;
    final done = Completer<bool>();
    _clearDone = done;
    _clearHides = true;
    final owner = _owner;
    _clearTimer = Timer(clearUndoTime, () async {
      _clearTimer = null;
      // Another person signed in meanwhile: theirs is left alone.
      _checkOwner();
      if (owner != _owner) return;
      final cleared = await clearWatched();
      if (!identical(_clearDone, done)) return;
      _clearDone = null;
      _clearHides = false;
      // Failed, the watched ones come back; done, the page is the new one.
      notifyListeners();
      done.complete(cleared);
    });
    notifyListeners();
    return done.future;
  }

  /// Puts the watched ones back, within their undo time.
  void undoClearWatched() {
    if (_clearTimer == null) return;
    _dropClear();
    notifyListeners();
  }

  void _dropClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _clearHides = false;
    final done = _clearDone;
    _clearDone = null;
    if (done != null && !done.isCompleted) done.complete(false);
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
    final owner = _owner;
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
      // Kos TV: the person changed while it was sent: the answer is about
      // the last one's list, not this one's.
      _checkOwner();
      if (owner != _owner) return onList;
      final listed = (data['ItemId'] as String?)?.replaceAll('-', '') ?? itemId;
      final next = Set.of(_ids);
      onList ? next.add(listed) : next.remove(listed);
      _ids = next;
      // Kos TV: what went off the list goes off the page read earlier too, so
      // Home's row doesn't show it again while the list is read anew.
      final page = _page;
      if (!onList && page != null) {
        _page = page._where((item) => (listIdOf(item) ?? item.id) != listed);
      }
      notifyListeners();
      return onList;
    } catch (e) {
      debugPrint('[MyList] Changing the list failed: $e');
      return null;
    }
  }
}
