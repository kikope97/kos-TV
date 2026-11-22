# Revisión semanal del proyecto principal y del complemento

Cada semana se mira qué ha cambiado en:

- **La app de la que partimos:** Moonfin-Core (`upstream` en git,
  `https://github.com/Moonfin-Client/Moonfin-Core`, rama `main`). Se busca lo
  que merece la pena traer a kOS TV: arreglos del reproductor, fallos,
  rendimiento, seguridad y mejoras que encajen con la familia.
- **El complemento del servidor:** desde el 2026-11-12 es nuestro
  (`complemento/`, el complemento «kOS TV»), una copia de Moonbase, el oficial
  (`https://github.com/Moonfin-Client/Plugin`, versiones en su
  [`manifest.json`](https://raw.githubusercontent.com/Moonfin-Client/Plugin/refs/heads/master/manifest.json)
  y en sus etiquetas). Con especial cuidado: qué ha cambiado en el oficial (solo
  Jellyfin), qué hay nuevo que aprovechar y qué podría romper la app (las rutas
  `/Moonfin/...` que usa). Se decide si traerlo a nuestra copia (y publicar
  `X.Y.Z.1`) o esperar; cómo se trae, en `complemento/README.md`.

Cómo se hace y cuándo se pregunta: ver la norma en [`CLAUDE.md`](../CLAUDE.md).

**Cada revisión se apunta aquí, siempre**, aunque no se integre nada o el
usuario decida dejarla para otro día (entonces se apunta que se pospuso). Es el
historial de dónde venimos y de lo que se ha ido haciendo: no se borra ni se
reescribe lo anterior, solo se añade arriba.

## Dónde estamos ahora

Se actualiza al terminar cada revisión. La siguiente empieza justo aquí.

| | |
|---|---|
| Copia original de kOS TV | upstream `3d87996d2` (2026-11-10): Moonfin 3.0.0 más 658 commits posteriores sin publicar |
| Último commit de upstream revisado | `a1fa0f9f1` (2026-11-20; revisión corta del 2026-11-21) |
| Última versión del complemento oficial revisada | 3.1.1.0 (2026-11-19, etiqueta `3.1.1`, commit `afb2e7356`): traída a nuestra copia |
| Nuestro complemento | «kOS TV» 3.1.1.6, basado en la 3.1.1, publicado el 2026-11-22 antes que la app 1.21.0 (desde la rama de trabajo) |
| Complemento instalado en el servidor de casa | el nuestro, en Jellyfin 12.4.0; la última publicada es la 3.1.1.6 |
| Última revisión | 2026-11-20 |
| Próxima revisión | a partir del 2026-11-27 |

## Cómo apuntar cada revisión

Copiar este bloque arriba del registro y rellenarlo:

```
### AAAA-MM-DD

- **App, revisado:** upstream `<desde>`..`<hasta>` (N commits, fechas).
- **Integrado:** qué se trajo y con qué commit nuestro (o «nada»).
- **Descartado:** qué no aplica y por qué (Plex, Emby, Silo, escritorio,
  Seerr, Firebase, ya lo teníamos…).
- **Dudoso o pendiente:** lo que el usuario decide más adelante.
- **Complemento, revisado:** versiones oficiales `<desde>` → `<hasta>`; qué
  cambia en las rutas `/Moonfin/...` que usa la app; qué hay nuevo; si rompe
  algo.
- **Decisión del complemento:** traerlo a nuestra copia (con qué commit y qué
  versión nuestra se publicó) o esperar, y por qué. Versión instalada en el
  servidor después.
- **Notas:** cualquier otra cosa que convenga recordar.
```

## Registro

### 2026-11-21 · Revisión corta (a petición, por el anuncio de una versión nueva)

- **App, revisado:** upstream `defe4661b`..`a1fa0f9f1` (9 commits, del
  2026-11-20). La última versión publicada del original sigue siendo la 3.1.1
  (etiqueta del 2026-11-18), que ya se revisó entera el 2026-11-20; el anuncio
  de Reddit no se pudo leer desde aquí.
- **Integrado** (con el visto bueno del usuario, el mismo día): `379a9bad4` →
  `6373e0d1e` y `bef6fd5a0` → `d9822375e`:
  - `379a9bad4`: al volver a Inicio desde una página abierta en la barra de
    arriba, el banner se iba de la vista. Nuestro `home_screen.dart:3750` tiene
    la misma línea.
  - `bef6fd5a0`: cambiar «Decodificación por hardware» se aplica al siguiente
    título sin reiniciar la app. Solo con el reproductor mpv (opcional en
    Android) y en la web; con Media3, el de por defecto, no cambia nada.
- **Dudoso:** `808ddbcc2`, enlaces directos para abrir una biblioteca,
  Favoritos, Ajustes, el buscador o la TV en directo. Tenemos el mismo
  servicio de enlaces, pero nadie los usa en casa; solo serviría para atajos
  o para Home Assistant.
- **Descartado:** `d58b20d5c` y `66076d9b2` (escritorio y Windows),
  `6c7bd864f`, `2f25cf3bd` y `1dabeb736` (snap y flatpak de Linux) y
  `a1fa0f9f1` (traducción al chino).
- **Complemento, revisado:** sin cambios desde la 3.1.1 (ya traída y publicada
  como 3.1.1.1).
- **Decisión del complemento:** nada que traer.

### 2026-11-20

- **App, revisado:** upstream `3d87996d2`..`defe4661b` (333 commits, del
  2026-11-10 al 2026-11-20). 178 son traducciones de Weblate; los otros 155,
  uno a uno. Antes de traer nada, se comprobó fallo por fallo, con archivo y
  línea (y pruebas cuando se pudo), que el mismo fallo existía en kOS TV.
- **Integrado** (cada uno con su commit, «Traído/Adaptado de upstream»):
  - Reproductor: el tiempo que se paraba al volver a la app en la tele
    (`4aeab9820` → `1df713dd7`); bajar rápido a los botones ya no adelanta
    (`1da2b7372` → `5648ab39e`); mantener Izquierda/Derecha a pasos que crecen
    (`a438fbe8f` → `ef0ed1ad5`); «Detener» desde otro aparato
    cierra el reproductor (`189f1219a`, adaptado → `3bb6448e6`); subtítulos «solo
    si el audio es extranjero» con el audio de la serie (`fc155ab50` →
    `7da49a263`) y elección por serie desde Siguiente y la cola (`ac5780b7b` →
    `648c1ac22`); subtítulos mov_text (`bbaed8e80` → `1fe82b7be`); web en
    iPhone/iPad (`50427ddb9` → `200fd218e`); Ver juntos en la web (`36d5653ad` →
    `1bef368aa`); bloqueo de controles del móvil (`8f500b709` → `d5ff2cfcb`);
    sombra de subtítulos con mpv (`fec476bf6` → `16fb04c13`).
  - Tele, fichas, Inicio y Ajustes: el OK tras «Visto» (`86f76a14c`, adaptado a
    la ficha kOS TV → `1c541c51f`); el token fuera de las carátulas de Watch
    Next y canales (`d2d9cf577` → `48420cf79`); «Seguir viendo + Siguiente» al
    volver (`d0203a49f` → `2dcc4fa05`); temporada no vista que seguía en
    «Reanudar» (`93887fcff` → `ddf480ad6`); botón que saltaba con el ratón
    (`b0ae1d747` → `5b4639d52`); más perfiles en «¿Quién está viendo?»
    (`5650bd798` → `ef71f8aee`); foco en las acciones de segmentos (`6d52efdab`
    → `661060e53`); editor de filas (`0749c1277` → `647e6e443`); «TV en
    directo»/«Ahora en directo» al volver (`d7b7cef60` → `22044bec7`); orden de
    estudios (`cd9fafc57` → `5ee3547e2`).
  - Móvil, web y privacidad: invitados de SyncPlay (`f846a8e66` → `32f98162d`);
    Chromecast y DLNA (`61bd49dff`, `1efa38a9f` → `43daa5581`, `b5665527d`);
    visor de fotos (`609a06136`, `3a7f6c3c5` → `8c84543e0`); SponsorBlock con
    prefijo del hash (parte de `47d176d6b` → `7e6ee0a35`); fuentes de reserva
    de la web dentro de la imagen (`a6bec3155`, adaptado → `edd5f0d13`); foco
    de la web al cambiar de ventana (`e700d7dda` → `581aa9e82`).
- **Descartado:** traducciones de otros idiomas; Seerr, Silo, Plex, Emby,
  Firebase/push; escritorio, iOS y tvOS; CI y publicación de upstream; el APK
  único (`8efeff436`, nosotros publicamos dos); el SDK de Cast al arrancar
  (`9a806714c`, va unido al APK único). Ya lo teníamos: las descargas que se
  congelaban (`cd3570c99`, nuestro `42f058a25`), el tráiler del banner
  (`559f07093`), hls.js local y `allowBackup`. No nos pasa: el logotipo de la
  serie en «Últimos» (`13091f3e9`, no se ve con nuestro Inicio).
- **Dudoso o pendiente:** marcar como visto al salir en los créditos
  (`80d29f1a6`), barra de abajo por defecto en el móvil (`10da70687`), ficha
  «Solicitar» en ventanas grandes (`4433f1526`), filas de JustWatch/TMDB
  Discover (`2733144bc`), novedades de películas en la barra (`1c53d95e3`),
  ocultar el progreso en las bibliotecas (`8a266bb62`), imagen en imagen en la
  web, 2× con la barra espaciadora, DLNA y demás de app_upstream. La fuente de
  subtítulos elegida en Ajustes aún se baja de Google.
- **Complemento, revisado:** oficial 3.1.0 → 3.1.1 (2026-11-19, 13 commits).
  Ninguna ruta `/Moonfin/...` de la app cambia ni desaparece; el Ping añade
  `discoverChartsSupported` y `pushSupported`. Trae las listas de TMDB con todas
  sus páginas (#390) y MDBList en el idioma pedido (#391); lo demás es para
  funciones que no usamos (juegos, push, Seerr, campos nuevos del perfil).
- **Decisión del complemento:** traída a nuestra copia con `git subtree pull`
  (squash `56ccac902`, fusión `867a5a689`), conservando lo nuestro; los campos
  nuevos del panel van ocultos y traducidos, sin la ruta `Notifications/Test`
  ni la política de privacidad. 1451 pruebas en verde. Se publica como 3.1.1.1
  cuando el usuario lo diga. Instalada en casa: 3.1.0.8.
- **Notas:** pendiente de probar en aparatos reales lo que el ordenador no
  puede (Kotlin de Media3, Chromecast/DLNA, Watch Next, Safari de iPhone y la
  imagen de Docker con las fuentes).

### 2026-11-12 · Complemento sin Seerr y en español (sin revisión)

- **App, revisado:** nada; la primera revisión sigue para el 2026-11-18.
- **Complemento:** a petición del usuario, fuera Seerr y lo que dependía de él
  (el calendario de Sonarr/Radarr con sus recordatorios y el aviso de
  descargas atascadas); a las apps se les dice que no hay. La página de
  ajustes, traducida al español con los nombres de la app; lo de Seerr queda
  oculto con la clase `kostvSinSeerr`. **Para las próximas revisiones:** los
  cambios del oficial en Seerr, el calendario o las descargas atascadas no
  aplican, y los textos nuevos de su página de ajustes llegarán en inglés y
  hay que traducirlos. Se publica como 3.1.0.2 cuando el usuario lo diga.

### 2026-11-12 · El complemento pasa a ser nuestro (sin revisión de la app)

- **App, revisado:** nada; la primera revisión de la app sigue para el
  2026-11-18, desde `3d87996d2`.
- **Complemento, revisado:** el oficial 3.0.0.0 → 3.1.0.0 (publicada hoy).
  Trae ver juntos alojado en el servidor, búsqueda inteligente con frases,
  calendario de Radarr/Sonarr con avisos, etiquetas de pósteres, logotipos de
  estudios, valores por defecto por tipo de aparato y seis ajustes más que se
  sincronizan, entre otros arreglos. Rutas: todas las que usa la app siguen
  (solo `ClientLog`, los informes de diagnóstico, no existe en Jellyfin, ni en
  la 3.0). No rompe nada que se haya visto.
- **Decisión del complemento:** el usuario decide tener su propio complemento,
  partiendo de la 3.1.0 oficial, para poder añadirle lo que necesite kOS TV
  (por ejemplo, sincronizar sus ajustes propios). Se trae a `complemento/` con
  `git subtree` (commit de la copia `46cffcaa2`), se queda solo lo de Jellyfin y
  se le da identidad propia: nombre «kOS TV», identificador
  `561f86df-fa00-4fca-aa4d-2fed0e332670`, imagen, textos del panel, tareas en
  español y la invitación de «Ver juntos». Mantiene las rutas `/Moonfin/...` y
  la carpeta de datos del oficial, así que al cambiar se conserva todo
  (probado en un Jellyfin 10.10.7 de prueba: ajustes del administrador, los de
  cada persona y el historial de tareas). Se publica como 3.1.0.1 con su propio
  catálogo; en el servidor se desinstala el oficial y se instala este.
- **Notas:** la web de Moonfin que el paquete oficial lleva dentro
  (`/Moonfin/Web/`) no va en el nuestro; quizá más adelante, la web de kOS TV.
  La página de ajustes del complemento sigue en inglés, como la oficial, salvo
  el nombre.

### 2026-11-11 · Punto de partida (sin revisión)

- **Decisión:** el usuario decide partir de aquí, sin revisar ahora (acabamos
  de salir de esta versión), y hacer la primera revisión en una semana, hacia
  el 2026-11-18.
- **App:** la copia de kOS TV sale de upstream `3d87996d2` (2026-11-10). La
  última versión publicada de Moonfin es la 3.0.0 (2026-10-30) y ya está
  dentro, junto con los 658 commits que hicieron después hasta el 10 de
  noviembre (trabajo aún sin publicar como versión). Desde la copia, en
  upstream `main` hay 23 commits más, también sin publicar, hasta
  `d31a38f8b` (2026-11-11). No son versiones sino cambios sueltos (arreglos,
  traducciones, cosas de Seerr, Silo y Plex…). No están en kOS TV, así que la
  primera revisión empieza en `3d87996d2` y los incluye.
- **Desde la copia, kOS TV ha cambiado mucho** (ver la tabla de `KOSTV.md`):
  marca propia, sin Plex, Emby, escritorio, Seerr ni Firebase, servidor de casa
  integrado, Descubrir (Stremfin), web en Docker, aplicaciones de la tele,
  intro en vídeo… Todo lo que venga de upstream se mira teniendo eso en
  cuenta.
- **Complemento:** el oficial va por la 3.0.0.0 (2026-10-30, Jellyfin 10.10 o
  superior), que es la 2.5.0 renumerada para ir con las apps Moonfin 3.0.0.
  Se decidió usar el oficial y no una copia propia (que lo mantengan ellos; si
  un día rompe algo, se vuelve a una versión anterior o se copia y lo seguimos
  nosotros). El usuario lo instaló el mismo 2026-11-11 desde el catálogo
  (3.0.0.0, la última). Configuración recomendada: Seerr apagado y sin push
  (kOS TV no se apunta a las notificaciones), clave de TMDB (y de MDBList si
  se quiere), recomendaciones y logos de estudios encendidos, anime solo si
  hay anime. «User defaults» sin tocar de momento.

## 2026-11-21 · Complemento 3.1.1.3 (fuera de la revisión semanal)

- No es una revisión del original: auditoría de nuestro complemento contra Jellyfin 12.4.0, el del servidor de casa (Jellyfin dejó el «10.» en la 12.0).
- La 3.1.1.2 cargaba, pero fallaban en 10.11 y 12 los mixes de música, el Descubrimiento semanal y el Momento (error 500), el artista de las escuchas, `/Moonfin/Kostv/Collections`, los favoritos de antes y los disparadores de «listas personalizadas» (esto último también en el oficial). Causa: cambios de la API de Jellyfin en 10.11 (`GetItemList`/`GetItemIds`, `SimilarTo`, `LinkedChild.Id`, `TaskTriggerInfo.Type`).
- Publicada la 3.1.1.3 desde `complemento-hotfix-3.1.1.3` (sobre la 3.1.1.2, commit `34a07d30c`), solo con esos arreglos, el proveedor de similares renombrado a «kOS TV» (con migración del orden de cada biblioteca en 12) y la nota de no tener Moonbase y kOS TV a la vez. En la rama principal: `913b2c102` y `b4c08dc77`.
- Nuevo: `complemento/Jellyfin/tools/abi-check/`, que comprueba el complemento contra Jellyfin 10.10.0, 10.10.7, 10.11.11 y 12.4.0 al publicarlo.
- Para la próxima revisión: mirar qué hace el oficial con Jellyfin 12 (sus issues #350 y #355).

## 2026-11-22 · App 1.19.0 y complemento 3.1.1.4 (fuera de la revisión semanal)

- Publicadas juntas desde `claude/intelligent-albattani-lfpzv9` (commit `5347f33ef`): «Toda la música» (escuchar lo que no está en casa, listas y ♥ con canciones de fuera, música sin cortes en Android, aprender de lo escuchado), el diseño nuevo de Música (`docs/diseno-musica/`) y la ficha de series (marco en el episodio con el foco; elegir un episodio lo reproduce).
- No hay revisión del original en este bloque: la siguiente sigue empezando en `a1fa0f9f1` y el complemento oficial 3.1.1.0.

## 2026-11-22 · App 1.20.0 y complemento 3.1.1.5 (fuera de la revisión semanal)

- Publicadas desde `claude/intelligent-albattani-lfpzv9` (app en `18d128b67`; complemento en `70de208f5`, el primer intento falló por una prueba con carrera, ya arreglada): «Para ti» con lo personal primero (una sola sección «Listas de éxitos», «Porque escuchas a…», «Radios de tus artistas») y la radio de una canción con datos públicos (ruta `Station` del complemento: ListenBrainz + filtro de estilo con Deezer; Last.fm opcional), el ∞ sembrado con la última canción elegida y sin intercalar casa/fuera.
- Stremfin 1.101.0 añade `POST /music/songs/match` y `GET /music/songs/{id}/radio` (pedidos por nosotros); se usarán en la siguiente versión (con «Toda la música», la radio de Stremfin primero y la del complemento detrás).
- La siguiente revisión del original sigue empezando en `a1fa0f9f1` y el complemento oficial 3.1.1.0.

## 2026-11-22 · Complemento 3.1.1.6 (fuera de la revisión semanal)

- Publicado el complemento 3.1.1.6 (commit `140bce394`) a petición del usuario, antes que la app: pestaña «Actualizaciones de la app», apartado «Instalaciones (últimos 14 días)», emisoras de música con fuentes gratuitas, listas con canciones de fuera y sin las opciones de diseño del menú en el panel.
- La app 1.21.0 (versión puente) espera a que el menú nuevo quede igual que las maquetas aprobadas.
- La siguiente revisión del original sigue empezando en `a1fa0f9f1` y el complemento oficial 3.1.1.0.

## 2026-11-22 · App 1.21.0, versión puente (fuera de la revisión semanal)

- Publicada la app 1.21.0 (commit `762699bbc`), la versión puente: busca sus actualizaciones en el complemento (3.1.1.6), menú nuevo único (tele A, móvil y tableta con barra de cristal, ordenador), sin los diseños antiguos ni sus opciones, radio de canción con Stremfin y arreglo del marco de «Descubrimiento semanal».
- Desde ahora la familia se actualiza subiendo los APK en *Panel > Complementos > kOS TV > Actualizaciones de la app*; GitHub queda como canal beta.
- Pendiente de publicar: complemento 3.1.1.7 (panel: ListenBrainz y Last.fm en «Integraciones», «Nueva actualización» rediseñada), cuando el usuario lo diga.
- La siguiente revisión del original sigue empezando en `a1fa0f9f1` y el complemento oficial 3.1.1.0.
