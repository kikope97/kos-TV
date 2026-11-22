const L = require('./lib');
const { ic, AL, cover, portrait, bigPortrait, playBtn, roundBtn, pill, songRow, card, artistCard, mixCard, shelfHead, awayNote, capsule, topBar, sideRail, page, wash } = L;
const W = 1280, H = 720, M = 64;

const TRACKS = {
  faroles: [['Calle', '3:00'], ['Luna de noche', '3:07'], ['Bailar otra vez', '3:14'], ['Volver en ti', '3:21'], ['Contigo y tú', '3:28'], ['Sin ti', '3:35'], ['Farol', '3:12'], ['Noche en ti', '3:40'], ['Madrugada', '3:05'], ['Hasta luego', '3:52']],
  brillo: [['Brillo', '2:58'], ['Cielo de noche', '3:22'], ['Verano otra vez', '3:05'], ['Vuelo en ti', '3:41'], ['Sombra de noche', '3:16'], ['Latido', '3:09'], ['Espejo', '2:47'], ['Hasta mañana', '3:55'], ['Marea', '3:18'], ['Brillo (acústica)', '3:02']],
};

function tile(al, label, sub, { focus = false, w = 268, h = 64, special } = {}) {
  const art = special || cover(al, h, 0);
  return `<div class="tile${focus ? ' ftile' : ''}" style="width:${w}px;height:${h}px">${art}<div style="min-width:0;flex:1;padding-right:10px"><div style="font-size:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${label}</div><div style="font-size:12px;color:var(--mut);margin-top:3px;font-weight:400">${sub}</div></div></div>`;
}
const favArt = (s) => `<div class="cov" style="width:${s}px;height:${s}px;background:linear-gradient(135deg,#8F6BFF,#FF5CCF);display:flex;align-items:center;justify-content:center;box-shadow:none">${ic('heart', s * 0.42, '#fff')}</div>`;

function home() {
  const body = `${topBar(W)}
  <div style="position:absolute;left:${M}px;right:${M}px;top:104px">
    <div class="row" style="justify-content:space-between">
      <div class="o" style="font-size:40px">Música</div>
      <div class="search" style="width:380px;height:46px;padding:0 18px;font-size:16px">${ic('search', 22)}Artistas, canciones o álbumes</div>
    </div>
    <div style="margin-top:26px">${shelfHead('Sigue escuchando', '', { fs: 22 })}
      <div style="display:grid;grid-template-columns:repeat(4,268px);gap:12px 16px">
        ${tile('faroles', 'Faroles', 'Álbum · Los Faroleros', { focus: true })}
        ${tile(null, 'Tus favoritas', 'Lista · 128 canciones', { special: favArt(64) })}
        ${tile('brillo', 'Brillo', 'Álbum · Clara Vega')}
        ${tile('marea', 'Mezcla 2', 'DJ Marea, Nube Roja y más')}
        ${tile('verano', 'Verano', 'Álbum · Lola Brisa')}
        ${tile('nube', 'Cielo rojo', 'Álbum · Nube Roja')}
        ${tile('limon', 'Para la cena', 'Lista de Marta')}
        ${tile('norte', 'Norte', 'Álbum · Rumba Norte')}
      </div></div>
    <div style="margin-top:34px">${shelfHead('Tus mezclas', 'Lo que más escuchas, mezclado con lo que te puede gustar', { fs: 22 })}
      <div class="shelf">
        ${mixCard(1, 172, 'brillo', ['Clara Vega', 'Lola Brisa'])}
        ${mixCard(2, 172, 'marea', ['DJ Marea', 'Nube Roja'])}
        ${mixCard(3, 172, 'limon', ['Sal y Limón', 'Rumba Norte'])}
        ${mixCard(4, 172, 'lunas', ['Tres Lunas', 'Los Faroleros'])}
        ${mixCard(5, 172, 'faroles', ['Los Faroleros', 'Clara Vega'])}
        ${mixCard(6, 172, 'norte', ['Rumba Norte', 'DJ Marea'])}
      </div></div>
  </div>`;
  return { name: 'tele_inicio', w: W, h: H, html: page(W, H, body, 'background:radial-gradient(ellipse 70% 50% at 15% 0%,rgba(143,107,255,.22),transparent 70%),#0B0B0F') };
}

