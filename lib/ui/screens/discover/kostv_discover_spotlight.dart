import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/services/stremfin/stremfin_models.dart';
import '../../../data/services/stremfin/stremfin_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/bounded_network_image.dart';
import '../../widgets/kos_logo.dart';
import '../../widgets/offline_aware_image.dart';
import 'kostv_discover_parts.dart';

/// Kos TV: what Discover's spotlight shows of a title beyond its list: its
/// wide art, its logo, what it is about, genres, length and rating.
@immutable
class KostvSpotlightExtra {
  const KostvSpotlightExtra({
    this.backdrop,
    this.logo,
    this.overview,
    this.genres = const [],
    this.runtime,
    this.rating,
  });

  final String? backdrop;
  final String? logo;
  final String? overview;
  final List<String> genres;

  /// Minutes, for a film.
  final int? runtime;
  final double? rating;
}

/// Kos TV: finds the spotlight's extra for a title, once per title while the
/// app is open. What is at home comes from the home server (art, logo,
/// overview); a film that isn't, from its page on the requests service,
/// which is a cheap call; a series that isn't keeps what its list says (its
/// page there is one of the costly calls).
class KostvSpotlightDetails {
  KostvSpotlightDetails(this._service);

  final StremfinService _service;

  static final Map<String, KostvSpotlightExtra> _kept = {};
  static const _keep = 150;

  static String _key(StremfinTitle title) =>
      '${title.type.apiValue}:${title.tmdbId}:${title.library.itemId ?? ''}';

  /// Forgets everything (another person, or a test).
  static void clear() => _kept.clear();

  KostvSpotlightExtra? kept(StremfinTitle title) => _kept[_key(title)];

  /// Whether there is anything to ask for this title.
  static bool worthAsking(StremfinTitle title) =>
      title.library.itemId != null || title.type == StremfinTitleType.movie;

  Future<KostvSpotlightExtra?> load(StremfinTitle title) async {
    final key = _key(title);
    final kept = _kept[key];
    if (kept != null) return kept;
    final getIt = GetIt.instance;
    final itemId = title.library.itemId;
    KostvSpotlightExtra? extra;
    try {
      if (itemId != null && getIt.isRegistered<MediaServerClient>()) {
        extra = await _fromHome(
          getIt<MediaServerClient>(),
          itemId,
          film: title.type == StremfinTitleType.movie,
        );
      } else if (title.type == StremfinTitleType.movie) {
        final detail = await _service.movie(title.tmdbId);
        extra = KostvSpotlightExtra(
          backdrop: detail.title.backdrop,
          overview: detail.title.overview,
          genres: detail.genres,
          runtime: detail.runtime,
          rating: detail.title.rating,
        );
      }
    } catch (_) {
      // Asked again next time it comes round.
      return null;
    }
    if (extra == null) return null;
    if (_kept.length >= _keep) _kept.remove(_kept.keys.first);
    return _kept[key] = extra;
  }

  static Future<KostvSpotlightExtra> _fromHome(
    MediaServerClient client,
    String id, {
    required bool film,
  }) async {
    final raw = await client.itemsApi.getItem(id, fields: 'Overview,Genres');
    final images = client.imageApi;
    String? backdrop;
    final tags = raw['BackdropImageTags'];
    if (tags is List && tags.isNotEmpty) {
      backdrop = images.getBackdropImageUrl(
        id,
        maxWidth: 1280,
        tag: tags.first?.toString(),
      );
    }
    String? logo;
    final logoTag = (raw['ImageTags'] as Map?)?['Logo'];
    if (logoTag is String && logoTag.isNotEmpty) {
      logo = images.getLogoImageUrl(id, maxWidth: 640, tag: logoTag);
    }
    final ticks = raw['RunTimeTicks'];
    final genres = raw['Genres'];
    final overview = raw['Overview'];
    final rating = raw['CommunityRating'];
    return KostvSpotlightExtra(
      backdrop: backdrop,
      logo: logo,
      overview: overview is String && overview.trim().isNotEmpty
          ? overview.trim()
          : null,
      genres: genres is List
          ? [
              for (final genre in genres)
                if (genre is String) genre,
            ]
          : const [],
      runtime: film && ticks is num && ticks > 0
          ? (ticks / 600000000).round()
          : null,
      rating: rating is num ? rating.toDouble() : null,
    );
  }
}

