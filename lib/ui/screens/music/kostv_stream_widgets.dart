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
      icon: Icons.downloading_rounded,
      can: false,
    );
  }
  if (album?.request case final request?) {
    return (
      label: request.statusLabel ?? l10n.kostvMusicAsked,
      icon: Icons.check_rounded,
      can: false,
    );
  }
  if (album != null && !album.canRequest) return null;
  return (label: l10n.kostvStreamAskAlbum, icon: Icons.add_rounded, can: true);
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
    final state = kostvStreamAlbumState(
      l10n,
      album,
      hasAlbum: _albumId != null,
    );
    final label = state?.label;
    final icon = state?.icon ?? Icons.add_rounded;
    final can = state?.can ?? false;
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
                  // Kos TV: a long label (what the service says, with its
                  // percentage) or big system text is cut short, rather
                  // than overflowing on a narrow phone.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: lit ? Colors.black : Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                      ),
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

/// Kos TV: the small mark of a song that isn't at home (the queue's, the
/// lists', the floating player's): a cloud, with «No está en casa» for the
/// mouse's pointer and the screen reader.
class KostvStreamMark extends StatelessWidget {
  const KostvStreamMark({super.key, this.size = 16, this.color});

  final double size;

  /// Of the cloud; a soft white by default (on a dark background).
  final Color? color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: AppLocalizations.of(context).kostvStreamOutOfHome,
    child: Icon(
      Icons.cloud_outlined,
      size: size,
      color: color ?? Colors.white.withValues(alpha: 0.5),
    ),
  );
}

/// Kos TV: [child] (a song's artist line) with [KostvStreamMark] right after
/// it when [stream] (the song isn't at home); just [child] when it is.
class KostvStreamMarked extends StatelessWidget {
  const KostvStreamMarked({
    super.key,
    required this.stream,
    required this.child,
    this.size = 14,
    this.color,
    this.centred = false,
  });

  final bool stream;
  final Widget child;
  final double size;
  final Color? color;

  /// Kos TV: centred under a centred title, rather than from the start.
  final bool centred;

  @override
  Widget build(BuildContext context) {
    if (!stream) return child;
    return Row(
      mainAxisSize: centred ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: centred
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Flexible(child: child),
        SizedBox(width: size * 0.4),
        KostvStreamMark(size: size, color: color),
      ],
    );
  }
}
