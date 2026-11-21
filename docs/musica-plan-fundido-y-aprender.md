# Plan: música sin cortes, «Fundir canciones» y música que aprende de verdad

Sigue a `docs/musica-recomendaciones.md` (partes A–D). Este documento detalla la
parte D («aprender de verdad») y añade la reproducción sin cortes y el fundido.
Todo va en tele, móvil y web; lo único que queda a medias es el fundido en el
iPhone (web), por límites de Safari.

## 1. Cómo está hoy

### Paso de una canción a otra

- La música usa el mismo `PlaybackManager` que el vídeo
  (`packages/playback_core/lib/src/playback_manager.dart`). Suena **una canción
  cada vez**, sin lista en el reproductor:
  - Android (tele y móvil): Media3/ExoPlayer con un único elemento
    (`Media3VideoView.kt`, `setMediaItem` + `prepare`).
  - Web: media_kit, un único elemento `<video>` al que se cambia el `src`.
- Al acabar una canción (`_autoNext`, `playback_manager.dart:2936`) se para el
  reproductor, se avanza la cola, se vuelve a pedir `PlaybackInfo` al servidor
  y se arranca de cero, esperando el búfer. **No se precarga nada.**
- Silencio esperado entre canciones: unos 0,5–2 s con reproducción directa y
  2–5 s si el servidor convierte (HLS). Es una estimación; se mide en el aparato.

### Lo que se aprende

- El complemento apunta cada escucha con mucho detalle: cómo acabó
  (`completed`, `skipped`, `stopped`), por qué (`endedBy`), de dónde venía
  (`source`), la sesión y la anterior, el aparato, aleatorio o repetición,
  repeticiones y vueltas atrás. También ♥, añadidos a listas, peticiones,
  `dislike` (aceptado, nadie lo manda) y lo enseñado (`shown`).
- **Del historial solo se usa cómo acabó y la fecha**
  (`KostvMusicEngine.Listens`: entera +1, parada +0,4, saltada −0,6, la mitad
  cada 30 días). Todo lo demás está guardado y sin usar.
- **Hay dos gustos distintos:**
  - el complemento calcula uno para el Mix diario, la Mezcla del momento y las
    semillas del Descubrimiento;
  - la app calcula otro para «Para ti» (`KostvMusicTaste.of`): las 300 más
    puestas según Jellyfin, solo el primer artista, sin fechas, saltos ni ♥.
- La radio de una canción o artista y la reproducción automática (∞) usan el
  InstantMix de Jellyfin tal cual (casi aleatorio dentro de los géneros), sin
  gustos ni saltos.
- El orden de las filas de Música está fijo en el código.
- Stremfin no acepta pesos ni exclusiones: todo el aprendizaje está en **qué
  semillas le mandamos y cómo filtramos y ordenamos lo que devuelve**. Tiene
  límite de 10 peticiones por minuto y caché de una hora por conjunto de
  artistas.

## 2. Parte 3: sin cortes y «Fundir canciones»

### Qué verá la familia

- **Sin cortes:** siempre activo, sin ajuste. Las canciones seguidas de un
  disco (directos, discos conceptuales, música clásica) suenan sin silencio.
- **«Fundir canciones»:** ajuste en *Ajustes > Música* y en el menú «…» de
  Reproduciendo, con *Apagado* (por defecto) · 3 s · 6 s · 9 s · 12 s. Como en
  Spotify, apagado por defecto.
- **Fundido inteligente** (no hay que configurar nada):
  - no se funde entre canciones seguidas del mismo disco (mismo álbum y la
    siguiente pista): ahí se pasa sin cortes, que es lo que pide la música;
  - no se funde si la canción que acaba tiene un final en silencio o es muy
    corta (menos de 30 s);
  - al pulsar «Siguiente» a mano no hay fundido largo, solo un paso suave de
    medio segundo, para que responda al momento;
  - con el temporizador «al acabar la canción», con «repetir esta canción» o
    enviando a Chromecast/DLNA, no se precarga ni se funde.

### Cómo se hace

**Común (Dart).**
1. En `player_backend.dart`, una capacidad nueva para el reproductor que lo
   admita: `preloadNext(...)`, `cancelPreload()` y un aviso de «ya suena la
   siguiente» (`transitionedStream`).
