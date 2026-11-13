import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/background_service.dart';
import '../../../data/services/kostv_favorites_news.dart';
import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/focus/input_mode_tracker.dart';
import '../../../util/platform_detection.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/kostv_favorites_shortcut.dart';

/// Kos TV: what a piece of news says under the series' name: the new season,
/// or how many episodes arrived.
String kostvNewsLine(KostvSeriesNews news, AppLocalizations l10n) =>
    news.newSeason && news.season > 0
    ? l10n.kostvFavoritesSeasonNew(news.season)
    : l10n.kostvFavoritesEpisodesNew(news.count);

/// Kos TV: the big piece at the top of «Mis favoritos» when a favourite
/// series got something new: its artwork, what arrived and a way to watch it
/// at once. One after another when there are several.
class KostvFavoritesNewsHero extends StatefulWidget {
  const KostvFavoritesNewsHero({
    super.key,
    required this.news,
    required this.fresh,
    required this.onWatch,
    required this.onOpen,
    required this.watchNode,
    this.onUp,
    this.onDown,
    this.onLeftEdge,
  });

  final List<KostvSeriesNews> news;

  /// The series whose news came since the person last looked.
  final Set<String> fresh;
  final ValueChanged<AggregatedItem> onWatch;
  final ValueChanged<AggregatedItem> onOpen;

  /// «Ver el episodio», where the page's focus starts.
  final FocusNode watchNode;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeftEdge;

  @override
  State<KostvFavoritesNewsHero> createState() => _KostvFavoritesNewsHeroState();
}

class _KostvFavoritesNewsHeroState extends State<KostvFavoritesNewsHero> {
  static const _every = Duration(seconds: 9);

  final _openNode = FocusNode(debugLabel: 'kostvFavoritesNewsOpen');
  int _at = 0;
  Timer? _timer;

