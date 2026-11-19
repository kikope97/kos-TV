import 'dart:convert';

import 'package:web/web.dart' as web;

/// Kos TV: on the web the rows are kept in the browser's local storage, so
/// Home paints the last rows at once on the next visit, as it does on the
/// TV and the phone, while it reads them again.
///
/// One entry per person, under this prefix, and the list of whose are kept,
/// the most recent first. The single entry builds before that wrote is
/// still read (its rows say whose they are) and dropped on the next write.
const _legacyKey = 'kostv_home_rows_cache';
const _slotPrefix = 'kostv_home_rows_cache_';
const _slotsKey = 'kostv_home_rows_cache_slots';

/// Local storage holds a few MB for the whole page; rows bigger than this,
/// between all the people kept, are not kept (the oldest people's go
/// first), rather than crowd out the rest of what the page keeps there.
const _maxChars = 1500000;

/// How many people's rows are kept, at most.
const _maxSlots = 3;

String _keyOf(String slot) => '$_slotPrefix$slot';

List<String> _slots(web.Storage storage) {
  try {
    final raw = storage.getItem(_slotsKey);
    if (raw == null) return [];
    return [
      for (final slot in jsonDecode(raw) as List)
        if (slot is String) slot,
    ];
  } catch (_) {
    return [];
  }
}

void _saveSlots(web.Storage storage, List<String> slots) {
  if (slots.isEmpty) {
    storage.removeItem(_slotsKey);
  } else {
    storage.setItem(_slotsKey, jsonEncode(slots));
  }
}

Future<String?> readHomeRowCache(String slot) async {
  final storage = web.window.localStorage;
  return storage.getItem(_keyOf(slot)) ?? storage.getItem(_legacyKey);
}

Future<void> writeHomeRowCache(String slot, String payload) async {
  final storage = web.window.localStorage;
  storage.removeItem(_legacyKey);
  final others = [
    for (final s in _slots(storage))
      if (s != slot) s,
  ];
  if (payload.length > _maxChars) {
    storage.removeItem(_keyOf(slot));
    _saveSlots(storage, others);
    return;
  }
  // The most recent people first, as many as fit beside these rows.
  var room = _maxChars - payload.length;
  final kept = <String>[];
  for (final other in others) {
    final length = storage.getItem(_keyOf(other))?.length;
    if (length == null) continue;
    if (kept.length + 1 < _maxSlots && length <= room) {
      kept.add(other);
      room -= length;
    } else {
      storage.removeItem(_keyOf(other));
    }
  }
  try {
    storage.setItem(_keyOf(slot), payload);
    _saveSlots(storage, [slot, ...kept]);
  } catch (_) {
    // Full: nothing kept for this person, as before.
    storage.removeItem(_keyOf(slot));
    _saveSlots(storage, kept);
  }
}

Future<void> deleteHomeRowCache(String slot) async {
  final storage = web.window.localStorage;
  storage.removeItem(_keyOf(slot));
  storage.removeItem(_legacyKey);
  _saveSlots(storage, [
    for (final s in _slots(storage))
      if (s != slot) s,
  ]);
}

// The web has a single thread: decoded where it is.
Future<Object?> decodeHomeRowCache(String raw) async => jsonDecode(raw);

Future<String> encodeHomeRowCache(Object envelope) async =>
    jsonEncode(envelope);
