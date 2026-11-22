import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/app_update_service.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/app_update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('org.moonfin.androidtv/platform');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('update dialog', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferenceStore();
      await store.init();
      GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    });

    tearDown(() => GetIt.instance.reset());

    testWidgets('shows the release notes from the plugin', (tester) async {
      final update = DesktopUpdateInfo(
        version: '1.21.0',
        downloadUri: Uri.parse(
          'https://example.invalid/Moonfin/Kostv/Update/Download/a/tv.apk',
        ),
        notes: 'Arreglos del reproductor.\nMás rápido al abrir.',
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppUpdateDialog(context, update),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('v1.21.0 disponible'), findsOneWidget);
      expect(find.text('Novedades'), findsOneWidget);
      expect(
        find.text('Arreglos del reproductor.\nMás rápido al abrir.'),
        findsOneWidget,
      );
      // No web page to send anyone to any more.
      expect(find.text('Leer notas de la versión'), findsNothing);
    });

    testWidgets('without notes there is no notes box', (tester) async {
      final update = DesktopUpdateInfo(
        version: '1.21.0',
        downloadUri: Uri.parse('https://example.invalid/x/tv.apk'),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppUpdateDialog(context, update),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateReleaseNotes), findsNothing);
    });
  });

  group('downloadAndVerifyUpdate', () {
    final apk = List<int>.generate(4096, (i) => i % 251);
    final apkSha = sha256.convert(apk).toString();
    final l10n = lookupAppLocalizations(const Locale('es'));

    late HttpServer server;
    late List<HttpHeaders> seen;
    late Directory dir;
    late bool? signatureAnswer;
    late List<MethodCall> calls;
    var redirect = false;

    setUpAll(() {
      // flutter_test answers every HttpClient request with a 400; these
      // tests talk to a real local server.
      HttpOverrides.global = null;
    });

    setUp(() async {
      seen = [];
      calls = [];
      redirect = false;
      signatureAnswer = true;
      dir = await Directory.systemTemp.createTemp('kostv_update_test');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        seen.add(request.headers);
        if (redirect) {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, 'http://127.0.0.2/x.apk');
        } else {
          request.response
            ..contentLength = apk.length
            ..add(apk);
        }
        await request.response.close();
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            if (call.method == 'apkSignatureMatches') return signatureAnswer;
            return null;
          });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    DesktopUpdateInfo update({String? sha, int? size}) => DesktopUpdateInfo(
      version: '1.21.0',
      versionCode: 102100000,
      downloadUri: Uri.parse(
        'http://127.0.0.1:${server.port}/Moonfin/Kostv/Update/Download/a/tv.apk',
      ),
      downloadHeaders: const {'Authorization': 'MediaBrowser Token="t"'},
      sha256: sha ?? apkSha,
      size: size ?? apk.length,
    );

    Future<Object?> run(DesktopUpdateInfo info, File file) async {
      try {
        await downloadAndVerifyUpdate(info, file, ValueNotifier<double?>(null));
        return null;
      } catch (e) {
        return e;
      }
    }

    test('downloads with the session token and checks the signature', () async {
      final file = File('${dir.path}/kostv-update.apk');
      final error = await run(update(), file);
      expect(error, isNull);
      expect(seen.single.value('authorization'), 'MediaBrowser Token="t"');
      expect(await file.readAsBytes(), apk);
      final check = calls.singleWhere((c) => c.method == 'apkSignatureMatches');
      expect((check.arguments as Map)['path'], file.path);
    });

    test('a SHA-256 that does not match is a damaged download', () async {
      final file = File('${dir.path}/kostv-update.apk');
      final error = await run(update(sha: 'a' * 64), file);
      expect(error, isNotNull);
      expect(updateFailureMessage(l10n, error!), l10n.updateDownloadCorrupt);
      // The signature isn't even asked about.
      expect(calls.where((c) => c.method == 'apkSignatureMatches'), isEmpty);
    });

    test('an APK signed otherwise is refused with its own message', () async {
      signatureAnswer = false;
      final file = File('${dir.path}/kostv-update.apk');
      final error = await run(update(), file);
      expect(error, isNotNull);
      expect(updateFailureMessage(l10n, error!), l10n.updateSignatureMismatch);
    });

    test('when Android cannot tell, it is refused too', () async {
      signatureAnswer = null;
      final file = File('${dir.path}/kostv-update.apk');
      final error = await run(update(), file);
      expect(updateFailureMessage(l10n, error!), l10n.updateSignatureMismatch);
    });

    test('a redirect is not followed with the token', () async {
      redirect = true;
      final file = File('${dir.path}/kostv-update.apk');
      final error = await run(update(), file);
      expect(error, isNotNull);
      expect(seen, hasLength(1));
      expect(updateFailureMessage(l10n, error!), l10n.updateDownloadFailed);
    });
  });
}
