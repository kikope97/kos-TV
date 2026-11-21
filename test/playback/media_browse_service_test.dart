import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/audiobook_resume_service.dart';
import 'package:moonfin/data/services/kostv_music_plugin.dart';
import 'package:moonfin/data/services/stremfin/kostv_stream_song.dart';
import 'package:moonfin/data/services/media_server_client_factory.dart';
import 'package:moonfin/playback/headless_session_bootstrap.dart';
import 'package:moonfin/playback/last_playback_session_store.dart';
import 'package:moonfin/playback/media_browse_service.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPage = 'android.media.browse.extra.PAGE';
const _kPageSize = 'android.media.browse.extra.PAGE_SIZE';

/// Serves [totalItems] fake albums with names spread across '#' and A-Z,
/// honoring the nameStartsWith/nameLessThan/startIndex/limit windows the same
/// way the Jellyfin/Emby items APIs do.
class _FakeItemsApi implements ItemsApi {
  _FakeItemsApi({
    required this.totalItems,
    this.delay,
    this.books,
    this.latestBooks,
    this.resume,
    this.itemsById,
    this.emptyViews = const {},
  });

  /// View ids that contain no audio; getItems with one of these as parentId
  /// returns nothing, so the content probe filters the view out.
  final Set<String> emptyViews;

  final int totalItems;
  final Duration? delay;
  int listCalls = 0;

  /// Optional fixed book dataset served when [getItems] is called with a
  /// parentId (the booklib fill), regardless of name filters. Books carry a
  /// SortName so the service can bucket them client-side.
  final List<Map<String, dynamic>>? books;

  /// Recently-added books returned by getLatestItems when a parentId (the book
  /// view) is passed; music latest (no parentId) returns empty.
  final List<Map<String, dynamic>>? latestBooks;

  /// Server-side resume rows (usually empty for this app's local tracking).
  final List<Map<String, dynamic>>? resume;

  /// Backs getItem lookups (e.g. local-resume books resolved for Home).
  final Map<String, Map<String, dynamic>>? itemsById;

  static String nameFor(int i) {
    final bucket = i % 27;
    if (bucket == 0) return '0 Item $i';
    return '${String.fromCharCode(64 + bucket)} Item $i';
  }

