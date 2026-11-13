import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_widgets.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<StremfinService>()) {
      setState(() => _loading = false);
      return;
    }
    try {
      final detail = await getIt<StremfinService>().musicArtist(
        widget.deezerId,
      );
      if (mounted) setState(() => _detail = detail);
    } catch (e) {
      debugPrint('[Music] Artist failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final insets = calendarChromeInsets(context);
    final phone = KostvMusicSizes.phone;
    final detail = _detail;
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
              ),
            if (detail != null && detail.topSongs.isNotEmpty) ...[
              KostvMusicHeading(
                title: l10n.kostvMusicArtistTopSongs,
                padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 8),
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
                          for (final (i, song) in detail.topSongs.indexed)
                            KostvMusicSongRow(
                              autofocus: i == 0 && PlatformDetection.isTV,
                              title: song.title,
                              artist: song.albumTitle,
                              cover: song.cover,
                              rank: i + 1,
                              atHome: song.inJellyfin,
                              explicit: song.explicit,
                              onTap: () =>
                                  unawaited(openKostvMusicSong(context, song)),
                              onLongPress: () => unawaited(
                                showKostvMusicSongMenu(context, song: song),
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
                  for (final album in detail.albums)
                    KostvMusicAlbumTile(
                      title: album.title,
                      subtitle: album.year?.toString(),
                      cover: album.cover,
                      badge: kostvMusicBadgeOf(album),
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
