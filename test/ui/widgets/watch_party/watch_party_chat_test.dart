import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/watch_party/watch_party_player_overlay.dart';
import 'package:moonfin/watch_party/silo_watch_party_manager.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:server_silo/server_silo.dart' show SiloRoom;

class _NoPlayback extends Fake implements PlaybackManager {}

class _Client extends Fake implements MediaServerClient {
  @override
  String get baseUrl => 'https://jellyfin.example';
  @override
  String? get userId => 'adult';
}

void main() {
  setUp(() {
    GetIt.instance.registerSingleton<SiloWatchPartyManager>(
      SiloWatchPartyManager(_NoPlayback())..debugEnterRoom(
        SiloRoom.fromJson({'room_id': 'r1', 'chat_enabled': true}),
        _Client(),
      ),
    );
  });

  tearDown(() => GetIt.instance.reset());

  Future<FocusNode> typeAndSend(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: WatchPartyChatView()),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final field = FocusManager.instance.primaryFocus!;
    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    return field;
  }

  // Kos TV: on a phone or a TV, Done on the on-screen keyboard sends and
  // closes it, so it doesn't stay over the video.
  testWidgets('Done on a phone or TV lets go of the field', (tester) async {
    final field = await typeAndSend(tester);
    expect(field.hasFocus, isFalse);
  });

  // With a real keyboard, Enter sends and the next message can be typed
  // straight away.
  testWidgets('Enter on a desktop keeps the field focused', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final field = await typeAndSend(tester);
      expect(field.hasFocus, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
