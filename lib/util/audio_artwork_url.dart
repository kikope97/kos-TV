import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../data/models/aggregated_item.dart';
import '../data/services/media_server_client_factory.dart';
import '../data/services/stremfin/kostv_stream_song.dart';

/// The playing track's artwork: the album cover for music, its own picture
/// otherwise. Null when there's no artwork or its server can't be reached.
String? audioArtUrl(
  AggregatedItem item, {
  required MediaServerClientFactory clientFactory,
  required int maxHeight,
}) {
  // Kos TV: a song that isn't at home has Deezer's cover.
  if (isKostvStream(item)) return KostvStreamInfo.of(item)?.cover;
  try {
    final client = clientFactory.getClientIfExists(item.serverId) ??
        GetIt.instance<MediaServerClient>();
    final albumTag = item.albumPrimaryImageTag;
    final albumId = item.albumId;
    if (item.type == 'Audio' && albumTag != null && albumId != null) {
      return client.imageApi
          .getPrimaryImageUrl(albumId, maxHeight: maxHeight, tag: albumTag);
    }
    if (item.primaryImageTag != null) {
      return client.imageApi.getPrimaryImageUrl(
        item.id,
        maxHeight: maxHeight,
        tag: item.primaryImageTag,
      );
    }
  } catch (_) {}
  return null;
}
