import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/music/kostv_stream_widgets.dart';
import 'package:moonfin/ui/widgets/music/kostv_now_playing_capsule.dart';

AggregatedItem _away({String? artist = 'Los Faroleros'}) => kostvStreamItem(
  deezerId: '9',
  title: 'Farolillo',
  serverId: 'casa',
  artist: artist,
  album: 'Verbena',
);

const _home = AggregatedItem(
  id: 'h1',
  serverId: 'casa',
  rawData: {
    'Id': 'h1',
    'Name': 'Verano',
    'Type': 'Audio',
    'MediaType': 'Audio',
    'Artists': ['Lola Brisa'],
  },
);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

/// Kos TV: the music design: everything looks the same whether it is at
/// home or sounds in streaming. The floating player shows no mark (only the
/// album's page and «Reproduciendo» say it); the system's media controls
/// are tested in `test/playback/audio_handler_engine_now_playing_test.dart`.
void main() {
  group('the floating player', () {
    for (final big in [false, true]) {
      testWidgets('${big ? 'on the TV' : 'on the phone and the web'}: the '
          'same for one that isn\'t at home as for one that is', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            KostvCapsuleTitles(
              item: _away(),
              artist: 'Los Faroleros',
              big: big,
            ),
          ),
        );
        expect(find.text('Farolillo'), findsOneWidget);
        expect(find.text('Los Faroleros'), findsOneWidget);
        expect(find.byIcon(Icons.cloud_outlined), findsNothing);
        expect(find.byTooltip('No está en casa'), findsNothing);
        expect(find.textContaining('streaming'), findsNothing);
        final away = tester.getRect(find.text('Los Faroleros'));
        await tester.pumpWidget(
          _app(
            KostvCapsuleTitles(item: _home, artist: 'Los Faroleros', big: big),
          ),
        );
        expect(tester.getRect(find.text('Los Faroleros')), away);
      });
    }

    testWidgets('a long artist is cut short, with no overflow', (tester) async {
      final long = 'Los Faroleros de la Verbena ' * 6;
      await tester.pumpWidget(
        _app(
          KostvCapsuleTitles(
            item: _away(artist: long),
            artist: long,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('«Reproduciendo»\'s line is calm: no cloud, the wave', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        KostvStreamPill(
          item: _away(),
          stop: (onTap, builder) =>
              Builder(builder: (context) => builder(context, false)),
        ),
      ),
    );
    expect(find.text('Suena en streaming · no está en casa'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsNothing);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    // Nothing for a song at home.
    await tester.pumpWidget(
      _app(
        KostvStreamPill(
          item: _home,
          stop: (onTap, builder) =>
              Builder(builder: (context) => builder(context, false)),
        ),
      ),
    );
    expect(find.text('Suena en streaming · no está en casa'), findsNothing);
  });
}
