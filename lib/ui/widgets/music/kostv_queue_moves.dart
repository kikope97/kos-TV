import 'package:playback_core/playback_core.dart';

import '../../../data/models/aggregated_item.dart';

/// Kos TV: «A continuación» with the remote. The songs after the one
/// sounding, and moving one of them a place up or down or taking it away,
/// found again by the song itself (the queue may have moved on while its
/// menu was open).

typedef KostvUpcomingSong = ({int index, AggregatedItem item});

/// The songs after the one sounding, with where each sits in the queue.
List<KostvUpcomingSong> kostvUpcoming(QueueService queue) {
  final items = queue.items;
  return [
    for (var i = queue.currentIndex + 1; i < items.length; i++)
      if (items[i] is AggregatedItem)
        (index: i, item: items[i] as AggregatedItem),
  ];
}

/// Where [song] is among the songs to come, or null when it is not there
/// any more (it started, or was taken away).
int? kostvUpcomingPosition(QueueService queue, AggregatedItem song) {
  final upcoming = kostvUpcoming(queue);
  final at = upcoming.indexWhere((entry) => identical(entry.item, song));
  return at < 0 ? null : at;
}

/// Moves [song] one place up ([up]) or down among the songs to come. Gives
/// back its new place, or null when it could not move (already first or
/// last, or gone).
int? kostvMoveUpcoming(
  QueueService queue,
  AggregatedItem song, {
  required bool up,
}) {
  final upcoming = kostvUpcoming(queue);
  final at = upcoming.indexWhere((entry) => identical(entry.item, song));
  if (at < 0) return null;
  final to = up ? at - 1 : at + 1;
  if (to < 0 || to >= upcoming.length) return null;
  final from = upcoming[at].index;
  final other = upcoming[to].index;
  // QueueService.reorder takes the place before which it goes.
  queue.reorder(from, up ? other : other + 1);
  return to;
}

/// Takes [song] out of the songs to come. Gives back the place it had, or
/// null when it was not there.
int? kostvRemoveUpcoming(QueueService queue, AggregatedItem song) {
  final upcoming = kostvUpcoming(queue);
  final at = upcoming.indexWhere((entry) => identical(entry.item, song));
  if (at < 0) return null;
  queue.removeAt(upcoming[at].index);
  return at;
}

/// Kos TV: what «Vaciar» took away: the songs to come, in their order, and
/// the entry sounding then (for «Deshacer»).
typedef KostvClearedQueue = ({List<dynamic> gone, Object? sounding});

/// Kos TV: «Vaciar»: takes every song to come away (the one sounding goes
/// on), as one change of the queue. Gives back what went, for
/// [kostvPutBackUpcoming].
KostvClearedQueue kostvClearUpcoming(QueueService queue) {
  final sounding = queue.currentItem;
  return (gone: queue.removeUpcoming(), sounding: sounding);
}

/// Kos TV: «Deshacer» of «Vaciar»: the songs that went come back right
/// after the one that was sounding, in their order, ahead of anything added
/// since. What [addedBySelf] says came by itself meanwhile (autoplay, which
/// fills an empty queue) goes, so the queue is as it was. Nothing when that
/// song isn't in the queue any more (another queue was put on). Gives back
/// whether they came back.
bool kostvPutBackUpcoming(
  QueueService queue,
  KostvClearedQueue cleared, {
  bool Function(Object? item)? addedBySelf,
}) {
  if (cleared.gone.isEmpty) return false;
  if (!queue.items.any((e) => identical(e, cleared.sounding))) return false;
  if (addedBySelf != null) queue.removeUpcomingWhere(addedBySelf);
  final at = queue.items.indexWhere((e) => identical(e, cleared.sounding));
  if (at < 0) return false;
  queue.insertAllAfter(at, cleared.gone);
  return true;
}
