// Piezas comunes de las maquetas de Música de kOS TV.
const FONTS = '/home/user/kos-TV/assets/fonts';

const P = {
  play: 'M8 5.5v13a1 1 0 0 0 1.5.86l10.2-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z',
  pause: 'M7 5h3.2v14H7zM13.8 5H17v14h-3.2z',
  next: 'M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z',
  prev: 'M6 6h2v12H6zm3.5 6l8.5 6V6z',
  shuffle: 'M10.59 9.17L5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41l-1.41 1.41 3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z',
  repeat: 'M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z',
  home: 'M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z',
  search: 'M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z',
  explore: 'M12 10.9c-.61 0-1.1.49-1.1 1.1s.49 1.1 1.1 1.1c.61 0 1.1-.49 1.1-1.1s-.49-1.1-1.1-1.1zM12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm2.19 12.19L6 18l3.81-8.19L18 6l-3.81 8.19z',
  masks: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM8.5 8.5a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2zm7 0a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2zM12 18c-2.4 0-4.4-1.5-5.1-3.6h10.2C16.4 16.5 14.4 18 12 18z',
  bookmark: 'M17 3H7c-1.1 0-1.99.9-1.99 2L5 21l7-3 7 3V5c0-1.1-.9-2-2-2z',
  note: 'M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z',
  tv: 'M21 6h-7.59l3.29-3.29L16 2l-4 4-4-4-.71.71L10.59 6H3c-1.1 0-2 .89-2 2v12c0 1.1.9 2 2 2h18c1.1 0 2-.9 2-2V8c0-1.11-.9-2-2-2zm0 14H3V8h18v12zM9 10v8l7-4z',
  movie: 'M18 4l2 4h-3l-2-4h-2l2 4h-3l-2-4H8l2 4H7L5 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V4h-4z',
  gear: 'M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.49.49 0 0 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6a3.6 3.6 0 1 1 0-7.2 3.6 3.6 0 0 1 0 7.2z',
  heart: 'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z',
  heartO: 'M16.5 3c-1.74 0-3.41.81-4.5 2.09C10.91 3.81 9.24 3 7.5 3 4.42 3 2 5.42 2 8.5c0 3.78 3.4 6.86 8.55 11.54L12 21.35l1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3zm-4.4 15.55l-.1.1-.1-.1C7.14 14.24 4 11.39 4 8.5 4 6.5 5.5 5 7.5 5c1.54 0 3.04.99 3.57 2.36h1.87C13.46 5.99 14.96 5 16.5 5c2 0 3.5 1.5 3.5 3.5 0 2.89-3.14 5.74-7.9 10.05z',
  more: 'M6 10c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm12 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm-6 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z',
  queue: 'M15 6H3v2h12V6zm0 4H3v2h12v-2zM3 16h8v-2H3v2zM17 6v8.18c-.31-.11-.65-.18-1-.18-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3V8h3V6h-5z',
  lyrics: 'M4 5h16v2H4zM4 9h16v2H4zM4 13h11v2H4zM4 17h7v2H4z',
  add: 'M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
  check: 'M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z',
  ask: 'M12 3a1 1 0 0 1 1 1v8.59l2.3-2.3 1.4 1.42L12 16.4l-4.7-4.7 1.4-1.4 2.3 2.29V4a1 1 0 0 1 1-1zM5 18h14v2H5z',
  truck: 'M20 8h-3V4H3c-1.1 0-2 .9-2 2v11h2c0 1.66 1.34 3 3 3s3-1.34 3-3h6c0 1.66 1.34 3 3 3s3-1.34 3-3h2v-5l-3-4zM6 18.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm13.5-9l1.96 2.5H17V9.5h2.5zm-1.5 9c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5z',
  wave: 'M7 18h2V6H7v12zm4 4h2V2h-2v20zm-8-8h2v-4H3v4zm12 4h2V6h-2v12zm4-8v4h2v-4h-2z',
  back: 'M15.41 7.41L14 6l-6 6 6 6 1.41-1.41L10.83 12z',
  down: 'M7.41 8.59L12 13.17l4.59-4.58L18 10l-6 6-6-6z',
  close: 'M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
  inbox: 'M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 12h-4a3 3 0 0 1-6 0H5V5h14z',
  library: 'M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 9h-4v4h-2v-4H9V9h4V5h2v4h4v2z',
  cast: 'M21 3H3c-1.1 0-2 .9-2 2v3h2V5h18v14h-7v2h7c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM1 18v3h3c0-1.66-1.34-3-3-3zm0-4v2c2.76 0 5 2.24 5 5h2c0-3.87-3.13-7-7-7zm0-4v2a9 9 0 0 1 9 9h2c0-6.08-4.93-11-11-11z',
  volume: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 7.97v8.05c1.48-.73 2.5-2.25 2.5-4.02z',
  info: 'M11 7h2v2h-2zm0 4h2v6h-2zm1-9C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z',
  cursor: 'M5 3l14 8-6 1.5L10 19z',
};
const ic = (n, s = 24, c = 'currentColor', extra = '') =>
  `<svg width="${s}" height="${s}" viewBox="0 0 24 24" style="flex:none;${extra}"><path d="${P[n]}" fill="${c}" fill-rule="evenodd"/></svg>`;

