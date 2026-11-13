import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/services/kostv_home.dart';
import 'package:moonfin/data/services/stremfin/stremfin_models.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the Home built around the person.
void main() {
  HomeRow row(String id) =>
      HomeRow(id: id, title: id, rowType: HomeRowType.latestMedia);

  AggregatedItem card(String id) =>
      AggregatedItem(id: id, serverId: 'home', rawData: {'Id': id});
  HomeRow full(String id, List<String> items) => HomeRow(
    id: id,
    title: id,
    rowType: HomeRowType.latestMedia,
    items: [for (final i in items) card(i)],
    totalCount: items.length,
  );

  group('what the person sees', () {
    test('a title they turned down leaves the rows made for them, and a row '
        'left empty goes', () {
      final rows = [
        full('resume', ['a']),
        full('kostvRec_because_watched_1', ['a', 'b', 'c']),
        full('kostvRec_top_all', ['b']),
        full('kostvMore_genre_x', ['d']),
      ];
      final seen = KostvHomeRepository.visible(rows, {'a', 'b'});
      expect(seen.map((r) => r.id), [
        'resume',
        'kostvRec_because_watched_1',
        'kostvMore_genre_x',
      ]);
      // Carrying on is theirs to manage: it keeps what they turned down.
      expect(seen.first.items.map((i) => i.id), ['a']);
      expect(seen[1].items.map((i) => i.id), ['c']);
      expect(seen[1].totalCount, 1);
    });

    test('a new episode already in their row to carry on with is not shown '
        'twice', () {
      final rows = [
        full('resume', ['e1']),
        full('kostvRec_new_episodes', ['e1', 'e2']),
      ];
      expect(
        KostvHomeRepository.visible(rows, const {})[1].items.map((i) => i.id),
        ['e2'],
      );
      expect(
        KostvHomeRepository.visible([
          full('resume', ['e1']),
          full('kostvRec_new_episodes', ['e1']),
        ], const {}).map((r) => r.id),
        ['resume'],
      );
    });

    test('nothing to take out, the same rows', () {
      final rows = [
        full('kostvRec_for_you', ['a']),
      ];
      expect(
        identical(KostvHomeRepository.visible(rows, const {}), rows),
        isTrue,
      );
    });
  });

  group('favourites on Home', () {
    test('the row to watch again has its own id and title, and none when '
        'empty', () {
      final l10n = lookupAppLocalizations(const Locale('es'));
      expect(KostvHomeRepository.rewatchRow(const [], 'kostvRec_', l10n), isNull);
      final row = KostvHomeRepository.rewatchRow(
        [card('a'), card('b')],
        'kostvRec_',
        l10n,
      )!;
      expect(row.id, 'kostvRec_rewatch');
      expect(row.title, l10n.kostvHomeRewatch);
      expect(row.totalCount, 2);
    });

    test('a new episode of a favourite series is told apart', () {
      final plain = card('e1');
      final favourite = AggregatedItem(
        id: 'e2',
        serverId: 'home',
        rawData: {'Id': 'e2', 'KostvFavoriteSeries': true},
      );
      expect(KostvHomeRepository.isOfFavoriteSeries(plain), isFalse);
      expect(KostvHomeRepository.isOfFavoriteSeries(favourite), isTrue);
    });
  });

  group('the rows in order', () {
    test('the first top goes after the first row, then one every two', () {
      final rows = [for (var i = 0; i < 6; i++) row('r$i')];
      final tops = [row('t0'), row('t1'), row('t2')];

      expect(KostvHomeRepository.weave(rows, tops).map((r) => r.id), [
        'r0',
        't0',
        'r1',
        'r2',
        't1',
        'r3',
        'r4',
        't2',
        'r5',
      ]);
    });

    test('tops with no rows still show', () {
      expect(
        KostvHomeRepository.weave(const [], [row('t0')]).map((r) => r.id),
        ['t0'],
      );
    });

    test('films and series take turns in a top', () {
      expect(
        KostvHomeRepository.byTurns([
          ['f1', 'f2', 'f3'],
          ['s1'],
        ]),
        ['f1', 's1', 'f2', 'f3'],
      );
    });
  });

  group('what the person asked for', () {
    final now = DateTime(2026, 11, 12, 20);
    StremfinRequest request(
      int id, {
      bool mine = true,
      StremfinRequestStatus status = StremfinRequestStatus.completed,
      Duration ago = const Duration(hours: 5),
    }) => StremfinRequest(
      id: id,
      status: status,
      type: StremfinTitleType.movie,
      tmdbId: 100 + id,
      mine: mine,
      completedAt: now.subtract(ago),
    );

    test('shows for two days after it arrives, the newest first, and only '
        'their own', () {
      final titles = KostvHomeRepository.arrivedTitles([
        request(1, ago: const Duration(hours: 30)),
        request(2),
        request(3, ago: const Duration(days: 3)),
        request(4, mine: false),
        request(5, status: StremfinRequestStatus.approved),
      ], now);

      expect(titles.map((t) => t.tmdbId), [102, 101]);
    });
  });

  group('the titles of the rows', () {
    final l10n = lookupAppLocalizations(const Locale('es'));
    String title(String kind, [String? label]) => KostvHomeServerRow(
      kind: kind,
      label: label,
      items: const [],
    ).title(l10n);

    test('say why the row is there', () {
      expect(title('because_watched', 'Cars'), 'Porque viste Cars');
      expect(title('because_watching', 'Lost'), 'Porque estás viendo Lost');
      expect(title('for_you'), 'Recomendado para ti');
      expect(title('with_person', 'Ana Gil'), 'Más de Ana Gil');
      expect(title('genre', 'Comedia'), 'Porque sueles ver Comedia');
      expect(title('hidden_gems'), 'Joyas que no has visto');
    });

    test('a row keeps its id from one load to the next', () {
      const a = KostvHomeServerRow(kind: 'genre', label: 'Drama', items: []);
      const b = KostvHomeServerRow(kind: 'genre', label: 'Drama', items: []);
      const c = KostvHomeServerRow(kind: 'genre', label: 'Comedia', items: []);
      expect(a.idWith('x_'), b.idWith('x_'));
      expect(a.idWith('x_'), isNot(c.idWith('x_')));
    });
  });

  group('which Home is on', () {
    Future<UserPreferences> prefs(Map<String, Object> saved) async {
      SharedPreferences.setMockInitialValues(saved);
      final store = PreferenceStore();
      await store.init();
      return UserPreferences(store);
    }

    test('the recommended one once the server plugin offers it: arrived, '
        'carry on in one row, the rows made for the person, and nothing '
        'recently added', () async {
      final p = await prefs({'kostv_home_available': true});

      expect(p.kostvHomeActive, isTrue);
      final types = p.activeHomeSectionConfigs.map((c) => c.type).toList();
      expect(types.where((t) => t != HomeSectionType.mediaBar), [
        HomeSectionType.kostvArrived,
        HomeSectionType.resume,
        HomeSectionType.nextUp,
        HomeSectionType.kostvForYou,
        HomeSectionType.kostvForYouMore,
      ]);
      expect(p.effectiveMergeContinueWatchingNextUp, isTrue);
    });

    test('recently added goes last when asked for', () async {
      final p = await prefs({
        'kostv_home_available': true,
        'kostv_home_show_recent': true,
      });
      expect(p.activeHomeSectionConfigs.last.type, HomeSectionType.latestMedia);
    });

    test('the Home of sections with an older plugin, when turned off, and in '
        'Kids Mode', () async {
      expect((await prefs({})).kostvHomeActive, isFalse);
      expect(
        (await prefs({
          'kostv_home_available': true,
          'kostv_home_recommended': false,
        })).kostvHomeActive,
        isFalse,
      );
      final kids = await prefs({'kostv_home_available': true});
      await kids.set(UserPreferences.kidsModeEnabled, true);
      expect(kids.kostvHomeActive, isFalse);
      expect(
        kids.activeHomeSectionConfigs.map((c) => c.type),
        isNot(contains(HomeSectionType.kostvForYou)),
      );
    });
  });
}
