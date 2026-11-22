const B = require('./base.js') /* base.js = movil_mk.js sin el bloque final que hace las fotos */;
const { pg, tabs, accessory, avatar, lcard, FILMS, heroArt, icx, ic, status, card, mixCard } = B;
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const OUT = __dirname;
const extra = `<style>
.tbi.t{flex:none;flex-direction:row;gap:8px;padding:0 18px;font-size:14.5px;height:52px}
</style>`;
// Barra de la tableta: compacta, centrada, icono y nombre en línea; Buscar aparte.
function tbar(W, { active = 'Inicio', bottom = 26, top = null } = {}) {
  const t = tabs(active, 'A', false).replace(/class="tbi/g, 'class="tbi t').replace(/<span>/g, '<span>');
  const S = 62, gap = 10, w = 560, left = Math.round((W - w - S - gap) / 2);
  const pos = top != null ? `top:${top}px` : `bottom:${bottom}px`;
  return `<div class="g bar" style="left:${left}px;${pos};width:${w}px;height:${S}px;z-index:50;justify-content:space-between">${t}</div>
  <div class="g rb" style="left:${left + w + gap}px;${pos};width:${S}px;height:${S}px;z-index:50">${icx('search', 26, '#fff')}</div>`;
}
function rowAt(title, items, top, left, { w, h, txt = true, gap = 16 } = {}) {
  return `<div style="position:absolute;left:${left}px;right:0;top:${top}px;z-index:3"><div class="o" style="font-size:24px;margin-bottom:12px">${title}</div>
  <div class="row" style="gap:${gap}px;align-items:flex-start">${items.map((f) => lcard(f, w, { h, txt })).join('')}</div></div>`;
}
function head(W, title, top = 34) {
  const btn = (inner) => `<div class="g rb" style="position:relative;width:46px;height:46px">${inner}</div>`;
  return `<div class="row" style="position:absolute;top:${top}px;left:32px;right:32px;justify-content:space-between;z-index:40">
   <div class="o" style="font-size:40px;text-shadow:0 2px 16px rgba(0,0,0,.35)">${title}</div>
   <div class="row" style="gap:12px">${btn(ic('cast', 20, '#fff'))}${btn(`${ic('inbox', 20, '#fff')}<i class="bdg">3</i>`)}</div></div>`;
}
const hero = (left, top, fs = 48, w = 520) => `<div style="position:absolute;left:${left}px;top:${top}px;width:${w}px;z-index:3">
  <div class="kick" style="color:#9FF5E2;font-size:12px">Ya está aquí lo que pediste</div>
  <div class="o" style="font-size:${fs}px;line-height:1.03;margin-top:8px">La casa del faro</div>
  <div style="color:rgba(243,245,250,.75);font-size:15px;margin-top:8px">Serie · 2024 · Drama · 2 temporadas</div>
  <div class="row" style="gap:12px;margin-top:18px"><div class="btnw p" style="padding:0 26px">${ic('play', 20, '#0B0B0F')}Ver T1:E9</div>
  <div class="g btnw" style="position:relative;padding:0 24px">${ic('bookmark', 18, '#fff')}<span>Quiero verlo</span></div></div></div>`;
const fade = '<div style="position:absolute;left:0;right:0;bottom:0;height:200px;z-index:20;background:linear-gradient(0deg,rgba(6,6,10,.6),transparent)"></div>';
const accC = (W, bottom, w = 632) => accessory({ bottom, left: Math.round((W - w) / 2), right: Math.round((W - w) / 2), h: 56 });
const note = (l, t, w, s) => `<div class="note" style="left:${l}px;top:${t}px;max-width:${w}px;font-size:13px">${s}</div>`;

function vertical() {
  const W = 834, H = 1194;
  const body = `${extra}${heroArt(720)}${head(W, 'Inicio')}${hero(32, 360)}
  ${rowAt('Seguir viendo', FILMS.slice(0, 4), 620, 32, { w: 250 })}
  ${rowAt('Novedades', FILMS.slice(4, 9), 860, 32, { w: 150, h: 220, txt: false })}
  ${fade}${accC(W, 100)}${tbar(W)}
  ${note(32, 120, 380, 'Tableta en vertical: la misma barra de cristal del móvil, pero <b>compacta y centrada</b>, con icono y nombre en línea. Encima, el mini reproductor del mismo ancho. Caben 4 tarjetas por fila.')}`;
  return { name: 'tableta_vertical', w: W, h: H, html: pg(W, H, body) };
}
function horizontal() {
  const W = 1194, H = 834;
  const body = `${extra}${heroArt(834)}${head(W, 'Inicio')}${hero(40, 230, 54, 600)}
  ${rowAt('Seguir viendo', FILMS.slice(0, 5), 490, 40, { w: 260 })}
  ${fade}${accC(W, 100)}${tbar(W)}
  ${note(700, 120, 420, '<b>Recomendada.</b> En horizontal, la misma barra abajo y centrada: no cambia de sitio al girar la tableta, queda a mano del pulgar y no quita ancho al contenido. Al bajar se recoge igual que en el móvil.')}`;
  return { name: 'tableta_horizontal', w: W, h: H, html: pg(W, H, body) };
}
function horizontalArriba() {
  const W = 1194, H = 834;
  const t = tabs('Inicio', 'A', false).replace(/class="tbi/g, 'class="tbi t');
  const body = `${extra}${heroArt(834)}
  <div class="row" style="position:absolute;top:22px;left:32px;right:32px;justify-content:space-between;z-index:40">
    <div class="o" style="font-size:24px">kOS <span style="font-weight:300;font-size:13px;letter-spacing:.2em;background:var(--grad);-webkit-background-clip:text;color:transparent">TV</span></div>
    <div class="g bar" style="position:relative;width:520px;height:60px;justify-content:space-between">${t}</div>
    <div class="row" style="gap:10px"><div class="g rb" style="position:relative;width:48px;height:48px">${ic('search', 21, '#fff')}</div><div class="g rb" style="position:relative;width:48px;height:48px">${ic('inbox', 20, '#fff')}<i class="bdg">3</i></div></div></div>
  ${hero(40, 230, 54, 600)}
  ${rowAt('Seguir viendo', FILMS.slice(0, 5), 490, 40, { w: 260 })}
  ${fade}${accessory({ bottom: 24, left: 800, right: 28, h: 58 })}
  ${note(330, 96, 520, 'Alternativa: en horizontal la barra sube arriba (como el ordenador y las tabletas de Apple). Más «de escritorio», pero cambia de sitio al girar y queda lejos de las manos.')}`;
  return { name: 'tableta_horizontal_arriba', w: W, h: H, html: pg(W, H, body) };
}
function musica() {
  const W = 1194, H = 834;
  const body = `${extra}<div style="position:absolute;inset:0;background:radial-gradient(ellipse 80% 45% at 15% 0%,rgba(227,58,214,.5),transparent 70%),radial-gradient(ellipse 60% 40% at 100% 20%,rgba(79,216,255,.3),transparent 70%),#0B0B0F"></div>
  ${head(W, 'Música')}
  <div class="row" style="position:absolute;left:32px;top:104px;gap:10px;z-index:3">${['Para ti', 'Tus listas', 'Artistas', 'Álbumes'].map((x, i) => `<div class="g" style="position:relative;height:38px;padding:0 18px;display:flex;align-items:center;font-size:15px;font-weight:${i ? 500 : 700};${i ? '' : 'background:rgba(255,255,255,.22)'}"><span>${x}</span></div>`).join('')}</div>
  <div style="position:absolute;left:32px;top:166px;z-index:3"><div class="o" style="font-size:24px;margin-bottom:12px">Tus mezclas</div>
   <div class="row" style="gap:16px;align-items:flex-start">${mixCard(1, 200, 'brillo', ['Clara Vega', 'Lola Brisa'])}${mixCard(2, 200, 'marea', ['DJ Marea', 'Sal y Limón'])}${mixCard(3, 200, 'limon', ['Rumba Norte', 'Nube Roja'])}${mixCard(4, 200, 'luna', ['Luna Sur', 'Clara Vega'])}${mixCard(5, 200, 'sal', ['Sal y Limón'])}</div></div>
  <div style="position:absolute;left:32px;top:470px;z-index:3"><div class="o" style="font-size:24px;margin-bottom:12px">Escuchado hace poco</div>
   <div class="row" style="gap:16px;align-items:flex-start">${['verano', 'norte', 'luna', 'orilla', 'bailar', 'primavera', 'faroles'].map((a) => card(a, 160)).join('')}</div></div>
  ${fade}${accC(W, 100)}${tbar(W, { active: 'Música' })}`;
  return { name: 'tableta_musica', w: W, h: H, html: pg(W, H, body) };
}
(async () => {
  const b = await chromium.launch();
  for (const s of [vertical(), horizontal(), horizontalArriba(), musica()]) {
    const p = await b.newPage({ viewport: { width: s.w, height: s.h }, deviceScaleFactor: 2 });
    const f = path.join(OUT, 'html', s.name + '.html'); fs.writeFileSync(f, s.html);
    await p.goto('file://' + f); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(200);
    await p.screenshot({ path: path.join(OUT, s.name + '.png') }); await p.close(); console.log(s.name);
  }
  await b.close();
})();
