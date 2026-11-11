// Exports the iOS, tvOS and web icons from apple_web.html.
// usage: node render_apple_web.js <apple_web.html> <repo root>
const path = require('path');
const { chromium } = require('playwright');
const [page, repo] = process.argv.slice(2);
const ios = path.join(repo, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
const brand = path.join(repo, 'tvos/Runner/Assets.xcassets/AppIcon.brandassets');
const jobs = [];
for (const [name, px] of [
  ['1024x1024@1x', 1024], ['20x20@1x', 20], ['20x20@2x', 40], ['20x20@3x', 60],
  ['29x29@1x', 29], ['29x29@2x', 58], ['29x29@3x', 87], ['40x40@1x', 40],
  ['40x40@2x', 80], ['40x40@3x', 120], ['60x60@2x', 120], ['60x60@3x', 180],
  ['76x76@1x', 76], ['76x76@2x', 152], ['83.5x83.5@2x', 167],
]) jobs.push(['squarecrop', px, px, path.join(ios, `Icon-App-${name}.png`), false]);
for (const [stack, file, w, h] of [
  ['App Icon.imagestack', 'App-Icon-Small-1x.png', 400, 240],
  ['App Icon.imagestack', 'App-Icon-Small-2x.png', 800, 480],
  ['App Icon - App Store.imagestack', 'App-Icon-Large-1x.png', 1280, 768],
  ['App Icon - App Store.imagestack', 'App-Icon-Large-2x.png', 2560, 1536],
]) {
  jobs.push(['tvback', w, h, path.join(brand, stack, 'Back.imagestacklayer/Content.imageset', file), false]);
  jobs.push(['tvfront', w, h, path.join(brand, stack, 'Front.imagestacklayer/Content.imageset', file), true]);
}
for (const [dir, file, w, h] of [
  ['Top Shelf Image.imageset', 'Top-Shelf-1x.png', 1920, 720],
  ['Top Shelf Image.imageset', 'Top-Shelf-2x.png', 3840, 1440],
  ['Top Shelf Image Wide.imageset', 'Top-Shelf-Wide-1x.png', 2320, 720],
  ['Top Shelf Image Wide.imageset', 'Top-Shelf-Wide-2x.png', 4640, 1440],
]) jobs.push(['shelf', w, h, path.join(brand, dir, file), false]);
for (const [file, px, what] of [
  ['Icon-192.png', 192, 'squarecrop'], ['Icon-512.png', 512, 'squarecrop'],
  ['Icon-maskable-192.png', 192, 'square'], ['Icon-maskable-512.png', 512, 'square'],
]) jobs.push([what, px, px, path.join(repo, 'web/icons', file), false]);
jobs.push(['rounded', 64, 64, path.join(repo, 'web/favicon.png'), true]);

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ deviceScaleFactor: 1, viewport: { width: 5000, height: 2000 } });
  const p = await ctx.newPage();
  await p.goto('file://' + path.resolve(page));
  await p.evaluate(() => document.fonts.ready);
  for (const [what, w, h, out, transparent] of jobs) {
    await p.evaluate(([what, w, h]) => draw(what, w, h), [what, w, h]);
    await p.evaluate(() => document.fonts.ready);
    await p.locator('#out').screenshot({ path: out, omitBackground: transparent });
  }
  console.log('fonts ok:', await p.evaluate(() => document.fonts.check('700 40px Outfit') && document.fonts.check('300 40px Outfit')), jobs.length, 'images');
  await browser.close();
})();