// Discos de mentira, como los datos falsos de la app.
const AL = {
  faroles: { t: 'Faroles', a: 'Los Faroleros', y: 2026, c: ['#36E58C', '#0C2B5E'], p: 0, home: false },
  brillo: { t: 'Brillo', a: 'Clara Vega', y: 2026, c: ['#E33AD6', '#5B0F30'], p: 1, home: true },
  verano: { t: 'Verano', a: 'Lola Brisa', y: 2025, c: ['#E9D23A', '#2B6912'], p: 2, home: true },
  norte: { t: 'Norte', a: 'Rumba Norte', y: 2026, c: ['#F2456B', '#6A4A12'], p: 1, home: false },
  marea: { t: 'Mar adentro', a: 'DJ Marea', y: 2025, c: ['#3BA9F2', '#2A1561'], p: 0, home: true },
  lunas: { t: 'Tres de la mañana', a: 'Tres Lunas', y: 2024, c: ['#F2A33A', '#3B5A0E'], p: 2, home: false },
  nube: { t: 'Cielo rojo', a: 'Nube Roja', y: 2026, c: ['#6C4BF2', '#4A0F5B'], p: 0, home: false },
  limon: { t: 'Limonada', a: 'Sal y Limón', y: 2025, c: ['#9BF23A', '#0E5A3C'], p: 1, home: true },
  bailar: { t: 'Bailar contigo', a: 'Rumba Norte', y: 2025, c: ['#F27A3A', '#2E5A0E'], p: 2, home: true },
  luna: { t: 'Luna', a: 'Sal y Limón', y: 2026, c: ['#3AF0C8', '#16245E'], p: 1, home: false },
  primavera: { t: 'Primavera', a: 'Nube Roja', y: 2024, c: ['#5B3BF2', '#7A1A6A'], p: 2, home: true },
  madrid: { t: 'Madrid de noche', a: 'DJ Marea', y: 2026, c: ['#3B4CF2', '#5E0F3C'], p: 0, home: false },
  orilla: { t: 'La orilla', a: 'Lola Brisa', y: 2023, c: ['#3AD4F2', '#5A2E0E'], p: 0, home: true },
  sal: { t: 'Agua de sal', a: 'Lola Brisa', y: 2024, c: ['#F2D9A3', '#B0306A'], p: 1, home: false },
};
const ART = {
  'Lola Brisa': ['#F2B48C', '#8A2E5E'], 'Sal y Limón': ['#B8F25A', '#1F5A4A'], 'Los Faroleros': ['#5AF2B0', '#123A6A'],
  'Clara Vega': ['#F25AD8', '#3A0F4A'], 'Rumba Norte': ['#F2865A', '#5A1A12'], 'DJ Marea': ['#5AB8F2', '#1A1A5A'],
  'Tres Lunas': ['#F2C85A', '#4A3A0E'], 'Nube Roja': ['#F25A5A', '#3A0E2A'],
};

