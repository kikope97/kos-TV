import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/platform/web_runtime_config_model.dart';

/// Kos TV: the web version's config.json, which its Docker container writes
/// from the container's variables.
void main() {
  test('reads the household server and the requests service', () {
    final config = WebRuntimeConfig.fromJson({
      'schemaVersion': 1,
      'brandingName': 'kOS TV',
      'serverUrl': ' https://media.example.org ',
      'requestsUrl': '/stremfin',
    });

    expect(config.kostvServerUrl, 'https://media.example.org');
    expect(config.kostvRequestsUrl, '/stremfin');
  });

  test('a container without them leaves both empty', () {
    final config = WebRuntimeConfig.fromJson({
      'serverUrl': null,
      'requestsUrl': '',
    });

    expect(config.kostvServerUrl, isNull);
    expect(config.kostvRequestsUrl, isNull);
    expect(WebRuntimeConfig.defaults.kostvServerUrl, isNull);
  });
}
