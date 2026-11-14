import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart' show GlassSettings;

import '../../../data/models/aggregated_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/app_router.dart';
import '../../navigation/destinations.dart';
import '../offline_aware_image.dart';
import 'kostv_now_playing.dart';

/// Kos TV: the floating player. While a song sounds and the person moves
/// around the app, a glass capsule keeps it at hand: in the bottom right
/// corner on the TV and the web, across the bottom on the phone. It goes
/// away with its ✕, when a film or a series starts, and over the players,
/// dialogs and sheets. Where the phone's bottom bar is, the bar carries its
/// own.

/// Whether the floating player shows now, and the space it takes.
class KostvCapsuleVisibility extends ChangeNotifier {
  KostvCapsuleVisibility._() {
    _merged.addListener(_check);
  }

  static final instance = KostvCapsuleVisibility._();

  late final _merged = Listenable.merge([
    KostvNowPlaying.instance,
    KostvNowPlayingRouteObserver.instance.changes,
    PlayerRouteObserver.instance.isPlayerActive,
    appRouter.routerDelegate,
  ]);

  bool _shows = false;
  bool get shows => _shows;

  bool _pending = false;

  /// Whether the pages keep its room at their bottom: also under a dialog
  /// or a sheet (the page under them doesn't jump).
  bool get keepsRoom => _keepsRoom;
  bool _keepsRoom = false;

