import 'package:dio/dio.dart';
import 'package:moonfin/data/services/stremfin/stremfin_client.dart';
import 'package:moonfin/data/services/stremfin/stremfin_service.dart';

import '../../../data/services/stremfin/fake_stremfin_adapter.dart';

typedef Reply = ({int status, Object? body, Map<String, String> headers});

/// A requests service with one film (920) and one series (1396) whose
/// requests go through their whole life as the test moves them along:
/// asked for, accepted, downloading, there.
class FakeStremfinLife {
  FakeStremfinLife({this.mode = 'direct'});

  /// `direct` (starts at once) or `review` (waits for the administrator).
  String mode;
  bool atLimit = false;

  /// The film on the home server: `missing`, `arriving` (there, no item
  /// yet) or `available`.
  String movieLibrary = 'missing';
  Map<String, Object?> availability = {
    'status': 'ready',
    'cached': true,
    'fast': true,
    'version': {'summary': '1080p · Castellano · 9,0 GB'},
    'criterion': 'en castellano de 1080p o más',
    'on_request': 'download',
  };

  /// Downloading for someone else, with no request of the person's.
  Map<String, Object?>? movieDownload;

  /// Season numbers of the series on the home server, all of them.
  final Set<int> seriesHave = {1};
  final Map<int, Map<String, Object?>> requests = {};
  int _nextId = 50;
  final List<String> calls = [];

  /// The next call answers with this error status instead.
  int? failNext;

  StremfinService service() => StremfinService(
    StremfinClient(
      dio: Dio()..httpClientAdapter = FakeStremfinAdapter.withMethod(answer),
      baseUrl: 'https://requests.example.org/api/v1',
      token: () => 'token',
    ),
    watchLifecycle: false,
  );

  Map<String, Object?>? get movieRequest => requests.values
      .where((r) => r['type'] == 'movie' && _open(r))
      .firstOrNull;

  bool _open(Map<String, Object?> r) =>
      r['status'] == 'pending' || r['status'] == 'approved';

  Map<String, Object?> _ref(Map<String, Object?> r) => {
    'id': r['id'],
    'status': r['status'],
    'season': r['season'],
    'mine': r['mine'],
    'requesters': r['requesters'],
  };

  // -------------------------------------------------- moving things along

  void approve(int id) {
    requests[id]!
      ..['status'] = 'approved'
      ..['can_withdraw'] = false
      ..['progress'] = {'state': 'accepted', 'label': 'Aceptada'};
  }

  void download(int id, int percent, {String phase = 'downloading'}) {
    requests[id]!
      ..['status'] = 'approved'
      ..['progress'] = {
        'state': 'downloading',
        'phase': phase,
        'percent': percent,
        'speed': 12 * 1024 * 1024,
        'eta_seconds': 240,
        'paused': false,
      };
  }

  void complete(int id, {bool indexed = true}) {
    final r = requests[id]!
      ..['status'] = 'completed'
      ..['progress'] = null;
    if (r['type'] == 'movie') {
      movieLibrary = indexed ? 'available' : 'arriving';
    } else {
      final season = r['season'] as int?;
      seriesHave.addAll(season == null ? [1, 2, 3] : [season]);
    }
  }

  void reject(int id, String reason) {
    requests[id]!
      ..['status'] = 'rejected'
      ..['reason'] = reason
      ..['progress'] = null;
  }

  // ---------------------------------------------------------- answering

  Reply answer(String method, String path, Object? sent) {
    calls.add('$method $path');
    final fail = failNext;
    if (fail != null && path != '/me') {
      failNext = null;
      return (
        status: fail,
        body: {
          'error': {'code': 'source_unavailable', 'message': 'Ahora no.'},
        },
        headers: const {},
      );
    }
    if (path == '/me') return _ok(_me());
    if (path == '/movies/920') return _ok(_movie());
    if (path == '/movies/920/availability') return _ok(availability);
    if (path == '/series/1396') return _ok(_series());
    if (path == '/requests' && method == 'POST') return _post(sent);
    final id = int.tryParse(path.replaceFirst('/requests/', ''));
    if (id != null) {
      final r = requests[id];
      if (r == null) return _error(404, 'not_found');
      if (method == 'DELETE') {
        if (r['status'] != 'pending') return _error(409, 'already_answered');
        requests.remove(id);
        return _ok({'outcome': 'withdrawn', 'message': 'Petición retirada.'});
      }
      return _ok(r);
    }
    return _error(404, 'not_found');
  }

  Reply _ok(Object? body, [int status = 200]) =>
      (status: status, body: body, headers: const {});

