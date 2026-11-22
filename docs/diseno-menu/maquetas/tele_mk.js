// Maquetas de la propuesta de menú de kOS TV (tele, móvil y ordenador).
// Reutiliza las piezas de las maquetas de Música (solo se leen).
const L = require('/home/user/kos-TV/docs/diseno-musica/maquetas/lib.js');
const { ic, cover, playBtn, capsule, status, page } = L;
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const OUT = __dirname;

// Iconos que faltan en la librería de Música.
const X = {
  apps: 'M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4zm6 0h4v-4h-4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z',
  cal: 'M19 4h-1V2h-2v2H8V2H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 16H5V10h14v10zM7 12h5v5H7z',
  dl: 'M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z',
  swap: 'M16 17.01V10h-2v7.01h-3L15 21l4-3.99h-3zM9 3L5 6.99h3V14h2V6.99h3L9 3z',
  chev: 'M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z',
  homeO: 'M12 5.69l5 4.5V18h-2v-6H9v6H7v-7.81l5-4.5M12 3L2 12h3v8h6v-6h2v6h6v-8h3L12 3z',
  bell: 'M12 22c1.1 0 2-.9 2-2h-4a2 2 0 0 0 2 2zm6-6v-5c0-3.07-1.64-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.63 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z',
  kbd: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z',
};
const icx = (n, s = 24, c = 'currentColor', extra = '') =>
  X[n] ? `<svg width="${s}" height="${s}" viewBox="0 0 24 24" style="flex:none;${extra}"><path d="${X[n]}" fill="${c}"/></svg>` : ic(n, s, c, extra);

// Destinos. Principales a la vista; el resto en «Más» o en el perfil.
const MAIN = [
  ['home', 'Inicio'], ['explore', 'Descubrir'], ['note', 'Música'], ['bookmark', 'Quiero verlo'],
  ['movie', 'Bibliotecas'], ['tv', 'TV en directo'],
];
const MORE = [['masks', 'Géneros'], ['cal', 'Calendario'], ['apps', 'Aplicaciones']];
// Lo de hoy, en su orden.
const NOW = ['home', 'search', 'explore', 'masks', 'bookmark', 'note', 'tv', 'movie', 'gear'];

