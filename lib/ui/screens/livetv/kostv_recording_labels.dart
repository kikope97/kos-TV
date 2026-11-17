import 'package:intl/intl.dart';

import '../../../data/viewmodels/schedule_view_model.dart';
import '../../../data/viewmodels/series_recordings_view_model.dart';
import '../../../l10n/app_localizations.dart';

/// Kos TV: a day of the recordings schedule in the person's language
/// («Hoy», «Mañana», «sáb, 14 nov»).
String kostvScheduleDayLabel(AppLocalizations l10n, ScheduleGroup group) {
  final date = group.date;
  if (date == null) return group.dateLabel;
  return switch (group.daysFromToday) {
    0 => l10n.kostvDayToday,
    1 => l10n.kostvDayTomorrow,
    -1 => l10n.kostvDayYesterday,
    _ => DateFormat('EEE, d MMM', l10n.localeName).format(date),
  };
}

/// Kos TV: a series recording's channel and days in the person's language.
String kostvSeriesTimerSubtitle(AppLocalizations l10n, SeriesTimerItem timer) {
  final parts = <String>[];
  final channel = timer.recordAnyChannel == true
      ? l10n.kostvAllChannels
      : timer.channelName;
  if (channel != null && channel.isNotEmpty) parts.add(channel);
  final days = switch (timer.dayPattern) {
    'Daily' => l10n.kostvEveryDay,
    'Weekdays' => l10n.kostvWeekdays,
    'Weekends' => l10n.kostvWeekends,
    final other => other,
  };
  if (days != null && days.isNotEmpty) parts.add(days);
  return parts.join(' • ');
}
