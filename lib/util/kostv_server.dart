/// Kos TV: the household Jellyfin server, built into the app.
///
/// It comes from `--dart-define=KOSTV_SERVER_URL=...`, which build-android.sh
/// passes from the `KOSTV_SERVER_URL` environment variable (a GitHub secret on
/// CI), so the address is never written into the repository. Empty in builds
/// made without it, which then ask for a server address as Moonfin does.
library;

const String kostvServerUrl = String.fromEnvironment('KOSTV_SERVER_URL');

/// Whether this build has the household server built in.
bool get hasKostvServer => kostvServerUrl.trim().isNotEmpty;

/// Kos TV: the household requests service, where the family asks for movies
/// and shows. Built in the same way from `--dart-define=KOSTV_REQUESTS_URL`
/// (the `KOSTV_REQUESTS_URL` GitHub secret), so its address stays out of the
/// repository too. Empty in builds made without it.
const String kostvRequestsUrl = String.fromEnvironment('KOSTV_REQUESTS_URL');

/// Whether this build has the requests service built in.
bool get hasKostvRequests => kostvRequestsUrl.trim().isNotEmpty;