const CSS2 = `
.scrim{position:absolute;left:0;right:0;top:0;height:150px;background:linear-gradient(180deg,rgba(0,0,0,.72),rgba(0,0,0,.35) 55%,transparent);z-index:9}
.av{position:relative;flex:none;border-radius:50%;display:flex;align-items:center;justify-content:center;font-family:Outfit;font-weight:700;color:#0B0B0F;
 background:radial-gradient(circle at 30% 25%,#FFC9A8,#E0607E 75%)}
.av.ring:before{content:'';position:absolute;inset:-5px;border-radius:50%;background:conic-gradient(from 40deg,#4FD8FF,#8F6BFF,#FF5CCF,transparent 75%);
 -webkit-mask:radial-gradient(circle,transparent 62%,#000 63%);mask:radial-gradient(circle,transparent 62%,#000 63%)}
.bdg{position:absolute;top:-4px;right:-6px;min-width:20px;height:20px;padding:0 5px;border-radius:10px;background:#FF5CCF;color:#0B0B0F;font:700 12px Rob;display:flex;align-items:center;justify-content:center;box-shadow:0 0 0 2px #0B0B0F}
.tabs{display:flex;align-items:center;gap:4px}
.tab{position:relative;height:44px;padding:0 18px;border-radius:999px;display:flex;align-items:center;gap:9px;font-size:18px;font-weight:500;color:rgba(243,245,250,.62);white-space:nowrap}
.tab.on{color:var(--ink);font-weight:700}
.tab.on:after{content:'';position:absolute;left:50%;bottom:2px;width:22px;margin-left:-11px;height:3px;border-radius:2px;background:var(--grad)}
.tab.f{background:var(--ink);color:#0B0B0F;font-weight:700;transform:scale(1.06);box-shadow:inset 0 1px 0 rgba(255,255,255,.9),0 10px 30px rgba(0,0,0,.55)}
.tab.f:after{display:none}.tab.f svg path{fill:#0B0B0F}
.tab.ico{width:44px;padding:0;justify-content:center}
.glassbar{padding:5px;border-radius:999px;background:rgba(36,36,44,.62);backdrop-filter:blur(24px) saturate(1.3);box-shadow:inset 0 0 0 1px rgba(255,255,255,.08),0 10px 30px rgba(0,0,0,.35)}
.clk{font-size:22px;font-weight:500;font-variant-numeric:tabular-nums}
.hero{position:absolute;inset:0;overflow:hidden}
.btnw{display:inline-flex;align-items:center;gap:10px;height:48px;padding:0 24px;border-radius:999px;font-weight:700;font-size:17px;white-space:nowrap}
.btnw.g{background:rgba(255,255,255,.14);color:var(--ink)}
.btnw.p{background:var(--grad);color:#0B0B0F}
.lcard{flex:none;border-radius:10px;position:relative;overflow:hidden;box-shadow:0 8px 20px rgba(0,0,0,.4)}
.lcard .pb{position:absolute;left:10px;right:10px;bottom:10px;height:4px;border-radius:2px;background:rgba(255,255,255,.25)}
.lcard .pb i{display:block;height:100%;border-radius:2px;background:var(--ink)}
.lt{font-size:15px;font-weight:500;margin-top:10px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ls{font-size:13px;color:var(--mut);margin-top:3px}
.fl{box-shadow:0 0 0 3px #0B0B0F,0 0 0 6px var(--ink),0 18px 40px rgba(0,0,0,.7);transform:scale(1.07)}
.menu{position:absolute;z-index:30;border-radius:18px;background:rgba(30,30,38,.94);backdrop-filter:blur(30px);box-shadow:inset 0 0 0 1px rgba(255,255,255,.08),0 24px 60px rgba(0,0,0,.6);padding:8px}
.mi{display:flex;align-items:center;gap:14px;height:48px;padding:0 16px;border-radius:12px;font-size:17px;font-weight:500;color:rgba(243,245,250,.85)}
.mi .cnt{margin-left:auto;font-size:14px;color:var(--mut)}
.mi.f{background:var(--ink);color:#0B0B0F;font-weight:700}.mi.f svg path{fill:#0B0B0F}.mi.f .cnt{color:#333}
.sep{height:1px;background:rgba(255,255,255,.08);margin:6px 10px}
.side{position:absolute;left:0;top:0;bottom:0;z-index:20;display:flex;flex-direction:column;padding:28px 0 24px}
.sitem{display:flex;align-items:center;gap:16px;height:46px;margin:2px 14px;padding:0 13px;border-radius:999px;color:rgba(243,245,250,.6);font-size:18px;font-weight:500;white-space:nowrap;position:relative}
.sitem.on{color:var(--ink)}
.sitem.on:before{content:'';position:absolute;left:-14px;top:13px;width:3px;height:20px;border-radius:2px;background:var(--grad)}
.sitem.f{background:var(--ink);color:#0B0B0F;font-weight:700}.sitem.f svg path{fill:#0B0B0F}
.lab{position:absolute;z-index:60;font:700 13px Rob;letter-spacing:.06em;text-transform:uppercase;color:#0B0B0F;background:#FFE27A;padding:5px 10px;border-radius:6px}
.note{position:absolute;z-index:60;font:500 13px Rob;color:#0B0B0F;background:#FFE27A;padding:6px 10px;border-radius:8px;max-width:300px;line-height:1.3;box-shadow:0 6px 18px rgba(0,0,0,.4)}
/* móvil */
.tabbar{position:absolute;left:0;right:0;bottom:0;z-index:30;background:rgba(14,14,19,.9);backdrop-filter:blur(26px) saturate(1.3);box-shadow:inset 0 1px 0 rgba(255,255,255,.07)}
.tabrow{display:flex;justify-content:space-around;height:64px;align-items:center;padding:0 6px}
.bt{flex:1;display:flex;flex-direction:column;align-items:center;gap:4px;color:rgba(243,245,250,.55);font-size:12px;font-weight:500}
.bt .ind{width:56px;height:30px;border-radius:15px;display:flex;align-items:center;justify-content:center;position:relative}
.bt.on{color:var(--ink);font-weight:700}
.bt.on .ind{background:rgba(255,255,255,.14)}
.bt.on .ind:after{content:'';position:absolute;bottom:-1px;left:50%;margin-left:-8px;width:16px;height:3px;border-radius:2px;background:var(--grad)}
.gest{height:24px;display:flex;justify-content:center;align-items:center}.gest i{width:108px;height:4px;border-radius:2px;background:rgba(255,255,255,.5)}
.rbtn2{width:40px;height:40px;border-radius:50%;background:rgba(255,255,255,.1);display:flex;align-items:center;justify-content:center;position:relative;flex:none}
.prow{display:flex;align-items:center;gap:14px;height:54px;padding:0 4px;font-size:16px;font-weight:500;border-bottom:1px solid rgba(255,255,255,.06)}
.prow .cnt{margin-left:auto;color:var(--mut);font-size:14px;display:flex;align-items:center;gap:6px}
.qt{flex:1;border-radius:14px;background:rgba(255,255,255,.07);padding:14px;display:flex;flex-direction:column;gap:10px;font-size:14px;font-weight:500}
.qt b{display:block;font-size:12px;color:var(--mut);font-weight:400;margin-top:2px}
`;
const pg = (w, h, body, bg = '') => page(w, h, `<style>${CSS2}</style>${body}`, bg);

