import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/kostv_household_server.dart';
import 'package:moonfin/auth/models/server.dart';
import 'package:moonfin/auth/repositories/server_repository.dart';
import 'package:moonfin/platform/web_runtime_config_model.dart';
import 'package:moonfin/platform/web_runtime_config_stub.dart' as config;
import 'package:server_core/server_core.dart';

class _MockServers extends Mock implements ServerRepository {}

Server _server(String id, String address) => Server(
  id: id,
  name: id,
  address: address,
  version: '10.11.0',
  serverType: ServerType.jellyfin,
  dateAdded: DateTime(2026),
);

/// Kos TV: with the household server built in there is no server to pick,
/// so whatever led to the server list opens that server instead.
void main() {
  late _MockServers repo;

  void householdAt(String? url) => config.webRuntimeConfig = WebRuntimeConfig(
    schemaVersion: 1,
    defaultServerUrl: null,
    discoveryProxyUrl: null,
    enableWebRtcScan: true,
    brandingName: 'kOS TV',
    pluginMode: false,
    forcedServerUrl: null,
    kostvServerUrl: url,
  );

  setUp(() {
    repo = _MockServers();
    when(() => repo.loadStoredServers()).thenAnswer((_) async {});
  });

  tearDown(() => config.webRuntimeConfig = WebRuntimeConfig.defaults);

  test('without a household server there is nothing to open', () async {
    householdAt(null);
    expect(await kostvHouseholdServer(repo), isNull);
    verifyNever(() => repo.addServer(any()));
  });

  test('the stored household server is the one opened', () async {
    householdAt('https://media.example.org');
    final household = _server('home', 'https://media.example.org/');
    when(() => repo.servers)
        .thenReturn([_server('other', 'https://other.example.org'), household]);

    expect(await kostvHouseholdServer(repo), same(household));
    verifyNever(() => repo.addServer(any()));
  });

  test('after everyone signed out it is added again', () async {
    householdAt('https://media.example.org');
    final added = _server('home', 'https://media.example.org');
    when(() => repo.servers).thenReturn(const []);
    when(() => repo.addServer('https://media.example.org'))
        .thenAnswer((_) async => added);

    expect(await kostvHouseholdServer(repo), same(added));
  });

  test('out of reach, nothing is opened', () async {
    householdAt('https://media.example.org');
    when(() => repo.servers).thenReturn(const []);
    when(() => repo.addServer(any())).thenAnswer((_) async => null);

    expect(await kostvHouseholdServer(repo), isNull);
  });
}
