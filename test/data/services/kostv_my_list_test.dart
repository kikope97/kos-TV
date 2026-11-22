import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/kostv_my_list.dart';
import 'package:moonfin/preference/bottom_nav_tabs.dart';

/// Kos TV: the person's list of what they want to watch.
void main() {
  AggregatedItem item(String type, {String? series}) => AggregatedItem(
    id: 'a-1',
    serverId: 'home',
    rawData: {'Id': 'a-1', 'Type': type, 'SeriesId': ?series},
  );

  group('what goes on the list', () {
    test('a film or a series is itself', () {
      expect(KostvMyListService.listIdOf(item('Movie')), 'a1');
      expect(KostvMyListService.listIdOf(item('Series')), 'a1');
    });

    test('an episode or a season stands for its series', () {
      expect(KostvMyListService.listIdOf(item('Episode', series: 's-9')), 's9');
      expect(KostvMyListService.listIdOf(item('Season', series: 's-9')), 's9');
    });

    test('anything else has no place on it', () {
      expect(KostvMyListService.listIdOf(item('Audio')), isNull);
      expect(KostvMyListService.listIdOf(item('Episode')), isNull);
    });
  });

  group('how to get to it on a phone', () {
    const gates = BottomNavTabGates(kostvMyListAvailable: true);

    test('offered only with a plugin that keeps lists', () {
      expect(gates.offers(BottomNavTab.myList), isTrue);
      expect(const BottomNavTabGates().offers(BottomNavTab.myList), isFalse);
    });

    // Kos TV: the bar's tabs are Descubrir and Música; where they aren't
    // offered the list takes a place on the bar.
    test('on the bar when Discover and Music are not', () {
      const noDiscoverNoMusic = BottomNavTabGates(
        kostvMyListAvailable: true,
        showKostvMusic: false,
        showLibraries: false,
      );
      expect(noDiscoverNoMusic.barTabs(), contains(BottomNavTab.myList));
      expect(gates.barTabs(), isNot(contains(BottomNavTab.favorites)));
    });
  });
}
