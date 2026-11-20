{{flutter_js}}
{{flutter_build_config}}

// Kos TV: where the web engine fetches the fonts for characters the app's own
// fonts don't have (emoji, Chinese, Japanese, symbols...). A plain build keeps
// the engine's default, Google Fonts. scripts/fetch-web-fonts.sh, run after the
// build (build.yml does, for the web and its Docker image), puts the fonts in
// fonts/, next to the app, and changes this line to "fonts/", so the browser
// never asks Google for them. Keep the line as it is: the script looks for it.
const kosTvFontFallbackBaseUrl = "https://fonts.gstatic.com/s/";
// The subtitle fonts picked in Settings come from the same place, under the
// same paths (lib/playback/subtitle_font_base_web.dart reads this).
globalThis.kosTvFontBaseUrl = kosTvFontFallbackBaseUrl;

// No service worker settings, as in Flutter's own default for a build without
// --pwa-strategy: with them, the loader would register a service worker.
_flutter.loader.load({
  config: { fontFallbackBaseUrl: kosTvFontFallbackBaseUrl },
});
