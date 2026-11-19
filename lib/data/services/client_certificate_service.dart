import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:server_core/server_core.dart';

import '../../auth/store/client_certificate_store.dart';
import '../../util/pkcs12_decoder.dart';
import '../../util/platform_detection.dart';
import 'background_download_coordinator.dart';

const _media3Control = MethodChannel('moonfin/media3_video_control');

final _compatPkcs12 = Expando<({Uint8List der, String password})>();

/// Kos TV: whether media3 may hold certificates this isolate sent it. It
/// starts with none, so an empty list is only worth sending after that.
bool _media3MayHoldCertificates = false;

/// Loads the stored certificates into every stack that presents them. Pass
/// [syncNative] false from isolates that have no plugins. [stored] is the
/// store's [ClientCertificateStore.getAll] already under way, if it is.
Future<void> installClientCertificates(
  ClientCertificateStore store, {
  bool syncNative = true,
  Future<List<StoredClientCertificate>>? stored,
}) async {
  setClientCertificates([
    for (final c in await (stored ?? store.getAll())) c.material,
  ]);
  if (!syncNative) return;
  final media3Certificates = nativeClientCertificates(pkcs12: false);
  // Kos TV: an empty list to a media3 that has none (every launch, before
  // the first frame) is a trip over the channel for nothing.
  if (PlatformDetection.isAndroid &&
      (media3Certificates.isNotEmpty || _media3MayHoldCertificates)) {
    if (media3Certificates.isNotEmpty) _media3MayHoldCertificates = true;
    try {
      await _media3Control.invokeMethod<void>('setClientCertificates', {
        'certificates': media3Certificates,
      });
      if (media3Certificates.isEmpty) _media3MayHoldCertificates = false;
    } on Exception {
      // Playback sends them again on the next open.
    }
  }
  if (GetIt.instance.isRegistered<BackgroundDownloadCoordinator>()) {
    await GetIt.instance<BackgroundDownloadCoordinator>()
        .applyClientCertificates(clientCertificates.toList());
  }
}

Future<void> removeClientCertificate(
  ClientCertificateStore store,
  String host,
) async {
  await store.remove(host);
  for (final extension in const ['crt', 'key', 'p12']) {
    final file = await clientCertificateFile(host, extension);
    if (await file.exists()) await file.delete();
  }
  await installClientCertificates(store);
}

/// The certificates as the native players take them: PEM for media3, and a
/// compatible .p12 for Apple's importer.
List<Map<String, Object?>> nativeClientCertificates({required bool pkcs12}) => [
  for (final c in clientCertificates)
    if (pkcs12)
      {
        'host': c.host,
        'p12Base64': base64Encode(compatPkcs12For(c).der),
        'password': compatPkcs12For(c).password,
      }
    else
      {'host': c.host, 'chainPem': c.chainPem, 'keyPem': c.keyPem},
];

({Uint8List der, String password}) compatPkcs12For(
  ClientCertificateMaterial certificate,
) => _compatPkcs12[certificate] ??= buildCompatPkcs12(
  chainPem: certificate.chainPem,
  keyPem: certificate.keyPem,
);

/// Where the copies that need a file path (mpv, the WebViews) are written.
Future<File> clientCertificateFile(String host, String extension) async {
  final dir = Directory(
    '${(await getApplicationSupportDirectory()).path}/mtls',
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
    if (PlatformDetection.isLinux || PlatformDetection.isMacOS) {
      await Process.run('chmod', ['700', dir.path]);
    }
  }
  final name = sha256.convert(normalizeCertificateHost(host).codeUnits);
  return File('${dir.path}/$name.$extension');
}
