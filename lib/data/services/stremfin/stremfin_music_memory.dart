import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the last answers of the requests service for the Music page, so
/// it opens at once with what it showed last time while the service is
/// asked again behind it.
///
/// Kept on the device for one person only: their [scope] (a fingerprint of
/// their session, never the session itself) goes with the answers, and
/// another person's first answer replaces them all. Only what the page
/// shows is kept, without the 30-second previews' addresses (they expire),
/// and it goes when the person signs out.
class StremfinMusicMemory {
  StremfinMusicMemory({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  static const _key = 'kostv_music_memory';

  /// Too big to keep: the page's answers are a few hundred kilobytes.
  static const _maxChars = 1000000;

  /// The page asks for about a dozen things.
  static const _maxAnswers = 30;

  final Future<SharedPreferences> Function() _prefs;
  String? _scope;
  Map<String, Object?> _answers = {};
  Future<void>? _loading;
  Timer? _saving;

  Future<void> _load() => _loading ??= () async {
    try {
      final raw = (await _prefs()).getString(_key);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map && decoded['answers'] is Map) {
        _scope = decoded['scope']?.toString();
        _answers = (decoded['answers'] as Map).map(
          (key, value) => MapEntry('$key', value),
        );
      }
    } catch (_) {
      _answers = {};
    }
  }();

  /// The last answer for [key] of the person [scope], or null.
  Future<Object?> read(String scope, String key) async {
    await _load();
    return scope == _scope ? _answers[key] : null;
  }

  /// Keeps [answer] for [key] of the person [scope], written to the device
  /// a moment later. Another person's answers are dropped.
  void write(String scope, String key, Object? answer) {
    if (answer == null) return;
    unawaited(
      _load().then((_) {
        if (scope != _scope) {
          _scope = scope;
          _answers = {};
        }
        // The latest last; past [_maxAnswers], the oldest go (the keys of
        // «Para ti» change as the person's artists do).
        _answers.remove(key);
        _answers[key] = withoutPreviews(answer);
        while (_answers.length > _maxAnswers) {
          _answers.remove(_answers.keys.first);
        }
        _saving?.cancel();
        _saving = Timer(const Duration(seconds: 2), _save);
      }),
    );
  }

  /// Forgets everything (the person signed out).
  Future<void> clear() async {
    await _load();
    _saving?.cancel();
    _scope = null;
    _answers = {};
    try {
      await (await _prefs()).remove(_key);
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final encoded = jsonEncode({'scope': _scope, 'answers': _answers});
      // Too big: what was kept stays as it was rather than growing.
      if (encoded.length > _maxChars) return;
      await (await _prefs()).setString(_key, encoded);
    } catch (e) {
      debugPrint('[MusicMemory] Could not keep it: $e');
    }
  }

  /// [answer] without the previews' addresses, which expire.
  @visibleForTesting
  static Object? withoutPreviews(Object? answer) {
    if (answer is Map) {
      return {
        for (final entry in answer.entries)
          if (entry.key != 'preview')
            '${entry.key}': withoutPreviews(entry.value),
      };
    }
    if (answer is List)
      return [for (final item in answer) withoutPreviews(item)];
    return answer;
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
