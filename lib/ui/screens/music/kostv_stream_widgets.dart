import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/kostv_music_plugin.dart';
import '../../../data/services/stremfin/kostv_stream_song.dart';
import '../../../data/services/stremfin/stremfin_error_text.dart';
import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import 'kostv_music_actions.dart' show kostvMusicSay;
import '../../widgets/music/design/kostv_music_design.dart';

/// Kos TV: how a page's own stop of the remote is made (the player's, so
/// the remote moves through the pill as through the rest of the page).
typedef KostvStreamStop = Widget Function(
  VoidCallback? onTap,
  Widget Function(BuildContext context, bool lit) builder,
);

/// Kos TV: the album of an out-of-home song, as the requests service says
/// it is now (asked for, on its way…), kept a few minutes for every song of
/// it that sounds.
class KostvStreamAlbums {
  KostvStreamAlbums._();

  static final _known = <String, ({StremfinAlbum album, DateTime at})>{};

  /// Kos TV: the Deezer id of each album's artist, as its page said.
  static final _artists = <String, String>{};
  static final _asking = <String, Future<StremfinAlbum?>>{};
  static const _keep = Duration(minutes: 5);

  static StremfinService? get _service =>
      GetIt.instance.isRegistered<StremfinService>()
      ? GetIt.instance<StremfinService>()
      : null;

  /// Kos TV: whose [_known] is (the service's [StremfinService.generation]):
  /// whether an album was asked for is each person's own.
  static int? _generationKnown;

  static int? _generationNow() => _service?.generation;

  /// Forgets what was known for someone else.
  static void _sync() {
    final now = _generationNow();
    if (now == _generationKnown) return;
    _generationKnown = now;
    _known.clear();
    _asking.clear();
  }

  /// What is known of [deezerId] now (null until it is read).
  static StremfinAlbum? known(String deezerId) {
    _sync();
    return _known[deezerId]?.album;
  }

  /// Kos TV: the Deezer id of the album [deezerId]'s artist, once read.
  static String? artistOf(String deezerId) => _artists[deezerId];

  /// [deezerId] read from the service, unless it was a moment ago (or
  /// [fresh]).
  static Future<StremfinAlbum?> read(String deezerId, {bool fresh = false}) {
    _sync();
    final kept = _known[deezerId];
    if (!fresh && kept != null && DateTime.now().difference(kept.at) < _keep) {
      return Future.value(kept.album);
    }
    final generation = _generationKnown;
    late final Future<StremfinAlbum?> asking;
    asking = _asking[deezerId] ??= () async {
      try {
        final service = _service;
        if (service == null) return null;
        final detail = await service.musicAlbum(deezerId);
        final artist = detail.artistDeezerId;
        if (artist != null && artist.isNotEmpty) _artists[deezerId] = artist;
        // Kos TV: read for someone who is no longer signed in: not kept.
        if (_generationNow() != generation) return null;
        _known[deezerId] = (album: detail.album, at: DateTime.now());
        return detail.album;
      } catch (_) {
        return kept?.album;
      } finally {
        // After it is in [_asking] (this may end before that).
        scheduleMicrotask(() {
          if (identical(_asking[deezerId], asking)) _asking.remove(deezerId);
        });
      }
    }();
    return asking;
  }

  @visibleForTesting
  static void debugReset() {
    _known.clear();
    _artists.clear();
    _asking.clear();
    _generationKnown = null;
  }
}

/// Kos TV: asks for the album [deezerId] of a song that isn't at home (its
/// [title] and [artist], told to the server plugin), and says how it went.
/// True when it was asked for.
Future<bool> kostvStreamAskAlbum(
  BuildContext context,
  String deezerId, {
  String? title,
  String? artist,
}) async {
  final service = GetIt.instance.isRegistered<StremfinService>()
      ? GetIt.instance<StremfinService>()
      : null;
  if (service == null) return false;
  final l10n = AppLocalizations.of(context);
  try {
    final result = await service.createMusicRequest(deezerId);
    if (kostvMusicRequestCounts(result.outcome)) {
      kostvTellMusicRequest(
        () => GetIt.instance.isRegistered<MediaServerClient>()
            ? GetIt.instance<MediaServerClient>()
            : null,
        deezerAlbumId: deezerId,
        album: title,
        artist: artist,
      );
    }
    if (context.mounted) {
      kostvMusicSay(context, result.message ?? l10n.kostvMusicAskedDone);
    }
    unawaited(KostvStreamAlbums.read(deezerId, fresh: true));
    return true;
  } catch (e) {
    if (context.mounted) {
      kostvMusicSay(
        context,
        kostvStremfinErrorText(l10n, e, fallback: l10n.kostvMusicCantAskNow),
      );
    }
    return false;
  }
}

