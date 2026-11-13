import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/kostv_music_preview.dart';
import '../../../data/services/stremfin/stremfin_client.dart'
    show StremfinException;
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_widgets.dart';

/// Kos TV: an album that isn't at home, as Apple Music shows an album: its
/// big cover, title, artist and what it is, the button to ask for it and,
/// under it, its songs (those already at home marked, the one it was opened
/// from picked out). A single whose song is on an album shows that album:
/// the house always asks for the whole album, and the page says why.
class KostvMusicAlbumScreen extends StatefulWidget {
  const KostvMusicAlbumScreen({super.key, required this.deezerId, this.seed});

  final String deezerId;
  final KostvMusicAlbumSeed? seed;

  @override
  State<KostvMusicAlbumScreen> createState() => _KostvMusicAlbumScreenState();
}

class _KostvMusicAlbumScreenState extends State<KostvMusicAlbumScreen> {
  final _preview = KostvMusicPreview();
  final _askFocus = FocusNode(debugLabel: 'kostvMusicAsk');
  StremfinAlbumDetail? _detail;

  /// The single it was opened as, when the album asked for is another,
  /// and the song of it that is on that album.
  StremfinAlbum? _single;
  String? _singleSong;
  bool _loading = true;
  bool _asking = false;
  Object? _error;

  StremfinService? get _stremfin =>
      GetIt.instance.isRegistered<StremfinService>()
      ? GetIt.instance<StremfinService>()
      : null;

  @override
  void initState() {
    super.initState();
    _preview.addListener(_onPreview);
    // With a mouse, the right click is the songs' menu, not the browser's.
    if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
    unawaited(_load());
  }

  @override
  void dispose() {
    if (kIsWeb) unawaited(BrowserContextMenu.enableContextMenu());
    _preview
      ..removeListener(_onPreview)
      ..dispose();
    _askFocus.dispose();
    super.dispose();
  }

