// Maquetas del menú del móvil de kOS TV en «cristal líquido».
// Reutiliza las piezas de las maquetas de Música (solo se leen).
const L = require('/home/user/kos-TV/docs/diseno-musica/maquetas/lib.js');
const { ic, cover, card, mixCard, status, page, AL } = L;
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const OUT = __dirname;
const PREV = '/tmp/claude-0/-home-user-kos-TV/7af86e5b-00b3-5bbd-9eb0-2d96e684d63e/scratchpad/diseno_menu';

const X = {
  homeO: 'M12 5.69l5 4.5V18h-2v-6H9v6H7v-7.81l5-4.5M12 3L2 12h3v8h6v-6h2v6h6v-8h3L12 3z',
  exploreO: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-5.5-2.5l7.51-3.49L17.5 6.5 9.99 9.99 6.5 17.5zm5.5-6.6c.61 0 1.1.49 1.1 1.1s-.49 1.1-1.1 1.1-1.1-.49-1.1-1.1.49-1.1 1.1-1.1z',
  cal: 'M19 4h-1V2h-2v2H8V2H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 16H5V10h14v10zM7 12h5v5H7z',
  dl: 'M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z',
  swap: 'M16 17.01V10h-2v7.01h-3L15 21l4-3.99h-3zM9 3L5 6.99h3V14h2V6.99h3L9 3z',
  chev: 'M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z',
  apps: 'M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4zm6 0h4v-4h-4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z',
};
const icx = (n, s = 24, c = 'currentColor', extra = '') =>
  X[n] ? `<svg width="${s}" height="${s}" viewBox="0 0 24 24" style="flex:none;${extra}"><path d="${X[n]}" fill="${c}"/></svg>` : ic(n, s, c, extra);

// Grano: ruido muy suave para que el cristal no parezca plástico.
const NOISE = `url("data:image/svg+xml;utf8,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="140" height="140"><filter id="n"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" stitchTiles="stitch"/><feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 .55 0"/></filter><rect width="140" height="140" filter="url(#n)"/></svg>')}")`;

