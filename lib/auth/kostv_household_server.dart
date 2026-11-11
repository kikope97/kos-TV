import '../util/kostv_server.dart';
import '../util/server_url.dart';
import 'models/server.dart';
import 'repositories/server_repository.dart';

/// Kos TV: the household server among the stored ones, added again when it
/// isn't there (after signing everyone out, say). Null in a build without
/// one, or when it can't be reached to be added.
///
/// With the household server built in there is no other server to pick, so
/// everything that would open the server list opens this one's users instead
/// (see the server list route in `app_router.dart`).
Future<Server?> kostvHouseholdServer(ServerRepository repo) async {
  if (!hasKostvServer) return null;
  final wanted = normalizeServerBaseUrl(kostvServerUrl);
  bool isHousehold(Server s) =>
      normalizeServerBaseUrl(s.address) == wanted ||
      normalizeServerBaseUrl(s.displayAddress ?? '') == wanted;
  final known = repo.servers.where(isHousehold).firstOrNull;
  if (known != null) return known;
  await repo.loadStoredServers();
  return repo.servers.where(isHousehold).firstOrNull ??
      await repo.addServer(kostvServerUrl);
}
