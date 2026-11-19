import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/kostv_favorites_news.dart';
import 'package:moonfin/data/utils/blocked_ratings.dart';
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

  /// When set, the next read waits for it.
  Completer<void>? holdNextRead;

  Map<String, Object?> _entry(String series, {required bool unseen}) => {
    'Series': {
      'Id': series,
      'Name': series,
      'Type': 'Series',
      'OfficialRating': series == 'faro' ? 'TV-MA' : 'TV-PG',
    },
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
    final hold = holdNextRead;
    holdNextRead = null;
    if (hold != null) await hold.future;
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
    expect(news.news.first.episode.id, 'faroe1');
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

  // Kos TV: a series marked before its rating was blocked here (or on a
  // device without parental control) showed in big on Favourites and lit
  // the heart.
  test('a series this device blocks shows no news, nor counts for the '
      'alert', () async {
    final plugin = _Plugin();
    final jf = client('ana');
    final settings = await prefs(available: true);
    GetIt.instance.registerSingleton<UserPreferences>(settings);
    addTearDown(() async {
      await GetIt.instance.reset();
      resetParentalFilterCache();
    });
    final news = KostvFavoritesNewsService(
      client: () => jf,
      prefs: settings,
      dio: Dio()..httpClientAdapter = plugin,
    );
    await news.refresh();
    expect(news.news.map((n) => n.series.id), ['faro', 'puerto']);
    expect(news.unseen, 1);

    await settings.set(UserPreferences.blockedParentalRatings, 'TV-MA');
    expect(news.news.map((n) => n.series.id), ['puerto']);
    expect(news.unseen, 0);
    // The same list while nothing changes, for the rows that keep it.
    expect(identical(news.news, news.news), isTrue);

    await settings.set(UserPreferences.blockedParentalRatings, '');
    expect(news.news, hasLength(2));
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

  // Kos TV: a read for the last person, still under way, was handed to the
  // new one and thrown away on landing: no news until the next half hour.
  test('a new person gets a read of their own while the last one\'s is '
      'under way', () async {
    final plugin = _Plugin();
    var jf = client('ana');
    final news = KostvFavoritesNewsService(
      client: () => jf,
      prefs: await prefs(available: true),
      dio: Dio()..httpClientAdapter = plugin,
    );
    final slow = Completer<void>();
    plugin.holdNextRead = slow;
    final anas = news.refresh();
    await pumpEventQueue();

    jf = client('luis');
    await news.refresh();
    expect(plugin.reads, 2);
    expect(news.unseen, 1);

    slow.complete();
    await anas;
    expect(news.news, hasLength(2));
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
  testWidgets('stops asking while the app is out of sight', (tester) async {
    final jf = client('ana');
    final news = KostvFavoritesNewsService(
      client: () => jf,
      prefs: await tester.runAsync(() => prefs(available: false)),
      dio: Dio()..httpClientAdapter = _Plugin(),
    );
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    news.start();
    expect(news.polling, isTrue);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(news.polling, isFalse);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(news.polling, isTrue);
    news.dispose();
  });
}