const CSS2 = `
/* --- Receta del cristal: desenfoque + borde con degradado + brillo + grano --- */
.g{position:absolute;isolation:isolate;border-radius:999px;
 background:linear-gradient(180deg,rgba(255,255,255,.14),rgba(255,255,255,.04) 55%,rgba(255,255,255,.07)),rgba(20,20,28,.20);
 backdrop-filter:blur(10px) saturate(1.9) brightness(1.06);
 box-shadow:0 12px 32px rgba(0,0,0,.38),0 2px 6px rgba(0,0,0,.22),inset 0 1px 1px rgba(255,255,255,.38),inset 0 -1px 1px rgba(255,255,255,.10),inset 0 0 22px rgba(255,255,255,.07)}
.g:before{content:'';position:absolute;inset:0;border-radius:inherit;padding:1px;pointer-events:none;
 background:linear-gradient(135deg,rgba(255,255,255,.65),rgba(255,255,255,.10) 28%,rgba(255,255,255,0) 50%,rgba(255,255,255,.10) 72%,rgba(255,255,255,.45));
 -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude}
.g:after{content:'';position:absolute;inset:0;border-radius:inherit;pointer-events:none;opacity:.9;
 background:radial-gradient(110% 80% at 18% -20%,rgba(255,255,255,.24),transparent 46%),${NOISE};background-size:auto,140px 140px;mix-blend-mode:screen;opacity:.55}
.g>*{position:relative;z-index:1}
.g.heavy{backdrop-filter:blur(22px) saturate(1.8) brightness(.9);background:linear-gradient(180deg,rgba(255,255,255,.12),rgba(255,255,255,.03) 40%),rgba(18,18,26,.42)}
/* Sin desenfoque (teles flojas, web, «Calidad del cristal: reducida»): mismo dibujo, fondo casi opaco */
.g.nob{backdrop-filter:none;background:linear-gradient(180deg,rgba(255,255,255,.10),rgba(255,255,255,.02) 55%),rgba(30,30,40,.90)}
.ink{color:var(--ink)}
.av{position:relative;flex:none;border-radius:50%;display:flex;align-items:center;justify-content:center;font-family:Outfit;font-weight:700;color:#0B0B0F;background:radial-gradient(circle at 30% 25%,#FFC9A8,#E0607E 75%)}
.av.ring:before{content:'';position:absolute;inset:-5px;border-radius:50%;background:conic-gradient(from 40deg,#4FD8FF,#8F6BFF,#FF5CCF,transparent 75%);-webkit-mask:radial-gradient(circle,transparent 62%,#000 63%)}
.dot{position:absolute;top:-1px;right:-3px;width:9px;height:9px;border-radius:50%;background:#FF5CCF;box-shadow:0 0 0 2px rgba(0,0,0,.45)}
.bdg{position:absolute;top:-4px;right:-5px;min-width:19px;height:19px;padding:0 5px;border-radius:10px;background:#FF5CCF;color:#0B0B0F;font:700 11px Rob;display:flex;align-items:center;justify-content:center;font-style:normal;box-shadow:0 0 0 2px rgba(0,0,0,.35)}
/* barra */
.bar{display:flex;align-items:center;padding:5px}
.tbi{flex:1;height:52px;border-radius:999px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;color:rgba(243,245,250,.78);font-size:10.5px;font-weight:500;position:relative}
.tbi.on{color:#fff;font-weight:700}
.pillon{background:rgba(255,255,255,.17);box-shadow:inset 0 1px 0 rgba(255,255,255,.38),0 4px 14px rgba(0,0,0,.18)}
.pillon:before{content:'';position:absolute;inset:0;border-radius:inherit;padding:1.2px;background:linear-gradient(120deg,rgba(79,216,255,.9),rgba(143,107,255,.55) 50%,rgba(255,92,207,.9));
 -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;opacity:.85}
.tbi.h{flex:none;flex-direction:row;gap:7px;padding:0 16px;font-size:14px}
.tbi.io{flex:none;width:50px}
.rb{display:flex;align-items:center;justify-content:center}
/* mini reproductor (accesorio) */
.acc{display:flex;align-items:center;gap:10px;padding:0 8px 0 7px}
.acc .t{font-weight:500;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.acc .a{font-size:12px;color:rgba(243,245,250,.7)}
.acc .pr{position:absolute;left:22px;right:22px;bottom:3px;height:2px;border-radius:2px;background:rgba(255,255,255,.14);z-index:2}
.acc .pr i{display:block;height:100%;width:34%;border-radius:2px;background:var(--grad)}
.gest{position:absolute;left:50%;bottom:8px;width:108px;margin-left:-54px;height:4px;border-radius:2px;background:rgba(255,255,255,.7);z-index:60}
/* contenido */
.lcard{flex:none;border-radius:12px;position:relative;overflow:hidden}
.lcard .pb{position:absolute;left:10px;right:10px;bottom:9px;height:4px;border-radius:2px;background:rgba(255,255,255,.3)}
.lcard .pb i{display:block;height:100%;border-radius:2px;background:#fff}
.lt{font-size:14px;font-weight:500;margin-top:8px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ls{font-size:12px;color:var(--mut);margin-top:2px}
.btnw{display:inline-flex;align-items:center;justify-content:center;gap:8px;height:46px;border-radius:999px;font-weight:700;font-size:15px;white-space:nowrap}
.btnw.p{background:var(--grad);color:#0B0B0F}
.edge{position:absolute;left:0;right:0;top:0;z-index:35;backdrop-filter:blur(14px) saturate(1.4);
 -webkit-mask:linear-gradient(180deg,#000 55%,transparent);background:linear-gradient(180deg,rgba(8,8,12,.55),rgba(8,8,12,.15) 70%,transparent)}
.lab{position:absolute;z-index:80;font:700 12px Rob;letter-spacing:.05em;text-transform:uppercase;color:#0B0B0F;background:#FFE27A;padding:4px 8px;border-radius:6px}
.note{position:absolute;z-index:80;font:500 12px Rob;color:#0B0B0F;background:#FFE27A;padding:6px 9px;border-radius:8px;max-width:230px;line-height:1.3;box-shadow:0 6px 18px rgba(0,0,0,.4)}
.prow{display:flex;align-items:center;gap:14px;height:52px;padding:0 16px;font-size:15px;font-weight:500}
.prow+.prow{box-shadow:inset 0 1px 0 rgba(255,255,255,.08)}
.prow .cnt{margin-left:auto;color:rgba(243,245,250,.6);font-size:13px;display:flex;align-items:center;gap:4px}
`;
const pg = (w, h, body, bg = '') => page(w, h, `<style>${CSS2}</style>${body}`, bg);
const PW = 393, PH = 852;

const avatar = (s, { ring = false, dot = false } = {}) =>
  `<div class="av${ring ? ' ring' : ''}" style="width:${s}px;height:${s}px;font-size:${Math.round(s * 0.45)}px">M${dot ? '<i class="dot"></i>' : ''}</div>`;

