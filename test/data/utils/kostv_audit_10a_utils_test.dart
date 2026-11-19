import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/utils/image_cache_key.dart';
import 'package:moonfin/data/utils/tmdb_language.dart';
import 'package:moonfin/data/utils/user_avatar_url.dart';
import 'package:moonfin/util/silo_image_hooks.dart';
import 'package:server_core/server_core.dart';

class _Client extends Mock implements MediaServerClient {}

class _Images extends Mock implements ImageApi {}

void main() {
  group('tmdbLanguage', () {
    test('Spanish asks for Spain and English for the US', () {
      expect(tmdbLanguage(const Locale('es')), 'es-ES');
      expect(tmdbLanguage(const Locale('en')), 'en-US');
    });

    test('a locale with a region keeps it', () {
      expect(tmdbLanguage(const Locale('es', 'MX')), 'es-MX');
    });
  });

  group('tokenFreeImageCacheKey', () {
    test('drops the token and keeps the rest', () {
      expect(
        tokenFreeImageCacheKey(
          'https://media.example/Moonfin/Tmdb/Thumb?type=movie&tmdbId=1&ApiKey=secret',
        ),
        'https://media.example/Moonfin/Tmdb/Thumb?type=movie&tmdbId=1',
      );
      expect(
        tokenFreeImageCacheKey(
          'https://media.example/Moonfin/Tmdb/StudioImage/3?api_key=secret',
        ),
        'https://media.example/Moonfin/Tmdb/StudioImage/3',
      );
    });

    test('a URL without a token keeps its usual key', () {
      expect(
        tokenFreeImageCacheKey(
          'https://media.example/Items/1/Images/Primary?tag=a',
        ),
        isNull,
      );
      expect(tokenFreeImageCacheKey('https://media.example/a.jpg'), isNull);
    });

    test('two people share one cache entry for the same logo', () {
      addTearDown(() {
        CachedNetworkImageProvider.cacheKeyFor = null;
        CachedNetworkImageProvider.urlResolver = null;
      });
      installSiloImageHooks();
      const logo = 'https://media.example/Moonfin/Tmdb/StudioImage/3';
      expect(
        CachedNetworkImageProvider('$logo?ApiKey=one'),
        CachedNetworkImageProvider('$logo?ApiKey=two'),
      );
    });
  });

  group('userAvatarUrl', () {
    late _Client client;

    setUp(() {
      client = _Client();
      final images = _Images();
      when(() => client.imageApi).thenReturn(images);
      when(() => images.getUserImageUrl(any())).thenAnswer(
        (call) =>
            'https://media.example/Users/${call.positionalArguments.first}'
            '/Images/Primary?maxHeight=256',
      );
    });

    test('carries the tag, so a new photo is a new address', () {
      when(() => client.serverType).thenReturn(ServerType.jellyfin);
      expect(
        userAvatarUrl(client, userId: 'u1', imageTag: 'abc'),
        'https://media.example/Users/u1/Images/Primary?maxHeight=256&tag=abc',
      );
    });

    test('someone with no photo asks for nothing on Jellyfin', () {
      when(() => client.serverType).thenReturn(ServerType.jellyfin);
      expect(userAvatarUrl(client, userId: 'u1'), isNull);
    });

    test('Silo keeps its own address', () {
      when(() => client.serverType).thenReturn(ServerType.silo);
      expect(
        userAvatarUrl(client, userId: 'u1'),
        'https://media.example/Users/u1/Images/Primary?maxHeight=256',
      );
    });
  });
}
