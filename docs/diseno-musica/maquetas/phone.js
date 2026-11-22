const L = require('./lib');
const { ic, AL, cover, portrait, bigPortrait, playBtn, roundBtn, pill, songRow, card, artistCard, mixCard, shelfHead, awayNote, capsule, phoneTop, phoneBottom, status, page, wash } = L;
const { TRACKS, favArt } = require('./tv');
const W = 393, H = 852, M = 16;

function ptile(al, label, { special } = {}) {
  return `<div class="tile" style="height:52px;gap:10px">${special || cover(al, 52, 0)}<div style="font-size:13px;line-height:1.2;padding-right:8px">${label}</div></div>`;
}

function home() {
  const body = `${status()}${phoneTop()}
  <div style="position:absolute;left:${M}px;right:${M}px;top:100px">
    <div class="row" style="justify-content:space-between"><div class="o" style="font-size:34px">Música</div>${roundBtn('search', 42)}</div>
    <div class="row" style="gap:8px;margin-top:14px">${pill('Para ti', '', { size: 's', kind: 'quiet' }).replace('quiet', 'ghost')}${pill('Tus listas', '', { size: 's', kind: 'quiet' })}${pill('Artistas', '', { size: 's', kind: 'quiet' })}${pill('Álbumes', '', { size: 's', kind: 'quiet' })}</div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:16px">
      ${ptile('faroles', 'Faroles')}${ptile(null, 'Tus favoritas', { special: favArt(52) })}${ptile('brillo', 'Brillo')}${ptile('marea', 'Mezcla 2')}${ptile('verano', 'Verano')}${ptile('nube', 'Cielo rojo')}
    </div>
    <div style="margin-top:28px">${shelfHead('Tus mezclas', 'Lo que más escuchas, mezclado', { fs: 21 })}
      <div class="shelf" style="gap:14px">${mixCard(1, 150, 'brillo', ['Clara Vega', 'Lola Brisa'])}${mixCard(2, 150, 'marea', ['DJ Marea', 'Nube Roja'])}${mixCard(3, 150, 'limon', ['Sal y Limón', 'Rumba Norte'])}</div></div>
    <div style="margin-top:26px">${shelfHead('Top España', 'Lo más escuchado ahora', { fs: 21, play: 32 })}
      <div style="margin-left:-12px">${songRow({ n: 1, al: 'verano', t: 'Verano', a: 'Lola Brisa', cov: 46 })}${songRow({ n: 2, al: 'limon', t: 'Fuego', a: 'Sal y Limón', cov: 46 })}</div></div>
  </div>
  ${capsule({ w: W - 20, h: 62, pos: 'left:10px;bottom:22px' })}`;
  return { name: 'movil_inicio', w: W, h: H, html: page(W, H, body, 'background:radial-gradient(ellipse 90% 40% at 20% 0%,rgba(143,107,255,.25),transparent 70%),#0B0B0F') };
}

