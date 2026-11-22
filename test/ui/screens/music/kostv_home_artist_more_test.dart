import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/music/kostv_home_artist_view.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Images implements ImageApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => '';
}

class _Users extends Fake implements UserRepository {
  _Users({required this.admin});

  final bool admin;

  @override
  User? get currentUser => PrivateUser(
    id: 'u1',
    name: 'Ana',
    serverId: 'casa',
    accessToken: 'token',
    lastUsed: DateTime(2026),
    isAdministrator: admin,
  );
}

const _bio =
    'Lola Brisa empezó a cantar en las verbenas de su pueblo. Grabó su '
    'primer disco en 2009 y desde entonces no ha parado de girar por toda '
    'España. Su último trabajo, «Verano», la llevó por fin a los grandes '
    'festivales, donde se ganó al público con sus canciones de siempre y '
    'algunas nuevas que escribió en la carretera. Vive entre Cádiz y '
    'Madrid y dice que su próxima gira será la más larga.';

class _Vm extends Fake implements ItemDetailViewModel {
  @override
  AggregatedItem? get item => AggregatedItem(
    id: 'ar1',
    serverId: 'casa',
    rawData: const {
      'Id': 'ar1',
      'Name': 'Lola Brisa',
      'Type': 'MusicArtist',
      'Overview': _bio,
    },
  );

  @override
  ItemDetailState get state => ItemDetailState.ready;

  @override
  List<AggregatedItem> get tracks => const [];

  @override
  List<AggregatedItem> get albums => const [];

  @override
  List<AggregatedItem> get similar => const [];

  @override
  bool get tracksFailed => false;

  @override
  ImageApi get imageApi => _Images();
}

/// Kos TV: the home artist's «⋯»: what the generic page had that still
/// makes sense, compact (the whole biography, and an administrator's
/// controls).
void main() {
  tearDown(() async {
    PlatformDetection.setTvMode(false);
    await GetIt.instance.reset();
  });

  Future<void> open(WidgetTester tester, {required bool admin}) async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance
      ..registerSingleton<PreferenceStore>(store)
      ..registerSingleton<UserPreferences>(UserPreferences(store))
      ..registerSingleton<UserRepository>(_Users(admin: admin));
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: KostvHomeArtistView(viewModel: _Vm())),
      ),
    );
    await tester.pump();
  }

  testWidgets('«⋯» reads the whole biography; an administrator also has '
      'identify and the picture', (tester) async {
    await open(tester, admin: true);
    await tester.tap(find.byTooltip('Más'));
    await tester.pumpAndSettle();
    expect(find.text('Biografía'), findsOneWidget);
    expect(find.text('Identificar'), findsOneWidget);
    expect(find.text('Cambiar la carátula'), findsOneWidget);
    await tester.tap(find.text('Biografía'));
    await tester.pumpAndSettle();
    final whole = find.byWidgetPredicate(
      (w) => w is Text && w.data == _bio && w.maxLines == null,
    );
    expect(whole, findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(whole, findsNothing);
  });

  testWidgets('someone else: the biography, nothing of the administrator\'s', (
    tester,
  ) async {
    await open(tester, admin: false);
    await tester.tap(find.byTooltip('Más'));
    await tester.pumpAndSettle();
    expect(find.text('Biografía'), findsOneWidget);
    expect(find.text('Identificar'), findsNothing);
    expect(find.text('Cambiar la carátula'), findsNothing);
  });

  testWidgets('a tap on the three lines reads it whole', (tester) async {
    await open(tester, admin: false);
    await tester.tap(find.byKey(const ValueKey('kostv-artist-about')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == _bio && w.maxLines == null,
      ),
      findsOneWidget,
    );
  });
}
