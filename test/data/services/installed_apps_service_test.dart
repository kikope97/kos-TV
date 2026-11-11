import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/installed_apps_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kos TV: the installed apps behind the Apps row and the All apps screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kostv-test/platform');
  late UserPreferences prefs;
  late List<Map<String, Object?>> installed;
  late List<String> launched;

  Map<String, Object?> app(String package, String label, {bool banner = true}) => {
    'package': package,
    'label': label,
    'art': Uint8List.fromList([1, 2, 3]),
    'isBanner': banner,
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    prefs = UserPreferences(store);
    launched = [];
    installed = [
      app('com.example.alpha', 'Alpha'),
      app('com.google.android.youtube.tv', 'YouTube'),
      app('com.netflix.ninja', 'Netflix'),
      app('com.example.icononly', 'Icon only', banner: false),
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'listInstalledApps':
              return installed;
            case 'launchInstalledApp':
              final package = (call.arguments as Map)['package'] as String;
              launched.add(package);
              return installed.any((a) => a['package'] == package);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  InstalledAppsService service() =>
      InstalledAppsService(prefs, channel: channel, supported: true);

  test('reads the installed apps with their art', () async {
    final apps = service();
    await apps.refresh();

    expect(apps.isLoaded, isTrue);
    expect(apps.apps.map((a) => a.label), [
      'Alpha',
      'YouTube',
      'Netflix',
      'Icon only',
    ]);
    expect(apps.apps.first.isBanner, isTrue);
    expect(apps.apps.last.isBanner, isFalse);
  });

  test('the Apps row starts with the usual streaming apps, then others', () async {
    final apps = service();
    await apps.refresh();

    // Netflix comes before YouTube in the usual order, whatever their names.
    expect(apps.homeApps.map((a) => a.packageName), [
      'com.netflix.ninja',
      'com.google.android.youtube.tv',
      'com.example.alpha',
      'com.example.icononly',
    ]);
  });

  test('apps can be added, moved and removed, and that sticks', () async {
    final apps = service();
    await apps.refresh();

    await apps.removeFromHome(apps.apps.firstWhere((a) => a.label == 'Alpha'));
    await apps.moveOnHome(apps.apps.firstWhere((a) => a.label == 'YouTube'), -1);
    expect(apps.homeApps.map((a) => a.label), ['YouTube', 'Netflix', 'Icon only']);

    final again = service();
    await again.refresh();
    expect(again.homeApps.map((a) => a.label), ['YouTube', 'Netflix', 'Icon only']);

    await again.addToHome(again.apps.firstWhere((a) => a.label == 'Alpha'));
    expect(again.homeApps.last.label, 'Alpha');
    expect(again.isOnHome(again.apps.first), isTrue);
  });

  test('an uninstalled app drops off the Apps row', () async {
    final apps = service();
    await apps.refresh();
    await apps.removeFromHome(apps.apps.firstWhere((a) => a.label == 'Alpha'));

    installed.removeWhere((a) => a['package'] == 'com.netflix.ninja');
    await apps.refresh();

    expect(
      apps.homeApps.map((a) => a.packageName),
      isNot(contains('com.netflix.ninja')),
    );
  });

  test('opens an app through the TV', () async {
    final apps = service();
    await apps.refresh();

    expect(await apps.launch(apps.apps.first), isTrue);
    expect(launched, ['com.example.alpha']);
  });

  test('off Android the list stays empty and nothing is asked', () async {
    final apps = InstalledAppsService(prefs, channel: channel, supported: false);
    await apps.refresh();

    expect(apps.apps, isEmpty);
    expect(apps.homeApps, isEmpty);
  });
}