function pattern(p) {
  if (p === 0) return `<circle cx="70" cy="10" r="34"/><circle cx="2" cy="55" r="22"/><circle cx="-4" cy="88" r="30"/>`;
  if (p === 1) return `<circle cx="50" cy="62" r="30"/><circle cx="60" cy="28" r="13"/><circle cx="96" cy="70" r="14"/>`;
  return `<circle cx="78" cy="22" r="16" stroke-dasharray="3 3"/><circle cx="30" cy="70" r="20" stroke-dasharray="3 3"/><circle cx="88" cy="88" r="10" stroke-dasharray="3 3"/>`;
}
function cover(al, s, r = 8, extra = '') {
  const a = typeof al === 'string' ? AL[al] : al;
  return `<div class="cov" style="width:${s}px;height:${s}px;border-radius:${r}px;background:linear-gradient(160deg,${a.c[0]} 0%,${a.c[1]} 100%);${extra}">
  <svg viewBox="0 0 100 100" preserveAspectRatio="none"><g fill="none" stroke="rgba(255,255,255,.85)" stroke-width="${s > 120 ? 1.1 : 1.8}">${pattern(a.p)}</g></svg></div>`;
}
// Retrato de artista de mentira: fondo de color y silueta.
function portrait(name, s, round = true, extra = '') {
  const c = ART[name] || ['#888', '#222'];
  return `<div class="cov" style="width:${s}px;height:${s}px;border-radius:${round ? '50%' : '10px'};background:radial-gradient(circle at 30% 20%,${c[0]} 0%,${c[1]} 75%);${extra}">
  <svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMax slice"><g fill="rgba(10,6,20,.55)"><circle cx="50" cy="42" r="17"/><path d="M14 104c2-24 18-36 36-36s34 12 36 36z"/></g></svg></div>`;
}
function bigPortrait(name, w, h) {
  const c = ART[name];
  return `<div style="position:absolute;inset:0;background:radial-gradient(ellipse at 72% 30%,${c[0]} 0%,${c[1]} 55%,#0B0B0F 95%)">
  <svg style="position:absolute;right:${w * 0.12}px;bottom:0" width="${h * 0.95}" height="${h * 0.95}" viewBox="0 0 100 100"><g fill="rgba(10,6,20,.5)"><circle cx="50" cy="40" r="18"/><path d="M8 102c2-26 20-40 42-40s40 14 42 40z"/></g></svg></div>`;
}

// El botón de reproducir: uno solo para todo, con el degradado de la marca.
function playBtn(s, { focus = false, pause = false, hover = false } = {}) {
  const g = Math.round(s * 0.46);
  return `<div class="play${focus ? ' fplay' : ''}${hover ? ' hplay' : ''}" style="width:${s}px;height:${s}px">${ic(pause ? 'pause' : 'play', g, '#0B0B0F', pause ? '' : `margin-left:${Math.round(s * 0.04)}px`)}</div>`;
}
function roundBtn(icon, s, { focus = false, color = '#F3F5FA', glass = true } = {}) {
  return `<div class="rbtn${glass ? ' glass' : ''}${focus ? ' frb' : ''}" style="width:${s}px;height:${s}px">${ic(icon, Math.round(s * 0.46), focus ? '#0B0B0F' : color)}</div>`;
}
function pill(label, icon, { focus = false, size = 'm', kind = 'ghost' } = {}) {
  return `<div class="pill ${kind} ${size}${focus ? ' fpill' : ''}">${icon ? ic(icon, size === 's' ? 16 : size === 'l' ? 22 : 18) : ''}<span>${label}</span></div>`;
}
const eq = (h = 14, w = 3) => `<span class="eq" style="height:${h}px">${[0.5, 1, 0.7, 0.9].map((k, i) => `<i style="width:${w}px;height:${Math.round(h * k)}px"></i>`).join('')}</span>`;