2. En `playback_manager.dart`, solo para música:
   - unos 25 s antes del final, preparar ya la siguiente de la cola: pedir su
     `PlaybackInfo` y pasársela al reproductor;
   - cuando el reproductor avise de que ya suena, hacer lo mismo que hoy pero
     sin parar ni arrancar nada: cerrar la anterior como **terminada**
     (`_stopAndReportCurrent(finished: true)`), avanzar la cola como avance
     automático (`next(manual: false)`), avisar al servidor del inicio y poner
     la posición a 0 con la duración nueva a la vez (letra, cápsula y barra);
   - si la cola cambia (aleatorio, reordenar, quitar, ∞ añade canciones),
     cancelar y volver a preparar; si la conversión precargada se descarta,
     pararla en el servidor (`stopTranscoding`).
3. Aunque un reproductor no lo admita, ya se gana: tener el `PlaybackInfo` de
   la siguiente pedido de antemano quita una ida y vuelta al servidor.
4. Preferencia nueva `kostvMusicCrossfadeSeconds` (0, 3, 6, 9, 12), con los
   textos en `app_es.arb` y `app_en.arb`.

**Android (tele y móvil), sin cortes.**
- ExoPlayer ya pasa sin cortes si tiene lista: recorta el retardo y el relleno
  de MP3/AAC con sus metadatos, y FLAC/Opus/ALAC no lo necesitan.
- En el canal de Media3 (`Media3Bridge`/`Media3VideoView.kt`), un método
  `enqueueNext` que añade la siguiente con `addMediaItem` (dirección, cabeceras,
  ganancia de normalización por elemento) y un evento `transitioned` al pasar
  solo (`onMediaItemTransition` con motivo automático).
- Con la salida directa del audio al hardware activa, pedir que siga siendo sin
  cortes (`setIsGaplessSupportRequired(true)`); con «saltar silencios»
  encendido, no.
- Con el reproductor mpv (opcional en Ajustes) se queda como hoy.

**Android, fundido.**
- Un fundido de verdad necesita dos reproductores sonando a la vez durante unos
  segundos, con el volumen de uno bajando y el del otro subiendo.
- Se hace con un segundo reproductor solo de audio, sin vista, al lado del de
  ahora, cuidando que el foco de audio, la notificación y los botones del mando
  y de los auriculares sigan hablando con el que corresponde.
- Es la parte más delicada; va en su propio bloque y con un interruptor para
  apagarla si diera guerra.

**Web.**
- Con un solo elemento no hay forma de no cortar. La música de la web pasa a un
  reproductor propio con **dos elementos `<audio>`**: mientras suena uno, el otro
  carga la siguiente y arranca justo a tiempo. Queda casi sin cortes (de 20 a
  100 ms), que en la práctica no se nota.
- El fundido se hace bajando el volumen de uno y subiendo el del otro: funciona
  en Chrome, Edge, Firefox y Android.
- **iPhone y iPad:** Safari no deja cambiar el volumen de un `<audio>`. Habría
  que pasar el sonido por Web Audio, y eso exige que el servidor de Jellyfin
  responda con permisos CORS a la web, que está en otra dirección. Se comprueba
  en tu servidor:
  - si responde bien, fundido también en el iPhone;
  - si no, en el iPhone hay paso casi sin cortes y el ajuste de fundido sale
    apagado, con una nota.

### Lo que se cruza con «aprender»

- El complemento solo da una escucha por entera si la parada llega a 3 s del
  final. Con fundido, la anterior se cierra como **terminada**, con la
  posición en la duración, para que **un fundido no cuente nunca como salto**.
- El paso automático se apunta como `endedBy: natural`, igual que hoy.
- Pruebas en el complemento con escuchas que acaban a 12 s del final por
  fundido.

### Lo que solo se comprueba en aparatos de verdad

- Que no se oiga corte en la tele (también con barra de sonido o salida directa)
  y en el móvil con la pantalla apagada.
- Un disco en directo en MP3 y otro en FLAC, y uno que el servidor convierta.
- Fundido con la pantalla apagada y la app en segundo plano.
- La web en el iPhone: volumen, CORS y la siguiente arrancando con la pantalla
  bloqueada.
- Que en el panel del complemento las escuchas salgan como enteras.

## 3. Parte 4: música que aprende de verdad

### Ideas que guían el diseño

1. **Un solo gusto por persona, calculado en el complemento.** «Para ti», las
   mezclas, el descubrimiento, la radio y el ∞ beben del mismo sitio. La app deja
   de calcular el suyo.