  /// Told after the frame when the change comes in the middle of one (a
  /// route pushed while the navigator builds): a widget told to rebuild
  /// mid-build in a release build could stay stuck.
  void _notify() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  void _check() {
    final keepsRoom = _compute(underPopups: true);
    if (keepsRoom != _keepsRoom) {
      _keepsRoom = keepsRoom;
      _notify();
    }
    final shows = _compute();
    if (shows == _shows) return;
    if (!shows) {
      _shows = false;
      _notify();
      return;
    }
    // A page just opened says whether it has the bottom bar as it is built:
    // it shows after that frame, so it doesn't blink in and out.
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (_compute() && !_shows) {
        _shows = true;
        _notify();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _compute({bool underPopups = false}) {
    KostvNowPlaying.instance.ensureStarted();
    if (KostvNowPlaying.instance.item == null) return false;
    if (PlayerRouteObserver.instance.isPlayerActive.value) return false;
    final routes = KostvNowPlayingRouteObserver.instance;
    if ((routes.popupOnTop && !underPopups) || routes.bottomBarOnTop) {
      return false;
    }
    String path;
    try {
      path = appRouter.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return false;
    }
    if (path.startsWith('/player/') ||
        path == Destinations.liveTvPlayer ||
        Destinations.isSignedOutRoute(path)) {
      return false;
    }
    return true;
  }

  bool _started = false;

  /// Starts watching, the first time the app's shell is built. Called
  /// while building: what it finds is told after that frame, never in the
  /// middle of it (a widget told to rebuild mid-build in a release build
  /// could stay stuck without rebuilding again).
  void ensureStarted() {
    if (_started) return;
    _started = true;
    scheduleMicrotask(() {
      KostvNowPlaying.instance.ensureStarted();
      _check();
    });
  }

  /// The room the pages leave at their bottom while it shows (none on the
  /// TV, where it shrinks into a corner).
  static double insetFor(BuildContext context) {
    if (PlatformDetection.isTV) return 0;
    final mobile = PlatformDetection.useMobileUi;
    return (mobile ? _Sizes.mobileHeight : _Sizes.webHeight) +
        (mobile ? 8 : _Sizes.webMargin) +
        8;
  }
}

abstract final class _Sizes {
  static const mobileHeight = 62.0;
  static const webHeight = 68.0;
  static const webWidth = 380.0;
  static const webMargin = 20.0;
  static const tvHeight = 76.0;
  static const tvWidth = 420.0;
}

/// The pages under the floating player leave it room at their bottom.
class KostvNowPlayingInset extends StatelessWidget {
  const KostvNowPlayingInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visibility = KostvCapsuleVisibility.instance..ensureStarted();
    if (PlatformDetection.isTV) return child;
    return ListenableBuilder(
      listenable: visibility,
      builder: (context, child) {
        final data = MediaQuery.of(context);
        // With the keyboard up the capsule hides, and its room goes too.
        // Always the same MediaQuery around the app (with or without the
        // room), so the navigator below is never moved in the tree.
        final room = visibility.keepsRoom && data.viewInsets.bottom <= 0;
        final extra = room ? KostvCapsuleVisibility.insetFor(context) : 0.0;
        return MediaQuery(
          data: room
              ? data.copyWith(
                  padding: data.padding.copyWith(
                    bottom: data.padding.bottom + extra,
                  ),
                  viewPadding: data.viewPadding.copyWith(
                    bottom: data.viewPadding.bottom + extra,
                  ),
                )
              : data,
          child: child!,
        );
      },
      child: child,
    );
  }
}

/// The play and pause, next and previous keys of a remote or a keyboard
/// work on the music from any page that doesn't use them itself.
class KostvMediaKeys extends StatelessWidget {
  const KostvMediaKeys({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final music = KostvNowPlaying.instance;
      // Also on the music player itself (not over a film, a game or TV).
      final player = PlayerRouteObserver.instance;
      if (music.item == null ||
          (player.isPlayerActive.value &&
              player.activePlayerRoute != Destinations.audioPlayer)) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.mediaPlayPause ||
          key == LogicalKeyboardKey.mediaPlay && !music.playing ||
          key == LogicalKeyboardKey.mediaPause && music.playing) {
        music.playPause();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaTrackNext ||
          key == LogicalKeyboardKey.mediaFastForward) {
        music.next();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.mediaTrackPrevious ||
          key == LogicalKeyboardKey.mediaRewind) {
        music.previous();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}

/// The floating player, in the app's shell above every page.
class KostvNowPlayingHost extends StatefulWidget {
  const KostvNowPlayingHost({super.key});

  @override
  State<KostvNowPlayingHost> createState() => _KostvNowPlayingHostState();
}

class _KostvNowPlayingHostState extends State<KostvNowPlayingHost> {
  final _visibility = KostvCapsuleVisibility.instance;

  // On the TV it shrinks to its cover while the remote is in use, so it
  // never sits over what is being chosen, and opens again when it rests.
  bool _compact = false;
  Timer? _shrink;
  String? _shownId;

  @override
  void initState() {
    super.initState();
    _visibility
      ..ensureStarted()
      ..addListener(_changed);
    KostvNowPlaying.instance.addListener(_changed);
    if (PlatformDetection.isTV) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    _shrink?.cancel();
    _visibility.removeListener(_changed);
    KostvNowPlaying.instance.removeListener(_changed);
    if (PlatformDetection.isTV) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  void _changed() {
    final id = KostvNowPlaying.instance.item?.id;
    if (id != _shownId) {
      _shownId = id;
      _wake();
    }
    if (mounted) setState(() {});
  }

  /// With the remote in use it keeps to its corner, small, so it never
  /// covers what is being chosen; a new song shows itself for a moment.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !_visibility.shows) return false;
    if (!_compact && mounted) setState(() => _compact = true);
    _shrink?.cancel();
    _shrink = Timer(const Duration(seconds: 5), _wake);
    return false;
  }

  void _wake() {
    if (!PlatformDetection.isTV) return;
    _shrink?.cancel();
    if (_compact && mounted) setState(() => _compact = false);
  }

  @override
  Widget build(BuildContext context) {
    final music = KostvNowPlaying.instance;
    final item = music.item;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final shows = _visibility.shows && item != null && !keyboard;
    final tv = PlatformDetection.isTV;
    final mobile = PlatformDetection.useMobileUi && !tv;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    final Widget capsule = shows
        ? KeyedSubtree(
            key: const ValueKey('kostv-capsule'),
            child: tv
                ? _TvCapsule(item: item, compact: _compact)
                : _TouchCapsule(item: item, mobile: mobile),
          )
        : const SizedBox.shrink(key: ValueKey('kostv-capsule-none'));

    final animated = AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: capsule,
    );

    if (mobile) {
      return Positioned(
        left: 10,
        right: 10,
        bottom: bottom + 8,
        child: animated,
      );
    }
    return Positioned(
      right: tv ? 40 : _Sizes.webMargin + 4,
      bottom: tv ? 32 : _Sizes.webMargin,
      child: animated,
    );
  }
}

void _openPlayer() => appRouter.push(Destinations.audioPlayer);

/// The glass of the capsule, tinted with its cover's colours.
class _CapsuleGlass extends StatelessWidget {
  const _CapsuleGlass({required this.child, required this.radius});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<KostvCoverColors>(
        valueListenable: KostvNowPlaying.instance.colors,
        builder: (context, colors, _) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: _MaybeBlur(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.top.withValues(alpha: 0.86),
                      colors.bottom.withValues(alpha: 0.92),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
}

/// The glass's blur only where the app's glass blurs (the phone's frosted
/// glass), like the rest of its panes: not on the TV or the web, where a
/// live blur over a scrolling page stutters; the tinted colours, nearly
/// opaque, already read well there.
class _MaybeBlur extends StatelessWidget {
  const _MaybeBlur({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      PlatformDetection.isTV || !GlassSettings.blursBackdrop
      ? child
      : BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: GlassSettings.capSigma(24),
            sigmaY: GlassSettings.capSigma(24),
          ),
          child: child,
        );
}

/// The phone's and the web's: touch and mouse.
class _TouchCapsule extends StatefulWidget {
  const _TouchCapsule({required this.item, required this.mobile});

  final AggregatedItem item;
  final bool mobile;

  @override
  State<_TouchCapsule> createState() => _TouchCapsuleState();
}

class _TouchCapsuleState extends State<_TouchCapsule> {
  // Swiped away: gone at once, while the music is still being closed.
  String? _dismissed;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final mobile = widget.mobile;
    if (_dismissed == item.id) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final music = KostvNowPlaying.instance;
    final height = mobile ? _Sizes.mobileHeight : _Sizes.webHeight;
    final radius = mobile ? 18.0 : height / 2;
    final artist = music.artistOf(item);

    final body = _CapsuleGlass(
      radius: radius,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                mobile ? 8 : 10,
                0,
                mobile ? 4 : 10,
                0,
              ),
              child: Row(
                children: [
                  KostvCapsuleCover(
                    item: item,
                    size: height - 16,
                    round: !mobile,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Titles(item: item, artist: artist),
                  ),
                  _CapsuleButton(
                    icon: music.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: music.playing ? l10n.pause : l10n.play,
                    big: true,
                    onTap: music.playPause,
                  ),
                  _CapsuleButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: l10n.next,
                    onTap: music.next,
                  ),
                  _CapsuleButton(
                    icon: Icons.close_rounded,
                    tooltip: l10n.kostvNowPlayingClose,
                    small: true,
                    onTap: music.close,
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              start: radius,
              end: radius,
              bottom: 0,
              child: const KostvCapsuleProgress(),
            ),
          ],
        ),
      ),
    );

