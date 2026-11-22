const L = require('./lib');
const { ic, AL, cover, portrait, bigPortrait, playBtn, roundBtn, pill, songRow, card, artistCard, mixCard, shelfHead, awayNote, capsule, topBar, page, wash } = L;
const { TRACKS, tile, favArt } = require('./tv');
const W = 1440, H = 900, M = 56;
const cursor = (x, y) => `<svg class="cursor" style="left:${x}px;top:${y}px" width="22" height="22" viewBox="0 0 24 24"><path d="M5 3l14 8-6 1.5L10 19z" fill="#fff" stroke="#000" stroke-width="1.2"/></svg>`;

function discovery(s, r = 10) {
  return `<div class="card" style="width:${s}px"><div class="cwrap" style="border-radius:${r}px;width:${s}px;height:${s}px;background:linear-gradient(140deg,#4FD8FF 0%,#8F6BFF 50%,#FF5CCF 100%);position:relative">
    <div style="position:absolute;left:9%;bottom:12%;right:9%"><div style="font-family:Outfit;font-weight:300;font-size:${s * 0.08}px;letter-spacing:.2em;text-transform:uppercase;color:rgba(255,255,255,.85)">Cada lunes</div><div class="o" style="font-size:${s * 0.15}px;line-height:1;margin-top:4px">Descubri&shy;miento</div></div></div>
    <div class="ct">Descubrimiento semanal</div><div class="cs">Canciones nuevas para ti</div></div>`;
}

function home() {
  const body = `${topBar(W, { s: 0.95 })}
  <div style="position:absolute;left:${M}px;right:${M}px;top:100px">
    <div class="row" style="justify-content:space-between"><div class="o" style="font-size:44px">Música</div>
      <div class="search" style="width:420px;height:46px;padding:0 18px;font-size:16px">${ic('search', 22)}Artistas, canciones o álbumes</div></div>
    <div style="margin-top:26px">${shelfHead('Sigue escuchando', '', { fs: 22 })}
      <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:12px 16px">
        ${tile('faroles', 'Faroles', 'Álbum · Los Faroleros', { w: 'auto' })}${tile(null, 'Tus favoritas', 'Lista · 128 canciones', { w: 'auto', special: favArt(64) })}${tile('brillo', 'Brillo', 'Álbum · Clara Vega', { w: 'auto' })}${tile('marea', 'Mezcla 2', 'DJ Marea, Nube Roja y más', { w: 'auto' })}
        ${tile('verano', 'Verano', 'Álbum · Lola Brisa', { w: 'auto' })}${tile('nube', 'Cielo rojo', 'Álbum · Nube Roja', { w: 'auto' })}${tile('limon', 'Para la cena', 'Lista de Marta', { w: 'auto' })}${tile('norte', 'Norte', 'Álbum · Rumba Norte', { w: 'auto' })}
      </div></div>
    <div style="margin-top:34px">${shelfHead('Para ti', 'Hecho con lo que escuchas en casa', { fs: 22, more: 'Ver todo' })}
      <div class="shelf" style="gap:24px">${discovery(190)}${mixCard(1, 190, 'brillo', ['Clara Vega', 'Lola Brisa'])}${card('norte', 190, { hover: true, sub: 'Rumba Norte · Te puede gustar', playS: 48 })}${card('nube', 190)}${card('luna', 190)}${card('orilla', 190)}</div></div>
    <div style="margin-top:34px">${shelfHead('Novedades de tus artistas', '', { fs: 22 })}<div class="shelf" style="gap:24px">${['madrid', 'sal', 'primavera', 'bailar', 'lunas', 'limon'].map((k) => card(k, 190)).join('')}</div></div>
  </div>
  ${cursor(600, 560)}
  ${capsule({ w: 420, h: 66, pos: 'right:32px;bottom:26px' })}`;
  return { name: 'ordenador_inicio', w: W, h: H, html: page(W, H, body, 'background:radial-gradient(ellipse 70% 45% at 15% 0%,rgba(143,107,255,.22),transparent 70%),#0B0B0F') };
}

