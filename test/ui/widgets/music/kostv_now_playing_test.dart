import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing_capsule.dart';
import 'package:playback_core/playback_core.dart';

class _Manager extends Fake implements PlaybackManager {
  @override
  final PlayerState state = PlayerState();

  @override
  final QueueService queueService = QueueService();

  @override
  bool get isOfflinePlayback => false;

  @override
  Map<String, dynamic>? get currentOfflineMetadata => null;

  int pauses = 0;

  @override
  Future<void> pause() async => pauses++;
}

AggregatedItem _item(String id, String type) => AggregatedItem(
  id: id,
  serverId: 'casa',
  rawData: {
    'Id': id,
    'Name': 'Verano',
    'Type': type,
    if (type == 'Audio') 'MediaType': 'Audio',
    'Artists': ['Lola Brisa'],
  },
);

/// Kos TV: the music sounding in the app, for the floating player.
void main() {
  late _Manager manager;

  setUp(() {
    manager = _Manager();
    GetIt.instance.registerSingleton<PlaybackManager>(manager);
  });

  tearDown(() => GetIt.instance.reset());

  group('what sounds', () {
    test('a song is the music sounding; a film is not', () {
      final music = KostvNowPlaying.instance;
      manager.queueService.setQueue([_item('s1', 'Audio')]);
      expect(music.item?.id, 's1');
      expect(music.artistOf(music.item!), 'Lola Brisa');
      manager.queueService.setQueue([_item('m1', 'Movie')]);
      expect(music.item, isNull);
      manager.queueService.clear();
      expect(music.item, isNull);
    });

    test('the sleep timer pauses the music when it is up', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance;
        music.setSleep(const Duration(minutes: 15));
        expect(music.sleepAt, isNotNull);
        async.elapse(const Duration(minutes: 14));
        expect(manager.pauses, 0);
        async.elapse(const Duration(minutes: 2));
        expect(manager.pauses, 1);
        expect(music.sleepAt, isNull);
      });
    });

    test('a timer taken off never pauses it', () {
      fakeAsync((async) {
        final music = KostvNowPlaying.instance;
        music.setSleep(const Duration(minutes: 15));
        music.setSleep(null);
        async.elapse(const Duration(hours: 1));
        expect(manager.pauses, 0);
      });
    });
  });

  group('where the floating player steps aside', () {
    testWidgets('under a dialog, and where the bottom bar has its own', (
      tester,
    ) async {
      final routes = KostvNowPlayingRouteObserver.instance;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [routes],
          home: const SizedBox(),
        ),
      );
      expect(routes.popupOnTop, isFalse);
      expect(routes.bottomBarOnTop, isFalse);

      unawaited(
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => const Text('¿Seguro?'),
        ),
      );
      await tester.pumpAndSettle();
      expect(routes.popupOnTop, isTrue);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(routes.popupOnTop, isFalse);

      final page = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      unawaited(navigator.currentState!.push(page));
      await tester.pumpAndSettle();
      routes.setBottomBar(page, true);
      expect(routes.bottomBarOnTop, isTrue);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(routes.bottomBarOnTop, isFalse);
    });
  });

  testWidgets('the bars dance while it plays and rest while paused', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Center(child: KostvEqualizerBars(playing: true)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(
      const Center(child: KostvEqualizerBars(playing: false)),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