    final tappable = Semantics(
      container: true,
      button: true,
      label: '${l10n.kostvNowPlaying}: ${item.name}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openPlayer,
          // Up on the phone, the player rises from it.
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -200) _openPlayer();
          },
          child: body,
        ),
      ),
    );

    if (!mobile) {
      return SizedBox(width: _Sizes.webWidth, child: tappable);
    }
    return Dismissible(
      key: ValueKey('kostv-capsule-${item.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        setState(() => _dismissed = item.id);
        music.close();
      },
      child: tappable,
    );
  }
}

/// The TV's: not a stop of the remote, it shows what sounds and shrinks to
/// its cover when the remote rests. «Reproduciendo» in the menu opens the
/// player.
class _TvCapsule extends StatelessWidget {
  const _TvCapsule({required this.item, required this.compact});

  final AggregatedItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final music = KostvNowPlaying.instance;
    const height = _Sizes.tvHeight;
    final artist = music.artistOf(item);
    return _CapsuleGlass(
      radius: height / 2,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.centerRight,
        child: SizedBox(
          height: height,
          width: compact ? height : _Sizes.tvWidth,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        KostvCapsuleCover(
                          item: item,
                          size: height - 16,
                          round: true,
                        ),
                        if (compact)
                          Container(
                            width: height - 16,
                            height: height - 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.4),
                            ),
                            alignment: Alignment.center,
                            child: KostvEqualizerBars(
                              playing: music.playing,
                              size: 24,
                            ),
                          ),
                      ],
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: _Titles(item: item, artist: artist, big: true),
                      ),
                      const SizedBox(width: 12),
                      KostvEqualizerBars(playing: music.playing, size: 22),
                      const SizedBox(width: 18),
                    ],
                  ],
                ),
              ),
              if (!compact)
                const PositionedDirectional(
                  start: height / 2,
                  end: height / 2,
                  bottom: 0,
                  child: KostvCapsuleProgress(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Titles extends StatelessWidget {
  const _Titles({required this.item, required this.artist, this.big = false});

  final AggregatedItem item;
  final String artist;
  final bool big;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: big ? 17 : 14.5,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      if (artist.isNotEmpty) ...[
        const SizedBox(height: 3),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: big ? 14 : 12.5,
            fontWeight: FontWeight.w500,
            height: 1.15,
          ),
        ),
      ],
    ],
  );
}

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.big = false,
    this.small = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool big;
  final bool small;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: small ? 36 : 42,
        height: 44,
        child: Icon(
          icon,
          size: big ? 30 : (small ? 20 : 26),
          color: Colors.white.withValues(alpha: small ? 0.7 : 1),
        ),
      ),
    ),
  );
}

/// The cover of what sounds.
class KostvCapsuleCover extends StatelessWidget {
  const KostvCapsuleCover({
    super.key,
    required this.item,
    required this.size,
    this.round = false,
  });

