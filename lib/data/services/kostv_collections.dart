import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import 'moonbase_endpoint.dart';

/// Kos TV: asks the server plugin which collections hold an item, in one
/// request, where the server itself can only be asked collection by
/// collection.
///
/// A plugin from before this route answers 404; that server is then not asked
/// again for [_retryAfter], and the callers scan the collections as before.
class KostvCollectionsLookup {
  KostvCollectionsLookup({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  /// The one the app asks through; a test puts its own in.
  static KostvCollectionsLookup instance = KostvCollectionsLookup();

  /// How long a server whose plugin lacks the route is left alone. Short
  /// enough that updating the plugin shows without restarting the app.
  static const _retryAfter = Duration(minutes: 30);

  final Dio _dio;
  final Map<String, DateTime> _unsupportedAt = {};

  /// Whether [client]'s plugin was last seen without the route.
  bool knownUnsupported(MediaServerClient client) {
    final at = _unsupportedAt[client.baseUrl];
    return at != null && DateTime.now().difference(at) < _retryAfter;
  }

  /// The collections the person can see that hold [itemId] itself, as the
  /// server's item lists carry them (`Id`, `Name`, `ImageTags`…). Null when
  /// the plugin can't answer, so the caller scans instead.
  Future<List<Map<String, dynamic>>?> containing(
    MediaServerClient client,
    String itemId,
  ) async {
    if (itemId.isEmpty) return null;
    try {
      if (knownUnsupported(client)) return null;
      final ep = await moonbaseEndpoint(client, _dio);
      if (ep == null) return null;
      final response = await _dio.get<dynamic>(
        '${ep.base}/Moonfin/Kostv/Collections',
        queryParameters: {'itemId': itemId},
        options: Options(headers: ep.headers),
      );
      final data = response.data;
      if (data is! Map) return null;
      final items = data['Items'];
      if (items is! List) return null;
      return [
        for (final raw in items)
          if (raw is Map && raw['Id'] != null)
            {
              ...raw.cast<String, dynamic>(),
              // The plugin writes ids with dashes; the server's lists don't.
              'Id': raw['Id'].toString().replaceAll('-', ''),
            },
      ];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _unsupportedAt[client.baseUrl] = DateTime.now();
      } else {
        debugPrint('[Collections] Asking the plugin failed: ${e.message}');
      }
      return null;
    } catch (e) {
      debugPrint('[Collections] Asking the plugin failed: $e');
      return null;
    }
  }

  /// Forgets which servers lacked the route (sign-out, a user switch).
  @visibleForTesting
  void reset() => _unsupportedAt.clear();
}
