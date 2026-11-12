import 'package:get_it/get_it.dart';

import '../youtube_stream_resolver.dart';
import 'stremfin_models.dart';
import 'stremfin_service.dart';

/// Kos TV: a title's trailers with the Spanish ones first.
///
/// The home server lists a title's trailers as it got them from TMDB, in no
/// order of language, so most of the time the first is in English. The
/// requests service has the same trailers sorted: dubbed into Spain's Spanish,
/// then other Spanish, then subtitled, then English. Its list goes first and
/// the home server's follows, for whatever it has that the other doesn't.
abstract final class KostvTrailers {
  /// The keys a trailer from the requests service carries beside `Url` and
  /// `Name`, which are the home server's own.
  static const languageKey = 'KostvLanguage';
  static const countryKey = 'KostvCountry';
  static const subtitledKey = 'KostvSubtitled';

  /// The trailers of a film or series of the home server, in the shape the
  /// server gives its own ([server]). Anything else, or a title without a
  /// TMDB id, keeps the server's list as it is.
  static Future<List<Map<String, dynamic>>> sorted({
    required String? itemType,
    required String? tmdbId,
    required List<Map<String, dynamic>> server,
    StremfinService? stremfin,
  }) async {
    final type = switch (itemType) {
      'Movie' => StremfinTitleType.movie,
      'Series' => StremfinTitleType.series,
      _ => null,
    };
    final id = int.tryParse(tmdbId ?? '');
    final service =
        stremfin ??
        (GetIt.instance.isRegistered<StremfinService>()
            ? GetIt.instance<StremfinService>()
            : null);
    if (type == null || id == null || service == null) return server;
    return merge(await service.trailers(type, id), server);
  }

  /// [best] first, then what [server] has that isn't among them.
  static List<Map<String, dynamic>> merge(
    List<StremfinTrailer> best,
    List<Map<String, dynamic>> server,
  ) {
    if (best.isEmpty) return server;
    String videoOf(String url) =>
        YouTubeStreamResolver.extractVideoId(url) ?? url;
    final seen = <String>{};
    return [
      for (final trailer in best)
        if (seen.add(videoOf(trailer.url)))
          {
            'Url': trailer.url,
            'Name': ?trailer.name,
            languageKey: ?trailer.language,
            countryKey: ?trailer.country,
            subtitledKey: trailer.subtitled,
          },
      for (final trailer in server)
        if (trailer['Url'] case final String url
            when url.isNotEmpty && seen.add(videoOf(url)))
          trailer,
    ];
  }
}
