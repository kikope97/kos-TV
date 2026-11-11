/// Kos TV: the household services the app talks to, built in or given at
/// start.
///
/// The apps (Android TV and phones) get them at build time from
/// `--dart-define=KOSTV_SERVER_URL=...` and `KOSTV_REQUESTS_URL`, which
/// build-android.sh passes from GitHub secrets, so no address is written into
/// the repository. The web version gets them when it starts, from the
/// `config.json` its Docker container writes from the container's variables
/// of the same names (see `docker/web`). Builds with neither ask for a server
/// address as Moonfin does.
library;

import '../platform/web_runtime_config.dart';

const String _builtServerUrl = String.fromEnvironment('KOSTV_SERVER_URL');
const String _builtRequestsUrl = String.fromEnvironment('KOSTV_REQUESTS_URL');

/// The household Jellyfin server.
String get kostvServerUrl =>
    _pick(_builtServerUrl, webRuntimeConfig.kostvServerUrl);

/// Whether this build has the household server built in or given.
bool get hasKostvServer => kostvServerUrl.trim().isNotEmpty;

/// The household requests service, where the family asks for movies and
/// shows. On the web it is usually a path on the same site (`/stremfin`),
/// which the container passes on to the service.
String get kostvRequestsUrl =>
    _pick(_builtRequestsUrl, webRuntimeConfig.kostvRequestsUrl);

/// Whether this build knows the requests service.
bool get hasKostvRequests => kostvRequestsUrl.trim().isNotEmpty;

/// The address built in wins; the web container's is used otherwise.
String _pick(String built, String? given) =>
    built.trim().isNotEmpty ? built : (given ?? '').trim();