// --- Contenido de mentira (como los datos falsos de la app) ---
const HERO = { t: 'La casa del faro', m: 'Serie · 2024 · Drama · 2 temporadas', d: 'Una familia hereda un faro abandonado en una isla sin cobertura y, con él, los secretos de todo el pueblo.' };
const FILMS = [
  ['La casa del faro', 'T1:E9 · La bahía', ['#1E7A6E', '#0B2A3A'], 0.35],
  ['La última ola', '2020', ['#E8B6D8', '#252A6A'], 0.7],
  ['Niebla en el puerto', '2021', ['#2E4A5A', '#0E1620'], 0.15],
  ['El jardín de invierno', '2022', ['#7A4A9A', '#2A1030'], 0.5],
  ['Amigos para siempre', '2018', ['#2F8F7A', '#0F2A2A'], 0],
  ['El último turno', '2023', ['#E2643A', '#4A1A12'], 0],
  ['Marea alta', '2025', ['#3A6AF2', '#140F3A'], 0],
];
function lcard([t, s, c, p], w, { focus = false, h } = {}) {
  h = h || Math.round(w * 9 / 16);
  return `<div style="width:${w}px;flex:none"><div class="lcard${focus ? ' fl' : ''}" style="width:${w}px;height:${h}px;background:radial-gradient(ellipse at 70% 30%,${c[0]} 0%,${c[1]} 70%)">
  <svg viewBox="0 0 100 56" preserveAspectRatio="none" style="position:absolute;inset:0;width:100%;height:100%"><path d="M0 44 L18 30 L30 38 L48 22 L66 36 L80 28 L100 40 L100 56 L0 56Z" fill="rgba(0,0,0,.28)"/></svg>
  ${p ? `<div class="pb"><i style="width:${p * 100}%"></i></div>` : ''}</div>
  <div class="lt">${t}</div><div class="ls">${s}</div></div>`;
}
const heroBg = (k = 1) => `<div class="hero" style="background:radial-gradient(ellipse 60% 70% at 72% 28%,rgba(60,200,170,${0.55 * k}) 0%,transparent 70%),radial-gradient(ellipse 50% 60% at 95% 10%,rgba(143,107,255,${0.35 * k}),transparent 70%),linear-gradient(180deg,#0E2A2E 0%,#0B0B0F 78%)">
  <svg viewBox="0 0 100 60" preserveAspectRatio="none" style="position:absolute;left:0;right:0;top:20%;width:100%;height:60%"><path d="M0 46 L14 34 L26 40 L42 24 L58 38 L72 26 L86 36 L100 30 L100 60 L0 60Z" fill="rgba(4,14,18,.55)"/></svg>
  <div style="position:absolute;inset:0;background:linear-gradient(90deg,rgba(11,11,15,.92) 0%,rgba(11,11,15,.5) 45%,transparent 75%)"></div>
  <div style="position:absolute;left:0;right:0;bottom:0;height:45%;background:linear-gradient(0deg,#0B0B0F,transparent)"></div></div>`;

// Inicio de la tele: el banner y la primera fila (top = dónde empieza el contenido).
function tvHome({ top = 150, focusCard = -1, dim = 0, left = 64 } = {}) {
  return `${heroBg()}
  <div style="position:absolute;left:${left}px;top:${top}px;width:560px;z-index:2">
    <div class="kick" style="color:#7FE3D0">Ya está aquí lo que pediste</div>
    <div class="o" style="font-size:54px;line-height:1.02;margin-top:10px">${HERO.t}</div>
    <div style="color:var(--mut);font-size:16px;margin-top:12px">${HERO.m}</div>
    <div style="font-size:16px;line-height:1.45;margin-top:12px;color:rgba(243,245,250,.82)">${HERO.d}</div>
    <div class="row" style="gap:14px;margin-top:22px"><div class="btnw p">${ic('play', 24, '#0B0B0F')}Ver T1:E9</div><div class="btnw g">${ic('bookmark', 20)}Quiero verlo</div></div>
  </div>
  <div style="position:absolute;left:${left}px;top:${top + 330}px;right:0;z-index:2">
    <div class="o" style="font-size:24px;margin-bottom:14px">Seguir viendo</div>
    <div class="row" style="gap:22px;align-items:flex-start">${FILMS.slice(0, 5).map((f, i) => lcard(f, 250, { focus: i === focusCard })).join('')}</div>
  </div>
  ${dim ? `<div style="position:absolute;inset:0;background:rgba(0,0,0,${dim});z-index:8"></div>` : ''}`;
}
function tvRows({ left = 64, top = 70 } = {}) {
  return `<div class="hero" style="background:radial-gradient(ellipse 60% 50% at 80% 0%,rgba(60,200,170,.18),transparent 70%),#0B0B0F"></div>
  <div style="position:absolute;left:${left}px;top:${top}px;right:0;z-index:2">
    <div class="o" style="font-size:24px;margin-bottom:14px">Seguir viendo</div>
    <div class="row" style="gap:22px;align-items:flex-start">${FILMS.slice(0, 5).map((f) => lcard(f, 250)).join('')}</div>
    <div class="o" style="font-size:24px;margin:34px 0 14px">Quiero verlo</div>
    <div class="row" style="gap:22px;align-items:flex-start">${FILMS.slice(2, 7).map((f, i) => lcard([f[0], f[1], f[2], 0], 250, { focus: i === 1 })).join('')}</div>
    <div class="o" style="font-size:24px;margin:34px 0 14px">Nuevo en casa</div>
    <div class="row" style="gap:22px;align-items:flex-start">${FILMS.slice(1, 6).map((f) => lcard([f[0], f[1], f[2], 0], 250)).join('')}</div>
  </div>`;
}
const avatar = (s, { badge = 0, ring = false, letter = 'M', focus = false, dot = false } = {}) =>
  `<div class="av${ring ? ' ring' : ''}" style="width:${s}px;height:${s}px;font-size:${Math.round(s * 0.45)}px;${focus ? 'box-shadow:0 0 0 3px #0B0B0F,0 0 0 6px #F3F5FA;transform:scale(1.08)' : ''}">${letter}${badge ? `<i class="bdg" style="font-style:normal">${badge}</i>` : ''}${dot ? '<i style="position:absolute;top:-1px;right:-3px;width:10px;height:10px;border-radius:50%;background:#FF5CCF;box-shadow:0 0 0 2px #0E0E13"></i>' : ''}</div>`;

