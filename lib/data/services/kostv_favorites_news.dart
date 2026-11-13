import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../preference/user_preferences.dart';
import '../models/aggregated_item.dart';
import 'moonbase_endpoint.dart';

/// Kos TV: what arrived lately of one favourite series.
@immutable
class KostvSeriesNews {
  const KostvSeriesNews({
    required this.series,
    required this.episode,
    required this.count,
    required this.newSeason,
    required this.season,
    required this.unseen,
  });

  final AggregatedItem series;

  /// The first of the new episodes.
  final AggregatedItem episode;

  /// How many episodes arrived.
  final int count;

  /// Whether they open a season the person didn't have before.
  final bool newSeason;
  final int season;

  /// Whether it came after the person last looked.
  final bool unseen;

  KostvSeriesNews seen() => KostvSeriesNews(
    series: series,
    episode: episode,
    count: count,
    newSeason: newSeason,
    season: season,
    unseen: false,
  );
}

/// Kos TV: the news of the person's favourite series (new episodes and
/// seasons from the last month), kept by the server plugin, with how many
/// they haven't seen yet, for the heart's alert. Read on start, when the app
/// comes back and every half hour; seen when they open their favourites.
class KostvFavoritesNewsService extends ChangeNotifier {
  KostvFavoritesNewsService({
    MediaServerClient Function()? client,
    UserPreferences? prefs,
    Dio? dio,
  }) : _clientOf = client ?? (() => GetIt.instance<MediaServerClient>()),
       _prefs = prefs ?? GetIt.instance<UserPreferences>(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 30),
             ),
           );

  static const _every = Duration(minutes: 30);

  /// Asked again sooner than this only when told to.
  static const _fresh = Duration(minutes: 5);

  final MediaServerClient Function() _clientOf;
  final UserPreferences _prefs;
  final Dio _dio;

  /// Whose news [news] is, so another person's never shows.
  String? _owner;
  List<KostvSeriesNews> _news = const [];
  DateTime? _readAt;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _reading = false;

  /// Whether the server plugin keeps the news.
  bool get available => _prefs.get(UserPreferences.kostvFavoritesAvailable);

  /// The news, the latest first.
  List<KostvSeriesNews> get news {
    _checkOwner();
    return _news;
  }

  /// How many favourite series have news the person hasn't seen.
  int get unseen => available ? news.where((n) => n.unseen).length : 0;

  String _ownerNow() {
    try {
      final client = _clientOf();
      return '${client.baseUrl}|${client.userId}';
    } catch (_) {
      return '';
    }
  }

  void _checkOwner() {
    final now = _ownerNow();
    if (now == _owner) return;
    _owner = now;
    _news = const [];
    _readAt = null;
  }

  /// Starts reading now and every half hour.
  void start() {
    _timer ??= Timer.periodic(_every, (_) => unawaited(refresh(force: true)));
    // Back to the app: read again, as something may have arrived meanwhile.
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(refresh()));
    unawaited(refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    _dio.close();
    super.dispose();
  }

  /// Reads the news again, unless it was read a moment ago.
  Future<void> refresh({bool force = false}) async {
    _checkOwner();
    if (!available || _reading) return;
    final readAt = _readAt;
    if (!force &&
        readAt != null &&
        DateTime.now().difference(readAt) < _fresh) {
      return;
    }
    final owner = _owner;
    _reading = true;
    try {
      final client = _clientOf();
      final ep = await moonbaseEndpoint(client, _dio);
      if (ep == null) return;
      final response = await _dio.get<dynamic>(
        '${ep.base}/Moonfin/Kostv/Favorites/News',
        options: Options(headers: ep.headers),
      );
      final data = response.data;
      if (data is! Map || owner != _owner) return;
      AggregatedItem? card(Object? raw) => raw is Map && raw['Id'] != null
          ? AggregatedItem(
              id: raw['Id'].toString().replaceAll('-', ''),
              serverId: client.baseUrl,
              rawData: raw.cast<String, dynamic>(),
            )
          : null;
      _news = [
        if (data['Series'] case final List<dynamic> list)
          for (final entry in list.whereType<Map>())
            if ((card(entry['Series']), card(entry['Episode'])) case (
              final series?,
              final episode?,
            ))
              KostvSeriesNews(
                series: series,
                episode: episode,
                count: (entry['Count'] as num?)?.toInt() ?? 1,
                newSeason: entry['NewSeason'] == true,
                season: (entry['Season'] as num?)?.toInt() ?? 0,
                unseen: entry['Unseen'] == true,
              ),
      ];
      _readAt = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('[FavoritesNews] Reading the news failed: $e');
    } finally {
      _reading = false;
    }
  }

  /// The person saw the news: the alert goes, here and on their other
  /// devices.
  Future<void> markSeen() async {
    _checkOwner();
    if (!available || !_news.any((n) => n.unseen)) return;
    _news = [for (final n in _news) n.seen()];
    notifyListeners();
    try {
      final ep = await moonbaseEndpoint(_clientOf(), _dio);
      if (ep == null) return;
      await _dio.post<dynamic>(
        '${ep.base}/Moonfin/Kostv/Favorites/News/Seen',
        options: Options(headers: ep.headers),
      );
    } catch (e) {
      debugPrint('[FavoritesNews] Telling the news was seen failed: $e');
    }
  }
}
