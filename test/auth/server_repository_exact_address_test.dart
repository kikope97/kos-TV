import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/auth/store/authentication_store.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';

// Kos TV: the household server used to be looked for like a typed address:
// https, then plain http and other ports. Its https failing (a captive
// portal, say) and something answering over http stored the household
// server in http, with the password sent in the clear from then on.

class _AuthStore extends Fake implements AuthenticationStore {
  @override
  Future<void> putServer(Server server) async {}
}

class _ClientFactory extends Fake implements MediaServerClientFactory {}

// Sends every connection to the fake server, a plain HTTP one: an https
// address reaches it too, and fails there. With a connection factory dart:io
// leaves TLS to the factory for a direct https connection, so https gets a
// real TLS handshake here (which the plain server can't answer), and no proxy
// from the environment is used, so the result doesn't depend on the machine.
class _LoopbackOverrides extends HttpOverrides {
  _LoopbackOverrides(this.port);

  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = ((_) => 'DIRECT')
        ..connectionFactory = (uri, proxyHost, proxyPort) =>
            uri.isScheme('https')
            ? SecureSocket.startConnect(
                InternetAddress.loopbackIPv4,
                port,
                onBadCertificate: (_) => true,
              )
            : Socket.startConnect(InternetAddress.loopbackIPv4, port);
}

void main() {
  late HttpServer plainHttp;
  late ServerRepository repo;

  setUp(() async {
    repo = ServerRepository(_AuthStore(), _ClientFactory());
    plainHttp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    plainHttp.listen((request) {
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'ServerName': 'Not the household server',
            'Version': '10.11.0',
            'ProductName': 'Jellyfin Server',
          }),
        )
        ..close();
    });
  });

  tearDown(() => plainHttp.close(force: true));

  Future<Server?> add(String address, {required bool exact}) =>
      HttpOverrides.runWithHttpOverrides(
        () => repo.addServer(address, exactAddressOnly: exact),
        _LoopbackOverrides(plainHttp.port),
      );

  test('the household server is only tried at its own address', () async {
    final server = await add('https://home.example.org', exact: true);

    expect(server, isNull);
    expect(repo.lastFailure?.candidatesTried, ['https://home.example.org']);
  });

  test('a typed address still tries the other ways', () async {
    final server = await add('https://home.example.org', exact: false);

    expect(server?.address, startsWith('http://'));
  });

  test('exactServerCandidate keeps the scheme, or uses https', () {
    expect(exactServerCandidate('https://a.example'), 'https://a.example');
    expect(
      exactServerCandidate('http://a.example:8096'),
      'http://a.example:8096',
    );
    expect(exactServerCandidate('a.example'), 'https://a.example');
  });
}
