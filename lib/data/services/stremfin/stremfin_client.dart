import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../util/kostv_server.dart';
import '../log_service.dart';
import 'stremfin_models.dart';

/// Kos TV: a failed call to the requests service.
class StremfinException implements Exception {
  const StremfinException({
    required this.code,
    this.status,
    this.message,
    this.retryAfter,
  });

  /// The API's error code (`invalid_token`, `api_disabled`…), `network` when
  /// the service could not be reached, or `bad_response`.
  final String code;
  final int? status;

  /// Spanish text from the service, ready to show.
  final String? message;
  final Duration? retryAfter;

  /// The person has no access (signed out, not linked, no access).
  bool get isNoAccess => status == 401 || status == 403;

  @override
  String toString() => 'StremfinException($status $code)';
}

/// Kos TV: talks to the requests service (Stremfin) with the person's own
/// home-server token, which it never puts in a URL or a log.
class StremfinClient {
  StremfinClient({
    Dio? dio,
    String? baseUrl,
    @visibleForTesting String? Function()? token,
  }) : _baseUrl = baseUrl == null
           // The address can change while the app runs (the home server's
           // plugin gives it), so it's read on every call.
           ? (() => apiBaseFor(kostvRequestsUrl))
           : (() => baseUrl),
       _token = token ?? _sessionToken,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
             ),
           );

  final Dio _dio;
  final String? Function() _baseUrl;
  final String? Function() _token;

  /// Whether the app knows where the service is.
  bool get isConfigured => _baseUrl() != null;

  /// The API's base from the build's address: with or without a trailing
  /// slash or `/api/v1`, and always over https, since every call carries the
  /// person's token. A path (`/stremfin`, the web container's way in to the
  /// service) belongs to the site the app was opened from, [site], and keeps
  /// that site's scheme.
  @visibleForTesting
  static String? apiBaseFor(String raw, {Uri? site}) {
    var url = raw.trim();
    if (url.isEmpty) return null;
    if (url.startsWith('/')) {
      final origin = site ?? Uri.base;
      if (!origin.hasAuthority) return null;
      url = origin.resolve(url).toString();
    } else {
      if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
      if (!url.startsWith('https://')) url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api/v1')) url = url.substring(0, url.length - 7);
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return '$url/api/v1';
  }

  static String? _sessionToken() {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<MediaServerClient>()) {
      final token = getIt<MediaServerClient>().accessToken;
      if (token != null && token.isNotEmpty) return token;
    }
    return null;
  }

  Future<StremfinMe> me() async => StremfinMe.fromJson(await _get('/me'));

  Future<List<StremfinPlatform>> platforms() async {
    final body = await _get('/platforms');
    final raw = body is Map ? body['platforms'] : null;
    return [
      if (raw is List)
        for (final entry in raw) ?StremfinPlatform.fromJson(entry),
    ];
  }

  Future<List<StremfinTitle>> top({
    required String platform,
    required StremfinTitleType type,
    required StremfinTopList list,
    int? limit,
  }) async {
    final body = await _get('/top', {
      'platform': platform,
      'type': type.apiValue,
      'list': list.apiValue,
      'limit': ?limit,
    });
    final raw = body is Map ? body['items'] : null;
    return [
      if (raw is List)
        for (final entry in raw) ?StremfinTitle.fromJson(entry),
    ];
  }

  /// Films and series whose name matches [query], only the ones that
  /// aren't on the home server unless [only] says otherwise (`all`,
  /// `missing` or `available`). One of the costly calls: the service allows
  /// thirty a minute of them.
  Future<StremfinSearchPage> search(
    String query, {
    String only = 'missing',
    int? limit,
    String? cursor,
  }) async => StremfinSearchPage.fromJson(
    await _get('/search', {
      'q': query,
      'type': 'all',
      'only': only,
      'limit': ?limit,
      'cursor': ?cursor,
    }),
  );

  /// A film's page.
  Future<StremfinMovieDetail> movie(int tmdbId) async {
    final detail = StremfinMovieDetail.fromJson(await _get('/movies/$tmdbId'));
    if (detail == null) throw const StremfinException(code: 'bad_response');
    return detail;
  }

  /// Whether a film can be downloaded now and how fast. It asks the
  /// service's sources, so it takes a few seconds.
  Future<StremfinAvailability> movieAvailability(int tmdbId) async =>
      StremfinAvailability.fromJson(await _get('/movies/$tmdbId/availability'));

  /// A series' page, season by season.
  Future<StremfinSeriesDetail> series(int tmdbId) async {
    final detail = StremfinSeriesDetail.fromJson(await _get('/series/$tmdbId'));
    if (detail == null) throw const StremfinException(code: 'bad_response');
    return detail;
  }

  /// The person's own requests: [status] `open`, `closed` or `all`; with
  /// [since] (a `now` the service gave), only those changed since then.
  Future<StremfinRequestPage> requests({
    String status = 'all',
    String? since,
    int? limit,
  }) async => StremfinRequestPage.fromJson(
    await _get('/requests', {
      'scope': 'mine',
      'status': status,
      'since': ?since,
      'limit': ?limit,
    }),
  );

  /// One request as it stands now.
  Future<StremfinRequest> request(int id) async {
    final request = StremfinRequest.fromJson(await _get('/requests/$id'));
    if (request == null) throw const StremfinException(code: 'bad_response');
    return request;
  }

  /// Asks for a film, a season of a series or, with no [season], all that is
  /// missing of it. Whatever the answer says happened is a result, even when
  /// it comes with an error status (it is there already, the limit…); only
  /// an `error` is thrown.
  Future<StremfinRequestResult> createRequest({
    required StremfinTitleType type,
    required int tmdbId,
    int? season,
    int? episode,
    @visibleForTesting Duration busyPause = const Duration(milliseconds: 500),
  }) async {
    final data = {
      'type': type.apiValue,
      'tmdb_id': tmdbId,
      if (type == StremfinTitleType.series) 'season': season,
      // Kos TV: one episode of that season on its own.
      if (type == StremfinTitleType.series && season != null && episode != null)
        'episode': episode,
    };
    var response = await _send('POST', '/requests', data: data);
    // Kos TV: the service saves requests one at a time, and says it is busy
    // (503 busy) when another lands in the same instant: asked again, twice
    // at most, as it says.
    for (var tries = 0; tries < 2 && _isBusy(response); tries++) {
      await Future<void>.delayed(busyPause);
      response = await _send('POST', '/requests', data: data);
    }
    final body = response.data;
    if (body is Map && body['outcome'] is String) {
      return StremfinRequestResult.fromJson(
        body,
        retryAfter: _retryAfter(response),
      );
    }
    throw _failure(response);
  }

  /// Takes back one of theirs that still waits for an answer.
  Future<void> withdrawRequest(int id) async {
    final response = await _send('DELETE', '/requests/$id');
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) throw _failure(response);
  }

  Future<Object?> _get(String path, [Map<String, Object?>? query]) async {
    final response = await _send('GET', path, query: query);
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return response.data;
    throw _failure(response);
  }

  Future<Response<Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? data,
  }) async {
    final base = _baseUrl();
    if (base == null) {
      throw const StremfinException(code: 'not_configured');
    }
    final token = _token();
    if (token == null) {
      throw const StremfinException(code: 'unauthenticated', status: 401);
    }
    final Response<Object?> response;
    try {
      response = await _dio.request<Object?>(
        '$base$path',
        queryParameters: query,
        data: data,
        options: Options(
          method: method,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
          contentType: data == null ? null : Headers.jsonContentType,
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      _log('x $method $path (${e.type.name})');
      throw const StremfinException(code: 'network');
    }
    // Only the path: the address of the service and the token stay out of
    // the app's log.
    _log('<- ${response.statusCode ?? 0} $method $path');
    return response;
  }

  static StremfinException _failure(Response<Object?> response) {
    final status = response.statusCode ?? 0;
    final body = response.data;
    final error = body is Map ? body['error'] : null;
    final code = error is Map && error['code'] is String
        ? error['code'] as String
        : 'http_$status';
    final message = error is Map && error['message'] is String
        ? error['message'] as String
        : null;
    return StremfinException(
      code: code,
      status: status,
      message: message,
      retryAfter: _retryAfter(response),
    );
  }

  static bool _isBusy(Response<Object?> response) {
    if (response.statusCode != 503) return false;
    final body = response.data;
    final error = body is Map ? body['error'] : null;
    return error is Map && error['code'] == 'busy';
  }

  static Duration? _retryAfter(Response<Object?> response) {
    final seconds = int.tryParse(response.headers.value('retry-after') ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static void _log(String line) {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<LogService>()) {
      getIt<LogService>().network('[Stremfin] $line');
    }
  }
}
