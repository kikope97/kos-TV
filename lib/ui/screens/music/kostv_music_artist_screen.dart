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
import '../../widgets/music/kostv_stream_play.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_dislike.dart';
import 'kostv_music_links.dart';
import 'kostv_music_album_screen.dart' show KostvMusicButton;
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

  /// Kos TV: «Crear emisora» of the artist: the requests service's radio of
  /// them, what is at home from home.
  Widget? _stationButton(AppLocalizations l10n, StremfinArtistDetail? detail) {
    if (detail == null || !kostvMusicCatalogAll()) return null;
    return KostvMusicButton(
      icon: Icons.radio_rounded,
      label: l10n.kostvMusicRadio,
      onTap: () => unawaited(
        kostvMusicOnce(() => playKostvArtistStation(context, detail.artist)),
      ),
    );
  }

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

  Widget? _dislikeButton(AppLocalizations l10n) {
    final home = _atHome;
    if (home == null || !kostvMusicCanDislike(home)) return null;
    final disliked = kostvMusicDisliked(home.id, home);
    return KostvMusicButton(
      icon: Icons.person_off_outlined,
      label: disliked ? l10n.kostvMusicUndislike : l10n.kostvMusicDislikeArtist,
      onTap: () => unawaited(
        disliked
            ? kostvUndislike(context, id: home.id, name: home.name, from: home)
            : kostvDislikeArtist(
                context,
                id: home.id,
                name: home.name,
                from: home,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dislike = _dislikeButton(l10n);
    final insets = calendarChromeInsets(context);
    final phone = KostvMusicSizes.phone;
    final detail = _detail;
    final all = kostvMusicCatalogAll();
    final station = _stationButton(l10n, detail);
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: NavigationLayout(
        activeRoute: Destinations.kostvMusic,
        showBackButton: true,
        child: ListView(
          padding: EdgeInsets.only(
            top: insets.top + 12,
            bottom:
                MediaQuery.paddingOf(context).bottom +
                (phone && NavigationLayout.usesBottomNavbar ? 110 : 40),
          ),
          children: [
            if (artist != null)
              Padding(
                padding: EdgeInsets.only(
                  left: insets.left,
                  right: insets.right,
                ),
                child: Row(
                  children: [
                    KostvMusicCover(
                      url: artist.picture,
                      size: phone ? 110 : 170,
                      circle: true,
                      icon: Icons.person_rounded,
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: phone ? 28 : 42,
                              letterSpacing: -0.8,
                            ),
                          ),
                          if (detail != null && detail.total > 0)
                            Text(
                              l10n.kostvMusicArtistHave(
                                detail.have,
                                detail.total,
                              ),
                              style: const TextStyle(
                                color: kostvMusicGrey,
                                fontSize: 15,
                              ),
                            ),
                          if (dislike != null || station != null) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [?station, ?dislike],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 28),
            if (detail == null && _loading)
              const Center(
                child: CircularProgressIndicator(color: kostvMusicColor),
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
            if (detail != null && top.isNotEmpty) ...[
              KostvMusicHeading(
                title: l10n.kostvMusicArtistTopSongs,
                padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 8),
                // Kos TV: with «Toda la música», the list plays whole.
                actions: [
                  if (topPlays) ...[
                    KostvMusicRowAction(
                      icon: Icons.play_arrow_rounded,
                      label: l10n.play,
                      primary: true,
                      onTap: () => _playTop(top, picked: false),
                    ),
                    if (top.length > 2)
                      KostvMusicRowAction(
                        icon: Icons.shuffle_rounded,
                        label: l10n.shuffle,
                        onTap: () => _playTop(top, shuffle: true),
                      ),
                  ],
                ],
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: insets.left,
                  right: insets.right,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: FocusTraversalGroup(
                      child: Column(
                        children: [
                          for (final (i, song) in top.indexed)
                            KostvMusicSongRow(
                              autofocus: i == 0 && PlatformDetection.isTV,
                              title: song.title,
                              artist: song.albumTitle,
                              artistLinks: [
                                [?kostvStremfinAlbumLink(context, song)],
                              ],
                              cover: song.cover,
                              rank: i + 1,
                              atHome: song.inJellyfin,
                              away: all && kostvSongPlayable(song),
                              trailing:
                                  all &&
                                      !song.atHome &&
                                      !kostvSongPlayable(song)
                                  ? const Icon(
                                      Icons.album_outlined,
                                      color: kostvMusicGrey,
                                      size: 22,
                                    )
                                  : null,
                              explicit: song.explicit,
                              onRest:
                                  all && !song.atHome && kostvSongPlayable(song)
                                  ? (resting) => resting
                                        ? kostvPrefetchSoon(song)
                                        : kostvPrefetchCancel()
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
                        ],
                      ),
                    ),
                  ),
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
                          i == 0 && top.isEmpty && PlatformDetection.isTV,
                      title: album.title,
                      subtitle: album.year?.toString(),
                      cover: album.cover,
                      // Kos TV: with «Toda la música», asking for it is on
                      // its page.
                      badge: all
                          ? KostvMusicBadge.none
                          : kostvMusicBadgeOf(album),
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
    );
  }
}
