import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/stremfin/kostv_age_gate.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/util/parental_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_stremfin_adapter.dart';

const _noHeaders = <String, String>{};

/// Kos TV: what the audit of the Music pages found in the requests
/// service's layer, fixed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  StremfinService serviceOn(HttpClientAdapter adapter) => StremfinService(
    StremfinClient(
      dio: Dio()..httpClientAdapter = adapter,
      baseUrl: 'https://stremfin.ejemplo.com/api/v1',
      token: () => 'token',
    ),
    ageLimit: () async => KostvAgeLimit.none,
    parental: () => ParentalFilter.none,
    watchLifecycle: false,
  );

  group('access', () {
    test('not answering is told apart from saying no', () async {
      var me = 503;
      final adapter = FakeStremfinAdapter((path, _) {
        if (path == '/me') {
          return me == 200
              ? (
                  status: 200,
                  body: {
                    'user': {'role': 'none'},
                    'access': {'can_request': false},
                  },
                  headers: _noHeaders,
                )
              : (
                  status: me,
                  body: {
                    'error': {'code': 'x', 'message': 'x'},
                  },
                  headers: _noHeaders,
                );
        }
        return (status: 404, body: null, headers: _noHeaders);
      });
      final service = serviceOn(adapter);
      service.onUserChanged('ana');
      await service.refreshAccess();
      expect(service.isAllowed, isFalse);
      expect(service.accessUnanswered, isTrue);

      // It answers that they may not.
      me = 403;
      service.onUserChanged('luis');
      await service.refreshAccess();
      expect(service.isAllowed, isFalse);
      expect(service.accessUnanswered, isFalse);

      me = 200;
      service.onUserChanged('eva');
      await service.refreshAccess();
      expect(service.isAllowed, isFalse);
      expect(service.accessUnanswered, isFalse);
      service.dispose();
    });
  });

  group('the Music page\'s answers', () {
    late FakeStremfinAdapter adapter;
    int callsTo(String path) => adapter.calls
        .where((c) => c.uri.path.replaceFirst('/api/v1', '') == path)
        .length;

    setUp(() {
      adapter = FakeStremfinAdapter.withMethod((method, path, _) {
        if (method == 'POST' && path == '/requests') {
          return (
            status: 201,
            body: {'outcome': 'created', 'message': 'Pedido.'},
            headers: _noHeaders,
          );
        }
        if (path == '/music/requested' || path == '/music/releases') {
          return (
            status: 200,
            body: {
              'items': [
                {'title': 'Brisa', 'deezer_id': 1},
              ],
            },
            headers: _noHeaders,
          );
        }
        if (path == '/music/artists/7') {
          return (
            status: 200,
            body: {
              'artist': {'deezer_id': 7, 'name': 'Rosalía'},
              'items': const [],
            },
            headers: _noHeaders,
          );
        }
        return (status: 404, body: null, headers: _noHeaders);
      });
    });

    test('are kept a few minutes, and forgotten once something is asked '
        'for', () async {
      final service = serviceOn(adapter);
      var told = 0;
      service.musicRequestsRevision.addListener(() => told++);
      await service.musicRequested();
      await service.musicRequested();
      await service.musicReleases();
      await service.musicReleases();
      await service.musicArtist('7', keep: true);
      await service.musicArtist('7', keep: true);
      expect(callsTo('/music/requested'), 1);
      expect(callsTo('/music/releases'), 1);
      expect(callsTo('/music/artists/7'), 1);
      // The artist's own page asks each time.
      await service.musicArtist('7');
      expect(callsTo('/music/artists/7'), 2);

      await service.createMusicRequest('1');
      expect(told, 1);
      await service.musicRequested();
      expect(callsTo('/music/requested'), 2);
      service.dispose();
    });

    test('another person doesn\'t get the last one\'s', () async {
      final service = serviceOn(adapter);
      await service.musicRequested();
      service.onUserChanged('luis');
      await service.musicRequested();
      expect(callsTo('/music/requested'), 2);
      service.dispose();
    });
  });
}
