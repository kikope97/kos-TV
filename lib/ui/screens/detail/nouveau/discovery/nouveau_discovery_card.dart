import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../../../data/models/aggregated_item.dart';
import '../../../../../preference/user_preferences.dart';
import '../../../../../util/item_watch_state.dart';
import '../../../../navigation/destinations.dart';
import '../../item_detail_screen.dart'
    show isOutsideLibraryItem, showOutsideLibraryTitle;
import '../shared/nouveau_poster_card.dart';

class NouveauDiscoveryCard extends StatelessWidget {
  final AggregatedItem item;
  final ImageApi imageApi;
  final UserPreferences prefs;
  final double width;
  final bool isFocused;

  const NouveauDiscoveryCard({
    super.key,
    required this.item,
    required this.imageApi,
    required this.prefs,
    required this.width,
    required this.isFocused,
  });

  static const double _aspectRatio = 2 / 3;

  static void openItem(BuildContext context, AggregatedItem item) {
    if (isOutsideLibraryItem(item)) {
      showOutsideLibraryTitle(context, item.name);

      return;
    }

    context.push(Destinations.item(item.id, serverId: item.serverId));
  }

  bool _isPhonePortrait(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return size.height > size.width && size.width < 600;
  }

  String? _imageUrl() {
    final tag = item.primaryImageTag;

    if (tag != null) {
      return imageApi.getPrimaryImageUrl(item.id, maxHeight: 750, tag: tag);
    }

    // A TMDB recommendation from outside the library brings its own poster.
    final posterPath = item.rawData['PosterPath'] as String?;

    if (posterPath != null && posterPath.isNotEmpty) {
      return 'https://image.tmdb.org/t/p/w500$posterPath';
    }

    return null;
  }

  double get _progress {
    final percentage = item.playedPercentage ?? 0;

    if (!percentage.isFinite) {
      return 0;
    }

    return (percentage / 100).clamp(0.0, 1.0).toDouble();
  }

  bool _showPlayedIndicator() => showsWatchedIndicator(
    behavior: prefs.get(UserPreferences.watchedIndicatorBehavior),
    isPlayed: item.isPlayed,
    itemType: item.type,
    unplayedCount: item.unplayedItemCount,
  );

  @override
  Widget build(BuildContext context) {
    final phonePortrait = _isPhonePortrait(context);

    final posterHeight = width / _aspectRatio;

    final title = item.name.trim();

    final poster = NouveauPosterCard(
      imageUrl: _imageUrl(),
      title: title,
      width: width,
      height: posterHeight,
      isFocused: isFocused,
      isFavorite: item.isFavorite,
      isPlayed: _showPlayedIndicator(),
      progress: _progress,
      placeholderIcon: Icons.movie_outlined,
      onTap: () {
        openItem(context, item);
      },
    );

    if (!phonePortrait) {
      return poster;
    }

    final foreground = AppColorScheme.onSurface;

    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        openItem(context, item);
      },
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            poster,

            const SizedBox(height: 9),

            SizedBox(
              width: double.infinity,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: foreground.withValues(alpha: 0.94),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
