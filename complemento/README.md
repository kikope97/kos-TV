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
- **Solo Jellyfin:** fuera las versiones para Emby, Plex y Silo y lo de GitHub
  del oficial.
- **Sin Seerr:** fuera todo lo suyo (la conexión, el acceso único, sus avisos de
  peticiones, la búsqueda de lo que no tienes) y lo que colgaba de él: el
  calendario de Sonarr y Radarr con sus recordatorios y el aviso de descargas
  atascadas. kOS TV pide las cosas a su propio servicio. A las apps se les dice
  que no hay Seerr ni calendario (`/Moonfin/Ping`), y en la página de ajustes
  esos apartados están ocultos (su código sigue buscándolos por su nombre).
- **La página de ajustes en español**, con los mismos nombres que la app para los
  mismos ajustes, y sin lo que las apps de kOS TV no usan (cuatro valores por
  defecto y los campos de la web oficial, ocultos con la clase `kostvNoSeUsa`).
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
    géneros, cuándo (UTC, y día, hora y día de la semana en la hora del servidor), cuánto se
    oyó y lo que dura, cómo acabó (`completed`: ≥ 90 % o hasta el final; `skipped`: < 30 s o
    < 50 %; `stopped`: el resto), el aparato (`tv`, `mobile`, `web` u `other`, por el nombre
    de la app y del aparato) y de dónde venía (`source`, si la app lo dijo). Va en
    `kostv-musica/<usuario>/AAAA-MM.jsonl` (una línea JSON por escucha o ♥, un archivo por
    mes) en la carpeta de datos del complemento; se guarda 12 meses (lo anterior se borra a
    diario y al escribir) y se borra la carpeta de la persona al borrar su usuario. En la misma
    carpeta, `settings.json` (si aprende) y `discovery.json` (la lista de la semana).
  - **Rutas** (todas con la sesión de la persona; las tarjetas, como las de Inicio):
    `GET` y `POST /Moonfin/Kostv/Music/Settings` (`{ "Learn": true, "Listens": 1234, "Since":
    "…Z" }`; con `{ "Learn": false }` no se apunta nada de esa persona y las mezclas usan
    solo lo que sabe Jellyfin); `DELETE /Moonfin/Kostv/Music/Listens` (borra sus escuchas, `204`);
    `POST /Moonfin/Kostv/Music/Context` (`{ "Source": "mix:daily-2", "ItemIds": […] }`: de dónde
    viene lo que va a sonar, se recuerda 6 horas en memoria; `204`); `GET
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
    esa hora y el resto parecidas; `Ready: false`, sin `Items`, hasta tener 25 escuchas de esa
    franja en al menos 5 días de los últimos 60).
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

## Compilar y publicar

- En local (hace falta el SDK de .NET 8): `bash complemento/compilar.sh 3.1.0.1`.
  Deja el zip y su suma md5 en `complemento/salida/`.
- Para publicar, el automatismo **Complemento del servidor**
  (`.github/workflows/complemento.yml`), con la versión y sus novedades. Pasa
  las pruebas, compila, publica «Complemento kOS TV X.Y.Z.N» y lo añade al
  catálogo. Todas son pre-publicaciones, para que las apps no las tomen por una
  versión suya.

El catálogo, que se añade en Jellyfin en **Panel > Complementos >
Repositorios**:

```
https://github.com/kikope97/kos-TV/releases/download/complemento/manifest.json
```

## Traer los cambios del oficial

La carpeta se trajo con `git subtree` (un solo commit con la 3.1.0 exacta). Para
traer una versión oficial nueva (la etiqueta es su versión, por ejemplo
`3.2.0`):

```
git subtree pull --prefix=complemento https://github.com/Moonfin-Client/plugin 3.2.0 --squash
```

(Si deja la etiqueta oficial en el repositorio, se borra con `git tag -d 3.2.0`:
no debe subirse, porque las nuestras de la app son también números.)

En los conflictos manda lo nuestro: nombre e identificador de kOS TV, textos en
español, imágenes y lo quitado (Emby, Go, su `.github`, su `build.sh` y sus
`manifest.json`; Seerr, el calendario y las descargas atascadas: si traen
cambios en esos archivos, se vuelven a borrar). Después, pruebas, una pasada a
los textos nuevos (que se vean en español y sin el nombre del oficial; en la
página de ajustes, lo nuevo de Seerr se oculta con la clase `kostvSinSeerr`) y
publicar `3.2.0.1`.