2. **Usar todo lo que ya se apunta**, cada señal con su peso, y sin castigar lo
   que no es rechazo (cerrar la app, acabarse la sesión, el fundido).
3. **Lo elegido a mano manda más** que lo que sonó solo: saltar una canción que
   has buscado dice más que saltar una del aleatorio.
4. **Variedad y nada de repetirse:** reglas claras de artistas, discos y días.
5. **Siempre se puede explicar** («Porque escuchas X», «Hace tiempo que no la
   oyes») y **siempre se puede corregir** («No me gusta», con deshacer).
6. **Entra solo y poco a poco:** cada persona pasa al gusto aprendido cuando
   tiene datos suficientes, sin esperar a una fecha.
7. **Se mide:** si una mezcla se salta más que antes, se nota y se ajusta.

### 3.1. «No me gusta»

- **En una canción** (menú de canción y botón en Reproduciendo, junto al ♥):
  «No me gusta». Se salta al momento si está sonando y no vuelve a salir en nada
  automático de esa persona: mezclas, radio, ∞, descubrimiento, «Para ti» y la
  Mezcla del momento. Resta un poco a su artista.
- **En un artista** (menú de artista y de canción): «No me pongas a este artista».
  Fuera de todo lo automático. **Tres** «No me gusta» de canciones del mismo
  artista lo bajan mucho, sin quitarlo del todo.
- **Lo que no cambia:** el disco, la búsqueda y la biblioteca siguen
  enseñándolo todo (si lo buscas, es que lo quieres). Solo afecta a esa persona.
- **Deshacer:** aviso de 5 s con «Deshacer», como en «No me interesa» de Inicio.
  En *Ajustes > Música*, la lista «Lo que no quieres oír», para quitar lo que
  quieras.
- **Se guarda aparte del historial**, en un `dislikes.json` por persona:
  - vale también con «Aprender» apagado, porque es una elección tuya, no algo que
    se aprende;
  - «Borrar mi historial» no lo borra; en la misma pantalla hay otro botón para
    vaciar la lista.
- **Tele, móvil y web:** menús de siempre (mando, toque, ratón), con el ♥ y el
  «No me gusta» en la fila de Reproduciendo y en la cápsula al desplegarla en
  el móvil.
- Funciona al instante: lo filtra el complemento al servir las mezclas del día
  sin esperar al recálculo, y la app lo quita de la cola que ya tiene.

### 3.2. La puntuación de gusto

Cada escucha suma o resta, y lo reciente pesa más que lo antiguo.

**Peso de cada cosa** (de partida; se ajusta al medir):

| Qué pasó | Peso |
|---|---|
| Escuchada: al menos la mitad o 4 min (regla de Last.fm), o hasta el final | +1 |
| Saltada antes de 30 s, puesta a mano (disco, búsqueda, lista propia) | −0,5 |
| Saltada antes de 30 s, en mezcla, radio o ∞ | −0,3 |
| Saltada antes de 30 s, en aleatorio | −0,1 |
| Saltada entre los 30 s y la mitad | −0,1 |
| Saltada en el último 10 % | 0 |
| Parada porque se cerró la app, se acabó la sesión o falló | 0 |
| Repetida o con vuelta atrás para volver a oír un trozo | +0,5 |
| Puesta a propósito (buscada o elegida en el disco) | ×1,5 lo que sume |
| ♥ en la canción | +3, sin caducar |
| Añadida a una lista | +2 |
| ♥ en el disco o en el artista | +2 a todas sus canciones / al artista |
| Pedir un disco a Stremfin | +1 al artista |
| Enseñada muchas veces en mezclas y nunca puesta | −0,2 por semana, hasta un tope |

**Lo reciente pesa más.** Dos medidas por canción:
- **gusto de fondo**: el peso baja a la mitad cada 90 días;
- **lo de ahora**: baja a la mitad cada 14 días.

Las mezclas usan las dos; el descubrimiento, el gusto de fondo; «Para ti», más
lo de ahora.

**Del gusto de canción a artista y género:** suma de sus canciones con raíz
cuadrada, para que un disco muy escuchado no tape al resto. El segundo artista
de una canción cuenta la mitad, como ahora.

