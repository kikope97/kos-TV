import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/reader_settings.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/book/discover/book_discovery_models.dart';
import 'package:moonfin/ui/widgets/reader/reader_chrome_bar.dart';
import 'package:moonfin/ui/widgets/reader/reader_contents_hub.dart';
import 'package:moonfin/ui/widgets/reader/reader_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kos TV: the reader's chrome, contents and settings read in Spanish and
// still fit a phone's width with the longer labels.
void main() {
  const colors = ReaderThemeColors(
    background: Color(0xFFF4ECD8),
    foreground: Color(0xFF3E3023),
    link: Color(0xFF6B4E2A),
    isDark: false,
  );

  Future<BuildContext> pumpPhone(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              context = ctx;
              return child;
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('top bar tooltips are in Spanish', (tester) async {
    await pumpPhone(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: ReaderTopBar(
          title: 'Platero y yo',
          subtitle: 'Capítulo 4',
          pageColors: colors,
          onBack: () {},
          onContents: () {},
          onSearch: () {},
          onSettings: () {},
          onBookmark: () {},
          hasBookmarks: false,
        ),
      ),
    );

    expect(find.byTooltip('Atrás'), findsOneWidget);
    expect(find.byTooltip('Índice'), findsOneWidget);
    expect(find.byTooltip('Buscar'), findsOneWidget);
    expect(find.byTooltip('Marcador'), findsOneWidget);
    expect(find.byTooltip('Ajustes de lectura'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _android);

  testWidgets('contents hub is in Spanish and fits a phone', (tester) async {
    final context = await pumpPhone(tester, const SizedBox.shrink());
    final l10n = AppLocalizations.of(context);
    showReaderContentsHub(
      context: context,
      accent: const Color(0xFF0A84FF),
      pageColors: colors,
      chapters: const [],
      bookmarks: const [],
      highlights: const [],
      isPlayed: false,
      onToggleRead: () {},
      onReload: () {},
      progressLabel: '34%',
      // The longest label the reader passes here.
      extraActionLabel: l10n.invertColorsFixedLayout,
      extraActionIcon: Icons.invert_colors,
      onExtraAction: () {},
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Capítulos'), findsOneWidget);
    expect(find.text('Marcadores'), findsOneWidget);
    expect(find.text('Subrayados'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);
    expect(find.text('No hay índice disponible'), findsOneWidget);
    expect(find.text('Marcar como leído'), findsOneWidget);
    expect(find.text('Recargar'), findsOneWidget);
    expect(find.text('Invertir colores (diseño fijo)'), findsOneWidget);
    expect(find.text('34%'), findsOneWidget);

    await tester.tap(find.text('Subrayados'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no hay subrayados'), findsOneWidget);
    await tester.tap(find.text('Marcadores'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no hay marcadores'), findsOneWidget);
  }, variant: _android);

  testWidgets('settings sheet is in Spanish and fits a phone', (tester) async {
    final context = await pumpPhone(tester, const SizedBox.shrink());
    showReaderSettingsSheet(
      context: context,
      settings: const ReaderSettings(),
      accent: const Color(0xFF0A84FF),
      pageColors: colors,
      onChanged: (_) {},
      showScroll: true,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in [
      'Original',
      'Papel',
      'Suave',
      'Calma',
      'Noche',
      'Sistema',
      'Con serifa',
      'Sin serifa',
      'Mono',
      'Justificar',
      'Negrita',
      'Desplazar',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  }, variant: _android);

  test('a discovered book with no author reads in Spanish', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = PreferenceStore();
    await store.init();
    final prefs = UserPreferences(store);
    await prefs.set(UserPreferences.languageOverride, 'es');
    GetIt.instance.registerSingleton<UserPreferences>(prefs);
    addTearDown(GetIt.instance.reset);

    final book = DiscoverBook.fromOpenLibraryMap({
      'key': '/works/OL1W',
      'title': 'Sin firma',
    });
    final audiobook = LibrivoxBook.fromMap({'id': '1', 'title': 'Sin firma'});

    expect(book.author, 'Autor desconocido');
    expect(audiobook.authorName, 'Autor desconocido');
  });
}

/// A phone: the bottom sheets, not the desktop side panel.
final _android = TargetPlatformVariant.only(TargetPlatform.android);