/// Where a title in the spotlight comes from: its row, and its place there.
@immutable
class KostvSpotlightSource {
  const KostvSpotlightSource({
    required this.rowTitle,
    this.rank,
    this.season,
    this.platform,
  });

  /// The row's name: «Series más vistas en Netflix».
  final String rowTitle;

  /// Its place on a most-watched list.
  final int? rank;

  /// On the new series: «T3 nueva» or «Serie nueva».
  final String? season;

  /// On everything new together: the platform it is on.
  final StremfinPlatform? platform;
}

/// Year, kind, length, genres and rating, joined.
String kostvSpotlightMeta(
  BuildContext context,
  StremfinTitle title,
  KostvSpotlightExtra? extra,
) {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
  final rating = extra?.rating ?? title.rating;
  final runtime = extra?.runtime;
  return [
    ?title.year?.toString(),
    title.type == StremfinTitleType.movie
        ? l10n.kostvDiscoverKindMovie
        : l10n.kostvDiscoverKindSeries,
    if (runtime != null && runtime > 0)
      runtime < 60
          ? l10n.minutesShort(runtime)
          : l10n.kostvHoursMinutes(runtime ~/ 60, runtime % 60),
    if (extra != null && extra.genres.isNotEmpty)
      extra.genres.take(2).join(', '),
    if (rating != null && rating > 0)
      '★ ${NumberFormat('0.0', locale).format(rating)}',
  ].join('  ·  ');
}

/// The labels above the title: its place or season, and its row.
class KostvSpotlightKicker extends StatelessWidget {
  const KostvSpotlightKicker({
    super.key,
    required this.source,
    required this.unit,
  });

  final KostvSpotlightSource source;
  final double unit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget tag(String text, {Color? color, Gradient? gradient}) => Container(
      margin: EdgeInsets.only(right: 8 * unit),
      padding: EdgeInsets.symmetric(horizontal: 8 * unit, vertical: 3 * unit),
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: BorderRadius.circular(6 * unit),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontFamily: KosBrand.fontFamily,
          fontSize: 12.5 * unit,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
    final rank = source.rank;
    final platform = source.platform;
    final season = source.season;
    // The row's name is just below, over the cards: only the tags here.
    return Row(
      children: [
        if (rank != null)
          tag(
            l10n.kostvDiscoverRank(rank),
            gradient: const LinearGradient(
              colors: [KosBrand.violet, Color(0xFF5B3FD6)],
            ),
          ),
        if (platform != null)
          tag(platform.name, color: platform.color ?? Colors.black54),
        if (season != null)
          tag(season, color: Colors.white.withValues(alpha: 0.16)),
      ],
    );
  }

  /// Whether there is any tag to show.
  static bool hasAny(KostvSpotlightSource source) =>
      source.rank != null || source.platform != null || source.season != null;
}

/// The title: its logo when the home server has one, its name otherwise.
class KostvSpotlightName extends StatelessWidget {
  const KostvSpotlightName({
    super.key,
    required this.title,
    required this.logo,
    required this.unit,
    this.maxLines = 2,
    this.textAlign = TextAlign.start,
  });

  final StremfinTitle title;
  final String? logo;
  final double unit;
  final int maxLines;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final name = Text(
      title.title,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: TextStyle(
        color: AppColorScheme.onBackground,
        fontFamily: KosBrand.fontFamily,
        fontSize: 34 * unit,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -0.4 * unit,
        shadows: const [Shadow(color: Colors.black54, blurRadius: 18)],
      ),
    );
    final url = logo;
    if (url == null) return name;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: 64 * unit, maxWidth: 340 * unit),
      // As the home server's logos are drawn elsewhere in the app.
      child: Image(
        image: offlineAwareImageProvider(url),
        fit: BoxFit.contain,
        alignment: textAlign == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft,
        semanticLabel: title.title,
        errorBuilder: (_, _, _) => name,
        frameBuilder: (context, child, frame, sync) =>
            frame == null && !sync ? name : child,
      ),
    );
  }
}

/// The spotlight's words, on a TV or a computer: where it comes from, the
/// title, the line of facts, how it stands at home and what it's about.
class KostvSpotlightText extends StatelessWidget {
  const KostvSpotlightText({
    super.key,
    required this.title,
    required this.source,
    required this.extra,
    required this.unit,
    this.overviewLines = 2,
  });

