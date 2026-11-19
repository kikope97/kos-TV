import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/screens/detail/kostv/kostv_detail_buttons.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('es'));
  const series = AggregatedItem(
    id: 'series',
    serverId: 'home',
    rawData: {'Type': 'Series'},
  );

  AggregatedItem firstEpisode({int positionTicks = 0}) => AggregatedItem(
    id: 'e1',
    serverId: 'home',
    rawData: {
      'Type': 'Episode',
      'Name': 'Piloto',
      'ParentIndexNumber': 1,
      'IndexNumber': 1,
      'RunTimeTicks': 30 * 60 * 10000000,
      'UserData': {'PlaybackPositionTicks': positionTicks},
    },
  );

  test('the first episode not started yet is plain Play', () {
    final text = KostvPlayText.of(
      l10n,
      'Reproducir',
      series,
      nextUp: firstEpisode(),
    );
    expect(text.title, 'Reproducir');
    expect(text.progress, isNull);
  });

  test('the first episode half watched says Continue with it, and how far', () {
    final text = KostvPlayText.of(
      l10n,
      'Reproducir',
      series,
      nextUp: firstEpisode(positionTicks: 15 * 60 * 10000000),
    );
    expect(text.title, startsWith(l10n.kostvDetailContinueWith('').trim()));
    expect(text.subtitle, 'Piloto');
    expect(text.progress, closeTo(0.5, 0.001));
  });
}
