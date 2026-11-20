import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:server_core/server_core.dart' show MediaServerClient;
import 'package:shared_preferences/shared_preferences.dart';

import '../util/server_url.dart';

/// Car hosts and the artwork provider fetch images without the app's
/// Authorization header, so the URL has to carry the token itself.
String? carAuthedImageUrl(MediaServerClient client, String? url) =>
    tokenAuthedUrl(client, url);

/// Rewrites remote artwork URLs into content:// URIs backed by the native
/// MoonfinArtProvider.
///
/// The Android Auto host fetches browse artwork in its own process, which
/// refuses cleartext http and knows nothing about server auth, so a raw
/// http(s) URL to a home server never loads. Routing it through our provider
/// lets Moonfin download the image in its own process (where cleartext and
/// credentials work) and hand the car a content:// URI it can read. On other
/// platforms the original URL is kept: CarPlay fetches artwork in-process, so
/// it needs no rewrite.
///
/// The provider is exported so the car process can read it, so it only serves
/// hosts we have actually wrapped. [wrap] records each host and [persistHosts]
/// writes them to the shared preferences the provider checks.
///
/// The launcher and car host keep these URIs in their own storage, so [wrap]
/// also takes the server token out of the URL and the provider adds it back
/// from the same preferences.
class CarArtwork {
  CarArtwork._();
  static final CarArtwork instance = CarArtwork._();

  /// A fresh one, with nothing resolved or recorded yet.
  @visibleForTesting
  factory CarArtwork.forTesting() => CarArtwork._();

  static const _hostsKey = 'moonfin_art_hosts';
  static const _tokensKey = 'moonfin_art_tokens';
  static const _tokenParams = {
    'apikey',
    'api_key',
    'x-emby-token',
    'token',
  };

  String? _authority;
  Future<void>? _init;
  final Set<String> _hosts = {};
  final Map<String, String> _tokens = {};
  bool _dirty = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Resolves the provider authority once. Callers await this before building
  /// media items so [wrap] has the authority ready.
  Future<void> ensureReady() {
    if (!_isAndroid) return Future.value();
    return _init ??= _resolve();
  }

  Future<void> _resolve() async {
    try {
      final info =
          await PackageInfo.fromPlatform().timeout(const Duration(seconds: 5));
      _authority = '${info.packageName}.artwork';
    } catch (_) {
      // Do not memoize the failure: with a null authority every wrap() degrades
      // to a raw URL the car host refuses, killing all art for the session.
      // Clearing _init lets the next ensureReady try again.
      _init = null;
    }
  }

  Uri? wrap(String? url) {
    if (url == null) return null;
    // Idempotent: the persisted last-session artUri is already wrapped.
    if (url.startsWith('content://')) return Uri.tryParse(url);
    final authority = _authority;
    final parsed = Uri.tryParse(url);
    if (authority == null) {
      // Kos TV: on Android this URL ends up in the launcher's or the car
      // host's own storage, so it never takes the token along, even when
      // the provider couldn't be named (PackageInfo failed). Jellyfin serves
      // item images without one.
      return _isAndroid ? Uri.tryParse(_splitToken(url, parsed).$1) : parsed;
    }
    final host = parsed?.host;
    if (host != null && host.isNotEmpty && _hosts.add(host)) {
      _dirty = true;
    }
    return Uri(
      scheme: 'content',
      host: authority,
      path: '/img',
      queryParameters: {'u': _withoutToken(url, parsed)},
    );
  }

  String _withoutToken(String url, Uri? parsed) {
    final (stripped, token) = _splitToken(url, parsed);
    if (parsed == null || token == null) return stripped;
    final origin = '${parsed.scheme}://${parsed.host}:${parsed.port}';
    if (_tokens[origin] != token) {
      _tokens[origin] = token;
      _dirty = true;
    }
    return stripped;
  }

  /// [url] without its token parameter, and that parameter (`name=value`).
  (String, String?) _splitToken(String url, Uri? parsed) {
    final q = url.indexOf('?');
    if (parsed == null || q < 0) return (url, null);
    final kept = <String>[];
    String? token;
    for (final part in url.substring(q + 1).split('&')) {
      if (_tokenParams.contains(part.split('=').first.toLowerCase())) {
        token = part;
      } else {
        kept.add(part);
      }
    }
    if (token == null) return (url, null);
    final base = url.substring(0, q);
    return (kept.isEmpty ? base : '$base?${kept.join('&')}', token);
  }

  /// Kos TV: drops the tokens kept for the provider, on sign-out and when
  /// another person's profile takes over. Whoever is signed in next records
  /// their own the next time artwork is wrapped.
  Future<void> forgetTokens() async {
    _tokens.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokensKey);
    } catch (_) {}
    // The next person's may have been recorded meanwhile.
    if (_tokens.isNotEmpty) {
      _dirty = true;
      await persistHosts();
    }
  }

  /// Writes the hosts and tokens seen so far to the preferences the provider
  /// reads. Await this before returning media items so they're in place before
  /// the car requests an icon.
  Future<void> persistHosts() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hostsKey, _hosts.join(','));
      await prefs.setString(_tokensKey, jsonEncode(_tokens));
    } catch (_) {
      _dirty = true;
    }
  }
}
