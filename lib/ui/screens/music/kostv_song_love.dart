import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/repositories/item_mutation_repository.dart';
import '../../../data/services/kostv_music_away.dart';
import '../../../data/services/stremfin/kostv_stream_song.dart';
import 'kostv_music_actions.dart' show kostvMusicFavoritesChanged;
import 'kostv_music_away_actions.dart';

/// Kos TV: the ♥ of the song sounding, the same in «Reproduciendo», the
/// floating player and the bottom bar's player: the home server's for a
/// song at home, the server plugin's for one that isn't (when it keeps
/// them).

/// Bumps when a ♥ given here changes (at once, before the server answers),
/// for every player that shows it to redraw.
final kostvSongLoveChanged = ValueNotifier<int>(0);

bool _offline() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<PlaybackManager>()) return false;
  try {
    return getIt<PlaybackManager>().isOfflinePlayback;
  } catch (_) {
    return false;
  }
}

/// Whether [item] has a ♥ to give here: not with what is downloaded, and
/// for one that isn't at home, only when the plugin keeps them.
bool kostvSongCanLove(AggregatedItem item) =>
    !_offline() && (!isKostvStream(item) || kostvAwayCanKeep(item));

/// Whether the person gave [item] a ♥.
bool kostvSongLoved(AggregatedItem item) =>
    isKostvStream(item) ? kostvAwayLoved(item) : item.isFavorite;

/// Gives [item] the person's ♥, or takes it away: shown at once, and back
/// as it was if the server says no.
Future<void> kostvToggleSongLove(
  BuildContext context,
  AggregatedItem item,
) async {
  // One that isn't at home: the plugin's ♥ (with the offer to ask for its
  // album).
  if (isKostvStream(item)) {
    await kostvAwayToggleLove(context, item);
    kostvSongLoveChanged.value++;
    return;
  }
  final was = item.isFavorite;
  void mark(bool on) {
    // On the item itself, for its menu and every player showing it.
    final data = Map<String, dynamic>.from(
      (item.rawData['UserData'] as Map?) ?? const {},
    );
    data['IsFavorite'] = on;
    item.rawData['UserData'] = data;
    kostvSongLoveChanged.value++;
  }

  mark(!was);
  try {
    await GetIt.instance<ItemMutationRepository>().setFavorite(
      item.id,
      isFavorite: !was,
    );
    // «Tus favoritas» on the Music page hears of it.
    kostvMusicFavoritesChanged.value++;
  } catch (_) {
    mark(was);
  }
}

/// Kos TV: redraws [builder] whenever a ♥ may have changed (given here, or
/// the plugin's list of those of songs that aren't at home).
class KostvSongLoveBuilder extends StatelessWidget {
  const KostvSongLoveBuilder({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      kostvSongLoveChanged,
      kostvMusicFavoritesChanged,
      KostvMusicAwayStore.instance,
    ]),
    builder: (context, _) => builder(context),
  );
}

@visibleForTesting
void kostvSongLoveDebugReset() => kostvSongLoveChanged.value = 0;
