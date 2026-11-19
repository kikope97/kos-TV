import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../../../util/platform_detection.dart';

/// Kos TV: the single file builds before one slot per person wrote. Still
/// read (its rows say whose they are), and dropped on the next write.
const _legacyFileName = 'home_rows_cache.json';
const _slotPrefix = 'home_rows_cache_';
const _slotSuffix = '.json';

/// Kos TV: how many people's rows are kept, the most recent ones.
const _maxSlots = 4;

Future<Directory> _dir() async => PlatformDetection.isAppleTV
    ? await getApplicationCacheDirectory()
    : await getApplicationSupportDirectory();

File _slotFile(Directory dir, String slot) =>
    File('${dir.path}/$_slotPrefix$slot$_slotSuffix');

File _legacyFile(Directory dir) => File('${dir.path}/$_legacyFileName');

/// The rows saved in [slot] as written, or null when there are none.
Future<String?> readHomeRowCache(String slot) async {
  final dir = await _dir();
  final file = _slotFile(dir, slot);
  if (file.existsSync()) return file.readAsString();
  final legacy = _legacyFile(dir);
  if (legacy.existsSync()) return legacy.readAsString();
  return null;
}

Future<void> writeHomeRowCache(String slot, String payload) async {
  final dir = await _dir();
  await _slotFile(dir, slot).writeAsString(payload, flush: true);
  final legacy = _legacyFile(dir);
  if (legacy.existsSync()) await legacy.delete();
  await _dropOldSlots(dir);
}

Future<void> deleteHomeRowCache(String slot) async {
  final dir = await _dir();
  final file = _slotFile(dir, slot);
  if (file.existsSync()) await file.delete();
  final legacy = _legacyFile(dir);
  if (legacy.existsSync()) await legacy.delete();
}

/// Keeps the [_maxSlots] slots written last.
Future<void> _dropOldSlots(Directory dir) async {
  final slots = [
    for (final entity in dir.listSync())
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith(_slotPrefix) &&
          entity.path.endsWith(_slotSuffix))
        (file: entity, at: entity.lastModifiedSync()),
  ]..sort((a, b) => b.at.compareTo(a.at));
  for (final old in slots.skip(_maxSlots)) {
    try {
      await old.file.delete();
    } catch (_) {}
  }
}

/// The cache can be hundreds of KB: its JSON is read and written off the UI
/// isolate.
Future<Object?> decodeHomeRowCache(String raw) =>
    Isolate.run(() => jsonDecode(raw));

Future<String> encodeHomeRowCache(Object envelope) =>
    Isolate.run(() => jsonEncode(envelope));
