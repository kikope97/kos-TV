import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/app_update_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/app_distribution.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sha = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';
const _server = 'https://jellyfin.example.invalid';
const _headers = {'Authorization': 'MediaBrowser Token="t"'};

Map<String, Object?> _available({
  int code = 102100000,
  String url = '/Moonfin/Kostv/Update/Download/abc/tv.apk',
}) => {
  'Available': true,
  'VersionName': '1.21.0',
  'VersionCode': code,
  'Notes': 'Arreglos del reproductor.',
  'Date': '2026-11-23T10:00:00Z',
  'Size': 125000000,
  'Sha256': _sha,
  'Url': url,
};

/// Answers every request with [status] and [body], noting what was asked.
class _Answer implements HttpClientAdapter {
  _Answer(this.status, [this.body]);

  final int status;
  final Object? body;
  final List<RequestOptions> asked = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('AppUpdateService.updateKindFor', () {
    test('the TV build asks for tv and the phone build for phone', () {
      expect(
        AppUpdateService.updateKindFor(DistributionChannel.androidTvApk),
        'tv',
      );
      expect(AppUpdateService.updateKindFor(DistributionChannel.apk), 'phone');
    });

    test('store, iOS and other builds have no updater', () {
      for (final channel in [
        DistributionChannel.aab,
        DistributionChannel.androidTvAab,
        DistributionChannel.iosSigned,
        DistributionChannel.iosUnsigned,
        DistributionChannel.macosDmg,
        DistributionChannel.linux,
        DistributionChannel.windows,
        DistributionChannel.unknown,
      ]) {
        expect(
          AppUpdateService.updateKindFor(channel),
          isNull,
          reason: '$channel',
        );
      }
    });
  });

  group('AppUpdateService.answerFor', () {
    test('a 2xx is read', () {
      expect(AppUpdateService.answerFor(200), PluginUpdateAnswer.answered);
    });

    test('an older plugin (404) or a refused kind (400) offers nothing', () {
      expect(AppUpdateService.answerFor(404), PluginUpdateAnswer.noRoute);
      expect(AppUpdateService.answerFor(400), PluginUpdateAnswer.noRoute);
    });

    test('a server error or an expired session is no answer', () {
      for (final status in [401, 403, 500, 502, 503]) {
        expect(
          AppUpdateService.answerFor(status),
          PluginUpdateAnswer.failed,
          reason: '$status',
        );
      }
    });
  });

  group('AppUpdateService.parseUpdate', () {
    DesktopUpdateInfo? parse(Object? data, {int installed = 102000000}) =>
        AppUpdateService.parseUpdate(
          data,
          serverBase: _server,
          headers: _headers,
          installedVersionCode: installed,
        );

    test('reads the contract', () {
      final update = parse(_available())!;
      expect(update.version, '1.21.0');
      expect(update.versionCode, 102100000);
      expect(update.notes, 'Arreglos del reproductor.');
      expect(update.size, 125000000);
      expect(update.sha256, _sha);
      expect(
        update.downloadUri.toString(),
        '$_server/Moonfin/Kostv/Update/Download/abc/tv.apk',
      );
      expect(update.downloadHeaders, _headers);
    });

    test('also takes the answer as text, and camelCase names', () {
      final camel = {
        for (final e in _available().entries)
          '${e.key[0].toLowerCase()}${e.key.substring(1)}': e.value,
      };
      expect(parse(jsonEncode(_available()))?.version, '1.21.0');
      expect(parse(camel)?.version, '1.21.0');
    });

    test('Available: false offers nothing', () {
      expect(parse({'Available': false}), isNull);
    });

    test('only a version code above the installed one is offered', () {
      expect(parse(_available(), installed: 102100000), isNull);
      expect(parse(_available(), installed: 102100001), isNull);
      expect(parse(_available(), installed: 102099999), isNotNull);
    });

    test('a server base with a path keeps it', () {
      final update = AppUpdateService.parseUpdate(
        _available(),
        serverBase: 'http://casa.invalid:8096/jellyfin/',
        headers: _headers,
        installedVersionCode: 0,
      )!;
      expect(
        update.downloadUri.toString(),
        'http://casa.invalid:8096/jellyfin/Moonfin/Kostv/Update/Download/abc/tv.apk',
      );
    });

    test('nothing without a valid SHA-256, a name or a code', () {
      expect(parse({..._available(), 'Sha256': null}), isNull);
      expect(parse({..._available(), 'Sha256': 'abc'}), isNull);
      expect(parse({..._available(), 'VersionName': ''}), isNull);
      expect(parse({..._available(), 'VersionCode': null}), isNull);
      expect(parse('not json'), isNull);
      expect(parse([1, 2]), isNull);
    });

    test('only an .apk path on the home server is downloaded', () {
      for (final url in [
        'https://elsewhere.invalid/x.apk',
        '//elsewhere.invalid/x.apk',
        'Moonfin/Kostv/Update/Download/abc/tv.apk',
        '/Moonfin/Kostv/Update/Download/abc/tv.zip',
        '',
      ]) {
        expect(parse(_available(url: url)), isNull, reason: url);
      }
    });
  });

