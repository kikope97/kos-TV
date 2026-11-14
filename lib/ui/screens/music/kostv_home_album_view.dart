import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/download_service.dart';
import '../../../data/viewmodels/item_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/download_utils.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_now_playing.dart';
import '../../widgets/music/music_navigation.dart';
import '../../widgets/add_to_playlist_dialog.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_album_screen.dart';
import 'kostv_music_widgets.dart';

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
    if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
  }

  @override
  void dispose() {
    KostvNowPlaying.instance.removeListener(_onNowPlaying);
    if (kIsWeb) unawaited(BrowserContextMenu.enableContextMenu());
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
    final insets = calendarChromeInsets(context);
    final phone = KostvMusicSizes.phone;
    final cover = _coverUrl(album, 300);
    return ColoredBox(
      color: const Color(0xFF0B0B0D),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The cover, blurred and dark, behind the top of the page.
          if (cover != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: phone ? 420 : 520,
              child: RepaintBoundary(
                child: ClipRect(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
                    ).createShader(rect),
                    child: BoundedNetworkImage(
                      imageUrl: cover,
                      fit: BoxFit.cover,
                      maxWidth: 300,
                      blurSigma: 50,
                      errorBuilder: (context, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ListView(
            padding: EdgeInsets.fromLTRB(
              insets.left,
              insets.top + 12,
              insets.right,
              MediaQuery.paddingOf(context).bottom +
                  (phone && NavigationLayout.usesBottomNavbar ? 110 : 40),
            ),
            children: [
              phone || MediaQuery.sizeOf(context).width < 900
                  ? Column(
                      children: [
                        _cover(album, MediaQuery.sizeOf(context).width * 0.66),
                        const SizedBox(height: 20),
                        _info(context, album, centred: true),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _cover(album, 300),
                        const SizedBox(width: 36),
                        Expanded(child: _info(context, album, centred: false)),
                      ],
                    ),
              const SizedBox(height: 26),
              ..._tracks(context, album),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cover(AggregatedItem album, double size) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: AppRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0xAA000000),
          blurRadius: 30,
          offset: Offset(0, 14),
        ),
      ],
    ),
    child: KostvMusicCover(
      url: _coverUrl(album, (size * 2).round()),
      size: size,
      radius: 14,
    ),
  );

  Widget _info(
    BuildContext context,
    AggregatedItem album, {
    required bool centred,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final phone = KostvMusicSizes.phone;
    final tracks = _vm.tracks;
    final minutes = _minutes(tracks);
    final meta = [
      l10n.kostvMusicKindAlbum,
      if (album.productionYear != null) '${album.productionYear}',
      if (tracks.isNotEmpty) l10n.kostvMusicTracks(tracks.length),
      if (minutes != null && minutes > 0) l10n.kostvMusicMinutes(minutes),
    ].join(' · ');
    final artist =
        album.albumArtist ??
        (album.artists.isNotEmpty ? album.artists.join(', ') : null);
    final artistId = kostvMusicArtistIdOf(album);
    final align = centred
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = centred ? TextAlign.center : TextAlign.start;
    final favorite = album.isFavorite;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          album.name,
          textAlign: textAlign,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: phone ? 24 : 34,
            letterSpacing: -0.5,
          ),
        ),
        if (artist != null)
          GestureDetector(
            onTap: artistId == null
                ? null
                : () => context.push(
                    Destinations.item(artistId, serverId: album.serverId),
                  ),
            child: Text(
              artist,
              textAlign: textAlign,
              style: theme.textTheme.titleMedium?.copyWith(
                color: kostvMusicColor,
                fontWeight: FontWeight.w600,
                fontSize: phone ? 18 : 22,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          meta,
          textAlign: textAlign,
          style: const TextStyle(color: kostvMusicGrey, fontSize: 14),
        ),
        const SizedBox(height: 18),
        _buttons(
          phone: phone,
          centred: centred,
          children: [
            KostvMusicButton(
              focusNode: widget.initialFocusNode ?? _playFocus,
              expand: phone,
              icon: Icons.play_arrow_rounded,
              label: l10n.play,
              primary: true,
              autofocus: PlatformDetection.isTV,
              onTap: tracks.isEmpty
                  ? () {}
                  : () => unawaited(playMusicTracks(context, tracks)),
            ),
            if (tracks.length > 1)
              KostvMusicButton(
                expand: phone,
                icon: Icons.shuffle_rounded,
                label: l10n.shuffle,
                onTap: () => unawaited(
                  playMusicTracks(
                    context,
                    List<AggregatedItem>.of(tracks)..shuffle(),
                  ),
                ),
              ),
            KostvMusicButton(
              icon: favorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              iconColor: favorite ? kostvMusicColor : null,
              label: '',
              onTap: () => unawaited(_vm.toggleFavorite()),
            ),
            KostvMusicButton(
              icon: Icons.more_horiz_rounded,
              label: '',
              onTap: () => unawaited(_more(context, album)),
            ),
          ],
        ),
      ],
    );
  }

  /// On a phone, Play and Shuffle share the width with ♥ and … at the end,
  /// in one line; elsewhere they sit side by side.
  Widget _buttons({
    required bool phone,
    required bool centred,
    required List<Widget> children,
  }) {
    if (!phone) {
      return Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: centred ? WrapAlignment.center : WrapAlignment.start,
        children: children,
      );
    }
    return Row(
      spacing: 8,
      children: [
        for (final child in children)
          if (child is KostvMusicButton && child.expand)
            Expanded(child: child)
          else
            child,
      ],
    );
  }

  List<Widget> _tracks(BuildContext context, AggregatedItem album) {
    final tracks = _vm.tracks;
    if (tracks.isEmpty) {
      return [
        if (_vm.state == ItemDetailState.loading)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
              child: CircularProgressIndicator(color: kostvMusicColor),
            ),
          ),
      ];
    }
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
          artist: _otherArtist(track, albumArtist),
          duration: track.runtime?.inSeconds,
          sounding: track.id == soundingId,
          soundingPlays: track.id == soundingId && now.playing,
          onTap: () =>
              unawaited(playMusicTracks(context, tracks, startIndex: i)),
          onMenu: () => unawaited(showKostvMusicSongMenu(context, item: track)),
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
