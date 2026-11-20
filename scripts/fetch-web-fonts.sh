#!/usr/bin/env bash
# Kos TV: puts the fallback fonts the web engine can ask for (emoji, Chinese,
# Japanese, symbols...) into <web build>/fonts and points the build's
# flutter_bootstrap.js at them, so browsers load them from wherever the app is
# hosted instead of Google Fonts. Run it after flutter build web. The list comes
# from the built main.dart.js (the JavaScript build, also there with --wasm), so
# it always matches the Flutter version that made the build.
#
# A build it hasn't run on still works: it keeps fetching them from Google.
#
# Adapted from upstream a6bec3155.
set -euo pipefail

WEB_DIR="${1:-build/web}"
BOOTSTRAP="$WEB_DIR/flutter_bootstrap.js"
GOOGLE_LINE='const kosTvFontFallbackBaseUrl = "https://fonts.gstatic.com/s/";'
LOCAL_LINE='const kosTvFontFallbackBaseUrl = "fonts/";'

if ! grep -qF "$GOOGLE_LINE" "$BOOTSTRAP" && ! grep -qF "$LOCAL_LINE" "$BOOTSTRAP"; then
  echo "No font address line in $BOOTSTRAP (see web/flutter_bootstrap.js)" >&2
  exit 1
fi

paths="$(grep -oE '"[a-z0-9]+/v[0-9]+/[A-Za-z0-9_-]+(\.[0-9]+)?\.woff2"' "$WEB_DIR/main.dart.js" | tr -d '"' | sort -u)" || true
if [ -z "$paths" ]; then
  echo "No fallback font list in $WEB_DIR/main.dart.js" >&2
  exit 1
fi

# Flutter leaves this folder alone between builds, so clear out fonts an older
# Flutter asked for.
rm -rf "$WEB_DIR/fonts"
printf '%s\n' "$paths" | xargs -P 8 -I{} \
  curl -fsS --retry 3 --create-dirs -o "$WEB_DIR/fonts/{}" "https://fonts.gstatic.com/s/{}"

# Only once every font is in place: from here on the app asks for them here.
sed -i "s|$GOOGLE_LINE|$LOCAL_LINE|" "$BOOTSTRAP"
grep -qF "$LOCAL_LINE" "$BOOTSTRAP"

echo "Fetched $(printf '%s\n' "$paths" | wc -l | tr -d ' ') fallback fonts into $WEB_DIR/fonts"