// Fila de canción: sin botón propio; el número se convierte en ▶ al enfocar.
function songRow({ n, al, t, a, d, focus = false, playing = false, cov = 44, fs = 15, w = '100%', liked = false, plays }) {
  const lead = playing ? eq(16, 3) : focus ? ic('play', fs + 3, '#F3F5FA') : `<span>${n}</span>`;
  return `<div class="srow${focus ? ' frow' : ''}" style="width:${w};--fs:${fs}px">
    ${n !== undefined ? `<div class="num">${lead}</div>` : ''}
    ${al ? cover(al, cov, 6) : ''}
    <div class="st"><div class="t${playing ? ' grad' : ''}">${t}</div>${a ? `<div class="a">${a}</div>` : ''}</div>
    ${plays ? `<div class="plays">${plays}</div>` : ''}
    ${liked ? ic('heart', fs, '#FF5CCF') : ''}
    ${d ? `<div class="d">${d}</div>` : ''}
    ${focus ? `<div class="rmore">${ic('more', fs + 5, '#F3F5FA')}</div>` : ''}
  </div>`;
}
function card(al, s, { focus = false, hover = false, sub, title, r = 10, playS } = {}) {
  const a = AL[al];
  return `<div class="card${focus ? ' fcard' : ''}${hover ? ' hcard' : ''}" style="width:${s}px">
    <div class="cwrap" style="border-radius:${r}px">${cover(al, s, r)}${focus || hover ? `<div class="cplay">${playBtn(playS || Math.round(s * 0.26), {})}</div>` : ''}</div>
    <div class="ct">${title || a.t}</div><div class="cs">${sub || a.a + ' · ' + a.y}</div></div>`;
}
function artistCard(name, s, { sub = 'Artista', focus = false } = {}) {
  return `<div class="card acard${focus ? ' fcard' : ''}" style="width:${s}px">${portrait(name, s)}<div class="ct" style="text-align:center">${name}</div><div class="cs" style="text-align:center">${sub}</div></div>`;
}
function mixCard(i, s, al, names, { focus = false, r = 10 } = {}) {
  const a = AL[al];
  return `<div class="card${focus ? ' fcard' : ''}" style="width:${s}px"><div class="cwrap mix" style="border-radius:${r}px;width:${s}px;height:${s}px;background:linear-gradient(155deg,${a.c[0]},${a.c[1]})">
    <div class="mixgrid">${portrait(names[0], s * 0.44, true)}${portrait(names[1], s * 0.3, true, 'margin-left:-' + s * 0.06 + 'px;margin-top:' + s * 0.1 + 'px')}</div>
    <div class="mixlab" style="font-size:${Math.round(s * 0.13)}px">Mezcla ${i}</div>
    <div class="mixbar" style="background:${a.c[0]}"></div></div>
    <div class="ct">Mezcla ${i}</div><div class="cs">${names.join(', ')} y más</div></div>`;
}
function shelfHead(title, sub, { fs = 24, play = 0, more = '' } = {}) {
  return `<div class="sh"><div><div class="row" style="gap:14px"><div class="shT" style="font-size:${fs}px">${title}</div>${play ? playBtn(play) : ''}</div>${sub ? `<div class="shS">${sub}</div>` : ''}</div>
    <div class="shR">${more ? `<span class="shM">${more}</span>` : ''}</div></div>`;
}
// La nota de «no está en casa»: solo en el álbum y en el reproductor.
function awayNote({ fs = 15, btnFocus = false, state = 'ask', size = 'm', compact = false } = {}) {
  const btn = state === 'ask' ? pill('Pedir el álbum', 'ask', { focus: btnFocus, size })
    : state === 'asked' ? pill('Pedido · te avisamos', 'check', { size, kind: 'quiet' })
    : state === 'way' ? pill('De camino', 'truck', { size, kind: 'quiet' })
    : pill('Ya está en casa', 'home', { size, kind: 'quiet' });
  return `<div class="away${compact ? ' compact' : ''}" style="font-size:${fs}px"><div class="row" style="gap:10px;align-items:flex-start">${ic('wave', fs + 3, 'rgba(243,245,250,.55)', 'margin-top:1px')}
    <div class="awt"><b>Este disco no está en casa: suena en streaming.</b> Pídelo para tenerlo en casa con más calidad.</div></div>${btn}</div>`;
}
function capsule({ al = 'faroles', t = 'Calle', a = 'Los Faroleros', w = 380, h = 64, focus = false, pos = '' } = {}) {
  return `<div class="caps${focus ? ' fcaps' : ''}" style="width:${w}px;height:${h}px;${pos}">
    ${cover(al, h - 16, (h - 16) / 2, 'margin-left:8px')}
    <div class="capt"><div class="t">${t}</div><div class="a">${a}</div></div>
    ${ic('heartO', 22, 'rgba(243,245,250,.8)')}
    ${playBtn(h - 22, { pause: true })}
    ${ic('next', 24, '#F3F5FA', 'margin-right:14px')}
    <div class="capbar"><i style="width:34%"></i></div></div>`;
}