/// Kos TV: how the album of a song that isn't at home stands for its
/// «Pedir álbum»: what the button says, and whether it can be asked for
/// now (null: nothing to say, at home or not to be asked for).
({String label, IconData icon, bool can})? kostvStreamAlbumState(
  AppLocalizations l10n,
  StremfinAlbum? album, {
  required bool hasAlbum,
}) {
  if (!hasAlbum || album?.inJellyfin == true) return null;
  if (album?.download case final download?) {
    return (
      label: [
        download.label ?? l10n.kostvMusicOnItsWay,
        if (download.percent != null) '${download.percent} %',
      ].join(' · '),
      icon: Icons.local_shipping_rounded,
      can: false,
    );
  }
  if (album?.request case final request?) {
    return (
      label: request.statusLabel ?? l10n.kostvMusicAskedNotify,
      icon: Icons.check_rounded,
      can: false,
    );
  }
  if (album != null && !album.canRequest) return null;
  return (
    label: l10n.kostvMusicAskTheAlbum,
    icon: Icons.download_rounded,
    can: true,
  );
}

/// Kos TV: the music design's small line of «Reproduciendo» for a song
/// heard through the requests service: «Suena en streaming · no está en
/// casa» and, in the same chip, «Pedir el álbum» (a stop of the remote, the
/// same ask as the album's page), or its state once asked (Pedido · te
/// avisamos, De camino…). Nothing for a song that is at home.
class KostvStreamPill extends StatefulWidget {
  const KostvStreamPill({
    super.key,
    required this.item,
    required this.stop,
    this.big = false,
    this.centred = true,
    this.short = false,
    this.scale = 1,
  });

  final AggregatedItem item;
  final KostvStreamStop stop;

  /// The TV's and the computer's sizes (the phone's otherwise).
  final bool big;

  /// Kos TV: kept for the callers that centre it; the chip is one piece.
  final bool centred;

  /// «En streaming · no está en casa», for the phone's narrow width.
  final bool short;

  /// How much bigger than its own sizes (the TV's screen).
  final double scale;

  @override
  State<KostvStreamPill> createState() => _KostvStreamPillState();
}

class _KostvStreamPillState extends State<KostvStreamPill> {
  StremfinAlbum? _album;
  bool _asking = false;

  String? get _albumId => KostvStreamInfo.of(widget.item)?.albumDeezerId;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(KostvStreamPill old) {
    super.didUpdateWidget(old);
    if (KostvStreamInfo.of(old.item)?.albumDeezerId != _albumId) {
      _album = null;
      unawaited(_read());
    }
  }

  Future<void> _read({bool fresh = false}) async {
    final id = _albumId;
    if (id == null) return;
    _album ??= KostvStreamAlbums.known(id);
    final album = await KostvStreamAlbums.read(id, fresh: fresh);
    if (!mounted || id != _albumId) return;
    setState(() => _album = album ?? _album);
  }

  Future<void> _ask() async {
    final id = _albumId;
    if (id == null || _asking) return;
    setState(() => _asking = true);
    try {
      final asked = await kostvStreamAskAlbum(
        context,
        id,
        title: _album?.title ?? widget.item.album,
        artist: _album?.artist ?? widget.item.albumArtist,
      );
      if (asked && mounted) await _read(fresh: true);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isKostvStream(widget.item)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final k = widget.scale;
    final big = widget.big;
    final fontSize = (big ? 15.0 : 12.0) * k;
    final height = (big ? 40.0 : 34.0) * k;
    // What the album button says: to ask for it, or how it is once asked.
    final state = kostvStreamAlbumState(
      l10n,
      _album,
      hasAlbum: _albumId != null,
    );
    final label = state?.label;
    final can = state?.can ?? false;
    final button = label == null
        ? null
        : widget.stop(
            can ? () => unawaited(_ask()) : null,
            // Kos TV: the chip's link: bold, white with the focus; its
            // state once asked, quiet.
            (context, lit) {
              final ink = lit
                  ? KostvMusicTokens.background
                  : (can ? KostvMusicTokens.ink : KostvMusicTokens.muted);
              return AnimatedContainer(
                duration: KostvMusicTokens.focusDuration,
                constraints: BoxConstraints(minHeight: height - 8 * k),
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: (big ? 12 : 10) * k),
                decoration: BoxDecoration(
                  color: lit ? KostvMusicTokens.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_asking)
                      SizedBox.square(
                        dimension: fontSize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ink,
                        ),
                      )
                    else
                      Icon(
                        state?.icon ?? Icons.download_rounded,
                        size: fontSize + 2 * k,
                        color: ink,
                      ),
                    SizedBox(width: 6 * k),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink,
                          fontSize: fontSize,
                          fontWeight: can ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
    // Kos TV: calm: no cloud, no colour; one chip with the link inside.
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 600 * k;
        return _chip(l10n, button, label, can, fontSize, height, room);
      },
    );
  }