function homeSide() {
  const X = 128;
  const top = [['verano', 'Verano', 'Lola Brisa'], ['limon', 'Fuego', 'Sal y Limón'], ['faroles', 'Calle', 'Los Faroleros'], ['marea', 'Volver', 'DJ Marea'],
    ['primavera', 'Primavera', 'Nube Roja'], ['brillo', 'Brillo', 'Clara Vega'], ['norte', 'Latido', 'Rumba Norte'], ['lunas', 'Noche', 'Tres Lunas'],
    ['luna', 'Luna', 'Sal y Limón'], ['orilla', 'Lluvia', 'Lola Brisa'], ['madrid', 'Madrid', 'DJ Marea'], ['bailar', 'Contigo', 'Rumba Norte']];
  const col = (k) => `<div style="width:340px;display:flex;flex-direction:column;gap:6px">${top.slice(k * 4, k * 4 + 4).map(([al, t, a], i) =>
    songRow({ n: k * 4 + i + 1, al, t, a, cov: 52, fs: 16, focus: k === 0 && i === 2 })).join('')}</div>`;
  const body = `${sideRail(H)}
  <div style="position:absolute;left:${X}px;right:0;top:44px">
    <div style="padding-right:48px">${shelfHead('Top España', 'Lo más escuchado ahora en España', { fs: 24, play: 40 })}</div>
    <div class="row" style="gap:20px;align-items:flex-start">${col(0)}${col(1)}${col(2)}</div>
    <div style="margin-top:34px;padding-right:48px">${shelfHead('Porque escuchas a Lola Brisa', 'Artistas parecidos a los que más escuchas', { fs: 24 })}</div>
    <div class="shelf">${artistCard('Lola Brisa', 168, { sub: 'Mezcla de la artista' })}${card('norte', 168)}${card('bailar', 168)}${card('sal', 168)}${card('orilla', 168)}${card('primavera', 168)}</div>
  </div>
  ${capsule({ w: 400, h: 68, pos: 'right:40px;bottom:28px' })}`;
  return { name: 'tele_lateral_inicio', w: W, h: H, html: page(W, H, body, 'background:radial-gradient(ellipse 60% 45% at 30% 0%,rgba(255,92,207,.14),transparent 70%),#0B0B0F') };
}

function album(key, { away, focus }) {
  const a = AL[key];
  const tr = TRACKS[key];
  const body = `${topBar(W)}
  <div style="position:absolute;left:${M}px;top:104px">${cover(key, 296, 12, 'box-shadow:0 24px 60px rgba(0,0,0,.6)')}</div>
  <div style="position:absolute;left:${M + 296 + 44}px;right:${M}px;top:104px;height:296px;display:flex;flex-direction:column;justify-content:flex-end">
    <div class="kick">Álbum · ${a.y}</div>
    <div class="o" style="font-size:64px;line-height:1.05;margin-top:6px">${a.t}</div>
    <div class="row" style="gap:10px;margin-top:12px;font-size:19px;font-weight:500">${portrait(a.a, 30)}${a.a}<span style="color:var(--mut);font-weight:400;font-size:16px">· 10 canciones · 33 min</span></div>
    <div class="row" style="gap:18px;margin-top:22px">${playBtn(68, { focus: focus === 'play' })}${roundBtn('shuffle', 50)}${roundBtn('heartO', 50)}${roundBtn('more', 50)}</div>
    <div style="height:56px;margin-top:16px;display:flex;align-items:center">${away ? awayNote({ fs: 15, btnFocus: focus === 'ask' }) : ''}</div>
  </div>
  <div style="position:absolute;left:${M - 12}px;right:${M - 12}px;top:426px;display:grid;grid-template-columns:1fr 1fr;grid-template-rows:repeat(5,auto);grid-auto-flow:column;gap:2px 28px">
    ${tr.map(([t, d], i) => songRow({ n: i + 1, t, d, fs: 17 })).join('')}
  </div>`;
  return { name: `tele_album_${away ? 'fuera' : 'casa'}`, w: W, h: H, html: page(W, H, body, wash(a.c[0], 0.42, '10% 0%')) };
}

