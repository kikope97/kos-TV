import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:get_it/get_it.dart';

import '../../preference/user_preferences.dart';
import '../../util/platform_detection.dart';

/// Kos TV: an app installed on the TV.
@immutable
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.label,
    this.art,
    this.isBanner = false,
  });

  final String packageName;
  final String label;

  /// The app's TV banner (16:9) or, when it has none, its icon, as PNG.
  final Uint8List? art;
  final bool isBanner;

  static InstalledApp? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final packageName = raw['package'];
    final label = raw['label'];
    if (packageName is! String || packageName.isEmpty) return null;
    final art = raw['art'];
    return InstalledApp(
      packageName: packageName,
      label: label is String && label.isNotEmpty ? label : packageName,
      art: art is Uint8List ? art : null,
      isBanner: raw['isBanner'] == true && art is Uint8List,
    );
  }
}

/// Kos TV: the apps installed on the TV, for the Apps row on Home and the All
/// apps screen, and which of them the Apps row shows. Android only; on other
/// platforms the list stays empty and [isSupported] is false.
class InstalledAppsService extends ChangeNotifier {
  InstalledAppsService(
    this._prefs, {
    @visibleForTesting MethodChannel? channel,
    @visibleForTesting bool? supported,
  }) : _channel = channel ?? const MethodChannel('org.moonfin.androidtv/platform'),
       isSupported =
           supported ?? (_demoApps || (!kIsWeb && PlatformDetection.isAndroid));

  /// For screenshots off a TV: with --dart-define=KOSTV_DEMO_APPS=true the
  /// list comes from kostv_demo_apps.json next to the web page (entries like
  /// the TV's, with the art in base64) and opening an app does nothing.
  /// Release builds never set it.
  static const _demoApps = bool.fromEnvironment('KOSTV_DEMO_APPS');

  final UserPreferences _prefs;
  final MethodChannel _channel;
  final bool isSupported;

  /// The usual streaming apps, in the order the Apps row shows them until the
  /// user picks their own (Android TV package names).
  @visibleForTesting
  static const defaultHomePackages = [
    'com.netflix.ninja',
    'com.disney.disneyplus',
    'com.amazon.amazonvideo.livingroom',
    'com.wbd.stream',
    'com.hbo.hbonow',
    'com.apple.atve.androidtv.appletv',
    'com.google.android.youtube.tv',
    'com.google.android.youtube.tvmusic',
    'com.spotify.tv.android',
    'tv.twitch.android.app',
  ];

  /// How many apps the Apps row shows before the user picks their own, when
  /// fewer of the usual ones are installed.
  static const _defaultHomeCount = 8;

  /// The TV's own Settings app, which All apps already opens from its first
  /// card, so it isn't listed a second time. (The TV side leaves it out too,
  /// whatever its package on that TV.)
  @visibleForTesting
  static const settingsPackages = {
    'com.android.tv.settings',
    'com.android.settings',
  };

  static bool _listed(InstalledApp app) =>
      !settingsPackages.contains(app.packageName);

  List<InstalledApp> _apps = const [];
  bool _loaded = false;
  Future<void>? _loading;

  /// Every installed app, by name.
  List<InstalledApp> get apps => _apps;

  /// Whether the list has been read at least once.
  bool get isLoaded => _loaded;

  /// Reads the installed apps again (on start, and when the app comes back to
  /// the front, so a newly installed app shows up).
  Future<void> refresh() {
    if (!isSupported) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  /// Reads the list once, if it hasn't been read yet.
  Future<void> ensureLoaded() => _loaded ? Future.value() : refresh();

  Future<void> _load() async {
    if (_demoApps) {
      await _loadDemo();
      return;
    }
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('listInstalledApps');
      _apps = [
        for (final entry in raw ?? const <Object?>[])
          ?InstalledApp.fromMap(entry),
      ].where(_listed).toList();
    } on PlatformException catch (e) {
      debugPrint('[InstalledApps] list failed: $e');
    } on MissingPluginException {
      // No native side (tests, other platforms).
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _loadDemo() async {
    try {
      final response = await Dio().get<List<dynamic>>(
        Uri.base.resolve('kostv_demo_apps.json').toString(),
      );
      _apps = [
        for (final entry in response.data ?? const [])
          if (entry is Map)
            ?InstalledApp.fromMap({
              ...entry,
              'art': entry['art'] is String
                  ? base64Decode(entry['art'] as String)
                  : null,
            }),
      ].where(_listed).toList();
    } catch (e) {
      debugPrint('[InstalledApps] demo list failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Opens [app]. False if the TV couldn't open it (uninstalled meanwhile).
  Future<bool> launch(InstalledApp app) async {
    if (_demoApps) return true;
    try {
      final opened = await _channel.invokeMethod<bool>(
        'launchInstalledApp',
        {'package': app.packageName},
      );
      if (opened != true) unawaited(refresh());
      return opened == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the TV's own settings.
  Future<bool> openSystemSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSystemSettings') == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// The apps on the Apps row, in order: the user's choice if they made one,
  /// else the usual streaming apps that are installed, topped up with others.
  List<InstalledApp> get homeApps {
    final byPackage = {for (final app in _apps) app.packageName: app};
    final chosen = _chosenPackages();
    if (chosen != null) {
      return [for (final p in chosen) ?byPackage[p]];
    }
    final result = [for (final p in defaultHomePackages) ?byPackage[p]];
    for (final app in _apps) {
      if (result.length >= _defaultHomeCount) break;
      if (!result.contains(app)) result.add(app);
    }
    return result;
  }

  bool isOnHome(InstalledApp app) =>
      homeApps.any((a) => a.packageName == app.packageName);

  /// Adds [app] to the end of the Apps row.
  Future<void> addToHome(InstalledApp app) async {
    final packages = _currentHomePackages();
    if (packages.contains(app.packageName)) return;
    await _save([...packages, app.packageName]);
  }

  Future<void> removeFromHome(InstalledApp app) async {
    final packages = _currentHomePackages()..remove(app.packageName);
    await _save(packages);
  }

  /// Moves [app] [offset] places along the Apps row (-1 left, 1 right).
  Future<void> moveOnHome(InstalledApp app, int offset) async {
    final packages = _currentHomePackages();
    final from = packages.indexOf(app.packageName);
    if (from < 0) return;
    final to = (from + offset).clamp(0, packages.length - 1);
    if (to == from) return;
    packages
      ..removeAt(from)
      ..insert(to, app.packageName);
    await _save(packages);
  }

  List<String> _currentHomePackages() =>
      [for (final app in homeApps) app.packageName];

  List<String>? _chosenPackages() {
    final raw = _prefs.get(UserPreferences.homeApps);
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return [for (final p in decoded) if (p is String) p];
    } on FormatException {
      // Fall through to the defaults.
    }
    return null;
  }

  Future<void> _save(List<String> packages) async {
    await _prefs.set(UserPreferences.homeApps, jsonEncode(packages));
    notifyListeners();
  }
}

/// Kos TV: whether this is a TV whose apps can be listed, which is where the
/// Apps row, the Apps button and their settings appear.
bool kostvAppsAvailable() {
  final getIt = GetIt.instance;
  return PlatformDetection.isTV &&
      getIt.isRegistered<InstalledAppsService>() &&
      getIt<InstalledAppsService>().isSupported;
}

/// Kos TV: whether the navigation bar shows the Apps button: where
/// [kostvAppsAvailable], while it is turned on in Settings.
bool showKostvAppsButton(UserPreferences prefs) =>
    kostvAppsAvailable() && prefs.get(UserPreferences.showAppsButton);