  /// Held still while the person is on it.
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(KostvFavoritesNewsHero old) {
    super.didUpdateWidget(old);
    if (_at >= widget.news.length) _at = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _openNode.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.news.length < 2) return;
    _timer = Timer.periodic(_every, (_) {
      if (!mounted || _held) return;
      _go(1);
    });
  }

  void _go(int step) {
    final count = widget.news.length;
    if (count < 2) return;
    setState(() => _at = (_at + step) % count);
    if (_at < 0) _at += count;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, {required bool watch}) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (event is KeyDownEvent && key.isSelectKey) {
      final news = widget.news[_at];
      watch ? widget.onWatch(news.episode) : widget.onOpen(news.series);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onUp?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onDown?.call();
      return KeyEventResult.handled;
    }
    final many = widget.news.length > 1;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!watch) {
        widget.watchNode.requestFocus();
      } else if (many && _at > 0) {
        _go(-1);
      } else {
        widget.onLeftEdge?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (watch) {
        _openNode.requestFocus();
      } else if (many && _at < widget.news.length - 1) {
        // On to the next one, back on its first button.
        _go(1);
        widget.watchNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String? _backdrop(KostvSeriesNews news) {
    if (GetIt.instance.isRegistered<BackgroundService>()) {
      final url = GetIt.instance<BackgroundService>()
          .backdropUrlsFor(news.series)
          .firstOrNull;
      if (url != null) return url;
    }
    if (!GetIt.instance.isRegistered<MediaServerClient>()) return null;
    return GetIt.instance<MediaServerClient>().imageApi.getPrimaryImageUrl(
      news.episode.id,
      maxWidth: 1280,
    );
  }

  String? _logo(KostvSeriesNews news) {
    final tag = news.series.logoImageTag;
    if (tag == null || !GetIt.instance.isRegistered<MediaServerClient>()) {
      return null;
    }
    return GetIt.instance<MediaServerClient>().imageApi.getLogoImageUrl(
      news.series.id,
      maxWidth: 600,
      tag: tag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final phone = PlatformDetection.useMobileUi;
    final news = widget.news[_at];
    final backdrop = _backdrop(news);
    final logo = _logo(news);
    final fresh = widget.fresh.contains(news.series.id);
    final headline = news.newSeason
        ? l10n.kostvFavoritesNewSeasonHeadline
        : l10n.kostvFavoritesNewEpisodesHeadline(news.count);
    final episode = news.episode;
    final number =
        episode.parentIndexNumber != null && episode.indexNumber != null
        ? 'T${episode.parentIndexNumber}:E${episode.indexNumber}'
        : null;
    final episodeLine = [
      number,
      episode.name,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    final content = Column(
      key: ValueKey(news.series.id),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fresh) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D),
                  borderRadius: AppRadius.circular(999),
                ),
                child: Text(
                  l10n.kostvFavoritesNewBadge.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            const Icon(
              Icons.favorite_rounded,
              size: 16,
              color: kostvFavoritesColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: phone ? 8 : 12),
        if (logo != null)
          SizedBox(
            height: phone ? 46 : 70,
            width: phone ? 200 : 320,
            child: BoundedNetworkImage(
              imageUrl: logo,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (context, url, error) =>
                  _title(context, news.series.name),
            ),
          )
        else
          _title(context, news.series.name),
        SizedBox(height: phone ? 6 : 10),
        Text(
          [
            kostvNewsLine(news, l10n),
            if (episodeLine.isNotEmpty) episodeLine,
          ].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ],
    );

    final buttons = Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _HeroButton(
          focusNode: widget.watchNode,
          primary: true,
          icon: Icons.play_arrow_rounded,
          label: l10n.kostvFavoritesWatchEpisode,
          onKey: (node, event) => _onKey(node, event, watch: true),
          onTap: () => widget.onWatch(widget.news[_at].episode),
          onFocus: (focused) => _held = focused,
        ),
        _HeroButton(
          focusNode: _openNode,
          icon: Icons.info_outline_rounded,
          label: l10n.kostvFavoritesOpenSeries,
          onKey: (node, event) => _onKey(node, event, watch: false),
          onTap: () => widget.onOpen(widget.news[_at].series),
          onFocus: (focused) => _held = focused,
        ),
      ],
    );

    final height = phone ? 236.0 : 300.0;
    return MouseRegion(
      onEnter: (_) => _held = true,
      onExit: (_) => _held = false,
      child: GestureDetector(
        // A swipe goes to the next or the one before.
        onHorizontalDragEnd: (details) {
          final speed = details.primaryVelocity ?? 0;
          if (speed.abs() < 200) return;
          _go(speed < 0 ? 1 : -1);
          _restartTimer();
        },
        child: ClipRRect(
          borderRadius: AppRadius.circular(phone ? 18 : 24),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF1B1F27)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  // Each picture fills the whole piece, also while they cross.
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  child: backdrop == null
                      ? const SizedBox.expand()
                      : BoundedNetworkImage(
                          key: ValueKey(backdrop),
                          imageUrl: backdrop,
                          fit: BoxFit.cover,
                          alignment: Alignment.topRight,
                          maxWidth: 1600,
                          errorBuilder: (context, url, error) =>
                              const SizedBox.expand(),
                        ),
                ),
                // Dark from the left, where the words are, and from below.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xF00B0D12),
                        Color(0xB30B0D12),
                        Color(0x000B0D12),
                      ],
                      stops: [0, 0.45, 0.85],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC0B0D12), Color(0x000B0D12)],
                      stops: [0, 0.6],
                    ),
                  ),
                ),
                // A thin line of the heart's colour round the edge.
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.circular(phone ? 18 : 24),
                    border: Border.all(
                      color: kostvFavoritesColor.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    phone ? 18 : 32,
                    phone ? 16 : 26,
                    phone ? 18 : 32,
                    phone ? 16 : 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 350),
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.centerLeft,
                                children: [...previous, ?current],
                              ),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween(
                                        begin: const Offset(0.04, 0),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: content,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: phone ? 10 : 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: buttons),
                          if (widget.news.length > 1)
                            _Dots(
                              count: widget.news.length,
                              at: _at,
                              onTap: (i) {
                                setState(() => _at = i);
                                _restartTimer();
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String name) => Text(
    name,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style:
        (PlatformDetection.useMobileUi
                ? Theme.of(context).textTheme.headlineSmall
                : Theme.of(context).textTheme.headlineMedium)
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
  );
}

/// Kos TV: a button of the news highlight.
class _HeroButton extends StatefulWidget {
  const _HeroButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onKey,
    required this.onTap,
    required this.onFocus,
    this.primary = false,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final FocusOnKeyEventCallback onKey;
  final VoidCallback onTap;
  final ValueChanged<bool> onFocus;
  final bool primary;

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final lit =
        InputModeTracker.showFocusVisuals(context, _focused) || _hovered;
    final phone = PlatformDetection.useMobileUi;
    final Color background;
    final Color ink;
    if (lit) {
      background = Colors.white;
      ink = Colors.black;
    } else if (widget.primary) {
      background = kostvFavoritesColor;
      ink = Colors.white;
    } else {
      background = Colors.white.withValues(alpha: 0.16);
      ink = Colors.white;
    }
    return Semantics(
      button: true,
      label: widget.label,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          widget.onFocus(focused);
          setState(() => _focused = focused);
        },
        onKeyEvent: widget.onKey,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: lit ? 1.05 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: phone ? 14 : 20,
                  vertical: phone ? 9 : 11,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: AppRadius.circular(999),
                  boxShadow: lit
                      ? const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: phone ? 20 : 22, color: ink),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kos TV: which of the news is shown, and a way to another one by touch.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.at, required this.onTap});

  final int count;
  final int at;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(i),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: i == at ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == at
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.35),
                borderRadius: AppRadius.circular(999),
              ),
            ),
          ),
        ),
    ],
  );
}
