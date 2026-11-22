const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const OUT = path.join(__dirname, '..');
(async () => {
  const only = process.argv[2];
  const sets = ['tv', 'phone', 'web', 'sheet'].filter((s) => fs.existsSync(path.join(__dirname, s + '.js')));
  let screens = [];
  for (const s of sets) screens = screens.concat(require('./' + s)());
  if (only) screens = screens.filter((s) => s.name.includes(only));
  const browser = await chromium.launch();
  for (const s of screens) {
    const pg = await browser.newPage({ viewport: { width: s.w, height: s.h }, deviceScaleFactor: 2 });
    const f = path.join(__dirname, 'html', s.name + '.html');
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, s.html);
    await pg.goto('file://' + f);
    await pg.evaluate(() => document.fonts.ready);
    await pg.waitForTimeout(150);
    await pg.screenshot({ path: path.join(OUT, s.name + '.png') });
    await pg.close();
    console.log(s.name);
  }
  await browser.close();
})();
