import 'dart:async';

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
import 'kostv_music_widgets.dart' show kostvMusicColor;

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
  static final _asking = <String, Future<StremfinAlbum?>>{};
  static const _keep = Duration(minutes: 5);

  static StremfinService? get _service =>
      GetIt.instance.isRegistered<StremfinService>()
      ? GetIt.instance<StremfinService>()
      : null;

  /// What is known of [deezerId] now (null until it is read).
  static StremfinAlbum? known(String deezerId) => _known[deezerId]?.album;

  /// [deezerId] read from the service, unless it was a moment ago (or
  /// [fresh]).
  static Future<StremfinAlbum?> read(String deezerId, {bool fresh = false}) {
    final kept = _known[deezerId];
    if (!fresh && kept != null && DateTime.now().difference(kept.at) < _keep) {
      return Future.value(kept.album);
    }
    return _asking[deezerId] ??= () async {
      try {
        final service = _service;
        if (service == null) return null;
        final detail = await service.musicAlbum(deezerId);
        _known[deezerId] = (album: detail.album, at: DateTime.now());
        return detail.album;
      } catch (_) {
        return kept?.album;
      } finally {
        unawaited(Future<void>.sync(() => _asking.remove(deezerId)));
      }
    }();
  }

  @visibleForTesting
  static void debugReset() {
    _known.clear();
    _asking.clear();
  }
}

/// Kos TV: «No está en casa · en streaming», the pill of «Reproduciendo»
/// for a song heard through the requests service, with «Pedir álbum» next
/// to it: the same ask as the album's page, its state once asked (Pedido,
/// De camino…). Nothing for a song that is at home.
class KostvStreamPill extends StatefulWidget {
  const KostvStreamPill({
    super.key,
    required this.item,
    required this.stop,
    this.big = false,
    this.centred = true,
  });

  final AggregatedItem item;
  final KostvStreamStop stop;
  final bool big;

  /// Kos TV: centred (under a centred title) or from the start (the
  /// phone's titles).
  final bool centred;

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
    final service = GetIt.instance.isRegistered<StremfinService>()
        ? GetIt.instance<StremfinService>()
        : null;
    if (id == null || service == null || _asking) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _asking = true);
    try {
      final result = await service.createMusicRequest(id);
      if (kostvMusicRequestCounts(result.outcome)) {
        kostvTellMusicRequest(
          () => GetIt.instance.isRegistered<MediaServerClient>()
              ? GetIt.instance<MediaServerClient>()
              : null,
          deezerAlbumId: id,
          album: _album?.title ?? widget.item.album,
          artist: _album?.artist ?? widget.item.albumArtist,
        );
      }
      if (!mounted) return;
      kostvMusicSay(context, result.message ?? l10n.kostvMusicAskedDone);
      await _read(fresh: true);
    } catch (e) {
      if (mounted) {
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
    if (!isKostvStream(widget.item)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final big = widget.big;
    final album = _album;
    final fontSize = big ? 16.0 : 13.0;
    final pill = Container(
      padding: EdgeInsets.symmetric(
        horizontal: big ? 16 : 12,
        vertical: big ? 9 : 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_outlined,
            size: big ? 20 : 16,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          SizedBox(width: big ? 8 : 6),
          Flexible(
            child: Text(
              l10n.kostvStreamNotAtHome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    // What the album button says: to ask for it, or how it is once asked.
    final String? label;
    final IconData icon;
    final bool can;
    if (_albumId == null || album?.inJellyfin == true) {
      label = null;
      icon = Icons.add_rounded;
      can = false;
    } else if (album?.download case final download?) {
      label = [
        download.label ?? l10n.kostvMusicOnItsWay,
        if (download.percent != null) '${download.percent} %',
      ].join(' · ');
      icon = Icons.downloading_rounded;
      can = false;
    } else if (album?.request case final request?) {
      label = request.statusLabel ?? l10n.kostvMusicAsked;
      icon = Icons.check_rounded;
      can = false;
    } else if (album != null && !album.canRequest) {
      label = null;
      icon = Icons.add_rounded;
      can = false;
    } else {
      label = l10n.kostvStreamAskAlbum;
      icon = Icons.add_rounded;
      can = true;
    }
    final button = label == null
        ? null
        : widget.stop(
            can ? () => unawaited(_ask()) : null,
            (context, lit) => AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: EdgeInsets.symmetric(
                horizontal: big ? 16 : 12,
                vertical: big ? 9 : 7,
              ),
              decoration: BoxDecoration(
                color: lit
                    ? Colors.white
                    : (can
                          ? kostvMusicColor
                          : Colors.white.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_asking)
                    SizedBox.square(
                      dimension: big ? 18 : 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: lit ? Colors.black : Colors.white,
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: big ? 20 : 16,
                      color: lit ? Colors.black : Colors.white,
                    ),
                  SizedBox(width: big ? 8 : 6),
                  Text(
                    label!,
                    maxLines: 1,
                    style: TextStyle(
                      color: lit ? Colors.black : Colors.white,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
    return Wrap(
      alignment: widget.centred ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: big ? 12 : 8,
      runSpacing: 8,
      children: [pill, ?button],
    );
  }
}

/// Kos TV: «Preparando la canción…» and why, under the cover of a song
/// that isn't at home while the service gets it; after a while, that it is
/// taking longer than usual.
class KostvPreparingNote extends StatelessWidget {
  const KostvPreparingNote({
    super.key,
    required this.slow,
    this.big = false,
    this.centred = true,
    this.compact = false,
  });

  final bool slow;
  final bool big;
  final bool centred;

  /// Only the first line (the floating player's).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final align = centred ? TextAlign.center : TextAlign.start;
    final title = Text(
      compact && slow
          ? l10n.kostvStreamPreparingSlow
          : l10n.kostvStreamPreparing,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: TextStyle(
        color: Colors.white.withValues(alpha: compact ? 0.68 : 0.95),
        fontSize: compact ? (big ? 14 : 12.5) : (big ? 20 : 16),
        fontWeight: compact ? FontWeight.w500 : FontWeight.w700,
        height: 1.15,
      ),
    );
    if (compact) return title;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centred
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: big ? 18 : 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            SizedBox(width: big ? 10 : 8),
            Flexible(child: title),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            slow
                ? l10n.kostvStreamPreparingSlow
                : l10n.kostvStreamPreparingHint,
            key: ValueKey(slow),
            textAlign: align,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: big ? 16 : 13.5,
              height: 1.3,
            ),
          ),
        ),
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
    if (widget.active && !_beat.isAnimating) {
      _beat.repeat(reverse: true);
    } else if (!widget.active && _beat.isAnimating) {
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

/// Kos TV: the small mark of a queue's song that isn't at home.
class KostvStreamMark extends StatelessWidget {
  const KostvStreamMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: AppLocalizations.of(context).kostvStreamOutOfHome,
    child: Icon(
      Icons.cloud_outlined,
      size: size,
      color: Colors.white.withValues(alpha: 0.5),
    ),
  );
}