  /// How wide [label] is written at [fontSize] (bold while it can be
  /// asked), with the person's text size.
  static double _labelWidth(
    BuildContext context,
    String label,
    double fontSize,
    bool bold,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        // The app's own letters, as the button is written.
        style: DefaultTextStyle.of(context).style.copyWith(
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  Widget _chip(
    AppLocalizations l10n,
    Widget? button,
    String? label,
    bool can,
    double fontSize,
    double height,
    double room,
  ) {
    final k = widget.scale;
    final big = widget.big;
    return Tooltip(
      message: l10n.kostvMusicAwaySongNote,
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        padding: EdgeInsetsDirectional.fromSTEB(
          (big ? 14 : 12) * k,
          4 * k,
          (button == null ? 14 : 4) * k,
          4 * k,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: fontSize + 2 * k,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            SizedBox(width: 8 * k),
            Flexible(
              child: Text(
                widget.short
                    ? l10n.kostvMusicAwayPlayerLineShort
                    : l10n.kostvMusicAwayPlayerLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: KostvMusicTokens.muted,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (button != null) ...[
              SizedBox(width: 8 * k),
              // «Pedir el álbum» keeps its whole room (the line is cut
              // first), up to most of a narrow chip.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(
                    _labelWidth(context, label!, fontSize, can) +
                        (big ? 50 : 43) * k,
                    room * 0.7,
                  ),
                ),
                child: button,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kos TV: «Preparando la canción…», calm, while the sound of a song that
/// isn't at home is got ready (shown only once it has taken a moment: see
/// `KostvNowPlaying.preparingShown`); after a while, that it is taking
/// longer than usual. Nothing about it not being at home: the player's
/// line already says so.
class KostvPreparingNote extends StatelessWidget {
  const KostvPreparingNote({
    super.key,
    required this.slow,
    this.big = false,
    this.centred = true,
    this.compact = false,
    this.scale = 1,
  });

  final bool slow;
  final bool big;
  final bool centred;

  /// Only the words, no wheel (the floating player's).
  final bool compact;

  /// How much bigger than its own sizes (the TV's screen).
  final double scale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = scale;
    final size = (big ? 14.0 : 12.5) * k;
    final text = AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        slow ? l10n.kostvStreamPreparingSlow : l10n.kostvStreamPreparing,
        key: ValueKey(slow),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: centred ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          color: KostvMusicTokens.muted,
          fontSize: size,
          fontWeight: FontWeight.w500,
          height: 1.15,
        ),
      ),
    );
    if (compact) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: size - 1,
          child: const CircularProgressIndicator(
            strokeWidth: 1.6,
            color: KostvMusicTokens.muted,
          ),
        ),
        SizedBox(width: 8 * k),
        Flexible(child: text),
      ],
    );
  }
}

/// Kos TV: [child] (a cover) gently beating while [active]: the song is
/// being prepared.
class KostvPulse extends StatefulWidget {
  const KostvPulse({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<KostvPulse> createState() => _KostvPulseState();
}

class _KostvPulseState extends State<KostvPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _beat.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(KostvPulse old) {
    super.didUpdateWidget(old);
    // Kos TV: by the change, not by whether it moves: back on while it was
    // still settling (going from one song that isn't at home to another),
    // it beats again rather than staying still.
    if (widget.active == old.active) return;
    if (widget.active) {
      _beat.repeat(reverse: true);
    } else {
      _beat
        ..stop()
        ..animateTo(0, duration: const Duration(milliseconds: 250));
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _beat,
    builder: (context, child) {
      final t = Curves.easeInOut.transform(_beat.value);
      return Opacity(
        opacity: 1 - 0.28 * t,
        child: Transform.scale(scale: 1 - 0.04 * t, child: child),
      );
    },
    child: widget.child,
  );
}
