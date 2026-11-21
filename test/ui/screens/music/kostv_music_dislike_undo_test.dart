import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music_dislikes.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/music/kostv_music_dislike.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:server_core/server_core.dart';
import 'package:server_jellyfin/server_jellyfin.dart';

/// The plugin keeping every «No me gusta».
class _Plugin implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('', 204);

  @override
  void close({bool force = false}) {}
}

/// The player's 👎 next to play/pause: [showDislike] false is a next song
/// that isn't at home, without one.
class _Row extends StatefulWidget {
  const _Row({super.key, required this.dislike, required this.play});

  final FocusNode dislike;
  final FocusNode play;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool showDislike = true;

  void setShown(bool shown) => setState(() => showDislike = shown);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Focus(
        focusNode: widget.play,
        child: const SizedBox(width: 40, height: 40),
      ),
      if (showDislike)
        Focus(
          focusNode: widget.dislike,
          child: const SizedBox(width: 40, height: 40),
        ),
    ],
  );
}

/// Kos TV: «Deshacer» of «No me gusta» on the TV gives the remote back to
/// where it was, or to play/pause when that went from the page meanwhile,
/// and never leaves a request pending for it.
void main() {
  late KostvMusicDislikesStore before;

  setUp(() {
    PlatformDetection.setTvMode(true);
    before = KostvMusicDislikesStore.instance;
    KostvMusicDislikesStore.instance = KostvMusicDislikesStore(
      KostvMusicPlugin(dio: Dio()..httpClientAdapter = _Plugin()),
    );
    GetIt.instance.registerSingleton<MediaServerClient>(
      JellyfinMediaServerClient(
          baseUrl: 'https://casa.example',
          deviceInfo: const DeviceInfo(
            id: 'device',
            name: 'Device',
            appName: 'kOS TV',
            appVersion: '1.0.0',
          ),
        )
        ..accessToken = 'token'
        ..userId = 'ana',
    );
  });

  tearDown(() async {
    PlatformDetection.setTvMode(false);
    KostvMusicDislikesStore.instance = before;
    await GetIt.instance.reset();
  });

  testWidgets('the 👎 gone meanwhile: to play/pause, with no jump back to it '
      'later', (tester) async {
    final dislike = FocusNode(debugLabel: 'dislike');
    final play = FocusNode(debugLabel: 'play');
    addTearDown(dislike.dispose);
    addTearDown(play.dispose);
    final row = GlobalKey<_RowState>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: _Row(key: row, dislike: dislike, play: play),
        ),
      ),
    );
    dislike.requestFocus();
    await tester.pump();
    final song = AggregatedItem(
      id: 's1',
      serverId: '',
      rawData: const {'Id': 's1', 'Name': 'Canción', 'Type': 'Audio'},
    );
    unawaited(
      kostvDislikeSong(tester.element(find.byType(_Row)), song, orElse: play),
    );
    // The page asks for a frame (in the player, its row changes).
    for (var i = 0; i < 4; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 50));
    }
    // The notice has the remote.
    expect(dislike.hasFocus, isFalse);
    // The next song isn't at home: no 👎.
    row.currentState!.setShown(false);
    await tester.pump();
    // The notice goes by itself.
    await tester.pump(kostvMusicDislikeUndoTime + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, play);
    // A song at home again: the 👎 is back and the remote stays put.
    row.currentState!.setShown(true);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, play);
  });

  testWidgets('the 👎 still there: back to it', (tester) async {
    final dislike = FocusNode(debugLabel: 'dislike');
    final play = FocusNode(debugLabel: 'play');
    addTearDown(dislike.dispose);
    addTearDown(play.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: _Row(dislike: dislike, play: play),
        ),
      ),
    );
    dislike.requestFocus();
    await tester.pump();
    unawaited(
      kostvDislikeSong(
        tester.element(find.byType(_Row)),
        AggregatedItem(
          id: 's1',
          serverId: '',
          rawData: const {'Id': 's1', 'Name': 'Canción', 'Type': 'Audio'},
        ),
        orElse: play,
      ),
    );
    // The page asks for a frame (in the player, its row changes).
    for (var i = 0; i < 4; i++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(dislike.hasFocus, isFalse);
    await tester.pump(kostvMusicDislikeUndoTime + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, dislike);
  });

  testWidgets('kostvFocusInTree: a node whose widget went away is not', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(Focus(focusNode: node, child: const SizedBox()));
    expect(kostvFocusInTree(node), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(node.context, isNotNull);
    expect(kostvFocusInTree(node), isFalse);
    expect(kostvFocusInTree(null), isFalse);
  });
}