// Navegación de la app (diseño de barra arriba, lateral y móvil).
const NAV = ['home', 'search', 'explore', 'masks', 'bookmark', 'note', 'tv', 'movie', 'gear'];
function topBar(w, { clock = '21:14', active = 'note', s = 1 } = {}) {
  return `<div class="topbar" style="width:${w}px;padding:0 ${48 * s}px;height:${84 * s}px">
    <div class="tl"><div class="avatar">K</div><div class="tb">${ic('inbox', 20)}</div><div class="tb">${ic('heart', 20, '#FF5CCF')}<i class="badge">2</i></div></div>
    <div class="navpill">${NAV.map((n) => `<div class="ni${n === active ? ' on' : ''}">${ic(n, 22)}</div>`).join('')}</div>
    <div class="clock">${clock}</div></div>`;
}
function sideRail(h) {
  return `<div class="rail" style="height:${h}px"><div class="tb">${ic('inbox', 20)}</div><div class="tb">${ic('heart', 20, '#FF5CCF')}<i class="badge">2</i></div><div style="height:22px"></div>
  ${NAV.map((n) => `<div class="ri${n === 'note' ? ' on' : ''}">${ic(n, 24)}</div>`).join('')}</div>`;
}
function phoneTop() {
  return `<div class="ptop"><div class="navpill sm">${NAV.slice(0, 8).map((n) => `<div class="ni${n === 'note' ? ' on' : ''}">${ic(n, 19)}</div>`).join('')}</div></div>`;
}
function phoneBottom() {
  const items = [['home', 'Inicio'], ['search', 'Buscar'], ['note', 'Música'], ['tv', 'Directo'], ['bookmark', 'Mi lista']];
  return `<div class="pbot">${items.map(([n, l]) => `<div class="bi${n === 'note' ? ' on' : ''}">${ic(n, 24)}<span>${l}</span></div>`).join('')}</div>`;
}
function status() {
  return `<div class="status"><b>21:14</b><span>●●● ▴ ▮</span></div>`;
}

