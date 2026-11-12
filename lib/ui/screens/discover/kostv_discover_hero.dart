import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/bounded_network_image.dart';
import 'kostv_discover_parts.dart';
import 'kostv_discover_spotlight.dart';

/// Kos TV: the top of Discover on a phone: the first of each row on a
/// carousel, each poster large over its own colours, with its place, its
/// row, its name and how it stands at home. A swipe moves along; a tap
/// opens it.
class KostvDiscoverHero extends StatefulWidget {
  const KostvDiscoverHero({
    super.key,
    required this.items,
    required this.onOpen,
    required this.width,
  });

  /// Each title with where it comes from.
  final List<({StremfinTitle title, KostvSpotlightSource source})> items;
  final ValueChanged<StremfinTitle> onOpen;
  final double width;

  @override
  State<KostvDiscoverHero> createState() => _KostvDiscoverHeroState();
}

class _KostvDiscoverHeroState extends State<KostvDiscoverHero> {
  late final PageController _pages;
  int _page = 0;

  /// The poster's share of the width; the next ones peek at the sides.
  static const _fraction = 0.56;

  @override
  void initState() {
    super.initState();
    _pages = PageController(viewportFraction: _fraction);
  }

  @override
  void didUpdateWidget(KostvDiscoverHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= widget.items.length && widget.items.isNotEmpty) {
      _page = widget.items.length - 1;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final entry = items[_page.clamp(0, items.length - 1)];
    final current = entry.title;
    final posterWidth = (widget.width * _fraction - 16).clamp(150.0, 300.0);
    final posterHeight = posterWidth * 3 / 2;
    final background = AppColorScheme.background;

    return Stack(
      children: [
        // Its colours behind, fading into the page.
        Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              KostvSpotlightArt(title: current, backdrop: null),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      background.withValues(alpha: 0),
                      background.withValues(alpha: 0.35),
                      background,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [background, background.withValues(alpha: 0)],
                    stops: const [0, 0.12],
                  ),
                ),
              ),
            ],
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 14),
            SizedBox(
              height: posterHeight + 20,
              child: PageView.builder(
                controller: _pages,
                itemCount: items.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => AnimatedBuilder(
                  animation: _pages,
                  builder: (context, child) {
                    final page =
                        _pages.hasClients && _pages.position.haveDimensions
                        ? (_pages.page ?? _page.toDouble())
                        : _page.toDouble();
                    final away = (page - index).abs().clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: 1 - away * 0.14,
                      child: Opacity(opacity: 1 - away * 0.45, child: child),
                    );
                  },
                  child: Center(
                    child: _Poster(
                      title: items[index].title,
                      width: posterWidth,
                      height: posterHeight,
                      onTap: () => index == _page
                          ? widget.onOpen(items[index].title)
                          : _pages.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Padding(
                key: ValueKey('${current.type.name}${current.tmdbId}'),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GestureDetector(
                  onTap: () => widget.onOpen(current),
                  child: Column(
                    children: [
                      _kicker(entry.source, l10n),
                      const SizedBox(height: 8),
                      KostvSpotlightName(
                        title: current,
                        logo: null,
                        unit: 0.72,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        kostvSpotlightMeta(context, current, null),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColorScheme.onBackground.withValues(
                            alpha: 0.75,
                          ),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final status in KostvTitleStatus.of(
                            current,
                            l10n,
                          ))
                            KostvStatusChip(status: status, unit: 0.95),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _dots(items.length),
            const SizedBox(height: 4),
          ],
        ),
      ],
    );
  }

  /// Its platform, its place or season, and its row, centred.
  Widget _kicker(KostvSpotlightSource source, AppLocalizations l10n) {
    final rank = source.rank;
    final platform = source.platform;
    final tag = rank != null ? l10n.kostvDiscoverRank(rank) : source.season;
    return Text.rich(
      TextSpan(
        children: [
          if (platform != null)
            TextSpan(
              text: '${platform.name}  ·  ',
              style: TextStyle(
                color: Color.lerp(
                  platform.color ?? Colors.white,
                  Colors.white,
                  0.3,
                ),
                fontWeight: FontWeight.w800,
              ),
            ),
          if (tag != null)
            TextSpan(
              text: '$tag  ·  ',
              style: const TextStyle(
                color: Color(0xFFB9A6FF),
                fontWeight: FontWeight.w800,
              ),
            ),
          TextSpan(text: source.rowTitle.toUpperCase()),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: AppColorScheme.onBackground.withValues(alpha: 0.7),
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _dots(int count) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == _page ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == _page
                ? AppColorScheme.onBackground
                : AppColorScheme.onBackground.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );
}

/// A large poster on the carousel: grey while it isn't at home, with its
/// tick when it is.
class _Poster extends StatelessWidget {
  const _Poster({
    required this.title,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final StremfinTitle title;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final poster = title.poster;
    Widget image = poster == null
        ? ColoredBox(color: Colors.white.withValues(alpha: 0.06))
        : BoundedNetworkImage(
            imageUrl: poster,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 200),
          );
    if (!title.isInLibrary) {
      image = ColorFiltered(colorFilter: kostvMissingFilter, child: image);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
              if (title.isInLibrary)
                const Positioned(
                  top: 10,
                  right: 10,
                  child: KostvHomeTick(scale: 1.1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
