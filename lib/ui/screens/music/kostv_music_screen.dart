import 'dart:async';

import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/music/music_navigation.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_widgets.dart';

/// Kos TV: Music, a page of its own as the music apps open: a big search
/// at the top (only music: what is at home and, under it, what can be asked
/// for), the charts right under it, and then what goes with what the person
/// listens to: their albums of late, mixes of their artists, more of the one
/// they listen to most, the chart of their genre, what the house asked for
/// and what arrived. Not a wall of posters: covers, lists and mixes.
class KostvMusicScreen extends StatefulWidget {
  const KostvMusicScreen({super.key});

  @override
  State<KostvMusicScreen> createState() => _KostvMusicScreenState();
}

class _KostvMusicScreenState extends State<KostvMusicScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'kostvMusicSearch');
  final _searchTvField = GlobalKey<CustomTVTextFieldState>();
  final _firstStop = FocusNode(debugLabel: 'kostvMusicFirst');
  Timer? _debounce;

  late final KostvMusicService _music = KostvMusicService(
    GetIt.instance<MediaServerClient>(),
  );

  /// The requests service, when it lets the person in.
  StremfinService? _stremfin;

  // What the page shows, each as it comes.
  StremfinChartPage? _topSongs;
  StremfinChartPage? _latino;
  StremfinChartPage? _topAlbums;
  StremfinChartPage? _genreChart;
  StremfinChartPage? _mexico;
  StremfinChartPage? _unitedStates;

  /// «Para ti», from the requests service, and what is new of the person's
  /// artists.
  StremfinRecommendations? _forYou;
  List<StremfinAlbum> _yourNews = const [];
  List<AggregatedItem> _recent = const [];
  List<AggregatedItem> _newAtHome = const [];
  KostvMusicTaste _taste = const KostvMusicTaste();
  ({String name, List<StremfinAlbum> albums})? _moreOf;
  List<StremfinAlbum> _requested = const [];
  List<StremfinAlbum> _releases = const [];
  bool _loading = true;

  // The search.
  String _query = '';
  KostvMusicAtHome? _atHome;
  StremfinMusicSearch? _toAsk;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQuery);
    _searchFocus.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _firstStop.dispose();
    super.dispose();
  }

  Future<StremfinService?> _allowedStremfin() async {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) return null;
    final stremfin = getIt<StremfinService>();
    if (!stremfin.isConfigured) return null;
    if (!stremfin.isAllowed) {
      try {
        await stremfin.refreshAccess();
      } catch (_) {
        return null;
      }
    }
    return stremfin.isAllowed ? stremfin : null;
  }

  /// Loads every part on its own, each shown as soon as it is there.
  Future<void> _load() async {
    Future<void> part(Future<void> Function() load) async {
      try {
        await load();
      } catch (e) {
        debugPrint('[Music] A part failed: $e');
      }
      if (mounted) setState(() {});
    }

    final stremfin = _stremfin = await _allowedStremfin();
    await Future.wait([
      if (stremfin != null) ...[
        part(() async => _topSongs = await stremfin.musicChart('top-songs')),
        part(() async => _latino = await stremfin.musicChart('latino-songs')),
        part(() async => _topAlbums = await stremfin.musicChart('top-albums')),
        part(() async => _requested = await stremfin.musicRequested()),
        part(
          () async =>
              _mexico = await stremfin.musicChart('top-songs', country: 'MX'),
        ),
        part(
          () async => _unitedStates = await stremfin.musicChart(
            'top-songs',
            country: 'US',
          ),
        ),
        part(() async => _releases = await stremfin.musicReleases()),
      ],
      part(() async => _recent = await _music.recentAlbums()),
      part(() async => _newAtHome = await _music.newAlbums()),
      part(() async {
        _taste = await _music.taste();
        await _loadForTaste(stremfin);
      }),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  /// What depends on the person's taste: the chart of their genre and more
  /// of the artist they listen to most.
  Future<void> _loadForTaste(StremfinService? stremfin) async {
    if (stremfin == null) return;
    final genre = _taste.chartGenre;
    final loads = <Future<void>>[
      if (genre != null && genre != 'latino')
        () async {
          try {
            _genreChart = await stremfin.musicChart('$genre-songs');
          } catch (_) {
            _genreChart = null;
          }
        }(),
    ];
    final artist = _taste.artists.firstOrNull;
    if (artist != null) {
      loads.add(
        () async {
          final found = await stremfin.musicSearch(artist.name);
          final match = found.artists.firstOrNull;
          if (match == null) return;
          final detail = await stremfin.musicArtist(match.deezerId);
          if (detail.albums.isNotEmpty) {
            _moreOf = (name: detail.artist.name, albums: detail.albums);
          }
        }().catchError((Object _) {}),
      );
    }
    // «Para ti»: what goes with the artists and genres the person listens
    // to most, and then what is new of those artists.
    final artists = [for (final a in _taste.artists.take(6)) a.name];
    if (artists.isNotEmpty) {
      loads.add(
        () async {
          final genres = <String>{
            for (final g in _taste.genres) ?kostvChartGenreOf(g),
          }.take(3).toList();
          final found = await stremfin.musicRecommendations(
            artists,
            genres: genres,
          );
          _forYou = found;
          if (mounted) setState(() {});
          final ids = [for (final seed in found.seeds) ?seed.deezerId];
          if (ids.isNotEmpty) {
            _yourNews = await stremfin.musicArtistReleases(ids);
          }
        }().catchError((Object e) {
          debugPrint('[Music] For you failed: $e');
        }),
      );
    }
    await Future.wait(loads);
  }

  // ---------------------------------------------------------------- search

  void _onQuery() {
    final query = _search.text.trim();
    if (query == _query) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _query = query;
      _atHome = null;
      _toAsk = null;
      _searching = query.isNotEmpty;
    });
    if (query.isEmpty) return;
    final stremfin = _stremfin;
    await Future.wait([
      _music
          .search(query)
          .then((found) {
            if (mounted && _query == query) setState(() => _atHome = found);
          })
          .catchError((Object _) {}),
      if (stremfin != null)
        stremfin
            .musicSearch(query)
            .then((found) {
              if (mounted && _query == query) setState(() => _toAsk = found);
            })
            .catchError((Object _) {}),
    ]);
    if (mounted && _query == query) setState(() => _searching = false);
  }

  // ----------------------------------------------------------------- moves

  void _toMenu() => NavigationLayout.focusNavbarNotifier.value?.call();

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey.isUpKey) {
      _toMenu();
      return KeyEventResult.handled;
    }
    if (event.logicalKey.isDownKey) {
      final next = FocusScope.of(context);
      if (_firstStop.context != null) {
        _firstStop.requestFocus();
      } else {
        next.focusInDirection(TraversalDirection.down);
      }
      return KeyEventResult.handled;
    }
    if (PlatformDetection.isTV &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.select)) {
      _searchTvField.currentState?.openKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Up from the first line of the page: the search.
  KeyEventResult _upToSearch(KeyEvent event) {
    if (event.logicalKey.isUpKey) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------- opening

  MediaServerClient get _client => GetIt.instance<MediaServerClient>();

  Future<void> _playMix(String artistId) async {
    final songs = await _music
        .mix(artistId)
        .catchError((Object _) => <AggregatedItem>[]);
    if (!mounted || songs.isEmpty) return;
    await playMusicTracks(context, songs);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final insets = calendarChromeInsets(context);
    final phone = KostvMusicSizes.phone;
    final bottom =
        MediaQuery.paddingOf(context).bottom +
        (phone && NavigationLayout.usesBottomNavbar ? 110 : 40);
    final searching = _query.isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: NavigationLayout(
        activeRoute: Destinations.kostvMusic,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A faint glow of Music's colour from the top.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.6, -1.2),
                  radius: 1.3,
                  colors: [Color(0x33FA2D55), Color(0x00000000)],
                ),
              ),
            ),
            CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    insets.left,
                    insets.top + (phone ? 4 : 8),
                    insets.right,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(child: _header(context)),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 26)),
                if (searching)
                  ..._results(context, insets)
                else
                  ..._sections(context, insets),
                SliverToBoxAdapter(child: SizedBox(height: bottom)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.kostvMusic,
          style: theme.textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: phone ? 34 : 44,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _searchField(context),
        ),
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = KostvMusicSizes.phone;
    final height = phone ? 50.0 : 60.0;
    final focused = _searchFocus.hasFocus;
    const fill = Color(0xFF1C1C1E);
    final icon = Icon(
      Icons.search_rounded,
      color: focused ? Colors.white : kostvMusicGrey,
      size: phone ? 24 : 28,
    );
    final textStyle = TextStyle(color: Colors.white, fontSize: phone ? 17 : 20);
    final hintStyle = TextStyle(
      color: kostvMusicGrey,
      fontSize: phone ? 17 : 20,
    );
    if (PlatformDetection.isTV) {
      return Focus(
        focusNode: _searchFocus,
        onKeyEvent: _onSearchKey,
        child: SizedBox(
          height: height,
          child: CustomTVTextField(
            key: _searchTvField,
            controller: _search,
            isFocused: focused,
            hint: l10n.kostvMusicSearchHint,
            textStyle: textStyle,
            hintStyle: hintStyle,
            prefixIcon: icon,
            filled: true,
            fillColor: fill,
            borderRadius: 14,
            borderColor: Colors.transparent,
            focusedBorderColor: Colors.white,
            borderWidth: 0,
            focusedBorderWidth: 3,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 4,
            ),
            popParentOnKeyboardClose: false,
          ),
        ),
      );
    }
    final border = OutlineInputBorder(
      borderRadius: AppRadius.circular(14),
      borderSide: BorderSide.none,
    );
    return Focus(
      onKeyEvent: _onSearchKey,
      skipTraversal: true,
      canRequestFocus: false,
      child: SizedBox(
        height: height,
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          style: textStyle,
          cursorColor: kostvMusicColor,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.kostvMusicSearchHint,
            hintStyle: hintStyle,
            filled: true,
            fillColor: fill,
            prefixIcon: icon,
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(
                      Icons.cancel_rounded,
                      color: kostvMusicGrey,
                    ),
                    onPressed: _search.clear,
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.circular(14),
              borderSide: const BorderSide(color: Colors.white54, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- sections

  List<Widget> _sections(BuildContext context, EdgeInsets insets) {
    final l10n = AppLocalizations.of(context);
    var first = true;
    FocusNode? firstNode() {
      if (!first) return null;
      first = false;
      return _firstStop;
    }

    Widget gap() => const SizedBox(height: 34);
    final parts = <Widget>[];
    void add(Widget? part) {
      if (part == null) return;
      parts
        ..add(part)
        ..add(gap());
    }

    add(
      _chartSongs(
        context,
        _topSongs,
        l10n.kostvMusicTopSongs,
        l10n.kostvMusicTopSongsWhy,
        insets,
        firstNode(),
      ),
    );
    add(
      _chartSongs(
        context,
        _latino,
        l10n.kostvMusicTopLatino,
        l10n.kostvMusicChartSoldWhy,
        insets,
        parts.isEmpty ? firstNode() : null,
      ),
    );
    add(_recentShelf(context, insets, parts.isEmpty ? firstNode() : null));
    add(_mixShelf(context, insets, parts.isEmpty ? firstNode() : null));
    // «Para ti»: a row for each «Porque escuchas a …», then its songs.
    final forYou = _forYou;
    if (forYou != null) {
      final byReason = <String, List<StremfinAlbum>>{};
      for (final album in forYou.albums) {
        byReason.putIfAbsent(album.reason ?? '', () => []).add(album);
      }
      for (final entry in byReason.entries.take(3)) {
        add(
          _albumShelf(
            context,
            entry.key.isEmpty ? l10n.kostvMusicForYouSongs : entry.key,
            l10n.kostvMusicForYouWhy,
            entry.value,
            insets,
          ),
        );
      }
      add(
        _chartSongs(
          context,
          null,
          l10n.kostvMusicForYouSongs,
          l10n.kostvMusicForYouWhy,
          insets,
          null,
          songs: forYou.songs,
          ranked: false,
        ),
      );
    }
    add(
      _albumShelf(
        context,
        l10n.kostvMusicNewFromYours,
        l10n.kostvMusicNewFromYoursWhy,
        _yourNews,
        insets,
      ),
    );
    add(_chartAlbums(context, _topAlbums, l10n.kostvMusicTopAlbums, insets));
    add(
      _chartSongs(
        context,
        _mexico,
        l10n.kostvMusicTopCountry(l10n.kostvMusicMexico),
        l10n.kostvMusicTopCountryWhy(l10n.kostvMusicMexico),
        insets,
        null,
      ),
    );
    final moreOf = _moreOf;
    if (moreOf != null) {
      add(
        _albumShelf(
          context,
          l10n.kostvMusicMoreOf(moreOf.name),
          l10n.kostvMusicMoreOfWhy(moreOf.name),
          moreOf.albums,
          insets,
        ),
      );
    }
    final genre = _genreChart;
    if (genre != null) {
      add(
        _chartSongs(
          context,
          genre,
          l10n.kostvMusicTopGenre(
            genre.chart.name.split('·').first.replaceFirst('Top ', '').trim(),
          ),
          l10n.kostvMusicChartSoldWhy,
          insets,
          null,
        ),
      );
    }
    add(
      _chartSongs(
        context,
        _unitedStates,
        l10n.kostvMusicTopCountry(l10n.kostvMusicUnitedStates),
        l10n.kostvMusicTopCountryWhy(l10n.kostvMusicUnitedStates),
        insets,
        null,
      ),
    );
    add(_albumShelf(context, l10n.kostvMusicReleases, null, _releases, insets));
    add(
      _albumShelf(context, l10n.kostvMusicRequested, null, _requested, insets),
    );
    if (_newAtHome.isNotEmpty) {
      add(
        KostvMusicShelf(
          title: l10n.kostvMusicNewAtHome,
          insets: insets,
          children: [
            for (final album in _newAtHome)
              KostvMusicAlbumTile(
                title: album.name,
                subtitle: album.albumArtist,
                cover: kostvMusicImageOf(album),
                onTap: () => openMusicItem(context, album),
              ),
          ],
        ),
      );
    }
    if (parts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(insets.left, 40, insets.right, 0),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator(color: kostvMusicColor)
                  : Text(
                      l10n.kostvMusicUnavailable,
                      style: const TextStyle(color: kostvMusicGrey),
                    ),
            ),
          ),
        ),
      ];
    }
    return [SliverList.list(children: parts)];
  }

  /// A chart of songs as Apple Music shows its top songs: columns of four
  /// numbered rows, sideways.
  Widget? _chartSongs(
    BuildContext context,
    StremfinChartPage? page,
    String title,
    String why,
    EdgeInsets insets,
    FocusNode? firstNode, {
    List<StremfinSong>? songs,
    bool ranked = true,
  }) {
    final list = songs ?? page?.songs ?? const <StremfinSong>[];
    return _songColumns(context, list, title, why, insets, firstNode, ranked);
  }

  Widget? _songColumns(
    BuildContext context,
    List<StremfinSong> songs,
    String title,
    String why,
    EdgeInsets insets,
    FocusNode? firstNode,
    bool ranked,
  ) {
    if (songs.isEmpty) return null;
    const perColumn = 4;
    final columns = (songs.length / perColumn).ceil();
    final phone = KostvMusicSizes.phone;
    final rowHeight = phone ? 62.0 : 70.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KostvMusicHeading(
          title: title,
          subtitle: why,
          padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 10),
        ),
        SizedBox(
          height: rowHeight * perColumn + 8,
          child: FocusTraversalGroup(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: insets.left, right: insets.right),
              itemCount: columns,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (context, column) => SizedBox(
                width: KostvMusicSizes.songColumn(context),
                child: Column(
                  children: [
                    for (
                      var i = column * perColumn;
                      i < songs.length && i < (column + 1) * perColumn;
                      i++
                    )
                      KostvMusicSongRow(
                        focusNode: i == 0 ? firstNode : null,
                        onKey: i % perColumn == 0 && firstNode != null
                            ? _upToSearch
                            : null,
                        title: songs[i].title,
                        artist: songs[i].artist,
                        cover: songs[i].cover,
                        rank: ranked ? songs[i].rank ?? i + 1 : null,
                        atHome: songs[i].inJellyfin,
                        badge: songs[i].album == null
                            ? KostvMusicBadge.none
                            : kostvMusicBadgeOf(songs[i].album!),
                        onTap: () =>
                            unawaited(openKostvMusicSong(context, songs[i])),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _chartAlbums(
    BuildContext context,
    StremfinChartPage? page,
    String title,
    EdgeInsets insets,
  ) {
    final albums = page?.albums ?? const <StremfinAlbum>[];
    if (albums.isEmpty) return null;
    return KostvMusicShelf(
      title: title,
      subtitle: AppLocalizations.of(context).kostvMusicTopSongsWhy,
      insets: insets,
      children: [
        for (final album in albums.take(30))
          KostvMusicAlbumTile(
            title: album.title,
            subtitle: album.artist,
            cover: album.cover,
            rank: album.rank,
            badge: kostvMusicBadgeOf(album),
            onTap: () => unawaited(openKostvStremfinAlbum(context, album)),
          ),
      ],
    );
  }

  Widget? _albumShelf(
    BuildContext context,
    String title,
    String? why,
    List<StremfinAlbum> albums,
    EdgeInsets insets,
  ) {
    if (albums.isEmpty) return null;
    return KostvMusicShelf(
      title: title,
      subtitle: why,
      insets: insets,
      children: [
        for (final album in albums.take(30))
          KostvMusicAlbumTile(
            title: album.title,
            subtitle: [
              ?album.artist,
              if (album.year != null) '${album.year}',
            ].join(' · '),
            cover: album.cover,
            badge: kostvMusicBadgeOf(album),
            onTap: () => unawaited(openKostvStremfinAlbum(context, album)),
          ),
      ],
    );
  }

  Widget? _recentShelf(
    BuildContext context,
    EdgeInsets insets,
    FocusNode? firstNode,
  ) {
    if (_recent.isEmpty) return null;
    return KostvMusicShelf(
      title: AppLocalizations.of(context).kostvMusicRecent,
      insets: insets,
      children: [
        for (final (i, album) in _recent.indexed)
          KostvMusicAlbumTile(
            focusNode: i == 0 ? firstNode : null,
            onKey: i == 0 && firstNode != null ? _upToSearch : null,
            title: album.name,
            subtitle: album.albumArtist,
            cover: kostvMusicImageOf(album),
            onTap: () => openMusicItem(context, album),
          ),
      ],
    );
  }

  Widget? _mixShelf(
    BuildContext context,
    EdgeInsets insets,
    FocusNode? firstNode,
  ) {
    final artists = _taste.artists.take(6).toList();
    if (artists.isEmpty) return null;
    final l10n = AppLocalizations.of(context);
    final size = KostvMusicSizes.cover;
    return KostvMusicShelf(
      title: l10n.kostvMusicMixes,
      subtitle: l10n.kostvMusicMixesWhy,
      insets: insets,
      children: [
        for (final (i, artist) in artists.indexed)
          KostvMusicAlbumTile(
            focusNode: i == 0 ? firstNode : null,
            onKey: i == 0 && firstNode != null ? _upToSearch : null,
            title: artist.name,
            subtitle: l10n.kostvMusicMixLabel,
            art: KostvMusicMixArt(
              name: artist.name,
              index: i,
              size: size - 6,
              picture: _client.imageApi.getPrimaryImageUrl(
                artist.id,
                maxWidth: 400,
              ),
            ),
            onTap: () => unawaited(_playMix(artist.id)),
          ),
      ],
    );
  }

  // --------------------------------------------------------------- results

  List<Widget> _results(BuildContext context, EdgeInsets insets) {
    final l10n = AppLocalizations.of(context);
    final atHome = _atHome;
    final toAsk = _toAsk;
    final askable = [
      for (final album in toAsk?.albums ?? const <StremfinAlbum>[])
        if (!album.inJellyfin) album,
    ];
    final askSongs = [
      for (final song in toAsk?.songs ?? const <StremfinSong>[])
        if (!song.inJellyfin) song,
    ];
    final artistsAway = toAsk?.artists ?? const <StremfinArtist>[];
    final parts = <Widget>[];
    void add(Widget part) => parts
      ..add(part)
      ..add(const SizedBox(height: 30));
    var first = true;
    FocusNode? firstNode() {
      if (!first) return null;
      first = false;
      return _firstStop;
    }

    // Artists: those at home first, then the service's.
    final artistTiles = <Widget>[
      for (final artist in atHome?.artists ?? const <AggregatedItem>[])
        KostvMusicAlbumTile(
          circle: true,
          size: KostvMusicSizes.artist,
          title: artist.name,
          cover: kostvMusicImageOf(artist),
          onTap: () => openMusicItem(context, artist),
        ),
      for (final artist in artistsAway)
        if (!(atHome?.artists.any(
              (a) => a.name.toLowerCase() == artist.name.toLowerCase(),
            ) ??
            false))
          KostvMusicAlbumTile(
            circle: true,
            size: KostvMusicSizes.artist,
            title: artist.name,
            cover: artist.picture,
            onTap: () => openKostvMusicArtist(context, artist),
          ),
    ];
    if (artistTiles.isNotEmpty) {
      final node = firstNode();
      if (node != null && artistTiles.first is KostvMusicAlbumTile) {
        final tile = artistTiles.first as KostvMusicAlbumTile;
        artistTiles[0] = KostvMusicAlbumTile(
          focusNode: node,
          onKey: _upToSearch,
          circle: true,
          size: tile.size,
          title: tile.title,
          cover: tile.cover,
          onTap: tile.onTap,
        );
      }
      add(
        KostvMusicShelf(
          title: l10n.kostvMusicArtists,
          insets: insets,
          height: KostvMusicSizes.artist + 40,
          children: artistTiles,
        ),
      );
    }

    // Songs: at home (they play), then the ones to ask for.
    final homeSongs = (atHome?.songs ?? const <AggregatedItem>[])
        .take(6)
        .toList();
    final songsAway = askSongs.take(6).toList();
    if (homeSongs.isNotEmpty || songsAway.isNotEmpty) {
      final node = firstNode();
      var index = 0;
      Widget row({
        required String title,
        required String artist,
        required String? cover,
        required bool atHome,
        bool explicit = false,
        required VoidCallback onTap,
      }) {
        final first = index++ == 0;
        return KostvMusicSongRow(
          focusNode: first ? node : null,
          onKey: first && node != null ? _upToSearch : null,
          title: title,
          artist: artist,
          cover: cover,
          atHome: atHome,
          explicit: explicit,
          onTap: onTap,
        );
      }

      parts
        ..add(
          KostvMusicHeading(
            title: l10n.kostvMusicSongs,
            padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 8),
          ),
        )
        ..add(
          Padding(
            padding: EdgeInsets.only(left: insets.left, right: insets.right),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: FocusTraversalGroup(
                  child: Column(
                    children: [
                      for (final song in homeSongs)
                        row(
                          title: song.name,
                          artist: [
                            ...song.artists.take(2),
                            ?song.album,
                          ].join(' · '),
                          cover: kostvMusicImageOf(song),
                          atHome: true,
                          onTap: () => unawaited(playMusicTrack(context, song)),
                        ),
                      for (final song in songsAway)
                        row(
                          title: song.title,
                          artist: [?song.artist, ?song.albumTitle].join(' · '),
                          cover: song.cover,
                          atHome: false,
                          explicit: song.explicit,
                          onTap: () =>
                              unawaited(openKostvMusicSong(context, song)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: 30));
    }

    final homeAlbums = atHome?.albums ?? const <AggregatedItem>[];
    if (homeAlbums.isNotEmpty) {
      add(
        KostvMusicShelf(
          title: l10n.kostvMusicAlbumsAtHome,
          insets: insets,
          children: [
            for (final album in homeAlbums)
              KostvMusicAlbumTile(
                title: album.name,
                subtitle: album.albumArtist,
                cover: kostvMusicImageOf(album),
                onTap: () => openMusicItem(context, album),
              ),
          ],
        ),
      );
    }
    if (askable.isNotEmpty) {
      add(
        KostvMusicShelf(
          title: l10n.kostvMusicToAsk,
          subtitle: l10n.kostvMusicToAskWhy,
          insets: insets,
          children: [
            for (final album in askable)
              KostvMusicAlbumTile(
                title: album.title,
                subtitle: [
                  ?album.artist,
                  switch (album.kind) {
                    StremfinAlbumKind.ep => l10n.kostvMusicKindEp,
                    StremfinAlbumKind.single => l10n.kostvMusicKindSingle,
                    _ => album.year?.toString(),
                  },
                ].whereType<String>().join(' · '),
                cover: album.cover,
                badge: kostvMusicBadgeOf(album),
                onTap: () => openKostvMusicAlbum(context, album),
              ),
          ],
        ),
      );
    }
    if (parts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(insets.left, 30, insets.right, 0),
            child: _searching
                ? const Center(
                    child: CircularProgressIndicator(color: kostvMusicColor),
                  )
                : Text(
                    l10n.kostvMusicNoResults(_query),
                    style: const TextStyle(color: kostvMusicGrey, fontSize: 17),
                  ),
          ),
        ),
      ];
    }
    return [SliverList.list(children: parts)];
  }
}
