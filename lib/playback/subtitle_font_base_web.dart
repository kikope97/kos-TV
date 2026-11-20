import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('kosTvFontBaseUrl')
external JSString? get _fontBaseUrl;

/// Kos TV: the full address of the web build's own fonts folder, from what
/// web/flutter_bootstrap.js sets: "fonts/" once scripts/fetch-web-fonts.sh
/// has put them there. Null while it still points at Google Fonts. Resolved
/// against the page's base href, not the current route.
String? bundledSubtitleFontBase() {
  try {
    final base = _fontBaseUrl?.toDart;
    if (base == null ||
        base.isEmpty ||
        base.startsWith('https://fonts.gstatic.com/')) {
      return null;
    }
    return Uri.parse(web.document.baseURI).resolve(base).toString();
  } catch (_) {
    return null;
  }
}
