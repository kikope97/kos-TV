import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_music.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';

/// Kos TV: Music, as far as it can be tried without a server.
void main() {
  AggregatedItem song(
    String id,
    String name, {
    String artist = 'Lola Brisa',
    String artistId = 'a1',
    List<String> genres = const ['Latin'],
    int plays = 1,
  }) => AggregatedItem(
    id: id,
    serverId: 'casa',
    rawData: {
      'Id': id,
      'Name': name,
      'Artists': [artist],
      'AlbumArtist': artist,
      'AlbumArtists': [
        {'Id': artistId, 'Name': artist},
      ],
      'Genres': genres,
      'UserData': {'PlayCount': plays},
    },
  );

  group('what the person listens to', () {
    test('their artists and genres go by how many times they played them', () {
      final taste = KostvMusicTaste.of([
        song('1', 'Verano', plays: 3),
        song(
          '2',
          'Fuego',
          artist: 'Clara Vega',
          artistId: 'a2',
          genres: ['Pop'],
          plays: 10,
        ),
        song('3', 'Noche', plays: 4),
      ]);
      expect(taste.artists.map((a) => a.name), ['Clara Vega', 'Lola Brisa']);
      expect(taste.genres, ['Pop', 'Latin']);
      expect(taste.chartGenre, 'pop');
    });

    test('the charts\' genre for the names the files carry', () {
      expect(kostvChartGenreOf('Reggaeton'), 'latino');
      expect(kostvChartGenreOf('Latin Pop'), 'latino');
      expect(kostvChartGenreOf('Hip-Hop/Rap'), 'hiphop');
      expect(kostvChartGenreOf('Electronic'), 'electronica');
      expect(kostvChartGenreOf('Indie Rock'), 'alternativa');
      expect(kostvChartGenreOf('Banda sonora'), 'bandas-sonoras');
      expect(kostvChartGenreOf('Clásica'), isNull);
    });
  });

  group('a chart\'s song at home', () {
    test('found by its title, without what is in brackets, and its artist', () {
      final found = [
        song('x', 'Verano', artist: 'Otra'),
        song('y', 'Verano (Remastered)', artist: 'Lola Brisa'),
      ];
      expect(
        kostvBestSong(found, 'Verano', 'Lola Brisa, Sal y Limón')?.id,
        'y',
      );
      // Same name, someone else's: not that one.
      expect(kostvBestSong([found.first], 'Verano', 'Lola Brisa'), isNull);
      expect(
        kostvMusicSearchable('BbY WOW (feat. Judeline) - Remix'),
        'BbY WOW',
      );
    });
  });

  group('the requests service\'s music', () {
    test('a chart of songs, each with the album to ask for', () {
      final page = StremfinChartPage.fromJson({
        'id': 'top-songs',
        'name': 'Top España · Canciones',
        'kind': 'songs',
        'measure': 'played',
        'items': [
          {
            'rank': 1,
            'title': 'Verano',
            'artist': 'Lola Brisa',
            'cover': 'https://img.example/c.jpg',
            'in_jellyfin': false,
            'album': {
              'type': 'music',
              'deezer_id': 302127,
              'title': 'Brisa',
              'kind': 'single',
              'library': {'in_jellyfin': false},
              'request': null,
              'can_request': true,
            },
          },
        ],
      })!;
      expect(page.chart.songs, isTrue);
      expect(page.chart.played, isTrue);
      final first = page.songs.single;
      expect(first.rank, 1);
      expect(first.album!.deezerId, '302127');
      expect(first.album!.kind, StremfinAlbumKind.single);
      expect(first.album!.canRequest, isTrue);
    });

    test(
      'a Deezer song knows where it sits, but brings no album to ask for',
      () {
        final found = StremfinMusicSearch.fromJson({
          'artists': [
            {
              'deezer_id': '27',
              'name': 'Daft Punk',
              'picture': 'https://p/x.jpg',
            },
          ],
          'songs': [
            {
              'deezer_id': '3135556',
              'title': 'One More Time',
              'artist': 'Daft Punk',
              'album': {
                'deezer_id': '302127',
                'title': 'Discovery',
                'cover': 'https://c/x.jpg',
              },
              'in_jellyfin': true,
              'in_album': 'Discovery',
            },
          ],
          'items': [
            {
              'title': 'Discovery',
              'deezer_id': '302127',
              'library': {'in_jellyfin': true},
            },
          ],
        });
        expect(found.artists.single.name, 'Daft Punk');
        final one = found.songs.single;
        expect(one.album, isNull);
        expect(one.albumDeezerId, '302127');
        expect(one.cover, 'https://c/x.jpg');
        expect(one.inJellyfin, isTrue);
        expect(found.albums.single.inJellyfin, isTrue);
      },
    );

    test('a single\'s page says which album to ask for instead', () {
      final detail = StremfinAlbumDetail.fromJson({
        'deezer_id': '31',
        'title': 'One More Time',
        'kind': 'single',
        'songs': [
          {'position': 1, 'title': 'One More Time', 'duration': 320},
        ],
        'album_instead': {
          'deezer_id': '302127',
          'title': 'Discovery',
          'contains': 'One More Time',
        },
      })!;
      expect(detail.album.kind, StremfinAlbumKind.single);
      expect(detail.albumInstead!.deezerId, '302127');
      expect(detail.albumInstead!.contains, 'One More Time');
      expect(detail.songs.single.duration, 320);
    });
  });

  group('Stremfin 1.91', () {
    test('what is at home comes with its id there, to play it at once', () {
      final song = StremfinSong.fromJson({
        'title': 'Verano',
        'in_jellyfin': true,
        'jellyfin_id': 'abc',
        'album_jellyfin_id': 'alb',
      })!;
      expect(song.jellyfinId, 'abc');
      expect(song.albumJellyfinId, 'alb');
      final album = StremfinAlbum.fromJson({
        'title': 'Brisa',
        'library': {'in_jellyfin': true, 'jellyfin_id': 'alb'},
      })!;
      expect(album.jellyfinId, 'alb');
    });

    test('«Para ti» says why, and which artists it went from', () {
      final found = StremfinRecommendations.fromJson({
        'seeds': [
          {'name': 'Bad Bunny', 'deezer_id': '10583405'},
          {'name': 'Nadie', 'deezer_id': null},
        ],
        'items': [
          {
            'title': 'Un disco',
            'deezer_id': '1',
            'reason': 'Porque escuchas a Bad Bunny',
          },
        ],
        'songs': [
          {'title': 'Una canción', 'reason': 'Porque escuchas a Bad Bunny'},
        ],
      });
      expect(found.seeds.map((s) => s.deezerId), ['10583405', null]);
      expect(found.albums.single.reason, 'Porque escuchas a Bad Bunny');
      expect(found.songs.single.reason, 'Porque escuchas a Bad Bunny');
    });
  });
}
