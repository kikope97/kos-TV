import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music_dislikes.dart';
import '../../../data/services/kostv_music_plugin.dart' show KostvMusicSource;
import '../../../data/viewmodels/item_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/music/design/kostv_music_design.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/music_navigation.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_album_play.dart';
import 'kostv_music_dislike.dart';
import 'kostv_music_links.dart';
import 'kostv_music_page.dart';
import 'kostv_music_widgets.dart';
import '../../../util/kostv_browser_menu.dart';

enum _ArtistChoice { playlist, dislike }

/// Kos TV: an artist of the home server, as the page of an artist the
/// requests service knows (`docs/diseno-musica`): their picture big at the
/// top, their name in the brand's letters, the play button, «Aleatorio»,
/// ♥ and «⋯» (add them to a list, «No me pongas a este artista»), their
/// most played songs, their albums (each with its ▶) and similar artists.
class KostvHomeArtistView extends StatefulWidget {
  const KostvHomeArtistView({
    super.key,
    required this.viewModel,
    this.initialFocusNode,
  });

  final ItemDetailViewModel viewModel;

  /// The node the page's focus starts on, for Play.
  final FocusNode? initialFocusNode;

  @override
  State<KostvHomeArtistView> createState() => _KostvHomeArtistViewState();
}

class _KostvHomeArtistViewState extends State<KostvHomeArtistView> {
  final _playFocus = FocusNode(debugLabel: 'kostvHomeArtistPlay');

  ItemDetailViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    // Its songs have a menu of their own on a right click.
    kostvHoldBrowserMenu();
    KostvMusicDislikesStore.instance.addListener(_changed);
    final shown = _vm.item;
    if (shown != null) unawaited(kostvMusicDislikesReady(shown));
  }

  @override
  void dispose() {
    KostvMusicDislikesStore.instance.removeListener(_changed);
    kostvReleaseBrowserMenu();
    _playFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _play({int index = 0, bool shuffle = false, List<AggregatedItem>? of}) {
    final tracks = of ?? _vm.tracks;
    if (tracks.isEmpty) {
      _nothingToPlay();
      return;
    }
    unawaited(
      kostvMusicOnce(
        () => playMusicTracks(
          context,
          shuffle ? (List<AggregatedItem>.of(tracks)..shuffle()) : tracks,
          startIndex: shuffle ? 0 : index,
          source: KostvMusicSource.artist,
        ),
      ),
    );
  }

  /// Kos TV: Play with no songs says why, rather than doing nothing.
  void _nothingToPlay() {
    if (_vm.state == ItemDetailState.loading) return;
    final l10n = AppLocalizations.of(context);
    kostvMusicSay(
      context,
      _vm.tracksFailed ? l10n.kostvMusicTracksFailed : l10n.kostvMusicCantPlay,
    );
  }

  Future<void> _more(AggregatedItem artist) async {
    final l10n = AppLocalizations.of(context);
    final canDislike = kostvMusicCanDislike(artist);
    final disliked = canDislike && kostvMusicDisliked(artist.id, artist);
    final choice = await showKostvMusicMenu<_ArtistChoice>(
      context,
      title: artist.name,
      entries: [
        if (_vm.tracks.isNotEmpty)
          KostvMenuEntry(
            _ArtistChoice.playlist,
            Icons.playlist_add_rounded,
            l10n.kostvPlayerAddToPlaylist,
          ),
        if (canDislike)
          KostvMenuEntry(
            _ArtistChoice.dislike,
            Icons.person_off_outlined,
            disliked ? l10n.kostvMusicUndislike : l10n.kostvMusicDislikeArtist,
          ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _ArtistChoice.playlist:
        await AddToPlaylistDialog.show(
          context,
          itemIds: [for (final track in _vm.tracks) track.id],
          serverId: artist.serverId,
        );
      case _ArtistChoice.dislike:
        unawaited(
          disliked
              ? kostvUndislike(
                  context,
                  id: artist.id,
                  name: artist.name,
                  from: artist,
                )
              : kostvDislikeArtist(
                  context,
                  id: artist.id,
                  name: artist.name,
                  from: artist,
                ),
        );
    }
  }

  int _plays(AggregatedItem track) =>
      ((track.rawData['UserData'] as Map?)?['PlayCount'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final artist = _vm.item;
    if (artist == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final form = kostvPageForm(context);
    final insets = kostvPageInsets(context);
    final tracks = _vm.tracks;
    final albums = _vm.albums;
    final tag = artist.primaryImageTag;
    final picture = tag == null
        ? null
        : _vm.imageApi.getPrimaryImageUrl(artist.id, maxWidth: 1000, tag: tag);
    // Their most played songs at home; with none played yet, their first.
    final played = tracks.any((t) => _plays(t) > 0);
    final top = played
        ? ([...tracks]..sort((a, b) => _plays(b).compareTo(_plays(a))))
              .take(form == KostvPageForm.tv ? 6 : 5)
              .toList()
        : tracks.take(form == KostvPageForm.tv ? 6 : 5).toList();
    final favorite = artist.isFavorite;
    final about = artist.overview?.trim();
    final rows = [
      for (final (i, track) in top.indexed)
        KostvMusicSongRow(
          title: track.name,
          artistLinks: [
            [
              ?kostvHomeAlbumLink(
                track,
                open: (location) => unawaited(context.push(location)),
              ),
            ],
          ],
          artist: track.album,
          cover: kostvMusicImageOf(track),
          rank: i + 1,
          atHome: true,
          duration: track.runtime?.inSeconds,
          soundingId: track.id,
          onTap: () => _play(index: i, of: top),
          onLongPress: () => unawaited(
            showKostvMusicSongMenu(
              context,
              item: track,
              source: KostvMusicSource.artist,
            ),
          ),
        ),
    ];
    return KostvArtworkWash(
      url: picture,
      strength: 0.5,
      at: const Alignment(0.6, -1.1),
      child: ListView(
        padding: EdgeInsets.only(bottom: kostvPageBottom(context)),
        children: [
          KostvArtistHero(
            name: artist.name,
            kicker: l10n.kostvMusicArtistKicker,
            picture: picture,
            meta: [
              ...artist.genres.take(1),
              if (albums.isNotEmpty) l10n.kostvMusicAlbumCount(albums.length),
            ].join(' · '),
            play: (diameter) => KostvPlayButton(
              revealFromTop: true,
              focusNode: widget.initialFocusNode ?? _playFocus,
              diameter: diameter,
              tooltip: l10n.play,
              autofocus: PlatformDetection.isTV,
              onTap: _play,
            ),
            pill: tracks.length > 1
                ? (size) => KostvPillButton(
                    icon: Icons.shuffle_rounded,
                    label: l10n.shuffle,
                    size: size,
                    onTap: () => _play(shuffle: true),
                  )
                : null,
            round: [
              (diameter) => KostvRoundButton(
                icon: favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: favorite ? KostvMusicTokens.pink : KostvMusicTokens.ink,
                tooltip: l10n.favorite,
                diameter: diameter,
                onTap: () => unawaited(_vm.toggleFavorite()),
              ),
              if (tracks.isNotEmpty || kostvMusicCanDislike(artist))
                (diameter) => KostvRoundButton(
                  icon: Icons.more_horiz_rounded,
                  tooltip: l10n.more,
                  diameter: diameter,
                  onTap: () => unawaited(_more(artist)),
                ),
            ],
          ),
          if (about != null && about.isNotEmpty) ...[
            const SizedBox(height: 18),
            Padding(
              padding: EdgeInsets.fromLTRB(insets.left, 0, insets.right, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Text(
                    about,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KostvMusicTokens.muted,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (rows.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                insets.left - 12,
                0,
                insets.right - 12,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: form == KostvPageForm.tv ? double.infinity : 900,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      KostvShelfHeader(
                        title: played
                            ? l10n.kostvMusicPopular
                            : l10n.kostvMusicArtistSongs,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      ),
                      FocusTraversalGroup(
                        child: form == KostvPageForm.tv && rows.length >= 4
                            ? KostvTwoColumns(rows: rows)
                            : Column(children: rows),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ] else if (_vm.state == ItemDetailState.loading) ...[
            const Center(
              child: CircularProgressIndicator(color: kostvMusicColor),
            ),
            const SizedBox(height: 30),
          ],
          if (albums.isNotEmpty) ...[
            KostvMusicShelf(
              title: l10n.kostvMusicDiscography,
              insets: insets,
              children: [
                for (final album in albums)
                  KostvMusicAlbumTile(
                    title: album.name,
                    subtitle: album.productionYear?.toString(),
                    cover: kostvMusicImageOf(album),
                    // Kos TV: its ▶ plays it whole, without opening it.
                    onPlay: () => unawaited(playKostvHomeAlbum(context, album)),
                    onTap: () => openMusicItem(context, album),
                  ),
              ],
            ),
            const SizedBox(height: 30),
          ],
          if (_vm.similar.isNotEmpty)
            KostvMusicShelf(
              title: l10n.kostvMusicSimilar,
              insets: insets,
              height: KostvMusicSizes.artist + 40,
              children: [
                for (final other in _vm.similar)
                  KostvMusicAlbumTile(
                    circle: true,
                    size: KostvMusicSizes.artist,
                    title: other.name,
                    cover: kostvMusicImageOf(other),
                    onTap: () => openMusicItem(context, other),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
