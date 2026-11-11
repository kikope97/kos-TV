import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';
import 'package:dio/dio.dart';

import '../../l10n/current_app_localizations.dart';
import '../../preference/detail_section_layout.dart';
import '../../preference/preference_constants.dart';
import '../../preference/user_preferences.dart';
import '../models/aggregated_item.dart';
import '../models/lyrics.dart';
import '../services/blocked_content_gate.dart';
import '../services/row_data_source.dart';
import '../services/series_track_sync.dart';
import '../repositories/item_mutation_repository.dart';
import '../repositories/mdblist_repository.dart';
import '../repositories/tmdb_repository.dart';
import '../utils/blocked_ratings.dart';
import '../utils/episode_cast_utils.dart';
import '../utils/playlist_utils.dart';
import '../../util/episode_playability.dart';
import '../services/plugin_sync_service.dart';
import '../services/user_data_sync.dart';
import 'book_browse_view_model.dart';
import '../models/upcoming_episode_info.dart';
import '../services/upcoming_episode_service.dart';

enum CollectionSortOption {
  server,
  alphabetical,
  releaseAscending,
  releaseDescending,
  custom,
}

/// Lightweight metadata entry used to build and re-sort the flat playlist index
/// without holding full [AggregatedItem] objects in memory.
class _PlaylistItemIndexEntry {
  final String id;
  final String name;
  final DateTime? premiereDate;
  final int? productionYear;

  const _PlaylistItemIndexEntry({
    required this.id,
    required this.name,
    this.premiereDate,
    this.productionYear,
  });