function album(key, away) {
  const a = AL[key];
  const tr = TRACKS[key];
  const body = `${status()}
  <div class="row" style="position:absolute;top:50px;left:12px;right:12px;justify-content:space-between">${roundBtn('back', 38)}${roundBtn('more', 38)}</div>
  <div style="position:absolute;top:100px;left:0;right:0;display:flex;justify-content:center">${cover(key, 250, 12, 'box-shadow:0 26px 60px rgba(0,0,0,.55)')}</div>
  <div style="position:absolute;top:372px;left:${M}px;right:${M}px">
    <div class="o" style="font-size:30px;line-height:1.1">${a.t}</div>
    <div class="row" style="gap:8px;margin-top:8px;font-size:15px;font-weight:500">${portrait(a.a, 22)}${a.a}</div>
    <div style="color:var(--mut);font-size:13px;margin-top:6px">Álbum · ${a.y} · 10 canciones · 33 min</div>
    <div class="row" style="justify-content:space-between;margin-top:12px">
      <div class="row" style="gap:6px;margin-left:-8px">${roundBtn('heartO', 40, { glass: false })}${roundBtn('more', 40, { glass: false })}</div>
      <div class="row" style="gap:14px">${roundBtn('shuffle', 40, { glass: false })}${playBtn(56)}</div></div>
    <div style="min-height:${away ? 0 : 0}px">${away ? `<div style="margin-top:12px;padding:12px 14px;border-radius:12px;background:rgba(255,255,255,.06)">${awayNote({ fs: 13, size: 's', compact: true })}</div>` : ''}</div>
    <div style="margin:${away ? 10 : 14}px -12px 0">${tr.slice(0, 6).map(([t, d], i) => songRow({ n: i + 1, t, a: a.a, fs: 15 })).join('')}</div>
  </div>`;
  return { name: `movil_album_${away ? 'fuera' : 'casa'}`, w: W, h: H, html: page(W, H, body, wash(a.c[0], 0.5, '50% 0%')) };
}

function artist() {
  const songs = [['verano', 'Verano', '1,2 M'], ['orilla', 'Lluvia', '820 mil'], ['sal', 'Agua de sal', '640 mil'], ['verano', 'Vuelo en ti', '410 mil'], ['orilla', 'La orilla', '380 mil']];
  const body = `<div style="position:absolute;left:0;top:0;width:${W}px;height:380px">${bigPortrait('Lola Brisa', W, 380)}<div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(11,11,15,0) 45%,#0B0B0F 100%)"></div></div>
  ${status()}<div style="position:absolute;top:50px;left:12px">${roundBtn('back', 38)}</div>
  <div style="position:absolute;left:${M}px;right:${M}px;top:272px">
    <div class="o" style="font-size:46px;line-height:1">Lola Brisa</div>
    <div style="color:var(--mut);font-size:13px;margin-top:8px">Pop · 4 álbumes</div>
    <div class="row" style="justify-content:space-between;margin-top:12px">
      <div class="row" style="gap:10px">${pill('Mezcla', 'shuffle', { size: 's' })}${roundBtn('heart', 36, { color: '#FF5CCF' })}</div>${playBtn(56)}</div>
    <div style="margin-top:20px">${shelfHead('Populares', '', { fs: 21 })}<div style="margin-left:-12px">${songs.map(([al, t, p], i) => songRow({ n: i + 1, al, t, a: p + ' escuchas', cov: 44, playing: i === 0 })).join('')}</div></div>
    <div style="margin-top:20px">${shelfHead('Discografía', '', { fs: 21, more: 'Ver todo' })}<div class="shelf" style="gap:14px">${card('verano', 140)}${card('sal', 140)}${card('orilla', 140)}</div></div>
  </div>`;
  return { name: 'movil_artista', w: W, h: H, html: page(W, H, body) };
}

