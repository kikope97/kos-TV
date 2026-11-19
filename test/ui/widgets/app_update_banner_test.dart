import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/app_update_service.dart';
import 'package:moonfin/ui/widgets/app_update_banner.dart';

void main() {
  final update = DesktopUpdateInfo(
    version: '2.3.3',
    downloadUri: Uri.parse('https://example.invalid/KosTV_AndroidTV.apk'),
    releaseNotesUrl: 'https://example.invalid/notes',
  );

  const none = DesktopUpdateCheckResult(
    status: DesktopUpdateCheckStatus.upToDate,
  );
  const failed = DesktopUpdateCheckResult(
    status: DesktopUpdateCheckStatus.checkFailed,
  );
  final found = DesktopUpdateCheckResult(
    status: DesktopUpdateCheckStatus.updateAvailable,
    update: update,
  );

  late ValueNotifier<bool> watching;
  late List<String> offered;
  late int checks;

  setUp(() {
    watching = ValueNotifier(false);
    offered = [];
    checks = 0;
  });

  tearDown(() => watching.dispose());

  Widget banner(Future<DesktopUpdateCheckResult> Function() check) =>
      MaterialApp(
        home: Scaffold(
          body: AppUpdateBanner(
            checkForUpdate: () {
              checks++;
              return check();
            },
            showUpdate: (update) async => offered.add(update.version),
            isWatching: () => watching.value,
            isOpening: () => false,
            routeChanges: watching,
            retryAfterFailure: const Duration(minutes: 5),
          ),
        ),
      );

  testWidgets('offers an update found', (tester) async {
    await tester.pumpWidget(banner(() async => found));
    await tester.pump();

    expect(offered, ['2.3.3']);
  });

  testWidgets('offers nothing when there is no update', (tester) async {
    await tester.pumpWidget(banner(() async => none));
    await tester.pump();

    expect(offered, isEmpty);
  });

  testWidgets('a check that throws offers nothing', (tester) async {
    await tester.pumpWidget(banner(() async => throw Exception('offline')));
    await tester.pump();

    expect(offered, isEmpty);
  });

  testWidgets('waits for the player to close before checking', (tester) async {
    watching.value = true;
    await tester.pumpWidget(banner(() async => found));
    await tester.pump();
    expect(checks, 0);

    watching.value = false;
    await tester.pump(const Duration(seconds: 3));
    expect(offered, ['2.3.3']);
  });

  // Kos TV: the answer can take a while; Play pressed in the meantime keeps
  // the dialog off the video, and it comes once the player closes.
  testWidgets('holds an update found while playback started', (tester) async {
    await tester.pumpWidget(
      banner(() async {
        watching.value = true;
        return found;
      }),
    );
    await tester.pump();
    expect(checks, 1);
    expect(offered, isEmpty);

    watching.value = false;
    await tester.pump(const Duration(seconds: 3));
    expect(offered, ['2.3.3']);
    // Offered from what it held, not asked for again.
    expect(checks, 1);
  });

  // Kos TV: a check that got no answer (the wifi still coming back) is tried
  // again in a few minutes, not at the next resume.
  testWidgets('tries again soon after a check that got no answer', (
    tester,
  ) async {
    var answers = [failed, found];
    await tester.pumpWidget(banner(() async => answers.removeAt(0)));
    await tester.pump();
    expect(offered, isEmpty);

    await tester.pump(const Duration(minutes: 5));
    expect(checks, 2);
    expect(offered, ['2.3.3']);
    answers = [];
  });

  testWidgets('doesn\'t try again after a check that was answered', (
    tester,
  ) async {
    await tester.pumpWidget(banner(() async => none));
    await tester.pump();
    await tester.pump(const Duration(minutes: 10));
    expect(checks, 1);
  });
}
