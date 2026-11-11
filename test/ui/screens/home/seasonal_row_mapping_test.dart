import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';

/// What Moonbase answers for the seasonal row, as the clients read it.
Map<String, dynamic> _body({
  String? holiday = 'christmas',
  List<Map<String, dynamic>>? items,
}) => {
  'holiday': holiday,
  'country': 'US',
  'items': items ??
      [
        {
          'Id': 'abc',
          'Name': 'Elf',
          'Type': 'Movie',
          'OfficialRating': 'PG',
          'ImageTags': {'Primary': '1A'},
          'UserData': {'Played': true},
        },
      ],
  // Titles from outside the library. Kos TV leaves them out of the row.
  'suggestions': [
    {
      'id': 10719,
      'name': 'The Polar Express',
      'type': 'Movie',
      'productionYear': 2004,
      'officialRating': 'G',
      'providerIds': {'Tmdb': '10719', 'Imdb': 'tt0338348'},
      'posterUrl': '/poster.jpg',
      'backdropUrl': '/backdrop.jpg',
      'overview': 'A boy rides a train to the North Pole.',
      'rating': 6.7,
      'genres': ['Animation', 'Adventure'],
      'runTimeTicks': 60000000000,
    },
  ],
};

void main() {
  SeasonalRowData? map(Map<String, dynamic> body, {Set<String> hidden = const {}}) =>
      HomeViewModel.mapSeasonalResponse(body, serverId: 'http://srv', hiddenHolidays: hidden);

  test('no holiday means no row', () {
    expect(map(_body(holiday: null)), isNull);
    expect(map(_body(holiday: '')), isNull);
  });

  test('a holiday the viewer hid means no row', () {
    expect(map(_body(), hidden: {'christmas'}), isNull);
    expect(map(_body(), hidden: {'halloween'}), isNotNull);
  });

  test('owned movies belong to this server and keep what the server sent', () {
    final data = map(_body())!;

    expect(data.holiday, 'christmas');
    final owned = data.owned.single;
    expect(owned.id, 'abc');
    expect(owned.serverId, 'http://srv');
    expect(owned.officialRating, 'PG');
    expect(owned.rawData['UserData'], {'Played': true});
  });

  test('a holiday with nothing from the library means no row', () {
    expect(map(_body(items: [])), isNull);
  });

  test('items without an id are skipped', () {
    final body = _body(items: [{'Name': 'no id'}]);

    expect(map(body), isNull);
  });
}
