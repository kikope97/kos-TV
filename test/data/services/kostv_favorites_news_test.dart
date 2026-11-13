import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/kostv_favorites_news.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _device = DeviceInfo(
  id: 'device',
  name: 'Device',
  appName: 'kOS TV',
  appVersion: '1.0.0',
);

/// The server plugin's news, until it is told they were seen.
class _Plugin implements HttpClientAdapter {
  bool seen = false;
  int reads = 0;

  Map<String, Object?> _entry(String series, {required bool unseen}) => {
    'Series': {'Id': series, 'Name': series, 'Type': 'Series'},
    'Episode': {
      'Id': '$series-e1',
      'Name': 'Uno',
      'Type': 'Episode',
      'SeriesId': series,
    },
    'Count': 3,
    'NewSeason': series == 'faro',
    'Season': 2,
    'Unseen': unseen,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path == '/Moonfin/Kostv/Favorites/News/Seen' &&
        options.method == 'POST') {
      seen = true;
      return ResponseBody.fromString('', 204);
    }
    if (path != '/Moonfin/Kostv/Favorites/News') {
      return ResponseBody.fromString('', 404);
    }
    reads++;
    return ResponseBody.fromString(
      jsonEncode({
        'Series': [
          _entry('faro', unseen: !seen),
          _entry('puerto', unseen: false),
          // Broken entries are left out.
          {'Series': null, 'Episode': null},
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Future<UserPreferences> prefs({required bool available}) async {
    SharedPreferences.setMockInitialValues({
      'kostv_favorites_available': available,
    });
    final store = PreferenceStore();
    await store.init();
    return UserPreferences(store);
  }

  JellyfinMediaServerClient client(String user) =>
      JellyfinMediaServerClient(
          baseUrl: 'https://casa.example',
          deviceInfo: _device,
        )
        ..accessToken = 'token'
        ..userId = user;

  test('reads the news of favourite series and counts what wasn\'t seen, '
      'then clears it on the server too', () async {
    final plugin = _Plugin();
    final jf = client('ana');
    final news = KostvFavoritesNewsService(
      client: () => jf,
      prefs: await prefs(available: true),
      dio: Dio()..httpClientAdapter = plugin,
    );
    var told = 0;
    news.addListener(() => told++);

    await news.refresh();
    expect(news.news.map((n) => n.series.id), ['faro', 'puerto']);
    expect(news.news.first.newSeason, isTrue);
    expect(news.news.first.episode.id, 'faro-e1');
    expect(news.news.first.count, 3);
    expect(news.unseen, 1);

    await news.markSeen();
    expect(news.unseen, 0);
    expect(plugin.seen, isTrue);
    // Still there to see: only the alert goes.
    expect(news.news, hasLength(2));

    // Read a moment ago: not asked again unless told to.
    await news.refresh();
    expect(plugin.reads, 1);
    await news.refresh(force: true);
    expect(plugin.reads, 2);
    expect(news.unseen, 0);
    expect(told, greaterThanOrEqualTo(3));
    news.dispose();
  });

  test('another person never sees someone else\'s news', () async {
    final plugin = _Plugin();
    var jf = client('ana');
    final news = KostvFavoritesNewsService(
      client: () => jf,
      prefs: await prefs(available: true),
      dio: Dio()..httpClientAdapter = plugin,
    );
    await news.refresh();
    expect(news.unseen, 1);

    jf = client('luis');
    expect(news.news, isEmpty);
    expect(news.unseen, 0);
    news.dispose();
  });

  test(
    'with an older server plugin, nothing is asked and no alert shows',
    () async {
      final plugin = _Plugin();
      final jf = client('ana');
      final news = KostvFavoritesNewsService(
        client: () => jf,
        prefs: await prefs(available: false),
        dio: Dio()..httpClientAdapter = plugin,
      );
      await news.refresh(force: true);
      await news.markSeen();
      expect(plugin.reads, 0);
      expect(plugin.seen, isFalse);
      expect(news.unseen, 0);
      news.dispose();
    },
  );
}