  void _onPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final stremfin = _stremfin;
    if (stremfin == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      var detail = await stremfin.musicAlbum(widget.deezerId);
      final instead = detail.albumInstead?.deezerId;
      if (instead != null) {
        _single = detail.album;
        _singleSong = detail.albumInstead?.contains ?? detail.album.title;
        // The album the single is on; if it can't be had, the single.
        try {
          detail = await stremfin.musicAlbum(instead);
        } catch (_) {
          _single = null;
          _singleSong = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  Future<void> _ask() async {
    final detail = _detail;
    final stremfin = _stremfin;
    final id = detail?.album.deezerId;
    if (detail == null || stremfin == null || id == null || _asking) return;
    final l10n = AppLocalizations.of(context);
    // Asking stops the 30 seconds (and gives the music back).
    unawaited(_preview.stop());
    setState(() => _asking = true);
    try {
      final result = await stremfin.createMusicRequest(id);
      if (!mounted) return;
      kostvMusicSay(context, result.message ?? l10n.kostvMusicAskedDone);
      await _load();
    } catch (e) {
      if (mounted) {
        // The service's own words when it has them («hay mucha gente
        // pidiendo…»), otherwise ours.
        final said = e is StremfinException ? e.message : null;
        kostvMusicSay(context, said ?? l10n.kostvMusicCantAskNow);
      }
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = calendarChromeInsets(context);
    final phone = KostvMusicSizes.phone;
    final seed = widget.seed?.album;
    final album = _detail?.album ?? seed;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: NavigationLayout(
        activeRoute: Destinations.kostvMusic,
        showBackButton: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The cover, blurred and dark, behind the top of the page.
            if (album?.cover != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: phone ? 420 : 520,
                // Blurred once when it loads, and its own layer: the list
                // scrolling over it doesn't blur it again on every frame.
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
                        imageUrl: album!.cover!,
                        fit: BoxFit.cover,
                        maxWidth: 300,
                        blurSigma: 50,
                        errorBuilder: (context, _, _) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            if (album == null && _loading)
              const Center(
                child: CircularProgressIndicator(color: kostvMusicColor),
              )
            else if (album == null)
              Center(
                child: Text(
                  AppLocalizations.of(context).kostvMusicUnavailable,
                  style: const TextStyle(color: kostvMusicGrey),
                ),
              )
            else
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
                      ? _headerStacked(context, album)
                      : _headerSideBySide(context, album),
                  const SizedBox(height: 26),
                  ..._tracks(context),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _headerSideBySide(BuildContext context, StremfinAlbum album) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      _cover(album, 300),
      const SizedBox(width: 36),
      Expanded(child: _info(context, album, centred: false)),
    ],
  );

  Widget _headerStacked(BuildContext context, StremfinAlbum album) => Column(
    children: [
      _cover(album, MediaQuery.sizeOf(context).width * 0.66),
      const SizedBox(height: 20),
      _info(context, album, centred: true),
    ],
  );

  Widget _cover(StremfinAlbum album, double size) => DecoratedBox(
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
    child: KostvMusicCover(url: album.cover, size: size, radius: 14),
  );

  Widget _info(
    BuildContext context,
    StremfinAlbum album, {
    required bool centred,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = _detail;
    final phone = KostvMusicSizes.phone;
    final kind = switch (album.kind) {
      StremfinAlbumKind.ep => l10n.kostvMusicKindEp,
      StremfinAlbumKind.single => l10n.kostvMusicKindSingle,
      StremfinAlbumKind.album => l10n.kostvMusicKindAlbum,
    };
    final minutes = detail?.duration == null
        ? null
        : (detail!.duration! / 60).round();
    final meta = [
      kind,
      if (album.year != null) '${album.year}',
      if (detail != null && detail.songs.isNotEmpty)
        l10n.kostvMusicTracks(detail.songs.length),
      if (minutes != null && minutes > 0) l10n.kostvMusicMinutes(minutes),
    ].join(' · ');
    final song = widget.seed?.song ?? _singleSong;
    final whole =
        _single != null ||
        (song != null && album.kind != StremfinAlbumKind.single);
    final why = whole && song != null
        ? l10n.kostvMusicAskWholeAlbum(song, album.title)
        : l10n.kostvMusicAskAlbumWhy;
    final align = centred
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = centred ? TextAlign.center : TextAlign.start;
    final preview = widget.seed?.preview;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          album.title,
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
        if (album.artist != null)
          Text(
            album.artist!,
            textAlign: textAlign,
            style: theme.textTheme.titleMedium?.copyWith(
              color: kostvMusicColor,
              fontWeight: FontWeight.w600,
              fontSize: phone ? 18 : 22,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          meta,
          textAlign: textAlign,
          style: const TextStyle(color: kostvMusicGrey, fontSize: 14),
        ),
        if (detail != null && detail.songsHave > 0 && !album.inJellyfin) ...[
          const SizedBox(height: 4),
          Text(
            l10n.kostvMusicSongsHave(detail.songsHave, detail.songs.length),
            textAlign: textAlign,
            style: const TextStyle(color: kostvMusicGrey, fontSize: 14),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: centred ? WrapAlignment.center : WrapAlignment.start,
          children: [
            _askButton(context, album),
            if (preview != null)
              _MusicButton(
                icon: _preview.isPlaying(preview)
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                label: _preview.isPlaying(preview)
                    ? l10n.kostvMusicStop
                    : l10n.kostvMusicListen,
                onTap: () => unawaited(_preview.toggle(preview)),
              ),
          ],
        ),
        if (!album.inJellyfin) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              why,
              textAlign: textAlign,
              style: const TextStyle(
                color: kostvMusicGrey,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _askButton(BuildContext context, StremfinAlbum album) {
    final l10n = AppLocalizations.of(context);
    if (album.inJellyfin) {
      return _MusicButton(
        icon: Icons.play_arrow_rounded,
        label: l10n.kostvMusicPlayAtHome,
        primary: true,
        autofocus: PlatformDetection.isTV,
        onTap: () {
          unawaited(_preview.stop());
          unawaited(openKostvStremfinAlbum(context, album));
        },
      );
    }
    // Someone else asked for it, or it is coming down already: the person
    // can still ask to be told when it arrives (the service joins them).
    final join = album.canRequest && album.request?.mine != true;
    Widget withJoin(Widget status) => !join
        ? status
        : Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              status,
              _MusicButton(
                focusNode: _askFocus,
                icon: Icons.notifications_active_rounded,
                label: l10n.kostvMusicNotifyMe,
                primary: true,
                busy: _asking,
                autofocus: PlatformDetection.isTV,
                onTap: () => unawaited(_ask()),
              ),
            ],
          );
    final download = album.download;
    if (download != null) {
      return withJoin(
        _MusicButton(
          icon: Icons.downloading_rounded,
          label: [
            download.label ?? l10n.kostvMusicOnItsWay,
            if (download.percent != null) '${download.percent} %',
          ].join(' · '),
          autofocus: PlatformDetection.isTV && !join,
          onTap: () {},
        ),
      );
    }
    final request = album.request;
    if (request != null) {
      return withJoin(
        _MusicButton(
          icon: Icons.check_rounded,
          label: request.statusLabel ?? l10n.kostvMusicAsked,
          autofocus: PlatformDetection.isTV && !join,
          onTap: () {},
        ),
      );
    }
    return _MusicButton(
      focusNode: _askFocus,
      icon: Icons.add_rounded,
      label: l10n.kostvMusicAskAlbum,
      primary: true,
      busy: _asking,
      autofocus: PlatformDetection.isTV,
      onTap: album.canRequest || _detail == null
          ? () => unawaited(_ask())
          : () => kostvMusicSay(context, l10n.kostvMusicCantAsk),
    );
  }

  List<Widget> _tracks(BuildContext context) {
    final detail = _detail;
    if (detail == null) {
      return [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
              child: CircularProgressIndicator(color: kostvMusicColor),
            ),
          )
        else if (_error != null)
          Text(
            AppLocalizations.of(context).kostvMusicUnavailable,
            style: const TextStyle(color: kostvMusicGrey),
          ),
      ];
    }
    final picked = (widget.seed?.song ?? _single?.contains)?.toLowerCase();
    final multiDisc = detail.songs.map((s) => s.disc ?? 1).toSet().length > 1;
    return [
      for (final (i, song) in detail.songs.indexed)
        _TrackRow(
          number: song.position ?? i + 1,
          disc: multiDisc ? song.disc : null,
          title: song.title,
          artist: song.artist != null && song.artist != detail.album.artist
              ? song.artist
              : null,
          duration: song.duration,
          atHome: song.inJellyfin,
          picked: picked != null && song.title.toLowerCase().contains(picked),
          // At home (Stremfin 1.91 says which it is): it plays.
          onTap: song.jellyfinId == null
              ? null
              : () {
                  unawaited(_preview.stop());
                  unawaited(playKostvMusicTrack(context, song.jellyfinId!));
                },
          onMenu: song.jellyfinId == null
              ? null
              : () => unawaited(
                  showKostvMusicSongMenu(
                    context,
                    song: StremfinSong(
                      title: song.title,
                      artist: song.artist ?? detail.album.artist,
                      jellyfinId: song.jellyfinId,
                      inJellyfin: true,
                    ),
                  ),
                ),
        ),
    ];
  }
}

/// A button of the album's page: filled in Music's colour when it is the
/// main one.
class _MusicButton extends StatelessWidget {
  const _MusicButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.busy = false,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool busy;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final phone = KostvMusicSizes.phone;
    return KostvMusicPressable(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: busy ? () {} : onTap,
      builder: (context, lit) {
        final background = lit
            ? Colors.white
            : (primary ? kostvMusicColor : const Color(0xFF2C2C2E));
        final ink = lit ? Colors.black : Colors.white;
        return AnimatedScale(
          scale: lit ? 1.05 : 1,
          duration: const Duration(milliseconds: 160),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: EdgeInsets.symmetric(
              horizontal: phone ? 20 : 26,
              vertical: phone ? 12 : 14,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: AppRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ink,
                    ),
                  )
                else
                  Icon(icon, color: ink, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: ink,
                    fontSize: phone ? 15.5 : 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A song of the album's list.
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.number,
    required this.title,
    this.disc,
    this.artist,
    this.duration,
    this.atHome = false,
    this.picked = false,
    this.onTap,
    this.onMenu,
  });

  final VoidCallback? onTap;

  /// The song's menu, for one at home.
  final VoidCallback? onMenu;
  final int number;
  final int? disc;
  final String title;
  final String? artist;
  final int? duration;
  final bool atHome;
  final bool picked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final length = duration == null
        ? null
        : '${duration! ~/ 60}:${(duration! % 60).toString().padLeft(2, '0')}';
    final onTap = this.onTap;
    if (onTap == null) return _row(context, l10n, length, lit: false);
    return KostvMusicPressable(
      onTap: onTap,
      onLongPress: onMenu,
      builder: (context, lit) => _row(context, l10n, length, lit: lit),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    String? length, {
    required bool lit,
  }) {
    final color = lit
        ? Colors.black
        : (picked ? kostvMusicColor : Colors.white);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: lit ? Colors.white : Colors.transparent,
        borderRadius: lit ? AppRadius.circular(8) : null,
        border: const Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              disc == null ? '$number' : '$disc·$number',
              style: TextStyle(
                color: picked ? kostvMusicColor : kostvMusicGrey,
                fontSize: 15,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: picked ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (artist != null)
                  Text(
                    artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kostvMusicGrey, fontSize: 13),
                  ),
              ],
            ),
          ),
          if (atHome)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: l10n.kostvMusicAtHome,
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF30D158),
                  size: 18,
                ),
              ),
            ),
          if (length != null)
            Text(
              length,
              style: const TextStyle(color: kostvMusicGrey, fontSize: 14),
            ),
        ],
      ),
    );
  }
}
