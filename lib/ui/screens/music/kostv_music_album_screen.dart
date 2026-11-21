import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/services/kostv_music.dart' show kostvMusicSameTitle;
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/kostv_music_preview.dart';
import '../../../data/services/stremfin/stremfin_error_text.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/navigation_layout.dart';
import '../calendar/calendar_common.dart';
import '../../widgets/music/kostv_now_playing_capsule.dart'
    show KostvEqualizerBars;
import '../../widgets/music/kostv_stream_play.dart';
import '../../../playback/kostv_stream_playback.dart';
import '../../../data/services/kostv_music_catalog.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_links.dart';
import 'kostv_music_widgets.dart';
import '../../../util/kostv_browser_menu.dart';

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
    kostvHoldBrowserMenu();
    unawaited(_load());
  }

  @override
  void dispose() {
    kostvPrefetchCancel();
    kostvReleaseBrowserMenu();
    _preview
      ..removeListener(_onPreview)
      ..dispose();
    _askFocus.dispose();
    super.dispose();
  }

  void _onPreview() {
    if (mounted) setState(() {});
  }

  /// The load under way, for an ask pressed while it is.
  Future<void>? _loadingNow;

  Future<void> _load() =>
      _loadingNow ??= _read().whenComplete(() => _loadingNow = null);

  Future<void> _read() async {
    final stremfin = _stremfin;
    if (stremfin == null) {
      setState(() => _loading = false);
      return;
    }
    if (!_loading) setState(() => _loading = true);
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
      // Kos TV: the page left open a moment: its first song that would
      // sound through the service is asked for in advance.
      if (_streamable(detail)) {
        final first = detail.songs.where(kostvTrackPlayable).firstOrNull;
        if (first != null && !first.atHome) {
          kostvPrefetchSoonTrack(first, dwell: const Duration(seconds: 3));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  /// Kos TV: whether the album's songs that aren't at home can be heard
  /// through the service («Toda la música»): one of them at least.
  bool _streamable(StremfinAlbumDetail? detail) =>
      detail != null &&
      !detail.album.inJellyfin &&
      kostvMusicCatalogAll() &&
      detail.songs.any((song) => !song.atHome && kostvTrackPlayable(song));

  /// Kos TV: plays the album from its song [index] (at home from home, the
  /// rest through the service), or all of it shuffled.
  Future<void> _play({int index = 0, bool shuffle = false}) async {
    final detail = _detail;
    if (detail == null) return;
    unawaited(_preview.stop(resume: false));
    await playKostvStreamSongs(
      context,
      kostvAlbumQueueSongs(detail),
      startIndex: index,
      source: KostvMusicSource.album,
      shuffle: shuffle,
    );
  }

  Future<void> _ask() async {
    if (_asking) return;
    final l10n = AppLocalizations.of(context);
    // Kos TV: pressed before the album came, or after it failed to: it is
    // read (again) first, and then asked for if it still can be.
    if (_detail == null) {
      setState(() => _asking = true);
      await _load();
      if (!mounted) return;
      setState(() => _asking = false);
      final loaded = _detail;
      if (loaded == null) {
        kostvMusicSay(
          context,
          kostvStremfinErrorText(
            l10n,
            _error ?? const Object(),
            fallback: l10n.kostvMusicUnavailable,
          ),
        );
        return;
      }
      // What it says now may be another thing (asked for already, at home).
      if (!loaded.album.canRequest ||
          loaded.album.inJellyfin ||
          loaded.album.request != null ||
          loaded.album.download != null) {
        return;
      }
    }
    final detail = _detail;
    final stremfin = _stremfin;
    final id = detail?.album.deezerId;
    if (detail == null || stremfin == null || id == null) return;
    // Asking stops the 30 seconds (and gives the music back).
    unawaited(_preview.stop());
    setState(() => _asking = true);
    try {
      final result = await stremfin.createMusicRequest(id);
      // Kos TV: an album asked for (or joined) tells the server plugin what
      // the person likes, without waiting for it.
      if (kostvMusicRequestCounts(result.outcome)) {
        kostvTellMusicRequest(
          () => GetIt.instance.isRegistered<MediaServerClient>()
              ? GetIt.instance<MediaServerClient>()
              : null,
          deezerAlbumId: id,
          album: detail.album.title,
          artist: detail.album.artist,
        );
      }
      if (!mounted) return;
      kostvMusicSay(context, result.message ?? l10n.kostvMusicAskedDone);
      await _load();
    } catch (e) {
      if (mounted) {
        // Kos TV: why, by the service's error code, in the app's language;
        // otherwise ours.
        kostvMusicSay(
          context,
          kostvStremfinErrorText(l10n, e, fallback: l10n.kostvMusicCantAskNow),
        );
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
                    // Kos TV: faded into the page's colour by a gradient of that
                    // colour over it, the same picture the mask gave, without
                    // the mask's layer on every frame.
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BoundedNetworkImage(
                          imageUrl: album!.cover!,
                          fit: BoxFit.cover,
                          maxWidth: 300,
                          blurSigma: 50,
                          errorBuilder: (context, _, _) =>
                              const SizedBox.shrink(),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x990B0B0D), Color(0xFF0B0B0D)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (album == null && _loading)
              const Center(
                child: CircularProgressIndicator(color: kostvMusicColor),
              )
            else if (album == null)
              Center(child: _retry(context, autofocus: PlatformDetection.isTV))
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
    final artistStyle = theme.textTheme.titleMedium?.copyWith(
      color: kostvMusicColor,
      fontWeight: FontWeight.w600,
      fontSize: phone ? 18 : 22,
    );
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
          // Kos TV: the artist opens their page, with the remote too.
          switch (kostvStremfinArtistLink(
            context,
            album.artist,
            detail?.artistDeezerId,
          )) {
            final link? when link.opens => KostvMusicLinkButtons(
              groups: [
                [link],
              ],
              style: artistStyle ?? const TextStyle(color: kostvMusicColor),
              centred: centred,
            ),
            _ => Text(album.artist!, textAlign: textAlign, style: artistStyle),
          },
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
            // Kos TV: an album that isn't at home plays through the service.
            if (_streamable(detail)) ...[
              KostvMusicButton(
                icon: Icons.play_arrow_rounded,
                label: l10n.play,
                primary: true,
                autofocus: PlatformDetection.isTV,
                onTap: () => unawaited(_play()),
              ),
              KostvMusicButton(
                icon: Icons.shuffle_rounded,
                label: l10n.shuffle,
                onTap: () => unawaited(_play(shuffle: true)),
              ),
            ],
            _askButton(context, album, focusFirst: !_streamable(detail)),
            if (preview != null)
              KostvMusicButton(
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
        if (_streamable(detail)) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text.rich(
              TextSpan(
                children: [
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.cloud_outlined,
                        color: kostvMusicGrey,
                        size: 18,
                      ),
                    ),
                  ),
                  TextSpan(text: l10n.kostvStreamAlbumNote),
                ],
              ),
              textAlign: textAlign,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

  Widget _askButton(
    BuildContext context,
    StremfinAlbum album, {
    bool focusFirst = true,
  }) {
    final l10n = AppLocalizations.of(context);
    if (album.inJellyfin) {
      return KostvMusicButton(
        icon: Icons.play_arrow_rounded,
        label: l10n.kostvMusicPlayAtHome,
        primary: true,
        autofocus: PlatformDetection.isTV && focusFirst,
        onTap: () {
          unawaited(_preview.stop());
          // Kos TV: from its own page: one found at home under no name of
          // its own plays there, rather than this page opening again.
          unawaited(openKostvStremfinAlbum(context, album, shown: _detail));
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
              KostvMusicButton(
                focusNode: _askFocus,
                icon: Icons.notifications_active_rounded,
                label: l10n.kostvMusicNotifyMe,
                primary: true,
                busy: _asking,
                autofocus: PlatformDetection.isTV && focusFirst,
                onTap: () => unawaited(_ask()),
              ),
            ],
          );
    final download = album.download;
    if (download != null) {
      return withJoin(
        KostvMusicButton(
          // Kos TV: a download that failed doesn't show as coming down.
          icon: download.failed
              ? Icons.error_outline_rounded
              : Icons.downloading_rounded,
          label: [
            download.label ?? l10n.kostvMusicOnItsWay,
            if (download.percent != null) '${download.percent} %',
          ].join(' · '),
          // The same node as the ask it took the place of: the focus stays.
          focusNode: join ? null : _askFocus,
          autofocus: PlatformDetection.isTV && !join && focusFirst,
          onTap: () {},
        ),
      );
    }
    final request = album.request;
    if (request != null) {
      return withJoin(
        KostvMusicButton(
          icon: Icons.check_rounded,
          label: request.statusLabel ?? l10n.kostvMusicAsked,
          // The same node as the ask it took the place of: the focus stays.
          focusNode: join ? null : _askFocus,
          autofocus: PlatformDetection.isTV && !join && focusFirst,
          onTap: () {},
        ),
      );
    }
    return KostvMusicButton(
      focusNode: _askFocus,
      icon: Icons.add_rounded,
      label: l10n.kostvMusicAskAlbum,
      // Kos TV: next to «Reproducir», not the main one.
      primary: focusFirst,
      busy: _asking,
      autofocus: PlatformDetection.isTV && focusFirst,
      onTap: album.canRequest || _detail == null
          ? () => unawaited(_ask())
          : () => kostvMusicSay(context, l10n.kostvMusicCantAsk),
    );
  }

  /// Kos TV: «No disponible» with what failed, as a button that reads the
  /// album again (it can be reached with the remote).
  Widget _retry(BuildContext context, {bool autofocus = false}) {
    final l10n = AppLocalizations.of(context);
    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          error == null
              ? l10n.kostvMusicUnavailable
              : kostvStremfinErrorText(
                  l10n,
                  error,
                  fallback: l10n.kostvMusicUnavailable,
                ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: kostvMusicGrey),
        ),
        const SizedBox(height: 14),
        KostvMusicButton(
          icon: Icons.refresh_rounded,
          label: l10n.retry,
          autofocus: autofocus,
          onTap: () => unawaited(_load()),
        ),
      ],
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
          Align(alignment: Alignment.centerLeft, child: _retry(context)),
      ];
    }
    final picked = widget.seed?.song ?? _single?.contains;
    // Kos TV: the song it came from is the one of the same title; only if
    // none is, the one of that title without what is in brackets («Canción
    // (feat. X)» in a chart, «Canción» here). Never one that only has it in
    // its name («Mía» isn't «Mía (Remix)»).
    final exact =
        picked != null &&
        detail.songs.any((song) => kostvMusicSameTitle(song.title, picked));
    bool isPicked(String title) =>
        picked != null && kostvMusicSameTitle(title, picked, loose: !exact);
    final multiDisc = detail.songs.map((s) => s.disc ?? 1).toSet().length > 1;
    return [
      for (final (i, song) in detail.songs.indexed)
        KostvMusicTrackRow(
          number: song.position ?? i + 1,
          disc: multiDisc ? song.disc : null,
          title: song.title,
          artist: song.artist != null && song.artist != detail.album.artist
              ? song.artist
              : null,
          duration: song.duration,
          atHome: song.inJellyfin,
          picked: isPicked(song.title),
          // At home (Stremfin 1.91 says which it is): it plays. Kos TV: with
          // «Toda la música», the rest too, through the service, the album
          // going on from it.
          onTap: _streamable(detail) && kostvTrackPlayable(song)
              ? () => unawaited(_play(index: i))
              : song.jellyfinId == null
              ? null
              : () {
                  // Its own music doesn't come back for a moment between.
                  unawaited(_preview.stop(resume: false));
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
                    source: KostvMusicSource.album,
                  ),
                ),
        ),
    ];
  }
}

