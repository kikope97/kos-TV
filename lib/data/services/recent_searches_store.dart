import 'package:jellyfin_preference/jellyfin_preference.dart';

class RecentSearchesStore {
  /// Kos TV: the list of everyone on the device, from before it was kept for
  /// each person. Dropped: it would show one person's searches to another.
  static const _sharedKey = 'recent_searches_v1';
  static const _keyPrefix = 'recent_searches_v2';
  static const _maxEntries = 12;

  final PreferenceStore _store;

  /// Whose searches: the server and the person signed in to it.
  final String Function()? _scope;

  /// Kos TV: in Kids Mode searches are neither kept nor offered.
  final bool Function()? _paused;

  RecentSearchesStore(
    this._store, {
    String Function()? scope,
    bool Function()? paused,
  }) : _scope = scope,
       _paused = paused;

  bool _sharedDropped = false;

  String get _storageKey {
    if (!_sharedDropped) {
      _sharedDropped = true;
      if (_store.getStringList(_sharedKey) != null) {
        _store.remove(_sharedKey);
      }
    }
    final scope = _scope?.call() ?? '';
    return scope.isEmpty ? _keyPrefix : '${_keyPrefix}_$scope';
  }

  List<String> get recent {
    if (_paused?.call() ?? false) return const [];
    final values = _store.getStringList(_storageKey) ?? const <String>[];
    final normalized = <String>[];
    final seen = <String>{};

    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        normalized.add(trimmed);
      }
      if (normalized.length >= _maxEntries) {
        break;
      }
    }

    return normalized;
  }

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || (_paused?.call() ?? false)) return;

    final current = recent;
    final next = <String>[trimmed];
    final seen = <String>{trimmed.toLowerCase()};

    for (final value in current) {
      final key = value.toLowerCase();
      if (seen.add(key)) {
        next.add(value);
      }
      if (next.length >= _maxEntries) {
        break;
      }
    }

    await _store.setStringList(_storageKey, next);
  }

  Future<void> clear() async {
    await _store.remove(_storageKey);
  }
}
