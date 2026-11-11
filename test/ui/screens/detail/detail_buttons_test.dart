import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/models/user.dart';
import 'package:moonfin/auth/repositories/user_repository.dart';
import 'package:moonfin/data/services/incomplete_recordings_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/screens/detail/detail_buttons.dart';
import 'package:moonfin/util/download_utils.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IncompleteRecordings extends Mock
    implements IncompleteRecordingsService {}

/// Seeds the arrangement through the layout itself, so the test follows
/// whichever per-device preference this platform reads.
Future<UserPreferences> _prefs({String? order}) async {
  SharedPreferences.setMockInitialValues({});
  final store = PreferenceStore();
  await store.init();
  final prefs = UserPreferences(store);
  if (order != null) {
    await prefs.set(detailButtonLayout.orderPreference, order);
  }
  return prefs;
}

List<String> _arrangedIds(UserPreferences prefs) => detailButtonLayout
    .ordered(DetailButton.values, (b) => b.id, prefs)
    .map((b) => b.id)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
    PlatformDetection.setTvMode(false);
    debugDefaultTargetPlatformOverride = null;
  });

  group('DetailButton', () {
    test('every id is distinct, since the id is what gets stored', () {
      final ids = DetailButton.values.map((b) => b.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('a button missing from the stored order follows the one it was '
        'declared after', () async {
      final prefs = await _prefs(order: 'goToSeries,admin');
      final ids = _arrangedIds(prefs);

      // Declared between goToSeries and admin, so it inherits goToSeries'
      // place rather than jumping to either end.
      expect(ids.sublist(ids.indexOf('goToSeries')), [
        'goToSeries',
        'keepAsComplete',
        'admin',
      ]);
    });

    test('Android TV offers offline controls but not casting', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      PlatformDetection.setTvMode(true);

      expect(DetailButton.download.isOffered, isTrue);
      expect(DetailButton.deleteFiles.isOffered, isTrue);
      expect(DetailButton.cast.isOffered, isFalse);
    });

    test('watchWithGroup is hidden from offered buttons when SyncPlay is not enabled', () {
      expect(DetailButton.watchWithGroup.isOffered, isFalse);
    });

    test('Keep as Complete is only offered to someone who can manage Live TV', () {
      final incomplete = _IncompleteRecordings();
      when(() => incomplete.supported).thenReturn(true);
      final users = UserRepository();
      GetIt.instance
        ..registerSingleton<IncompleteRecordingsService>(incomplete)
        ..registerSingleton<UserRepository>(users);
      addTearDown(GetIt.instance.reset);

      PrivateUser user({required bool canManageLiveTv}) => PrivateUser(
        id: 'u1',
        name: 'viewer',
        serverId: 's1',
        accessToken: 'token',
        lastUsed: DateTime(2026),
        canManageLiveTv: canManageLiveTv,
      );

      users.setCurrentUser(user(canManageLiveTv: false));
      expect(DetailButton.keepAsComplete.isOffered, isFalse);

      users.setCurrentUser(user(canManageLiveTv: true));
      expect(DetailButton.keepAsComplete.isOffered, isTrue);
    });
  });

  group('showsTvDownloadActions', () {
    test('TV hides the download actions until the user opts in', () async {
      PlatformDetection.setTvMode(true);
      final prefs = await _prefs();

      expect(showsTvDownloadActions(prefs), isFalse);

      await prefs.set(UserPreferences.tvOfflineDownloads, true);
      expect(showsTvDownloadActions(prefs), isTrue);
    });

    test('non-TV platforms offer downloads unconditionally', () async {
      PlatformDetection.setTvMode(false);
      final prefs = await _prefs();
      expect(showsTvDownloadActions(prefs), isTrue);
    });

    test('a saved button order does not opt TV in on its own', () async {
      PlatformDetection.setTvMode(true);
      // Moving any row writes the whole arrangement back, download included,
      // so the order says nothing about whether downloads were asked for.
      final prefs = await _prefs(order: 'play,download,subtitles');

      expect(showsTvDownloadActions(prefs), isFalse);
    });
  });
}