// --- Tele · hoy (reproducido para comparar) ---
function tvNow() {
  const body = `${tvHome({ focusCard: 0 })}<div class="scrim"></div>
  <div style="position:absolute;top:0;left:0;right:0;height:96px;display:flex;align-items:center;justify-content:space-between;padding:0 48px;z-index:10">
    <div class="row" style="gap:12px;width:200px"><div class="avatar" style="width:42px;height:42px">M</div><div class="tb">${ic('inbox', 20)}</div><div class="tb">${ic('heart', 20, '#FF5CCF')}<i class="badge">2</i></div></div>
    <div class="navpill">${NOW.map((n) => `<div class="ni${n === 'home' ? ' on' : ''}">${ic(n, 22)}</div>`).join('')}</div>
    <div class="clock" style="width:200px">21:14</div></div>`;
  return { name: 'tele_ahora', w: 1280, h: 720, html: pg(1280, 720, body) };
}

// --- Tele · A: pestañas con nombre ---
function barA({ focus = null, active = 'Inicio', badge = 3, ring = true, glass = false, avFocus = false } = {}) {
  const items = [['search', '', 'ico'], ...MAIN.map(([i, l]) => [i, l, '']), ['more', '', 'ico']];
  const tabs = items.map(([i, l, k]) => {
    const key = l || i;
    const cls = `tab${k ? ' ico' : ''}${active === key ? ' on' : ''}${focus === key ? ' f' : ''}`;
    return `<div class="${cls}">${k ? ic(i, 24) : l}</div>`;
  }).join('');
  return `<div class="scrim" style="${glass ? 'height:190px;background:linear-gradient(180deg,rgba(0,0,0,.85),rgba(0,0,0,.4) 60%,transparent)' : ''}"></div>
  <div style="position:absolute;top:0;left:0;right:0;height:96px;display:flex;align-items:center;padding:0 56px;z-index:10;gap:22px">
    ${avatar(44, { badge, ring, focus: avFocus })}
    <div class="tabs${glass ? ' glassbar' : ''}" style="${glass ? '' : 'padding:5px'}">${tabs}</div>
    <div style="flex:1"></div><div class="clk">21:14</div></div>`;
}
function tvA_rest() {
  const body = `${tvHome({ top: 150, focusCard: 0 })}${barA()}`;
  return { name: 'tele_A_reposo', w: 1280, h: 720, html: pg(1280, 720, body) };
}
function tvA_focus() {
  const body = `${tvHome({ top: 150, dim: 0.25 })}${barA({ focus: 'Música', glass: true })}
  <div class="note" style="left:520px;top:110px">Con el foco en el menú, el cristal se enciende y la cápsula blanca va al botón. Quedarse 0,7 s abre Música detrás.</div>`;
  return { name: 'tele_A_foco', w: 1280, h: 720, html: pg(1280, 720, body) };
}
function tvA_more() {
  const body = `${tvHome({ top: 150, dim: 0.45 })}${barA({ focus: 'more', glass: true })}
  <div class="menu" style="left:880px;top:84px;width:300px">
    <div class="mi f">${icx('masks', 22)}Géneros</div><div class="mi">${icx('cal', 22)}Calendario</div><div class="mi">${icx('apps', 22)}Aplicaciones<span class="cnt">solo tele</span></div>
  </div>`;
  return { name: 'tele_A_mas', w: 1280, h: 720, html: pg(1280, 720, body) };
}
function tvProfile() {
  const body = `${tvHome({ top: 150, dim: 0.45 })}${barA({ glass: true, avFocus: true })}
  <div class="menu" style="left:48px;top:96px;width:340px">
    <div class="row" style="gap:14px;padding:10px 12px 14px">${avatar(52, {})}<div><div class="o" style="font-size:22px">Marta</div><div style="color:var(--mut);font-size:14px;margin-top:2px">Perfil de la familia</div></div></div>
    <div class="mi f">${ic('inbox', 22)}Mis peticiones<span class="cnt">3 novedades</span></div>
    <div class="mi">${ic('heart', 22, '#F3F5FA')}Mis favoritos</div>
    <div class="sep"></div>
    <div class="mi">${icx('swap', 22)}Cambiar de persona</div>
    <div class="mi">${ic('gear', 22)}Ajustes</div>
  </div>
  <div class="note" style="left:410px;top:140px">El avatar es «Tú»: el número de la bandeja va en el avatar y el anillo gira si hay algo en marcha.</div>`;
  return { name: 'tele_A_perfil', w: 1280, h: 720, html: pg(1280, 720, body) };
}
function tvA_compact() {
  const body = `${tvRows({ top: 84 })}
  <div style="position:absolute;top:0;left:0;right:0;height:70px;background:linear-gradient(180deg,rgba(0,0,0,.7),transparent);z-index:9"></div>
  <div style="position:absolute;top:22px;left:56px;z-index:10" class="row"><div class="glassbar row" style="gap:10px;padding:6px 16px 6px 6px;font-size:16px;font-weight:600">${avatar(30, { badge: 0, ring: true })}<span>Inicio</span></div></div>
  <div class="clk" style="position:absolute;top:26px;right:56px;z-index:10;font-size:20px;color:rgba(243,245,250,.8)">21:14</div>
  <div class="note" style="left:300px;top:20px">Al bajar por las filas el menú se recoge en una píldora pequeña. Atrás (o subir hasta arriba) lo despliega con el foco en la página actual.</div>`;
  return { name: 'tele_A_compacta', w: 1280, h: 720, html: pg(1280, 720, body) };
}

