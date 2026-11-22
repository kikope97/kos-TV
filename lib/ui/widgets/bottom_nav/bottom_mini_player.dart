import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
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
import '../music/design/kostv_music_tokens.dart';
import '../music/kostv_now_playing.dart';
import '../offline_aware_image.dart';

enum BottomMiniPlayerVariant {
  /// Kos TV: the glass bar's accessory, its own glass pane above the bar.
  capsule,

  /// Inside the gathered bar, between the page's tab and Search.
  inline,
}

/// Whether the queue holds something the mini player shows. Video plays full
/// screen and has no business in the bar.
///
/// Kos TV: what was downloaded too, which plays from a file rather than a
/// library item (the floating player steps aside for this bar, so it must
/// show it, or nothing does).
bool bottomMiniPlayerHasTrack() => KostvNowPlaying.instance.item != null;

/// Kos TV: the music that sounds, in the glass bar (docs/diseno-menu, the
/// accessory `.acc`): the cover, the song and the artist, plain white pause
/// and «next», with a thin line of progress in the gradient along its foot.
/// The bar puts it on its own glass ([KostvGlass]); gathered, the same piece
/// sits between the page's tab and Search.
class BottomMiniPlayer extends StatefulWidget {
  final BottomMiniPlayerVariant variant;

  /// The accessory's height: 54 on the phone, 56 on a tablet, 60 on a
  /// computer.
  final double height;

  const BottomMiniPlayer({super.key, required this.variant, this.height = 54});

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

    final l10n = AppLocalizations.of(context);
    final playing = _manager.state.isPlaying;
    final artist = item.artists.isNotEmpty
        ? item.artists.join(', ')
        : item.albumArtist ?? '';
    // The cover is the accessory's height less 14 (40 on the phone's 54).
    final height = widget.height;
    final artSize = height - 14;

    final row = Row(
      children: [
        _Artwork(
          url: _artUrl(item),
          size: artSize,
          color: KostvMusicTokens.ink,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KostvMusicTokens.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  decoration: TextDecoration.none,
                ),
              ),
              if (artist.isNotEmpty) ...[
                const SizedBox(height: 2),
                // Kos TV: the same for a song that isn't at home.
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: KostvMusicTokens.ink.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Kos TV: plain white pause and «next», 26 px, 8 px apart.
        _TransportButton(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: playing ? l10n.pause : l10n.play,
          color: Colors.white,
          onPressed: playing ? _manager.pause : _manager.resume,
        ),
        const SizedBox(width: 8),
        _TransportButton(
          icon: Icons.skip_next_rounded,
          tooltip: l10n.next,
          color: Colors.white,
          // Kos TV: a skip the person chose, which «Al acabar la
          // canción» mustn't pause.
          onPressed: KostvNowPlaying.instance.next,
        ),
        const SizedBox(width: 6),
        // Kos TV: the music design's capsule has no ✕: it is swiped away
        // (sideways) to stop the music, as before.
      ],
    );

    final progress = RepaintBoundary(
      child: _ProgressLine(state: _manager.state),
    );

    final Widget body = Stack(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(7, 0, 8, 0),
          child: row,
        ),
        PositionedDirectional(start: 22, end: 22, bottom: 3, child: progress),
      ],
    );

    return Semantics(
      container: true,
      label: l10n.nowPlaying,
      // Kos TV: the swipe that stops the music, for a screen reader too.
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.kostvNowPlayingClose):
            KostvNowPlaying.instance.close,
      },
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
  final Color color;

  const _Artwork({required this.url, required this.size, required this.color});

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
      borderRadius: AppRadius.circular(10),
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
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 26,
            height: 44,
            child: OverflowBox(
              maxWidth: 26,
              child: AdaptiveIcon(icon, size: 26, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatefulWidget {
  final PlayerState state;

  const _ProgressLine({required this.state});

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
    // Kos TV: what sounds in the brand's gradient, as everywhere in Music.
    return SizedBox(
      height: 2,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: KostvMusicTokens.ink.withValues(alpha: 0.14),
                borderRadius: const BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: value,
            alignment: AlignmentDirectional.centerStart,
            heightFactor: 1,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                gradient: KostvMusicTokens.gradient,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
