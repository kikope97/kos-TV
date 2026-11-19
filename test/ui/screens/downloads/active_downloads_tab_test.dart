import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/download_source.dart';
import 'package:moonfin/data/services/download_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/downloads/widgets/active_downloads_tab.dart';
import 'package:moonfin/util/platform_detection.dart';

class _FakeDownloadService extends ChangeNotifier implements DownloadService {
  final cancelled = <String>[];
  var cancelledAll = false;

  @override
  Map<String, DownloadProgress> get activeDownloads => const {
    'm1': DownloadProgress(itemId: 'm1', fileName: 'A Film', progress: 0.4),
  };

  @override
  bool get isBatchDownloading => false;

  @override
  DownloadSource sourceOf(String itemId) => DownloadSource.manual;

  @override
  void cancelDownload(String itemId) => cancelled.add(itemId);

  @override
  void cancelAll() => cancelledAll = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Kos TV: stopping a transfer asks first where a single press could do it
/// by accident: OK on a remote, and Cancel for all of them.
void main() {
  late _FakeDownloadService service;
  late AppLocalizations l10n;

  setUp(() async {
    service = _FakeDownloadService();
    GetIt.instance.registerSingleton<DownloadService>(service);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    await GetIt.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ActiveDownloadsTab()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('on TV, OK on a download asks before cancelling it', (
    tester,
  ) async {
    PlatformDetection.setTvMode(true);
    await pump(tester);

    await tester.tap(find.text('A Film'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.kostvCancelDownloadTitle), findsOneWidget);
    expect(service.cancelled, isEmpty);

    // Keeping it is where focus starts.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(service.cancelled, isEmpty);

    await tester.tap(find.text('A Film'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.savedMediaCancelDownload));
    await tester.pumpAndSettle();
    expect(service.cancelled, ['m1']);
  });

  testWidgets('Cancel for every download asks first', (tester) async {
    await pump(tester);

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.kostvCancelAllDownloadsTitle), findsOneWidget);
    await tester.tap(find.text(l10n.kostvKeepDownloading));
    await tester.pumpAndSettle();
    expect(service.cancelledAll, isFalse);

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.kostvCancelAllDownloadsConfirm));
    await tester.pumpAndSettle();
    expect(service.cancelledAll, isTrue);
  });
}