// Pósteres de colores vivos (para que el cristal se note).
const FILMS = [
  ['La casa del faro', 'T1:E9 · La bahía', ['#2FE0C0', '#1A3A8A'], 0.35],
  ['La última ola', '2020', ['#FF8AD8', '#3A2AA0'], 0.7],
  ['Niebla en el puerto', '2021', ['#5AB8FF', '#10204A'], 0.15],
  ['El jardín de invierno', '2022', ['#C07AFF', '#4A1060'], 0.5],
  ['Amigos para siempre', '2018', ['#5AF29A', '#0F4A3A'], 0],
  ['El último turno', '2023', ['#FF8A3A', '#7A1A22'], 0],
  ['Marea alta', '2025', ['#4A7AFF', '#2A0F6A'], 0],
  ['Verano en Cádiz', '2024', ['#FFD23A', '#C0306A'], 0],
  ['Los piratas del patio', '2025', ['#FF5A7A', '#3A1A6A'], 0],
];
function lcard([t, s, c, p], w, { h, txt = true } = {}) {
  h = h || Math.round(w * 9 / 16);
  return `<div style="width:${w}px;flex:none"><div class="lcard" style="width:${w}px;height:${h}px;background:radial-gradient(ellipse at 70% 25%,${c[0]} 0%,${c[1]} 78%)">
  <svg viewBox="0 0 100 56" preserveAspectRatio="none" style="position:absolute;inset:0;width:100%;height:100%"><circle cx="72" cy="18" r="9" fill="rgba(255,255,255,.35)"/><path d="M0 44 L18 30 L30 38 L48 22 L66 36 L80 28 L100 40 L100 56 L0 56Z" fill="rgba(0,0,0,.3)"/></svg>
  ${p ? `<div class="pb"><i style="width:${p * 100}%"></i></div>` : ''}</div>
  ${txt ? `<div class="lt">${t}</div><div class="ls">${s}</div>` : ''}</div>`;
}
const row = (title, items, top, { w = 200, h, txt = true } = {}) =>
  `<div style="position:absolute;left:16px;right:0;top:${top}px;z-index:3"><div class="o" style="font-size:21px;margin-bottom:10px">${title}</div>
  <div class="row" style="gap:12px;align-items:flex-start">${items.map((f) => lcard(f, w, { h, txt })).join('')}</div></div>`;