  final StremfinTitle title;
  final KostvSpotlightSource source;
  final KostvSpotlightExtra? extra;
  final double unit;
  final int overviewLines;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final overview = extra?.overview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (KostvSpotlightKicker.hasAny(source)) ...[
          KostvSpotlightKicker(source: source, unit: unit),
          SizedBox(height: 10 * unit),
        ],
        KostvSpotlightName(
          title: title,
          // A logo is the home server's: only for what is at home.
          logo: title.isInLibrary ? extra?.logo : null,
          unit: unit,
        ),
        SizedBox(height: 10 * unit),
        Text(
          kostvSpotlightMeta(context, title, extra),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColorScheme.onBackground.withValues(alpha: 0.82),
            fontSize: 14 * unit,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        SizedBox(height: 12 * unit),
        Wrap(
          spacing: 8 * unit,
          runSpacing: 6 * unit,
          children: [
            for (final status in KostvTitleStatus.of(title, l10n))
              KostvStatusChip(status: status, unit: unit),
          ],
        ),
        if (overviewLines > 0)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: overview == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: EdgeInsets.only(top: 12 * unit),
                    child: Text(
                      overview,
                      maxLines: overviewLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColorScheme.onBackground.withValues(
                          alpha: 0.78,
                        ),
                        fontSize: 14 * unit,
                        height: 1.4,
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// The spotlight's art: the title's wide image or, without one, its poster
/// as a wash of its colours. Grey while it isn't at home, as on its page.
class KostvSpotlightArt extends StatelessWidget {
  const KostvSpotlightArt({
    super.key,
    required this.title,
    required this.backdrop,
  });

  final StremfinTitle? title;
  final String? backdrop;

  @override
  Widget build(BuildContext context) {
    final current = title;
    final url = backdrop;
    final poster = current?.poster;
    final grey = current != null && !current.isInLibrary;
    Widget art;
    if (url != null) {
      art = BoundedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        maxWidth: 1600,
        sourceAspectRatio: 16 / 9,
        fadeInDuration: const Duration(milliseconds: 250),
        errorBuilder: (_, _, _) => _wash(poster),
      );
    } else {
      art = _wash(poster);
    }
    if (grey) art = ColorFiltered(colorFilter: kostvMissingFilter, child: art);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Only the newest outgoing art stays painted under the incoming:
      // moving fast would otherwise stack every full-screen image still
      // fading, each its own layer, on a weak TV GPU.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [if (previous.isNotEmpty) previous.last, ?current],
      ),
      child: KeyedSubtree(key: ValueKey('${url ?? poster}|$grey'), child: art),
    );
  }

  /// The poster, blurred into its colours, for a title with no wide image.
  static Widget _wash(String? poster) {
    if (poster == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        BoundedNetworkImage(
          imageUrl: poster,
          fit: BoxFit.cover,
          scale: 0.2,
          minWidth: 32,
          maxWidth: 160,
          blurSigma: 28,
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
      ],
    );
  }
}

/// Kos TV: follows the title the spotlight shows and finds its extra once
/// it has stayed there a moment, so moving along a row asks for nothing.
class KostvSpotlightFollower {
  KostvSpotlightFollower(this._details, this._onChanged);

  final KostvSpotlightDetails _details;
  final VoidCallback _onChanged;

  /// How long a title has to stay before its extra is asked for.
  static const settle = Duration(milliseconds: 450);

  StremfinTitle? _title;
  KostvSpotlightExtra? extra;
  Timer? _timer;
  int _generation = 0;

  void show(StremfinTitle? title) {
    final previous = _title;
    _title = title;
    // The same title again (its lists were read again, say): what was found
    // or is being found for it still holds.
    if (title != null &&
        previous != null &&
        title.type == previous.type &&
        title.tmdbId == previous.tmdbId &&
        title.library.itemId == previous.library.itemId) {
      return;
    }
    _timer?.cancel();
    final generation = ++_generation;
    extra = title == null ? null : _details.kept(title);
    if (title == null ||
        extra != null ||
        !KostvSpotlightDetails.worthAsking(title)) {
      return;
    }
    _timer = Timer(settle, () async {
      final found = await _details.load(title);
      if (generation != _generation || found == null) return;
      extra = found;
      _onChanged();
    });
  }

  void dispose() {
    _timer?.cancel();
    _generation++;
  }
}
