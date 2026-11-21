# Plan: «Toda la música» (escuchar lo que no está en casa)

Stremfin 1.97 puede dar el audio de cualquier canción de Deezer que no esté en
Jellyfin («Escuchar mientras llega», `docs/stremfin-api.md` 8.35–8.38). Con eso
la app puede servir de sustituto de Spotify aunque en casa haya poca música.

## 1. Cómo funciona el servidor (resumen)

- `GET /music/songs/{deezer_id}/listen`: «la quiere escuchar». **Espera** hasta
  que el audio está listo y devuelve su dirección (`url`, sin token, 12 h).
  - Al momento si ya estaba guardada (`listen_ready`).
  - Unos segundos si se estaba adelantando.
  - Unos 8–12 s si es nueva.
  - Cuenta una escucha. No hace falta preguntar cada pocos segundos: se espera a
    la respuesta (con un tiempo de espera de 60 s).
- `POST /music/songs/{deezer_id}/prefetch`: «quizás la escuche». Responde al
  momento con el estado (`ready`, `downloading`, `queued`, `in_jellyfin`,
  `unavailable`) y la descarga por detrás, con menos prioridad. Se puede repetir
  sin coste para saber cómo va. Como mucho 3 esperando por persona; el servidor
  descarga una cada 10 s y tiene topes por hora y día.
- Regla única: `in_jellyfin` → desde Jellyfin; si no, con `deezer_id` → en
  streaming; sin `deezer_id` → solo pedir el álbum.

## 2. Qué verá la familia

**Ajuste** en *Ajustes > Reproducción > Música*: «Qué música enseñar»: *Solo la
de casa* (como ahora) o *Toda la música*. Por persona, guardado en el complemento.

**Con «Toda la música»:**

- **Se acaba el gris:** en el buscador, las listas de éxitos, «Para ti», el
  descubrimiento, la ficha de artista y la de álbum, todas las canciones se
  ponen con un toque, OK o clic, igual que las de casa. Primero sale lo de casa
  y debajo el resto.
- **Las peticiones pasan a segundo plano:** las tarjetas ya no llevan «Pedir»;
  pedir está en la ficha del álbum y en Reproduciendo.
- **Ficha de un álbum que no está en casa:** aviso «Este disco no está en casa ·
  se escucha en streaming» y el botón «Pedir álbum» (con su estado: Pedido, De
  camino…). «Reproducir» y «Aleatorio» funcionan.
- **Reproduciendo una canción en streaming:**
  - una píldora fija «No está en casa · en streaming» con «Pedir álbum» al lado;
  - en la cola, un icono pequeño en las que no están en casa.
- **«Preparando la canción…»:** si no estaba lista, la carátula late
  suavemente y debajo se lee «No está en casa: la estamos preparando para que la
  escuches. Tarda unos segundos». A los 20 s: «Está tardando más de lo normal».
  Igual en la cápsula, en pequeño.
- **Si no se puede:**
  - no existe o no hay audio (404): «Esta canción no se puede escuchar» y pasa
    a la siguiente;
  - fallo del servidor (503): «Ahora no se puede escuchar. Prueba más tarde».
- **Listas con todo el catálogo:**
  - las listas de éxitos, «Para ti» y el descubrimiento semanal se ponen
    enteras;
  - la radio de un artista y la reproducción continua (∞) mezclan lo de casa
    con lo de fuera (radio de Stremfin);
  - más adelante, el Mix diario también con canciones de fuera.
- **Niños:** lo explícito de fuera no sale en perfiles con límite de edad, como
  ya pasa con lo que viene de Stremfin.

## 3. Adelantar sin pasarse

El servidor descarga lo adelantado de una en una y cada 10 s, así que hay que
pedir con criterio:

| Cuándo | Qué se adelanta |
|---|---|
| La canción que suena va por la mitad (o le quedan 90 s, lo que llegue antes) | La siguiente de la cola, si no está en casa ni lista. Con aleatorio, la que de verdad va a sonar |
| Ficha de un álbum abierta 3 s | La primera canción (o la que tiene el foco o el ratón encima 2 s) |
| Una canción enfocada 2 s en el buscador o en una lista (tele y ordenador) | Esa canción |
| La siguiente cambia (saltas, reordenas, aleatorio) | La nueva siguiente; la anterior se deja estar |

Como mucho la siguiente y la de después. Nunca la lista entera. Lo que ya viene
con `listen_ready` no se adelanta. Si `prefetch` dice `unavailable`, se quita de
la cola antes de llegar a ella.

## 4. Cómo se hace por dentro

- **Stremfin en la app:**
  - `listen_ready` en las canciones;
  - `deezer_id`, `listen_ready` y `album_jellyfin_id` en las canciones de un
    álbum;
  - `musicListen` (con 60 s de espera) y `musicPrefetch`, con los errores 404,
    503 y 429 bien tratados.
