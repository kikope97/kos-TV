import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_home.dart';
import 'package:moonfin/data/services/kostv_my_list.dart';
import 'package:moonfin/data/services/stremfin/stremfin_inbox.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:server_core/server_core.dart';

class _SignedIn extends Fake implements MediaServerClient {
  @override
  String get baseUrl => 'http://server';
  @override
  String? get accessToken => 'token';
  @override
  String? get userId => 'mum';
  @override
  ServerType get serverType => ServerType.jellyfin;
  @override
  DeviceInfo get deviceInfo => const DeviceInfo(
    id: 'tv',
    name: 'TV',
    appName: 'kOS TV',
    appVersion: 'test',
  );
}

/// Answers the lookup of what is at home with [items], and counts it.
class _Lookup implements HttpClientAdapter {
  _Lookup(this.items);

  final List<String> items;
  int lookups = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lookups++;
    return ResponseBody.fromString(
      jsonEncode({
        'Items': [
          for (final id in items)
            {
              'Item': {'Id': id, 'Type': 'Movie', 'Name': id},
            },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Stremfin extends Mock implements StremfinService {}

class _Inbox extends Mock implements StremfinInbox {}

class _MyList extends Mock implements KostvMyListService {}

/// Kos TV: what the person asked for and has arrived, and the requests
/// service it comes from.
void main() {
  setUpAll(
    () => registerFallbackValue(
      AggregatedItem(id: 'x', serverId: 's', rawData: const {}),
    ),
  );

  final l10n = lookupAppLocalizations(const Locale('es'));

  ({KostvHomeRepository home, _MyList myList, _Stremfin stremfin}) setUpHome({
    StremfinAccess access = StremfinAccess.allowed,
    Set<String> onList = const {},
  }) {
    final stremfin = _Stremfin();
    when(() => stremfin.access).thenReturn(access);
    when(() => stremfin.isAllowed).thenReturn(access == StremfinAccess.allowed);
    when(() => stremfin.refreshAccess()).thenAnswer((_) async {});
    final inbox = _Inbox();
    when(() => inbox.isLoaded).thenReturn(true);
    when(() => inbox.finished).thenReturn([
      for (final (i, tmdb) in [101, 102].indexed)
        StremfinRequest(
          id: i,
          status: StremfinRequestStatus.completed,
          type: StremfinTitleType.movie,
          tmdbId: tmdb,
          mine: true,
          completedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
    ]);
    when(() => stremfin.inbox).thenReturn(inbox);
    final myList = _MyList();
    when(() => myList.contains(any())).thenAnswer(
      (inv) =>
          onList.contains((inv.positionalArguments.first as AggregatedItem).id),
    );
    when(() => myList.addArrived(any())).thenAnswer((_) async {});
    final dio = Dio()..httpClientAdapter = _Lookup(['a', 'b']);
    return (
      home: KostvHomeRepository(
        _SignedIn(),
        dio: dio,
        stremfin: stremfin,
        myList: myList,
      ),
      myList: myList,
      stremfin: stremfin,
    );
  }

  test('goes on their list once a session, and not when it is on it '
      'already', () async {
    final s = setUpHome(onList: {'b'});

    final row = await s.home.arrived(l10n);
    await s.home.arrived(l10n);
    await s.home.arrived(l10n);

    expect(row?.items.map((i) => i.id), ['a', 'b']);
    verify(() => s.myList.addArrived('a')).called(1);
    verifyNever(() => s.myList.addArrived('b'));
  });

  test(
    'the requests service is asked again only while it hasn\'t said',
    () async {
      final denied = setUpHome(access: StremfinAccess.denied);
      expect(await denied.home.allowedStremfin(), isNull);
      verifyNever(() => denied.stremfin.refreshAccess());

      final unknown = setUpHome(access: StremfinAccess.unknown);
      expect(await unknown.home.allowedStremfin(), isNull);
      verify(() => unknown.stremfin.refreshAccess()).called(1);

      final allowed = setUpHome();
      expect(await allowed.home.allowedStremfin(), same(allowed.stremfin));
      verifyNever(() => allowed.stremfin.refreshAccess());
    },
  );
}
