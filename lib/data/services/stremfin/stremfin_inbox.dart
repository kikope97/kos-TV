import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stremfin_client.dart';
import 'stremfin_models.dart';

/// Kos TV: the person's own requests, for the requests tray: what is new to
/// them (accepted by the administrator, turned down, arrived), what is under
/// way and what finished. Only theirs: nobody sees what the others ask for.
///
/// It asks the service only for what changed since last time: when the app
/// opens or comes back to the front, every few minutes while it is in use,
/// and after asking for something. While the tray is open it follows the
/// requests under way every few seconds.
class StremfinInbox extends ChangeNotifier {
  StremfinInbox(this._client);

  final StremfinClient _client;

  /// How often to ask what changed while the app is in use. The service asks
  /// not to go below five minutes.
  static const syncInterval = Duration(minutes: 5);

  /// While the tray is open: something coming down, and otherwise.
  static const liveQuick = Duration(seconds: 5);
  static const liveSlow = Duration(seconds: 15);

  /// Finished requests the tray keeps showing.
  static const keepFinished = 30;

  String? _userId;
  bool _enabled = false;
  bool _foreground = true;

  /// The service's clock at the last answer, to ask only what changed.
  String? _since;
  final Map<int, StremfinRequest> _items = {};

  /// What the person has seen: `id:status` of each piece of news.
  Set<String>? _seen;

  /// Bumped when the person changes, so an answer for the previous one is
  /// dropped.
  int _generation = 0;
  Future<void>? _syncing;
  Timer? _timer;
  Timer? _liveTimer;
  int _watchers = 0;
  bool _disposed = false;

  /// The list has been read at least once for this person.
  bool get isLoaded => _since != null;

  List<StremfinRequest> get _latestFirst =>
      _items.values.toList()..sort((a, b) {
        final at = a.lastChange;
        final bt = b.lastChange;
        if (at != null && bt != null && at != bt) return bt.compareTo(at);
        return b.id.compareTo(a.id);
      });

  /// News the person hasn't seen yet, latest first.
  List<StremfinRequest> get news => [
    for (final request in _latestFirst)
      if (isNews(request)) request,
  ];

  int get newsCount => _items.values.where(isNews).length;

  /// Waiting for an answer or under way, latest first.
  List<StremfinRequest> get active => [
    for (final request in _latestFirst)
      if (request.status.isOpen) request,
  ];

  bool get hasActive => _items.values.any((r) => r.status.isOpen);

  /// Something is coming down right now.
  bool get hasDownloading => _items.values.any(
    (r) =>
        r.status == StremfinRequestStatus.approved &&
        r.progress?.state == StremfinProgressState.downloading,
  );

  /// Arrived or turned down, latest first.
  List<StremfinRequest> get finished => [
    for (final request in _latestFirst)
      if (!request.status.isOpen &&
          request.status != StremfinRequestStatus.unknown)
        request,
  ].take(keepFinished).toList();

  /// What makes a request news: it arrived, it was turned down, or the
  /// administrator accepted it (one accepted on its own isn't: the person
  /// knew). Null when it isn't news.
  static String? _newsKey(StremfinRequest request) => switch (request.status) {
    StremfinRequestStatus.completed => '${request.id}:completed',
    StremfinRequestStatus.rejected => '${request.id}:rejected',
    StremfinRequestStatus.approved when !request.direct =>
      '${request.id}:approved',
    _ => null,
  };

  bool isNews(StremfinRequest request) {
    final key = _newsKey(request);
    final seen = _seen;
    return key != null && seen != null && !seen.contains(key);
  }