function nowPlaying() {
  const a = AL.faroles;
  const bg = `background:linear-gradient(180deg,${a.c[0]}cc 0%,${a.c[1]} 55%,#060A14 100%);`;
  const body = `${status()}<div style="position:absolute;inset:0;background:rgba(0,0,0,.25)"></div>
  <div class="row" style="position:absolute;top:50px;left:14px;right:14px;justify-content:space-between">${ic('down', 30)}<div style="text-align:center"><div style="font-size:11px;color:rgba(243,245,250,.7);letter-spacing:.08em;text-transform:uppercase;font-weight:500">Sonando desde</div><div style="font-size:14px;font-weight:500;margin-top:2px">Faroles</div></div>${ic('more', 26)}</div>
  <div style="position:absolute;top:116px;left:24px">${cover('faroles', 345, 14, 'box-shadow:0 30px 70px rgba(0,0,0,.45)')}</div>
  <div style="position:absolute;top:492px;left:24px;right:24px">
    <div class="row" style="justify-content:space-between"><div><div class="o" style="font-size:28px">Calle</div><div style="font-size:17px;color:rgba(243,245,250,.75);margin-top:4px">Los Faroleros</div></div>${ic('heartO', 28)}</div>
    <div class="chip" style="margin-top:14px;height:34px;padding:0 4px 0 12px;font-size:12.5px">${ic('wave', 15, 'rgba(243,245,250,.7)')}<span>En streaming · no está en casa</span><span class="lnk" style="padding:6px 10px">${ic('ask', 14, '#F3F5FA')}Pedir el álbum</span></div>
    <div style="margin-top:20px"><div class="prog"><i style="width:31%"></i><b style="left:31%"></b></div><div class="times"><span>0:56</span><span>-2:04</span></div></div>
    <div class="row" style="justify-content:space-between;margin-top:14px">${ic('shuffle', 26, 'rgba(243,245,250,.75)')}${ic('prev', 40)}${playBtn(76, { pause: true })}${ic('next', 40)}${ic('repeat', 26, 'rgba(243,245,250,.75)')}</div>
    <div class="row" style="justify-content:space-between;margin-top:26px;color:rgba(243,245,250,.75)">${ic('cast', 22)}<div class="row" style="gap:28px">${ic('lyrics', 22)}${ic('queue', 24)}</div></div>
  </div>`;
  return { name: 'movil_reproductor', w: W, h: H, html: page(W, H, body, bg) };
}

function searchScr() {
  const songs = [['luna', 'Luna', 'Sal y Limón'], ['faroles', 'Luna de noche', 'Los Faroleros'], ['lunas', 'Media luna', 'Tres Lunas'], ['brillo', 'Luna llena', 'Clara Vega']];
  const body = `${status()}
  <div style="position:absolute;left:${M}px;right:${M}px;top:54px">
    <div class="search" style="height:44px;padding:0 14px;font-size:16px;color:var(--ink);background:rgba(255,255,255,.12)">${ic('search', 20)}luna<span style="flex:1"></span>${ic('close', 18, 'rgba(243,245,250,.6)')}</div>
    <div class="row" style="gap:8px;margin-top:12px">${pill('Todo', '', { size: 's', kind: 'ghost' }).replace('class="pill ghost s"', 'class="pill s" style="background:var(--ink);color:#0B0B0F"')}${pill('Canciones', '', { size: 's', kind: 'quiet' })}${pill('Álbumes', '', { size: 's', kind: 'quiet' })}${pill('Artistas', '', { size: 's', kind: 'quiet' })}</div>
    <div style="margin-top:18px">${shelfHead('Lo mejor', '', { fs: 19 })}
      <div class="row" style="gap:14px;background:rgba(255,255,255,.07);border-radius:12px;padding:12px">${cover('luna', 84, 8)}<div style="flex:1"><div class="o" style="font-size:24px">Luna</div><div style="color:var(--mut);font-size:13px;margin-top:3px">Álbum · Sal y Limón</div></div>${playBtn(44)}</div></div>
    <div style="margin-top:18px">${shelfHead('Canciones', '', { fs: 19 })}<div style="margin-left:-12px">${songs.map(([al, t, a]) => songRow({ al, t, a, cov: 46 })).join('')}</div></div>
    <div style="margin-top:14px">${shelfHead('Artistas', '', { fs: 19 })}<div class="shelf" style="gap:14px">${artistCard('Sal y Limón', 96)}${artistCard('Tres Lunas', 96)}${artistCard('Clara Vega', 96)}</div></div>
  </div>
  ${capsule({ al: 'brillo', t: 'Brillo', a: 'Clara Vega', w: W - 20, h: 58, pos: 'left:10px;bottom:94px' })}
  ${phoneBottom()}`;
  return { name: 'movil_buscador_barra_abajo', w: W, h: H, html: page(W, H, body) };
}

module.exports = () => [home(), album('brillo', false), album('faroles', true), artist(), nowPlaying(), searchScr()];