// --- Tele · B: iconos que se abren ---
function barB({ focus = null, active = 'Inicio', glass = true } = {}) {
  const items = [['search', 'Buscar'], ...MAIN, ['more', 'Más']];
  const tabs = items.map(([i, l]) => {
    const show = focus === l || (active === l && !focus) || active === l;
    const cls = `tab${show ? '' : ' ico'}${active === l ? ' on' : ''}${focus === l ? ' f' : ''}`;
    return `<div class="${cls}" style="font-size:17px">${ic(i, 23)}${show ? `<span>${l}</span>` : ''}</div>`;
  }).join('');
  return `<div class="scrim"></div>
  <div style="position:absolute;top:0;left:0;right:0;height:96px;display:flex;align-items:center;justify-content:space-between;padding:0 56px;z-index:10">
    <div style="width:140px">${avatar(44, { badge: 3, ring: true })}</div>
    <div class="tabs glassbar" style="${focus ? '' : 'background:rgba(36,36,44,.45)'}">${tabs}</div>
    <div class="clk" style="width:140px;text-align:right">21:14</div></div>`;
}
function tvB_rest() {
  return { name: 'tele_B_reposo', w: 1280, h: 720, html: pg(1280, 720, `${tvHome({ top: 150, focusCard: 0 })}${barB()}`) };
}
function tvB_focus() {
  const body = `${tvHome({ top: 150, dim: 0.25 })}${barB({ focus: 'Música' })}
  <div class="note" style="left:560px;top:112px">El botón con el foco se abre y enseña su nombre; la página en la que estás conserva el suyo.</div>`;
  return { name: 'tele_B_foco', w: 1280, h: 720, html: pg(1280, 720, body) };
}

// --- Tele · barra lateral ---
function sideItems(expanded, focus) {
  const items = [['search', 'Buscar'], ...MAIN, ['more', 'Más']];
  return items.map(([i, l]) => `<div class="sitem${l === 'Inicio' ? ' on' : ''}${focus === l ? ' f' : ''}">${ic(i, 24)}${expanded ? `<span>${l}</span>` : ''}</div>`).join('');
}
function tvSideClosed() {
  const body = `${tvHome({ top: 150, left: 128, focusCard: 0 })}
  <div class="side" style="width:100px;background:linear-gradient(90deg,rgba(0,0,0,.78),rgba(0,0,0,.35) 70%,transparent)">
    <div style="padding:0 0 18px 26px">${avatar(44, { badge: 3, ring: true })}</div>
    ${sideItems(false)}<div style="flex:1"></div>
    <div style="padding-left:30px;color:var(--mut);font-size:15px;font-weight:500">21:14</div></div>`;
  return { name: 'tele_lateral_cerrada', w: 1280, h: 720, html: pg(1280, 720, body) };
}
function tvSideOpen() {
  const body = `${tvHome({ top: 150, left: 128, dim: 0.35 })}
  <div class="side" style="width:330px;background:linear-gradient(90deg,rgba(14,14,20,.97) 0%,rgba(14,14,20,.92) 75%,rgba(14,14,20,0))">
    <div class="row" style="gap:14px;padding:0 0 18px 26px">${avatar(44, { badge: 3, ring: true })}<div><div style="font-size:18px;font-weight:700">Marta</div><div style="font-size:13px;color:#FF8FDE">3 novedades</div></div></div>
    ${sideItems(true, 'Música')}<div style="flex:1"></div>
    <div style="padding-left:30px;color:var(--mut);font-size:15px;font-weight:500">21:14</div></div>
  <div class="note" style="left:350px;top:300px">Con el foco en la barra se abre con los nombres y oscurece la página; derecha vuelve a la página, sin trampas.</div>`;
  return { name: 'tele_lateral_abierta', w: 1280, h: 720, html: pg(1280, 720, body) };
}

