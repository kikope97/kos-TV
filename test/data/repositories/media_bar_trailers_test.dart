import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/media_bar_repository.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends Mock implements MediaServerClient {}

class _ItemsApi extends Mock implements ItemsApi {}

class _ImageApi extends Mock implements ImageApi {}

/// Kos TV: the slides carry their trailer links and TMDB id, so the banner
/// needn't read every title's full item to find its trailer. The cards of an
/// older server plugin leave them out, and the banner still copes.
void main() {
  late _ItemsApi items;
  late MediaBarRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    items = _ItemsApi();
    final images = _ImageApi();
    when(
      () => images.getPrimaryImageUrl(
        any(),
        tag: any(named: 'tag'),
        maxWidth: any(named: 'maxWidth'),
      ),
    ).thenReturn('primary');
    final client = _Client();
    when(() => client.itemsApi).thenReturn(items);
    when(() => client.imageApi).thenReturn(images);
    repository = MediaBarRepository(client, UserPreferences(store));
  });

  void serve(List<Map<String, dynamic>> answer) {
    when(
      () => items.getItems(
        includeItemTypes: any(named: 'includeItemTypes'),
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        recursive: any(named: 'recursive'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((_) async => {'Items': answer});
  }

  test('the trailer links are asked for with the rest', () async {
    serve(const []);
    await repository.fetchPreviewItems();
    final fields =
        verify(
              () => items.getItems(
                includeItemTypes: any(named: 'includeItemTypes'),
                sortBy: any(named: 'sortBy'),
                sortOrder: any(named: 'sortOrder'),
                recursive: any(named: 'recursive'),
                limit: any(named: 'limit'),
                fields: captureAny(named: 'fields'),
              ),
            ).captured.single
            as String;
    expect(fields.split(','), containsAll(['ProviderIds', 'RemoteTrailers']));
  });

  test(
    'a slide carries its trailer links and TMDB id when they come',
    () async {
      serve([
        {
          'Id': 'film',
          'Name': 'The Film',
          'ProviderIds': <String, String>{'Tmdb': '603', 'Imdb': 'tt0133093'},
          'RemoteTrailers': [
            {'Url': 'https://www.youtube.com/watch?v=abc', 'Name': 'Trailer'},
            {'Name': 'No link'},
          ],
        },
        {'Id': 'bare', 'Name': 'Bare', 'RemoteTrailers': <Object>[]},
      ]);
      final slides = await repository.fetchPreviewItems();

      expect(slides.first.tmdbId, '603');
      expect(slides.first.imdbId, 'tt0133093');
      expect(slides.first.remoteTrailers, [
        {'Url': 'https://www.youtube.com/watch?v=abc', 'Name': 'Trailer'},
      ]);
      expect(slides.first.remoteTrailersKnown, isTrue);
      // None at all is an answer too.
      expect(slides.last.remoteTrailers, isEmpty);
      expect(slides.last.remoteTrailersKnown, isTrue);
    },
  );

  test(
    'a card without them (an older server plugin) still makes a slide',
    () async {
      serve([
        {'Id': 'film', 'Name': 'The Film'},
      ]);
      final slides = await repository.fetchPreviewItems();

      expect(slides.single.tmdbId, isNull);
      expect(slides.single.remoteTrailers, isEmpty);
      expect(slides.single.remoteTrailersKnown, isFalse);
    },
  );

  test('a link spelt in lower case is still read', () {
    expect(
      remoteTrailersOf({
        'RemoteTrailers': [
          {'url': 'https://www.youtube.com/watch?v=abc'},
        ],
      }).single['Url'],
      'https://www.youtube.com/watch?v=abc',
    );
    expect(remoteTrailersOf({'RemoteTrailers': 'nope'}), isEmpty);
  });
}
