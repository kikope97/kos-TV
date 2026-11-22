import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music_catalog.dart';
import '../../../data/services/kostv_music_dislikes.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/stremfin/stremfin_error_text.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../playback/kostv_stream_playback.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/music/design/kostv_music_design.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_stream_play.dart';
import '../../widgets/navigation_layout.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_dislike.dart';
import 'kostv_music_links.dart';
import 'kostv_music_album_play.dart';
import 'kostv_music_album_screen.dart' show KostvMusicButton;
import 'kostv_music_page.dart';
import 'kostv_music_widgets.dart';
import '../../../util/kostv_browser_menu.dart';

/// Kos TV: an artist the home server may not have all of: their picture
/// and name, how many of their albums are at home, their most played songs,
/// their albums (those at home and those to ask for) and similar artists.
class KostvMusicArtistScreen extends StatefulWidget {
  const KostvMusicArtistScreen({super.key, required this.deezerId, this.seed});

  final String deezerId;
  final StremfinArtist? seed;

  @override
  State<KostvMusicArtistScreen> createState() => _KostvMusicArtistScreenState();
}

class _KostvMusicArtistScreenState extends State<KostvMusicArtistScreen> {
  StremfinArtistDetail? _detail;
  bool _loading = true;

  /// Why it couldn't be read, for what the page says.
  Object? _error;

  StremfinService? _listening;

  @override
  void initState() {
    super.initState();
    // Its songs have a menu of their own on a right click.
    kostvHoldBrowserMenu();
    KostvMusicDislikesStore.instance.addListener(_dislikesChanged);
    // Kos TV: «Qué música enseñar» changed: the songs play (or not) at once.
    KostvMusicCatalog.instance.addListener(_dislikesChanged);
    // Kos TV: the person's age limit read meanwhile (just started): what
    // isn't at home shows, and plays, as it should at once.
    _listening = GetIt.instance.isRegistered<StremfinService>()
        ? (GetIt.instance<StremfinService>()..addListener(_dislikesChanged))
        : null;
    kostvRefreshMusicCatalog();
    unawaited(_load());
  }