// --- Piezas de cristal ---
const TABS = [['homeO', 'home', 'Inicio'], ['exploreO', 'explore', 'Descubrir'], ['note', 'note', 'Música']];
const TABS5 = [['homeO', 'home', 'Inicio'], ['search', 'search', 'Buscar'], ['exploreO', 'explore', 'Descubrir'], ['note', 'note', 'Música']];
// variant 'A': icono + nombre pequeño en todas; 'B': solo icono salvo la activa.
function tabs(active, variant, withSearch) {
  const list = withSearch ? TABS5 : TABS;
  const one = ([o, f, l]) => {
    const on = active === l;
    if (variant === 'B') {
      return on ? `<div class="tbi h on pillon">${icx(f, 22, '#fff')}<span>${l}</span></div>` : `<div class="tbi io">${icx(o, 24)}</div>`;
    }
    return `<div class="tbi${on ? ' on pillon' : ''}">${icx(on ? f : o, 23, on ? '#fff' : 'currentColor')}<span>${l}</span></div>`;
  };
  const you = active === 'Tú';
  const youEl = variant === 'B' && !you
    ? `<div class="tbi io">${avatar(26, { dot: true })}</div>`
    : variant === 'B' ? `<div class="tbi h on pillon">${avatar(24, { dot: true })}<span>Tú</span></div>`
    : `<div class="tbi${you ? ' on pillon' : ''}">${avatar(24, { dot: true })}<span>Tú</span></div>`;
  return list.map(one).join('') + youEl;
}
// Barra completa abajo (con o sin Buscar aparte). bottom = distancia al borde.
function tabBar({ active = 'Inicio', variant = 'A', search = 'aparte', bottom = 24, nob = false } = {}) {
  const S = 62, side = 14, gap = 10;
  if (search === 'aparte') {
    const w = PW - side * 2 - S - gap;
    return `<div class="g bar${nob ? ' nob' : ''}" style="left:${side}px;bottom:${bottom}px;width:${w}px;height:${S}px;z-index:50;${variant === 'B' ? 'justify-content:space-around' : ''}">${tabs(active, variant, false)}</div>
    <div class="g rb${nob ? ' nob' : ''}" style="right:${side}px;bottom:${bottom}px;width:${S}px;height:${S}px;z-index:50">${icx('search', 26, active === 'Buscar' ? '#fff' : 'rgba(243,245,250,.9)')}</div>`;
  }
  return `<div class="g bar${nob ? ' nob' : ''}" style="left:${side}px;right:${side}px;bottom:${bottom}px;height:${S}px;z-index:50;${variant === 'B' ? 'justify-content:space-around' : ''}">${tabs(active, variant, true)}</div>`;
}
// El mini reproductor como accesorio de cristal, encima de la barra.
function accessory({ bottom = 96, left = 14, right = 14, h = 54, nob = false } = {}) {
  return `<div class="g acc${nob ? ' nob' : ''}" style="left:${left}px;right:${right}px;bottom:${bottom}px;height:${h}px;z-index:50">
    ${cover('brillo', h - 14, 10, 'box-shadow:none')}
    <div style="flex:1;min-width:0"><div class="t">Cielo de noche</div><div class="a">Clara Vega</div></div>
    ${ic('pause', 26, '#fff')}<div style="width:8px"></div>${ic('next', 26, '#fff', 'margin-right:6px')}
    <div class="pr"><i></i></div></div>`;
}
// Estado recogido: pestaña activa en un círculo · mini reproductor dentro · Buscar.
function compactBar({ active = 'home', bottom = 24 } = {}) {
  const S = 54;
  return `<div class="g rb" style="left:14px;bottom:${bottom}px;width:${S}px;height:${S}px;z-index:50">${icx(active, 25, '#fff')}</div>
  ${accessory({ bottom, left: 14 + S + 8, right: 14 + S + 8, h: S })}
  <div class="g rb" style="right:14px;bottom:${bottom}px;width:${S}px;height:${S}px;z-index:50">${icx('search', 25, '#fff')}</div>`;
}
// Cabecera grande de la página: título + enviar a la tele + bandeja.
function header(title, { top = 52, right = 'cast' } = {}) {
  const btn = (inner) => `<div class="g rb" style="position:relative;width:42px;height:42px">${inner}</div>`;
  const r = right === 'cast'
    ? `${btn(ic('cast', 19, '#fff'))}${btn(`${ic('inbox', 19, '#fff')}<i class="bdg">3</i>`)}`
    : btn(ic('gear', 20, '#fff'));
  return `<div class="row" style="position:absolute;top:${top}px;left:16px;right:16px;justify-content:space-between;z-index:40">
    <div class="o" style="font-size:34px;text-shadow:0 2px 16px rgba(0,0,0,.35)">${title}</div><div class="row" style="gap:10px">${r}</div></div>`;
}
// Cabecera recogida al bajar: borde suave desenfocado, título pequeño y botones de cristal.
function headerSmall(title) {
  const btn = (inner) => `<div class="g rb" style="position:relative;width:38px;height:38px">${inner}</div>`;
  return `<div class="edge" style="height:118px"></div>
  <div class="row" style="position:absolute;top:50px;left:16px;right:16px;justify-content:space-between;z-index:40">
    <div style="width:86px"></div><div class="o" style="font-size:17px">${title}</div>
    <div class="row" style="gap:10px">${btn(ic('cast', 17, '#fff'))}${btn(`${ic('inbox', 17, '#fff')}<i class="bdg" style="min-width:17px;height:17px">3</i>`)}</div></div>`;
}
const gest = '<i class="gest"></i>';
const fadeBottom = '<div style="position:absolute;left:0;right:0;bottom:0;height:150px;z-index:20;background:linear-gradient(0deg,rgba(6,6,10,.55),transparent)"></div>';