  final AggregatedItem item;
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final url = KostvNowPlaying.instance.artUrl(item, maxHeight: 160);
    final placeholder = ColoredBox(
      color: Colors.white.withValues(alpha: 0.1),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.45,
        color: Colors.white.withValues(alpha: 0.6),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(round ? size / 2 : 10),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? placeholder
            : OfflineAwareImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

/// The thin line of how far the song has gone.
class KostvCapsuleProgress extends StatefulWidget {
  const KostvCapsuleProgress({super.key});

  @override
  State<KostvCapsuleProgress> createState() => _KostvCapsuleProgressState();
}

class _KostvCapsuleProgressState extends State<KostvCapsuleProgress> {
  final _subs = <StreamSubscription<dynamic>>[];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    final state = KostvNowPlaying.instance.state;
    if (state == null) return;
    _position = state.position;
    _duration = state.duration;
    _subs.addAll([
      state.positionStream.listen((p) {
        // Only when the line would grow (half a pixel of its widest, 800
        // steps a song): some players tell the position many times a second.
        final total = _duration.inMilliseconds;
        final moved = (p - _position).inMilliseconds.abs();
        if (total > 0 && moved * 800 < total) return;
        if (mounted) setState(() => _position = p);
      }),
      state.durationStream.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    ]);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds;
    final value = total > 0
        ? (_position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;
    return RepaintBoundary(
      child: SizedBox(
        height: 2.5,
        child: ValueListenableBuilder<KostvCoverColors>(
          valueListenable: KostvNowPlaying.instance.colors,
          builder: (context, colors, _) => Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
              ),
              FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                alignment: AlignmentDirectional.centerStart,
                child: ColoredBox(color: colors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bars that dance while the music sounds, and rest when it is paused.
/// Everywhere they show (the menu, the floating player, the player), on a
/// light timer rather than every frame, and still where nothing is seen.
/// Not [animated], they only stand up while it sounds.
class KostvEqualizerBars extends StatefulWidget {
  const KostvEqualizerBars({
    super.key,
    required this.playing,
    this.size = 20,
    this.color = Colors.white,
    this.animated = true,
  });

  final bool playing;
  final double size;
  final Color color;
  final bool animated;

  @override
  State<KostvEqualizerBars> createState() => _KostvEqualizerBarsState();
}

class _KostvEqualizerBarsState extends State<KostvEqualizerBars> {
  // Moved by a timer at about 15 frames a second, not by a ticker: a ticker
  // asks the screen for every frame it can draw (60 a second on a TV, for
  // a few bars), and a few small bars only need to move a little.
  static const _loop = Duration(milliseconds: 1800);
  static const _step = Duration(milliseconds: 66);

  final _t = ValueNotifier<double>(0);
  Timer? _timer;

  bool get _moves => widget.playing && widget.animated;

  @override
  void didUpdateWidget(KostvEqualizerBars old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    // Also still where animations are off (a page underneath, the menu
    // scrolled away or hidden under a trailer).
    final moves = _moves && TickerMode.valuesOf(context).enabled;
    if (moves && _timer == null) {
      _timer = Timer.periodic(_step, (_) {
        _t.value = (_t.value + _step.inMicroseconds / _loop.inMicroseconds) % 1;
      });
    } else if (!moves && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _BarsPainter(
          t: _t,
          // Standing still, a pose with the bars at different heights.
          still: widget.animated ? null : 0.1,
          playing: widget.playing,
          color: widget.color,
        ),
      ),
    ),
  );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.t,
    required this.still,
    required this.playing,
    required this.color,
  }) : super(repaint: t);

  final ValueListenable<double> t;
  final double? still;
  final bool playing;
  final Color color;

  static const _phases = [0.0, 0.55, 0.25, 0.8];
  // Whole turns per loop, so the bars don't jump when it starts again.
  static const _speeds = [2.0, 3.0, 2.0, 4.0];

  @override
  void paint(Canvas canvas, Size size) {
    const count = 4;
    final gap = size.width * 0.12;
    final width = (size.width - gap * (count - 1)) / count;
    final paint = Paint()..color = color;
    final t = still ?? this.t.value;
    for (var i = 0; i < count; i++) {
      final wave = playing
          ? 0.5 + 0.5 * math.sin((t * _speeds[i] + _phases[i]) * 2 * math.pi)
          : 0.0;
      final h = size.height * (0.22 + 0.78 * wave);
      final x = i * (width + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, width, h),
          Radius.circular(width / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.t != t ||
      old.still != still ||
      old.playing != playing ||
      old.color != color;
}