function artist() {
  const songs = [['verano', 'Verano', '1,2 M'], ['orilla', 'Lluvia', '820 mil'], ['sal', 'Agua de sal', '640 mil'], ['verano', 'Vuelo en ti', '410 mil'], ['orilla', 'La orilla', '380 mil'], ['sal', 'Noche', '290 mil']];
  const body = `<div style="position:absolute;left:0;top:0;width:${W}px;height:400px">${bigPortrait('Lola Brisa', W, 400)}
    <div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(11,11,15,0) 40%,#0B0B0F 100%),linear-gradient(90deg,rgba(11,11,15,.7),transparent 60%)"></div></div>
  ${topBar(W)}
  <div style="position:absolute;left:${M}px;top:170px">
    <div class="kick">Artista</div>
    <div class="o" style="font-size:84px;line-height:1;margin-top:6px">Lola Brisa</div>
    <div style="color:var(--mut);font-size:16px;margin-top:10px">Pop · 4 álbumes · Te gusta desde 2024</div>
    <div class="row" style="gap:18px;margin-top:22px">${playBtn(64)}${pill('Mezcla de Lola Brisa', 'shuffle', { size: 'l' })}${roundBtn('heart', 52, { color: '#FF5CCF' })}</div>
  </div>
  <div style="position:absolute;left:${M - 12}px;right:${M - 12}px;top:420px">
    <div style="padding-left:12px">${shelfHead('Populares', '', { fs: 24 })}</div>
    <div style="display:grid;grid-template-columns:1fr 1fr;grid-template-rows:repeat(3,auto);grid-auto-flow:column;gap:4px 28px">
      ${songs.map(([al, t, p], i) => songRow({ n: i + 1, al, t, plays: p, cov: 48, fs: 17, focus: i === 3, d: ['3:12', '3:40', '2:58', '3:31', '3:05', '3:18'][i] })).join('')}
    </div>
  </div>`;
  return { name: 'tele_artista', w: W, h: H, html: page(W, H, body) };
}

function nowPlaying() {
  const a = AL.faroles;
  const bg = `background:radial-gradient(ellipse 70% 90% at 10% 20%,${a.c[0]}99,transparent 70%),radial-gradient(ellipse 80% 90% at 90% 100%,${a.c[1]},transparent 70%),#08120F;`;
  const body = `<div style="position:absolute;inset:0;background:rgba(0,0,0,.35)"></div>
  <div style="position:absolute;left:96px;top:96px">${cover('faroles', 400, 16, 'box-shadow:0 40px 90px rgba(0,0,0,.55)')}</div>
  <div style="position:absolute;left:560px;right:96px;top:96px;height:400px;display:flex;flex-direction:column;justify-content:center">
    <div class="kick" style="color:rgba(243,245,250,.7)">Sonando · Faroles</div>
    <div class="o" style="font-size:64px;line-height:1.05;margin-top:8px">Calle</div>
    <div style="font-size:24px;color:rgba(243,245,250,.75);margin-top:8px">Los Faroleros</div>
    <div class="chip" style="margin-top:20px;height:40px;padding:0 6px 0 14px;font-size:15px;align-self:flex-start">${ic('wave', 17, 'rgba(243,245,250,.7)')}<span>Suena en streaming · no está en casa</span><span class="lnk" style="padding:7px 12px">${ic('ask', 16, '#F3F5FA')}Pedir el álbum</span></div>
    <div style="margin-top:34px"><div class="prog"><i style="width:31%"></i><b style="left:31%"></b></div><div class="times"><span>0:56</span><span>-2:04</span></div></div>
    <div class="row" style="gap:34px;margin-top:22px;justify-content:center">
      ${ic('shuffle', 28, 'rgba(243,245,250,.7)')}${ic('prev', 40)}${playBtn(84, { pause: true, focus: true })}${ic('next', 40)}${ic('repeat', 28, 'rgba(243,245,250,.7)')}
    </div>
  </div>
  <div style="position:absolute;left:96px;right:96px;bottom:40px;display:flex;align-items:center;justify-content:space-between">
    <div class="row" style="gap:12px;color:var(--mut);font-size:15px">${cover('faroles', 40, 6)}<div><div style="color:var(--dim);font-size:12px;letter-spacing:.08em;text-transform:uppercase;font-weight:500">A continuación</div><div style="color:var(--ink);font-weight:500;margin-top:2px">Luna de noche · Los Faroleros</div></div></div>
    <div class="row" style="gap:14px">${roundBtn('heartO', 48)}${roundBtn('lyrics', 48)}${roundBtn('queue', 48)}${roundBtn('more', 48)}</div>
  </div>`;
  return { name: 'tele_reproductor', w: W, h: H, html: page(W, H, body, bg) };
}

