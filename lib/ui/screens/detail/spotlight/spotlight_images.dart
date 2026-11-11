import 'dart:math' as math;

import 'package:server_core/server_core.dart';

import '../../../../data/models/aggregated_item.dart';
import '../../../../data/viewmodels/item_detail_view_model.dart';
import '../item_detail_screen.dart' show isOutsideLibraryItem;

const _tmdbPosterBase = 'https://image.tmdb.org/t/p/w342';
const _tmdbBackdropBase = 'https://image.tmdb.org/t/p/w1280';

/// The poster or primary image for [item], with the TMDB poster a title from
/// outside the library carries.
String? spotlightItemImageUrl(ImageApi imageApi, AggregatedItem item) {
  final isLibraryItem = !isOutsideLibraryItem(item);
  final tag = item.primaryImageTag ?? item.primaryImageTagField;
  if (isLibraryItem && tag != null) {
    return imageApi.getPrimaryImageUrl(item.id, maxHeight: 360, tag: tag);
  }
  if (!isLibraryItem) {
    return _tmdbUrl(_tmdbPosterBase, item.rawData['PosterPath'] as String?);
  }
  // A collection built from an ancestor record can arrive without its image
  // tag while the server still holds a primary image for it. Only box sets
  // get the tagless request: any folder with children would qualify
  // otherwise, and one with no image at all would fetch a 404 in place of
  // its placeholder.
  if (isLibraryItem && item.type == 'BoxSet') {
    return imageApi.getPrimaryImageUrl(item.id, maxHeight: 360);
  }
  return null;
}

/// A person's portrait: the server image when [id] and [tag] name a library
/// person, else null.
String? spotlightPersonImageUrl(
  ImageApi imageApi, {
  String? id,
  String? tag,
  required int maxHeight,
}) {
  if (id != null && tag != null) {
    return imageApi.getPrimaryImageUrl(id, maxHeight: maxHeight, tag: tag);
  }
  return null;
}

/// A landscape thumbnail or backdrop for [item], prioritizing 16:9 artwork
/// (Thumb, then Backdrop) over posters.
String? spotlightLandscapeImageUrl(
  ImageApi imageApi,
  AggregatedItem item, {
  int maxWidth = 640,
  String? fallbackUrl,
}) {
  final thumbTag = item.thumbImageTag;
  if (thumbTag != null) {
    return imageApi.getThumbImageUrl(item.id, maxWidth: maxWidth, tag: thumbTag);
  }
  if (item.backdropImageTags.isNotEmpty) {
    return imageApi.getBackdropImageUrl(
      item.id,
      maxWidth: maxWidth,
      tag: item.backdropImageTags.first,
    );
  }
  final parentBackdropId = item.parentBackdropItemId;
  if (parentBackdropId != null && item.parentBackdropImageTags.isNotEmpty) {
    return imageApi.getBackdropImageUrl(
      parentBackdropId,
      maxWidth: maxWidth,
      tag: item.parentBackdropImageTags.first,
    );
  }
  if (isOutsideLibraryItem(item)) {
    final backdrop = _tmdbUrl(
      _tmdbBackdropBase,
      item.rawData['BackdropPath'] as String?,
    );
    if (backdrop != null) return backdrop;
  }

  return fallbackUrl;
}

/// A bare TMDB image path at [base], or null when there is none.
String? _tmdbUrl(String base, String? path) =>
    path == null || path.isEmpty ? null : '$base$path';

/// A backdrop a person's page could use, taken from their filmography.
class PersonBackdropCandidate {
  /// What marks this backdrop as already taken, in the form `local:id:tag`.
  final String key;

  /// The wide copy the full screen hero draws.
  final String fullUrl;

  /// The narrower copy a summary card draws.
  final String cardUrl;

  const PersonBackdropCandidate({
    required this.key,
    required this.fullUrl,
    required this.cardUrl,
  });
}

/// The backdrops a person's library filmography can offer.
List<PersonBackdropCandidate> collectPersonLocalBackdrops(
  ItemDetailViewModel vm,
) {
  final results = <PersonBackdropCandidate>[];
  final seen = <String>{};
  // filmographyMovies and filmographySeries are filters over this same list.
  for (final item in vm.filmography) {
    if (item.backdropImageTags.isEmpty) continue;
    final tag = item.backdropImageTags.first;
    final key = 'local:${item.id}:$tag';
    if (!seen.add(key)) continue;
    results.add(
      PersonBackdropCandidate(
        key: key,
        fullUrl: vm.imageApi.getBackdropImageUrl(
          item.id,
          tag: tag,
          maxWidth: 1920,
        ),
        cardUrl: vm.imageApi.getBackdropImageUrl(
          item.id,
          tag: tag,
          maxWidth: 960,
        ),
      ),
    );
  }
  return results;
}

/// A backdrop for one card, taken from [preferred] where it can be and from
/// [all] otherwise, and marked in [usedKeys] so the next card picks another.
///
/// Once every candidate is spoken for it repeats one rather than leaving the
/// card bare, which is why a person with a single backdrop still gets cards.
String? randomPickBackdrop({
  required List<PersonBackdropCandidate> preferred,
  required List<PersonBackdropCandidate> all,
  required Set<String> usedKeys,
  math.Random? random,
}) {
  final rng = random ?? math.Random();
  for (final pool in [preferred, all]) {
    final free = pool.where((c) => !usedKeys.contains(c.key)).toList();
    if (free.isEmpty) continue;
    final chosen = free[rng.nextInt(free.length)];
    usedKeys.add(chosen.key);
    return chosen.cardUrl;
  }
  for (final pool in [preferred, all]) {
    if (pool.isNotEmpty) return pool[rng.nextInt(pool.length)].cardUrl;
  }
  return null;
}

/// The backdrop for each of a person's cards, keyed by card id, with
/// [mainBackdropKey] held back so the hero keeps a picture of its own.
Map<String, String?> personCardBackdropsFor({
  required List<PersonBackdropCandidate> local,
  String? mainBackdropKey,
  math.Random? random,
}) {
  return {
    'filmography': randomPickBackdrop(
      preferred: local,
      all: local,
      usedKeys: <String>{?mainBackdropKey},
      random: random,
    ),
  };
}