function album(key, away) {
  const a = AL[key];
  const tr = TRACKS[key];
  const body = `${topBar(W, { s: 0.95 })}
  <div style="position:absolute;left:${M}px;top:104px">${cover(key, 280, 12, 'box-shadow:0 24px 60px rgba(0,0,0,.6)')}</div>
  <div style="position:absolute;left:${M + 280 + 40}px;right:${M}px;top:104px;height:280px;display:flex;flex-direction:column;justify-content:flex-end">
    <div class="kick">Álbum · ${a.y}</div>
    <div class="o" style="font-size:68px;line-height:1.05;margin-top:6px">${a.t}</div>
    <div class="row" style="gap:10px;margin-top:10px;font-size:17px;font-weight:500">${portrait(a.a, 28)}${a.a}<span style="color:var(--mut);font-weight:400;font-size:15px">· 10 canciones · 33 min</span></div>
    <div class="row" style="gap:16px;margin-top:20px">${playBtn(60)}${roundBtn('shuffle', 44)}${roundBtn('heartO', 44)}${roundBtn('more', 44)}</div>
  </div>
  <div style="position:absolute;left:${M}px;right:${M}px;top:404px;height:44px">${away ? awayNote({ fs: 14, size: 's' }) : ''}</div>
  <div style="position:absolute;left:${M - 12}px;right:${M - 12}px;top:460px">
    <div class="row" style="padding:0 12px 8px;gap:14px;color:var(--dim);font-size:12px;letter-spacing:.08em;text-transform:uppercase;border-bottom:1px solid rgba(255,255,255,.08);margin-bottom:6px"><span style="width:22px;text-align:center">#</span><span style="flex:1">Título</span><span>Duración</span><span style="width:26px"></span></div>
    ${tr.slice(0, 7).map(([t, d], i) => songRow({ n: i + 1, t, a: a.a, d, fs: 15, focus: false }).replace('</div>\n  </div>', `<span style="width:26px"></span></div>\n  </div>`)).join('')}
  </div>
  <style>.srow:nth-of-type(3){background:rgba(255,255,255,.08)}</style>
  ${cursor(560, 560)}`;
  return { name: `ordenador_album_${away ? 'fuera' : 'casa'}`, w: W, h: H, html: page(W, H, body, wash(a.c[0], 0.42, '10% 0%')) };
}

function artist() {
  const songs = [['verano', 'Verano', '1,2 M', '3:12'], ['orilla', 'Lluvia', '820 mil', '3:40'], ['sal', 'Agua de sal', '640 mil', '2:58'], ['verano', 'Vuelo en ti', '410 mil', '3:31'], ['orilla', 'La orilla', '380 mil', '3:05']];
  const body = `<div style="position:absolute;left:0;top:0;width:${W}px;height:430px">${bigPortrait('Lola Brisa', W, 430)}
    <div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(11,11,15,0) 40%,#0B0B0F 100%),linear-gradient(90deg,rgba(11,11,15,.7),transparent 60%)"></div></div>
  ${topBar(W, { s: 0.95 })}
  <div style="position:absolute;left:${M}px;top:190px">
    <div class="kick">Artista</div><div class="o" style="font-size:92px;line-height:1;margin-top:6px">Lola Brisa</div>
    <div style="color:var(--mut);font-size:15px;margin-top:10px">Pop · 4 álbumes</div>
    <div class="row" style="gap:16px;margin-top:20px">${playBtn(60)}${pill('Mezcla de Lola Brisa', 'shuffle', { size: 'm' })}${roundBtn('heart', 44, { color: '#FF5CCF' })}</div></div>
  <div style="position:absolute;left:${M - 12}px;top:440px;width:760px">
    <div style="padding-left:12px">${shelfHead('Populares', '', { fs: 22 })}</div>
    ${songs.map(([al, t, p, d], i) => songRow({ n: i + 1, al, t, plays: p, d, cov: 40, playing: i === 0 })).join('')}</div>
  <div style="position:absolute;left:${M + 780}px;right:${M}px;top:450px">${shelfHead('Su último disco', '', { fs: 22 })}
    <div class="row" style="gap:18px;align-items:flex-start">${cover('sal', 150, 10)}<div><div class="kick">Álbum · 2024</div><div class="o" style="font-size:26px;margin-top:4px">Agua de sal</div><div style="color:var(--mut);font-size:14px;margin-top:4px">12 canciones</div><div style="margin-top:14px">${playBtn(44)}</div></div></div></div>
  <div style="position:absolute;left:${M}px;right:0;top:790px">${shelfHead('Discografía', '', { fs: 22, more: '' })}<div class="shelf">${['verano', 'sal', 'orilla', 'verano', 'sal', 'orilla', 'verano'].map((k) => cover(k, 150, 10)).join('')}</div></div>`;
  return { name: 'ordenador_artista', w: W, h: H, html: page(W, H, body) };
}

