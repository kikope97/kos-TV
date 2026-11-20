#!/usr/bin/env bash
# Kos TV: puts the fallback fonts the web engine can ask for (emoji, Chinese,
# Japanese, symbols...) into <web build>/fonts and points the build's
# flutter_bootstrap.js at them, so browsers load them from wherever the app is
# hosted instead of Google Fonts. Run it after flutter build web. The list comes
# from the built main.dart.js (the JavaScript build, also there with --wasm), so
# it always matches the Flutter version that made the build.
#
# The subtitle fonts picked in Settings (lib/playback/subtitle_fonts.dart) go
# into the same folder, with the same paths as on Google Fonts, and the web
# asks for them there once the bootstrap line points at fonts/.
#
# A build it hasn't run on still works: it keeps fetching them from Google.
#
# Exits with 75 when the fonts couldn't be downloaded: the build is then left
# exactly as Flutter made it (no fonts/, the bootstrap pointing at Google), so
# it still works. Any other failure is a 1.
#
# Adapted from upstream a6bec3155.
set -euo pipefail

WEB_DIR="${1:-build/web}"
BOOTSTRAP="$WEB_DIR/flutter_bootstrap.js"
SUBTITLE_FONTS="$(dirname "$0")/../lib/playback/subtitle_fonts.dart"
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

subtitle_paths="$(grep -oE '\$_gstatic/[a-z0-9]+/v[0-9]+/[A-Za-z0-9_-]+\.ttf' "$SUBTITLE_FONTS" | sed 's|^\$_gstatic/||' | sort -u)" || true
if [ -z "$subtitle_paths" ]; then
  echo "No subtitle font list in $SUBTITLE_FONTS" >&2
  exit 1
fi

# Flutter leaves this folder alone between builds, so clear out fonts an older
# Flutter asked for.
rm -rf "$WEB_DIR/fonts"
# --retry alone doesn't retry a refused or cut connection, and without the
# timeouts a download stuck trickling would hold the build for hours.
if ! printf '%s\n%s\n' "$paths" "$subtitle_paths" | xargs -P 8 -I{} \
  curl -fsS --connect-timeout 15 --max-time 120 --retry 5 --retry-all-errors \
    --retry-delay 3 --create-dirs -o "$WEB_DIR/fonts/{}" "https://fonts.gstatic.com/s/{}"; then
  # Nothing half done stays behind: the build keeps asking Google.
  rm -rf "$WEB_DIR/fonts"
  sed -i "s|$LOCAL_LINE|$GOOGLE_LINE|" "$BOOTSTRAP"
  echo "Couldn't download the fonts: $BOOTSTRAP still fetches them from Google" >&2
  exit 75
fi

# Only once every font is in place: from here on the app asks for them here.
sed -i "s|$GOOGLE_LINE|$LOCAL_LINE|" "$BOOTSTRAP"
grep -qF "$LOCAL_LINE" "$BOOTSTRAP"

echo "Fetched $(printf '%s\n' "$paths" | wc -l | tr -d ' ') fallback fonts and $(printf '%s\n' "$subtitle_paths" | wc -l | tr -d ' ') subtitle font files into $WEB_DIR/fonts"
