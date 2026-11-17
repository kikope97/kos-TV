import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:moonfin/data/viewmodels/schedule_view_model.dart';
import 'package:moonfin/data/viewmodels/series_recordings_view_model.dart';
import 'package:moonfin/l10n/app_localizations_es.dart';
import 'package:moonfin/ui/screens/livetv/kostv_recording_labels.dart';

/// Kos TV: the recordings screens speak the person's language.
void main() {
  final l10n = AppLocalizationsEs();

  setUpAll(() => initializeDateFormatting('es'));

  ScheduleGroup day(int offset, DateTime date) => ScheduleGroup(
    dateLabel: 'English',
    items: const [],
    date: date,
    daysFromToday: offset,
  );

  test('today, tomorrow and yesterday by name', () {
    final d = DateTime(2026, 11, 14);
    expect(kostvScheduleDayLabel(l10n, day(0, d)), 'Hoy');
    expect(kostvScheduleDayLabel(l10n, day(1, d)), 'Mañana');
    expect(kostvScheduleDayLabel(l10n, day(-1, d)), 'Ayer');
  });

  test('any other day with its date in Spanish', () {
    final label = kostvScheduleDayLabel(l10n, day(3, DateTime(2026, 11, 14)));
    expect(label, contains('14'));
    expect(label, contains('nov'));
  });

  test('a series recording on any channel, every day', () {
    final timer = SeriesTimerItem.fromJson({
      'Id': '1',
      'Name': 'Noticias',
      'RecordAnyChannel': true,
      'DayPattern': 'Daily',
    });
    expect(
      kostvSeriesTimerSubtitle(l10n, timer),
      'Todos los canales • Todos los días',
    );
  });

  test('one channel on weekdays', () {
    final timer = SeriesTimerItem.fromJson({
      'Id': '1',
      'Name': 'Noticias',
      'ChannelName': 'La 1',
      'DayPattern': 'Weekdays',
    });
    expect(kostvSeriesTimerSubtitle(l10n, timer), 'La 1 • Entre semana');
  });
}
