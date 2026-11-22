# El complemento del servidor de kOS TV

El complemento de Jellyfin que acompaña a kOS TV. Es nuestra copia de
**Moonbase**, el complemento oficial de Moonfin
([Moonfin-Client/plugin](https://github.com/Moonfin-Client/plugin), licencia
GPLv3, ver [`LICENSE`](LICENSE)), con los cambios de kOS TV encima. Todo el
mérito del original es de sus autores.

Hace lo mismo que el oficial para la app: sincroniza los ajustes de cada
persona entre sus aparatos (con los valores por defecto del administrador),
valoraciones de MDBList y TMDB, filas de listas y de temporada, búsqueda
inteligente, ver juntos, avisos, PIN de perfiles…

## Qué cambia respecto al oficial

- **Su propia identidad:** se llama «kOS TV» en el panel de Jellyfin y tiene su
  propio identificador (`561f86df-fa00-4fca-aa4d-2fed0e332670`), así que el
  catálogo oficial nunca lo «actualiza» con el suyo. Imagen, página de ajustes,
  tareas programadas (en español) y la página de invitación de «Ver juntos»
  van con la marca kOS TV.
- **Las mismas tripas:** las rutas siguen siendo `/Moonfin/...` (la app las usa
  y no se ven), y sus datos, en la misma carpeta que el oficial
  (`plugins/configurations/Moonfin/` y `Moonfin.Server.xml`). Por eso, al
  cambiar del oficial a este, todo se conserva: ajustes del administrador, los
  de cada persona y el historial de las tareas.
- **Nunca los dos a la vez:** Moonbase (el oficial) y kOS TV no pueden estar
  instalados al mismo tiempo. Usan los mismos nombres por dentro y el mismo
  archivo de ajustes, y con los dos cargados Jellyfin puede dejar
  `Moonfin.Server.xml` vacío (se pierden los ajustes). Para cambiar del oficial
  a este: desinstala Moonbase en **Panel > Complementos**, reinicia el
  servidor y solo entonces instala kOS TV (y vuelve a reiniciar).
- **Solo Jellyfin:** fuera las versiones para Emby, Plex y Silo y lo de GitHub
  del oficial.
- **Sin Seerr:** fuera todo lo suyo (la conexión, el acceso único, sus avisos de
  peticiones, la búsqueda de lo que no tienes) y lo que colgaba de él: el
  calendario de Sonarr y Radarr con sus recordatorios y el aviso de descargas
  atascadas. kOS TV pide las cosas a su propio servicio. A las apps se les dice
  que no hay Seerr ni calendario (`/Moonfin/Ping`), y en la página de ajustes
  esos apartados están ocultos (su código sigue buscándolos por su nombre).
- **La página de ajustes en español**, con los mismos nombres que la app para los
  mismos ajustes, y sin lo que las apps de kOS TV no usan (valores por defecto
  de funciones que la app no tiene y los campos de la web oficial, ocultos con
  la clase `kostvNoSeUsa`). De la 3.1.1 se ocultan así unir las bibliotecas de
  películas y series, ocultar el progreso y los «sin ver» en las bibliotecas, y
  las etiquetas, el periodo y el lema de las películas nuevas de la barra
  multimedia; el tipo de filas «Carrusel» no se ofrece.
- **Sin la notificación de prueba** del oficial (`/Moonfin/Notifications/Test`)
  ni su política de privacidad: kOS TV tiene el push apagado.
- **La dirección del servicio de peticiones (Stremfin)** se pone aquí, en la
  pestaña «Direcciones», y el complemento se la da a las apps en `/Moonfin/Ping`
  (`kostvRequestsUrl`) cuando inician sesión. Así no va dentro del APK y, si
  cambia, solo se cambia aquí.
- **El Inicio de cada persona** (`/Moonfin/Kostv/Home`, en `Jellyfin/backend/Kostv/`): el
  complemento monta las filas de recomendaciones del Inicio de las apps. Lee del propio
  Jellyfin lo que cada persona ha visto (lo reciente pesa más) y sus favoritos, pregunta a TMDB
  qué gustó a quien le gustaron esos títulos (se guarda un mes en `kostv-home-tmdb.json`), se
  queda con lo que está en el servidor, la persona no ha visto y puede ver, y devuelve las
  filas por páginas: «Porque viste…», «Porque estás viendo…», «Porque te gusta…» (un favorito
  o algo de «Mi lista» que aún no ha visto; tipo `because_liked`, que las apps anteriores
  enseñan como «Recomendado para ti»), «Recomendado para ti», «Con [alguien]», por género y
  las mejor valoradas, sin repetir títulos entre filas ni con «Volver a ver». Una fila
  necesita 6 títulos. Con `refresh` la página se rehace si la persona ha visto algo, si ha
  llegado algo nuevo que pueda ver o si han cambiado sus favoritos. Usa la clave de TMDB del complemento; sin ella solo salen las de género
  y las mejor valoradas. En la pestaña «Direcciones» hay un botón que dice cuántas filas le
  salen a cada persona. A las apps se les avisa en `/Moonfin/Ping` (`kostvHome`).
- **«Mi lista»** (`Jellyfin/backend/Kostv/KostvMyList.cs`): la lista de cada persona de lo que
  quiere ver, en `kostv-my-list.json` (hasta 1000). `GET /Moonfin/Kostv/MyList` la da en tres
  partes (`Watching`, a medias; `ToStart`, sin empezar; `Watched`, películas vistas y series sin
  nada pendiente, que vuelven a `Watching` si llega una temporada nueva) y con `Ids`. `POST
  /Moonfin/Kostv/MyList?itemId=…` añade (un episodio o temporada cuenta como su serie),
  `&remove=true` quita y `&arrived=true` es la app añadiendo algo pedido que acaba de llegar: solo
  la primera vez, así quitarlo se respeta. `POST /Moonfin/Kostv/MyList/ClearWatched` quita lo
  visto. Las recomendaciones no repiten lo que está en la lista y la lista cuenta como un
  favorito para «Recomendado para ti». Con las primeras filas, `/Moonfin/Kostv/Home` devuelve
  `MyList` (lo sin empezar) y `MyListIds`. A las apps se les avisa en `/Moonfin/Ping`
  (`kostvMyList`). Lo que tiene título de TMDB y falta un momento del servidor (un archivo
  que se sustituye por otro mejor, un disco que no está durante un escaneo) no se quita al
  momento: se apunta desde cuándo falta (`missingSince`), vuelve a su sitio si reaparece
  (con el mismo id o, por su título de TMDB, con otro) y solo se quita si sigue faltando a
  los 7 días.
- **Colecciones de un título** (`Jellyfin/backend/Kostv/KostvCollections.cs`): `GET
  /Moonfin/Kostv/Collections?itemId=…` da las colecciones que la persona puede ver que
  tienen ese título directamente (no por su serie), con una sola lectura de las colecciones.
  La app lo usa para «Parte de la colección…» de la ficha y para «Quitar de la colección» del
  menú de las tarjetas; con un complemento anterior (contesta 404) recorre las colecciones
  una a una, como antes.
- **«No me interesa» y episodios nuevos** (también en `Jellyfin/backend/Kostv/`): `POST
  /Moonfin/Kostv/Home/NotInterested?itemId=…` (con `undo=true` para deshacerlo) guarda por persona
  el título de TMDB que no le interesa (`kostv-home-dismissed.json`, hasta 500; si el título no
  tiene identificador de TMDB, por su id del servidor, que no aguanta que se sustituya el archivo), lo saca de sus
  filas, resta peso a lo que TMDB encuentra parecido y un poco a sus géneros, y rehace su página.
  Con las primeras filas, `/Moonfin/Kostv/Home` devuelve además `NewEpisodes` (episodios sin ver
  añadidos en las dos últimas semanas de las series que la persona ha visto, uno por serie,
  el primero de ellos y los especiales detrás; nada de una serie en la que va atrasada; leídos
  en cada petición) y `Hidden` (los elementos de lo descartado, para las filas que monta
  la app).
- **Favoritos** (`Jellyfin/backend/Kostv/KostvFavorites*.cs`): apunta el momento en que cada
  persona marca o quita un favorito, desde cualquier app o desde la web de Jellyfin
  (`kostv-favorites.json`; Jellyfin no lo guarda). `GET
  /Moonfin/Kostv/Favorites?types=Movie,Series&start&limit&ascending` da sus favoritos por
  «Añadidos a favoritos», lo último marcado primero; los que ya eran favoritos antes de instalar
  esta versión van detrás, por fecha de llegada al servidor. `GET /Moonfin/Kostv/Favorites/News`
  da las novedades de sus series favoritas: por serie, los episodios sin ver añadidos en los
  últimos 30 días, el primero de ellos, cuántos son, si abren una temporada nueva (ningún
  episodio de esa temporada es anterior a esos 30 días) y si llegaron después de la última vez
  que la persona miró (`Unseen`, para el aviso del corazón). `POST
  /Moonfin/Kostv/Favorites/News/Seen` apunta que las ha visto (el aviso se quita en todos sus
  aparatos). Con las primeras filas, `/Moonfin/Kostv/Home` pone primero en `NewEpisodes` los de
  sus series favoritas (de los últimos 30 días, aunque no las haya empezado), con
  `FavoriteSeriesIds`, y añade `Rewatch`: favoritos vistos hace más de 180 días o marcados hace
  más de 14 y sin empezar (hasta 20, en un orden que cambia cada día). A las apps se les avisa
  en `/Moonfin/Ping` (`kostvFavorites`). Los favoritos que ya lo eran antes de que se
  apuntaran las fechas se anotan una vez como «de antes» (unos minutos después de arrancar el
  servidor) y nunca se fechan, así que valorar uno no lo sube al primer puesto.
- **Música que aprende de cada persona** (`Jellyfin/backend/Kostv/KostvMusic*.cs`, el plan en
  `docs/musica-recomendaciones.md`):
  - **Lo que se escucha:** el complemento apunta cada canción que suena (solo `Audio`), desde
    cualquier app, con los avisos de «empieza», «avanza» y «termina» de Jellyfin, y los ♥ que se
    ponen y se quitan a las canciones. De cada escucha: canción, álbum, artistas (ids y nombres),
    géneros, cuándo (UTC, y día, hora y día de la semana en la hora de casa, solo para leer el
    archivo: las franjas se sacan siempre de la hora UTC), cuánto se oyó y lo que dura, cómo
    acabó (`completed`: ≥ 90 % o hasta el final; `skipped`: < 30 s o < 50 %; `stopped`: el
    resto), el aparato (`tv`, `mobile`, `web` u `other`, por el nombre de la app y del aparato)
    y de dónde venía (`source`, si la app lo dijo; si es un «Mix diario», también su género ese
    día, `mixGenre`). Cuánto se oyó es dónde paró la canción si la app lo dice; si no, dónde
    estaba en su último aviso de «avanza» más el tiempo desde entonces (sin contar pausas) o,
    sin avisos, cuánto tiempo lleva sonando (con el «hasta el final» de Jellyfin como pista).
    Los avisos que llegan desordenados (un «avanza» tras el «termina», un «avanza» antes del
    «empieza», el «empieza» de la siguiente antes del «termina» de la anterior) no apuntan
    escuchas de más ni saltos falsos. Va en `kostv-musica/<usuario>/AAAA-MM.jsonl` (una línea
    JSON por escucha, ♥ u otro aviso, un archivo por mes) en la carpeta de datos del complemento;
    se guarda 24 meses (lo anterior se borra a diario y al escribir) y se borra la carpeta de la
    persona al borrar su usuario (y, en la vuelta diaria, la de los usuarios que ya no están en el
    servidor). En la misma carpeta, `settings.json` (si aprende), `discovery.json` (la lista de
    la semana), `today.json` (los mixes, los artistas y las mezclas del momento del día, para
    que no cambien al reiniciar el servidor; se sobrescribe cada día y se borra al borrar las
    escuchas o apagar «Aprender») y `shown.json` (qué se apuntó ya como enseñado ese día o
    semana). Las líneas de antes, sin los campos nuevos, se leen igual.
  - **Más datos de cada escucha:** `session` (las escuchas seguidas de la persona, sin pausas
    de 30 minutos o más, comparten id), `prev` y `prevEndedBy` (la canción de antes y cómo
    acabó; tras reiniciar, de la última escucha del archivo del mes); `endedBy`: `natural`
    (llegó al final, a menos de 3 s, o sin posición con el «hasta el final» de Jellyfin),
    `next` (otra empezó en la misma sesión en menos de 5 s: la que para antes del final se
    guarda en memoria unos 6 s esperando a la siguiente y, si no llega, se apunta como
    `stop`; si el «empieza» de la siguiente llega antes, es `next` al momento), `stop`,
    `closed` (se acabó la sesión de Jellyfin) o `error` (falló: Jellyfin no lo pasa en su
    aviso de «termina», así que un filtro del complemento lo lee del `Failed` del propio aviso
    de la app al llegar a `/Sessions/Playing/Stopped`, sin tocar nada más); `shuffle` y
    `repeat` (`none`, `all` u `one`), de la sesión de Jellyfin (`PlaybackOrder` o
    `ShuffleMode` y `RepeatMode`, leídos por nombre; sin ellos, no van); `replay` (la misma
    canción otra vez a menos de 10 s de acabar) y `seekBack` (cuántas veces se echó atrás más
    de 5 s mientras sonaba; no en pausa ni al volver a empezar desde el final). Una escucha que
    falla pronto no cuenta como saltada en nada (mixes, artistas ni mezcla del momento); si
    falla tras oír buena parte, cuenta lo que se oyó.
  - **Más señales:** los ♥ de álbumes y artistas (líneas `favorite` con `kind`: `album` o
    `artist`; los de canciones siguen como `heart`); lo que llega por la ruta `Event`; y lo
    que se enseñó (`shown`), la primera vez cada día de música que se piden: `mixes` (id,
    género y canciones de cada mix), `moment` (franja y canciones, una por franja) y
    `discovery` (semana e ids de Deezer de la lista guardada, una vez por semana). Solo ids.
  - **«No me gusta» y el gusto aprendido:** el «No me gusta» de canciones y artistas va en
    `dislikes.json` de cada persona (con nombre, artista y disco para la lista de la app; hasta
    2000 de cada), aparte del historial: vale con «Aprender» apagado y no se borra al borrar las
    escuchas (`GET /Moonfin/Kostv/Music/Dislikes`, `DELETE …/Dislikes/{itemId}` y `DELETE
    …/Dislikes`). Lo que tiene «No me gusta» no sale en los mixes, la mezcla del momento, las
    semillas ni el gusto (se quita al servir lo del día, que además se vuelve a calcular), y cada
    canción con «No me gusta» resta a su artista (tres, mucho). El gusto de cada persona se resume
    en `taste.json`, que se pone al día al apuntar cada línea y se calcula entero una vez al día
    (y al faltarle algo), en vez de leer los 24 meses: con dos medidas por canción (la mitad cada
    90 y cada 14 días), los pesos del plan (`docs/musica-plan-fundido-y-aprender.md`, 3.2) y la
    mezcla con lo que sabe Jellyfin según cuántas escuchas hay. `GET /Moonfin/Kostv/Music/Taste`
    lo da a la app (`Learned`, `Artists`, `Recent` y `Genres`). Los mixes y la mezcla del momento
    siguen las reglas de variedad (nunca el mismo artista a menos de tres canciones, como mucho 3
    por artista cada 25, nunca dos del mismo disco seguidas; si con lo que hay no cabe nada más,
    ceden primero las 3 cada 25 y luego la distancia, nunca el seguido), 3 de cada 4 conocidas
    (con algunas «olvidadas») y no repiten lo de los 3 días anteriores ni lo oído en 24 horas; y
    llevan `Because`, sus tres artistas principales.
  - **Cómo se puntúa:** el ajuste «Cómo se puntúa la música» de la pestaña «Direcciones»
    (`KostvMusicEngine`): `actual` (por defecto), `nuevo` o `alterno` (un día cada uno). El que no
    se usa se calcula igual (`shadow.json`) y al día siguiente se apunta en `compare.jsonl` cuántas
    de sus 25 primeras se oyeron enteras, para el panel de más adelante. Los dos se borran con las
    escuchas, y `compare.jsonl` guarda 24 meses como ellas.
  - **La hora de casa:** el ajuste «Zona horaria de casa» de la pestaña «Direcciones»
    (`KostvMusicTimeZone`, un nombre como `Europe/Madrid`, que es el de por defecto). Con él
    van las franjas del día, el «Mix diario», que cambia a las 5:00, y la semana del
    «Descubrimiento semanal», aunque el servidor vaya en UTC (lo normal en un contenedor).
  - **Rutas** (todas con la sesión de la persona; las tarjetas, como las de Inicio):
    `GET` y `POST /Moonfin/Kostv/Music/Settings` (`{ "Learn": true, "Listens": 1234, "Since":
    "…Z" }`; con `{ "Learn": false }` no se apunta nada de esa persona y las mezclas usan
    solo lo que sabe Jellyfin); `DELETE /Moonfin/Kostv/Music/Listens` (borra sus escuchas, `204`);
    `POST /Moonfin/Kostv/Music/Context` (`{ "Source": "mix:daily-2", "ItemIds": […] }`: de dónde
    viene lo que va a sonar, se recuerda 6 horas en memoria; `204`); `POST
    /Moonfin/Kostv/Music/Event` (lo que hace la persona y el servidor no ve, apuntado con la
    fecha: `{ "Type": "playlist_add", "ItemIds": […] }` de 1 a 500 ids, `{ "Type": "request",
    "Album", "Artist", "DeezerAlbumId" }` todos opcionales, de hasta 200 caracteres y el id de
    hasta 32; con «Aprender» apagado no se apunta; o `{ "Type": "dislike", "ItemIds": […],
    "Kind": "song" | "artist" }`, que va aparte, ver abajo; `204`, y `400` con un tipo desconocido
    o un cuerpo que no es así); `GET
    /Moonfin/Kostv/Music/Mixes` (`{ "Day", "Mixes": [ { "Id": "daily-1", "Genre", "Artists",
    "Items" } ] }`: hasta 4 «Mix diario» de unas 50 canciones, uno por cada género principal de
    la persona, mitad de lo que escucha y no salta y mitad de esos artistas sin oír y de
    artistas parecidos de casa, sin repetir canciones entre mezclas ni el mismo artista seguido;
    iguales todo el día, que empieza a las 5:00); `GET /Moonfin/Kostv/Music/Discovery` (`{
    "Week": "2026-W47", "Seeds": [hasta 10 artistas], "Songs": null }`) y `PUT` con `{ "Week",
    "Songs": […] }` (hasta 30 canciones y 64 KB, solo la semana en curso: `409` si es otra,
    `413` si pasa de 64 KB; las de semanas pasadas se borran); y `GET
    /Moonfin/Kostv/Music/Moment` (`{ "Slot": "tarde", "Ready": true, "Items": […] }`: 40
    canciones para `manana` 6–12, `tarde` 12–20 o `noche` 20–6, un 40 % de lo que escucha a
    esa hora y el resto parecidas; `Ready: false`, sin `Items`, hasta tener 25 escuchas no
    saltadas de esa franja en al menos 5 días de los últimos 60; una noche que pasa de las
    doce cuenta como un solo día).
  - **Listas y ♥ con canciones de fuera** (`/Moonfin/Kostv/Music/Away/...`, contrato en
    `docs/musica-toda-la-musica.md`, sección 8): los «huecos» de cada lista de Jellyfin van en
    `kostv-musica/listas-fuera/<lista>.json` (uno por lista, el mismo para todos: los lee quien
    puede ver la lista y los cambia su dueña o quien la tiene compartida con edición; hasta 500)
    y el ♥ de cada persona en `fuera-favoritas.json` de su carpeta (hasta 2000; cuenta en el gusto
    como un ♥ desde el día siguiente). Cuando una llega a casa (lo dice la app con `Arrived`, o el
    complemento la reconoce al entrar o cambiar canciones en la biblioteca y en la ronda diaria,
    por título, artista y disco, y duración ±3 s), entra en la lista de Jellyfin en su sitio
    (como la dueña de la lista, si puede verla), se quita el hueco y el ♥ pasa a ser el de
    Jellyfin para quien puede verla. Al borrar una lista se van sus huecos.
  - **La emisora de una canción** (`GET /Moonfin/Kostv/Music/Station?seed=<id | stremfin:<DeezerId>>&title=…&artist=…&limit=50&away=true|false`,
    contrato en `docs/musica-radio.md`): con fuentes gratis, desde el servidor y sin historial
    de casa. Canciones que la gente escucha junto a esa (ListenBrainz Labs, sus dos conjuntos: el
    reciente y MLHD; hasta 6 grabaciones de MusicBrainz de la semilla, por nombre, búsqueda e
    ISRC), solo de su estilo (su artista, sus relacionados en Deezer y, de los parecidos de
    ListenBrainz, solo los que también son relacionados de los relacionados en Deezer o comparten
    una etiqueta de estilo fuerte en MusicBrainz); detrás, la radio del artista en Deezer (que va
    delante si pasan menos de 10) y lo más escuchado de los relacionados. Fuera versiones (en
    directo, remezclas, karaoke…, salvo que la semilla lo sea) y villancicos fuera de diciembre;
    pesa menos lo de más de 15 años de distancia. Por persona: lo de casa que ve (por MBID o
    título y artista), si no el `DeezerId` de Deezer (por ISRC o búsqueda); lo de casa que no ve
    no sale tampoco de fuera; sin su «No me gusta»; a quien tiene edad máxima en Jellyfin, solo la
    radio de Deezer y nada explícito de fuera; nunca dos seguidas del mismo artista, como mucho 2
    por artista cada 25 y el de la semilla de vuelta cada 8. Ritmo propio (2 peticiones/s a cada
    servicio, 1/s a MusicBrainz, User-Agent `kOS-TV-complemento/<versión>`); respuestas guardadas 30
    días y la emisora del día, 1 día, en `kostv-emisoras/` (64 MB como mucho). Contesta en 5 s
    como mucho: si no está, lo que haya con `Source: "fallback"` y la termina por detrás. En el
    panel, opcionales: token de ListenBrainz y clave de Last.fm (`track.getSimilar` solo con ella).
- **El botón Descubrir se sincroniza** como los demás (`showDiscoverButton`), con
  su valor por defecto en la página.
- **La marca del paso a la ficha de kOS TV se sincroniza** junto al estilo de la
  ficha (`kostvDetailAdopted`), para que un aparato nuevo no vuelva a cambiar a
  kOS TV un estilo que la persona eligió a mano.
- **Sin la web de Moonfin dentro:** el paquete no la lleva, así que el botón que
  el oficial añade a la cabecera de la web de Jellyfin solo sale si esa web
  existe.

## Versiones

`X.Y.Z.N`: `X.Y.Z` es la versión oficial en la que se basa y `N`, la nuestra
sobre ella. La primera, **3.1.0.1**, es la oficial 3.1.0 con los cambios de
arriba. Al traer una versión oficial nueva, `X.Y.Z` pasa a la suya y `N` vuelve
a 1.

Ahora se basa en la oficial **3.1.1**: la siguiente que se publique es la
**3.1.1.1**. De la 3.1.1 trae que las filas de una lista de TMDB lean todas sus
páginas (no solo los 20 primeros títulos) y que las de MDBList salgan con la
sinopsis, los géneros y la duración en el idioma pedido; además, las fuentes
`justwatch` y `tmdb_discover` de las filas personalizadas
(`discoverChartsSupported` y `pushSupported` en `/Moonfin/Ping`) y la ruta
`/Moonfin/Games/{libraryId}/Recent`, que la app aún no usa.

## Compilar y publicar

- En local (hace falta el SDK de .NET 8): `bash complemento/compilar.sh 3.1.1.1`.
  Deja el zip y su suma md5 en `complemento/salida/`.
- **Que funcione con cada Jellyfin:** se compila contra Jellyfin 10.10, pero
  tiene que valer también en 10.11 y en 12. Algo que Jellyfin cambió después
  (un método que ahora devuelve otro tipo, una propiedad que ya no existe)
  compila sin avisar y solo falla en el servidor, al usarse. Lo comprueba
  `Jellyfin/tools/abi-check/comprobar.sh` (hace falta el SDK de .NET 10): carga
  el complemento con las DLL reales de Jellyfin 10.10.0, 10.10.7, 10.11.11 y
  12.4.0 y falla si alguna referencia no existe, si algún método no compila o
  si una tarea no da sus disparadores. Tras compilar:
  `bash complemento/Jellyfin/tools/abi-check/comprobar.sh complemento/Jellyfin/backend/bin/Release/net8.0/publish/Moonfin.Server.dll`
  (con más versiones detrás, prueba esas). El automatismo lo pasa antes de
  publicar. En el código nuevo, lo que cambió entre versiones va por nombre
  (`Helpers/LibraryQueries.cs`, `UserReflection.cs`, `TaskTriggers.cs`): nunca
  `GetItemList`, `GetItemIds`, `SimilarTo`, `LinkedChild.Id` ni
  `TaskTriggerInfo.Type` directos.
- Para publicar, el automatismo **Complemento del servidor**
  (`.github/workflows/complemento.yml`), con la versión y sus novedades. Pasa
  las pruebas, compila, lo comprueba con cada Jellyfin, publica «Complemento kOS TV X.Y.Z.N» y lo añade al
  catálogo. Todas son pre-publicaciones, para que las apps no las tomen por una
  versión suya.

El catálogo, que se añade en Jellyfin en **Panel > Complementos >
Repositorios**:

```
https://github.com/kikope97/kos-TV/releases/download/complemento/manifest.json
```

## Traer los cambios del oficial

La carpeta se trajo con `git subtree` (un solo commit con la 3.1.0 exacta) y se
puso al día a la 3.1.1 de la misma forma. Para traer una versión oficial nueva
(la etiqueta es su versión, por ejemplo `3.2.0`):

```
git subtree pull --prefix=complemento https://github.com/Moonfin-Client/plugin 3.2.0 --squash
```

(Si deja la etiqueta oficial en el repositorio, se borra con `git tag -d 3.2.0`:
no debe subirse, porque las nuestras de la app son también números.)

En los conflictos manda lo nuestro: nombre e identificador de kOS TV, textos en
español, imágenes y lo quitado (Emby, Go, su `.github`, su `build.sh` y sus
`manifest.json`, su `PRIVACY_POLICY.md`, la notificación de prueba y su
prueba `NotificationTestEndpointTests.cs`; Seerr, el calendario y las descargas
atascadas: si traen cambios en esos archivos, se vuelven a borrar). Después, pruebas, una pasada a
los textos nuevos (que se vean en español y sin el nombre del oficial; en la
página de ajustes, lo nuevo de Seerr se oculta con la clase `kostvSinSeerr` y
lo que la app no usa, con `kostvNoSeUsa`) y publicar `3.2.0.1`.