  static int compareReleaseAscending(
    _PlaylistItemIndexEntry a,
    _PlaylistItemIndexEntry b,
  ) {
    final aDate =
        a.premiereDate ??
        (a.productionYear != null ? DateTime(a.productionYear!) : null);
    final bDate =
        b.premiereDate ??
        (b.productionYear != null ? DateTime(b.productionYear!) : null);
    if (aDate == null && bDate == null) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    final byDate = aDate.compareTo(bDate);
    if (byDate != 0) return byDate;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

enum ItemDetailState { loading, ready, blocked, error }

/// Why a delete request failed.
///
/// [detail] is a short status line safe to show the user. The raw response
/// body never travels here because it can leak server paths.
class DeleteItemFailure {
  final int? statusCode;
  final String? detail;

  const DeleteItemFailure({this.statusCode, this.detail});
}

class ParentCollection {
  final String id;
  final String name;

  /// The collection itself as an item, for a grid cell that opens it.
  final AggregatedItem boxSetItem;

  /// The collection's library members, in release order.
  final List<AggregatedItem> items;

  ParentCollection({
    required this.id,
    required this.name,
    required this.boxSetItem,
    required this.items,
  });

  ParentCollection withItems(List<AggregatedItem> updated) =>
      ParentCollection(
        id: id,
        name: name,
        boxSetItem: boxSetItem,
        items: updated,
      );
}

/// Where the detail page's similar-titles list came from, so a section can be
/// named for the source that produced it.
enum SimilarSource { jellyfin, moonfin, tmdb }

// How many cards the More Like This row draws, so every source is asked for
// the same count.
const int _similarLimit = 20;

/// Orders a person's filmography by the person page sort preference. Items
/// with no date at all sink to the bottom whichever way the dates run.
List<AggregatedItem> sortJellyfinFilmography(
  List<AggregatedItem> items,
  String sortOption,
) {
  final sorted = List<AggregatedItem>.from(items);
  if (sortOption == 'alphabetical') {
    return sorted..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  final ascending = sortOption == 'releaseDateAsc';
  sorted.sort((a, b) {
    final dateA =
        a.premiereDate ??
        (a.productionYear != null ? DateTime(a.productionYear!) : null);
    final dateB =
        b.premiereDate ??
        (b.productionYear != null ? DateTime(b.productionYear!) : null);

    if (dateA == null && dateB == null) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    if (dateA == null) return 1;
    if (dateB == null) return -1;

    final comparison = dateA.compareTo(dateB);
    if (comparison != 0) {
      return ascending ? comparison : -comparison;
    }

    final nameComparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return ascending ? nameComparison : -nameComparison;
  });

  return sorted;
}

/// Which engine fills a detail page's "More like this" row.
///
/// The setting's default, Moonfin Recommends, matches genres across the
/// library on the device. On Silo the server's own engine
/// (`/recommendations/similar`, embeddings blended with co-watching) is what
/// Silo's apps show and what the profile's access already shapes, so Moonfin
/// Recommends means Silo's engine there. TMDb Similarity stays TMDb, and kids
/// mode keeps the local algorithm and its parental-rating cap.
@visibleForTesting
RecommendationSystemSource similarItemsSource({
  required RecommendationSystemSource setting,
  required bool kidsMode,
  required ServerType serverType,
}) {
  if (kidsMode) return RecommendationSystemSource.local;
  if (serverType == ServerType.silo &&
      setting == RecommendationSystemSource.local) {
    return RecommendationSystemSource.server;
  }
  return setting;
}

class ItemDetailViewModel extends ChangeNotifier {
  static const _episodeOverviewFields = 'Overview,RunTimeTicks,UserData';

  final MediaServerClient _client;
  final ItemMutationRepository _mutations;
  final MdbListRepository _mdbListRepository;
  final TmdbRepository _tmdbRepository;

  final String itemId;

  /// The season the viewer was browsing when they opened this item. Only set
  /// when it differs from the item's own season, which happens for a special
  /// that DisplaySpecialsWithinSeasons lists inside a regular season.
  final String? contextSeasonId;

  String? _resolvedEpisodesSeasonId;

  /// The season [episodes] was actually loaded from, so callers queue playback
  /// and build links against the list that is on screen.
  String? get effectiveSeasonId {
    final item = _item;
    if (item == null) return _resolvedEpisodesSeasonId ?? contextSeasonId;
    if (item.type == 'Season') return itemId;
    return _resolvedEpisodesSeasonId ?? contextSeasonId ?? item.seasonId;
  }

  ItemDetailState _state = ItemDetailState.loading;
  ItemDetailState get state => _state;

  AggregatedItem? _item;
  AggregatedItem? get item => _item;

  List<AggregatedItem> _seriesBooks = const [];
  List<AggregatedItem> get seriesBooks => _seriesBooks;

  /// The book a series page shows and acts on: the one being read, else the
  /// first unread one, else the first.
  AggregatedItem? get seriesFeaturedBook {
    if (_item?.type != 'BookSeries') return null;
    return _seriesBooks
            .where((book) => (book.playedPercentage ?? 0) > 0 && !book.isPlayed)
            .firstOrNull ??
        _seriesBooks.where((book) => !book.isPlayed).firstOrNull ??
        _seriesBooks.firstOrNull;
  }

  /// A book series is put together from the library's books, so the server
  /// has nothing under its id.
  bool get _isBookSeries => itemId.startsWith('bookSeries:');

  /// What favorite, played and rating changes go to. A series page shows its
  /// featured book, so that's what they change.
  String get _mutationId => seriesFeaturedBook?.id ?? itemId;

  /// The library [book] is filed in, so its series page knows where to look.
  /// The route carries it when the book was opened from its library,
  /// otherwise the book's ancestors do.
  Future<String?> libraryIdOf(AggregatedItem book) async {
    if (_libraryId != null) return _libraryId;
    try {
      final ancestors = await _client.itemsApi.getAncestors(book.id);
      final library = ancestors
          .where((ancestor) => ancestor['Type'] == 'CollectionFolder')
          .firstOrNull;
      return library?['Id']?.toString() ?? book.parentId;
    } catch (_) {
      return book.parentId;
    }
  }

  int? _selectedAudioIndex;
  int? get selectedAudioIndex => _selectedAudioIndex;
  set selectedAudioIndex(int? value) {
    if (_selectedAudioIndex != value) {
      _selectedAudioIndex = value;
      GetIt.instance<UserPreferences>().setItemAudioStreamIndex(itemId, value);
      notifyListeners();
    }
  }

  int? _selectedSubtitleIndex;
  int? get selectedSubtitleIndex => _selectedSubtitleIndex;
  set selectedSubtitleIndex(int? value) {
    if (_selectedSubtitleIndex != value) {
      _selectedSubtitleIndex = value;
      GetIt.instance<UserPreferences>().setItemSubtitleStreamIndex(itemId, value);
      notifyListeners();
    }
  }

  List<AggregatedItem> _similar = const [];
  List<AggregatedItem> get similar => _similar;
  List<TmdbReview> _reviews = const [];
  List<TmdbReview> get reviews => _reviews;
  bool _similarInitialLoadComplete = false;
  bool get similarInitialLoadComplete => _similarInitialLoadComplete;

  SimilarSource _similarSource = SimilarSource.jellyfin;

  /// Where [similar] came from, for a label that matches the list.
  SimilarSource get similarSource => _similarSource;

  List<AggregatedItem> _filmography = const [];
  List<AggregatedItem> get filmography => _filmography;

  TmdbPersonAccounts? _personAccounts;
  TmdbPersonAccounts? get personAccounts => _personAccounts;

  List<AggregatedItem> _seasons = const [];
  List<AggregatedItem> get seasons => _seasons;

  bool _seasonsLoaded = false;

  /// Whether the seasons fetch has finished, however it went. An empty
  /// [seasons] says nothing on its own until this is true, so callers can tell
  /// a load still in flight from a series that really has none.
  bool get seasonsLoaded => _seasonsLoaded;

  List<AggregatedItem> _episodes = const [];
  List<AggregatedItem> get episodes => _episodes;

  bool _episodesLoaded = false;

  /// The [seasonsLoaded] contract, for [episodes].
  bool get episodesLoaded => _episodesLoaded;

  List<AggregatedItem> _seriesEpisodes = const [];
  bool _seriesEpisodesRequested = false;
  bool _seriesEpisodesLoaded = false;

  /// Whether [seriesEpisodes] has arrived. Unlike [seasonsLoaded] this only
  /// turns true on a fetch that worked, because a failed one is tried again.
  bool get seriesEpisodesLoaded => _seriesEpisodesLoaded;

  /// All episodes of a Series across every season, in the server's
  /// season/episode order. Empty until [loadAllSeriesEpisodes] completes.
  List<AggregatedItem> get seriesEpisodes => _seriesEpisodes;

  /// Compares two episodes by season ([AggregatedItem.parentIndexNumber]),
  /// episode number ([AggregatedItem.indexNumber]), and finally [AggregatedItem.name]
  /// as a tie-breaker.
  static int compareEpisodes(AggregatedItem a, AggregatedItem b) {
    final sa = a.parentIndexNumber ?? 0;
    final sb = b.parentIndexNumber ?? 0;
    if (sa != sb) return sa.compareTo(sb);
    final ea = a.indexNumber ?? 0;
    final eb = b.indexNumber ?? 0;
    if (ea != eb) return ea.compareTo(eb);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Compares two special features by index number ([AggregatedItem.indexNumber]),
  /// and finally [AggregatedItem.name] as a tie-breaker.
  static int compareFeatures(AggregatedItem a, AggregatedItem b) {
    final ea = a.indexNumber ?? 0;
    final eb = b.indexNumber ?? 0;
    if (ea != eb) return ea.compareTo(eb);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  AggregatedItem? _nextUp;
  AggregatedItem? get nextUp => _nextUp;

  /// Counts Next Up requests, so an older answer that arrives late can't
  /// replace the one a refresh asked for after it.
  int _nextUpRequest = 0;

  Map<String, double> _ratings = const {};
  Map<String, double> get ratings => _ratings;

  List<AggregatedItem> _albums = const [];
  List<AggregatedItem> get albums => _albums;

  List<AggregatedItem> _tracks = const [];
  List<AggregatedItem> get tracks => _tracks;

  List<AggregatedItem> _collectionItems = const [];
  List<AggregatedItem> get collectionItems => _collectionItems;

  // --- Collection grid pagination state ---
  static const _collectionPageSize = 50;

  /// Items fetched so far for the grid (startIndex).
  int _collectionFetchedCount = 0;
  int _collectionTotalCount = 0;
  bool _collectionHasMore = false;
  bool _collectionLoadingMore = false;

  // --- Playlist index ---

  /// How much of a collection the index scan will walk. Past this the playlist
  /// tab covers the head rather than the whole thing.
  static const _indexScanLimit = 2000;

  /// How many series are asked for their episodes at once during the scan.
  static const _indexScanBatchSize = 8;

  /// Member types that play on their own. A series is swapped for its episodes.
  static const _playableTypes = {'Movie', 'Audio', 'Video', 'MusicVideo', 'Episode'};

  /// True while the index is being built. The playlist area shows a spinner.
  bool _playlistIndexBuilding = false;
  bool get playlistIndexBuilding => _playlistIndexBuilding;
  bool _playlistFallbackTriggered = false;
  bool _playlistSortRefreshing = false;
  bool get playlistSortRefreshing => _playlistSortRefreshing;

  /// The id and sort keys of every playable item in the order the server lists
  /// them, kept so the order can change without fetching anything again. Null
  /// until the collection is scanned.
  List<_PlaylistItemIndexEntry>? _playlistIndexEntries;

  /// Ids in the order the playlist currently shows, which pages are read from.
  List<String>? _flattenedIds;
  List<String>? get flattenedIds => _flattenedIds;

  /// Ids in the order the user arranged them, either dragged here or saved on
  /// the server. Kept apart from [_flattenedIds] so switching to another sort
  /// and back doesn't lose it.
  List<String>? _customOrderIds;

  // --- Playlist page loading ---
  static const _playlistPageSize = 50;
  int _playlistFetchedCount = 0;
  bool _playlistHasMore = false;
  bool _playlistLoadingMore = false;

  bool get playlistLoadingMore => _playlistLoadingMore;

  // Cached BoxSet cast/crew, rebuilt only when _collectionItems changes.
  List<AggregatedItem>? _boxSetPeopleSource;
  List<Map<String, dynamic>> _boxSetDirectors = const [];
  List<Map<String, dynamic>> _boxSetWriters = const [];
  List<Map<String, dynamic>> _boxSetActors = const [];

  void _ensureBoxSetPeople() {
    if (identical(_boxSetPeopleSource, _collectionItems)) return;
    _boxSetPeopleSource = _collectionItems;

    final directors = <Map<String, dynamic>>[];
    final writers = <Map<String, dynamic>>[];
    final actors = <Map<String, dynamic>>[];
    final dirNames = <String>{};
    final writNames = <String>{};
    final actorNames = <String>{};

    for (final child in _collectionItems) {
      final people = child.rawData['People'] as List?;
      if (people == null) continue;
      for (final person in people.cast<Map<String, dynamic>>()) {
        final name = person['Name'] as String?;
        if (name == null) continue;
        switch (person['Type']) {
          case 'Director':
            if (dirNames.add(name)) directors.add(person);
          case 'Writer':
            if (writNames.add(name)) writers.add(person);
        }
      }
    }
    for (final child in _collectionItems) {
      final people = child.rawData['People'] as List?;
      if (people == null) continue;
      for (final person in people.cast<Map<String, dynamic>>()) {
        final type = person['Type'] as String?;
        if (type != 'Actor' && type != 'GuestStar') continue;
        final name = person['Name'] as String?;
        if (name == null ||
            dirNames.contains(name) ||
            writNames.contains(name)) {
          continue;
        }
        if (actorNames.add(name)) actors.add(person);
      }
    }

    _boxSetDirectors = directors;
    _boxSetWriters = writers;
    _boxSetActors = actors;
  }

  List<AggregatedItem> _playlistItems = const [];
  List<AggregatedItem> get playlistItems => _playlistItems;

  /// What the collection's Playlist tab shows. Until the playlist has items,
  /// that's the collection's own playable members.
  List<AggregatedItem> get collectionPlaylistItems => _playlistItems.isNotEmpty
      ? _playlistItems
      : _collectionItems.where((i) => _playableTypes.contains(i.type)).toList();

  CollectionSortOption _collectionSort = CollectionSortOption.server;
  CollectionSortOption get collectionSort => _collectionSort;

  List<ParentCollection> _parentCollections = const [];
  List<ParentCollection> get parentCollections => _parentCollections;

  List<AggregatedItem> _features = const [];
  List<AggregatedItem> get features => _features;

  LyricsData _lyrics = LyricsData.empty;
  LyricsData get lyrics => _lyrics;

  Object? _error;
  Object? get error => _error;

  ImageApi get imageApi => _client.imageApi;
  String get baseUrl => _client.baseUrl;
  bool get supportsNumericUserRatings =>
      _client.userLibraryApi.supportsNumericUserRatings;

  bool get supportsPersonalRating => _client.features.supportsPersonalRatings;

  bool get supportsPersonFavorites => _client.features.supportsPersonFavorites;

  /// Plex keeps no YouTube links, so a trailer it doesn't have is searched
  /// for on YouTube instead.
  bool get searchesYouTubeForTrailer =>
      !_client.features.supportsRemoteTrailers;

  /// Whether this collection's cards offer "Remove from collection". A
  /// server can limit editing to some collections (Silo: the profile's own
  /// manual ones). Otherwise any collection page offers it.
  bool get canRemoveFromCollection {
    final collection = _item;
    if (collection == null || collection.type != 'BoxSet') return false;
    final api = _client.itemsApi;
    return api is! EditableCollectionsApi ||
        (api as EditableCollectionsApi).canEditCollection(collection.rawData);
  }

  bool _isRatingMutationInProgress = false;
  bool get isRatingMutationInProgress => _isRatingMutationInProgress;

  bool get canManagePlaylistTracks =>
      _item?.type == 'Playlist' &&
      _tracks.isNotEmpty &&
      _tracks.every(hasPlaylistEntryId);

  final String? _serverId;
  final String? _libraryId;
  bool _isDisposed = false;

  /// What the server probed in place of the item's placeholder source, kept so
  /// a reload of the item doesn't put the placeholder back.
  List<Map<String, dynamic>>? _probedMediaSources;

  /// Longest the action row waits on its late inputs. Long enough for the
  /// server's own lookups, short enough that the row still feels instant.
  static const actionsWaitCap = Duration(milliseconds: 250);

  /// Whether everything that adds, removes or relabels an action button has
  /// come back (or [actionsWaitCap] ran out), so the row can show complete
  /// rather than gaining a button a moment later. Stays true for reloads of
  /// the same item, so switching version doesn't hide the row again.
  bool _actionsSettled = false;
  bool get actionsSettled => _actionsSettled;

  UpcomingEpisodeInfo? _upcomingEpisode;
  UpcomingEpisodeInfo? get upcomingEpisode => _upcomingEpisode;

  ItemDetailViewModel({
    required this.itemId,
    String? serverId,
    this.contextSeasonId,
    required MediaServerClient client,
    required ItemMutationRepository mutations,
    required MdbListRepository mdbListRepository,
    required TmdbRepository tmdbRepository,
    String? libraryId,
  }) : _serverId = serverId,
       _libraryId = libraryId,
       _client = client,
       _mutations = mutations,
       _mdbListRepository = mdbListRepository,
       _tmdbRepository = tmdbRepository {
    userDataSync.addListener(_onUserDataChanged);
  }

  /// Whether anything this page shows has been watched, favourited or rated
  /// since it was loaded. [syncUserDataIfStale] clears it, which is what
  /// catches the series' own state after an episode of it was played.
  bool _userDataStale = false;
  bool _syncingUserData = false;

  void _onUserDataChanged() {
    if (_isDisposed) return;
    var changed = false;

    final item = userDataSync.applyOrNull(_item);
    if (!identical(item, _item)) {
      _item = item;
      changed = true;
    }
    final nextUp = userDataSync.applyOrNull(_nextUp);
    if (!identical(nextUp, _nextUp)) {
      final justPlayed =
          _nextUp?.isPlayed == false && nextUp?.isPlayed == true;
      _nextUp = nextUp;
      changed = true;
      // A played mark only lands here once the server has it, so the next
      // episode can be fetched right away, even when marked from this page.
      if (justPlayed && !_syncingUserData && _item?.type == 'Series') {
        unawaited(_loadNextUp());
      }
    }

    List<AggregatedItem> patch(List<AggregatedItem> list) {
      final patched = userDataSync.applyAll(list);
      if (!identical(patched, list)) changed = true;
      return patched;
    }

    _episodes = patch(_episodes);
    _seriesEpisodes = patch(_seriesEpisodes);
    _seasons = patch(_seasons);
    _similar = patch(_similar);
    _filmography = patch(_filmography);
    _albums = patch(_albums);
    _tracks = patch(_tracks);
    _collectionItems = patch(_collectionItems);
    _playlistItems = patch(_playlistItems);
    _features = patch(_features);
    _seriesBooks = patch(_seriesBooks);
    final collections = [..._parentCollections];
    var collectionsChanged = false;
    for (var i = 0; i < collections.length; i++) {
      final items = patch(collections[i].items);
      if (identical(items, collections[i].items)) continue;
      collections[i] = collections[i].withItems(items);
      collectionsChanged = true;
    }
    if (collectionsChanged) _parentCollections = collections;

    if (changed) notifyListeners();
    if (!_syncingUserData) _userDataStale = true;
  }

  /// Does nothing until a change has actually been recorded, so coming back to
  /// the page normally costs no request.
  Future<void> syncUserDataIfStale() async {
    if (_isDisposed || _syncingUserData || !_userDataStale) return;
    final ids = <String>{
      if (!_isBookSeries) itemId,
      if (_nextUp != null) _nextUp!.id,
      for (final list in [
        _episodes,
        _seriesEpisodes,
        _seasons,
        _similar,
        _filmography,
        _albums,
        _tracks,
        _collectionItems,
        _playlistItems,
        _features,
        _seriesBooks,
      ])
        for (final item in list) item.id,
      for (final collection in _parentCollections)
        for (final item in collection.items) item.id,
    };
    _syncingUserData = true;
    try {
      await userDataSync.refreshFromServer(_client, ids);
    } finally {
      _syncingUserData = false;
      _userDataStale = false;
    }
    // A change to an episode's watched state can move the series on, and
    // only the server knows which episode comes next.
    if (!_isDisposed && _item?.type == 'Series') await _loadNextUp();
  }

  Future<void> load({String? mediaSourceId}) async {
    _similarInitialLoadComplete = false;
    _state = ItemDetailState.loading;
    _castLoadGeneration++;
    _parentActors = const [];
    _collectionItems = const [];
    _parentCollections = const [];
    _flattenedIds = null;
    _customOrderIds = null;
    _playlistIndexEntries = null;
    _collectionFetchedCount = 0;
    _collectionTotalCount = 0;
    _collectionHasMore = false;
    _collectionLoadingMore = false;
    _playlistIndexBuilding = false;
    _playlistFallbackTriggered = false;
    _playlistSortRefreshing = false;
    _playlistFetchedCount = 0;
    _playlistHasMore = false;
    _playlistLoadingMore = false;
    _playlistItems = const [];
    notifyListeners();

    try {
      if (_isBookSeries && _libraryId != null) {
        final series = await BookBrowseViewModel(
          libraryId: _libraryId,
          dataSource: GetIt.instance<RowDataSource>(),
          client: _client,
        ).loadSeries(itemId.substring('bookSeries:'.length));
        if (series == null) {
          throw Exception(currentAppLocalizations().seriesNotFound);
        }
        _seriesBooks = series.books;
        _item = series.series;
      } else {
        final data = await _client.itemsApi.getItem(itemId, mediaSourceId: mediaSourceId);
        final candidate = AggregatedItem(
          id: itemId,
          serverId: _serverId ?? _client.baseUrl,
          rawData: data,
        );
        // Checked before the item is published and before the secondary loads
        // fan out, so nothing downstream can read the title and nothing goes
        // off fetching episodes for a page that will never be shown. No gate
        // registered means a boot ordering this knows nothing about, and
        // refusing the screen outright would be worse than the gap.
        final gate = GetIt.instance.isRegistered<BlockedContentGate>()
            ? GetIt.instance<BlockedContentGate>()
            : null;
        if (gate != null && await gate.isBlocked(candidate)) {
          _item = null;
          _state = ItemDetailState.blocked;
          notifyListeners();
          return;
        }
        gate?.observe(candidate);
        _item = candidate;
      }
      _lyrics = LyricsData.empty;
      final prefs = GetIt.instance<UserPreferences>();
      final savedSubIndex = prefs.getItemSubtitleStreamIndex(itemId);
      _selectedSubtitleIndex = savedSubIndex == -2 ? null : savedSubIndex;
      final savedAudioIndex = prefs.getItemAudioStreamIndex(itemId);
      _selectedAudioIndex = savedAudioIndex == -2 ? null : savedAudioIndex;
      _state = ItemDetailState.ready;
      notifyListeners();

      _loadSecondary();
    } catch (e) {
      _error = e;
      _state = ItemDetailState.error;
      notifyListeners();
    }
  }

  static const _probedSourceTypes = {
    'Movie',
    'Episode',
    'Video',
    'MusicVideo',
    'Trailer',
  };

  bool _hasPlaceholderSource(Map<String, dynamic> data) {
    if (!_probedSourceTypes.contains(data['Type'])) return false;
    final sources = data['MediaSources'];
    if (sources is! List || sources.length != 1) return false;
    final first = sources.first;
    return first is Map &&
        MediaStreamResolver.isStreamlessStaticSource(
          data,
          first['Id']?.toString(),
        );
  }

  /// [data] with its placeholder source swapped for the probed ones, once
  /// they are known.
  Map<String, dynamic> _withProbedSources(Map<String, dynamic> data) {
    final probed = _probedMediaSources;
    if (probed == null || !_hasPlaceholderSource(data)) return data;
    return <String, dynamic>{...data, 'MediaSources': probed};
  }

  /// A channel item, like one from a plugin's virtual library, comes with a
  /// bare placeholder source: no streams, no size, a link for a file name.
  /// The server only probes the real file for PlaybackInfo, so the page asks
  /// for it and shows that source instead.
  Future<void> _loadProbedMediaSources() async {
    final item = _item;
    if (item == null || !_hasPlaceholderSource(item.rawData)) return;
    try {
      final info = await _client.playbackApi.getPlaybackInfo(
        itemId,
        requestBody: PlaybackInfoRequest(
          itemId: itemId,
          autoOpenLiveStream: false,
        ).toJson(),
        userId: _client.userId,
      );
      final probed = (info['MediaSources'] as List?)
              ?.whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .where((s) => (s['MediaStreams'] as List?)?.isNotEmpty ?? false)
              .toList() ??
          const <Map<String, dynamic>>[];
      if (probed.isEmpty || _isDisposed) return;
      _probedMediaSources = probed;
      final current = _item;
      if (current == null || current.id != item.id) return;
      _item = AggregatedItem(
        id: current.id,
        serverId: current.serverId,
        rawData: _withProbedSources(current.rawData),
      );
      notifyListeners();
    } catch (_) {}
  }

  /// Copies the series' audio and subtitle choice that Silo keeps into this
  /// device's settings before anything plays.
  Future<void> _syncSeriesTrackChoices() async {
    final item = _item;
    if (item == null) return;
    final seriesId = item.type == 'Series' ? item.id : item.seriesId;
    if (seriesId == null || seriesId.isEmpty) return;
    final changed = await syncSeriesTrackChoices(
      _client,
      seriesId,
      GetIt.instance<UserPreferences>(),
    );
    if (changed && !_isDisposed) notifyListeners();
  }

  Future<void> _loadSecondary() async {
    final type = _item?.type;
    final futures = <Future>[];
    // The loads that change which action buttons show or what they say. Only
    // quick ones belong here: parent collections stay out, since finding them
    // can mean scanning every collection in the library.
    final actionInputs = <Future>[];
    Future<void> forActions(Future<void> load) {
      actionInputs.add(load);
      return load;
    }

    unawaited(forActions(_loadProbedMediaSources()));
    if (type == 'Person') {
      futures.add(_loadFilmography());
      futures.add(forActions(_loadPersonAccounts()));
    } else if (type == 'Series') {
      unawaited(_loadReviews());
      unawaited(_syncSeriesTrackChoices());
      futures.add(_loadRatings());
      futures.add(forActions(_loadSeasons()));
      futures.add(forActions(_loadNextUp()));
      futures.add(_loadSimilar());
      futures.add(forActions(_loadFeatures()));
      futures.add(_loadParentCollection());
      unawaited(_loadUpcomingEpisode());
    } else if (type == 'Season') {
      unawaited(_syncSeriesTrackChoices());
      futures.add(_loadRatings());
      futures.add(forActions(_loadEpisodes()));
      futures.add(_loadSeasonCast());
      futures.add(forActions(_loadFeatures()));
    } else if (type == 'Episode') {
      unawaited(_syncSeriesTrackChoices());
      futures.add(_loadRatings());
      futures.add(_loadEpisodes());
      futures.add(_loadParentCast());
      futures.add(_loadSimilar());
      futures.add(forActions(_loadFeatures()));
    } else if (type == 'MusicArtist') {
      futures.add(forActions(_loadAlbums()));
      futures.add(forActions(_loadTracks(artistId: itemId)));
      futures.add(_loadSimilar());
    } else if (type == 'MusicAlbum' || type == 'Playlist') {
      futures.add(forActions(_loadTracks()));
    } else if (type == 'AudioBook') {
      futures.add(_loadRatings());
      futures.add(_loadSimilar());
    } else if (type == 'Audio') {
      futures.add(_loadLyrics());
    } else if (type == 'BoxSet') {
      futures.add(forActions(_loadCollectionItems()));
      futures.add(_buildPlaylistIndex());  // playlist — Phase 1, runs concurrently
    } else if (type == 'MusicVideo' ||
        type == 'Movie' ||
        type == 'Trailer' ||
        type == 'Video') {
      futures.add(_loadRatings());
      futures.add(_loadSimilar());
      futures.add(forActions(_loadFeatures()));
      if (type != 'MusicVideo') {
        futures.add(_loadParentCollection());
      }
      if (type == 'Movie') unawaited(_loadReviews());
    } else {
      futures.add(_loadRatings());
      futures.add(_loadSimilar());
    }
    unawaited(_settleActions(actionInputs));
    await Future.wait(futures);
  }

  Future<void> _settleActions(List<Future> inputs) async {
    if (!_actionsSettled) {
      // Each input swallows its own error: Future.wait gives up on the first
      // one, which would show the row before the slower inputs are back.
      try {
        await Future.wait(
          inputs.map((f) => f.catchError((_) {})),
        ).timeout(actionsWaitCap);
      } catch (_) {}
    }
    if (_isDisposed || _actionsSettled) return;
    _actionsSettled = true;
    notifyListeners();
  }

  Future<void> _loadSeasons() async {
    try {
      final data = await _client.itemsApi.getSeasons(
        itemId,
        fields: 'ChildCount,UserData',
      );
      final items = (data['Items'] as List?) ?? [];
      _seasons = _mapItems(items, fallbackRating: _item?.officialRating);
    } catch (_) {
    } finally {
      _seasonsLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _loadEpisodes() async {
    final item = _item;
    if (item == null) return;
    final seriesId = item.seriesId ?? itemId;
    final ownSeasonId = item.type == 'Season' ? itemId : item.seasonId;
    final requestedSeasonId = item.type == 'Season'
        ? itemId
        : (contextSeasonId ?? item.seasonId);
    try {
      Future<List<AggregatedItem>> episodesOf(String? seasonId) async {
        final data = await _client.itemsApi.getEpisodes(
          seriesId,
          seasonId: seasonId,
          fields: _episodeOverviewFields,
        );
        return _mapItems(
          (data['Items'] as List?) ?? [],
          fallbackRating: _item?.officialRating,
        );
      }

      var seasonId = requestedSeasonId;
      var episodes = await episodesOf(seasonId);

      // The browsed season only holds this item while the server inlines
      // specials. A stale link, or an offline catalogue that files specials
      // strictly under season 0, leaves it out — fall back to its own season
      // rather than stranding the page on a list it does not appear in.
      // Without a season to fall back to there is nothing better to ask for:
      // a null season id would fetch every episode of the series.
      if (ownSeasonId != null &&
          seasonId != ownSeasonId &&
          !episodes.any((e) => e.id == itemId)) {
        seasonId = ownSeasonId;
        episodes = await episodesOf(ownSeasonId);
      }

      _resolvedEpisodesSeasonId = seasonId;
      _episodes = episodes;
    } catch (_) {
    } finally {
      _episodesLoaded = true;
      notifyListeners();
    }
  }

  /// Loads every episode of the current Series (all seasons) on demand. Used by
  /// the Modern and Nouveau detail layout's Episodes tab, accurate season counts,
  /// and the Spotlight More Episodes modal. No-op once already loaded.
  Future<void> loadAllSeriesEpisodes() async {
    final item = _item;
    if (item == null) return;
    final seriesId = item.type == 'Series' ? itemId : item.seriesId;
    if (seriesId == null || seriesId.isEmpty) return;
    if (_seriesEpisodesRequested) return;
    _seriesEpisodesRequested = true;
    try {
      final data = await _client.itemsApi.getEpisodes(
        seriesId,
        fields: _episodeOverviewFields,
      );
      final items = (data['Items'] as List?) ?? [];
      _seriesEpisodes = _mapItems(
        items,
        fallbackRating: _item?.officialRating,
      );
      _seriesEpisodesLoaded = true;
      notifyListeners();
    } catch (_) {
      // Left unloaded and silent on purpose. The Modern layout calls this from
      // build, so the next rebuild gets another go, and notifying here would
      // turn that into a loop against a server that is down.
      _seriesEpisodesRequested = false;
    }
  }

  Future<void> refreshSeriesEpisodes() {
    _seriesEpisodesRequested = false;
    _seriesEpisodesLoaded = false;
    return loadAllSeriesEpisodes();
  }

  int _castLoadGeneration = 0;
  List<Map<String, dynamic>> _parentActors = const [];
  List<Map<String, dynamic>> get parentActors => _parentActors;

  Future<void> _loadParentCast() async {
    final item = _item;
    if (item == null) return;
    final generation = ++_castLoadGeneration;
    final actors = await resolveParentCast(
      client: _client,
      seasonId: item.seasonId,
      seriesId: item.seriesId,
    );
    if (_isDisposed || generation != _castLoadGeneration || actors.isEmpty) return;
    _parentActors = actors;
    notifyListeners();
  }

  Future<void> _loadSeasonCast() async {
    final item = _item;
    if (item == null) return;
    final hasActors = item.people.any((p) {
      final t = p['Type'] as String?;
      return t == 'Actor' || t == 'GuestStar';
    });
    if (hasActors) return;
    final generation = ++_castLoadGeneration;
    final actors = await resolveParentCast(
      client: _client,
      seriesId: item.seriesId,
    );
    if (_isDisposed || generation != _castLoadGeneration || actors.isEmpty) return;
    _parentActors = actors;
    notifyListeners();
  }

  Future<void> _loadNextUp() async {
    final request = ++_nextUpRequest;
    AggregatedItem? nextUp;
    try {
      final data = await _client.itemsApi.getNextUp(
        seriesId: itemId,
        limit: 1,
        fields: _episodeOverviewFields,
      );
      final items = (data['Items'] as List?) ?? [];
      if (items.isNotEmpty) {
        final raw = items.first as Map<String, dynamic>;
        final candidate = AggregatedItem(
          id: raw['Id']?.toString() ?? '',
          serverId: _serverId ?? _client.baseUrl,
          rawData: raw,
        );
        if (isEligibleNextEpisodeCandidate(candidate)) {
          nextUp = candidate;
        }
      }
    } catch (_) {
      // A failed refresh keeps the Next Up already shown.
      return;
    }

    if (_isDisposed || request != _nextUpRequest) return;
    final previousId = _nextUp?.id;
    _nextUp = nextUp;
    if (previousId != _nextUp?.id) {
      notifyListeners();
    }
  }

  /// [fallbackRating] is the rating to judge an item by when it carries none of
  /// its own, which is the normal case for an episode under a rated series.
  /// Without it, blocking a rating hides the series everywhere and leaves its
  /// episodes listed and playable underneath.
  List<AggregatedItem> _mapItems(List items, {String? fallbackRating}) {
    final mapped = items
        .cast<Map<String, dynamic>>()
        .map(
          (raw) => AggregatedItem(
            id: raw['Id']?.toString() ?? '',
            serverId: _serverId ?? _client.baseUrl,
            rawData: raw,
          ),
        )
        .toList();
    return withoutBlockedItems(mapped, fallbackRating: fallbackRating);
  }

  Future<void> _loadAlbums() async {
    try {
      final data = await _client.itemsApi.getItems(
        artistIds: [itemId],
        includeItemTypes: ['MusicAlbum'],
        sortBy: 'ProductionYear,SortName',
        sortOrder: 'Descending',
        recursive: true,
        fields: 'PrimaryImageAspectRatio,BasicSyncInfo',
      );
      final items = (data['Items'] as List?) ?? [];
      _albums = _mapItems(items);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadTracks({String? artistId}) async {
    try {
      final data = _item?.type == 'Playlist'
          ? await _client.itemsApi.getPlaylistItems(itemId)
          : artistId != null
          ? await _client.itemsApi.getItems(
              artistIds: [artistId],
              includeItemTypes: ['Audio'],
              sortBy: 'Album,ParentIndexNumber,IndexNumber,SortName',
              recursive: true,
              fields: 'PrimaryImageAspectRatio,BasicSyncInfo',
            )
          : await _client.itemsApi.getItems(
              parentId: itemId,
              includeItemTypes: ['Audio'],
              sortBy: 'ParentIndexNumber,IndexNumber,SortName',
              fields: 'PrimaryImageAspectRatio,BasicSyncInfo',
            );
      final items = (data['Items'] as List?) ?? [];
      _tracks = _mapItems(items);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadLyrics() async {
    try {
      final data = await _client.itemsApi.getLyrics(itemId);
      _lyrics = LyricsData.fromJson(data);
      notifyListeners();
    } catch (_) {
      _lyrics = LyricsData.empty;
      notifyListeners();
    }
  }

  String? _playlistEntryId(AggregatedItem track) =>
      track.rawData['PlaylistItemId']?.toString();

  Future<void> removeTrackFromPlaylist(AggregatedItem track) async {
    if (_item?.type != 'Playlist') return;
    final entryId = _playlistEntryId(track);
    if (entryId == null) return;

    final previousTracks = List<AggregatedItem>.from(_tracks);
    _tracks = _tracks.where((t) {
      final sameId = t.id == track.id;
      final sameEntry = _playlistEntryId(t) == entryId;
      return !(sameId && sameEntry);
    }).toList();
    notifyListeners();

    try {
      await _client.itemsApi.removeFromPlaylist(itemId, [entryId]);
      await _loadTracks();
      await _reload();
    } catch (_) {
      _tracks = previousTracks;
      notifyListeners();
    }
  }

  Future<void> reorderPlaylistTrack(int oldIndex, int newIndex) async {
    if (_item?.type != 'Playlist') return;
    if (oldIndex < 0 || oldIndex >= _tracks.length) {
      return;
    }
    final targetIndex = newIndex;
    if (targetIndex < 0 || targetIndex >= _tracks.length) {
      return;
    }

    final moved = _tracks[oldIndex];
    final entryId = _playlistEntryId(moved);
    if (entryId == null) return;

    final previousTracks = List<AggregatedItem>.from(_tracks);
    final reordered = List<AggregatedItem>.from(_tracks);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(targetIndex, item);
    _tracks = reordered;
    notifyListeners();

    try {
      await _client.itemsApi.movePlaylistItem(itemId, entryId, targetIndex);
      await _loadTracks();
    } catch (_) {
      _tracks = previousTracks;
      notifyListeners();
    }
  }

  Future<void> renamePlaylist(String name) async {
    final item = _item;
    if (item == null || item.type != 'Playlist') return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == item.name) return;

    final previous = item.name;
    final patched = Map<String, dynamic>.from(item.rawData)..['Name'] = trimmed;
    _item = AggregatedItem(
      id: item.id,
      serverId: item.serverId,
      rawData: patched,
    );
    notifyListeners();

    try {
      await _client.itemsApi.renamePlaylist(itemId, trimmed);
      await _reload();
    } catch (_) {
      final reverted = Map<String, dynamic>.from(item.rawData)
        ..['Name'] = previous;
      _item = AggregatedItem(
        id: item.id,
        serverId: item.serverId,
        rawData: reverted,
      );
      notifyListeners();
    }
  }

  /// Returns `null` when the item was deleted, otherwise why it failed.
  Future<DeleteItemFailure?> deleteItem() async {
    try {
      await _client.itemsApi.deleteItem(itemId);
      return null;
    } catch (e) {
      if (e is DioException) {
        // The body can be an HTML error page or JSON holding server paths, so
        // it gets logged instead of shown.
        debugPrint('[ItemDetailViewModel] Delete failed: ${e.response?.data}');
        return DeleteItemFailure(
          statusCode: e.response?.statusCode,
          detail: e.response?.statusMessage ?? e.message,
        );
      }
      debugPrint('[ItemDetailViewModel] Delete failed: $e');
      return const DeleteItemFailure();
    }
  }

  /// Reorders the whole index and starts the list again from the top.
  ///
  /// Only a slice of the collection is loaded, so re-sorting what is on screen
  /// would leave it holding one ordering while later pages arrive in another.
  Future<void> setCollectionSort(CollectionSortOption option) async {
    if (_collectionSort == option) return;
    _collectionSort = option;
    _playlistSortRefreshing = true;
    notifyListeners();
    try {
      // A saved order arrives ready to use, so the scan is only worth paying for
      // when the sort actually needs the keys.
      if (option != CollectionSortOption.custom) {
        await _ensurePlaylistIndexEntries();
      }
      _rebuildFlattenedIds();
      _resetPlaylistPaging();
      notifyListeners();
      await loadMorePlaylistItems();
    } finally {
      _playlistSortRefreshing = false;
      notifyListeners();
    }
  }

  /// Points [_flattenedIds] at the active sort. Every option lands here, so the
  /// index and the pages fetched from it can never describe different orders.
  void _rebuildFlattenedIds() {
    if (_collectionSort == CollectionSortOption.custom) {
      final custom = _customOrderIds;
      // Copied, so a later drag can't edit the saved order underneath itself.
      if (custom != null) _flattenedIds = List<String>.from(custom);
      return;
    }
    final entries = _playlistIndexEntries;
    if (entries == null || entries.isEmpty) return;
    // Sorted as a copy, so the entries keep the order the server gave them.
    final sorted = [...entries];
    switch (_collectionSort) {
      case CollectionSortOption.alphabetical:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case CollectionSortOption.releaseAscending:
        sorted.sort(_PlaylistItemIndexEntry.compareReleaseAscending);
      case CollectionSortOption.releaseDescending:
        sorted.sort(
          (a, b) => _PlaylistItemIndexEntry.compareReleaseAscending(b, a),
        );
      case CollectionSortOption.server || CollectionSortOption.custom:
        break;
    }
    final seenIds = <String>{};
    _flattenedIds = [
      for (final e in sorted)
        if (seenIds.add(e.id)) e.id,
    ];
  }

  /// Drops the loaded pages so the next fetch starts at the head of the index.
  void _resetPlaylistPaging() {
    _playlistItems = const [];
    _playlistFetchedCount = 0;
    _playlistHasMore = _flattenedIds?.isNotEmpty ?? false;
  }

  Future<void> reorderCollectionPlaylistItem(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _playlistItems.length) return;
    if (newIndex < 0 || newIndex >= _playlistItems.length) return;

    final reordered = List<AggregatedItem>.from(_playlistItems);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    _playlistItems = reordered;
    _collectionSort = CollectionSortOption.custom;

    // The loaded items take the head of the index in their new order and the
    // rest keep theirs. Matching on id rather than position holds up even when
    // a page came back short because the server had dropped one of them.
    final ids = _flattenedIds;
    if (ids != null) {
      final loadedIds = reordered.map((i) => i.id).toList();
      final loaded = loadedIds.toSet();
      final merged = [...loadedIds, ...ids.where((id) => !loaded.contains(id))];
      _flattenedIds = merged;
      _customOrderIds = List<String>.from(merged);
    }

    notifyListeners();

    try {
      final syncService = GetIt.instance<PluginSyncService>();
      final order = _customOrderIds;
      if (syncService.collectionOrderSupported(_client) && order != null) {
        // The whole order goes up, otherwise the server forgets where the items
        // that haven't been paged in yet belong.
        await syncService.saveCustomCollectionOrder(_client, itemId, order);
      }
    } catch (_) {}
  }

  /// Pulls one item out of this collection and rebuilds every list that
  /// carries it, so the grid, the playlist tab and the saved order all stop
  /// showing it without a page reload.
  ///
  /// The lists are edited locally first so the card disappears on the tap
  /// that confirmed it, then the server call runs. A failure restores the
  /// prior lists and rethrows, so the caller can say it didn't take.
  Future<void> removeFromCollection(AggregatedItem item) async {
    if (_item?.type != 'BoxSet') return;

    final previousCollectionItems = _collectionItems;
    final previousPlaylistItems = _playlistItems;
    final previousFlattenedIds = _flattenedIds;
    final previousCustomOrderIds = _customOrderIds;
    final previousIndexEntries = _playlistIndexEntries;
    final previousFetchedCount = _playlistFetchedCount;
    final previousCollectionFetched = _collectionFetchedCount;
    final previousCollectionTotal = _collectionTotalCount;
    final previousPlaylistHasMore = _playlistHasMore;

    // Where the item sits right now decides which read cursors move below, so
    // both positions are taken before the splices erase them.
    final wasInLoadedGridPage = _collectionItems.any(
      (entry) => entry.id == item.id,
    );
    final flattenedIndex = _flattenedIds?.indexOf(item.id) ?? -1;
    final wasInLoadedPlaylistPage =
        flattenedIndex >= 0 && flattenedIndex < _playlistFetchedCount;

    _collectionItems = _collectionItems
        .where((entry) => entry.id != item.id)
        .toList();
    _playlistItems = _playlistItems
        .where((entry) => entry.id != item.id)
        .toList();
    final flattened = _flattenedIds;
    if (flattened != null) {
      _flattenedIds = flattened.where((id) => id != item.id).toList();
    }
    // The drag order is user data, so it drops the id too and the save
    // below pushes the shorter list. Leaving it in would put the title
    // back on the next open.
    _customOrderIds = _customOrderIds?.where((id) => id != item.id).toList();
    final entries = _playlistIndexEntries;
    if (entries != null) {
      _playlistIndexEntries = entries
          .where((entry) => entry.id != item.id)
          .toList();
    }
    // Both lists count how far into the collection they have read, and they
    // page independently in orders of their own. A cursor only steps back when
    // the hole opened behind it: stepping one that sits ahead of the hole would
    // re-read an id the list already shows and repeat a card on the next page.
    if (wasInLoadedPlaylistPage) _playlistFetchedCount -= 1;
    if (wasInLoadedGridPage && _collectionFetchedCount > 0) {
      _collectionFetchedCount -= 1;
    }
    // The membership shrank for every list, wherever the card was showing.
    if (_collectionTotalCount > 0) _collectionTotalCount -= 1;
    final remainingIds = _flattenedIds;
    if (remainingIds != null) {
      // The paged read returns at its guard once the cursor reaches the end,
      // so it never clears this itself.
      _playlistHasMore = _playlistFetchedCount < remainingIds.length;
    }
    notifyListeners();

    try {
      await _client.itemsApi.removeFromCollection(itemId, [item.id]);
      final syncService = GetIt.instance<PluginSyncService>();
      final order = _customOrderIds;
      if (syncService.collectionOrderSupported(_client) && order != null) {
        await syncService.saveCustomCollectionOrder(_client, itemId, order);
      }
    } catch (_) {
      _collectionItems = previousCollectionItems;
      _playlistItems = previousPlaylistItems;
      _flattenedIds = previousFlattenedIds;
      _customOrderIds = previousCustomOrderIds;
      _playlistIndexEntries = previousIndexEntries;
      _playlistFetchedCount = previousFetchedCount;
      _collectionFetchedCount = previousCollectionFetched;
      _collectionTotalCount = previousCollectionTotal;
      _playlistHasMore = previousPlaylistHasMore;
      notifyListeners();
      rethrow;
    }
  }

  /// Fetches the first page of grid items.
  Future<void> _loadCollectionItems() async {
    try {
      await _fetchCollectionPage();
    } catch (_) {}
  }

  /// Fetches the next page of BoxSet top-level items for the **grid**.
  ///
  /// Grid and playlist are now independent.  This method only updates
  /// [_collectionItems]; playlist content is managed by [_buildPlaylistIndex]
  /// and [_fetchPlaylistPage].
  Future<void> _fetchCollectionPage() async {
    // Deliberately not recursive and not filtered by type. The server returns
    // exactly the collection's own members this way, episodes included, where
    // a recursive read either drags in every episode of a member series or,
    // filtered, drops episode members and leaves the grid blank.
    final data = await _client.itemsApi.getItems(
      parentId: itemId,
      startIndex: _collectionFetchedCount,
      limit: _collectionPageSize,
      fields: 'PrimaryImageAspectRatio,BasicSyncInfo,People',
    );
    final newItems = _mapItems((data['Items'] as List?) ?? []);
    final total = data['TotalRecordCount'] as int?;
    if (total != null) _collectionTotalCount = total;
    _collectionFetchedCount += newItems.length;
    // A server that leaves the total out would otherwise strand the grid on its
    // first page, so a full page is taken to mean there is more behind it.
    _collectionHasMore = total != null
        ? _collectionFetchedCount < _collectionTotalCount
        : newItems.length == _collectionPageSize;
    _collectionItems = [..._collectionItems, ...newItems];
    if ((_playlistIndexEntries == null || _playlistIndexEntries!.isEmpty) &&
        !_playlistIndexBuilding &&
        !_playlistFallbackTriggered) {
      _playlistFallbackTriggered = true;
      _buildPlaylistIndex();
    }
    notifyListeners();
  }

  /// Puts [_flattenedIds] in place, either from a saved order or by scanning
  /// the collection, then starts the first page.
  Future<void> _buildPlaylistIndex() async {
    _playlistIndexBuilding = true;
    notifyListeners();

    try {
      // A saved order still needs the scan to find members added since it was
      // saved. They go on the end in release order so they aren't lost.
      final syncService = GetIt.instance<PluginSyncService>();
      if (syncService.collectionOrderSupported(_client)) {
        try {
          final customOrder = await syncService.fetchCustomCollectionOrder(
            _client,
            itemId,
          );
          if (customOrder != null && customOrder.isNotEmpty) {
            _customOrderIds = customOrder;
            await _ensurePlaylistIndexEntries();
            final customSet = customOrder.toSet();
            final remaining = (_playlistIndexEntries ?? [])
                .where((e) => !customSet.contains(e.id))
                .toList()
              ..sort(_PlaylistItemIndexEntry.compareReleaseAscending);
            final seenIds = <String>{};
            _flattenedIds = [
              for (final id in [...customOrder, ...remaining.map((e) => e.id)])
                if (seenIds.add(id)) id,
            ];
            _customOrderIds = _flattenedIds;
            _collectionSort = CollectionSortOption.custom;
          }
        } catch (_) {}
      }

      if (_flattenedIds == null) {
        await _ensurePlaylistIndexEntries();
        _collectionSort = CollectionSortOption.server;
        _rebuildFlattenedIds();
      }

      _resetPlaylistPaging();
    } catch (_) {}

    _playlistIndexBuilding = false;
    notifyListeners();

    await loadMorePlaylistItems();
  }

  /// Walks the collection once to build [_playlistIndexEntries], the id and
  /// sort key of every playable item in it. Does nothing if they already exist.
  ///
  /// Only the keys are kept. The items themselves are read a page at a time by
  /// [_fetchPlaylistPage], so a collection of any size settles at a few KB.
  Future<void> _ensurePlaylistIndexEntries() async {
    if (_playlistIndexEntries != null) return;
    try {
      // Deliberately not recursive. The scan reads the collection's own members
      // and then asks each series for its episodes below, so walking the tree
      // here would spend the limit on episodes that arrive twice.
      final allData = await _client.itemsApi.getItems(
        parentId: itemId,
        limit: _indexScanLimit,
        fields: 'BasicSyncInfo',
      );
      final allTopLevel = _mapItems((allData['Items'] as List?) ?? []);

      final seriesItems = allTopLevel.where((i) => i.type == 'Series').toList();
      final episodesBySeries = <String, List<AggregatedItem>>{};

      // A batch at a time. One request per series all at once would open as
      // many sockets as the collection has shows.
      for (var i = 0; i < seriesItems.length; i += _indexScanBatchSize) {
        final end = i + _indexScanBatchSize;
        final batch = seriesItems.sublist(
          i,
          end < seriesItems.length ? end : seriesItems.length,
        );
        final episodeLists = await Future.wait(
          batch.map((series) async {
            try {
              final epData = await _client.itemsApi.getEpisodes(series.id);
              return _mapItems(
                (epData['Items'] as List?) ?? [],
                fallbackRating: _item?.officialRating,
              );
            } catch (_) {
              return const <AggregatedItem>[];
            }
          }),
        );
        for (var j = 0; j < batch.length; j++) {
          episodesBySeries[batch[j].id] = episodeLists[j];
        }
      }

      // Each series' episodes take its place, so the server's order holds.
      final flat = [
        for (final item in allTopLevel)
          if (item.type == 'Series')
            ...?episodesBySeries[item.id]
          else if (_playableTypes.contains(item.type))
            item,
      ];

      final seenIds = <String>{};
      final uniqueFlat = [
        for (final item in flat)
          if (seenIds.add(item.id)) item,
      ];

      _playlistIndexEntries = uniqueFlat
          .map(
            (i) => _PlaylistItemIndexEntry(
              id: i.id,
              name: i.name,
              premiereDate: i.premiereDate,
              productionYear: i.productionYear,
            ),
          )
          .toList();
    } catch (_) {}
    if (_playlistIndexEntries == null || _playlistIndexEntries!.isEmpty) {
      if (_collectionItems.isNotEmpty) {
        final seenIds = <String>{};
        _playlistIndexEntries = _collectionItems
            .where((i) => _playableTypes.contains(i.type) && seenIds.add(i.id))
            .map(
              (i) => _PlaylistItemIndexEntry(
                id: i.id,
                name: i.name,
                premiereDate: i.premiereDate,
                productionYear: i.productionYear,
              ),
            )
            .toList();
      }
    }
  }

  /// Reads the next run of ids into [_playlistItems].
  ///
  /// Progress is counted in index positions rather than items returned, so an
  /// id the server no longer knows about can't stall the list.
  Future<void> _fetchPlaylistPage() async {
    final ids = _flattenedIds;
    if (ids == null || _playlistFetchedCount >= ids.length) return;

    final end = (_playlistFetchedCount + _playlistPageSize).clamp(
      0,
      ids.length,
    );
    final batch = ids.sublist(_playlistFetchedCount, end);

    final data = await _client.itemsApi.getItems(
      ids: batch,
      fields: 'PrimaryImageAspectRatio,BasicSyncInfo,People,Overview',
    );
    final items = _mapItems((data['Items'] as List?) ?? []);

    // The by-id endpoint answers in whatever order it likes.
    final orderMap = {for (var i = 0; i < batch.length; i++) batch[i]: i};
    items.sort(
      (a, b) => (orderMap[a.id] ?? batch.length)
          .compareTo(orderMap[b.id] ?? batch.length),
    );

    _playlistFetchedCount += batch.length;
    _playlistHasMore = _playlistFetchedCount < ids.length;

    _playlistItems = [..._playlistItems, ...items];

    _resolveNextUp();
    notifyListeners();
  }

  /// Picks the first unwatched item, or the first item once the whole
  /// collection has been watched.
  ///
  /// Only the loaded head is visible here, so a watched head with pages still
  /// to come is left alone. Wrapping to the start then would point at item one
  /// while the next unseen one is further down.
  void _resolveNextUp() {
    if (_playlistItems.isEmpty) {
      _nextUp = null;
      return;
    }
    final unwatched = _playlistItems
        .where((item) => item.rawData['UserData']?['Played'] != true)
        .firstOrNull;
    if (unwatched != null) {
      _nextUp = unwatched;
    } else if (!_playlistHasMore) {
      _nextUp = _playlistItems.first;
    }
  }

  /// Called by the UI scroll listener to load the next grid page.
  Future<void> loadMoreCollectionItems() async {
    if (_collectionLoadingMore || !_collectionHasMore) return;
    _collectionLoadingMore = true;
    notifyListeners();
    try {
      await _fetchCollectionPage();
    } catch (_) {}
    _collectionLoadingMore = false;
    notifyListeners();
  }

  /// Called by the UI scroll listener to load the next playlist page.
  Future<void> loadMorePlaylistItems() async {
    if (_playlistLoadingMore || !_playlistHasMore || _playlistIndexBuilding) {
      return;
    }
    _playlistLoadingMore = true;
    notifyListeners();
    try {
      await _fetchPlaylistPage();
    } catch (_) {}
    _playlistLoadingMore = false;
    notifyListeners();
  }

  /// Refreshes the already loaded BoxSet collection cards without resetting
  /// pagination, scroll position, focus or the detail screen state.
  ///
  /// Used after an item mutation (watched/favorite/etc.). Only the items that
  /// are currently loaded are hydrated again from the server.
  Future<void> refreshCollectionItems() async {
    if (_collectionItems.isEmpty) {
      return;
    }

    final ids = _collectionItems
        .map((item) => item.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (ids.isEmpty) {
      return;
    }

    try {
      final refreshedById = await _refetchItemsById(ids, _collectionPageSize);

      if (refreshedById.isEmpty) {
        return;
      }

      _collectionItems = _collectionItems
          .map((item) => refreshedById[item.id] ?? item)
          .toList(growable: false);

      notifyListeners();
    } catch (_) {}
  }

  /// Re-reads [ids] a page at a time. One request carrying every loaded id
  /// builds a query string long enough for the server to reject.
  Future<Map<String, AggregatedItem>> _refetchItemsById(
    List<String> ids,
    int pageSize,
  ) async {
    final refreshedById = <String, AggregatedItem>{};

    for (var start = 0; start < ids.length; start += pageSize) {
      final end = start + pageSize;
      final data = await _client.itemsApi.getItems(
        ids: ids.sublist(start, end > ids.length ? ids.length : end),
        fields: 'PrimaryImageAspectRatio,BasicSyncInfo,People,Overview',
      );

      for (final item in _mapItems((data['Items'] as List?) ?? const [])) {
        refreshedById[item.id] = item;
      }
    }

    return refreshedById;
  }

  /// Refreshes the already loaded BoxSet playlist cards without rebuilding the
  /// playlist index or resetting pagination.
  ///
  /// This keeps the active sort, loaded page count, focus and horizontal scroll
  /// completely intact while updating UserData such as watched/progress state.
  Future<void> refreshPlaylistItems() async {
    if (_playlistItems.isEmpty) {
      return;
    }

    final ids = _playlistItems
        .map((item) => item.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (ids.isEmpty) {
      return;
    }

    try {
      final refreshedById = await _refetchItemsById(ids, _playlistPageSize);

      if (refreshedById.isEmpty) {
        return;
      }

      _playlistItems = _playlistItems
          .map((item) => refreshedById[item.id] ?? item)
          .toList(growable: false);

      _resolveNextUp();

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadParentCollection() async {
    final item = _item;
    if (item == null) {
      _parentCollections = const [];
      notifyListeners();
      return;
    }

    try {
      final Map<String, ({String name, Map<String, dynamic> rawData})> boxSetInfo = {};
      final ancestors = await _client.itemsApi.getAncestors(item.id);
      for (final ancestor in ancestors) {
        if (ancestor['Type'] == 'BoxSet') {
          final boxSetId = ancestor['Id']?.toString();
          final name = ancestor['Name']?.toString();
          if (boxSetId != null && boxSetId.isNotEmpty && name != null) {
            final isMember = await _boxSetContainsItem(boxSetId, item.id);
            if (isMember && !boxSetInfo.containsKey(boxSetId)) {
              boxSetInfo[boxSetId] = (
                name: name,
                rawData: Map<String, dynamic>.from(ancestor),
              );
            }
          }
        }
      }

      final scannedCollections = await _findParentCollectionsByScanningBoxSets(item.id);
      boxSetInfo.addAll(scannedCollections);

      if (boxSetInfo.isEmpty) {
        _parentCollections = const [];
        notifyListeners();
        return;
      }

      // Keep collections in a stable order so the rows don't shuffle around
      // between opens.
      final entries = boxSetInfo.entries.toList();
      final ordered = List<ParentCollection?>.filled(entries.length, null);
      final fetchFutures = <Future<void>>[];

      for (var i = 0; i < entries.length; i++) {
        final index = i;
        final boxSetId = entries[i].key;
        final info = entries[i].value;

        fetchFutures.add(() async {
          // Not recursive and not filtered, same as the collection grid, so a
          // collection made of episodes still shows its members here.
          final data = await _client.itemsApi.getItems(
            parentId: boxSetId,
            sortBy: 'PremiereDate,SortName',
            sortOrder: 'Ascending',
            fields: 'PrimaryImageAspectRatio,BasicSyncInfo,ProviderIds',
          );

          final items = (data['Items'] as List?) ?? [];
          ordered[index] = ParentCollection(
            id: boxSetId,
            name: info.name,
            boxSetItem: AggregatedItem(
              id: boxSetId,
              serverId: item.serverId,
              rawData: info.rawData,
            ),
            items: _sortCollectionByReleaseOrder(_mapItems(items)),
          );
        }());
      }
      await Future.wait(fetchFutures);

      final collections = ordered.whereType<ParentCollection>().toList();

      _parentCollections = collections;

      notifyListeners();
    } catch (_) {}
  }

  Future<bool> _boxSetContainsItem(String boxSetId, String itemId) async {
    try {
      // Membership is a direct-children question. Walking the tree would report
      // an episode as belonging to whatever collection holds its series, and
      // hand back every episode in the collection to answer it.
      final membership = await _client.itemsApi.getItems(
        parentId: boxSetId,
        fields: 'BasicSyncInfo',
      );
      final members = (membership['Items'] as List?) ?? const [];
      return members.whereType<Map>().any((entry) {
        final map = entry.cast<String, dynamic>();
        return map['Id'] == itemId;
      });
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, ({String name, Map<String, dynamic> rawData})>> _findParentCollectionsByScanningBoxSets(String itemId) async {
    final Map<String, ({String name, Map<String, dynamic> rawData})> result = {};
    try {
      const pageSize = 200;
      var startIndex = 0;

      while (true) {
        final data = await _client.itemsApi.getItems(
          includeItemTypes: ['BoxSet'],
          recursive: true,
          sortBy: 'SortName',
          fields: 'BasicSyncInfo,PrimaryImageAspectRatio,ImageTags,ProviderIds',
          startIndex: startIndex,
          limit: pageSize,
          enableTotalRecordCount: true,
        );
        final boxSets = (data['Items'] as List?) ?? const [];
        if (boxSets.isEmpty) {
          break;
        }

        final candidates = <({String id, String name, Map<String, dynamic> rawData})>[];
        for (final raw in boxSets.whereType<Map>()) {
          final boxSet = raw.cast<String, dynamic>();
          final boxSetId = boxSet['Id']?.toString();
          final boxSetName = boxSet['Name']?.toString();
          if (boxSetId == null || boxSetId.isEmpty || boxSetName == null) {
            continue;
          }
          candidates.add((id: boxSetId, name: boxSetName, rawData: boxSet));
        }

        // Cap how many membership lookups run at once so a large library
        // doesn't fire a whole page of requests in one burst.
        const maxConcurrent = 12;
        for (var i = 0; i < candidates.length; i += maxConcurrent) {
          final batch = candidates.skip(i).take(maxConcurrent);
          await Future.wait(batch.map((candidate) async {
            final membership = await _client.itemsApi.getItems(
              parentId: candidate.id,
              fields: 'BasicSyncInfo',
            );
            final members = (membership['Items'] as List?) ?? const [];
            final hasItem = members.whereType<Map>().any((entry) {
              final map = entry.cast<String, dynamic>();
              return map['Id'] == itemId;
            });
            if (hasItem) {
              result[candidate.id] = (
                name: candidate.name,
                rawData: candidate.rawData,
              );
            }
          }));
        }

        if (boxSets.length < pageSize) {
          break;
        }
        startIndex += boxSets.length;
      }
    } catch (_) {}

    return result;
  }

  List<AggregatedItem> _sortCollectionByReleaseOrder(
    List<AggregatedItem> items,
  ) {
    final sorted = List<AggregatedItem>.from(items);
    sorted.sort((a, b) {
      final aDate = a.premiereDate;
      final bDate = b.premiereDate;
      if (aDate != null && bDate != null) {
        final byDate = aDate.compareTo(bDate);
        if (byDate != 0) {
          return byDate;
        }
      } else if (aDate != null) {
        return -1;
      } else if (bDate != null) {
        return 1;
      }

      final aYear = a.productionYear;
      final bYear = b.productionYear;
      if (aYear != null && bYear != null) {
        final byYear = aYear.compareTo(bYear);
        if (byYear != 0) {
          return byYear;
        }
      } else if (aYear != null) {
        return -1;
      } else if (bYear != null) {
        return 1;
      }

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  Future<void> _loadFeatures() async {
    final parts = _loadAdditionalParts();
    try {
      final items = await _client.itemsApi.getSpecialFeatures(itemId);
      final mapped = _mapItems(items).where((item) => item.id != itemId).toList()
        ..sort(compareFeatures);
      _features = [
        ...await parts,
        ...mapped,
      ];
      notifyListeners();
    } catch (_) {
      _features = await parts;
      notifyListeners();
    }
  }

  // A movie split across files, like DVD1 and DVD2, lists the other files as
  // its parts. They're tagged so the extras rows give them their own heading.
  Future<List<AggregatedItem>> _loadAdditionalParts() async {
    if ((_item?.partCount ?? 1) < 2) return const [];
    try {
      final parts = await _client.itemsApi.getAdditionalParts(itemId);
      return _mapItems([
        for (final part in parts) {...part, '__moonfinAdditionalPart': true},
      ]);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadFilmography() async {
    try {
      final data = await _client.itemsApi.getItems(
        personIds: [itemId],
        includeItemTypes: ['Movie', 'Series', 'MusicVideo', 'Episode'],
        sortBy: 'PremiereDate',
        sortOrder: 'Descending',
        recursive: true,
        limit: 100,
        fields: 'PrimaryImageAspectRatio,BasicSyncInfo,People',
      );
      final items = (data['Items'] as List?) ?? [];
      // The cards don't know whose page they're on, so each title carries
      // the role for its subtitle and lets go of the rest of the cast.
      _filmography = [
        for (final item in _mapItems(items))
          AggregatedItem(
            id: item.id,
            serverId: item.serverId,
            rawData: {
              ...item.rawData,
              '__moonfinPersonRole': item.roleOf(itemId),
            }..remove('People'),
          ),
      ];
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadPersonAccounts() async {
    final tmdbId = _item?.tmdbId;
    if (tmdbId == null || tmdbId.isEmpty) return;
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<PluginSyncService>() ||
        !getIt<PluginSyncService>().tmdbPersonLinksAvailable ||
        !DetailSection.personLinks.isOffered ||
        !DetailSectionVisibility.of(
          getIt<UserPreferences>(),
        ).shows(DetailSection.personLinks)) {
      return;
    }
    final accounts = await _tmdbRepository.getPersonAccounts(tmdbId);
    if (accounts == null) return;
    _personAccounts = accounts;
    notifyListeners();
  }

  Future<void> _loadReviews() async {
    final item = _item;
    final tmdbId = item?.tmdbId;
    if (item == null || tmdbId == null || tmdbId.isEmpty) return;
    if (!DetailSection.reviews.isOffered ||
        !DetailSectionVisibility.of(
          GetIt.instance<UserPreferences>(),
        ).shows(DetailSection.reviews)) {
      return;
    }
    final reviews = await _tmdbRepository.getReviews(
      tmdbId: tmdbId,
      type: item.type == 'Series' ? 'tv' : 'movie',
      language: currentAppLocale().toLanguageTag(),
    );
    if (reviews == null || reviews.isEmpty || _item?.id != item.id) return;
    _reviews = reviews;
    notifyListeners();
  }

  Future<void> _loadSimilar() async {
    try {
      final item = _item;
      if (item != null && (item.type == 'Movie' || item.type == 'Series')) {
        try {
          final prefs = GetIt.instance<UserPreferences>();
          final sourceSetting = similarItemsSource(
            setting: prefs.get(UserPreferences.recommendationSystemSource),
            kidsMode: prefs.get(UserPreferences.kidsModeEnabled),
            serverType: _client.serverType,
          );

          if (sourceSetting == RecommendationSystemSource.server) {
            final data = await _client.itemsApi.getSimilarItems(
              itemId,
              limit: _similarLimit,
              bypass: 'moonfin',
            );
            final items = (data['Items'] as List?) ?? [];
            _similar = _mapItems(items);
            _similarSource = SimilarSource.jellyfin;
            return;
          }

          final isLocal = sourceSetting == RecommendationSystemSource.local;

          // Auto-detect server recommendations via Moonbase if "Moonfin Recommends" is selected
          // and Moonbase announces recommendationsSupported.
          if (isLocal && GetIt.instance.isRegistered<PluginSyncService>()) {
            final pluginSync = GetIt.instance<PluginSyncService>();
            if (pluginSync.recommendationsSupported) {
              try {
                final data = await pluginSync.fetchSimilarItems(
                  _client,
                  itemId,
                  limit: _similarLimit,
                );
                final items = (data?['Items'] as List?) ?? [];
                if (items.isNotEmpty) {
                  _similar = _mapItems(items);
                  _similarSource = SimilarSource.moonfin;
                  return;
                }
              } catch (e) {
                debugPrint('[ItemDetailViewModel] Moonbase server recommendation failed, falling back to local: $e');
              }
            }
          }

          final serverId = _serverId ?? _client.baseUrl;
          final dataSource = GetIt.instance<RowDataSource>();

          final recommended = await dataSource.getRecommendations(
            serverId: serverId,
            baseItem: item,
            isLocal: isLocal,
            limit: _similarLimit,
            includeWatched: true,
          );
          // Only short-circuit when we actually have results. An empty list (e.g.
          // the online source has nothing, or no local matches) falls through
          // to Jellyfin's similar-items below.
          if (recommended.isNotEmpty) {
            _similar = recommended;
            _similarSource = isLocal ? SimilarSource.moonfin : SimilarSource.tmdb;
            return;
          }
        } catch (e) {
          debugPrint('[ItemDetailViewModel] Custom recommendation system failed: $e');
        }
      }

      try {
        final data = await _client.itemsApi.getSimilarItems(itemId, limit: _similarLimit);
        final items = (data['Items'] as List?) ?? [];
        _similar = _mapItems(items);
        _similarSource = SimilarSource.jellyfin;
      } catch (_) {}
    } finally {
      _similarInitialLoadComplete = true;
      notifyListeners();
    }
  }

  Future<void> _loadRatings() async {
    final item = _item;
    if (item == null) return;

    if (item.type == 'Episode') {
      if (!GetIt.instance<UserPreferences>().canFetchEpisodeRatings) return;

      final seriesId = item.seriesId;
      final season = item.parentIndexNumber;
      final episode = item.indexNumber;

      if (seriesId != null && season != null && episode != null) {
        try {
          final seriesData = await _client.itemsApi.getItem(seriesId);
          final seriesTmdbId = (seriesData['ProviderIds'] as Map?)?['Tmdb']?.toString();
          if (seriesTmdbId != null && seriesTmdbId.isNotEmpty) {
            final rating = await _tmdbRepository.getEpisodeRating(
              tmdbId: seriesTmdbId,
              season: season,
              episode: episode,
            );
            if (rating != null && rating > 0) {
              _ratings = {'tmdb_episode': rating};
              notifyListeners();
            }
          }
        } catch (_) {}
      }
      return;
    }

    if (!GetIt.instance<UserPreferences>()
        .get(UserPreferences.enableAdditionalRatings)) {
      return;
    }

    final tmdbId = item.tmdbId;
    if (tmdbId == null) return;
    final mediaType = item.type ?? 'Movie';

    try {
      final result = await _mdbListRepository.getRatings(
        tmdbId: tmdbId,
        mediaType: mediaType,
      );
      if (result != null && result.isNotEmpty) {
        _ratings = result;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadUpcomingEpisode() async {
    final item = _item;
    if (item == null || item.type != 'Series') return;
    try {
      if (!GetIt.instance.isRegistered<UpcomingEpisodeService>()) return;
      final service = GetIt.instance<UpcomingEpisodeService>();
      final cached = service.getCached(item.id);
      if (cached != null) {
        _upcomingEpisode = cached;
        notifyListeners();
        return;
      }
      final episode = await service.resolveUpcomingEpisode(
        seriesId: item.id,
        providerIds: item.providerIds,
      );
      if (_isDisposed) return;
      if (episode != null && !episode.hasAired) {
        _upcomingEpisode = episode;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ItemDetailViewModel] Upcoming episode resolution failed: $e');
    }
  }

  Future<void> toggleFavorite() async {
    final item = seriesFeaturedBook ?? _item;
    if (item == null) return;
    final newState = !item.isFavorite;
    _applyOptimisticUpdate({'IsFavorite': newState});
    try {
      await _mutations.setFavorite(_mutationId, isFavorite: newState);
      await _reload();
    } catch (_) {
      _applyOptimisticUpdate({'IsFavorite': !newState});
    }
  }

  Future<void> togglePlayed() async {
    final item = seriesFeaturedBook ?? _item;
    if (item == null) return;
    final newState = !item.isPlayed;
    _applyOptimisticUpdate({'Played': newState});
    try {
      await _mutations.setPlayed(_mutationId, isPlayed: newState);
      await _reload();
    } catch (_) {
      _applyOptimisticUpdate({'Played': !newState});
    }
  }

  Future<void> setThumbRating(bool likes) async {
    return _mutateRating(
      {'Likes': likes},
      () => _mutations.setRating(_mutationId, likes: likes),
    );
  }

  Future<void> setNumericRating(double rating) async {
    if (!rating.isFinite || rating < 0 || rating > 10) {
      throw ArgumentError.value(rating, 'rating', 'must be between 0 and 10');
    }
    return _mutateRating(
      {
        'Rating': rating,
        'Likes': rating >= AggregatedItem.likedRatingThreshold,
      },
      () => _mutations.setNumericRating(_mutationId, rating: rating),
    );
  }

  Future<void> clearRating() async {
    return _mutateRating(
      {'Rating': null, 'Likes': null},
      () => _mutations.clearRating(_mutationId),
    );
  }

  Future<void> _mutateRating(
    Map<String, dynamic> userDataPatch,
    Future<void> Function() mutation,
  ) async {
    if (_isRatingMutationInProgress) return;
    final previousUserData = _copyUserData();
    _isRatingMutationInProgress = true;
    try {
      _applyOptimisticUpdate(userDataPatch);
      await mutation();
      await _reload();
    } catch (_) {
      _restoreUserData(previousUserData);
      rethrow;
    } finally {
      _isRatingMutationInProgress = false;
      notifyListeners();
    }
  }

  Map<String, dynamic>? _copyUserData() {
    final userData = _item?.rawData['UserData'];
    return userData is Map ? Map<String, dynamic>.from(userData) : null;
  }

  void _restoreUserData(Map<String, dynamic>? userData) {
    final item = _item;
    if (item == null) return;
    final updatedRaw = Map<String, dynamic>.from(item.rawData);
    if (userData == null) {
      updatedRaw.remove('UserData');
    } else {
      updatedRaw['UserData'] = userData;
    }
    _item = AggregatedItem(
      id: item.id,
      serverId: item.serverId,
      rawData: updatedRaw,
    );
    notifyListeners();
  }

  void _applyOptimisticUpdate(Map<String, dynamic> userDataPatch) {
    final item = _item;
    if (item == null) return;
    final updatedRaw = Map<String, dynamic>.from(item.rawData);
    final userData = Map<String, dynamic>.from(
      (updatedRaw['UserData'] as Map?) ?? {},
    );
    userData.addAll(userDataPatch);
    updatedRaw['UserData'] = userData;
    _item = AggregatedItem(
      id: item.id,
      serverId: item.serverId,
      rawData: updatedRaw,
    );
    notifyListeners();
  }

  Future<void> _reload() async {
    if (_isBookSeries) return;
    try {
      final data = await _client.itemsApi.getItem(itemId);
      _item = AggregatedItem(
        id: itemId,
        serverId: _serverId ?? _client.baseUrl,
        rawData: _withProbedSources(data),
      );
      notifyListeners();
    } catch (_) {}
  }

  List<Map<String, dynamic>>? _cachedEpisodeDirectors;
  List<Map<String, dynamic>>? _cachedEpisodeWriters;
  AggregatedItem? _cachedEpisodeCrewItem;

  void _ensureEpisodeCrew() {
    if (identical(_cachedEpisodeCrewItem, _item)) return;
    _cachedEpisodeCrewItem = _item;
    final item = _item;
    if (item?.type != 'Episode') {
      _cachedEpisodeDirectors = null;
      _cachedEpisodeWriters = null;
      return;
    }
    final l10n = currentAppLocalizations();
    _cachedEpisodeDirectors = item!.people
        .where((p) => p['Type'] == 'Director')
        .map((p) => <String, dynamic>{
              ...p,
              'Role': formatEpisodeDirectorRole(l10n, p['Role']?.toString()),
            })
        .toList(growable: false);
    _cachedEpisodeWriters = item.people
        .where((p) => p['Type'] == 'Writer')
        .map((p) => <String, dynamic>{
              ...p,
              'Role': formatEpisodeWriterRole(l10n, p['Role']?.toString()),
            })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get directors {
    if (_item?.type == 'BoxSet') {
      _ensureBoxSetPeople();
      return _boxSetDirectors;
    }
    final list = _item?.people.where((p) => p['Type'] == 'Director').toList() ?? const [];
    if (_item?.type == 'Episode') {
      _ensureEpisodeCrew();
      return _cachedEpisodeDirectors ?? list;
    }
    return list;
  }

  List<Map<String, dynamic>> get writers {
    if (_item?.type == 'BoxSet') {
      _ensureBoxSetPeople();
      return _boxSetWriters;
    }
    final list = _item?.people.where((p) => p['Type'] == 'Writer').toList() ?? const [];
    if (_item?.type == 'Episode') {
      _ensureEpisodeCrew();
      return _cachedEpisodeWriters ?? list;
    }
    return list;
  }

  List<Map<String, dynamic>> get actors {
    if (_item?.type == 'BoxSet') {
      _ensureBoxSetPeople();
      return _boxSetActors;
    }
    final list = _item?.people ?? const [];
    final dirNames = directors.map((d) => d['Name'] as String?).toSet();
    final writNames = writers.map((w) => w['Name'] as String?).toSet();
    final rawActors = list.where((p) {
      final type = p['Type'] as String?;
      if (type != 'Actor' && type != 'GuestStar') return false;
      final name = p['Name'] as String?;
      if (dirNames.contains(name) || writNames.contains(name)) return false;
      return true;
    }).toList();

    if (_item?.type == 'Episode') {
      return mergeEpisodeCast(
        episodeActors: rawActors,
        parentActors: _parentActors,
      );
    }

    if (_item?.type == 'Season' && rawActors.isEmpty) {
      return _parentActors;
    }

    return rawActors;
  }

  List<AggregatedItem> get filmographyMovies =>
      _filmography.where((i) => i.type == 'Movie').toList();

  List<AggregatedItem> get filmographySeries =>
      _filmography.where((i) => i.type == 'Series').toList();

  List<AggregatedItem> get filmographyMusicVideos =>
      _filmography.where((i) => i.type == 'MusicVideo').toList();

  List<AggregatedItem> get filmographyEpisodes =>
      _filmography.where((i) => i.type == 'Episode').toList();

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    userDataSync.removeListener(_onUserDataChanged);
    super.dispose();
  }
}