// --- Pantallas ---
function heroArt(h = 600) {
  return `<div style="position:absolute;left:0;right:0;top:0;height:${h}px;overflow:hidden;background:
   radial-gradient(ellipse 70% 45% at 75% 22%,rgba(255,170,90,.95),transparent 65%),
   radial-gradient(ellipse 80% 55% at 15% 30%,rgba(255,80,170,.75),transparent 70%),
   radial-gradient(ellipse 90% 60% at 60% 60%,rgba(60,200,200,.7),transparent 70%),
   linear-gradient(180deg,#3A1F7A 0%,#0E3A4A 70%,#0B0B0F 100%)">
   <div style="position:absolute;left:62%;top:15%;width:90px;height:90px;border-radius:50%;background:radial-gradient(circle,#FFF2C0,#FFB060 60%,transparent 72%)"></div>
   <svg viewBox="0 0 100 60" preserveAspectRatio="none" style="position:absolute;left:0;right:0;top:28%;width:100%;height:72%"><path d="M0 40 L14 30 L26 36 L42 20 L58 34 L72 22 L86 32 L100 26 L100 60 L0 60Z" fill="rgba(20,10,50,.55)"/><path d="M0 48 L20 40 L36 46 L54 36 L70 44 L100 38 L100 60 L0 60Z" fill="rgba(10,20,40,.7)"/>
   <rect x="88" y="14" width="2.4" height="14" fill="rgba(255,255,255,.75)"/><polygon points="87,14 91.6,14 89.2,10" fill="#FFE27A"/></svg>
   <div style="position:absolute;left:0;right:0;bottom:0;height:45%;background:linear-gradient(0deg,#0B0B0F,transparent)"></div></div>`;
}
function inicio({ variant = 'A', search = 'aparte', name = 'movil_cristal_inicio', notes = true } = {}) {
  const body = `${heroArt()}${status()}${header('Inicio')}
  <div style="position:absolute;left:16px;right:16px;top:300px;z-index:3">
    <div class="kick" style="color:#9FF5E2;font-size:11px">Ya está aquí lo que pediste</div>
    <div class="o" style="font-size:34px;line-height:1.05;margin-top:6px">La casa del faro</div>
    <div style="color:rgba(243,245,250,.75);font-size:13px;margin-top:6px">Serie · 2024 · Drama · 2 temporadas</div>
    <div class="row" style="gap:10px;margin-top:14px"><div class="btnw p" style="flex:1">${ic('play', 20, '#0B0B0F')}Ver T1:E9</div>
      <div class="g btnw" style="position:relative;flex:1">${ic('bookmark', 18, '#fff')}<span>Quiero verlo</span></div></div></div>
  ${row('Seguir viendo', FILMS.slice(0, 3), 490)}
  ${row('Novedades', FILMS.slice(4, 9), 690, { w: 120, h: 176, txt: false })}
  ${fadeBottom}${accessory()}${tabBar({ variant, search })}${gest}
  ${notes ? `<div class="note" style="left:16px;top:130px;max-width:300px">Abajo: el mini reproductor, una pieza de cristal encima de la barra. Debajo, la barra flotante con 4 pestañas y Buscar en un botón redondo aparte. Las filas pasan por debajo del cristal.</div>` : ''}`;
  return { name, w: PW, h: PH, html: pg(PW, PH, body) };
}
function inicioScroll() {
  const body = `<div style="position:absolute;inset:0;background:radial-gradient(ellipse 90% 40% at 70% 10%,rgba(143,107,255,.35),transparent 70%),#0B0B0F"></div>
  ${row('Seguir viendo', FILMS.slice(0, 3), 34)}
  ${row('Novedades', FILMS.slice(4, 9), 236, { w: 120, h: 176, txt: false })}
  ${row('Para los peques', [FILMS[8], FILMS[7], FILMS[1], FILMS[4]], 470, { w: 200 })}
  ${row('Música en casa', [FILMS[3], FILMS[6], FILMS[5]], 672, { w: 150, h: 150, txt: false })}
  ${status()}${headerSmall('Inicio')}${fadeBottom}${compactBar()}${gest}
  <div class="note" style="left:60px;top:118px;max-width:240px">Al bajar, el título grande se queda pequeño y el contenido pasa por debajo, desenfocado.</div>
  <div class="note" style="left:30px;top:705px;max-width:330px">Al bajar, la barra se recoge: la pestaña en la que estás (izquierda), el mini reproductor en medio y Buscar. Al subir o tocar, vuelve a abrirse.</div>`;
  return { name: 'movil_cristal_bajando', w: PW, h: PH, html: pg(PW, PH, body) };
}
function musica() {
  const body = `<div style="position:absolute;inset:0;background:radial-gradient(ellipse 100% 45% at 20% 0%,rgba(227,58,214,.55),transparent 70%),radial-gradient(ellipse 80% 40% at 100% 20%,rgba(79,216,255,.3),transparent 70%),#0B0B0F"></div>
  ${status()}${header('Música')}
  <div class="row" style="position:absolute;left:16px;top:112px;gap:8px;z-index:3">
    ${['Para ti', 'Álbumes', 'Artistas', 'Listas'].map((t, i) => `<div class="g" style="position:relative;height:34px;padding:0 15px;display:flex;align-items:center;font-size:14px;font-weight:${i ? 500 : 700};${i ? '' : 'background:rgba(255,255,255,.22)'}"><span>${t}</span></div>`).join('')}</div>
  <div style="position:absolute;left:16px;top:166px;z-index:3"><div class="o" style="font-size:21px;margin-bottom:10px">Tus mezclas</div>
    <div class="row" style="gap:12px;align-items:flex-start">${mixCard(1, 170, 'brillo', ['Clara Vega', 'Lola Brisa'])}${mixCard(2, 170, 'marea', ['DJ Marea', 'Sal y Limón'])}${mixCard(3, 170, 'limon', ['Rumba Norte', 'Nube Roja'])}</div></div>
  <div style="position:absolute;left:16px;top:432px;z-index:3"><div class="o" style="font-size:21px;margin-bottom:10px">Escuchado hace poco</div>
    <div class="row" style="gap:12px;align-items:flex-start">${['verano', 'norte', 'luna', 'orilla'].map((a) => card(a, 140)).join('')}</div></div>
  <div style="position:absolute;left:16px;top:652px;z-index:3"><div class="o" style="font-size:21px;margin-bottom:10px">Novedades en casa</div>
    <div class="row" style="gap:12px;align-items:flex-start">${['bailar', 'primavera', 'faroles', 'sal'].map((a) => card(a, 140)).join('')}</div></div>
  ${fadeBottom}${accessory()}${tabBar({ active: 'Música' })}${gest}`;
  return { name: 'movil_cristal_musica', w: PW, h: PH, html: pg(PW, PH, body) };
}
function tu() {
  const r = (i, l, c = '') => `<div class="prow">${icx(i, 21, 'rgba(243,245,250,.9)')}<span>${l}</span><span class="cnt">${c}${icx('chev', 18, 'rgba(243,245,250,.45)')}</span></div>`;
  const qt = (icon, col, t, s) => `<div class="g" style="position:relative;flex:1;border-radius:20px;padding:13px;display:flex;flex-direction:column;gap:10px;font-size:14px;font-weight:500">${icx(icon, 22, col)}<div>${t}<div style="font-size:12px;color:rgba(243,245,250,.65);font-weight:400;margin-top:2px">${s}</div></div></div>`;
  const body = `<div style="position:absolute;inset:0;background:
     radial-gradient(ellipse 80% 30% at 20% 4%,rgba(255,140,120,.55),transparent 70%),
     radial-gradient(ellipse 70% 35% at 100% 30%,rgba(143,107,255,.45),transparent 70%),
     radial-gradient(ellipse 90% 30% at 0% 75%,rgba(79,216,255,.28),transparent 70%),#0B0B0F"></div>
  ${status()}${header('Tú', { right: 'gear' })}
  <div style="position:absolute;left:16px;right:16px;top:112px;z-index:3">
    <div class="row" style="gap:16px">${avatar(66, { ring: true })}<div style="flex:1"><div class="o" style="font-size:24px">Marta</div><div style="color:rgba(243,245,250,.7);font-size:13px;margin-top:3px">Perfil de la familia</div></div>
      <div class="g" style="position:relative;height:36px;padding:0 14px;display:flex;align-items:center;gap:6px;font-size:13px;font-weight:500">${icx('swap', 16, '#fff')}<span>Cambiar</span></div></div>
    <div class="g" style="position:relative;margin-top:20px;border-radius:22px;padding:14px;display:flex;align-items:center;gap:12px;background:linear-gradient(120deg,rgba(79,216,255,.22),rgba(143,107,255,.20) 55%,rgba(255,92,207,.22)),rgba(20,20,28,.2)">
      <div class="rb" style="width:42px;height:42px;border-radius:50%;background:rgba(255,255,255,.16)">${ic('inbox', 20, '#fff')}</div>
      <div style="flex:1"><div style="font-weight:700;font-size:16px">Mis peticiones</div><div style="color:rgba(243,245,250,.75);font-size:13px;margin-top:2px">3 novedades · 1 descargándose</div></div>
      <i class="bdg" style="position:static">3</i></div>
    <div class="row" style="gap:10px;margin-top:12px;align-items:stretch">
      ${qt('bookmark', '#fff', 'Quiero verlo', '12 títulos')}${qt('heart', '#FF5CCF', 'Mis favoritos', '2 novedades')}${qt('dl', '#fff', 'Descargas', '3 en el móvil')}</div>
    <div style="margin:20px 0 8px 4px;color:rgba(243,245,250,.6);font-size:12px;font-weight:700;letter-spacing:.08em">EN CASA</div>
    <div class="g" style="position:relative;border-radius:22px;display:block">
      ${r('movie', 'Bibliotecas', '4')}${r('masks', 'Géneros')}${r('tv', 'TV en directo')}${r('cal', 'Calendario', '2 esta semana')}</div>
  </div>
  ${fadeBottom}${accessory()}${tabBar({ active: 'Tú' })}${gest}`;
  return { name: 'movil_cristal_tu', w: PW, h: PH, html: pg(PW, PH, body) };
}
function hoja() {
  const base = inicio({ notes: false }).html.replace(/<\/body>/, '');
  const tile = (i, l, s = '') => `<div class="g" style="position:relative;border-radius:20px;height:86px;display:flex;flex-direction:column;justify-content:center;align-items:center;gap:6px;font-size:13px;font-weight:500;box-shadow:inset 0 1px 1px rgba(255,255,255,.3)">${icx(i, 24, '#fff')}<span>${l}</span>${s ? `<span style="position:absolute;top:8px;right:10px" class="bdg">${s}</span>` : ''}</div>`;
  const sheet = `<div style="position:absolute;inset:0;z-index:70;background:rgba(0,0,0,.38)"></div>
  <div class="g heavy" style="left:8px;right:8px;bottom:8px;height:418px;border-radius:36px;z-index:75;display:block;padding:10px 18px 0">
    <div style="width:38px;height:5px;border-radius:3px;background:rgba(255,255,255,.45);margin:0 auto 10px"></div>
    <div class="row" style="justify-content:space-between"><div class="o" style="font-size:24px">Más</div>
      <div class="g rb" style="position:relative;width:36px;height:36px">${ic('close', 18, '#fff')}</div></div>
    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-top:16px">
      ${tile('movie', 'Bibliotecas')}${tile('masks', 'Géneros')}${tile('tv', 'TV en directo')}${tile('cal', 'Calendario')}${tile('bookmark', 'Quiero verlo')}${tile('inbox', 'Peticiones', '3')}</div>
    <div class="g" style="position:relative;border-radius:20px;margin-top:14px;display:block">
      <div class="prow">${icx('swap', 21, '#fff')}<span>Cambiar de persona</span><span class="cnt">${icx('chev', 18, 'rgba(243,245,250,.45)')}</span></div>
      <div class="prow">${ic('gear', 21, '#fff')}<span>Ajustes</span><span class="cnt">${icx('chev', 18, 'rgba(243,245,250,.45)')}</span></div></div>
  </div>${gest}
  <div class="note" style="left:20px;top:250px;max-width:330px">Hoja de cristal, separada de los bordes y con las esquinas del teléfono. Se abre manteniendo pulsado «Tú» (atajo) y la misma pieza sirve para las demás hojas (acciones de un título, elegir tele…).</div></body>`;
  return { name: 'movil_cristal_hoja', w: PW, h: PH, html: base + sheet };
}
// Hoja de variantes: las cuatro barras + recogida + sin desenfoque, sobre fondo de colores.
function variantes() {
  const W = 393 * 2 + 30, H = 820;
  const bg = `<div style="position:absolute;inset:0;background:
    radial-gradient(ellipse 30% 40% at 10% 20%,#FF5CCF,transparent 70%),radial-gradient(ellipse 30% 40% at 40% 70%,#4FD8FF,transparent 70%),
    radial-gradient(ellipse 30% 40% at 75% 25%,#FFB060,transparent 70%),radial-gradient(ellipse 30% 40% at 95% 80%,#8F6BFF,transparent 70%),#151520"></div>
    <svg style="position:absolute;inset:0" width="${W}" height="${H}">${Array.from({ length: 22 }, (_, i) => `<rect x="${(i * 97) % W}" y="${(i * 173) % H}" width="70" height="100" rx="10" fill="hsla(${i * 37},90%,60%,.55)"/>`).join('')}</svg>`;
  const cell = (x, y, title, inner, ih = 100) => `<div style="position:absolute;left:${x}px;top:${y}px;width:393px;height:140px;overflow:visible">
     <div class="lab" style="left:14px;top:0;position:absolute">${title}</div>
     <div style="position:absolute;left:0;top:30px;width:393px;height:${ih}px">${inner}</div></div>`;
  const wrap = (s) => s.replace(/bottom:24px/g, 'bottom:14px');
  const body = `${bg}
   ${cell(10, 20, 'A · todas con nombre · Buscar aparte', wrap(tabBar({ variant: 'A' })))}
   ${cell(413, 20, 'A · todas con nombre · Buscar dentro', wrap(tabBar({ variant: 'A', search: 'dentro' })))}
   ${cell(10, 170, 'B · solo icono · Buscar aparte', wrap(tabBar({ variant: 'B' })))}
   ${cell(413, 170, 'B · solo icono · Buscar dentro', wrap(tabBar({ variant: 'B', search: 'dentro', active: 'Descubrir' })))}
   ${cell(10, 320, 'Abierta · mini reproductor encima', `${accessory({ bottom: 82 })}${tabBar({ bottom: 14 })}`, 160)}
   ${cell(413, 320, 'Recogida al bajar', compactBar({ bottom: 14 }))}
   ${cell(10, 530, 'Sin desenfoque (teles flojas, web, «reducida»)', wrap(tabBar({ nob: true })))}
   ${cell(413, 530, 'Sin desenfoque · recogida', compactBar({ bottom: 14 }).replace(/class="g /g, 'class="g nob '))}
   <div class="note" style="left:20px;top:690px;max-width:770px;font-size:13px">Recomendada: <b>A con Buscar aparte</b> (arriba a la izquierda). Los nombres se leen siempre (la familia no adivina iconos) y Buscar queda a mano del pulgar, como en las apps de Apple. En la versión sin desenfoque la barra se dibuja igual (borde, brillo y grano), pero con fondo casi opaco: cuesta lo mismo que la barra de hoy.</div>`;
  return { name: 'movil_cristal_barras', w: W, h: H, html: pg(W, H, body) };
}
function desktop() {
  const W = 1440, H = 900;
  const tabsD = ['Inicio', 'Descubrir', 'Música', 'Quiero verlo', 'Bibliotecas', 'TV en directo', 'Más ▾'].map((l, i) =>
    `<div class="${i === 0 ? 'pillon' : ''}" style="position:relative;height:40px;padding:0 16px;border-radius:999px;display:flex;align-items:center;font-size:15px;font-weight:${i === 0 ? 700 : 500};color:${i === 0 ? '#fff' : 'rgba(243,245,250,.8)'}">${l}</div>`).join('');
  const body = `${heroArt(900).replace(/<rect x="88"[^>]*\/><polygon[^>]*\/>/, '')}
  <div class="row" style="position:absolute;top:22px;left:40px;right:40px;justify-content:space-between;z-index:40">
    <div class="o" style="font-size:26px">kOS <span style="font-weight:300;font-size:14px;letter-spacing:.2em;background:var(--grad);-webkit-background-clip:text;color:transparent">TV</span></div>
    <div class="g bar" style="position:relative;padding:5px;gap:2px">${tabsD}</div>
    <div class="row" style="gap:10px"><div class="g" style="position:relative;width:220px;height:44px;display:flex;align-items:center;gap:10px;padding:0 16px;color:rgba(243,245,250,.75);font-size:15px">${ic('search', 20, '#fff')}<span>Buscar</span></div>
      <div class="g rb" style="position:relative;width:44px;height:44px">${ic('inbox', 19, '#fff')}<i class="bdg">3</i></div>${avatar(40, { ring: true })}</div></div>
  <div style="position:absolute;left:56px;top:300px;width:620px;z-index:3">
    <div class="kick" style="color:#9FF5E2">Ya está aquí lo que pediste</div>
    <div class="o" style="font-size:64px;line-height:1.02;margin-top:10px">La casa del faro</div>
    <div class="row" style="gap:14px;margin-top:24px"><div class="btnw p" style="padding:0 26px">${ic('play', 22, '#0B0B0F')}Ver T1:E9</div><div class="g btnw" style="position:relative;padding:0 26px">${ic('bookmark', 18, '#fff')}<span>Quiero verlo</span></div></div></div>
  ${row('Seguir viendo', FILMS.slice(0, 6), 620, { w: 270 }).replace('left:16px', 'left:56px')}
  ${accessory({ bottom: 24, left: 1040, right: 28, h: 60 })}
  <div class="note" style="left:470px;top:84px;max-width:500px">Web en el ordenador: la misma barra de arriba (tele A), ahora como cápsula de cristal flotante; el mini reproductor, cristal abajo a la derecha. En ventana estrecha o en el iPhone, la barra de abajo del móvil.</div>`;
  return { name: 'ordenador_cristal', w: W, h: H, html: pg(W, H, body) };
}
function cmp() {
  const iw = 393, ih = 852, W = iw * 2 + 60, H = ih + 80;
  const body = `<div style="display:flex;gap:20px;padding:20px;background:#1a1a1f;height:100%">
    ${[[path.join(PREV, 'movil_inicio.png'), 'Propuesta anterior'], [path.join(OUT, 'movil_cristal_inicio.png'), 'Cristal (nueva)']].map(([f, t]) => `<div><div class="o" style="font-size:24px;margin-bottom:10px">${t}</div><img src="file://${f}?v=${Date.now()}" style="width:${iw}px;height:${ih}px;border-radius:14px;display:block"></div>`).join('')}</div>`;
  return { name: 'comparar_cristal', w: W, h: H, html: page(W, H, body) };
}

(async () => {
  const browser = await chromium.launch();
  const shoot = async (s, dsf = 3) => {
    const p = await browser.newPage({ viewport: { width: s.w, height: s.h }, deviceScaleFactor: dsf });
    const f = path.join(OUT, 'html', s.name + '.html');
    fs.writeFileSync(f, s.html);
    await p.goto('file://' + f);
    await p.evaluate(() => document.fonts.ready);
    await p.waitForTimeout(200);
    await p.screenshot({ path: path.join(OUT, s.name + '.png') });
    await p.close();
    console.log(s.name);
  };
  for (const s of [inicio(), inicioScroll(), musica(), tu(), hoja(), inicio({ variant: 'B', name: 'movil_cristal_B', notes: false })]) await shoot(s);
  await shoot(variantes(), 2);
  await shoot(desktop(), 1.5);
  await shoot(cmp(), 2);
  await browser.close();
})();
