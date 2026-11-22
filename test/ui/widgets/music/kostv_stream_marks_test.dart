import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/playback/kostv_stream_artist_line.dart';
import 'package:moonfin/ui/screens/music/kostv_stream_widgets.dart';
import 'package:moonfin/ui/widgets/music/kostv_music_menu.dart';
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

Widget _app(Widget child, {Locale locale = const Locale('es')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

/// Kos TV: wherever a song shows or sounds, whether it is at home: the small
/// cloud of one that isn't (the floating player, the menus) and «· en
/// streaming» where only text fits (the notification, the browser).
void main() {
  group('the floating player', () {
    for (final big in [false, true]) {
      testWidgets('${big ? 'on the TV' : 'on the phone and the web'}: the '
          'cloud after the artist of one that isn\'t at home', (tester) async {
        await tester.pumpWidget(
          _app(
            KostvCapsuleTitles(
              item: _away(),
              artist: 'Los Faroleros',
              big: big,
            ),
          ),
        );
        expect(find.text('Los Faroleros'), findsOneWidget);
        expect(find.byType(KostvStreamMark), findsOneWidget);
        expect(find.byTooltip('No está en casa'), findsOneWidget);
        final artist = tester.getRect(find.text('Los Faroleros'));
        final cloud = tester.getRect(find.byType(KostvStreamMark));
        expect(cloud.left, greaterThanOrEqualTo(artist.right));
        expect(cloud.center.dy, closeTo(artist.center.dy, 4));
      });
    }

    testWidgets('a song at home, as before: no cloud', (tester) async {
      await tester.pumpWidget(
        _app(const KostvCapsuleTitles(item: _home, artist: 'Lola Brisa')),
      );
      expect(find.text('Lola Brisa'), findsOneWidget);
      expect(find.byType(KostvStreamMark), findsNothing);
    });

    testWidgets('a long artist is cut short and the cloud still shows', (
      tester,
    ) async {
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
      expect(find.byType(KostvStreamMark), findsOneWidget);
      final cloud = tester.getRect(find.byType(KostvStreamMark));
      expect(
        cloud.right,
        lessThanOrEqualTo(
          tester.getRect(find.byType(KostvCapsuleTitles)).right + 0.5,
        ),
      );
    });
  });

  testWidgets('a menu with a mark after its subtitle', (tester) async {
    await tester.pumpWidget(
      _app(
        const KostvMusicMenu<int>(
          title: 'Farolillo',
          subtitle: 'Los Faroleros · No está en casa',
          subtitleMark: KostvStreamMark(),
          entries: [KostvMenuEntry(1, Icons.radio_rounded, 'Crear emisora')],
        ),
      ),
    );
    expect(find.text('Los Faroleros · No está en casa'), findsOneWidget);
    expect(find.byType(KostvStreamMark), findsOneWidget);
    await tester.pumpWidget(
      _app(
        const KostvMusicMenu<int>(
          title: 'Verano',
          subtitle: 'Lola Brisa',
          entries: [KostvMenuEntry(1, Icons.radio_rounded, 'Crear emisora')],
        ),
      ),
    );
    expect(find.byType(KostvStreamMark), findsNothing);
  });

  group('the line of the system\'s media controls', () {
    final es = lookupAppLocalizations(const Locale('es'));
    final en = lookupAppLocalizations(const Locale('en'));

    test('one that isn\'t at home: «· en streaming» after its artist', () {
      expect(
        kostvStreamArtistLine(_away(), 'Los Faroleros', es),
        'Los Faroleros · en streaming',
      );
      expect(
        kostvStreamArtistLine(_away(), 'Los Faroleros', en),
        'Los Faroleros · streaming',
      );
    });

    test('with no artist, just that it is in streaming', () {
      expect(
        kostvStreamArtistLine(_away(artist: null), null, es),
        'En streaming',
      );
      expect(kostvStreamArtistLine(_away(artist: null), '  ', en), 'Streaming');
    });

    test('one at home, unchanged', () {
      expect(kostvStreamArtistLine(_home, 'Lola Brisa', es), 'Lola Brisa');
      expect(kostvStreamArtistLine(_home, null, es), isNull);
    });
  });
}