**Saltos:** se cuenta la proporción de saltos con un poco de margen
(`(saltos + 1) / (veces + 4)`), para que dos saltos seguidos no condenen una
canción. Si pasa del 60 % con al menos 3 veces, sale de las mezclas, salvo que
tenga ♥.

**Arranque en frío.** Al principio solo hay lo que sabe Jellyfin (cuántas veces
se puso cada canción, sin fechas, y los ♥).
- La puntuación mezcla las dos cosas según cuánto historial hay: con 0 escuchas
  apuntadas, todo es Jellyfin; con 300 o más, todo es lo aprendido.
- Así cada persona pasa sola y poco a poco, sin esperar a una fecha.
- Los ♥ y las listas cuentan desde el primer día.

**Dónde se calcula.**
- Un resumen por persona (`taste.json`) que se actualiza al apuntar cada
  escucha, en vez de leer los 24 meses cada día.
- Recálculo completo una vez al día de madrugada y al cambiar un ♥ o un «No me
  gusta».
- Ruta nueva `GET /Moonfin/Kostv/Music/Taste`: artistas y géneros principales
  (con su id de Jellyfin, el de Deezer si se conoce y el motivo), para que la
  app pida «Para ti».

### 3.3. Dónde se nota

**Mix diario.**
- Unas 50 canciones por mezcla:
  - 3 de cada 4 conocidas y que gustan, incluidas algunas olvidadas: mucho gusto
    y sin oír en 30 días;
  - 1 de cada 4 cercanas: canciones no oídas de artistas que gustan, y artistas
    parecidos de casa (ver «Parecido en casa»), de Jellyfin o de Stremfin.
- **Variedad:**
  - nunca el mismo artista seguido;
  - al menos 3 canciones entre dos del mismo artista;
  - como mucho 3 por artista cada 25;
  - nunca dos del mismo disco seguidas.
- **Sin repetirse:** fuera lo que salió en las mezclas de los 3 días anteriores
  y lo oído en las últimas 24 h.
- **Orden:** empieza por algo muy seguro (lo que más gusta de esa mezcla) y va
  encadenando por artistas y géneros parecidos, para que no haya saltos bruscos.

**Mezcla del momento.** Igual que hoy, pero con la nueva puntuación y mezclando
el gusto de esa franja con el general, hasta que la franja tenga datos
propios.

**Descubrimiento semanal.**
- Solo cosas nunca oídas, como ahora.
- Las semillas salen del gusto de fondo y **rotan cada semana** entre los 20
  artistas que más gustan (no siempre los mismos 10). Así descubre por más lados
  y no gasta la caché de Stremfin.
- Fuera los artistas con «No me gusta».
- **Aprende de sí mismo:** si de un artista descubierto se vuelve a oír algo en
  30 días, sus parecidos ganan peso en la semilla de la semana siguiente.

**«Para ti».**
- Sale de la ruta nueva del complemento: el mismo gusto que todo lo demás, con
  más peso a lo de ahora.
- Se piden a Stremfin los artistas por su id (`artist_ids`) cuando se conoce,
  que falla menos que el nombre.
- Lo que vuelve se filtra: fuera los «No me gusta» y lo explícito en perfiles
  infantiles.

**Radio y reproducción automática (∞).**
- La «Radio de esta canción» y el ∞ dejan de ser el InstantMix tal cual:
  1. se pide como ahora, más canciones de los artistas parecidos de casa;
  2. se quita lo que tiene «No me gusta» o se salta mucho;
  3. se ordena por gusto y parecido con la semilla;
  4. se aplican las reglas de variedad.
- Si se pide «más allá de casa», Stremfin (`/music/radio`), filtrado igual.

**«Parecido en casa».**
- Con las sesiones apuntadas: qué artistas suenan cerca unos de otros en la
  misma sesión (a 3 canciones o menos, sin contar los saltos).
- Solo se fía de un par de artistas con al menos 20 veces juntos; por debajo,
  usa lo parecido de Jellyfin o de Stremfin.
- Saldrá con unos meses de datos.
- Lo usan la radio, el ∞, las canciones cercanas del Mix diario y el orden de
  las mezclas.

**Orden de las filas de Música.**
- Las de arriba (buscador, sonando, Mix diario) se quedan fijas.
- Del resto, sube la que más se usa: veces que se puso algo de ella frente a
  veces que se enseñó, en las últimas 4 semanas.
