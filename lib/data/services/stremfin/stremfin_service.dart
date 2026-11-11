import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import '../../../preference/user_preferences.dart';
import 'stremfin_client.dart';
import 'stremfin_models.dart';

/// Kos TV: whether the person may use Discover, as the requests service last
/// said.
enum StremfinAccess { unknown, allowed, denied }

/// Kos TV: the requests service (Stremfin) for the rest of the app: who may
/// use it (asked when someone signs in and when the app comes back to the
/// front) and the platform lists, kept for a while so moving between
/// platforms doesn't ask again.
class StremfinService extends ChangeNotifier {
  StremfinService(
    this._client, {
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting bool watchLifecycle = true,
  }) : _clock = clock ?? DateTime.now {
    if (watchLifecycle) {
      _lifecycle = AppLifecycleListener(
        onResume: () => unawaited(refreshAccess()),
      );
    }
  }

  final StremfinClient _client;
  final DateTime Function() _clock;
  AppLifecycleListener? _lifecycle;

  /// How long a list stays fresh. The service itself keeps them for minutes
  /// to an hour, so asking more often brings nothing new.
  static const listLifetime = Duration(minutes: 15);

  /// When to ask again after the service couldn't answer.
  static const _retryDelay = Duration(minutes: 2);

  StremfinAccess _access = StremfinAccess.unknown;
  Future<void>? _checking;
  Timer? _retry;
  String? _checkedFor;

  /// Bumped when the person changes, so a list asked for before doesn't land
  /// in the next person's memory.
  int _generation = 0;
  List<StremfinPlatform>? _platforms;
  final Map<String, ({DateTime at, List<StremfinTitle> items})> _lists = {};
  final Map<String, Future<List<StremfinTitle>>> _loading = {};

  bool get isConfigured => _client.isConfigured;
  StremfinAccess get access => _access;
  bool get isAllowed => _access == StremfinAccess.allowed;

  /// Asks the service who the signed-in person is. Not reaching it keeps
  /// what it said last and tries again a little later; a refusal hides
  /// Discover but never signs anyone out of the app.
  Future<void> refreshAccess() {
    if (!_client.isConfigured) return Future.value();
    return _checking ??= _checkAccess().whenComplete(() => _checking = null);
  }

  Future<void> _checkAccess() async {
    _retry?.cancel();
    if (_disposed) return;
    try {
      final me = await _client.me();
      _setAccess(
        me.canDiscover ? StremfinAccess.allowed : StremfinAccess.denied,
      );
    } on StremfinException catch (e) {
      if (e.isNoAccess) {
        _setAccess(StremfinAccess.denied);
      } else {
        // Switched off, home server not answering, no network: hidden until
        // it answers, if it never has.
        if (_access == StremfinAccess.unknown) {
          _setAccess(StremfinAccess.denied);
        }
        if (_disposed) return;
        _retry = Timer(
          e.retryAfter ?? _retryDelay,
          () => unawaited(refreshAccess()),
        );
      }
    }
  }

  void _setAccess(StremfinAccess access) {
    if (_disposed || _access == access) return;
    _access = access;
    notifyListeners();
  }

  /// Someone else signed in, or nobody is: forget what was known.
  void onUserChanged(String? userId) {
    if (userId == _checkedFor) return;
    _checkedFor = userId;
    _generation++;
    _retry?.cancel();
    _lists.clear();
    _loading.clear();
    _setAccess(StremfinAccess.unknown);
    if (userId != null) unawaited(refreshAccess());
  }

  /// The platform buttons, in the service's order. Falls back to the usual
  /// four.
  Future<List<StremfinPlatform>> platforms() async {
    final known = _platforms;
    if (known != null) return known;
    try {
      final read = await _client.platforms();
      if (read.isNotEmpty) return _platforms = read;
    } on StremfinException {
      // The usual four below.
    }
    return StremfinPlatform.defaults;
  }

  /// A list, from memory while it is fresh. With [refresh] it is asked again.
  Future<List<StremfinTitle>> top({
    required String platform,
    required StremfinTitleType type,
    required StremfinTopList list,
    bool refresh = false,
  }) {
    final key = '$platform/${type.apiValue}/${list.apiValue}';
    final kept = _lists[key];
    if (!refresh &&
        kept != null &&
        _clock().difference(kept.at) < listLifetime) {
      return Future.value(kept.items);
    }
    final pending = _loading[key];
    if (pending != null) return pending;
    final generation = _generation;
    final future = _client
        .top(platform: platform, type: type, list: list)
        .then((items) {
          if (generation == _generation) {
            _lists[key] = (at: _clock(), items: items);
          }
          return items;
        })
        .whenComplete(() {
          if (generation == _generation) _loading.remove(key);
        });
    return _loading[key] = future;
  }

  /// A list as it was last read, however old, to show while it's asked again.
  List<StremfinTitle>? keptList({
    required String platform,
    required StremfinTitleType type,
    required StremfinTopList list,
  }) => _lists['$platform/${type.apiValue}/${list.apiValue}']?.items;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}

/// Kos TV: whether the requests service lets the signed-in person use
/// Discover (before the Settings switch and kids mode are counted).
bool kostvDiscoverAllowed() {
  final getIt = GetIt.instance;
  return getIt.isRegistered<StremfinService>() &&
      getIt<StremfinService>().isAllowed;
}

/// Kos TV: whether the navigation shows the Discover button: a build that
/// knows the requests service, a person it lets in, outside kids mode, while
/// it is turned on in Settings.
bool showKostvDiscoverButton(UserPreferences prefs, {required bool kidsMode}) {
  final getIt = GetIt.instance;
  return !kidsMode &&
      getIt.isRegistered<StremfinService>() &&
      getIt<StremfinService>().isAllowed &&
      prefs.get(UserPreferences.showDiscoverButton);
}