const CSS = `
@font-face{font-family:Outfit;src:url(file://${FONTS}/Outfit-Bold.ttf);font-weight:700}
@font-face{font-family:Outfit;src:url(file://${FONTS}/Outfit-Light.ttf);font-weight:300}
@font-face{font-family:Rob;src:url(file://${FONTS}/Roboto-Regular.ttf);font-weight:400}
@font-face{font-family:Rob;src:url(file://${FONTS}/Roboto-Medium.ttf);font-weight:500}
@font-face{font-family:Rob;src:url(file://${FONTS}/Roboto-Bold.ttf);font-weight:700}
:root{--ink:#F3F5FA;--mut:rgba(243,245,250,.62);--dim:rgba(243,245,250,.42);--bg:#0B0B0F;
 --grad:linear-gradient(120deg,#4FD8FF 0%,#8F6BFF 52%,#FF5CCF 100%)}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--ink);font-family:Rob,Roboto,sans-serif;overflow:hidden;position:relative;-webkit-font-smoothing:antialiased}
.o{font-family:Outfit,sans-serif;font-weight:700;letter-spacing:-.01em}
.cov{position:relative;flex:none;overflow:hidden;box-shadow:0 6px 18px rgba(0,0,0,.35)}
.cov svg{position:absolute;inset:0;width:100%;height:100%}
.row{display:flex;align-items:center}
.play{flex:none;border-radius:50%;background:var(--grad);display:flex;align-items:center;justify-content:center;box-shadow:0 6px 22px rgba(143,107,255,.35)}
.fplay{box-shadow:0 0 0 3px var(--bg),0 0 0 6px var(--ink),0 10px 40px rgba(143,107,255,.7);transform:scale(1.1)}
.rbtn{flex:none;border-radius:50%;display:flex;align-items:center;justify-content:center}
.rbtn.glass{background:rgba(255,255,255,.10);backdrop-filter:blur(10px)}
.frb{background:var(--ink)!important;transform:scale(1.1);box-shadow:0 8px 30px rgba(0,0,0,.5)}
.pill{display:inline-flex;align-items:center;gap:8px;border-radius:999px;font-weight:500;white-space:nowrap;flex:none}
.pill.m{height:40px;padding:0 18px;font-size:15px}.pill.s{height:32px;padding:0 14px;font-size:13px}.pill.l{height:52px;padding:0 24px;font-size:18px}
.pill.ghost{background:rgba(255,255,255,.08);box-shadow:inset 0 0 0 1px rgba(255,255,255,.22);color:var(--ink)}
.pill.quiet{background:rgba(255,255,255,.06);color:var(--mut)}
.fpill{background:var(--ink)!important;color:#0B0B0F!important;box-shadow:0 8px 28px rgba(0,0,0,.5)!important;transform:scale(1.06)}
.fpill svg path{fill:#0B0B0F}
.eq{display:inline-flex;align-items:flex-end;gap:2px}.eq i{display:block;border-radius:2px;background:var(--grad)}
.grad{background:var(--grad);-webkit-background-clip:text;color:transparent!important}
.srow{display:flex;align-items:center;gap:14px;padding:7px 12px;border-radius:10px;font-size:var(--fs)}
.srow .num{width:22px;text-align:center;color:var(--mut);font-variant-numeric:tabular-nums;display:flex;justify-content:center;font-weight:500}
.srow .st{flex:1;min-width:0}.srow .t{font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.srow .a{color:var(--mut);font-size:calc(var(--fs) - 2px);margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.srow .d,.srow .plays{color:var(--mut);font-variant-numeric:tabular-nums;font-size:calc(var(--fs) - 1px)}
.srow .plays{width:90px;text-align:right;white-space:nowrap}
.frow{background:rgba(255,255,255,.13);box-shadow:inset 0 0 0 2px var(--ink);transform:scale(1.02)}
.rmore{display:flex}
.card{flex:none}.cwrap{position:relative;overflow:hidden;transition:none}
.ct{font-weight:500;font-size:15px;margin-top:10px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cs{color:var(--mut);font-size:13px;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.fcard .cwrap,.fcard>.cov{box-shadow:0 0 0 3px var(--bg),0 0 0 6px var(--ink),0 18px 40px rgba(0,0,0,.7)}
.fcard{transform:scale(1.07);transform-origin:50% 40%}
.fcard .ct{color:#fff}
.cplay{position:absolute;right:8px;bottom:8px}
.hcard .cwrap{filter:brightness(1.08)}
.acard>.cov{margin:0 auto}
.mix{display:flex;flex-direction:column;justify-content:space-between}
.mixgrid{display:flex;padding:10%}
.mixlab{font-family:Outfit;font-weight:700;padding:0 9% 12%;text-shadow:0 2px 12px rgba(0,0,0,.35)}
.mixbar{position:absolute;left:0;right:0;bottom:0;height:5px;filter:brightness(1.2)}
.sh{display:flex;align-items:flex-end;justify-content:space-between;margin-bottom:14px}
.shT{font-family:Outfit;font-weight:700;letter-spacing:-.01em}.shS{color:var(--mut);font-size:14px;margin-top:3px}
.shR{display:flex;align-items:center;gap:14px}.shM{color:var(--mut);font-size:14px;font-weight:500}
.shelf{display:flex;gap:22px;overflow:visible}
.away{display:flex;align-items:center;gap:12px;color:var(--mut);line-height:1.35}
.away b{color:var(--ink);font-weight:500}.away .awt{flex:0 1 auto;max-width:560px}
.away.compact{flex-direction:column;align-items:flex-start;gap:10px}
.caps{position:absolute;display:flex;align-items:center;gap:12px;border-radius:999px;background:rgba(26,24,34,.92);backdrop-filter:blur(24px) saturate(1.4);
 box-shadow:0 14px 40px rgba(0,0,0,.55),inset 0 0 0 1px rgba(255,255,255,.10);overflow:hidden;z-index:20}
.caps .capt{flex:1;min-width:0}.caps .t{font-weight:500;font-size:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.caps .a{color:var(--mut);font-size:13px;margin-top:2px}
.capbar{position:absolute;left:28px;right:28px;bottom:0;height:3px;background:rgba(255,255,255,.12);border-radius:3px}
.capbar i{display:block;height:100%;background:var(--grad);border-radius:3px}
.fcaps{box-shadow:0 0 0 3px var(--ink),0 14px 40px rgba(0,0,0,.6)}
.topbar{position:absolute;top:0;left:0;display:flex;align-items:center;justify-content:space-between;z-index:10}
.tl{display:flex;gap:12px;align-items:center;width:200px}
.avatar{width:42px;height:42px;border-radius:50%;background:rgba(255,255,255,.12);display:flex;align-items:center;justify-content:center;font-weight:700;font-size:18px}
.tb{position:relative;width:42px;height:42px;border-radius:50%;background:rgba(255,255,255,.08);display:flex;align-items:center;justify-content:center;color:var(--ink)}
.badge{position:absolute;top:-3px;right:-3px;background:#FF5CCF;color:#0B0B0F;font-style:normal;font-size:10px;font-weight:700;border-radius:9px;min-width:17px;height:17px;display:flex;align-items:center;justify-content:center}
.navpill{display:flex;gap:6px;padding:5px 10px;border-radius:999px;background:rgba(40,40,48,.6);backdrop-filter:blur(20px);box-shadow:inset 0 0 0 1px rgba(255,255,255,.06)}
.ni{width:44px;height:38px;display:flex;align-items:center;justify-content:center;color:rgba(243,245,250,.55);border-radius:999px;position:relative}
.ni.on{color:var(--ink)}.ni.on:after{content:'';position:absolute;bottom:2px;width:16px;height:3px;border-radius:2px;background:var(--grad)}
.navpill.sm .ni{width:38px;height:34px}
.clock{width:200px;text-align:right;font-size:22px;font-weight:500}
.rail{position:absolute;left:0;top:0;width:88px;display:flex;flex-direction:column;align-items:center;gap:10px;padding-top:40px;z-index:10;background:linear-gradient(90deg,rgba(0,0,0,.5),transparent)}
.ri{width:46px;height:40px;display:flex;align-items:center;justify-content:center;color:rgba(243,245,250,.5);position:relative}
.ri.on{color:var(--ink)}.ri.on:before{content:'';position:absolute;left:-14px;width:3px;height:20px;border-radius:2px;background:var(--grad)}
.ptop{position:absolute;top:44px;left:0;right:0;display:flex;justify-content:center;z-index:10}
.pbot{position:absolute;bottom:0;left:0;right:0;height:84px;padding-bottom:20px;display:flex;justify-content:space-around;align-items:center;background:rgba(11,11,15,.92);backdrop-filter:blur(20px);border-top:1px solid rgba(255,255,255,.06);z-index:30}
.bi{display:flex;flex-direction:column;align-items:center;gap:3px;color:rgba(243,245,250,.5);font-size:11px;font-weight:500}.bi.on{color:var(--ink)}
.status{position:absolute;top:0;left:0;right:0;height:44px;display:flex;justify-content:space-between;align-items:center;padding:0 30px;font-size:15px;z-index:40}
.status span{font-size:11px;letter-spacing:2px}
.tile{display:flex;align-items:center;gap:12px;background:rgba(255,255,255,.07);border-radius:8px;overflow:hidden;font-weight:500}
.tile .cov{box-shadow:none}
.ftile{background:rgba(255,255,255,.16);box-shadow:0 0 0 3px var(--ink),0 12px 30px rgba(0,0,0,.6);transform:scale(1.05)}
.search{display:flex;align-items:center;gap:12px;border-radius:999px;background:rgba(255,255,255,.08);color:var(--mut);box-shadow:inset 0 0 0 1px rgba(255,255,255,.06)}
.kick{color:var(--mut);font-size:13px;font-weight:500;letter-spacing:.08em;text-transform:uppercase}
.prog{position:relative;height:5px;border-radius:5px;background:rgba(255,255,255,.18)}
.prog i{position:absolute;left:0;top:0;bottom:0;border-radius:5px;background:var(--grad)}
.prog b{position:absolute;top:50%;width:13px;height:13px;border-radius:50%;background:var(--ink);transform:translate(-50%,-50%)}
.times{display:flex;justify-content:space-between;color:var(--mut);font-size:13px;margin-top:8px;font-variant-numeric:tabular-nums}
.chip{white-space:nowrap;display:inline-flex;align-items:center;gap:8px;border-radius:999px;background:rgba(0,0,0,.28);color:var(--mut);backdrop-filter:blur(10px)}
.chip b{color:var(--ink);font-weight:500}
.chip .lnk{color:var(--ink);font-weight:700;display:inline-flex;align-items:center;gap:5px;border-radius:999px}
.chip .lnk.f{background:var(--ink);color:#0B0B0F}.chip .lnk.f svg path{fill:#0B0B0F}
.tag{display:inline-block;border-radius:6px;padding:3px 8px;font-size:12px;font-weight:700;background:rgba(255,255,255,.1);color:var(--mut)}
.cursor{position:absolute;z-index:50;filter:drop-shadow(0 2px 3px rgba(0,0,0,.6))}
`;

function page(w, h, body, bg = '') {
  return `<!doctype html><html><head><meta charset="utf-8"><style>${CSS}</style></head><body style="width:${w}px;height:${h}px;${bg}">${body}</body></html>`;
}
// Fondo que toma el color de la portada.
const wash = (c, k = 0.55, at = '25% 0%') =>
  `background:radial-gradient(ellipse 90% 70% at ${at},${c}${Math.round(k * 255).toString(16).padStart(2, '0')} 0%,transparent 70%),#0B0B0F;`;

module.exports = { ic, AL, ART, cover, portrait, bigPortrait, playBtn, roundBtn, pill, eq, songRow, card, artistCard, mixCard, shelfHead, awayNote, capsule, topBar, sideRail, phoneTop, phoneBottom, status, page, wash };