// --- Móvil ---
const PW = 393, PH = 852;
const PTABS = [['homeO', 'home', 'Inicio'], ['search', 'search', 'Buscar'], ['explore', 'explore', 'Descubrir'], ['note', 'note', 'Música']];
function tabbar(active) {
  const cells = PTABS.map(([o, f, l]) => `<div class="bt${active === l ? ' on' : ''}"><div class="ind">${icx(active === l ? f : o, 24)}</div><span>${l}</span></div>`).join('');
  const you = `<div class="bt${active === 'Tú' ? ' on' : ''}"><div class="ind">${avatar(26, { dot: true })}</div><span>Tú</span></div>`;
  return `<div class="tabbar"><div class="tabrow">${cells}${you}</div><div class="gest"><i></i></div></div>`;
}
function phoneHome() {
  const body = `<div class="hero" style="height:560px;background:radial-gradient(ellipse 90% 60% at 60% 25%,rgba(60,200,170,.55),transparent 70%),radial-gradient(ellipse 60% 40% at 100% 0%,rgba(143,107,255,.4),transparent 70%),linear-gradient(180deg,#0E2A2E,#0B0B0F 90%)">
    <svg viewBox="0 0 100 60" preserveAspectRatio="none" style="position:absolute;left:0;right:0;top:22%;width:100%;height:50%"><path d="M0 46 L14 34 L26 40 L42 24 L58 38 L72 26 L86 36 L100 30 L100 60 L0 60Z" fill="rgba(4,14,18,.55)"/></svg>
    <div style="position:absolute;left:0;right:0;bottom:0;height:60%;background:linear-gradient(0deg,#0B0B0F,transparent)"></div></div>
  ${status()}
  <div class="row" style="position:absolute;top:50px;left:16px;right:16px;justify-content:space-between;z-index:5">
    <div class="o" style="font-size:30px">Inicio</div>
    <div class="row" style="gap:10px"><div class="rbtn2">${ic('cast', 20)}</div><div class="rbtn2">${ic('inbox', 20)}<i class="bdg" style="font-style:normal;top:-3px;right:-3px">3</i></div></div></div>
  <div style="position:absolute;left:16px;right:16px;top:250px;z-index:3">
    <div class="kick" style="color:#7FE3D0;font-size:11px">Ya está aquí lo que pediste</div>
    <div class="o" style="font-size:34px;line-height:1.05;margin-top:6px">${HERO.t}</div>
    <div style="color:var(--mut);font-size:13px;margin-top:6px">${HERO.m}</div>
    <div class="row" style="gap:10px;margin-top:14px"><div class="btnw p" style="height:44px;font-size:15px;flex:1;justify-content:center">${ic('play', 22, '#0B0B0F')}Ver T1:E9</div><div class="btnw g" style="height:44px;font-size:15px;flex:1;justify-content:center">${ic('bookmark', 18)}Quiero verlo</div></div>
  </div>
  <div style="position:absolute;left:16px;top:440px;right:0;z-index:3">
    <div class="o" style="font-size:21px;margin-bottom:10px">Seguir viendo</div>
    <div class="row" style="gap:12px;align-items:flex-start">${FILMS.slice(0, 3).map((f) => lcard(f, 200)).join('')}</div>
    <div class="o" style="font-size:21px;margin:22px 0 10px">Quiero verlo</div>
    <div class="row" style="gap:12px;align-items:flex-start">${FILMS.slice(3, 7).map((f) => lcard([f[0], f[1], f[2], 0], 120, { h: 170 })).join('')}</div>
  </div>
  ${capsule({ al: 'brillo', t: 'Cielo de noche', a: 'Clara Vega', w: PW - 16, h: 58, pos: 'left:8px;bottom:98px;z-index:31' })}
  ${tabbar('Inicio')}`;
  return { name: 'movil_inicio', w: PW, h: PH, html: pg(PW, PH, body) };
}
function phoneYou() {
  const row = (i, l, c = '', x = '') => `<div class="prow">${icx(i, 22, 'rgba(243,245,250,.85)')}<span>${l}</span><span class="cnt">${c}${ic('chev' in X ? 'back' : 'back', 18, 'rgba(243,245,250,.4)', 'transform:rotate(180deg)')}</span>${x}</div>`;
  const body = `${status()}
  <div style="position:absolute;inset:0;background:radial-gradient(ellipse 90% 35% at 30% 0%,rgba(224,96,126,.28),transparent 70%)"></div>
  <div style="position:absolute;left:16px;right:16px;top:56px">
    <div class="row" style="justify-content:space-between"><div class="o" style="font-size:30px">Tú</div><div class="rbtn2">${ic('gear', 20)}</div></div>
    <div class="row" style="gap:16px;margin-top:18px">${avatar(68, { ring: true })}<div style="flex:1"><div class="o" style="font-size:24px">Marta</div><div style="color:var(--mut);font-size:13px;margin-top:3px">Perfil de la familia</div></div>
      <div class="pill ghost s">${icx('swap', 16)}<span>Cambiar</span></div></div>
    <div style="margin-top:20px;border-radius:16px;padding:14px;background:linear-gradient(120deg,rgba(79,216,255,.16),rgba(143,107,255,.16) 55%,rgba(255,92,207,.16));box-shadow:inset 0 0 0 1px rgba(255,255,255,.08)" class="row">
      <div class="rbtn2" style="background:rgba(255,255,255,.12)">${ic('inbox', 20)}</div>
      <div style="flex:1;margin-left:12px"><div style="font-weight:700;font-size:16px">Mis peticiones</div><div style="color:var(--mut);font-size:13px;margin-top:2px">3 novedades · 1 descargándose</div></div>
      <i class="bdg" style="position:static;font-style:normal">3</i></div>
    <div class="row" style="gap:10px;margin-top:12px;align-items:stretch">
      <div class="qt">${ic('bookmark', 24)}<div>Quiero verlo<b>12 títulos</b></div></div>
      <div class="qt">${ic('heart', 24, '#FF5CCF')}<div>Mis favoritos<b>2 novedades</b></div></div>
      <div class="qt">${icx('dl', 24)}<div>Descargas<b>3 en el móvil</b></div></div></div>
    <div style="margin-top:18px;color:var(--mut);font-size:12px;font-weight:700;letter-spacing:.08em">EN CASA</div>
    <div style="margin-top:4px">
      ${row('movie', 'Bibliotecas')}${row('masks', 'Géneros')}${row('tv', 'TV en directo')}${row('cal', 'Calendario')}
    </div>
  </div>
  ${capsule({ al: 'brillo', t: 'Cielo de noche', a: 'Clara Vega', w: PW - 16, h: 58, pos: 'left:8px;bottom:98px;z-index:31' })}
  ${tabbar('Tú')}`;
  return { name: 'movil_tu', w: PW, h: PH, html: pg(PW, PH, body, 'background:#0B0B0F') };
}
function phoneNow() {
  const body = `<div class="hero" style="height:560px;background:radial-gradient(ellipse 90% 60% at 60% 25%,rgba(60,200,170,.55),transparent 70%),linear-gradient(180deg,#0E2A2E,#0B0B0F 90%)"></div>${status()}
  <div style="position:absolute;top:46px;left:0;right:0;display:flex;justify-content:center;z-index:10"><div class="navpill sm" style="overflow:hidden;width:360px">${NOW.slice(0, 8).map((n) => `<div class="ni${n === 'home' ? ' on' : ''}">${ic(n, 19)}</div>`).join('')}</div></div>
  <div style="position:absolute;left:16px;right:16px;top:250px;z-index:3">
    <div class="o" style="font-size:34px;line-height:1.05">${HERO.t}</div>
    <div style="color:var(--mut);font-size:13px;margin-top:6px">${HERO.m}</div></div>
  <div style="position:absolute;left:16px;top:440px;right:0;z-index:3">
    <div class="o" style="font-size:21px;margin-bottom:10px">Seguir viendo</div>
    <div class="row" style="gap:12px;align-items:flex-start">${FILMS.slice(0, 3).map((f) => lcard(f, 200)).join('')}</div>
    <div class="o" style="font-size:21px;margin:22px 0 10px">Quiero verlo</div>
    <div class="row" style="gap:12px;align-items:flex-start">${FILMS.slice(3, 7).map((f) => lcard([f[0], f[1], f[2], 0], 120, { h: 170 })).join('')}</div></div>
  ${capsule({ al: 'brillo', t: 'Cielo de noche', a: 'Clara Vega', w: PW - 20, h: 62, pos: 'left:10px;bottom:22px' })}
  <div class="note" style="left:20px;top:100px;max-width:250px">Hoy: 8 iconos sin nombre arriba (no caben todos), lejos del pulgar.</div>`;
  return { name: 'movil_ahora', w: PW, h: PH, html: pg(PW, PH, body) };
}

