import 'package:server_core/server_core.dart';

/// Kos TV: the avatar of [userId] on [client]'s server, carrying the image's
/// [imageTag] so a new photo gets a new address and the image cache (which
/// keeps a picture for days) can't keep showing the old one.
///
/// On Jellyfin a person with no tag has no photo, so there is nothing to ask
/// for and the caller paints the initial. Other servers keep their own URLs.
String? userAvatarUrl(
  MediaServerClient client, {
  required String userId,
  String? imageTag,
}) {
  final url = client.imageApi.getUserImageUrl(userId);
  if (client.serverType != ServerType.jellyfin || url.isEmpty) return url;
  if (imageTag == null || imageTag.isEmpty) return null;
  final uri = Uri.parse(url);
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'tag': imageTag})
      .toString();
}