  Future<Map<String, dynamic>> _page(Invocation invocation) async {
    listCalls++;
    if (delay != null) await Future<void>.delayed(delay!);
    final parentId = invocation.namedArguments[#parentId] as String?;
    final startsWith = invocation.namedArguments[#nameStartsWith] as String?;
    final lessThan = invocation.namedArguments[#nameLessThan] as String?;
    final start = invocation.namedArguments[#startIndex] as int? ?? 0;
    final limit = invocation.namedArguments[#limit] as int?;

    // Book libraries fetch by parentId with no name filters; the service
    // buckets the whole list client-side off each item's SortName.
    final matching = parentId != null && emptyViews.contains(parentId)
        ? const <Map<String, dynamic>>[]
        : parentId != null && books != null
        ? books!
        : <Map<String, dynamic>>[
            for (var i = 0; i < totalItems; i++)
              if ((startsWith == null || nameFor(i).startsWith(startsWith)) &&
                  (lessThan == null || nameFor(i).compareTo(lessThan) < 0))
                {'Id': 'a$i', 'Name': nameFor(i), 'Type': 'MusicAlbum'},
          ];
    final end =
        limit == null ? matching.length : (start + limit).clamp(0, matching.length).toInt();
    return {
      'Items': matching.sublist(start.clamp(0, matching.length), end),
      'TotalRecordCount': matching.length,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #getItems:
      case #getAlbumArtists:
        return _page(invocation);
      case #getResumeItems:
        return Future<Map<String, dynamic>>.value({'Items': resume ?? const []});
      case #getLatestItems:
        final parentId = invocation.namedArguments[#parentId] as String?;
        return Future<Map<String, dynamic>>.value(
            {'Items': parentId != null ? (latestBooks ?? const []) : const []});
      case #getItem:
        final id = invocation.positionalArguments.first as String;
        final item = itemsById?[id];
        return item != null
            ? Future<Map<String, dynamic>>.value(item)
            : Future<Map<String, dynamic>>.error(StateError('no item $id'));
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

class _FakeImageApi implements ImageApi {
  @override
  String getPrimaryImageUrl(
    String itemId, {
    int? maxWidth,
    int? maxHeight,
    String? tag,
  }) =>
      'http://fake/Items/$itemId/Images/Primary?tag=$tag';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeUserViewsApi implements UserViewsApi {
  _FakeUserViewsApi(this.views);

  final List<Map<String, dynamic>> views;

  @override
  Future<Map<String, dynamic>> getUserViews({
    bool includeHidden = false,
  }) async =>
      {'Items': views};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeClient implements MediaServerClient {
  _FakeClient(this._itemsApi, {List<Map<String, dynamic>> views = const []})
      : _userViewsApi = _FakeUserViewsApi(views);

  final _FakeItemsApi _itemsApi;
  final _FakeUserViewsApi _userViewsApi;

  @override
  ItemsApi get itemsApi => _itemsApi;

  @override
  UserViewsApi get userViewsApi => _userViewsApi;

  final _imageApi = _FakeImageApi();

  @override
  ImageApi get imageApi => _imageApi;

  @override
  String? get accessToken => null;

  @override
  String get baseUrl => 'http://fake';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeClientFactory implements MediaServerClientFactory {
  _FakeClientFactory(this._client);

  final MediaServerClient _client;

  @override
  Map<String, MediaServerClient> get clients => {'srv': _client};

  @override
  MediaServerClient getActiveClient() => _client;

  @override
  MediaServerClient? getClientIfExists(String serverId) =>
      serverId == 'srv' ? _client : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeBootstrap implements HeadlessSessionBootstrap {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeResumeService implements AudiobookResumeService {
  _FakeResumeService([this.entries = const {}]);

  final Map<String, int> entries;

  @override
  Future<Map<String, int>> loadAll(String serverId) async => entries;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeSessionStore implements LastPlaybackSessionStore {
  _FakeSessionStore([this.kept]);

  /// Kos TV: the last queue, when the test keeps one.
  final LastPlaybackSession? kept;

  @override
  Future<LastPlaybackSession?> load() async => kept;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

MediaBrowseService _service(
  _FakeItemsApi api, {
  List<Map<String, dynamic>> views = const [],
  Map<String, int> localResume = const {},
  LastPlaybackSession? lastSession,
  KostvRestoredStreamGate? streamGate,
}) =>
    MediaBrowseService(
      _FakeClientFactory(_FakeClient(api, views: views)),
      _FakeBootstrap(),
      _FakeResumeService(localResume),
      _FakeSessionStore(lastSession),
      // Kos TV: every song that isn't at home may sound, unless the test
      // says otherwise.
      streamGate: streamGate ?? (_) async => (_) => true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MediaBrowseService car browse', () {
    test('section node renders letter folders without any server call',
        () async {
      final api = _FakeItemsApi(totalItems: 300);
      final service = _service(api);

      final nodes = await service.getChildren('sec|albums|srv');

      expect(nodes.length, 27);
      expect(nodes.first.id, 'sec|albums|srv|az|#');
      expect(nodes.first.title, '#');
      expect(nodes.last.id, 'sec|albums|srv|az|Z');
      expect(nodes.every((n) => n.playable == false), isTrue);
      expect(api.listCalls, 0);
    });

    test('letter folder lists only matching names in a single call',
        () async {
      final api = _FakeItemsApi(totalItems: 1200);
      final service = _service(api);

      final bItems = await service.getChildren('sec|albums|srv|az|B');

      expect(bItems, isNotEmpty);
      expect(bItems.every((i) => i.title.startsWith('B')), isTrue);
      expect(api.listCalls, 1);

      final hashItems = await service.getChildren('sec|albums|srv|az|#');
      expect(hashItems, isNotEmpty);
      expect(hashItems.every((i) => i.title.startsWith('0')), isTrue);
      expect(api.listCalls, 2);
    });

    test('paged host gets exactly the requested window from the cache',
        () async {
      final api = _FakeItemsApi(totalItems: 1200);
      final service = _service(api);

      final all = await service.getChildren('sec|albums|srv|az|B');
      final callsAfterFill = api.listCalls;

      final page1 = await service.getChildren(
        'sec|albums|srv|az|B',
        {_kPage: 1, _kPageSize: 10},
      );
      expect(page1.length, 10);
      expect(page1.first.title, all[10].title);
      expect(api.listCalls, callsAfterFill);

      final pastEnd = await service.getChildren(
        'sec|albums|srv|az|B',
        {_kPage: 999, _kPageSize: 10},
      );
      expect(pastEnd, isEmpty);
      expect(api.listCalls, callsAfterFill);
    });

    test('concurrent requests for one node share a single fetch', () async {
      final api = _FakeItemsApi(
        totalItems: 300,
        delay: const Duration(milliseconds: 10),
      );
      final service = _service(api);

      final results = await Future.wait([
        service.getChildren('sec|albums|srv|az|A'),
        service.getChildren('sec|albums|srv|az|A'),
      ]);

      expect(results[0], isNotEmpty);
      expect(results[0].length, results[1].length);
      expect(api.listCalls, 1);
    });
  });

  group('MediaBrowseService book letter buckets', () {
    final books = <Map<String, dynamic>>[
      {'Id': 'b1', 'Name': 'apple', 'SortName': 'apple', 'Type': 'Audio'},
      {'Id': 'b2', 'Name': 'Banana Saga', 'SortName': 'banana saga', 'Type': 'AudioBook'},
      {'Id': 'b3', 'Name': 'The Hobbit', 'SortName': 'Hobbit, The', 'Type': 'AudioBook'},
      {'Id': 'b4', 'Name': 'Ábba Lives', 'SortName': 'Ábba Lives', 'Type': 'AudioBook'},
      {'Id': 'b5', 'Name': 'Ølavg', 'SortName': 'Ølavg', 'Type': 'AudioBook'},
      {'Id': 'b6', 'Name': 'Яндекс', 'SortName': 'Яндекс', 'Type': 'AudioBook'},
      {'Id': 'b7', 'Name': '中文书', 'SortName': '中文书', 'Type': 'AudioBook'},
      {'Id': 'b8', 'Name': '123 Numbers', 'SortName': '123 Numbers', 'Type': 'AudioBook'},
      {'Id': 'b9', 'Name': 'NoSort Book', 'Type': 'AudioBook'},
    ];

    List<String> bookIds(List<MediaItem> items) =>
        items.map((m) => m.id.split('|').last).toList();

    test('buckets by SortName client-side, case-insensitively', () async {
      final api = _FakeItemsApi(totalItems: 0, books: books);
      final service = _service(api);

      final a = await service.getChildren('sec|booklib|srv|view1|az|A');
      final b = await service.getChildren('sec|booklib|srv|view1|az|B');

      expect(bookIds(a), containsAll(['b1', 'b4'])); // lowercase 'apple' + accented 'Ábba'
      expect(bookIds(b), contains('b2')); // lowercase 'banana saga'
      // One whole-library fetch fills all folders; the sibling is cache-served.
      expect(api.listCalls, 1);
    });

    test('files items by SortName, not display Name', () async {
      final api = _FakeItemsApi(totalItems: 0, books: books);
      final service = _service(api);

      final h = await service.getChildren('sec|booklib|srv|view1|az|H');
      final t = await service.getChildren('sec|booklib|srv|view1|az|T');

      expect(bookIds(h), contains('b3')); // 'Hobbit, The' -> H
      expect(bookIds(t), isNot(contains('b3'))); // not under its Name letter T
    });

    test('accented Latin folds to its base letter', () async {
      final api = _FakeItemsApi(totalItems: 0, books: books);
      final service = _service(api);

      final o = await service.getChildren('sec|booklib|srv|view1|az|O');

      expect(bookIds(o), contains('b5')); // 'Ø' -> O
    });

    test('# is a true catch-all for digits and non-Latin scripts', () async {
      final api = _FakeItemsApi(totalItems: 0, books: books);
      final service = _service(api);

      final hash = await service.getChildren('sec|booklib|srv|view1|az|#');

      expect(bookIds(hash), containsAll(['b6', 'b7', 'b8'])); // Cyrillic, CJK, digit
      expect(bookIds(hash), isNot(contains('b1'))); // A-Z items excluded
      expect(bookIds(hash), isNot(contains('b5'))); // 'Ø' folded to O, not '#'
    });

    test('empty SortName falls back to display Name', () async {
      final api = _FakeItemsApi(totalItems: 0, books: books);
      final service = _service(api);

      final n = await service.getChildren('sec|booklib|srv|view1|az|N');

      expect(bookIds(n), contains('b9'));
    });

    test('a letter bucket is capped at the binder parcel size', () async {
      final many = <Map<String, dynamic>>[
        for (var i = 0; i < 600; i++)
          {'Id': 'x$i', 'Name': 'Aaa $i', 'SortName': 'aaa $i', 'Type': 'AudioBook'},
      ];
      final api = _FakeItemsApi(totalItems: 0, books: many);
      final service = _service(api);

      final a = await service.getChildren('sec|booklib|srv|view1|az|A');

      expect(a.length, 500); // capped for the host, though all 600 were fetched
      expect(api.listCalls, 1);
    });

    test('concurrent distinct letters share one fetch', () async {
      final api = _FakeItemsApi(
        totalItems: 0,
        books: books,
        delay: const Duration(milliseconds: 10),
      );
      final service = _service(api);

      final results = await Future.wait([
        service.getChildren('sec|booklib|srv|view1|az|#'),
        service.getChildren('sec|booklib|srv|view1|az|A'),
      ]);

      expect(results[0], isNotEmpty);
      expect(results[1], isNotEmpty);
      expect(api.listCalls, 1);
    });
  });

  group('MediaBrowseService audiobook tab + home', () {
    final bookViews = [
      {'Id': 'view1', 'CollectionType': 'audiobooks', 'Name': 'Books'},
    ];
    // Any non-empty dataset keeps view1 alive through the content probe.
    final someBooks = [
      {'Id': 'p1', 'Name': 'Probe Book', 'Type': 'AudioBook'},
    ];

    test('books tab uses list hints so art-less letter folders are not grid',
        () async {
      final api = _FakeItemsApi(totalItems: 0, books: someBooks);
      final service = _service(api, views: bookViews);

      final tabs = await service.getChildren(AudioService.browsableRootId);
      final books = tabs.firstWhere((t) => t.id == 'tab|books');

      // List, not grid: grid would render the art-less letter folders as
      // broken-image tiles.
      expect(
        books.extras?[AndroidContentStyle.browsableHintKey],
        AndroidContentStyle.listItemHintValue,
      );
    });

    test('Home is not empty for an audiobook-only user with local resume',
        () async {
      // No music albums, empty server resume: Home used to return "No items".
      final api = _FakeItemsApi(
        totalItems: 0,
        books: someBooks,
        latestBooks: const [
          {'Id': 'nb1', 'Name': 'New Book 1', 'Type': 'AudioBook'},
          {'Id': 'nb2', 'Name': 'New Book 2', 'Type': 'AudioBook'},
        ],
        resume: const [],
        itemsById: const {
          'bk1': {'Id': 'bk1', 'Name': 'In Progress', 'Type': 'AudioBook'},
        },
      );
      final service = _service(api, views: bookViews, localResume: {'bk1': 5000});

      final home = await service.getChildren('tab|home');
      final ids = home.map((m) => m.id).toList();

      expect(home, isNotEmpty);
      // Local in-progress book surfaces as a book leaf (with its resume path).
      expect(ids, contains('book|srv|bk1'));
      // Recently-added audiobooks are shelved (not just MusicAlbum latest).
      expect(ids, containsAll(['book|srv|nb1', 'book|srv|nb2']));
    });

    test('ebook-only library is filtered out and the picker is skipped',
        () async {
      final api = _FakeItemsApi(
        totalItems: 0,
        books: someBooks,
        emptyViews: {'view0'},
      );
      final service = _service(api, views: [
        {'Id': 'view0', 'CollectionType': 'books', 'Name': 'Ebooks'},
        {'Id': 'view1', 'CollectionType': 'audiobooks', 'Name': 'Audio'},
      ]);

      final children = await service.getChildren('tab|books');

      // Only the audio library survives, so tab|books skips the library picker
      // and returns its letter folders directly.
      expect(children.length, 27);
      expect(children.first.id, 'sec|booklib|srv|view1|az|#');
    });

    test('library nodes carry the view Primary image when one exists',
        () async {
      final api = _FakeItemsApi(totalItems: 0, books: someBooks);
      final service = _service(api, views: [
        {
          'Id': 'view1',
          'CollectionType': 'audiobooks',
          'Name': 'With Art',
          'ImageTags': {'Primary': 'tag1'},
        },
        {'Id': 'view2', 'CollectionType': 'audiobooks', 'Name': 'No Art'},
      ]);

      final children = await service.getChildren('tab|books');
      final withArt =
          children.firstWhere((c) => c.id == 'sec|booklib|srv|view1');
      final noArt =
          children.firstWhere((c) => c.id == 'sec|booklib|srv|view2');

      expect(withArt.artUri, isNotNull);
      expect(withArt.artUri.toString(), contains('view1'));
      expect(noArt.artUri, isNull);
    });

    test('recent root returns empty instead of throwing', () async {
      // The fake session store throws on asRecentMediaItems; the host must
      // still get an answer or the resumption card spins.
      final api = _FakeItemsApi(totalItems: 0);
      final service = _service(api);

      final recent = await service.getChildren(AudioService.recentRootId);

      expect(recent, isEmpty);
    });
  });

  // Kos TV: songs that aren't at home are only in the last queue.
  group('MediaBrowseService songs that aren\'t at home', () {
    Map<String, dynamic> stream(String id) => {
      'Id': id,
      'Name': 'Canción $id',
      'Type': 'Audio',
    };
    final session = LastPlaybackSession(
      serverId: 'srv',
      itemIds: const ['h1', 'stremfin:2', 'stremfin:3'],
      index: 1,
      positionMs: 42000,
      title: 'Canción stremfin:2',
      streamItems: {
        'stremfin:2': stream('stremfin:2'),
        'stremfin:3': stream('stremfin:3'),
      },
    );
    MediaBrowseService service() => _service(
      _FakeItemsApi(
        totalItems: 0,
        itemsById: const {
          'h1': {'Id': 'h1', 'Name': 'De casa', 'Type': 'Audio'},
        },
      ),
      lastSession: session,
    );

    test('one tapped plays the last queue from it, from its start', () async {
      final request = await service().resolvePlayRequest(
        'track|srv|stremfin:3|-|-',
      );
      expect(request!.items.map((i) => i.id), [
        'h1',
        'stremfin:2',
        'stremfin:3',
      ]);
      expect(request.startIndex, 2);
      expect(request.startPosition, Duration.zero);
    });

    test('the one it was left on goes on from where it was', () async {
      final request = await service().resolvePlayRequest(
        'track|srv|stremfin:2|-|-',
      );
      expect(request!.startIndex, 1);
      expect(request.startPosition, const Duration(seconds: 42));
    });

    // Kos TV: what the person may hear now, not what they could when the
    // queue was kept.
    test('the restored queue keeps only those that may sound now', () async {
      var asked = 0;
      final request = await _service(
        _FakeItemsApi(
          totalItems: 0,
          itemsById: const {
            'h1': {'Id': 'h1', 'Name': 'De casa', 'Type': 'Audio'},
          },
        ),
        lastSession: session,
        streamGate: (_) async {
          asked++;
          return (song) => song.id != 'stremfin:2';
        },
      ).resolveLastSession(session);
      expect(asked, 1);
      expect(request!.items.map((i) => i.id), ['h1', 'stremfin:3']);
      // The one it was on is gone: from the next that stays, from its start.
      expect(request.startIndex, 1);
      expect(request.startPosition, Duration.zero);
    });

    test('none left after the one it was on: from the first', () async {
      final request = await _service(
        _FakeItemsApi(
          totalItems: 0,
          itemsById: const {
            'h1': {'Id': 'h1', 'Name': 'De casa', 'Type': 'Audio'},
          },
        ),
        lastSession: session,
        streamGate: (_) async => (_) => false,
      ).resolveLastSession(session);
      expect(request!.items.map((i) => i.id), ['h1']);
      expect(request.startIndex, 0);
      expect(request.startPosition, Duration.zero);
    });

    test('a queue of songs at home only asks nothing', () async {
      var asked = 0;
      const home = LastPlaybackSession(
        serverId: 'srv',
        itemIds: ['h1'],
        index: 0,
        positionMs: 1000,
        title: 'De casa',
      );
      final request = await _service(
        _FakeItemsApi(
          totalItems: 0,
          itemsById: const {
            'h1': {'Id': 'h1', 'Name': 'De casa', 'Type': 'Audio'},
          },
        ),
        lastSession: home,
        streamGate: (_) async {
          asked++;
          return (_) => false;
        },
      ).resolveLastSession(home);
      expect(asked, 0);
      expect(request!.items.single.id, 'h1');
      expect(request.startPosition, const Duration(seconds: 1));
    });
  });

  group('kostvRestoredStreamKept', () {
    AggregatedItem song({bool explicit = false}) => kostvStreamItem(
      deezerId: '7',
      title: 'Canción',
      serverId: 'srv',
      artist: 'Lola',
      explicit: explicit,
    );
    bool kept(
      AggregatedItem item, {
      bool catalogAll = true,
      bool kidsMode = false,
      bool hideExplicit = false,
      KostvMusicDislikes dislikes = KostvMusicDislikes.empty,
    }) => kostvRestoredStreamKept(
      item,
      catalogAll: catalogAll,
      kidsMode: kidsMode,
      hideExplicit: hideExplicit,
      dislikes: dislikes,
    );

    test('with all the music and no limit, every one', () {
      expect(kept(song()), isTrue);
      expect(kept(song(explicit: true)), isTrue);
    });

    test('«Solo la de casa» and kids mode: none', () {
      expect(kept(song(), catalogAll: false), isFalse);
      expect(kept(song(), kidsMode: true), isFalse);
    });

    test('with a limit, not the explicit ones', () {
      expect(kept(song(), hideExplicit: true), isTrue);
      expect(kept(song(explicit: true), hideExplicit: true), isFalse);
    });

    test('not one the person doesn\'t want to hear', () {
      final dislikes = KostvMusicDislikes(
        songs: [
          KostvMusicDisliked(
            id: kostvStreamId('7'),
            name: 'Canción',
            deezerId: '7',
          ),
        ],
      );
      expect(kept(song(), dislikes: dislikes), isFalse);
      const byArtist = KostvMusicDislikes(
        artists: [KostvMusicDisliked(id: 'a1', name: 'Lola', artist: true)],
      );
      expect(kept(song(), dislikes: byArtist), isFalse);
    });
  });
}