/// A button of the album's page: filled in Music's colour when it is the
/// main one.
class KostvMusicButton extends StatelessWidget {
  const KostvMusicButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.busy = false,
    this.autofocus = false,
    this.focusNode,
    this.iconColor,
    this.expand = false,
  });

  /// Fills the width it's given (a phone's row of buttons), the words made
  /// smaller rather than cut when it's tight.
  final bool expand;

  /// The icon's own colour when not lit (a heart that is on).
  final Color? iconColor;
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
      // Kos TV: the buttons sit in a page's header: the focus on them (the
      // first one, as the page opens) keeps the page at its top.
      revealFromTop: true,
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
              horizontal: label.isEmpty
                  ? (phone ? 12 : 14)
                  : (expand ? 10 : (phone ? 20 : 26)),
              vertical: phone ? 12 : 14,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: AppRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
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
                  Icon(icon, color: lit ? ink : (iconColor ?? ink), size: 22),
                if (label.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          color: ink,
                          fontSize: phone ? 15.5 : 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A song of the album's list.
class KostvMusicTrackRow extends StatelessWidget {
  const KostvMusicTrackRow({
    super.key,
    required this.number,
    required this.title,
    this.disc,
    this.artist,
    this.artistLinks,
    this.duration,
    this.atHome = false,
    this.picked = false,
    this.onTap,
    this.onMenu,
    this.sounding = false,
    this.soundingPlays = false,
    this.focusNode,
    this.autofocus = false,
  });

  /// Whether it's the song the player has, and whether it's playing.
  final bool sounding;
  final bool soundingPlays;
  final FocusNode? focusNode;
  final bool autofocus;

  final VoidCallback? onTap;

  /// The song's menu, for one at home.
  final VoidCallback? onMenu;
  final int number;
  final int? disc;
  final String title;
  final String? artist;

  /// Kos TV: [artist] as names that open their pages (see
  /// [KostvMusicLinks]).
  final List<KostvMusicLink>? artistLinks;
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
    // One not at home plays nothing; with a remote or keys (a TV, the web on
    // a computer) it still takes the focus, or the list couldn't be gone
    // down to read the rest.
    if (onTap == null && PlatformDetection.useMobileUi) {
      return _row(context, l10n, length, lit: false);
    }
    return KostvMusicPressable(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap ?? () {},
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
        : (picked || sounding ? kostvMusicColor : Colors.white);
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
            child: sounding
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: KostvEqualizerBars(
                      playing: soundingPlays,
                      size: 16,
                      color: lit ? Colors.black : kostvMusicColor,
                    ),
                  )
                : Text(
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
                if (artistLinks case final links? when links.isNotEmpty)
                  KostvMusicLinks(
                    groups: [links],
                    style: const TextStyle(color: kostvMusicGrey, fontSize: 13),
                  )
                else if (artist != null)
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