- Necesita al menos 4 semanas de datos; antes, el orden de siempre.

**Fila nueva «Hace tiempo que no las oyes».** Canciones que gustan mucho y que
no suenan desde hace 30 días o más. Sale cuando hay al menos 15.

**Explicaciones.** Cada mezcla y cada fila dice por qué existe: «Porque escuchas
a X», «Parecido a Y», «Hace tiempo que no la oyes», «Tu música de por la
mañana». Para eso el complemento guarda qué semilla o regla trajo cada canción.

### 3.4. Niños y privacidad

- Perfiles infantiles: las semillas que se mandan a Stremfin pasan por el filtro
  de lo explícito (hoy se filtra lo que vuelve, no lo que se pide), y lo de casa
  sigue con el control parental de Jellyfin.
- «Aprender» apagado: no se apunta nada nuevo y el gusto vuelve a ser solo lo de
  Jellyfin; el «No me gusta» sigue valiendo.
- «Borrar mi historial» borra también `taste.json` y lo de «Parecido en casa»
  de esa persona.
- Tele compartida: lo que suena en automático (∞, radio) pesa menos que lo
  elegido, así que un rato de música de fondo de otro no cambia tu gusto.

### 3.5. Medir que mejora

- **Panel en el complemento** (página de administración, «Cómo va la música»):
  por persona y semana,
  - proporción de saltos antes de 30 s en lo que sale de mezclas y radio;
  - canciones enteras;
  - minutos que vienen de mezclas;
  - ♥ y listas desde mezclas;
  - «No me gusta» por cada 100 canciones;
  - canciones descubiertas que se vuelven a oír.
- **Antes y después:** el cálculo nuevo y el actual conviven unas semanas.
  - Al principio, el nuevo calcula sin enseñarse y se compara cuál habría
    acertado más con lo que se escuchó de verdad (acierto en las 25 primeras).
  - Después, días alternos: pares uno, impares el otro.
  - Si el nuevo hace saltar 5 puntos más que el actual, se vuelve al actual y se
    revisan los pesos.
- Todo esto lo puede ver solo un administrador.

### 3.6. Pruebas

- El motor del complemento es puro y con reloj inyectable: funciones nuevas
  probadas con historiales de ejemplo:
  - una casa simulada con 4 personas y 6 meses de escuchas;
  - casos de salto, fundido, cierre de app, ♥ y «No me gusta»;
  - reglas de variedad y de no repetirse.
- La app con el servidor falso: «No me gusta» con deshacer, la lista en Ajustes,
  las explicaciones y las filas, con fotos en tele (barra de arriba y lateral),
  móvil y web.

## 4. Orden de trabajo

| Bloque | Qué | Versiones |
|---|---|---|
| 1 | «No me gusta» (canción y artista) con deshacer y lista en Ajustes; gusto único en el complemento con todas las señales y la mezcla con Jellyfin según los datos; ruta `Taste` y «Para ti» con ella; reglas de variedad y de no repetirse; explicaciones; el cálculo nuevo en modo sombra | Complemento 3.1.1.2 y app |
| 2 | Sin cortes: precarga común y Android (tele y móvil) | App |
| 3 | Web: reproductor de música propio con dos `<audio>` y fundido (y en el iPhone, según CORS) | App |
| 4 | Fundido en Android con el segundo reproductor | App |
| 5 | Radio y ∞ con gusto; «Hace tiempo que no las oyes»; panel «Cómo va la música» | Complemento y app |
| 6 | Con datos (hacia enero): «Parecido en casa», orden de filas, días alternos y ajuste de pesos | Complemento y app |

Cada bloque: pruebas del complemento y de la app, auditoría, fotos en tele,
móvil y web, `KOSTV.md` al día y subida a la rama. Se publica cuando digas.

## 5. Decisiones

1. **Fundido apagado por defecto y sin cortes siempre** (recomendado), o el
   fundido encendido a 6 s para todos.
2. **«No me gusta» en canción y en artista, permanentes y con deshacer**
   (recomendado), sin el «Ahora no» temporal de Pandora, que añade una tercera
   opción que confunde.
3. **El «No me gusta» va aparte del historial**: vale con «Aprender» apagado y
   no se borra al borrar el historial (recomendado).
4. **iPhone (web) sin fundido si el servidor no da CORS** (recomendado), en vez
   de tocar la configuración de Jellyfin o del proxy.
