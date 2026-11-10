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
