import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

/// What the server made of a Jellyfin password it was asked to check.
enum KostvPasswordVerdict {
  /// The server signed the account in with it.
  accepted,

  /// The server turned it down.
  wrong,

  /// The server could not be reached or did not say.
  unreachable,
}

/// Kos TV: checks a Jellyfin account's password with the server, for the way
/// out of a PIN kept on the device that was forgotten. It signs in by name
/// apart from the session in use: under a device id of its own (the server
/// ends that device's earlier sign-in for the same user, which would be the
/// session in use under the app's own id), on a client of its own (a refusal
/// must not read as the session having expired), and it signs that extra
/// session out straight away, so none are left behind.
class KostvPasswordCheck {
  KostvPasswordCheck({required this.deviceInfo, @visibleForTesting Dio? dio})
    : _dio = dio ?? _newDio();

  final DeviceInfo deviceInfo;
  final Dio _dio;

  static Dio _newDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        // The answers are read by status, not thrown.
        validateStatus: (_) => true,
      ),
    );
    configureServerDio(dio);
    // The password goes with this request: never to another host.
    dio.interceptors.add(redirectInterceptor(dio, sameOriginOnly: true));
    return dio;
  }

  /// The device the check signs in as: this one, under an id of its own.
  /// Always the same id, so a check whose sign-out was lost is ended by the
  /// next one.
  DeviceInfo get _checkDevice => DeviceInfo(
    id: '${deviceInfo.id}-pin-reset',
    name: deviceInfo.name,
    appName: deviceInfo.appName,
    appVersion: deviceInfo.appVersion,
  );

  String _header([String? token]) => buildServerAuthorizationHeader(
    scheme: 'MediaBrowser',
    deviceInfo: _checkDevice,
    accessToken: token,
  );

  /// Whether [password] signs [username] in on the server at [baseUrl] as the
  /// user [userId]. An empty password is sent as it is: the server accepts it
  /// for an account without one.
  Future<KostvPasswordVerdict> check({
    required String baseUrl,
    required String userId,
    required String username,
    required String password,
  }) async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '$base/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
        options: Options(headers: {'Authorization': _header()}),
      );
    } on DioException {
      return KostvPasswordVerdict.unreachable;
    }
    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) return KostvPasswordVerdict.wrong;
    final data = response.data;
    if (status != 200 || data is! Map) {
      return KostvPasswordVerdict.unreachable;
    }
    final token = data['AccessToken'];
    final user = data['User'];
    final signedIn = user is Map ? user['Id']?.toString() : null;
    if (token is String && token.isNotEmpty) await _signOut(base, token);
    if (token is! String || token.isEmpty) {
      return KostvPasswordVerdict.unreachable;
    }
    // Someone else's account by that name is not this person's password.
    return _sameId(signedIn, userId)
        ? KostvPasswordVerdict.accepted
        : KostvPasswordVerdict.wrong;
  }

  /// Ends the session the check opened.
  Future<void> _signOut(String base, String token) async {
    try {
      await _dio.post<dynamic>(
        '$base/Sessions/Logout',
        options: Options(headers: {'Authorization': _header(token)}),
      );
    } on DioException {
      // The next check, under the same device id, ends it.
    }
  }

  /// Lets go of the connections, once no more checks are coming.
  void close() => _dio.close();

  /// Jellyfin writes ids with and without dashes.
  static bool _sameId(String? a, String b) {
    if (a == null) return false;
    String plain(String id) => id.replaceAll('-', '').toLowerCase();
    return plain(a) == plain(b);
  }
}
