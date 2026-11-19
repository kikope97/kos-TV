import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/item_membership_service.dart';
import 'package:moonfin/data/services/kostv_collections.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

const _device = DeviceInfo(
  id: 'device',
  name: 'Device',
  appName: 'kOS TV',
  appVersion: '1.0.0',
);

/// The server plugin's answer to which collections hold an item, or a plugin
/// from before the route.
class _Plugin implements HttpClientAdapter {
  _Plugin({this.hasRoute = true});

  final bool hasRoute;
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!hasRoute || options.uri.path != '/Moonfin/Kostv/Collections') {
      return ResponseBody.fromString('', 404);
    }
    final itemId = options.uri.queryParameters['itemId']!;
    asked.add(itemId);
    return ResponseBody.fromString(
      jsonEncode({
        'Items': [
          if (itemId == 'movie1')
            {
              'Id': '4b1f0a2c-0000-4000-8000-000000000001',
              'Name': 'Saga',
              'Type': 'BoxSet',
            },
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

AggregatedItem _movie(String id) => AggregatedItem(
  id: id,
  serverId: 'https://casa.example',
  rawData: {'Id': id, 'Type': 'Movie', 'Name': id},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late JellyfinMediaServerClient client;

  setUp(() {
    client =
        JellyfinMediaServerClient(
            baseUrl: 'https://casa.example',
            deviceInfo: _device,
          )
          ..accessToken = 'token'
          ..userId = 'ana';
  });

  tearDown(() async {
    await GetIt.instance.reset();
    ItemMembershipService.instance.clearCache();
    KostvCollectionsLookup.instance = KostvCollectionsLookup();
  });

  group('asking the plugin', () {
    test(
      'gives the collections holding the item, ids without dashes',
      () async {
        final lookup = KostvCollectionsLookup(
          dio: Dio()..httpClientAdapter = _Plugin(),
        );
        final found = await lookup.containing(client, 'movie1');
        expect(found, hasLength(1));
        expect(found!.single['Id'], '4b1f0a2c000040008000000000000001');
        expect(found.single['Name'], 'Saga');
        expect(await lookup.containing(client, 'movie2'), isEmpty);
      },
    );

    test('a plugin without the route is not asked again for a while', () async {
      final plugin = _Plugin(hasRoute: false);
      final lookup = KostvCollectionsLookup(
        dio: Dio()..httpClientAdapter = plugin,
      );
      expect(await lookup.containing(client, 'movie1'), isNull);
      expect(lookup.knownUnsupported(client), isTrue);
      expect(await lookup.containing(client, 'movie1'), isNull);
    });
  });

  group('the card menu', () {
    setUp(() {
      final users = UserRepository()
        ..setCurrentUser(
          PrivateUser(
            id: 'ana',
            name: 'Ana',
            serverId: 'server-1',
            accessToken: 'token',
            lastUsed: DateTime(2026),
            canManageCollections: true,
          ),
        );
      GetIt.instance.registerSingleton<MediaServerClient>(client);
      GetIt.instance.registerSingleton<UserRepository>(users);
    });

    test('asks the plugin for the one item instead of scanning', () async {
      final plugin = _Plugin();
      KostvCollectionsLookup.instance = KostvCollectionsLookup(
        dio: Dio()..httpClientAdapter = plugin,
      );
      final service = ItemMembershipService.instance;

      final found = await service.getCollectionsContaining(_movie('movie1'));
      expect(found.map((c) => c.collectionName), ['Saga']);
      // Remembered for the menu's first frame, and not asked again.
      expect(service.getCachedCollectionsContaining(_movie('movie1')), found);
      await service.getCollectionsContaining(_movie('movie1'));
      expect(plugin.asked, ['movie1']);

      // Taken out of it here: asked again next time.
      service.notifyItemRemovedFromCollection(
        'https://casa.example',
        found.single.collectionId,
        'movie1',
      );
      await service.getCollectionsContaining(_movie('movie1'));
      expect(plugin.asked, ['movie1', 'movie1']);

      // The library changed: asked again too.
      service.onLibraryChanged(
        const LibraryChangedMessage(itemsAdded: ['new']),
      );
      await service.getCollectionsContaining(_movie('movie1'));
      expect(plugin.asked, hasLength(3));
    });

    test('nobody without the permission is offered collections', () async {
      GetIt.instance<UserRepository>().setCurrentUser(
        PrivateUser(
          id: 'ana',
          name: 'Ana',
          serverId: 'server-1',
          accessToken: 'token',
          lastUsed: DateTime(2026),
        ),
      );
      final plugin = _Plugin();
      KostvCollectionsLookup.instance = KostvCollectionsLookup(
        dio: Dio()..httpClientAdapter = plugin,
      );
      final found = await ItemMembershipService.instance
          .getCollectionsContaining(_movie('movie1'));
      expect(found, isEmpty);
      expect(plugin.asked, isEmpty);
    });
  });
}