// --- Ordenador (web) ---
function desktop() {
  const W = 1440, H = 900;
  const tabs = MAIN.map(([i, l]) => `<div class="tab${l === 'Inicio' ? ' on' : ''}" style="font-size:16px;height:40px;padding:0 16px;${l === 'Música' ? 'background:rgba(255,255,255,.10);color:var(--ink)' : ''}">${l}</div>`).join('')
    + `<div class="tab" style="font-size:16px;height:40px;padding:0 14px">Más ${ic('down', 18)}</div>`;
  const body = `${heroBg()}
  <div style="position:absolute;top:0;left:0;right:0;height:76px;display:flex;align-items:center;gap:26px;padding:0 56px;z-index:10;background:linear-gradient(180deg,rgba(0,0,0,.7),transparent)">
    <div class="o" style="font-size:26px;letter-spacing:-.02em">kOS <span style="font-weight:300;font-size:14px;letter-spacing:.2em;background:var(--grad);-webkit-background-clip:text;color:transparent">TV</span></div>
    <div class="tabs">${tabs}</div><div style="flex:1"></div>
    <div class="search" style="width:260px;height:40px;padding:0 16px;font-size:15px">${ic('search', 20)}Buscar</div>
    <div class="rbtn2">${ic('inbox', 20)}<i class="bdg" style="font-style:normal">3</i></div>
    ${avatar(40, { ring: true })}</div>
  <div style="position:absolute;left:56px;top:180px;width:620px;z-index:2">
    <div class="kick" style="color:#7FE3D0">Ya está aquí lo que pediste</div>
    <div class="o" style="font-size:64px;line-height:1.02;margin-top:10px">${HERO.t}</div>
    <div style="color:var(--mut);font-size:16px;margin-top:12px">${HERO.m}</div>
    <div style="font-size:16px;line-height:1.5;margin-top:12px;color:rgba(243,245,250,.82)">${HERO.d}</div>
    <div class="row" style="gap:14px;margin-top:24px"><div class="btnw p">${ic('play', 24, '#0B0B0F')}Ver T1:E9</div><div class="btnw g">${ic('bookmark', 20)}Quiero verlo</div></div></div>
  <div style="position:absolute;left:56px;top:580px;right:0;z-index:2">
    <div class="o" style="font-size:24px;margin-bottom:14px">Seguir viendo</div>
    <div class="row" style="gap:20px;align-items:flex-start">${FILMS.slice(0, 6).map((f) => lcard(f, 270)).join('')}</div></div>
  <div class="cursor" style="left:392px;top:40px">${ic('cursor', 26, '#fff')}</div>
  ${capsule({ al: 'brillo', t: 'Cielo de noche', a: 'Clara Vega', w: 380, h: 64, pos: 'right:28px;bottom:28px' })}`;
  return { name: 'ordenador', w: W, h: H, html: pg(W, H, body) };
}

