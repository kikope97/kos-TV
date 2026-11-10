import 'package:server_core/server_core.dart';
import 'package:test/test.dart';

void main() {
  group('ServerType.detect', () {
    test('recognizes a Silo product name', () {
      expect(ServerType.detect('Silo', null), ServerType.silo);
      expect(ServerType.detect('silo media server', '4b2e921c'), ServerType.silo);
    });

    test("classifies Silo's Jellyfin-compatible listener as Jellyfin", () {
      // Silo's compat port answers /System/Info/Public as "Jellyfin Server".
      expect(ServerType.detect('Jellyfin Server', '10.10.7'), ServerType.jellyfin);
    });

    test('treats everything that is not Silo as Jellyfin', () {
      expect(ServerType.detect(null, '4.10.1.0'), ServerType.jellyfin);
      expect(ServerType.detect(null, '10.10.7'), ServerType.jellyfin);
      expect(ServerType.detect(null, null), ServerType.jellyfin);
    });
  });

  test('tokenQueryParam per server type', () {
    expect(ServerType.jellyfin.tokenQueryParam, 'ApiKey');
    expect(ServerType.silo.tokenQueryParam, 'token');
  });

  test('productName per server type', () {
    expect(ServerType.values.map((t) => t.productName), ['Jellyfin', 'Silo']);
  });
}
