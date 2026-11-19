import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/minimalist/widgets/minimalist_episodes_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ViewModel extends Mock implements ItemDetailViewModel {}

// Kos TV: a series whose episodes failed to load used to show nothing under
// Play, with no way to ask again short of leaving the page (Kids Mode always
// uses this section).

void main() {
  late UserPreferences prefs;
  late _ViewModel vm;
  var loads = 0;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    GetIt.instance.registerSingleton<UserPreferences>(prefs);

    loads = 0;
    vm = _ViewModel();
    when(() => vm.item).thenReturn(
      AggregatedItem(
        id: 'series-1',
        serverId: 'server-1',
        rawData: const {'Id': 'series-1', 'Name': 'Bluey', 'Type': 'Series'},
      ),
    );
    when(() => vm.seriesEpisodes).thenReturn(const []);
    when(() => vm.episodes).thenReturn(const []);
    when(() => vm.seriesEpisodesLoaded).thenReturn(false);
    when(() => vm.loadAllSeriesEpisodes()).thenAnswer((_) async => loads++);
  });

  tearDown(() => GetIt.instance.reset());

  Widget app(FocusNode node) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: MinimalistEpisodesSection(
        viewModel: vm,
        prefs: prefs,
        landscape: true,
        episodesFocusNode: node,
      ),
    ),
  );

  testWidgets('a failed load offers Retry, which asks again', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(app(node));
    await tester.pumpAndSettle();

    expect(loads, 1);
    expect(find.text("The episodes couldn't be loaded"), findsOneWidget);

    // Down from Play aims at the section's node, so it has to be the button.
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(loads, 2);
  });

  testWidgets('a load still on its way shows nothing yet', (tester) async {
    when(() => vm.seriesEpisodesLoaded).thenReturn(false);
    when(() => vm.loadAllSeriesEpisodes())
        .thenAnswer((_) => Future<void>.delayed(const Duration(seconds: 1)));
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(app(node));
    await tester.pump();

    expect(find.text("The episodes couldn't be loaded"), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}