function nowPlaying() {
  const a = AL.faroles;
  const bg = `background:radial-gradient(ellipse 70% 90% at 10% 20%,${a.c[0]}99,transparent 70%),radial-gradient(ellipse 80% 90% at 70% 100%,${a.c[1]},transparent 70%),#08120F;`;
  const q = [['faroles', 'Luna de noche', 'Los Faroleros'], ['faroles', 'Bailar otra vez', 'Los Faroleros'], ['brillo', 'Cielo de noche', 'Clara Vega'], ['norte', 'Latido', 'Rumba Norte'], ['verano', 'Verano', 'Lola Brisa'], ['lunas', 'Noche', 'Tres Lunas'], ['marea', 'Volver', 'DJ Marea']];
  const body = `<div style="position:absolute;inset:0;background:rgba(0,0,0,.3)"></div>
  <div class="row" style="position:absolute;top:24px;left:32px;gap:12px">${roundBtn('down', 40)}</div>
  <div style="position:absolute;left:96px;top:120px">${cover('faroles', 440, 16, 'box-shadow:0 40px 90px rgba(0,0,0,.55)')}</div>
  <div style="position:absolute;left:96px;width:440px;top:590px">
    <div class="row" style="justify-content:space-between"><div><div class="o" style="font-size:40px">Calle</div><div style="font-size:19px;color:rgba(243,245,250,.75);margin-top:4px">Los Faroleros · Faroles</div></div>${ic('heartO', 28)}</div>
    <div class="chip" style="margin-top:14px;height:36px;padding:0 4px 0 12px;font-size:13.5px">${ic('wave', 16, 'rgba(243,245,250,.7)')}<span>Suena en streaming · no está en casa</span><span class="lnk" style="padding:6px 11px">${ic('ask', 15, '#F3F5FA')}Pedir el álbum</span></div>
    <div style="margin-top:22px"><div class="prog"><i style="width:31%"></i><b style="left:31%"></b></div><div class="times"><span>0:56</span><span>-2:04</span></div></div>
    <div class="row" style="justify-content:space-between;margin-top:10px">${ic('shuffle', 24, 'rgba(243,245,250,.75)')}${ic('prev', 36)}${playBtn(70, { pause: true })}${ic('next', 36)}${ic('repeat', 24, 'rgba(243,245,250,.75)')}</div>
  </div>
  <div style="position:absolute;right:32px;top:32px;bottom:32px;width:520px;border-radius:20px;background:rgba(0,0,0,.32);backdrop-filter:blur(30px);padding:24px 16px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08)">
    <div class="row" style="gap:8px;padding:0 8px">${pill('Cola', 'queue', { size: 's' }).replace('pill ghost', 'pill').replace('class="pill s"', 'class="pill s" style="background:var(--ink);color:#0B0B0F"')}${pill('Letra', 'lyrics', { size: 's', kind: 'quiet' })}${pill('Del álbum', '', { size: 's', kind: 'quiet' })}</div>
    <div style="padding:22px 8px 8px" class="kick">Sonando</div>
    ${songRow({ al: 'faroles', t: 'Calle', a: 'Los Faroleros', d: '3:00', cov: 48, playing: true })}
    <div style="padding:18px 8px 8px" class="row"><span class="kick" style="flex:1">A continuación</span><span style="color:var(--mut);font-size:13px">Vaciar</span></div>
    ${q.map(([al, t, aa], i) => songRow({ al, t, a: aa, d: ['3:07', '3:14', '3:22', '3:09', '3:12', '2:51', '3:21'][i], cov: 48 })).join('')}
  </div>`;
  return { name: 'ordenador_reproductor_cola', w: W, h: H, html: page(W, H, body, bg) };
}

function searchScr() {
  const songs = [['luna', 'Luna', 'Sal y Limón', '3:02'], ['faroles', 'Luna de noche', 'Los Faroleros', '3:07'], ['lunas', 'Media luna', 'Tres Lunas', '2:51'], ['brillo', 'Luna llena', 'Clara Vega', '3:33']];
  const body = `${topBar(W, { s: 0.95 })}
  <div style="position:absolute;left:${M}px;right:${M}px;top:100px">
    <div class="search" style="width:560px;height:50px;padding:0 20px;font-size:18px;color:var(--ink);background:rgba(255,255,255,.12)">${ic('search', 22)}luna</div>
    <div class="row" style="gap:8px;margin-top:16px">${'<div class="pill s" style="background:var(--ink);color:#0B0B0F">Todo</div>'}${pill('Canciones', '', { size: 's', kind: 'quiet' })}${pill('Álbumes', '', { size: 's', kind: 'quiet' })}${pill('Artistas', '', { size: 's', kind: 'quiet' })}${pill('Listas', '', { size: 's', kind: 'quiet' })}</div>
    <div class="row" style="gap:40px;margin-top:26px;align-items:flex-start">
      <div style="width:440px">${shelfHead('Lo mejor', '', { fs: 22 })}
        <div style="background:rgba(255,255,255,.07);border-radius:14px;padding:22px;height:250px;position:relative">${cover('luna', 120, 10)}<div class="o" style="font-size:36px;margin-top:18px">Luna</div><div style="color:var(--mut);margin-top:4px;font-size:15px">Álbum · Sal y Limón · 2026</div><div style="position:absolute;right:22px;bottom:22px">${playBtn(56)}</div></div></div>
      <div style="flex:1">${shelfHead('Canciones', '', { fs: 22 })}<div style="margin-left:-12px">${songs.map(([al, t, a, d], i) => songRow({ al, t, a, d, cov: 48, fs: 16 })).join('')}</div></div>
    </div>
    <div style="margin-top:30px">${shelfHead('Artistas', '', { fs: 22 })}<div class="shelf">${artistCard('Sal y Limón', 160)}${artistCard('Tres Lunas', 160)}${artistCard('Clara Vega', 160)}${artistCard('Los Faroleros', 160)}</div></div>
  </div>
  <style>.srow:nth-of-type(2){}</style>`;
  return { name: 'ordenador_buscador', w: W, h: H, html: page(W, H, body) };
}

module.exports = () => [home(), album('brillo', false), album('faroles', true), artist(), nowPlaying(), searchScr()];