  Reply _error(int status, String code) => (
    status: status,
    body: {
      'error': {'code': code, 'message': code},
    },
    headers: const {},
  );

  Map<String, Object?> _me() => {
    'user': {'name': 'Kiko', 'role': 'member'},
    'access': {
      'can_request': true,
      'mode': mode,
      'limit': 3,
      'pending': requests.values.where((r) => r['status'] == 'pending').length,
      'daily_left': atLimit ? 0 : 10,
      'at_limit': atLimit,
    },
  };

  Map<String, Object?> _movie() {
    final open = movieRequest;
    final inLibrary = movieLibrary != 'missing';
    return {
      'type': 'movie',
      'tmdb_id': 920,
      'title': 'Cars',
      'year': 2006,
      'overview': 'Un coche de carreras…',
      'poster': 'https://image.tmdb.org/t/p/w342/c.jpg',
      'backdrop': 'https://image.tmdb.org/t/p/w1280/c2.jpg',
      'runtime': 117,
      'genres': ['Animación', 'Comedia'],
      'library': {
        'status': inLibrary ? 'available' : 'missing',
        'in_jellyfin': inLibrary,
        'jellyfin_id': movieLibrary == 'available' ? 'cars-item' : null,
        'downloading': movieDownload != null,
      },
      'request': open == null ? null : _ref(open),
      'download': movieDownload,
      'release': null,
      'can_request': inLibrary
          ? {'allowed': false, 'action': null, 'reason': 'have'}
          : open != null && open['mine'] == true
          ? {'allowed': false, 'action': null, 'reason': 'already'}
          : {
              'allowed': true,
              'action': movieDownload != null ? 'notify' : 'request',
              'reason': null,
            },
    };
  }

  Map<String, Object?> _series() {
    Map<String, Object?>? covering(int? season) => requests.values
        .where(
          (r) =>
              r['type'] == 'series' &&
              _open(r) &&
              (r['season'] == null || r['season'] == season),
        )
        .firstOrNull;
    final whole = requests.values
        .where((r) => r['type'] == 'series' && _open(r) && r['season'] == null)
        .firstOrNull;
    final seasons = [
      for (final n in [1, 2, 3])
        () {
          final have = seriesHave.contains(n);
          final request = covering(n);
          return {
            'season': n,
            'aired': 10,
            'have': have ? 10 : 0,
            'missing': have ? 0 : 10,
            'downloading': 0,
            'status': have
                ? 'complete'
                : (request != null ? 'downloading' : 'missing'),
            'request': request == null ? null : _ref(request),
            'can_request': !have && request == null,
          };
        }(),
    ];
    final missing = seasons.where((s) => s['can_request'] == true).length;
    return {
      'type': 'series',
      'tmdb_id': 1396,
      'title': 'Marea alta',
      'year': 2024,
      'years': '2024–',
      'overview': 'Un pueblo junto al mar…',
      'genres': ['Drama'],
      'library': {
        'status': 'available',
        'in_jellyfin': true,
        'jellyfin_id': 'marea-item',
        'downloading': false,
      },
      'request': whole == null ? null : _ref(whole),
      'summary': {
        'aired': 30,
        'have': seriesHave.length * 10,
        'missing': 30 - seriesHave.length * 10,
        'missing_requestable': missing * 10,
      },
      'can_request_all': missing > 0 && whole == null,
      'seasons': seasons,
    };
  }

  Reply _post(Object? sent) {
    final body = (sent is Map ? sent : const {}).cast<String, Object?>();
    if (atLimit) {
      return (
        status: 429,
        body: {
          'outcome': 'limit',
          'limit': 'daily',
          'message': 'Hoy no.',
          'request': null,
        },
        headers: const {'retry-after': '3600'},
      );
    }
    final type = body['type'] as String;
    final season = body['season'] as int?;
    final id = _nextId++;
    final direct = mode != 'review';
    final request = <String, Object?>{
      'id': id,
      'type': type,
      'tmdb_id': body['tmdb_id'],
      'season': season,
      'whole_series': type == 'series' && season == null,
      'status': direct ? 'approved' : 'pending',
      'direct': direct,
      'mine': true,
      'requesters': ['Kiko'],
      'can_withdraw': !direct,
      'progress': direct ? {'state': 'accepted', 'label': 'Aceptada'} : null,
    };
    requests[id] = request;
    return _ok({
      'outcome': direct ? 'started' : 'created',
      'message': 'Hecho.',
      'request': request,
    }, 201);
  }
}