  group('AppUpdateService checks', () {
    late PreferenceStore store;
    late UserPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(const {});
      store = PreferenceStore();
      await store.init();
      prefs = UserPreferences(store);
    });

    AppUpdateService service(
      _Answer answer, {
      DistributionChannel channel = DistributionChannel.androidTvApk,
      bool signedIn = true,
    }) {
      final dio = Dio()..httpClientAdapter = answer;
      return AppUpdateService(
        store,
        prefs,
        dio: dio,
        channel: channel,
        endpoint: () async =>
            signedIn ? (base: _server, headers: _headers) : null,
        installedVersionCode: () async => 102000000,
        storeInstalled: () async => false,
      );
    }

    test(
      'asks the plugin with the kind and the installed version code',
      () async {
        final answer = _Answer(200, _available());
        final result = await service(answer).checkForUpdateNowDetailed();
        expect(result.status, DesktopUpdateCheckStatus.updateAvailable);
        expect(result.update?.version, '1.21.0');
        final asked = answer.asked.single;
        expect(asked.uri.host, Uri.parse(_server).host);
        expect(asked.uri.path, '/Moonfin/Kostv/Update');
        expect(asked.uri.queryParameters, {
          'kind': 'tv',
          'versionCode': '102000000',
        });
        expect(asked.headers['Authorization'], _headers['Authorization']);
      },
    );

    test('the phone build asks for phone', () async {
      final answer = _Answer(200, {'Available': false});
      await service(
        answer,
        channel: DistributionChannel.apk,
      ).checkForUpdateNowDetailed();
      expect(answer.asked.single.uri.queryParameters['kind'], 'phone');
    });

    test('Available: false is up to date', () async {
      final result = await service(_Answer(200, {'Available': false}))
          .checkForUpdateNowDetailed();
      expect(result.status, DesktopUpdateCheckStatus.upToDate);
      expect(result.update, isNull);
    });

    test(
      'an older plugin without the route (404) is silently up to date',
      () async {
        final answer = _Answer(404);
        final result = await service(answer).checkForUpdateIfDueDetailed();
        expect(result.status, DesktopUpdateCheckStatus.upToDate);
        // It answered: the next automatic check waits the whole cooldown.
        final again = await service(answer).checkForUpdateIfDueDetailed();
        expect(again.status, DesktopUpdateCheckStatus.rateLimited);
      },
    );

    test('a server error is a failed check, retried soon', () async {
      final result = await service(_Answer(500)).checkForUpdateIfDueDetailed();
      expect(result.status, DesktopUpdateCheckStatus.checkFailed);
    });

    test('signed out there is no one to ask yet', () async {
      final answer = _Answer(200, _available());
      final result = await service(
        answer,
        signedIn: false,
      ).checkForUpdateNowDetailed();
      expect(result.status, DesktopUpdateCheckStatus.checkFailed);
      expect(answer.asked, isEmpty);
    });

    test('web, iOS and store builds ask nobody', () async {
      final answer = _Answer(200, _available());
      final result = await service(
        answer,
        channel: DistributionChannel.iosUnsigned,
      ).checkForUpdateNowDetailed();
      expect(result.status, DesktopUpdateCheckStatus.unsupportedPlatform);
      expect(answer.asked, isEmpty);
    });

    test(
      'a version offered lately is not offered again by the automatic check',
      () async {
        final first = await service(_Answer(200, _available()))
            .checkForUpdateIfDueDetailed();
        expect(first.status, DesktopUpdateCheckStatus.updateAvailable);
        await store.remove('app_update_last_check_ms');
        final second = await service(_Answer(200, _available()))
            .checkForUpdateIfDueDetailed();
        expect(second.status, DesktopUpdateCheckStatus.alreadyNotified);
      },
    );
  });
}
