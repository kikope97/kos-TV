import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;

import '../../preference/user_preferences.dart';
import 'kostv_music_plugin.dart';

/// Kos TV: «Qué música enseñar» (Ajustes > Reproducción > Música): all the
/// music (the default: what isn't at home too, heard through the requests
/// service) or only what is at home.
///
/// It is the person's, kept by the server plugin (`Catalog` of its
/// `Settings`), so it follows them to every device. A plugin from before it
/// doesn't keep it: the device does then
/// ([UserPreferences.kostvMusicCatalogAll], per person too).
///
/// Kos TV: read as the person signs in, and what the plugin says is kept
/// on the device too, so «Solo la de casa» applies from the start (before
/// the plugin answers, or without it answering), not only once a Music
/// page has asked.
class KostvMusicCatalog extends ChangeNotifier {
  KostvMusicCatalog({
    UserPreferences? Function()? prefs,
    KostvMusicPlugin Function()? plugin,
  }) : _prefs = prefs ?? _appPrefs,
       _plugin = plugin ?? (() => KostvMusicPlugin.instance);

  /// The app's own.
  static KostvMusicCatalog instance = KostvMusicCatalog();

  final UserPreferences? Function() _prefs;
  final KostvMusicPlugin Function() _plugin;

  /// What the plugin keeps for the person (`true` all), or null when it
  /// doesn't keep it or hasn't said yet.
  bool? _person;

  /// Whose [_person] is: an answer for someone else doesn't count.
  String? _personOf;

  /// Kos TV: whose plugin answered without it (one from before «Toda la
  /// música»).
  String? _olderFor;

  /// Kos TV: whether each server's plugin (by address) keeps it, as far as
  /// it has said: the same plugin for everyone on it, so a person who just
  /// signed in, whose own answer hasn't come yet, still sets it there.
  final Map<String, bool> _keptOn = {};

  /// Whether the person's plugin keeps it.
  bool get keptByServer => _person != null;

  /// Kos TV: whether the signed-in person's plugin is known to be one from
  /// before «Toda la música» (it answered without `Catalog`): it can't keep
  /// what is said of the songs that aren't at home either («No me gusta»).
  bool get olderPlugin => _olderFor != null && _olderFor == _who(_client);

  static UserPreferences? _appPrefs() =>
      GetIt.instance.isRegistered<UserPreferences>()
      ? GetIt.instance<UserPreferences>()
      : null;

  static String? _who(MediaServerClient? client) => client == null
      ? null
      : '${client.baseUrl}|${client.userId}|${client.accessToken}';

  MediaServerClient? get _client =>
      GetIt.instance.isRegistered<MediaServerClient>()
      ? GetIt.instance<MediaServerClient>()
      : null;

  /// Whether to show all the music: the person's choice in the plugin, or
  /// the device's, or (with neither) yes.
  bool get all {
    final person = _person;
    if (person != null && _personOf == _who(_client)) return person;
    return _prefs()?.get(UserPreferences.kostvMusicCatalogAll) ?? true;
  }

  /// Reads the person's choice from [client]'s plugin, when it keeps it.
  /// Whatever fails, what was known stays.
  Future<void> refresh([MediaServerClient? client]) async {
    final server = client ?? _client;
    if (server == null) return;
    final who = _who(server);
    final answer = await _plugin().settings(server);
    if (_who(server) != who) return;
    final state = answer.value;
    if (answer.failed) return;
    final before = all;
    _olderFor = state != null && state.catalog == null ? who : null;
    if (answer.missing || state != null) {
      _keptOn[server.baseUrl] = state?.catalog != null;
    }
    if (state?.catalog == null) {
      _person = null;
      _personOf = null;
    } else {
      _person = state!.catalog == 'all';
      _personOf = who;
      await _copy(server, _person!);
    }
    if (all != before || answer.missing || state != null) notifyListeners();
  }

  /// Keeps what the plugin says on the device, for [server]'s person only
  /// (the device's is the one signed in's): what is used until it answers
  /// next time.
  Future<void> _copy(MediaServerClient? server, bool showAll) async {
    if (server == null || _who(server) != _who(_client)) return;
    final prefs = _prefs();
    if (prefs == null ||
        prefs.get(UserPreferences.kostvMusicCatalogAll) == showAll) {
      return;
    }
    await prefs.set(UserPreferences.kostvMusicCatalogAll, showAll);
  }

  /// [learned] is the plugin's answer to Settings (from somewhere else that
  /// read it): what it says of the catalog is taken.
  void take(KostvMusicLearnState? learned, [MediaServerClient? client]) {
    if (learned == null) return;
    final server = client ?? _client;
    final before = all;
    _olderFor = learned.catalog == null ? _who(server) : null;
    if (server != null) _keptOn[server.baseUrl] = learned.catalog != null;
    if (learned.catalog == null) {
      _person = null;
      _personOf = null;
    } else {
      _person = learned.catalog == 'all';
      _personOf = _who(server);
      unawaited(_copy(server, _person!));
    }
    if (all != before) notifyListeners();
  }

  /// Sets it: in the person's plugin when it keeps it, otherwise on the
  /// device. False when the plugin couldn't keep it (what was there stays).
  Future<bool> set(bool showAll, [MediaServerClient? client]) async {
    final server = client ?? _client;
    if (_person != null && server != null && _personOf == _who(server)) {
      final before = _person;
      _person = showAll;
      notifyListeners();
      final after = await _plugin().setCatalog(
        server,
        showAll ? 'all' : 'home',
      );
      if (after?.catalog == null) {
        _person = before;
        notifyListeners();
        return false;
      }
      _person = after!.catalog == 'all';
      await _copy(server, _person!);
      notifyListeners();
      return true;
    }
    // Kos TV: the person's own answer hasn't come yet (just signed in), but
    // their server's plugin is known to keep it: set there, not only on
    // the device (the plugin's would undo it at its next read).
    if (server != null && _keptOn[server.baseUrl] == true) {
      final who = _who(server);
      final before = (person: _person, of: _personOf);
      _person = showAll;
      _personOf = who;
      notifyListeners();
      final after = await _plugin().setCatalog(
        server,
        showAll ? 'all' : 'home',
      );
      // Someone else signed in meanwhile: theirs isn't touched.
      if (_who(server) != who) return after?.catalog != null;
      if (after?.catalog == null) {
        if (_personOf == who) {
          _person = before.person;
          _personOf = before.of;
        }
        notifyListeners();
        return false;
      }
      _person = after!.catalog == 'all';
      _personOf = who;
      await _copy(server, _person!);
      notifyListeners();
      return true;
    }
    await _prefs()?.set(UserPreferences.kostvMusicCatalogAll, showAll);
    notifyListeners();
    return true;
  }

  @visibleForTesting
  void debugReset() {
    _person = null;
    _personOf = null;
    _olderFor = null;
    _keptOn.clear();
  }
}

/// Kos TV: reads «Qué música enseñar» for [client]'s person as they sign in
/// (without waiting, whatever fails).
void kostvReadMusicCatalog(MediaServerClient client) => unawaited(
  KostvMusicCatalog.instance.refresh(client).catchError((Object _) {}),
);

/// Kos TV: whether the Music pages show all the music (what isn't at home
/// too, to listen to through the requests service) or only what is at home
/// («Qué música enseñar»).
bool kostvMusicCatalogAll() => KostvMusicCatalog.instance.all;
