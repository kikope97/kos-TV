// Exports the Android launcher icons and the Android TV banner from render.html.
// usage: node render.js <render.html> <android res dir>
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

const [page, res] = process.argv.slice(2);
const densities = { mdpi: 1, hdpi: 1.5, xhdpi: 2, xxhdpi: 3, xxxhdpi: 4 };

(async () => {
  const browser = await chromium.launch();
  for (const [name, scale] of Object.entries(densities)) {
    const ctx = await browser.newContext({ deviceScaleFactor: scale });
    const p = await ctx.newPage();
    await p.goto('file://' + path.resolve(page));
    await p.evaluate(() => document.fonts.ready);
    // Adaptive layers: 108 dp. Legacy: 48 dp. Render big, then let the
    // element size set the pixel size through deviceScaleFactor.
    await p.evaluate(() => {
      for (const id of ['foreground', 'background']) {
        const el = document.getElementById(id); el.setAttribute('width', 108); el.setAttribute('height', 108);
      }
      const l = document.getElementById('legacy'); l.setAttribute('width', 48); l.setAttribute('height', 48);
    });
    const dir = path.join(res, 'mipmap-' + name);
    fs.mkdirSync(dir, { recursive: true });
    await p.locator('#foreground').screenshot({ path: path.join(dir, 'ic_launcher_foreground.png'), omitBackground: true });
    await p.locator('#background').screenshot({ path: path.join(dir, 'ic_launcher_background.png'), omitBackground: true });
    await p.locator('#legacy').screenshot({ path: path.join(dir, 'ic_launcher.png'), omitBackground: true });
    await ctx.close();
  }
  // Banner: 320×180 dp drawn at xhdpi, as the TV launcher asks for.
  const ctx = await browser.newContext({ deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  await p.goto('file://' + path.resolve(page));
  await p.evaluate(() => document.fonts.ready);
  const bdir = path.join(res, 'drawable-xhdpi');
  fs.mkdirSync(bdir, { recursive: true });
  await p.locator('#banner').screenshot({ path: path.join(bdir, 'kostv_tv_banner.png') });
  console.log('fonts ok:', await p.evaluate(() => document.fonts.check('700 40px Outfit')));
  await browser.close();
})();
