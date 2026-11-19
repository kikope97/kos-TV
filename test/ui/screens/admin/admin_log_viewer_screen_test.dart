import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/admin/logs/admin_log_viewer_screen.dart';
import 'package:server_core/server_core.dart';

class _MockMediaServerClient extends Mock implements MediaServerClient {}

/// Serves GET /System/Logs/Log, growing by one line per read like a log
/// the server is still writing.
class _FakeSystemApi extends Fake implements AdminSystemApi {
  final names = <String>[];
  String? content;

  /// When set, reads wait for it, like a slow download.
  Completer<void>? hold;

  @override
  Future<String> getLogFileContent(String name) async {
    names.add(name);
    final gate = hold;
    if (gate != null) await gate.future;
    return content ??
        List.generate(
          80 + names.length,
          (i) => '[12:00:00] [INF] line $i',
        ).join('\n');
  }
}

void main() {
  late _FakeSystemApi api;
  late AppLocalizations l10n;

  setUp(() async {
    api = _FakeSystemApi();
    final client = _MockMediaServerClient();
    when(() => client.adminSystemApi).thenReturn(api);
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<MediaServerClient>(client);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: AdminLogViewerScreen(fileName: 'log_20261002.log'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('watch refetches every 2 s and follows the end', (tester) async {
    await pump(tester);
    expect(api.names, ['log_20261002.log']);

    await tester.pump(const Duration(seconds: 3));
    expect(api.names, hasLength(1));

    await tester.tap(find.byTooltip(l10n.adminLogWatch));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(api.names, hasLength(2));
    expect(find.text('[12:00:00] [INF] line 81', findRichText: true),
        findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(api.names, hasLength(3));
    expect(find.text('[12:00:00] [INF] line 82', findRichText: true),
        findsOneWidget);

    await tester.tap(find.byTooltip(l10n.adminLogStopWatching));
    await tester.pump(const Duration(seconds: 4));
    expect(api.names, hasLength(3));
  });

  testWidgets('the level filters read Jellyfin\'s level tags', (tester) async {
    const info = '[15:08:12] [INF] [1] Main: Application path';
    const warn = '[15:08:13] [WRN] [1] App: Slow start';
    const error = '[15:13:20] [ERR] [7] PackageService: Failed';
    const trace = '\t*** Error Report ***';
    api.content = [info, warn, error, trace].join('\n');
    await pump(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'ERR'));
    await tester.pumpAndSettle();
    expect(find.text(error, findRichText: true), findsOneWidget);
    expect(find.text(info, findRichText: true), findsNothing);
    expect(find.text(trace, findRichText: true), findsNothing);
    // Kos TV: the number is the line's in the file, not in the filtered list.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'WRN'));
    await tester.pumpAndSettle();
    expect(find.text(warn, findRichText: true), findsOneWidget);
    expect(find.text(error, findRichText: true), findsNothing);
  });

  // Kos TV: a read slower than the tick isn't joined by another one.
  testWidgets('watch never asks again while a read is on its way', (
    tester,
  ) async {
    await pump(tester);
    final gate = api.hold = Completer<void>();

    await tester.tap(find.byTooltip(l10n.adminLogWatch));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(api.names, hasLength(2));

    api.hold = null;
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(api.names, hasLength(3));

    await tester.tap(find.byTooltip(l10n.adminLogStopWatching));
    await tester.pump();
  });
}