- **Canciones de fuera en la cola:**
  - se meten como canciones normales con un id propio (`stremfin:<deezerId>`),
    su título, artista, álbum, duración y carátula de Deezer;
  - así la cápsula, Reproduciendo, la notificación del móvil y la cola funcionan
    sin cambios.
- **Un resolvedor nuevo** delante del de siempre:
  - si la canción es de fuera, llama a `listen`, guarda la dirección hasta que
    caduca y se la da al reproductor sin cabeceras de Jellyfin;
  - si `listen` dice que ya está en casa, la cambia por la de Jellyfin;
  - si la dirección caducó (404), la pide otra vez.
- **Lo que no se le manda a Jellyfin:**
  - los informes de reproducción de estas canciones;
  - en Reproduciendo se esconden el ♥ y la letra, porque son de Jellyfin;
  - en el menú, «No me gusta» queda para el artista hasta la fase 3.
- **Aprender:** cada escucha de fuera se le cuenta al complemento con un evento
  nuevo (`stream_listen`: canción, artista, álbum, cuánto se oyó y cómo acabó),
  para que cuente en los gustos como las de casa.
- **Chromecast:** las canciones de fuera no se envían en la primera versión.
- **Al volver a abrir la app** (móvil), la cola guardada recupera estas
  canciones y vuelve a pedir su dirección.
- **Web:**
  - por el paso `/stremfin` del contenedor web (mismo origen) funciona sin más;
  - con Stremfin en otra dirección, hace falta que Stremfin mande permisos CORS
    también en el audio;
  - Safari no siempre reproduce Opus (`audio/webm`), así que conviene pedirle a
    Stremfin el audio en mp4 para el iPhone.

## 5. Fases

| Fase | Qué |
|---|---|
| 1 | El ajuste; escuchar desde el buscador, la ficha de álbum y la de artista; «Preparando…»; el aviso con «Pedir álbum» en Reproduciendo; la cola mezclada; los informes; adelantar la siguiente |
| 2 | Las listas de éxitos, «Para ti» y el descubrimiento semanal reproducibles enteros; la radio de artista y el ∞ con lo de fuera; adelantar al pararse en fichas y canciones |
| 3 | Lo de fuera en los gustos: `stream_listen` en el complemento, «No me gusta» de canciones de fuera (por `deezer_id`) y el Mix diario con canciones de fuera |
| 4 | Con la parte 2 del plan de música (sin cortes): precargar también las de fuera |

Cada fase: pruebas, Stremfin falso con `listen` y `prefetch` (con su espera),
fotos en tele (barra de arriba y lateral), móvil y web, y `KOSTV.md` al día.

## 6. Lo que solo se comprueba en aparatos de verdad

- La tele y el móvil reproduciendo AAC y Opus, y saltando dentro de la canción.
- La notificación del móvil con la carátula de Deezer.
- La web en el iPhone (Opus y CORS).
- Cuánto tarda de verdad el paso a una canción que no se adelantó.

## 7. Decisiones y contrato (2026-11-21)

Decisiones tomadas: ajuste por persona con «Toda la música» por defecto (niños
sin lo explícito de fuera); lo escuchado en streaming cuenta para aprender; sin
Chromecast para lo de fuera; las cuatro fases de golpe, con la parte 2 del plan
de música (sin cortes en tele y móvil) para la fase 4.

Rutas del complemento (`/Moonfin/Kostv/Music/`), nuevas o ampliadas:

| Ruta | Qué cambia |
|---|---|
| `GET`/`POST Settings` | Campo nuevo `"Catalog": "all" \| "home"` (por persona, `all` por defecto). `POST` acepta `{ "Catalog": "home" }` solo, `{ "Learn": … }` solo, o los dos. Un complemento antiguo no lo trae: la app usa entonces un ajuste del aparato. |
| `POST Event` con `"Type": "stream_listen"` | Cuerpo `{ "Type": "stream_listen", "DeezerId": "…", "Title": "…", "Artist": "…", "Album": "…", "Genre": "…" (opcional), "Played": 123.4, "Duration": 224, "EndedBy": "natural" \| "next" \| "stop" \| "closed" \| "error", "Source": "…" (como en Context), "Shuffle": false }`. Se apunta como una escucha (`item` = `stremfin:<DeezerId>`, `outcome` con la misma regla que las de casa) y cuenta en el gusto del artista y del género por nombre. Solo con «Aprender» encendido. `204`; mal formado, `400`. Un `Title`, `Artist` o `Album` de más de 200 caracteres se recorta a 200 (no da `400`). `Artist` puede faltar: la escucha cuenta igual, pero no en el gusto por artista. Como mucho 60 por minuto y 3000 al día por persona (muy por encima de lo que manda una persona escuchando, aunque salte canción tras canción); lo que pase de ahí se descarta con `204`. |
| `POST Event` con `"Type": "dislike"` | Además de `ItemIds`, acepta `"Songs": [ { "DeezerId", "Name", "Artist" } ]` para canciones de fuera (Kind `song`). |
| `GET Dislikes` | Las canciones de fuera salen con `"DeezerId"` e `"Id": null`. `DELETE Dislikes/{id}` acepta también `stremfin:<DeezerId>`; si no se puede guardar, `500` y sigue en la lista. `DELETE Dislikes` vacía la lista entera, también lo de fuera, aunque la app 1.18.0 no lo enseñe: «Borrar todo» deja la lista vacía en todos los aparatos. |
| `GET Taste` | Los artistas de fuera van detrás de los 20 de casa (`"Id": null`), y `Learned` cuenta solo las escuchas de casa (ver el plan de música, sección 6). |

