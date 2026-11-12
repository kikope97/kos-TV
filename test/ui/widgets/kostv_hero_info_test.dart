import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/ui/widgets/mediabar/kostv_hero_info.dart';

void main() {
  test('the line of facts of a film carries its length and two genres', () {
    const film = MediaBarSlideItem(
      itemId: 'a',
      serverId: 's',
      title: 'Una',
      year: 2024,
      officialRating: '16',
      runtime: Duration(minutes: 105),
      genres: ['Thriller', 'Drama', 'Misterio'],
    );
    expect(
      KostvHeroInfo.facts(film),
      '2024  •  16  •  1h 45m  •  Thriller  •  Drama',
    );
  });

  test('a series has no length, and a pick with nothing says nothing', () {
    const series = MediaBarSlideItem(
      itemId: 'a',
      serverId: 's',
      title: 'Una',
      itemType: 'Series',
      year: 2021,
      runtime: Duration(minutes: 50),
    );
    expect(KostvHeroInfo.facts(series), '2021');
    expect(
      KostvHeroInfo.facts(
        const MediaBarSlideItem(itemId: 'a', serverId: 's', title: 'Una'),
      ),
      '',
    );
  });

  test('a copy of a pick keeps the row it came from', () {
    const pick = MediaBarSlideItem(
      itemId: 'a',
      serverId: 's',
      title: 'Una',
      kostvKind: 'because_watched',
      kostvLabel: 'Cars',
    );
    final copy = pick.withNewRelease(null);
    expect(copy.kostvKind, 'because_watched');
    expect(copy.kostvLabel, 'Cars');
  });
}
