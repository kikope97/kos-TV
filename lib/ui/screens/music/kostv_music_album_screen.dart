import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/services/kostv_music.dart' show kostvMusicSameTitle;
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/kostv_music_preview.dart';
import '../../../data/services/stremfin/kostv_stream_song.dart'
    show kostvStreamItemFromTrack;
import '../../../data/services/stremfin/stremfin_error_text.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/music/design/kostv_music_design.dart';
import '../../widgets/music/kostv_music_menu.dart';
import '../../widgets/music/kostv_stream_play.dart';
import '../../../playback/kostv_stream_playback.dart';
import '../../../data/services/kostv_music_catalog.dart';
import 'kostv_music_actions.dart';
import 'kostv_music_links.dart';
import 'kostv_music_page.dart';
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
  // Kos TV: «Reproducir» of an album that sounds through the service.
  final _playFocus = FocusNode(debugLabel: 'kostvMusicAlbumPlay');
  StremfinAlbumDetail? _detail;

  /// Kos TV: the ask keeps its element (and the remote's focus) when it
  /// moves from the buttons to the note, as the album comes.
  final _askKey = GlobalKey(debugLabel: 'kostvAlbumAsk');

  /// Kos TV: the small picture of its artist, once the service says it.
  String? _artistPicture;

  /// Kos TV: it has just arrived home while the page was open: «Ya está en
  /// casa» a moment, then the note goes.
  bool _arrived = false;
  Timer? _arrivedTimer;

  /// The single it was opened as, when the album asked for is another,
  /// and the song of it that is on that album.
  StremfinAlbum? _single;
  String? _singleSong;
  bool _loading = true;
  bool _asking = false;
  Object? _error;

  StremfinService? _listening;

  StremfinService? get _stremfin =>
      GetIt.instance.isRegistered<StremfinService>()
      ? GetIt.instance<StremfinService>()
      : null;

  @override
  void initState() {
    super.initState();
    _preview.addListener(_onPreview);
    // Kos TV: the person's age limit read meanwhile (just started): the
    // songs that aren't at home play, or not, at once.
    _listening = _stremfin?..addListener(_onPreview);
    // With a mouse, the right click is the songs' menu, not the browser's.
    kostvHoldBrowserMenu();
    unawaited(_load());
  }

  @override
  void dispose() {
    kostvPrefetchCancel();
    kostvReleaseBrowserMenu();
    _listening?.removeListener(_onPreview);
    _preview
      ..removeListener(_onPreview)
      ..dispose();
    _arrivedTimer?.cancel();
    _askFocus.dispose();
    _playFocus.dispose();
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
      // Kos TV: while it was read, the remote landed on the ask (the main
      // button then); with «Reproducir» in front of it now, it goes there,
      // unless the person has moved (or pressed it already).
      final toPlay =
          PlatformDetection.isTV &&
          _detail == null &&
          !_asking &&
          _askFocus.hasFocus;
      final arrived =
          _detail != null &&
          !_detail!.album.inJellyfin &&
          detail.album.inJellyfin;
      setState(() {
        _detail = detail;
        _loading = false;
        _error = null;
        if (arrived) _arrived = true;
      });
      if (arrived) {
        _arrivedTimer?.cancel();
        _arrivedTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _arrived = false);
        });
      }
      unawaited(_readArtistPicture(detail.artistDeezerId));
      if (toPlay && _streamable(detail)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Still on the ask (or nowhere, had it moved): «Reproducir».
          final now = FocusManager.instance.primaryFocus;
          final lost = now == null || now is FocusScopeNode;
          if (mounted &&
              (_askFocus.hasFocus || lost) &&
              _playFocus.canRequestFocus) {
            _playFocus.requestFocus();
          }
        });
      }
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

  /// Kos TV: the artist's small picture under the title, from what the
  /// service keeps of them (no wait: the page is drawn without it first).
  Future<void> _readArtistPicture(String? deezerId) async {
    final stremfin = _stremfin;
    if (stremfin == null || deezerId == null || _artistPicture != null) return;
    try {
      final artist = await stremfin.musicArtist(deezerId, keep: true);
      final picture = artist.artist.picture;
      if (mounted && picture != null) {
        setState(() => _artistPicture = picture);
      }
    } catch (_) {}
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
    final seed = widget.seed?.album;
    final album = _detail?.album ?? seed;
    return Scaffold(
      backgroundColor: KostvMusicTokens.background,
      body: NavigationLayout(
        activeRoute: Destinations.kostvMusic,
        showBackButton: true,
        child: album == null && _loading
            ? const Center(
                child: CircularProgressIndicator(color: kostvMusicColor),
              )
            : album == null
            ? Center(child: _retry(context, autofocus: PlatformDetection.isTV))
            : _page(context, album),
      ),
    );
  }

  /// Kos TV: the music design's album page ([KostvAlbumPage]), the same as
  /// one at home: only the note under its header says it isn't, with
  /// «Pedir el álbum» and how that stands.
  Widget _page(BuildContext context, StremfinAlbum album) {
    final l10n = AppLocalizations.of(context);
    final detail = _detail;
    final form = kostvPageForm(context);
    final streamable = _streamable(detail);
    final kind = switch (album.kind) {
      StremfinAlbumKind.ep => l10n.kostvMusicKindEp,
      StremfinAlbumKind.single => l10n.kostvMusicKindSingle,
      StremfinAlbumKind.album => l10n.kostvMusicKindAlbum,
    };
    final minutes = detail?.duration == null
        ? null
        : (detail!.duration! / 60).round();
    final kicker = [kind, if (album.year != null) '${album.year}'].join(' · ');
    final counts = [
      if (detail != null && detail.songs.isNotEmpty)
        l10n.kostvMusicTracks(detail.songs.length),
      if (minutes != null && minutes > 0) l10n.kostvMusicMinutes(minutes),
    ];
    final song = widget.seed?.song ?? _singleSong;
    final whole =
        _single != null ||
        (song != null && album.kind != StremfinAlbumKind.single);
    final why = whole && song != null
        ? l10n.kostvMusicAskWholeAlbum(song, album.title)
        : l10n.kostvMusicAskAlbumWhy;
    final preview = widget.seed?.preview;
    final link = kostvStremfinArtistLink(
      context,
      album.artist,
      detail?.artistDeezerId,
    );
    final have = detail != null && detail.songsHave > 0 && !album.inJellyfin
        ? l10n.kostvMusicSongsHave(detail.songsHave, detail.songs.length)
        : null;
    final previewPill = preview == null
        ? null
        : KostvPillButton(
            key: const ValueKey('kostvAlbumPreview'),
            icon: _preview.isPlaying(preview)
                ? Icons.stop_rounded
                : Icons.graphic_eq_rounded,
            label: _preview.isPlaying(preview)
                ? l10n.kostvMusicStop
                : l10n.kostvMusicListen,
            size: form == KostvPageForm.phone
                ? KostvPillSize.s
                : KostvPillSize.m,
            onTap: () => unawaited(_preview.toggle(preview)),
          );
    final arrived = _arrived && album.inJellyfin;
    // Kos TV: on the TV, down from the header's buttons goes to «Pedir el
    // álbum» in the note under them (it is to their right: the remote
    // would skip it for the songs).
    KeyEventResult toAsk(KeyEvent event) {
      if (form != KostvPageForm.tv ||
          !(streamable || arrived) ||
          event.logicalKey != LogicalKeyboardKey.arrowDown ||
          _askFocus.context == null ||
          !_askFocus.canRequestFocus) {
        return KeyEventResult.ignored;
      }
      _askFocus.requestFocus();
      return KeyEventResult.handled;
    }

    // Not at home and not heard through the service («Solo la de casa», a
    // limit): asking for it is what the page offers, as today.
    final askOnly = !album.inJellyfin && !streamable;
    return KostvAlbumPage(
      cover: album.cover,
      kicker: kicker,
      title: album.title,
      phoneMeta: [kicker, ...counts].join(' · '),
      artist: album.artist == null
          ? null
          : (form) => KostvAlbumArtistLine(
              form: form,
              picture: _artistPicture,
              meta: form == KostvPageForm.phone ? null : counts.join(' · '),
              name: (style) => link != null && link.opens
                  ? KostvMusicLinkButtons(
                      groups: [
                        [link],
                      ],
                      style: style,
                      oneLine: true,
                    )
                  : Text(
                      album.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
            ),
      play: album.inJellyfin
          // At home: it plays there (its page at home).
          ? (diameter) => KostvPlayButton(
              revealFromTop: true,
              key: const ValueKey('kostvAlbumPlayAtHome'),
              diameter: diameter,
              tooltip: l10n.kostvMusicPlayAtHome,
              autofocus: PlatformDetection.isTV,
              onTap: () {
                unawaited(_preview.stop());
                // Kos TV: from its own page: one found at home under no
                // name of its own plays there, rather than this page
                // opening again.
                unawaited(
                  openKostvStremfinAlbum(context, album, shown: _detail),
                );
              },
            )
          : streamable
          // Kos TV: each with its own key, so the ask keeps its element
          // (and the remote) when «Reproducir» comes in front of it.
          ? (diameter) => KostvPlayButton(
              revealFromTop: true,
              key: const ValueKey('kostvAlbumPlay'),
              focusNode: _playFocus,
              diameter: diameter,
              tooltip: l10n.play,
              autofocus: PlatformDetection.isTV,
              onKey: toAsk,
              onTap: () => unawaited(_play()),
            )
          : null,
      shuffle: streamable && (detail?.songs.length ?? 0) > 1
          ? (diameter) => KostvRoundButton(
              key: const ValueKey('kostvAlbumShuffle'),
              icon: Icons.shuffle_rounded,
              tooltip: l10n.shuffle,
              diameter: diameter,
              onKey: toAsk,
              onTap: () => unawaited(_play(shuffle: true)),
            )
          : null,
      more: link != null && link.opens
          ? (diameter) => KostvRoundButton(
              icon: Icons.more_horiz_rounded,
              tooltip: l10n.more,
              diameter: diameter,
              onKey: toAsk,
              onTap: () => unawaited(_more(album, link)),
            )
          : null,
      extras: [
        if (askOnly)
          KeyedSubtree(
            key: _askKey,
            child: _askAction(context, album, primary: true),
          ),
        ?previewPill,
      ],
      note: streamable || arrived
          ? (compact) => KostvAwayNote(
              lead: l10n.kostvMusicAwayNoteLead,
              rest: l10n.kostvMusicAwayNoteRest,
              extra: have,
              compact: compact,
              fontSize: compact ? 13 : 15,
              action: KeyedSubtree(
                key: _askKey,
                child: _askAction(context, album, compact: compact),
              ),
            )
          : null,
      // Kos TV: with the note, only what it doesn't say (that the song it
      // came from is asked for with its whole album); without (it can only
      // be asked for), why the whole album.
      under: askOnly || (streamable && whole && song != null)
          ? _quiet([why, if (askOnly && have != null) have].join('\n'))
          : null,
      tracks: _tracks(context, form),
      body: _detail == null ? _waiting(context) : null,
    );
  }

  Widget _quiet(String text) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 620),
    child: Text(
      text,
      style: const TextStyle(
        color: KostvMusicTokens.muted,
        fontSize: 14,
        height: 1.4,
      ),
    ),
  );

  /// Kos TV: «⋯» of an album that isn't at home: its artist.
  Future<void> _more(StremfinAlbum album, KostvMusicLink artist) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showKostvMusicMenu<int>(
      context,
      title: album.title,
      subtitle: album.artist,
      entries: [
        KostvMenuEntry(0, Icons.person_rounded, l10n.kostvPlayerGoToArtist),
      ],
    );
    if (choice == 0 && mounted) artist.onTap?.call();
  }

  /// Kos TV: «Pedir el álbum» and how it stands: «Pedido · te avisamos»,
  /// «De camino», «Ya está en casa» a moment, and «Avísame cuando llegue»
  /// when someone else asked for it. [primary] when it is what the page
  /// offers (it doesn't play: «Solo la de casa»).
  Widget _askAction(
    BuildContext context,
    StremfinAlbum album, {
    bool primary = false,
    bool compact = false,
  }) {
    final l10n = AppLocalizations.of(context);
    final size = compact
        ? KostvPillSize.s
        : (primary ? KostvPillSize.l : KostvPillSize.m);
    // With «Reproducir» first, the remote starts there, not here.
    final first = PlatformDetection.isTV && primary;
    if (_arrived && album.inJellyfin) {
      return KostvPillButton(
        focusNode: _askFocus,
        kind: KostvPillKind.quiet,
        size: size,
        icon: Icons.home_rounded,
        label: l10n.kostvMusicAlreadyHome,
        onTap: () {},
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
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              status,
              KostvPillButton(
                focusNode: _askFocus,
                icon: Icons.notifications_active_rounded,
                label: l10n.kostvMusicNotifyMe,
                size: size,
                busy: _asking,
                autofocus: first,
                onTap: () => unawaited(_ask()),
              ),
            ],
          );
    final download = album.download;
    if (download != null) {
      return withJoin(
        KostvPillButton(
          kind: KostvPillKind.quiet,
          size: size,
          // Kos TV: a download that failed doesn't show as coming down.
          icon: download.failed
              ? Icons.error_outline_rounded
              : Icons.local_shipping_outlined,
          label: [
            download.label ?? l10n.kostvMusicOnItsWay,
            if (download.percent != null) '${download.percent} %',
          ].join(' · '),
          // The same node as the ask it took the place of: the focus stays.
          focusNode: join ? null : _askFocus,
          autofocus: first && !join,
          onTap: () {},
        ),
      );
    }
    final request = album.request;
    if (request != null) {
      return withJoin(
        KostvPillButton(
          kind: KostvPillKind.quiet,
          size: size,
          icon: Icons.check_rounded,
          label: request.mine
              ? l10n.kostvMusicAskedNotify
              : (request.statusLabel ?? l10n.kostvMusicAsked),
          // The same node as the ask it took the place of: the focus stays.
          focusNode: join ? null : _askFocus,
          autofocus: first && !join,
          onTap: () {},
        ),
      );
    }
    return KostvPillButton(
      focusNode: _askFocus,
      icon: Icons.download_rounded,
      label: l10n.kostvMusicAskTheAlbum,
      size: size,
      busy: _asking,
      autofocus: first,
      onTap: album.canRequest || _detail == null
          ? () => unawaited(_ask())
          : () => kostvMusicSay(context, l10n.kostvMusicCantAsk),
    );
  }

  /// While the songs come, or why they didn't.
  Widget? _waiting(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: CircularProgressIndicator(color: kostvMusicColor)),
      );
    }
    if (_error != null) {
      return Align(alignment: Alignment.centerLeft, child: _retry(context));
    }
    return const SizedBox.shrink();
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

  List<Widget> _tracks(BuildContext context, KostvPageForm form) {
    final detail = _detail;
    if (detail == null) return const [];
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
          // Kos TV: its artist under it off the TV (the design's table and
          // the phone's list), on the TV only when it isn't the album's.
          artist: song.artist != null && song.artist != detail.album.artist
              ? song.artist
              : (form == KostvPageForm.tv ? null : detail.album.artist),
          textSize: form == KostvPageForm.tv ? 17 : null,
          duration: song.duration,
          atHome: song.inJellyfin,
          // Kos TV: the small cloud of one that sounds through the service.
          away: _streamable(detail) && !song.atHome && kostvTrackPlayable(song),
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
          // Kos TV: one that sounds through the service, resting on it a
          // couple of seconds (the remote's focus, the mouse) asks for it
          // in advance.
          onRest:
              _streamable(detail) && !song.atHome && kostvTrackPlayable(song)
              ? (resting) => resting
                    ? kostvPrefetchSoonTrack(
                        song,
                        dwell: const Duration(seconds: 2),
                      )
                    : kostvPrefetchCancel()
              : null,
          onMenu: song.jellyfinId == null
              ? _streamMenu(detail, song)
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

  /// Kos TV: the menu of one of the album's songs that sounds through the
  /// requests service («Toda la música»), or null.
  VoidCallback? _streamMenu(
    StremfinAlbumDetail detail,
    StremfinAlbumTrack track,
  ) {
    if (!_streamable(detail) || track.atHome || !kostvTrackPlayable(track)) {
      return null;
    }
    final client = GetIt.instance.isRegistered<MediaServerClient>()
        ? GetIt.instance<MediaServerClient>()
        : null;
    final item = kostvStreamItemFromTrack(
      track,
      detail.album,
      serverId: client?.baseUrl ?? '',
      artistDeezerId: detail.artistDeezerId,
    );
    if (item == null) return null;
    return () => unawaited(
      showKostvMusicSongMenu(
        context,
        item: item,
        fromAlbumDeezerId: detail.album.deezerId,
        source: KostvMusicSource.album,
      ),
    );
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
    this.away = false,
    this.picked = false,
    this.onTap,
    this.onMenu,
    this.sounding = false,
    this.soundingPlays = false,
    this.focusNode,
    this.autofocus = false,
    this.onRest,
    this.textSize,
  });

  /// Kos TV: the size of its title (the TV's album: 17); the design's by
  /// default.
  final double? textSize;

  /// Kos TV: see [KostvMusicPressable.onRest].
  final ValueChanged<bool>? onRest;

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

  /// Kos TV: it isn't at home but sounds through the requests service
  /// («Toda la música»): the small cloud where the home ones have their
  /// tick.
  final bool away;
  final bool picked;

  @override
  Widget build(BuildContext context) {
    // Kos TV: the music design's song row ([KostvSongRow]): no mark of
    // whether it is at home, the number turning into ▶ with the focus or
    // the mouse, and the equalizer on the one that sounds.
    final sound = !sounding
        ? KostvSongSound.none
        : (soundingPlays ? KostvSongSound.playing : KostvSongSound.paused);
    final links = artistLinks;
    final subtitleBuilder = links != null && links.isNotEmpty
        ? (TextStyle style) => KostvMusicLinks(groups: [links], style: style)
        : null;
    final number = disc == null ? '${this.number}' : '$disc·${this.number}';
    final length = kostvSongLength(duration);
    final onTap = this.onTap;
    // One not at home plays nothing; with a remote or keys (a TV, the web on
    // a computer) it still takes the focus, or the list couldn't be gone
    // down to read the rest.
    if (onTap == null && PlatformDetection.useMobileUi) {
      return KostvSongRowFace(
        lit: false,
        sound: sound,
        title: title,
        subtitle: artist,
        subtitleBuilder: subtitleBuilder,
        number: number,
        duration: length,
        picked: picked,
        textSize: textSize,
      );
    }
    return KostvSongRow(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap ?? () {},
      onMenu: onMenu,
      onRest: onRest,
      sound: sound,
      title: title,
      subtitle: artist,
      subtitleBuilder: subtitleBuilder,
      number: number,
      duration: length,
      picked: picked,
      textSize: textSize,
    );
  }
}
