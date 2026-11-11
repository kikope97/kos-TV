import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answers Dio calls the way the requests service would, and remembers them.
class FakeStremfinAdapter implements HttpClientAdapter {
  FakeStremfinAdapter(this.answer);

  /// Also by method, for the calls that send something.
  FakeStremfinAdapter.withMethod(this.answerWithMethod)
    : answer = ((_, _) => (status: 500, body: null, headers: const {}));

  /// Path (without `/api/v1`) and query → status, body and headers.
  ({int status, Object? body, Map<String, String> headers}) Function(
    String path,
    Map<String, String> query,
  )
  answer;

  /// Method, path and the JSON sent, when it answers by method.
  ({int status, Object? body, Map<String, String> headers}) Function(
    String method,
    String path,
    Object? sent,
  )?
  answerWithMethod;

  final List<RequestOptions> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final path = options.uri.path.replaceFirst('/api/v1', '');
    final byMethod = answerWithMethod;
    final reply = byMethod != null
        ? byMethod(options.method, path, options.data)
        : answer(path, options.uri.queryParameters);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final e in reply.headers.entries) e.key: [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> fakeTitle(
  int id, {
  String type = 'movie',
  bool inLibrary = false,
  String? itemId,
  int? rank,
}) => {
  'type': type,
  'tmdb_id': id,
  'title': 'Title $id',
  'year': 2026,
  'poster': 'https://image.tmdb.org/t/p/w342/$id.jpg',
  'rank': rank,
  'library': {
    'status': inLibrary ? 'available' : 'missing',
    'in_jellyfin': inLibrary,
    'jellyfin_id': itemId,
    'downloading': false,
  },
  'request': null,
};
