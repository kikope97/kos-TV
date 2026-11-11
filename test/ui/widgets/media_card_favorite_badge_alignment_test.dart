import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/anime_marker_repository.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/anime_marker_badge.dart';
import 'package:moonfin/ui/widgets/media_badge.dart';
import 'package:moonfin/ui/widgets/media_card.dart';

class _MockAnimeMarkerRepository extends Mock
    implements AnimeMarkerRepository {}

void main() {
  Widget testCard({
    required bool isFavorite,
    String? animeMarkerItemId,
    String? mediaTypeBadge,
    bool overlayOccupiesTopLeft = false,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MediaCard(
        title: 'Test Movie',
        width: 150,
        aspectRatio: 2 / 3,
        itemType: 'Movie',
        isFavorite: isFavorite,
        animeMarkerItemId: animeMarkerItemId,
        mediaTypeBadge: mediaTypeBadge,
        overlayOccupiesTopLeft: overlayOccupiesTopLeft,
        onTap: () {},
      ),
    ),
  );

  /// A null [audio] is an item the server has no verdict for, which is the
  /// state a card without an audio pill is in.
  void useAnimeRepository(String itemId, AnimeAudioKind? audio) {
    final repository = _MockAnimeMarkerRepository();
    when(() => repository.isItemResolved(itemId)).thenReturn(audio != null);
    when(() => repository.peekItem(itemId)).thenReturn(audio);
    when(() => repository.getForItem(itemId)).thenAnswer((_) async => audio);
    when(() => repository.labelStyle).thenReturn(AnimeAudioLabelStyle.full);
    GetIt.instance.registerSingleton<AnimeMarkerRepository>(repository);
    addTearDown(() => GetIt.instance.reset());
  }

  /// The MOVIE badge's box, around its label.
  Finder typeBadge() => find
      .ancestor(of: find.text('MOVIE'), matching: find.byType(DecoratedBox))
      .first;

  Offset offsetFromCard(WidgetTester tester, Finder finder) {
    expect(finder, findsOneWidget);
    return tester.getTopLeft(finder) - tester.getTopLeft(find.byType(MediaCard));
  }

  testWidgets(
    'favorite badge sits at top 6 when the anime marker resolves to nothing',
    (tester) async {
      useAnimeRepository('item-123', null);

      await tester.pumpWidget(
        testCard(isFavorite: true, animeMarkerItemId: 'item-123'),
      );
      await tester.pumpAndSettle();

      final favorite = offsetFromCard(tester, find.byType(MediaFavoriteBadge));
      expect(favorite.dx, closeTo(6.0, 0.1));
      expect(favorite.dy, closeTo(6.0, 0.1));
    },
  );

  testWidgets(
    'favorite badge sits at top 6 when animeMarkerItemId is null',
    (tester) async {
      await tester.pumpWidget(testCard(isFavorite: true));

      final favorite = offsetFromCard(tester, find.byType(MediaFavoriteBadge));
      expect(favorite.dx, closeTo(6.0, 0.1));
      expect(favorite.dy, closeTo(6.0, 0.1));
    },
  );

  testWidgets(
    'favorite badge sits at top 32 when overlayOccupiesTopLeft is explicitly true',
    (tester) async {
      await tester.pumpWidget(
        testCard(isFavorite: true, overlayOccupiesTopLeft: true),
      );

      final favorite = offsetFromCard(tester, find.byType(MediaFavoriteBadge));
      expect(favorite.dx, closeTo(6.0, 0.1));
      expect(favorite.dy, closeTo(32.0, 0.1));
    },
  );

  testWidgets(
    'favorite badge sits below anime audio badge when audio is resolved',
    (tester) async {
      useAnimeRepository('anime-1', AnimeAudioKind.subbed);

      await tester.pumpWidget(
        testCard(isFavorite: true, animeMarkerItemId: 'anime-1'),
      );

      expect(
        offsetFromCard(tester, find.byType(MediaFavoriteBadge)).dx,
        closeTo(6.0, 0.1),
      );
      // The pill carries its own bottom gap, so the heart starts where it ends.
      expect(
        tester.getRect(find.byType(MediaFavoriteBadge)).top,
        closeTo(tester.getRect(find.byType(AnimeItemAudioBadge)).bottom, 0.1),
      );
    },
  );

  testWidgets(
    'favorite badge sits under the media type badge',
    (tester) async {
      await tester.pumpWidget(
        testCard(isFavorite: true, mediaTypeBadge: 'movie'),
      );

      final badge = tester.getRect(typeBadge());
      final favorite = tester.getRect(find.byType(MediaFavoriteBadge));

      expect(
        offsetFromCard(tester, typeBadge()).dy,
        closeTo(6.0, 0.1),
      );
      expect(
        offsetFromCard(tester, find.byType(MediaFavoriteBadge)).dx,
        closeTo(6.0, 0.1),
      );
      expect(favorite.top - badge.bottom, closeTo(4.0, 0.1));
    },
  );

  testWidgets(
    'an occupied corner moves the media type badge down with the stack',
    (tester) async {
      await tester.pumpWidget(
        testCard(
          isFavorite: true,
          mediaTypeBadge: 'movie',
          overlayOccupiesTopLeft: true,
        ),
      );

      final badge = tester.getRect(typeBadge());
      final favorite = tester.getRect(find.byType(MediaFavoriteBadge));

      expect(
        offsetFromCard(tester, typeBadge()).dy,
        closeTo(32.0, 0.1),
      );
      expect(favorite.top - badge.bottom, closeTo(4.0, 0.1));
    },
  );
}
