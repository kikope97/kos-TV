import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/download_service.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/viewmodels/item_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/download_utils.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/music/design/kostv_music_design.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_now_playing.dart';
import '../../widgets/music/music_navigation.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_album_screen.dart';
import 'kostv_music_links.dart';
import 'kostv_music_page.dart';
import 'kostv_music_widgets.dart';
import '../../../util/kostv_browser_menu.dart';

enum _AlbumChoice { playlist, download, artist }

/// Kos TV: an album of the home server, as Apple Music shows one, the same
/// as the page of an album to ask for: the big cover, its title, artist and
/// what it is, the buttons a record has (play, shuffle, ♥ and the rest in a
/// menu: add to a playlist, download, its artist) and its songs, the one
/// sounding marked. Nothing a film has: no trailer, watched, rating or
/// watching together.
class KostvHomeAlbumView extends StatefulWidget {
  const KostvHomeAlbumView({
    super.key,
    required this.viewModel,
    this.initialFocusNode,
  });

  final ItemDetailViewModel viewModel;

  /// The node the page's focus starts on, for Play.
  final FocusNode? initialFocusNode;

  @override
  State<KostvHomeAlbumView> createState() => _KostvHomeAlbumViewState();
}

class _KostvHomeAlbumViewState extends State<KostvHomeAlbumView> {
  final _playFocus = FocusNode(debugLabel: 'kostvHomeAlbumPlay');

  ItemDetailViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    KostvNowPlaying.instance.addListener(_onNowPlaying);
    // With a mouse, the right click is the songs' menu, not the browser's.
    kostvHoldBrowserMenu();
  }

  @override
  void dispose() {
    KostvNowPlaying.instance.removeListener(_onNowPlaying);
    kostvReleaseBrowserMenu();
    _playFocus.dispose();
    super.dispose();
  }

  void _onNowPlaying() {
    if (mounted) setState(() {});
  }

  /// Downloads are offered where they are: not on a TV.
  bool get _canDownload => !PlatformDetection.isTV && userCanDownload();

  String? _coverUrl(AggregatedItem item, int width) {
    final tag = item.primaryImageTag;
    if (tag == null) return null;
    return _vm.imageApi.getPrimaryImageUrl(item.id, maxWidth: width, tag: tag);
  }

  int? _minutes(List<AggregatedItem> tracks) {
    var total = Duration.zero;
    for (final t in tracks) {
      total += t.runtime ?? Duration.zero;
    }
    return total == Duration.zero ? null : (total.inSeconds / 60).round();
  }

  Future<void> _more(BuildContext context, AggregatedItem album) async {
    final l10n = AppLocalizations.of(context);
    final artistId = kostvMusicArtistIdOf(album);
    final choice = await showKostvMusicMenu<_AlbumChoice>(
      context,
      title: album.name,
      subtitle: album.albumArtist,
      entries: [
        KostvMenuEntry(
          _AlbumChoice.playlist,
          Icons.playlist_add_rounded,
          l10n.kostvPlayerAddToPlaylist,
        ),
        if (_canDownload)
          KostvMenuEntry(
            _AlbumChoice.download,
            Icons.download_rounded,
            l10n.download,
          ),
        if (artistId != null)
          KostvMenuEntry(
            _AlbumChoice.artist,
            Icons.person_rounded,
            l10n.kostvPlayerGoToArtist,
          ),
      ],
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _AlbumChoice.playlist:
        await AddToPlaylistDialog.show(
          context,
          itemIds: [album.id],
          serverId: album.serverId,
          songs: kostvPlaylistSongsOf(album, tracks: _vm.tracks),
        );
      case _AlbumChoice.download:
        final tracks = _vm.tracks;
        if (tracks.isEmpty) return;
        GetIt.instance<DownloadService>().downloadItems(tracks);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(l10n.downloadingTitle(album.name, tracks.length)),
            duration: const Duration(seconds: 2),
          ),
        );
      case _AlbumChoice.artist:
        unawaited(
          context.push(Destinations.item(artistId!, serverId: album.serverId)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = _vm.item;
    if (album == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final form = kostvPageForm(context);
    final tracks = _vm.tracks;
    final minutes = _minutes(tracks);
    final kicker = [
      l10n.kostvMusicKindAlbum,
      if (album.productionYear != null) '${album.productionYear}',
    ].join(' · ');
    final counts = [
      if (tracks.isNotEmpty) l10n.kostvMusicTracks(tracks.length),
      if (minutes != null && minutes > 0) l10n.kostvMusicMinutes(minutes),
    ];
    final artist =
        album.albumArtist ??
        (album.artists.isNotEmpty ? album.artists.join(', ') : null);
    // Kos TV: each of its artists opens their page, with the remote too.
    final artistLinks = kostvHomeArtistLinks(
      album,
      albumArtists: true,
      open: (location) => unawaited(context.push(location)),
    );
    final artistId = kostvMusicArtistIdOf(album);
    final favorite = album.isFavorite;
    void play({bool shuffle = false}) => unawaited(
      kostvMusicOnce(
        () => playMusicTracks(
          context,
          shuffle ? (List<AggregatedItem>.of(tracks)..shuffle()) : tracks,
          source: KostvMusicSource.album,
        ),
      ),
    );
    return KostvAlbumPage(
      cover: _coverUrl(album, 600),
      kicker: kicker,
      title: album.name,
      phoneMeta: [kicker, ...counts].join(' · '),
      artist: artist == null && artistLinks.isEmpty
          ? null
          : (form) => KostvAlbumArtistLine(
              form: form,
              picture: artistId == null
                  ? null
                  : _vm.imageApi.getPrimaryImageUrl(artistId, maxWidth: 96),
              meta: form == KostvPageForm.phone ? null : counts.join(' · '),
              name: (style) => artistLinks.any((link) => link.opens)
                  ? KostvMusicLinkButtons(
                      groups: [artistLinks],
                      style: style,
                      oneLine: true,
                    )
                  : Text(
                      artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
            ),
      play: (diameter) => KostvPlayButton(
        revealFromTop: true,
        focusNode: widget.initialFocusNode ?? _playFocus,
        diameter: diameter,
        tooltip: l10n.play,
        autofocus: PlatformDetection.isTV,
        onTap: tracks.isEmpty ? () => _nothingToPlay(context) : play,
      ),
      shuffle: tracks.length > 1
          ? (diameter) => KostvRoundButton(
              icon: Icons.shuffle_rounded,
              tooltip: l10n.shuffle,
              diameter: diameter,
              onTap: () => play(shuffle: true),
            )
          : null,
      like: (diameter) => KostvRoundButton(
        icon: favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: favorite ? KostvMusicTokens.pink : KostvMusicTokens.ink,
        tooltip: l10n.favorite,
        diameter: diameter,
        onTap: () => unawaited(_vm.toggleFavorite()),
      ),
      more: (diameter) => KostvRoundButton(
        icon: Icons.more_horiz_rounded,
        tooltip: l10n.more,
        diameter: diameter,
        onTap: () => unawaited(_more(context, album)),
      ),
      tracks: _tracks(context, album, form),
      body: tracks.isEmpty ? _empty(context) : null,
    );
  }

  /// Kos TV: Play with no songs says why, rather than doing nothing.
  void _nothingToPlay(BuildContext context) {
    if (_vm.state == ItemDetailState.loading) return;
    final l10n = AppLocalizations.of(context);
    kostvMusicSay(
      context,
      _vm.tracksFailed ? l10n.kostvMusicTracksFailed : l10n.kostvMusicCantPlay,
    );
  }

  /// No songs yet: coming, or why not with a way to try again.
  Widget _empty(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_vm.state == ItemDetailState.loading) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: CircularProgressIndicator(color: kostvMusicColor)),
      );
    }
    // Kos TV: the songs failed to load: said, with a way to try again.
    if (_vm.tracksFailed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.kostvMusicTracksFailed,
              style: const TextStyle(color: kostvMusicGrey),
            ),
            const SizedBox(height: 14),
            KostvMusicButton(
              icon: Icons.refresh_rounded,
              label: l10n.retry,
              onTap: () => unawaited(_vm.retryTracks()),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _tracks(
    BuildContext context,
    AggregatedItem album,
    KostvPageForm form,
  ) {
    final tracks = _vm.tracks;
    if (tracks.isEmpty) return const [];
    final multiDisc =
        tracks.map((t) => t.parentIndexNumber ?? 1).toSet().length > 1;
    final albumArtist = album.albumArtist;
    final now = KostvNowPlaying.instance;
    final soundingId = now.item?.id;
    return [
      for (final (i, track) in tracks.indexed)
        KostvMusicTrackRow(
          number: track.indexNumber ?? i + 1,
          disc: multiDisc ? track.parentIndexNumber : null,
          title: track.name,
          // Kos TV: its artist under it off the TV (the design's table and
          // the phone's list), on the TV only when it isn't the album's.
          artist:
              _otherArtist(track, albumArtist) ??
              (form == KostvPageForm.tv ? null : albumArtist),
          textSize: form == KostvPageForm.tv ? 17 : null,
          artistLinks: _otherArtist(track, albumArtist) == null
              ? null
              : kostvHomeArtistLinks(
                  track,
                  open: (location) => unawaited(context.push(location)),
                ),
          duration: track.runtime?.inSeconds,
          sounding: track.id == soundingId,
          soundingPlays: track.id == soundingId && now.playing,
          onTap: () => unawaited(
            kostvMusicOnce(
              () => playMusicTracks(
                context,
                tracks,
                startIndex: i,
                source: KostvMusicSource.album,
              ),
            ),
          ),
          // Kos TV: «Ir al álbum» would be this same page.
          onMenu: () => unawaited(
            showKostvMusicSongMenu(
              context,
              item: track,
              fromAlbumId: album.id,
              source: KostvMusicSource.album,
            ),
          ),
        ),
    ];
  }

  /// A song's artist when it isn't the album's (a duet, a compilation).
  String? _otherArtist(AggregatedItem track, String? albumArtist) {
    final artists = track.artists;
    if (artists.isEmpty) return null;
    final joined = artists.join(', ');
    if (albumArtist != null &&
        joined.toLowerCase() == albumArtist.toLowerCase()) {
      return null;
    }
    return joined;
  }
}
