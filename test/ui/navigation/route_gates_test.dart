import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/models/aggregated_library.dart';
import 'package:moonfin/ui/navigation/destinations.dart';
import 'package:moonfin/ui/navigation/home_refresh_bus.dart';
import 'package:moonfin/ui/navigation/nav_libraries_memory.dart';
import 'package:moonfin/ui/navigation/route_gates.dart';

class _FakeSession extends Fake implements SessionRepository {
  String? userId;

  @override
  String? get activeUserId => userId;
}

AggregatedLibrary _lib(String id) => AggregatedLibrary(
  id: id,
  name: id,
  collectionType: 'movies',
  serverId: 's',
);

/// Kos TV: the gates the router, the menu and Back share.
void main() {
  group('Kids Mode', () {
    test('blocks the calendar, as the menus hide it', () {
      expect(kidsModeBlocksPath(Destinations.calendar), isTrue);
      expect(kidsModeBlocksPath(Destinations.calendarMonth), isTrue);
    });

    test('blocks what it blocked before', () {
      expect(kidsModeBlocksPath(Destinations.liveTvGuide), isTrue);
      expect(kidsModeBlocksPath(Destinations.kostvDiscover), isTrue);
      expect(kidsModeBlocksPath('/discover/movie/12'), isTrue);
      expect(kidsModeBlocksPath(Destinations.kostvMusic), isTrue);
      expect(kidsModeBlocksPath('/musica/album/3'), isTrue);
      expect(kidsModeBlocksPath(Destinations.admin), isTrue);
    });

    test('leaves the household libraries alone', () {
      // A music library is /music/..., not Music (/musica).
      expect(kidsModeBlocksPath(Destinations.musicLibrary('m1')), isFalse);
      expect(kidsModeBlocksPath(Destinations.home), isFalse);
      expect(kidsModeBlocksPath(Destinations.myList), isFalse);
    });

    test('blocks book Discover, but not the rest of a book library', () {
      expect(
        kidsModeBlocksPath(Destinations.bookCategory('b1', 'discover')),
        isTrue,
      );
      expect(kidsModeBlocksPath('/books/b1/discover/'), isTrue);
      expect(kidsModeClosesPath('/books/b1/discover'), isTrue);
      expect(
        kidsModeBlocksPath(Destinations.bookCategory('b1', 'titles')),
        isFalse,
      );
      expect(kidsModeBlocksPath(Destinations.bookLibrary('b1')), isFalse);
    });

    test('blocks the RomM account, but not the games', () {
      expect(kidsModeBlocksPath(Destinations.rommAccount), isTrue);
      expect(kidsModeClosesPath(Destinations.rommAccount), isTrue);
      expect(kidsModeBlocksPath('/games/g1'), isFalse);
    });

    test('closes the TV apps page too', () {
      expect(kidsModeClosesPath(Destinations.apps), isTrue);
      expect(kidsModeClosesPath(Destinations.allGenres), isFalse);
    });
  });

  group('Back on the web with nothing under the page', () {
    test('goes to Home from a menu page', () {
      expect(
        webBackGoesHome(Destinations.kostvDiscover, signedIn: true),
        isTrue,
      );
      expect(webBackGoesHome(Destinations.myList, signedIn: true), isTrue);
    });

    test('does nothing on Home', () {
      expect(webBackGoesHome(Destinations.home, signedIn: true), isFalse);
    });

    test('does nothing before Home', () {
      expect(webBackGoesHome(Destinations.login, signedIn: true), isFalse);
      expect(webBackGoesHome(Destinations.startup, signedIn: false), isFalse);
      expect(webBackGoesHome(Destinations.myList, signedIn: false), isFalse);
    });
  });

  test('a library page is what its menu button opens', () {
    expect(Destinations.isLibraryPage('/library/abc'), isTrue);
    expect(Destinations.isLibraryPage(Destinations.musicLibrary('m')), isTrue);
    expect(Destinations.isLibraryPage('/books/b'), isTrue);
    expect(Destinations.isLibraryPage(Destinations.gamesLibrary('g')), isTrue);
    expect(Destinations.isLibraryPage('/library/abc/genres'), isFalse);
    expect(Destinations.isLibraryPage(Destinations.home), isFalse);
  });

  group('Going to Home from the menu', () {
    test('asks nothing of a Home kept underneath', () {
      final bus = HomeRefreshBus();
      void onRefresh() {}
      bus.addListener(onRefresh);
      bus.requestOnArrival();
      bus.removeListener(onRefresh);
      // The next Home built (the next profile's) doesn't refresh for it.
      expect(bus.consumePending(), isFalse);
      expect(bus.value, 0);
    });

    test('refreshes a Home built afresh as it comes', () {
      final bus = HomeRefreshBus();
      bus.requestOnArrival();
      expect(bus.consumePending(), isTrue);
    });
  });

  group('The menus\' last libraries', () {
    late _FakeSession session;

    setUp(() {
      NavLibrariesMemory.reset();
      session = _FakeSession()..userId = 'parent';
      GetIt.instance.registerSingleton<SessionRepository>(session);
    });

    tearDown(() async {
      NavLibrariesMemory.reset();
      await GetIt.instance.reset();
    });

    test('are the ones of whoever is signed in', () {
      NavLibrariesMemory.remember('parent', [_lib('films'), _lib('tv')]);
      expect(NavLibrariesMemory.forActiveUser().map((l) => l.id), [
        'films',
        'tv',
      ]);
    });

    test('start empty for another profile', () {
      NavLibrariesMemory.remember('parent', [_lib('films'), _lib('tv')]);
      session.userId = 'child';
      expect(NavLibrariesMemory.forActiveUser(), isEmpty);
    });

    test('ignore a load that finished after someone else signed in', () {
      session.userId = 'child';
      NavLibrariesMemory.remember('parent', [_lib('films')]);
      expect(NavLibrariesMemory.forActiveUser(), isEmpty);
      session.userId = 'parent';
      expect(NavLibrariesMemory.forActiveUser(), isEmpty);
    });

    test('are none while nobody is signed in', () {
      NavLibrariesMemory.remember('parent', [_lib('films')]);
      session.userId = null;
      expect(NavLibrariesMemory.forActiveUser(), isEmpty);
      expect(listEquals(NavLibrariesMemory.forActiveUser(), const []), isTrue);
    });
  });
}
