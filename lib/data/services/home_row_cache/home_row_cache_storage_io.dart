import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../../../util/platform_detection.dart';

const _fileName = 'home_rows_cache.json';

Future<File> _file() async {
  final dir = PlatformDetection.isAppleTV
      ? await getApplicationCacheDirectory()
      : await getApplicationSupportDirectory();
  return File('${dir.path}/$_fileName');
}

/// The saved rows as written, or null when there are none.
Future<String?> readHomeRowCache() async {
  final file = await _file();
  if (!file.existsSync()) return null;
  return file.readAsString();
}

Future<void> writeHomeRowCache(String payload) async {
  final file = await _file();
  await file.writeAsString(payload, flush: true);
}

Future<void> deleteHomeRowCache() async {
  final file = await _file();
  if (file.existsSync()) await file.delete();
}

/// The cache can be hundreds of KB: its JSON is read and written off the UI
/// isolate.
Future<Object?> decodeHomeRowCache(String raw) =>
    Isolate.run(() => jsonDecode(raw));

Future<String> encodeHomeRowCache(Object envelope) =>
    Isolate.run(() => jsonEncode(envelope));
