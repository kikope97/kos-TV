const L = require('./lib');
const { ic, cover, playBtn, roundBtn, pill, songRow, card, awayNote, capsule, page } = L;
const W = 1440, H = 900;
const lab = (t) => `<div style="color:var(--dim);font-size:12px;letter-spacing:.1em;text-transform:uppercase;font-weight:500;margin-bottom:12px">${t}</div>`;
const cap = (t) => `<div style="color:var(--mut);font-size:12px;margin-top:8px;text-align:center">${t}</div>`;
const box = (w, inner) => `<div style="width:${w}px;padding:22px;border-radius:16px;background:rgba(255,255,255,.04);box-shadow:inset 0 0 0 1px rgba(255,255,255,.06)">${inner}</div>`;
module.exports = () => {
  const chip = (f) => `<div class="chip" style="height:36px;padding:0 4px 0 12px;font-size:13.5px;background:rgba(255,255,255,.08)">${ic('wave', 16, 'rgba(243,245,250,.7)')}<span>Suena en streaming · no está en casa</span><span class="lnk${f ? ' f' : ''}" style="padding:6px 11px">${ic('ask', 15, f ? '#0B0B0F' : '#F3F5FA')}Pedir el álbum</span></div>`;
  const body = `<div style="position:absolute;left:48px;top:36px;right:48px">
  <div class="row" style="justify-content:space-between;align-items:flex-end"><div><div class="o" style="font-size:34px">Música · piezas</div><div style="color:var(--mut);font-size:15px;margin-top:4px">Lo mismo en la tele, el móvil y la web. Lo de casa y lo de fuera se ven igual.</div></div>
  <div class="row" style="gap:10px">${['#4FD8FF', '#8F6BFF', '#FF5CCF', '#F3F5FA', '#0B0B0F'].map((c) => `<div style="width:34px;height:34px;border-radius:50%;background:${c};box-shadow:inset 0 0 0 1px rgba(255,255,255,.2)"></div>`).join('')}</div></div>
  <div class="row" style="gap:20px;margin-top:26px;align-items:stretch">
    ${box(430, `${lab('1 · Un solo botón de reproducir')}<div class="row" style="gap:26px;align-items:flex-end;justify-content:space-around;height:110px">
      <div>${playBtn(84, { pause: true })}${cap('Reproductor')}</div><div>${playBtn(64)}${cap('Álbum')}</div><div>${playBtn(44)}${cap('Tarjeta')}</div><div>${playBtn(32)}${cap('Fila')}</div><div style="padding-bottom:4px">${playBtn(56, { focus: true })}${cap('Foco tele')}</div></div>`)}
    ${box(450, `${lab('2 · Filas de canción: sin botón, igual en casa o fuera')}<div style="margin:0 -12px">
      ${songRow({ n: 1, al: 'verano', t: 'Verano', a: 'Lola Brisa · en casa', d: '3:12' })}
      ${songRow({ n: 2, al: 'faroles', t: 'Calle', a: 'Los Faroleros · fuera de casa', d: '3:00' })}
      ${songRow({ n: 3, al: 'brillo', t: 'Brillo', a: 'Sonando', d: '2:58', playing: true })}
      ${songRow({ n: 4, al: 'norte', t: 'Latido', a: 'Con foco (tele) o ratón encima', d: '3:09', focus: true })}</div>`)}
    ${box(420, `${lab('3 · Tarjetas')}<div class="row" style="gap:26px;justify-content:center;padding-top:6px">${card('brillo', 112, { sub: 'Normal' })}${card('faroles', 112, { focus: true, sub: 'Foco tele', playS: 34 })}${card('norte', 112, { hover: true, sub: 'Ratón encima', playS: 34 })}</div>`)}
  </div>
  <div class="row" style="gap:20px;margin-top:20px;align-items:stretch">
    ${box(780, `${lab('4 · Nota del álbum (solo si no está en casa) y sus estados')}
      ${awayNote({ fs: 15 })}<div style="height:16px"></div>
      <div class="row" style="gap:12px;flex-wrap:wrap">${pill('Pedir el álbum', 'ask')}${pill('Pedir el álbum', 'ask', { focus: true })}${pill('Pedido · te avisamos', 'check', { kind: 'quiet' })}${pill('De camino', 'truck', { kind: 'quiet' })}${pill('Ya está en casa', 'home', { kind: 'quiet' })}</div>
      <div style="color:var(--dim);font-size:13px;margin-top:12px">Cuando llega a casa, la nota desaparece sola. «Ya está en casa» solo se ve un momento, como aviso.</div>`)}
    ${box(540, `${lab('5 · Línea del reproductor')}${chip(false)}<div style="height:12px"></div>${chip(true)}<div style="color:var(--dim);font-size:13px;margin-top:12px">Abajo: «Pedir el álbum» con foco en la tele.</div>`)}
  </div>
  <div class="row" style="gap:20px;margin-top:20px;align-items:stretch">
    ${box(560, `${lab('6 · Cápsula (sin marcas de casa o fuera)')}<div style="position:relative;height:70px">${capsule({ w: 500, h: 66, pos: 'left:0;top:0' })}</div>`)}
    ${box(760, `${lab('7 · Letras')}<div class="row" style="gap:28px;align-items:baseline">
      <div class="o" style="font-size:44px">Faroles</div><div class="o" style="font-size:24px">Tus mezclas</div><div style="font-size:16px;font-weight:500">Calle</div><div style="font-size:14px;color:var(--mut)">Los Faroleros</div><div class="kick">Álbum · 2026</div></div>
      <div style="color:var(--dim);font-size:13px;margin-top:10px">Outfit Bold para títulos (marca) · Roboto para todo lo demás</div>`)}
  </div></div>`;
  return [{ name: 'componentes', w: W, h: H, html: page(W, H, body) }];
};
