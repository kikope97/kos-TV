import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/lyrics.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/music/kostv_now_playing_screen.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:playback_core/playback_core.dart';

class _Manager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  final seeks = <Duration>[];

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    state.setPosition(position);
  }
}

LyricsData _lyrics({bool synced = true}) => LyricsData(
  isSynced: synced,
  lines: [
    for (var i = 0; i < 60; i++)
      LyricLine(
        start: Duration(seconds: i * 3),
        text: 'Línea $i',
      ),
  ],
);

const _height = 600.0;

/// Kos TV: the synced lyrics follow the song however far down it is, stop
/// following while moved by hand and come back a few seconds later (or at
/// once with «Volver a la línea actual»), and a line picked plays from there.
void main() {
  late _Manager manager;

  setUp(() {
    manager = _Manager();
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    await GetIt.instance.reset();
  });

  Future<void> show(WidgetTester tester, {bool synced = true}) async {
    tester.view.physicalSize = const Size(800, _height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: KostvLyricsPanel(lyrics: _lyrics(synced: synced)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> sing(WidgetTester tester, int line) async {
    manager.state.setPosition(Duration(seconds: line * 3, milliseconds: 500));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Where [line] is, as a share of the panel's height from its top.
  double placeOf(WidgetTester tester, int line) =>
      tester.getCenter(find.text('Línea $line')).dy / _height;

  final back = find.text('Volver a la línea actual');

  Future<void> scrollByHand(WidgetTester tester) async {
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 400),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('the line sounding stays in sight, far past the first screen', (
    tester,
  ) async {
    await show(tester);
    for (final line in [5, 20, 41, 50]) {
      await sing(tester, line);
      expect(
        placeOf(tester, line),
        inInclusiveRange(0.25, 0.45),
        reason: 'line $line about a third of the way down',
      );
    }
    // The last one, with the lyrics at their end, still in sight.
    await sing(tester, 59);
    expect(placeOf(tester, 59), inInclusiveRange(0.25, 0.85));
    await done(tester);
  });

  testWidgets('moved by hand, it waits, then follows again', (tester) async {
    await show(tester);
    await sing(tester, 30);
    await scrollByHand(tester);
    expect(back, findsOneWidget);
    final where = tester.getCenter(find.text('Línea 30')).dy;

    // The song goes on: the page stays where the person left it.
    await sing(tester, 31);
    expect(tester.getCenter(find.text('Línea 30')).dy, where);

    // A few seconds without touching it: back to the line sounding.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(back, findsNothing);
    expect(placeOf(tester, 31), inInclusiveRange(0.25, 0.45));
    await done(tester);
  });

  testWidgets('the mouse wheel moves them by hand too', (tester) async {
    await show(tester);
    await sing(tester, 30);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(const Offset(400, 300));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
    await tester.pumpAndSettle();
    expect(back, findsOneWidget);
    final where = tester.getCenter(find.text('Línea 30')).dy;
    await sing(tester, 31);
    expect(tester.getCenter(find.text('Línea 30')).dy, where);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(placeOf(tester, 31), inInclusiveRange(0.25, 0.45));
    await done(tester);
  });

  testWidgets('«Volver a la línea actual» goes back at once', (tester) async {
    await show(tester);
    await sing(tester, 25);
    await scrollByHand(tester);
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(back, findsNothing);
    expect(placeOf(tester, 25), inInclusiveRange(0.25, 0.45));
    await done(tester);
  });

  testWidgets('a line picked plays from it and the page follows from there', (
    tester,
  ) async {
    await show(tester);
    await scrollByHand(tester);
    await tester.tap(find.text('Línea 6'));
    await tester.pumpAndSettle();
    expect(manager.seeks, [const Duration(seconds: 18)]);
    expect(back, findsNothing);
    expect(placeOf(tester, 6), inInclusiveRange(0.25, 0.45));
    await sing(tester, 12);
    expect(placeOf(tester, 12), inInclusiveRange(0.25, 0.45));
    await done(tester);
  });

  testWidgets('on the TV, the remote along the lines waits too, then the '
      'remote goes along with the song', (tester) async {
    PlatformDetection.setTvMode(true);
    await show(tester);
    await sing(tester, 2);
    Focus.of(tester.element(find.text('Línea 3'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus!;
    expect(focused.debugLabel, 'LyricsLine4');
    // No button to press on the TV: it comes back by itself.
    expect(back, findsNothing);

    await sing(tester, 20);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'LyricsLine4');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'LyricsLine20');
    expect(placeOf(tester, 20), inInclusiveRange(0.25, 0.45));

    // OK on a line plays from it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(manager.seeks.last, const Duration(seconds: 63));
    await done(tester);
  });

  testWidgets('unsynced lyrics just stay where they are', (tester) async {
    await show(tester, synced: false);
    final top = tester.getCenter(find.text('Línea 0')).dy;
    manager.state.setPosition(const Duration(seconds: 90));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('Línea 0')).dy, top);
    await scrollByHand(tester);
    expect(back, findsNothing);
    await done(tester);
  });
}
