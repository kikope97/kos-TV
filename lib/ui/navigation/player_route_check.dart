import 'package:go_router/go_router.dart';

import 'destinations.dart';

/// Kos TV: the location of whatever is on top of [router]'s stack. A player
/// is pushed over the tab that launched it, and a push leaves the router's
/// uri on that tab, so only the match list names what is actually on screen.
String topRouteLocation(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  if (configuration.matches.isEmpty) return '';
  return configuration.last.matchedLocation;
}

/// Kos TV: whether the video or audio player (or the external player host
/// standing in for the video one) is on top, so a remote command, a SyncPlay
/// group or a Watch Party room switching titles reuses it instead of pushing
/// a second player over it.
bool isMediaPlayerRouteOnTop(GoRouter router) {
  final location = topRouteLocation(router);
  return location == Destinations.videoPlayer ||
      location == Destinations.audioPlayer ||
      location == Destinations.externalPlayer;
}

/// Kos TV: whether the video player itself (or the external player host
/// standing in for it) is on top.
bool isVideoPlayerRouteOnTop(GoRouter router) {
  final location = topRouteLocation(router);
  return location == Destinations.videoPlayer ||
      location == Destinations.externalPlayer;
}