La app filtra lo de fuera con esa lista (por `DeezerId` y por nombre de
artista).

## 8. Listas y ♥ con canciones de fuera (2026-11-21)

Jellyfin solo guarda en sus listas y en sus favoritos canciones suyas. Para poder
añadir canciones de fuera, el complemento guarda «huecos» en las listas de
Jellyfin y un ♥ propio; cuando la canción llega a casa, la pasa a Jellyfin sola.

Decisiones: las listas siguen siendo las de Jellyfin; añadir o dar ♥ **no pide el
álbum solo** (se ofrece: «Añadida. ¿Pedir el álbum para tenerla en casa?»); en
otras apps la lista se ve solo con lo de casa; entra en la 1.19.0.

### Qué ve la familia

- En el menú de una canción de fuera (y en Reproduciendo): «Añadir a una lista»
  (las listas de siempre y «Nueva lista») y ♥.
- La lista se ve entera, en su orden, con la nube en las de fuera; al ponerla
  suena todo (lo de fuera en streaming). Se quitan y se mueven como las demás.
- «Tus favoritas» lleva también las de fuera con ♥.
- Niños: lo explícito de fuera no sale. «No me gusta»: se salta al ponerla.
  «Solo la de casa»: las de fuera salen en gris y no suenan, pero no se borran.
- Cuando la canción llega a casa, pasa a ser una canción normal de la lista (en
  su sitio) y su ♥ pasa a ser el de Jellyfin.

### Rutas del complemento (`/Moonfin/Kostv/Music/`)

Una canción de fuera (`AwaySong`): `{ "DeezerId", "Title", "Artist", "Album",
"AlbumDeezerId"?, "ArtistDeezerId"?, "Cover"?, "Duration"? (s), "Explicit" }`.
Textos recortados a 200; `DeezerId` solo cifras (≤ 32).

| Ruta | Qué hace |
|---|---|
| `GET Away/Playlist/{playlistId}` | `{ "Entries": [ { …AwaySong, "After": "<id>" \| null, "Added": fecha } ] }`. `After` es el id del elemento que la precede en la lista completa: un id de Jellyfin o `stremfin:<DeezerId>`; `null` = la primera. La app las coloca recorriendo la lista de Jellyfin; si su `After` ya no está, van al final. Quien puede ver la lista de Jellyfin puede leerla; si no, `404`. |
| `POST Away/Playlist/{playlistId}` | Cuerpo `{ "Songs": [AwaySong…], "After": "<id>" \| null }` (`After` ausente = al final). Solo quien puede cambiar la lista (su dueña o con permiso de edición). Repetida (mismo `DeezerId`) no se duplica. `200` con la lista como en el `GET`; `403` sin permiso; `400` mal formado. Tope: 500 canciones de fuera por lista. |
| `DELETE Away/Playlist/{playlistId}/{deezerId}` | Quita una. `204` (también si no estaba). |
| `POST Away/Playlist/{playlistId}/Order` | Cuerpo `{ "Ids": [ …el orden completo, ids de Jellyfin y stremfin:<id> ] }`: recalcula los `After` de las de fuera. Lo de Jellyfin lo mueve la app con la API de Jellyfin, como ahora. `204`. |
| `GET Away/Favorites` | `{ "Songs": [ { …AwaySong, "Added": fecha } ] }` de la persona, lo último primero. |
| `POST Away/Favorites` | Cuerpo `AwaySong`. `204`. Cuenta para el gusto como un ♥ (desde el día siguiente). Tope 2000. |
| `DELETE Away/Favorites/{deezerId}` | `204`. |
| `POST Away/Arrived` | Cuerpo `{ "DeezerId", "JellyfinId" }`: la app avisa de que una canción de fuera ya está en casa (Stremfin dijo `in_jellyfin`). El complemento comprueba que `JellyfinId` existe y es Audio, y entonces, en todas las listas y ♥ donde esté ese `DeezerId`: la mete en la lista de Jellyfin en su sitio (tras su `After`) y borra el hueco; da el ♥ de Jellyfin a quien lo tenía y lo quita de los suyos. `204`. |

Además, el complemento busca solo las que han llegado: al entrar canciones en la
biblioteca (evento de Jellyfin) y en la ronda diaria, por título, artista y
álbum normalizados (y duración ±3 s si la tiene), y hace lo mismo que `Arrived`.

Con un complemento antiguo (rutas en `404`), la app no ofrece «Añadir a una
lista» ni ♥ en canciones de fuera.