function searchScr() {
  const songs = [['luna', 'Luna', 'Sal y Limón', '3:02'], ['faroles', 'Luna de noche', 'Los Faroleros', '3:07'], ['lunas', 'Media luna', 'Tres Lunas', '2:51'], ['brillo', 'Luna llena', 'Clara Vega', '3:33']];
  const body = `${topBar(W, { active: 'note' })}
  <div style="position:absolute;left:${M}px;right:${M}px;top:104px">
    <div class="search" style="width:100%;height:50px;padding:0 22px;font-size:20px;color:var(--ink);background:rgba(255,255,255,.12)">${ic('search', 26)}luna<span style="width:2px;height:26px;background:var(--ink);margin-left:-8px"></span></div>
    <div class="row" style="gap:40px;margin-top:28px;align-items:flex-start">
      <div style="width:400px">${shelfHead('Lo mejor', '', { fs: 22 })}
        <div style="background:rgba(255,255,255,.07);border-radius:14px;padding:22px;height:226px;position:relative">
          ${cover('luna', 110, 10)}<div class="o" style="font-size:34px;margin-top:18px">Luna</div>
          <div style="color:var(--mut);margin-top:4px;font-size:15px">Álbum · Sal y Limón · 2026</div>
          <div style="position:absolute;right:22px;bottom:22px">${playBtn(56)}</div></div></div>
      <div style="flex:1">${shelfHead('Canciones', '', { fs: 22 })}
        <div style="display:flex;flex-direction:column;gap:4px;margin-left:-12px">${songs.map(([al, t, a, d], i) => songRow({ al, t, a, d, cov: 48, fs: 17, focus: i === 1 })).join('')}</div></div>
    </div>
    <div style="margin-top:24px">${shelfHead('Artistas y álbumes', '', { fs: 22 })}
      <div class="shelf">${artistCard('Sal y Limón', 116)}${artistCard('Tres Lunas', 116)}${card('luna', 116)}${card('madrid', 116, { title: 'Luna de Madrid' })}${card('faroles', 116)}${card('nube', 116, { title: 'Luna roja' })}${card('marea', 116, { title: 'Lunática' })}${card('brillo', 116, { title: 'Lunes' })}</div></div>
  </div>`;
  return { name: 'tele_buscador', w: W, h: H, html: page(W, H, body) };
}

module.exports = () => [home(), homeSide(), album('brillo', { away: false, focus: 'play' }), album('faroles', { away: true, focus: 'ask' }), artist(), nowPlaying(), searchScr()];
module.exports.TRACKS = TRACKS;
module.exports.tile = tile;
module.exports.favArt = favArt;
