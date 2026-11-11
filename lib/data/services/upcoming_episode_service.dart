import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../preference/user_preferences.dart';
import '../models/aggregated_item.dart';
import '../models/calendar_entry.dart';
import '../models/upcoming_episode_info.dart';
import 'moonbase_endpoint.dart';

/// The calendar reminder for [info], the next episode of [series]. Null when
/// the series has no TVDB id, since the server matches episode reminders by it.
CalendarEntry? upcomingEpisodeReminder(
  AggregatedItem series,
  UpcomingEpisodeInfo info,
) {
  final ids = series.providerIds;
  final tvdbId = int.tryParse(ids['Tvdb'] ?? ids['tvdb'] ?? ids['TVDB'] ?? '');
  if (tvdbId == null || tvdbId <= 0) return null;
  return CalendarEntry(
    key: 'episode:$tvdbId:${info.seasonNumber}:${info.episodeNumber}',
    kind: CalendarEntryKind.episode,
    release: CalendarRelease.airing,
    date: info.airDate.toLocal(),
    hasTime: false,
    title: series.name,
    episodeTitle: info.title == 'TBA' ? null : info.title,
    seasonNumber: info.seasonNumber,
    episodeNumber: info.episodeNumber,
    tvdbId: tvdbId,
    tmdbId: int.tryParse(series.tmdbId ?? ''),
    imdbId: series.imdbId,
  );
}

/// Service that resolves upcoming episode air dates for a TV series from
/// TMDB (through the server plugin).
class UpcomingEpisodeService {
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  final Map<String, ({UpcomingEpisodeInfo? info, DateTime at})> _seriesCache =
      {};

  // Two screens can ask at once, and they should share one answer rather than
  // both going to the network.
  final Map<String, Future<UpcomingEpisodeInfo?>> _inFlight = {};

  static const _cacheDuration = Duration(minutes: 30);

  UpcomingEpisodeInfo? getCached(String seriesId) {
    final entry = _seriesCache[seriesId];
    return _stillHolds(entry) ? entry!.info : null;
  }

  /// An answer holds until it ages out, and an episode that has since aired
  /// stops counting as one so the badge gives up on it.
  bool _stillHolds(({UpcomingEpisodeInfo? info, DateTime at})? entry) {
    if (entry == null) return false;
    if (DateTime.now().difference(entry.at) >= _cacheDuration) return false;
    return !(entry.info?.hasAired ?? false);
  }

  /// Resolves the upcoming episode for the given series.
  Future<UpcomingEpisodeInfo?> resolveUpcomingEpisode({
    required String seriesId,
    required Map<String, String?> providerIds,
  }) {
    final entry = _seriesCache[seriesId];
    if (_stillHolds(entry)) return Future.value(entry!.info);

    final running = _inFlight[seriesId];
    if (running != null) return running;

    final future = _resolve(seriesId, providerIds);
    _inFlight[seriesId] = future;
    return future.whenComplete(() => _inFlight.remove(seriesId));
  }

  Future<UpcomingEpisodeInfo?> _resolve(
    String seriesId,
    Map<String, String?> providerIds,
  ) async {
    final now = DateTime.now();

    // TMDB's next episode
    final tmdbIdStr = providerIds['Tmdb'] ?? providerIds['tmdb'];
    if (tmdbIdStr != null && tmdbIdStr.isNotEmpty) {
      try {
        final info = await _fetchTmdbNextEpisode(tmdbIdStr);
        if (info != null) {
          _seriesCache[seriesId] = (info: info, at: now);
          return info;
        }
      } catch (e) {
        debugPrint('[UpcomingEpisodeService] TMDB fallback failed: $e');
      }
    }

    // Cache negative result to avoid hammering APIs repeatedly
    _seriesCache[seriesId] = (info: null, at: now);
    return null;
  }

  Future<UpcomingEpisodeInfo?> _fetchTmdbNextEpisode(String tmdbId) async {
    final prefs = GetIt.instance<UserPreferences>();
    final apiKey = prefs.get(UserPreferences.tmdbApiKey);

    // If client has TMDB API key configured directly:
    if (apiKey.isNotEmpty) {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/tv/$tmdbId',
        queryParameters: {
          'api_key': apiKey,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        final nextEp = response.data['next_episode_to_air'];
        if (nextEp is Map) {
          final airDateStr = nextEp['air_date'] as String?;
          final airDate =
              airDateStr != null ? DateTime.tryParse(airDateStr) : null;
          if (airDate != null) {
            return UpcomingEpisodeInfo(
              seasonNumber: (nextEp['season_number'] as num?)?.toInt() ?? 1,
              episodeNumber: (nextEp['episode_number'] as num?)?.toInt() ?? 1,
              airDate: airDate,
              title: nextEp['name'] as String?,
            );
          }
        }
      }
      return null;
    }

    // Otherwise, try Moonbase server proxy if available:
    if (GetIt.instance.isRegistered<MediaServerClient>()) {
      final client = GetIt.instance<MediaServerClient>();
      final ep = await moonbaseEndpoint(client, _dio);
      if (ep != null) {
        try {
          final response = await _dio.get(
            '${ep.base}/Moonfin/Tmdb/NextEpisode',
            queryParameters: {'tmdbId': tmdbId},
            options: Options(headers: ep.headers),
          );
          if (response.statusCode == 200 && response.data is Map) {
            final data = response.data;
            if (data['success'] == true && data['airDate'] != null) {
              final airDate = DateTime.tryParse(data['airDate'] as String);
              if (airDate != null) {
                return UpcomingEpisodeInfo(
                  seasonNumber: (data['seasonNumber'] as num?)?.toInt() ?? 1,
                  episodeNumber: (data['episodeNumber'] as num?)?.toInt() ?? 1,
                  airDate: airDate,
                  title: data['name'] as String?,
                );
              }
            }
          }
        } catch (_) {
          // Moonbase endpoint may not be implemented yet
        }
      }
    }

    return null;
  }

  void clearCache() {
    _seriesCache.clear();
  }

  void dispose() {
    clearCache();
    _inFlight.clear();
    _dio.close(force: true);
  }
}