  /// Someone else signed in, or nobody: forget the last person's requests.
  void setUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _generation++;
    _since = null;
    _seen = null;
    _items.clear();
    _stopTimers();
    _notify();
  }

  /// Whether the service lets the person use requests.
  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      unawaited(sync());
    } else {
      _stopTimers();
      _items.clear();
      _since = null;
      _notify();
    }
  }

  /// The app came to the front (ask what changed) or left it (stop asking).
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) {
      unawaited(sync());
      if (_watchers > 0) unawaited(_live());
    } else {
      _stopTimers();
    }
  }

  /// Asks what changed since last time.
  Future<void> sync() => _syncing ??= _sync().whenComplete(() {
    _syncing = null;
  });

  Future<void> _sync() async {
    final user = _userId;
    if (!_enabled || user == null || _disposed) return;
    final generation = _generation;
    _timer?.cancel();
    try {
      final stored = _seen == null ? await _loadSeen(user) : null;
      if (generation != _generation || _disposed) return;
      final first = _seen == null;
      _seen ??= stored;
      final page = await _client.requests(
        since: _since,
        limit: _since == null ? 100 : null,
      );
      if (generation != _generation || _disposed) return;
      if (_since == null) _items.clear();
      for (final id in page.removedIds) {
        _items.remove(id);
      }
      for (final request in page.items) {
        _items[request.id] = request;
      }
      _since = page.now ?? _since ?? '';
      if (first && stored == null) {
        // The first time on this device: what already happened isn't news,
        // only what happens from now on.
        _seen = {for (final r in _items.values) ?_newsKey(r)};
        await _saveSeen();
      }
      _notify();
    } on StremfinException {
      // Asked again next time round.
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || !_enabled || !_foreground || _userId == null) return;
    _timer = Timer(syncInterval, () => unawaited(sync()));
  }

  /// The person has seen the news (the tray is open).
  Future<void> markAllSeen() async {
    final seen = _seen;
    if (seen == null) return;
    final fresh = [
      for (final request in _items.values)
        if (isNews(request)) _newsKey(request)!,
    ];
    if (fresh.isEmpty) return;
    seen.addAll(fresh);
    _notify();
    await _saveSeen();
  }

  /// A request as it stands now, read elsewhere (its page, or just asked
  /// for). [seen]: the person saw it so, so it isn't news.
  void note(StremfinRequest request, {bool seen = false}) {
    if (_disposed || _userId == null) return;
    _items[request.id] = request;
    final key = _newsKey(request);
    if (seen && key != null && _seen != null && _seen!.add(key)) {
      unawaited(_saveSeen());
    }
    _notify();
  }

  /// A request taken back.
  void remove(int id) {
    if (_items.remove(id) != null) _notify();
  }

  /// The tray is open: the requests under way are followed every few
  /// seconds until [unwatch].
  void watch() {
    _watchers++;
    if (_watchers == 1) unawaited(_live());
  }

  void unwatch() {
    if (_watchers == 0) return;
    _watchers--;
    if (_watchers == 0) _liveTimer?.cancel();
  }

  Future<void> _live() async {
    _liveTimer?.cancel();
    if (_watchers == 0 || !_enabled || !_foreground || _disposed) return;
    final generation = _generation;
    try {
      // How far each has got: its progress doesn't count as a change for
      // `since`, so the open ones are read as they are.
      final page = await _client.requests(status: 'open');
      if (generation != _generation || _disposed) return;
      final open = {for (final r in page.items) r.id};
      final finishedMeanwhile = _items.values.any(
        (r) => r.status.isOpen && !open.contains(r.id),
      );
      for (final request in page.items) {
        _items[request.id] = request;
      }
      _notify();
      // One that isn't open any more arrived, was turned down or went.
      if (finishedMeanwhile) await sync();
    } on StremfinException {
      // Asked again in a moment.
    }
    if (_watchers == 0 || _disposed || !_foreground) return;
    _liveTimer = Timer(
      hasDownloading ? liveQuick : liveSlow,
      () => unawaited(_live()),
    );
  }

  void _stopTimers() {
    _timer?.cancel();
    _liveTimer?.cancel();
  }

  String _seenKey(String user) => 'kostv_requests_seen_$user';

  Future<Set<String>?> _loadSeen(String user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_seenKey(user))?.toSet();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSeen() async {
    final user = _userId;
    final seen = _seen;
    if (user == null || seen == null) return;
    // Only what still matters: requests it still holds.
    final known = {for (final r in _items.values) r.id};
    seen.removeWhere((key) => !known.contains(int.tryParse(key.split(':')[0])));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenKey(user), seen.toList());
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    super.dispose();
  }
}
