import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/navigation/player_route_check.dart';

void main() {
  // Kos TV: a pushed player leaves the router's uri on the tab below, which
  // is how a remote Play, SyncPlay or a Watch Party room used to push a
  // second player over the one already open.
  testWidgets('a pushed player is seen on top though the uri stays below', (
    tester,
  ) async {
    Widget page(String name) => Scaffold(body: Text(name));
    final router = GoRouter(
      initialLocation: Destinations.home,
      routes: [
        GoRoute(path: Destinations.home, builder: (_, _) => page('home')),
        GoRoute(
          path: Destinations.videoPlayer,
          builder: (_, _) => page('video'),
        ),
        GoRoute(
          path: Destinations.audioPlayer,
          builder: (_, _) => page('audio'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(isMediaPlayerRouteOnTop(router), isFalse);

    router.push(Destinations.videoPlayer);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Destinations.home,
    );
    expect(topRouteLocation(router), Destinations.videoPlayer);
    expect(isMediaPlayerRouteOnTop(router), isTrue);
    expect(isVideoPlayerRouteOnTop(router), isTrue);

    router.pop();
    await tester.pumpAndSettle();
    router.push(Destinations.audioPlayer);
    await tester.pumpAndSettle();
    expect(isMediaPlayerRouteOnTop(router), isTrue);
    expect(isVideoPlayerRouteOnTop(router), isFalse);
  });
}