// --- Comparativas (después de renderizar) ---
function cmp(name, a, b, w, h, scale) {
  const iw = Math.round(w * scale), ih = Math.round(h * scale);
  const W = iw * 2 + 60, H = ih + 80;
  const body = `<div style="display:flex;gap:20px;padding:20px;background:#1a1a1f;height:100%">
    ${[[a, 'Ahora'], [b, 'Propuesta']].map(([f, t]) => `<div><div class="o" style="font-size:24px;margin-bottom:10px">${t}</div><img src="file://${path.join(OUT, f + '.png')}?v=${Date.now()}" style="width:${iw}px;height:${ih}px;border-radius:8px;display:block"></div>`).join('')}</div>`;
  return { name, w: W, h: H, html: page(W, H, body) };
}

(async () => {
  const screens = [tvNow(), tvA_rest(), tvA_focus(), tvA_more(), tvProfile(), tvA_compact(), tvB_rest(), tvB_focus(), tvSideClosed(), tvSideOpen(), phoneNow(), phoneHome(), phoneYou(), desktop()];
  const browser = await chromium.launch();
  const shoot = async (s) => {
    const p = await browser.newPage({ viewport: { width: s.w, height: s.h }, deviceScaleFactor: 2 });
    const f = path.join(OUT, 'html', s.name + '.html');
    fs.writeFileSync(f, s.html);
    await p.goto('file://' + f);
    await p.evaluate(() => document.fonts.ready);
    await p.waitForTimeout(150);
    await p.screenshot({ path: path.join(OUT, s.name + '.png') });
    await p.close();
    console.log(s.name);
  };
  for (const s of screens) await shoot(s);
  await shoot(cmp('comparar_tele', 'tele_ahora', 'tele_A_reposo', 1280, 720, 0.75));
  await shoot(cmp('comparar_movil', 'movil_ahora', 'movil_inicio', 393, 852, 1));
  await browser.close();
})();
