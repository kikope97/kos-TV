import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/database/offline_database.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/repositories/offline_repository.dart';
import 'package:moonfin/data/services/download_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/downloads/widgets/saved_media_actions.dart';

DownloadedItem _row(
  String id, {
  String type = 'Movie',
  String quality = 'original',
}) => DownloadedItem(
  itemId: id,
  serverId: 's1',
  type: type,
  name: id,
  localFilePath: '/tmp/$id.mkv',
  metadataJson: '{"Name":"$id","Type":"$type"}',
  downloadStatus: 2,
  downloadProgress: 1.0,
  fileSizeBytes: 1000,
  playbackPositionTicks: 0,
  progressSynced: true,
  qualityPreset: quality,
  downloadSource: 'manual',
  indexNumber: 3,
  parentIndexNumber: 1,
);

class _FakeRepository extends Fake implements OfflineRepository {
  @override
  Future<DownloadedItem?> getItem(String itemId) async => _row(itemId);
}

/// Fails to delete the files of the ids in [failing].
class _FakeDownloadService extends ChangeNotifier implements DownloadService {
  _FakeDownloadService(this.failing);

  final Set<String> failing;

  @override
  Future<bool> deleteDownloadedFiles(AggregatedItem item) async =>
      !failing.contains(item.id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppLocalizations en;
  late AppLocalizations es;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    es = await AppLocalizations.delegate.load(const Locale('es'));
  });

  tearDown(() => GetIt.instance.reset());

  // Kos TV: the type and the quality read in the app's language rather than
  // as the server's type name and the preset's stored name.
  test('the line under a saved item is in the app\'s language', () {
    expect(savedMediaSubtitle(es, _row('m1')), 'Película');
    expect(savedMediaSubtitle(es, _row('a1', type: 'AudioBook')), 'Audiolibro');
    expect(
      savedMediaSubtitle(
        es,
        _row('e1', type: 'Episode', quality: 'medium720p'),
        insideShow: true,
      ),
      contains('720p'),
    );
    expect(
      savedMediaSubtitle(
        es,
        _row('e1', type: 'Episode', quality: 'medium720p'),
        insideShow: true,
      ),
      isNot(contains('medium720p')),
    );
    expect(savedMediaSubtitle(en, _row('m1')), 'Movie');
  });

  testWidgets('a delete that fails says so', (tester) async {
    GetIt.instance
      ..registerSingleton<OfflineRepository>(_FakeRepository())
      ..registerSingleton<DownloadService>(_FakeDownloadService({'m2'}));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => deleteSavedItems(
                context,
                title: 'Remove them?',
                message: 'Two films',
                itemIds: const ['m1', 'm2'],
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.delete));
    await tester.pumpAndSettle();

    expect(find.text(en.failedToDeleteFiles), findsOneWidget);
  });

  // Kos TV: Wi-Fi only is about mobile data, so a wired TV still downloads.
  test('Wi-Fi only lets Wi-Fi and Ethernet through, not mobile data', () {
    expect(unmeteredConnection([ConnectivityResult.wifi]), isTrue);
    expect(unmeteredConnection([ConnectivityResult.ethernet]), isTrue);
    expect(unmeteredConnection([ConnectivityResult.mobile]), isFalse);
    expect(unmeteredConnection([ConnectivityResult.none]), isFalse);
  });
}