  void _dislikesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    KostvMusicDislikesStore.instance.removeListener(_dislikesChanged);
    KostvMusicCatalog.instance.removeListener(_dislikesChanged);
    _listening?.removeListener(_dislikesChanged);
    kostvPrefetchCancel();
    kostvReleaseBrowserMenu();
    super.dispose();
  }

  /// Kos TV: the artist's top songs as one queue from [index] (or all of
  /// them shuffled), what isn't at home through the requests service.
  /// Kos TV: not [picked] from the header's «Reproducir»: no song of it was
  /// chosen, so it doesn't start with one the person doesn't want to hear.
  void _playTop(
    List<StremfinSong> songs, {
    int index = 0,
    bool shuffle = false,
    bool picked = true,
  }) => unawaited(
    playKostvSongList(
      context,
      songs,
      index: index,
      source: KostvMusicSource.artist,
      shuffle: shuffle,
      picked: picked && !shuffle,
    ),
  );

  Future<void> _load() async {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) {
      setState(() => _loading = false);
      return;
    }
    if (!_loading) setState(() => _loading = true);
    try {
      final detail = await getIt<StremfinService>().musicArtist(
        widget.deezerId,
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _error = null;
        });
        unawaited(_findAtHome(detail.artist.name));
      }
    } catch (e) {
      debugPrint('[Music] Artist failed: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Kos TV: the same artist on the home server, for «No me pongas a este
  /// artista» (what plays by itself is the home server's), when the server
  /// plugin keeps it.
  AggregatedItem? _atHome;

  Future<void> _findAtHome(String name) async {
    await kostvMusicDislikesReady();
    if (!mounted || !kostvMusicCanDislike()) return;
    try {
      final found = await kostvMusicService().search(name);
      final wanted = name.trim().toLowerCase();
      final match = found.artists
          .where((a) => a.name.trim().toLowerCase() == wanted)
          .firstOrNull;
      if (mounted && match != null) setState(() => _atHome = match);
    } catch (_) {}
  }

  /// Kos TV: «⋯» of the artist: «No me pongas a este artista» (or undo it)
  /// when the home server has them.
  Future<void> _more(AppLocalizations l10n, String name) async {
    final home = _atHome;
    if (home == null || !kostvMusicCanDislike(home)) return;
    final disliked = kostvMusicDisliked(home.id, home);
    final choice = await showKostvMusicMenu<int>(
      context,
      title: name,
      entries: [
        KostvMenuEntry(
          0,
          Icons.person_off_outlined,
          disliked ? l10n.kostvMusicUndislike : l10n.kostvMusicDislikeArtist,
        ),
      ],
    );
    if (choice != 0 || !mounted) return;
    unawaited(
      disliked
          ? kostvUndislike(context, id: home.id, name: home.name, from: home)
          : kostvDislikeArtist(
              context,
              id: home.id,
              name: home.name,
              from: home,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = kostvPageForm(context);
    final insets = kostvPageInsets(context);
    final detail = _detail;
    final all = kostvMusicCatalogAll();
    // Kos TV: nothing explicit that isn't at home for someone with a limit.
    final hidesExplicit =
        !GetIt.instance.isRegistered<StremfinService>() ||
        GetIt.instance<StremfinService>().hidesExplicitMusic;
    final top = [
      for (final song in detail?.topSongs ?? const <StremfinSong>[])
        if (!all || song.atHome || !song.explicit || !hidesExplicit) song,
    ];
    final topPlays = all && top.any(kostvSongPlayable);
    final artist = detail?.artist ?? widget.seed;
    final home = _atHome;
    final canDislike = home != null && kostvMusicCanDislike(home);
    final albums = detail?.total != null && detail!.total > 0
        ? detail.total
        : (artist?.albums ?? 0);
    final station = detail != null && kostvMusicCatalogAll();
    final width = MediaQuery.sizeOf(context).width;
    final latest = form == KostvPageForm.wide && width >= 1180
        ? _latest(detail)
        : null;
    final rows = [
      for (final (i, song) in top.indexed)
        KostvMusicSongRow(
          // Kos TV: on the TV the remote starts on «Reproducir»; without it
          // (nothing plays from here), on the first song.
          autofocus: i == 0 && PlatformDetection.isTV && !topPlays,
          title: song.title,
          artist: song.albumTitle,
          artistLinks: [
            [?kostvStremfinAlbumLink(context, song)],
          ],
          cover: song.cover,
          rank: i + 1,
          atHome: song.inJellyfin,
          away: all && kostvSongPlayable(song),
          trailing: all && !song.atHome && !kostvSongPlayable(song)
              ? const Icon(
                  Icons.album_outlined,
                  color: kostvMusicGrey,
                  size: 22,
                )
              : null,
          explicit: song.explicit,
          duration: song.duration,
          soundingId: kostvSongSoundingId(song),
          onRest: all && !song.atHome && kostvSongPlayable(song)
              ? (resting) =>
                    resting ? kostvPrefetchSoon(song) : kostvPrefetchCancel()
              : null,
          onTap: () => all && kostvSongPlayable(song)
              ? _playTop(top, index: i)
              : unawaited(
                  openKostvMusicSong(
                    context,
                    song,
                    source: KostvMusicSource.artist,
                  ),
                ),
          onLongPress: () => unawaited(
            showKostvMusicSongMenu(
              context,
              song: song,
              source: KostvMusicSource.artist,
            ),
          ),
        ),
    ];
    final popular = rows.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KostvShelfHeader(
                title: l10n.kostvMusicPopular,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              ),
              FocusTraversalGroup(
                child: form == KostvPageForm.tv && rows.length >= 4
                    ? KostvTwoColumns(rows: rows)
                    : Column(children: rows),
              ),
            ],
          );
    return Scaffold(
      backgroundColor: KostvMusicTokens.background,
      body: NavigationLayout(
        activeRoute: Destinations.kostvMusic,
        showBackButton: true,
        child: KostvArtworkWash(
          url: artist?.picture,
          strength: 0.5,
          at: const Alignment(0.6, -1.1),
          child: ListView(
            padding: EdgeInsets.only(bottom: kostvPageBottom(context)),
            children: [
              if (artist != null)
                KostvArtistHero(
                  name: artist.name,
                  kicker: l10n.kostvMusicArtistKicker,
                  picture: artist.picture,
                  meta: albums > 0 ? l10n.kostvMusicAlbumCount(albums) : null,
                  play: topPlays
                      ? (diameter) => KostvPlayButton(
                          revealFromTop: true,
                          key: const ValueKey('kostvArtistPlay'),
                          diameter: diameter,
                          tooltip: l10n.play,
                          autofocus: PlatformDetection.isTV,
                          onTap: () => _playTop(top, picked: false),
                        )
                      : null,
                  // Kos TV: «Crear emisora» of the artist: the requests
                  // service's radio of them, what is at home from home.
                  pill: station
                      ? (size) => KostvPillButton(
                          icon: Icons.radio_rounded,
                          label: l10n.kostvMusicRadio,
                          size: size,
                          onTap: () => unawaited(
                            kostvMusicOnce(
                              () => playKostvArtistStation(
                                context,
                                detail.artist,
                              ),
                            ),
                          ),
                        )
                      : null,
                  round: [
                    if (topPlays && top.length > 2)
                      (diameter) => KostvRoundButton(
                        icon: Icons.shuffle_rounded,
                        tooltip: l10n.shuffle,
                        diameter: diameter,
                        onTap: () => _playTop(top, shuffle: true),
                      ),
                    if (canDislike)
                      (diameter) => KostvRoundButton(
                        icon: Icons.more_horiz_rounded,
                        tooltip: l10n.more,
                        diameter: diameter,
                        onTap: () => unawaited(_more(l10n, artist.name)),
                      ),
                  ],
                )
              else
                SizedBox(height: insets.top),
              const SizedBox(height: 24),
              if (detail == null && _loading)
                const Center(
                  child: CircularProgressIndicator(
                    color: KostvMusicTokens.violet,
                  ),
                )
              else if (detail == null)
                // Kos TV: why, and a button to read it again, which the
                // remote can reach (with neither picture nor name, the page
                // has nothing else to go to).
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: insets.left),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _error == null
                            ? l10n.kostvMusicUnavailable
                            : kostvStremfinErrorText(
                                l10n,
                                _error!,
                                fallback: l10n.kostvMusicUnavailable,
                              ),
                        style: const TextStyle(color: kostvMusicGrey),
                      ),
                      const SizedBox(height: 14),
                      KostvMusicButton(
                        icon: Icons.refresh_rounded,
                        label: l10n.retry,
                        autofocus: PlatformDetection.isTV,
                        onTap: () => unawaited(_load()),
                      ),
                    ],
                  ),
                ),
              if (popular != null || latest != null) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    insets.left - 12,
                    0,
                    insets.right - 12,
                    0,
                  ),
                  child: latest == null
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: form == KostvPageForm.tv
                                  ? double.infinity
                                  : 900,
                            ),
                            child: popular,
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: popular ?? const SizedBox.shrink(),
                            ),
                            const SizedBox(width: 32),
                            Expanded(flex: 2, child: latest),
                          ],
                        ),
                ),
                const SizedBox(height: 30),
              ],
              if (detail != null && detail.albums.isNotEmpty) ...[
                KostvMusicShelf(
                  title: l10n.kostvMusicDiscography,
                  insets: insets,
                  children: [
                    for (final (i, album) in detail.albums.indexed)
                      KostvMusicAlbumTile(
                        // Without songs of theirs, the remote starts here.
                        autofocus:
                            i == 0 &&
                            top.isEmpty &&
                            !topPlays &&
                            PlatformDetection.isTV,
                        title: album.title,
                        subtitle: album.year?.toString(),
                        cover: album.cover,
                        // Kos TV: with «Toda la música», asking for it is
                        // on its page.
                        badge: all
                            ? KostvMusicBadge.none
                            : kostvMusicBadgeOf(album),
                        // Kos TV: its ▶ plays it whole, without opening it.
                        onPlay: kostvStremfinAlbumPlays(album)
                            ? () => unawaited(
                                playKostvStremfinAlbum(context, album),
                              )
                            : null,
                        onTap: () =>
                            unawaited(openKostvStremfinAlbum(context, album)),
                      ),
                  ],
                ),
                const SizedBox(height: 30),
              ],
              if (detail != null && detail.related.isNotEmpty)
                KostvMusicShelf(
                  title: l10n.kostvMusicSimilar,
                  insets: insets,
                  height: KostvMusicSizes.artist + 40,
                  children: [
                    for (final other in detail.related)
                      KostvMusicAlbumTile(
                        circle: true,
                        size: KostvMusicSizes.artist,
                        title: other.name,
                        cover: other.picture,
                        onTap: () => openKostvMusicArtist(context, other),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kos TV: «Su último disco» (a computer's page, beside «Populares»): the
  /// newest of their albums, with its ▶.
  Widget? _latest(StremfinArtistDetail? detail) {
    if (detail == null || detail.albums.isEmpty) return null;
    final sorted = [...detail.albums]
      ..sort((a, b) => (b.releaseDate ?? '').compareTo(a.releaseDate ?? ''));
    final album =
        sorted.where((a) => a.kind == StremfinAlbumKind.album).firstOrNull ??
        sorted.first;
    final l10n = AppLocalizations.of(context);
    final kicker = [
      l10n.kostvMusicKindAlbum,
      if (album.year != null) '${album.year}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KostvShelfHeader(
            title: l10n.kostvMusicLatestRelease,
            padding: const EdgeInsets.only(bottom: 14),
          ),
          KostvMusicPressable(
            onTap: () => unawaited(openKostvStremfinAlbum(context, album)),
            builder: (context, lit) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KostvFocusFrame(
                  lit: lit,
                  radius: KostvMusicTokens.radiusCover,
                  child: KostvMusicCover(url: album.cover, size: 150),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kicker.toUpperCase(),
                        style: const TextStyle(
                          color: KostvMusicTokens.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.04,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        album.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: KostvMusicType.title(26),
                      ),
                      if (album.tracks != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          l10n.kostvMusicTracks(album.tracks!),
                          style: KostvMusicType.muted(14),
                        ),
                      ],
                      if (kostvStremfinAlbumPlays(album)) ...[
                        const SizedBox(height: 14),
                        KostvPlayButton(
                          diameter: 44,
                          tooltip: l10n.play,
                          onTap: () =>
                              unawaited(playKostvStremfinAlbum(context, album)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
