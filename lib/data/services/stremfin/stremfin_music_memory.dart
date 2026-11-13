import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the last answers of the requests service for the Music page, so
/// it opens at once with what it showed last time while the service is
/// asked again behind it. Kept on the device, one set per person (by their
/// token), and only what the page shows: the charts, «Para ti», the news.
class StremfinMusicMemory {
  StremfinMusicMemory({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const _key = 'kostv_music_memory';

  /// Too big to keep (a few hundred kilobytes is the usual).
  static const _maxBytes = 1500000;

  final Future<SharedPreferences> Function() _prefs;
  Map<String, Object?>? _answers;
  Future<void>? _loading;
  Timer? _saving;

  Future<void> _load() => _loading ??= () async {
    try {
      final raw = (await _prefs()).getString(_key);
      final decoded = raw == null ? null : jsonDecode(raw);
      _answers = decoded is Map
          ? decoded.map((key, value) => MapEntry('$key', value))
          : {};
    } catch (_) {
      _answers = {};
    }
  }();

  /// The last answer for [key], or null.
  Future<Object?> read(String key) async {
    await _load();
    return _answers?[key];
  }

  /// Keeps [answer] for [key], written to the device a moment later.
  void write(String key, Object? answer) {
    if (answer == null) return;
    unawaited(
      _load().then((_) {
        _answers![key] = answer;
        _saving?.cancel();
        _saving = Timer(const Duration(seconds: 2), _save);
      }),
    );
  }

  Future<void> _save() async {
    final answers = _answers;
    if (answers == null) return;
    try {
      final encoded = jsonEncode(answers);
      if (encoded.length > _maxBytes) {
        // Starting again is better than keeping it from growing forever.
        answers.clear();
        return;
      }
      await (await _prefs()).setString(_key, encoded);
    } catch (e) {
      debugPrint('[MusicMemory] Could not keep it: $e');
    }
  }

  /// A short fingerprint of [token], so each person keeps their own and the
  /// token itself is never written down.
  static String scopeOf(String token) {
    var hash = 0x811c9dc5;
    for (final unit in token.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }
}
