import 'dart:convert';

import 'package:web/web.dart' as web;

/// Kos TV: on the web the rows are kept in the browser's local storage, so
/// Home paints the last rows at once on the next visit, as it does on the
/// TV and the phone, while it reads them again.
const _key = 'kostv_home_rows_cache';

/// Local storage holds a few MB for the whole page; rows bigger than this
/// are not kept (and older ones are dropped), rather than crowd out the
/// rest of what the page keeps there.
const _maxChars = 1500000;

Future<String?> readHomeRowCache() async =>
    web.window.localStorage.getItem(_key);

Future<void> writeHomeRowCache(String payload) async {
  final storage = web.window.localStorage;
  if (payload.length > _maxChars) {
    storage.removeItem(_key);
    return;
  }
  try {
    storage.setItem(_key, payload);
  } catch (_) {
    // Full: nothing kept, as before.
    storage.removeItem(_key);
  }
}

Future<void> deleteHomeRowCache() async =>
    web.window.localStorage.removeItem(_key);

// The web has a single thread: decoded where it is.
Future<Object?> decodeHomeRowCache(String raw) async => jsonDecode(raw);

Future<String> encodeHomeRowCache(Object envelope) async =>
    jsonEncode(envelope);
