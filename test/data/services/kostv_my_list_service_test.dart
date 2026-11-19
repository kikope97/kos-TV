import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_my_list.dart';
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

Map<String, Object?> _card(String id) => {
  'Id': id,
  'Name': id,
  'Type': 'Movie',
};

/// The server plugin's list: what is on it and what was watched.
class _Plugin implements HttpClientAdapter {
  final onList = <String>{'ana', 'faro', 'visto'};
  final watched = <String>{'visto'};
  final posts = <Map<String, dynamic>>[];
  int reads = 0;
  int clears = 0;

  /// When set, the next read waits for it, so another can overtake it.
  Completer<void>? holdNextRead;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path == '/Moonfin/Kostv/MyList/ClearWatched') {
      clears++;
      onList.removeAll(watched);
      return ResponseBody.fromString('', 204);
    }
    if (path != '/Moonfin/Kostv/MyList') {
      return ResponseBody.fromString('', 404);
    }
    if (options.method == 'POST') {
      final query = options.uri.queryParameters;
      posts.add(query);
      final id = query['itemId']!;
      query['remove'] == 'true' ? onList.remove(id) : onList.add(id);
      return _json({'OnList': onList.contains(id), 'ItemId': id});
    }
    reads++;
    // What this read answers is what the list was when it was asked.
    final snapshot = Set.of(onList);
    final hold = holdNextRead;
    holdNextRead = null;
    if (hold != null) await hold.future;
    return _json({
      'Watching': <Object>[],
      'ToStart': [
        for (final id in snapshot)
          if (!watched.contains(id)) _card(id),
      ],
      'Watched': [
        for (final id in snapshot)
          if (watched.contains(id)) _card(id),
      ],
      'Ids': snapshot.toList(),
    });
  }

  ResponseBody _json(Object body) => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

AggregatedItem _movie(String id) => AggregatedItem(
  id: id,
  serverId: 'https://casa.example',
  rawData: _card(id),
);

void main() {
  Future<UserPreferences> prefs() async {
    SharedPreferences.setMockInitialValues({'kostv_my_list_available': true});
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

  test('what arrived is told once a session, and the list is read again '
      'only when it went on now', () async {
    final plugin = _Plugin();
    final jf = client('ana');
    final list = KostvMyListService(
      client: () => jf,
      prefs: await prefs(),
      dio: Dio()..httpClientAdapter = plugin,
    );
    list.noteIds(['faro']);

    // Already on the list: told, but nothing to read again.
    await list.addArrived('faro');
    expect(plugin.posts, hasLength(1));
    expect(plugin.reads, 0);

    // Every Home load asks again: nothing more is sent.
    await list.addArrived('faro');
    await list.addArrived('faro');
    expect(plugin.posts, hasLength(1));

    // New on the list: told and read.
    await list.addArrived('nueva');
    await pumpEventQueue();
    expect(plugin.posts, hasLength(2));
    expect(plugin.reads, 1);
    expect(list.contains(_movie('nueva')), isTrue);
  });

  test(
    'an older read landing last doesn\'t put back what was taken off',
    () async {
      final plugin = _Plugin();
      final jf = client('ana');
      final list = KostvMyListService(
        client: () => jf,
        prefs: await prefs(),
        dio: Dio()..httpClientAdapter = plugin,
      );
      final slow = Completer<void>();
      plugin.holdNextRead = slow;
      final older = list.load();
      await pumpEventQueue();

      // Taken off meanwhile: gone from the buttons at once, and read again.
      expect(await list.set(_movie('faro'), onList: false), isFalse);
      await pumpEventQueue();
      expect(list.contains(_movie('faro')), isFalse);
      expect(list.page!.toStart.map((i) => i.id), isNot(contains('faro')));

      // The first read, from before, lands now.
      slow.complete();
      await older;
      expect(list.contains(_movie('faro')), isFalse);
      expect(list.page!.toStart.map((i) => i.id), isNot(contains('faro')));
    },
  );

  test(
    'an answer about the last person\'s list doesn\'t touch the new one\'s',
    () async {
      final plugin = _Plugin();
      var jf = client('ana');
      final list = KostvMyListService(
        client: () => jf,
        prefs: await prefs(),
        dio: Dio()..httpClientAdapter = plugin,
      );
      list.noteIds(['ana']);
      final adding = list.set(_movie('para-ana'), onList: true);
      jf = client('luis');
      await adding;
      expect(list.contains(_movie('para-ana')), isFalse);
    },
  );

  test('«Clear watched» hides them at once and can be taken back', () async {
    final plugin = _Plugin();
    final jf = client('ana');
    final list = KostvMyListService(
      client: () => jf,
      prefs: await prefs(),
      dio: Dio()..httpClientAdapter = plugin,
    );
    await list.load();
    expect(list.page!.watched, hasLength(1));

    fakeAsync((async) {
      bool? result;
      list.clearWatchedLater().then((v) => result = v);
      expect(list.page!.watched, isEmpty);
      expect(list.clearPending, isTrue);

      async.elapse(const Duration(seconds: 2));
      list.undoClearWatched();
      async.flushMicrotasks();
      expect(result, isFalse);
      expect(list.page!.watched, hasLength(1));

      // Its time would have run out: nothing was sent.
      async.elapse(KostvMyListService.clearUndoTime);
      expect(plugin.clears, 0);
    });
  });

  test('«Clear watched» tells the server once its time is up', () {
    fakeAsync((async) {
      final plugin = _Plugin();
      final jf = client('ana');
      late KostvMyListService list;
      prefs().then((p) {
        list = KostvMyListService(
          client: () => jf,
          prefs: p,
          dio: Dio()..httpClientAdapter = plugin,
        );
      });
      async.flushMicrotasks();
      list.load();
      async.flushMicrotasks();
      async.elapse(Duration.zero);

      bool? result;
      list.clearWatchedLater().then((v) => result = v);
      async.elapse(KostvMyListService.clearUndoTime);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 10));
      expect(plugin.clears, 1);
      expect(result, isTrue);
      expect(list.page!.watched, isEmpty);
      expect(list.clearPending, isFalse);
    });
  });
}
