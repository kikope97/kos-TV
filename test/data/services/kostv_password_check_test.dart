import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/kostv_password_check.dart';
import 'package:server_core/server_core.dart';

/// Answers each request with whatever the test queued, and remembers it.
class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <String>[];
  int status = 200;
  Object? json;
  bool unreachable = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      bodies.add(utf8.decode(await requestStream.expand((c) => c).toList()));
    }
    if (unreachable) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'unreachable',
      );
    }
    if (options.uri.path == '/Sessions/Logout') {
      return ResponseBody.fromString('', 204);
    }
    return ResponseBody.fromString(
      json == null ? '' : jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late KostvPasswordCheck checker;

  setUp(() {
    adapter = _Adapter();
    final dio = Dio(BaseOptions(validateStatus: (_) => true))
      ..httpClientAdapter = adapter;
    checker = KostvPasswordCheck(
      deviceInfo: const DeviceInfo(
        id: 'tele',
        name: 'Tele',
        appName: 'kOS TV',
        appVersion: '1.0.0',
      ),
      dio: dio,
    );
  });

  Future<KostvPasswordVerdict> run({String password = 'secreto'}) =>
      checker.check(
        baseUrl: 'https://jellyfin.ejemplo.com/',
        userId: '1234abcd-0000-0000-0000-000000000000',
        username: 'Lucía',
        password: password,
      );

  test(
    'an accepted password signs the extra session out straight away',
    () async {
      adapter.json = {
        'AccessToken': 'token-nuevo',
        'User': {'Id': '1234abcd000000000000000000000000'},
      };
      expect(await run(), KostvPasswordVerdict.accepted);

      final signIn = adapter.requests.first;
      expect(
        signIn.uri.toString(),
        'https://jellyfin.ejemplo.com/Users/AuthenticateByName',
      );
      expect(jsonDecode(adapter.bodies.first), {
        'Username': 'Lucía',
        'Pw': 'secreto',
      });
      final header = signIn.headers['Authorization'] as String;
      // Not under the app's own device id, whose session the server would end.
      expect(header, contains('DeviceId="tele-pin-reset"'));
      expect(header, isNot(contains('Token=')));

      final signOut = adapter.requests.last;
      expect(signOut.uri.path, '/Sessions/Logout');
      expect(signOut.headers['Authorization'], contains('Token="token-nuevo"'));
    },
  );

  test('an empty password is sent as it is', () async {
    adapter.json = {
      'AccessToken': 'token-nuevo',
      'User': {'Id': '1234abcd-0000-0000-0000-000000000000'},
    };
    expect(await run(password: ''), KostvPasswordVerdict.accepted);
    expect(jsonDecode(adapter.bodies.first)['Pw'], '');
  });

  test('a refused password is wrong', () async {
    adapter.status = 401;
    expect(await run(), KostvPasswordVerdict.wrong);
    expect(adapter.requests, hasLength(1));
  });

  test('signing in as somebody else is wrong, and is signed out too', () async {
    adapter.json = {
      'AccessToken': 'token-ajeno',
      'User': {'Id': 'otra-persona'},
    };
    expect(await run(), KostvPasswordVerdict.wrong);
    expect(adapter.requests.last.uri.path, '/Sessions/Logout');
  });

  test('without the server there is no telling', () async {
    adapter.unreachable = true;
    expect(await run(), KostvPasswordVerdict.unreachable);
  });

  test('a server error is no answer', () async {
    adapter.status = 500;
    expect(await run(), KostvPasswordVerdict.unreachable);
  });
}
