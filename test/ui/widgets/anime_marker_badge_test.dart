import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/anime_marker_repository.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/anime_marker_badge.dart';

class _MockAnimeMarkerRepository extends Mock
    implements AnimeMarkerRepository {}

void main() {
  Widget app(String itemId) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: AnimeItemAudioBadge(itemId: itemId)),
  );

  testWidgets('a late answer for the previous title is not shown', (
    tester,
  ) async {
    final repository = _MockAnimeMarkerRepository();
    final first = Completer<AnimeAudioKind?>();
    when(() => repository.isItemResolved(any())).thenReturn(false);
    when(() => repository.getForItem('a')).thenAnswer((_) => first.future);
    when(() => repository.getForItem('b')).thenAnswer((_) async => null);
    when(() => repository.labelStyle).thenReturn(AnimeAudioLabelStyle.full);
    GetIt.instance.registerSingleton<AnimeMarkerRepository>(repository);
    addTearDown(() => GetIt.instance.reset());

    await tester.pumpWidget(app('a'));
    // The card is reused for another title before the first answer arrives.
    await tester.pumpWidget(app('b'));
    await tester.pump();

    first.complete(AnimeAudioKind.dubbed);
    await tester.pumpAndSettle();

    expect(find.text('DUBBED'), findsNothing);
  });

  testWidgets('the answer for the title on show is shown', (tester) async {
    final repository = _MockAnimeMarkerRepository();
    when(() => repository.isItemResolved(any())).thenReturn(false);
    when(() => repository.getForItem('a'))
        .thenAnswer((_) async => AnimeAudioKind.dubbed);
    when(() => repository.labelStyle).thenReturn(AnimeAudioLabelStyle.full);
    GetIt.instance.registerSingleton<AnimeMarkerRepository>(repository);
    addTearDown(() => GetIt.instance.reset());

    await tester.pumpWidget(app('a'));
    await tester.pumpAndSettle();

    expect(find.text('DUBBED'), findsOneWidget);
  });
}
