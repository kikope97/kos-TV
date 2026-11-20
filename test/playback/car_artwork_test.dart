import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/car_artwork.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('keeps the server token out of the wrapped URI', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    PackageInfo.setMockInitialValues(
      appName: 'kOS TV',
      packageName: 'com.kikope.kostv',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    await CarArtwork.instance.ensureReady();

    final jellyfin = CarArtwork.instance.wrap(
      'http://10.0.0.7:8096/Items/1/Images/Primary?tag=a&ApiKey=secret&quality=90',
    )!;
    final other = CarArtwork.instance.wrap(
      'https://jellyfin.example.com/Items/2/Images/Primary?api_key=other',
    )!;

    expect(
      jellyfin.queryParameters['u'],
      'http://10.0.0.7:8096/Items/1/Images/Primary?tag=a&quality=90',
    );
    expect(
      other.queryParameters['u'],
      'https://jellyfin.example.com/Items/2/Images/Primary',
    );

    await CarArtwork.instance.persistHosts();
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('moonfin_art_tokens')!), {
      'http://10.0.0.7:8096': 'ApiKey=secret',
      'https://jellyfin.example.com:443': 'api_key=other',
    });
  });

  test('never hands out the token when the provider is not named yet', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    // ensureReady never ran or PackageInfo failed: no authority.
    final artwork = CarArtwork.forTesting();

    expect(
      artwork
          .wrap(
            'http://10.0.0.7:8096/Items/1/Images/Primary?tag=a&api_key=secret',
          )
          .toString(),
      'http://10.0.0.7:8096/Items/1/Images/Primary?tag=a',
    );
    expect(
      artwork
          .wrap('http://10.0.0.7:8096/Items/1/Images/Primary?ApiKey=secret')
          .toString(),
      'http://10.0.0.7:8096/Items/1/Images/Primary',
    );
  });

  test('forgets the tokens it kept on sign-out or a profile switch', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    PackageInfo.setMockInitialValues(
      appName: 'kOS TV',
      packageName: 'com.kikope.kostv',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    final artwork = CarArtwork.forTesting();
    await artwork.ensureReady();
    artwork.wrap('http://10.0.0.7:8096/Items/1/Images/Primary?api_key=first');
    await artwork.persistHosts();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('moonfin_art_tokens'), isNotNull);

    await artwork.forgetTokens();

    expect(prefs.getString('moonfin_art_tokens'), isNull);
    // The hosts stay, so artwork already handed out keeps loading.
    expect(prefs.getString('moonfin_art_hosts'), '10.0.0.7');

    // The next person's token is recorded afresh.
    artwork.wrap('http://10.0.0.7:8096/Items/2/Images/Primary?api_key=next');
    await artwork.persistHosts();
    expect(jsonDecode(prefs.getString('moonfin_art_tokens')!), {
      'http://10.0.0.7:8096': 'api_key=next',
    });
  });
}
