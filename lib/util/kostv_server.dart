/// Kos TV: the household services the app talks to.
///
/// The home Jellyfin server is built in: the apps (Android TV and phones) get
/// it at build time from `--dart-define=KOSTV_SERVER_URL=...`, which
/// build-android.sh passes from a GitHub secret, so no address is written into
/// the repository; the web version gets it when it starts, from the
/// `config.json` its Docker container writes (see `docker/web`). Builds with
/// neither ask for a server address as Moonfin does.
///
/// The requests service (Stremfin) is not built in: the home server's plugin
/// gives its address to the signed-in apps ([KostvRequestsAddress]), so it
/// lives in one place, the plugin's settings page.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/web_runtime_config.dart';

const String _builtServerUrl = String.fromEnvironment('KOSTV_SERVER_URL');

/// The household Jellyfin server.
String get kostvServerUrl =>
    _pick(_builtServerUrl, webRuntimeConfig.kostvServerUrl);

/// Whether this build has the household server built in or given.
bool get hasKostvServer => kostvServerUrl.trim().isNotEmpty;

/// The household requests service, where the family asks for movies and
/// shows: the address the home server's plugin gives. A web container that
/// still passes the service on at a path of its own site (`/stremfin`, from
/// its `KOSTV_REQUESTS_URL`) keeps that way in, which needs nothing from the
/// service; without it the web talks to the service directly, as the apps do.
String get kostvRequestsUrl {
  final bridge = (webRuntimeConfig.kostvRequestsUrl ?? '').trim();
  if (bridge.isNotEmpty) return bridge;
  return KostvRequestsAddress.value ?? '';
}

/// Whether the requests service's address is known.
bool get hasKostvRequests => kostvRequestsUrl.trim().isNotEmpty;

/// The address built in wins; the web container's is used otherwise.
String _pick(String built, String? given) =>
    built.trim().isNotEmpty ? built : (given ?? '').trim();

/// Kos TV: where the requests service is, as the home server's plugin says.
///
/// The plugin sends it in its ping, which the app makes on opening and on
/// signing in, and again on coming back after [staleAfter] (a TV can keep the
/// app open for days). It is kept on the device, so Discover works at once on
/// the next start and while the server doesn't answer. Only the plugin's own
/// answer changes it: one without an address takes it away.
abstract final class KostvRequestsAddress {
  static const _key = 'kostv_requests_url';

  /// After this long without asking the plugin, coming back to the app asks
  /// again.
  static const staleAfter = Duration(hours: 6);

  /// The address, or null when the plugin gives none.
  static final ValueNotifier<String?> notifier = ValueNotifier(null);

  static DateTime? _askedAt;

  static String? get value => notifier.value;

  /// Whether the plugin hasn't been asked for a while.
  static bool isStale({DateTime? now}) {
    final asked = _askedAt;
    if (asked == null) return true;
    return (now ?? DateTime.now()).difference(asked) >= staleAfter;
  }

  /// Takes what the device kept from last time.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      notifier.value = _clean(prefs.getString(_key));
    } catch (_) {}
  }

  /// What the plugin just said: [url], or none.
  static Future<void> update(String? url, {DateTime? now}) async {
    _askedAt = now ?? DateTime.now();
    final next = _clean(url);
    if (next == notifier.value) return;
    notifier.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (next == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, next);
      }
    } catch (_) {}
  }

  static String? _clean(String? url) {
    final clean = (url ?? '').trim();
    return clean.isEmpty ? null : clean;
  }

  @visibleForTesting
  static void reset({String? value}) {
    _askedAt = null;
    notifier.value = value;
  }
}
