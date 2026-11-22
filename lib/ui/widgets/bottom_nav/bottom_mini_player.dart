import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:playback_core/playback_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../util/audio_artwork_url.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/app_router.dart';
import '../../navigation/destinations.dart';
import '../adaptive/sf_symbol.dart';
import '../music/design/kostv_play_button.dart';
import '../music/kostv_now_playing.dart';
import '../offline_aware_image.dart';
import 'bottom_nav_metrics.dart';
import 'bottom_nav_theme.dart';

enum BottomMiniPlayerVariant {
  /// Its own floating pane above Dock or an expanded Split.
  capsule,

  /// Squeezed between a minimised Split's two buttons.
  inline,

  /// A row inside Strip's surface.
  row,
}

/// Whether the queue holds something the mini player shows. Video plays full
/// screen and has no business in the bar.
///
/// Kos TV: what was downloaded too, which plays from a file rather than a
/// library item (the floating player steps aside for this bar, so it must
/// show it, or nothing does).
bool bottomMiniPlayerHasTrack() => KostvNowPlaying.instance.item != null;

class BottomMiniPlayer extends StatefulWidget {
  final BottomMiniPlayerVariant variant;
  final BottomNavTheme theme;

  const BottomMiniPlayer({
    super.key,
    required this.variant,
    required this.theme,
  });

  @override
  State<BottomMiniPlayer> createState() => _BottomMiniPlayerState();
}

class _BottomMiniPlayerState extends State<BottomMiniPlayer> {
  final _manager = GetIt.instance<PlaybackManager>();
  final _subs = <StreamSubscription>[];

  // A swiped away track must leave the tree on that frame, before the stop
  // it triggers has cleared the queue.
  String? _dismissedItemId;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      _manager.state.playingStream.listen((_) => _rebuild()),
      _manager.queueService.queueChangedStream.listen((_) => _rebuild()),
    ]);
  }

  void _rebuild() {
    final item = _currentItem;
    if (item == null || item.id != _dismissedItemId) _dismissedItemId = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  AggregatedItem? get _currentItem => KostvNowPlaying.instance.item;

  String? _artUrl(AggregatedItem item) => audioArtUrl(
    item,
    clientFactory: GetIt.instance<MediaServerClientFactory>(),
    maxHeight: 120,
  );

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    if (item == null || !item.isAudioLike || item.id == _dismissedItemId) {
      return const SizedBox.shrink();
    }

    final theme = widget.theme;
    final variant = widget.variant;
    final l10n = AppLocalizations.of(context);
    final playing = _manager.state.isPlaying;
    final artist = item.artists.isNotEmpty
        ? item.artists.join(', ')
        : item.albumArtist ?? '';
    final compact = variant == BottomMiniPlayerVariant.inline;
    final artSize = compact ? 38.0 : 42.0;

    final row = Row(
      children: [
        _Artwork(
          url: _artUrl(item),
          size: artSize,
          round: compact,
          color: theme.onBar,
        ),
        SizedBox(width: compact ? 10 : 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.labelStyle.copyWith(
                  color: theme.onBar,
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (artist.isNotEmpty) ...[
                const SizedBox(height: 3),
                // Kos TV: the same for a song that isn't at home.
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.labelStyle.copyWith(
                    color: theme.onBar.withValues(alpha: 0.6),
                    fontSize: compact ? 11.5 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Kos TV: the music design's one play button (the brand's).
        Tooltip(
          message: playing ? l10n.pause : l10n.play,
          child: Semantics(
            button: true,
            label: playing ? l10n.pause : l10n.play,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: playing ? _manager.pause : _manager.resume,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: KostvPlayFace(
                    diameter: compact ? 34 : 38,
                    pause: playing,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!compact)
          _TransportButton(
            icon: Icons.skip_next_rounded,
            tooltip: l10n.next,
            color: theme.onBar.withValues(alpha: 0.85),
            // Kos TV: a skip the person chose, which «Al acabar la
            // canción» mustn't pause.
            onPressed: KostvNowPlaying.instance.next,
          ),
        // Kos TV: the ✕ stops the music and takes the player away.
        if (!compact)
          _TransportButton(
            icon: Icons.close_rounded,
            tooltip: l10n.kostvNowPlayingClose,
            color: theme.onBar.withValues(alpha: 0.6),
            onPressed: () {
              setState(() => _dismissedItemId = item.id);
              KostvNowPlaying.instance.close();
            },
          ),
      ],
    );

    final progress = RepaintBoundary(
      child: _ProgressLine(state: _manager.state, theme: theme),
    );

    final Widget body = switch (variant) {
      BottomMiniPlayerVariant.capsule => SizedBox(
        height: BottomNavMetrics.capsulePlayerHeight,
        child: BottomNavSurface(
          theme: theme,
          radius: BottomNavMetrics.capsulePlayerRadius,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 6, 0),
                child: row,
              ),
              PositionedDirectional(
                start: 18,
                end: 18,
                bottom: 0,
                child: progress,
              ),
            ],
          ),
        ),
      ),
      BottomMiniPlayerVariant.inline => Stack(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 4, 0),
            child: row,
          ),
          PositionedDirectional(start: 22, end: 22, bottom: 0, child: progress),
        ],
      ),
      BottomMiniPlayerVariant.row => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          progress,
          SizedBox(
            height: BottomNavMetrics.rowPlayerHeight - 2,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 0),
              child: row,
            ),
          ),
        ],
      ),
    };

    return Semantics(
      container: true,
      label: l10n.nowPlaying,
      child: Dismissible(
        key: ValueKey('bottom-mini-player-${item.id}'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) {
          setState(() => _dismissedItemId = item.id);
          KostvNowPlaying.instance.close();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => appRouter.push(Destinations.audioPlayer),
          // Kos TV: up, and the player rises from it.
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -200) {
              appRouter.push(Destinations.audioPlayer);
            }
          },
          child: body,
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final String? url;
  final double size;
  final bool round;
  final Color color;

  const _Artwork({
    required this.url,
    required this.size,
    required this.round,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: color.withValues(alpha: 0.10),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * 0.5,
          color: color.withValues(alpha: 0.45),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: AppRadius.circular(round ? size / 2 : 10),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? placeholder
            : OfflineAwareImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 24,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: AdaptiveIcon(icon, size: 24, color: color),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatefulWidget {
  final PlayerState state;
  final BottomNavTheme theme;

  const _ProgressLine({required this.state, required this.theme});

  @override
  State<_ProgressLine> createState() => _ProgressLineState();
}

class _ProgressLineState extends State<_ProgressLine> {
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _position = widget.state.position;
    _duration = widget.state.duration;
    _posSub = widget.state.positionStream.listen((p) {
      // Only when the line would grow by about half a pixel (some players
      // tell the position many times a second).
      final total = _duration.inMilliseconds;
      final moved = (p - _position).inMilliseconds.abs();
      if (total > 0 && moved * 1600 < total) return;
      if (mounted) setState(() => _position = p);
    });
    _durSub = widget.state.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds.toDouble();
    final value = maxMs > 0
        ? (_position.inMilliseconds.toDouble().clamp(0, maxMs) / maxMs)
        : 0.0;
    final accent = widget.theme.accent;
    return SizedBox(
      height: 2,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: widget.theme.onBar.withValues(alpha: 0.10),
            ),
          ),
          FractionallySizedBox(
            widthFactor: value,
            alignment: AlignmentDirectional.centerStart,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent,
                boxShadow: AppColorScheme.isPixel
                    ? null
                    : [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
