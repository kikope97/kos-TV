import 'media_bar_slide_item.dart';

sealed class MediaBarState {
  const MediaBarState();
}

class MediaBarLoading extends MediaBarState {
  const MediaBarLoading();
}

class MediaBarReady extends MediaBarState {
  final List<MediaBarSlideItem> items;
  const MediaBarReady(this.items);
}

class MediaBarError extends MediaBarState {
  final Object error;
  const MediaBarError(this.error);
}

class MediaBarDisabled extends MediaBarState {
  const MediaBarDisabled();
}

/// Kos TV: none of the titles the bar could show has a backdrop. The widget
/// says so in the person's language.
class MediaBarNoBackdrops implements Exception {
  const MediaBarNoBackdrops();

  @override
  String toString() => 'No items with backdrop images found';
}
