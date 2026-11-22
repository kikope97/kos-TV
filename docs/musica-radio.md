# Radio de una canción con sentido

## Decisiones (2026-11-22, del usuario)

- **Fuente gratis:** ListenBrainz (canciones que la gente escucha junto a esa, datos públicos, sin clave) con un **filtro de estilo con Deezer** (artistas relacionados; API pública, sin clave). Si faltan, se completa con lo más escuchado de esos artistas parecidos y la radio de Deezer.
- **Last.fm, opcional:** desde el 1 de diciembre de 2026 su API pide cuenta Pro. Queda como fuente opcional: si algún día se pone una clave en el panel del complemento, se usa también; si no, todo funciona sin ella.
- **Nadie configura nada por persona.** Todo lo hace el complemento desde el servidor. En el panel, opcionales y para toda la casa: un token de ListenBrainz (más margen) y la clave de Last.fm. Nunca en la app ni en el repositorio.
- **Se hace en el complemento** (`GET /Moonfin/Kostv/Music/Station`) y además se le pide a Stremfin una radio por canción.
- **Fuera lo de «parecido en casa»:** lo que se escucha seguido en casa no decide qué viene después en la radio ni en el ∞.
- Antes de darla por buena, prueba a ciegas con 24 canciones de estilos distintos.

## Contrato de la emisora (2026-11-22)

Manda sobre la «Opción A» del estudio (que era con Last.fm como fuente principal).

`GET /Moonfin/Kostv/Music/Station?seed=<itemId | stremfin:<DeezerId>>&title=…&artist=…&limit=50&away=true|false`
(con la sesión de la persona; `title`/`artist` ayudan si la semilla es de fuera).

Respuesta: `{ "Seed": { "Title", "Artist", "Mbid"? }, "Items": [ { "Card": <tarjeta de casa, la misma forma que en Taste/Mixes> | null, "Away": { "Title", "Artist", "Album"?, "DeezerId", "Explicit"?, "Cover"?, "Duration"?, "AlbumDeezerId"?, "ArtistDeezerId"? } | null, "Why": "listenbrainz" | "style" | "deezer" | "lastfm" } ], "Source": "listenbrainz" | "lastfm" | "fallback", "Partial"? }` (los campos de `Away` desde `Cover` y `Partial`, añadidos después: ver «Añadido» más abajo).

- **Receta (gratis):** canciones que la gente escucha junto a la semilla (ListenBrainz, sin clave) → **filtro de estilo**: solo artistas que sean el de la semilla, sus relacionados en Deezer o sus parecidos en ListenBrainz → si faltan, lo más escuchado de esos artistas parecidos → por último, la radio del artista en Deezer. Last.fm `track.getSimilar` se suma solo si hay clave en el panel.
- **Variedad:** sin dos seguidas del mismo artista y como mucho 2 por artista en 25.
- **Sin historial de casa:** lo que se escucha seguido en casa no cuenta.
- **Filtros por persona:** control parental de Jellyfin (lo de casa que no ve, fuera; tampoco por streaming), «No me gusta» (canciones y artistas), explícito para quien tiene límite de edad.
- **Casar:** primero con casa (MBID de `ProviderIds` o título+artista normalizados); si no está en casa, con Deezer (búsqueda pública) para tener `DeezerId`; sin ninguno, se descarta.
- **`away=false`** («Solo la de casa»): solo `Card`.
- **Caché en disco:** respuestas externas 30 días; la emisora calculada de una semilla, 1 día. Ritmo propio: ≤ 2 peticiones/s a cada servicio, ≤ 1/s a MusicBrainz, con User-Agent genérico del complemento.
- **Panel (opcional, para toda la casa):** token de ListenBrainz y clave de Last.fm. Vacíos, funciona igual.
- **Errores:** si las fuentes externas no contestan, `Source: "fallback"` con lo que haya (puede venir vacío); `404` en un complemento antiguo → la app usa lo de hoy con los arreglos de la fase 1.
- **Añadido (2026-11-22, tras la auditoría; solo campos nuevos, lo de antes no cambia):**
  - `Away` lleva también `Cover` (portada del disco en Deezer, 500 px, solo `https://`), `Duration` (segundos), `AlbumDeezerId` y `ArtistDeezerId`, de los datos de Deezer de la canción; y `Explicit` sale de su `explicit_lyrics` (las de ListenBrainz, al casarlas con Deezer). Cualquiera puede faltar (`null`) si Deezer no lo dice. Así lo de fuera sale con su carátula en la cola, y quien tiene límite de edad sigue teniendo canciones de fuera no explícitas (`Explicit: false`).
  - `Partial: true` mientras la emisora se está calculando (la respuesta rápida de los primeros segundos); `false` cuando ya está entera. Una emisora entera hecha solo con la radio de Deezer (reguetón, infantil…) dice `Source: "fallback"` y `Partial: false`: no hay nada más que esperar. Sin el campo (un complemento de antes), la app toma `fallback` como «sin terminar».
  - Al casar con Deezer, se recorre la emisora en su orden: lo que se escucha junto a la semilla se casa antes que el relleno (que ya trae su `DeezerId`). Si el tiempo de cálculo se acaba con al menos 60 que pueden sonar, la emisora se da por entera con esas. Al apagar el servidor, lo que se está calculando se deja (no se guarda a medias).

**La app:** «Crear emisora» (menú, ficha, Reproduciendo, artista de fuera) y el ∞ usan `Station` (con «Toda la música», detrás de la radio de la canción de Stremfin: ver «Orden de las fuentes»). El ∞ siembra con **la última canción elegida por la persona** (no con las que puso él), pide más cuando quedan pocas y no repite. Sin intercalar una a una casa/fuera: el orden es el de la emisora. Lo de fuera suena como siempre por Stremfin (`listen`).

## Orden de las fuentes (2026-11-22, con Stremfin 1.101.0)

Decisión del usuario: usar **las dos**, la radio de una canción de Stremfin (`docs/stremfin-api.md` 8.40) y la emisora del complemento.

**Con «Toda la música»** («Crear emisora» de una canción, de un artista desde su canción, el «⋯» de Reproduciendo y el ∞):

1. **Radio de la canción en Stremfin** (`GET /music/songs/{deezer_id}/radio?only=all&limit=50`). La semilla necesita su id de Deezer: una de fuera ya lo tiene; una de casa se casa con `POST /music/songs/match` (8.39: título, primer artista y el ISRC si Jellyfin lo tiene en `ProviderIds`), una vez por canción (guardado 7 días; «Deezer no la tiene», 6 horas; si Deezer no contestó, `failed`, se vuelve a intentar otra vez). Lo que una radio dice que está en casa (`jellyfin_id` + `deezer_id`) queda casado sin llamada, y la canción de un artista de Stremfin desde la que sale su emisora también.
   - Cada canción: con `jellyfin_id`, la de Jellyfin (se pide a Jellyfin con la sesión de la persona; si no la da, es su control parental: **fuera, nunca por streaming**); sin él, la de fuera por Stremfin (`listen`).
   - Filtros de la app: «No me gusta» (canción y artista), lo explícito de fuera para quien tiene límite, la semilla, lo que ya está en la cola y sin dos seguidas del mismo artista (Stremfin ya pone como mucho 2 por artista cada 25).
2. **Emisora del complemento** (`Station`, el contrato de arriba), si la de Stremfin falla: no contesta en 30 s, `503`, `429`, `404` de una canción que Deezer no tiene, un Stremfin anterior a la 1.101.0, o no queda nada que pueda sonar para esa persona.
3. **Lo de antes** (la radio de los artistas de Stremfin y la mezcla de Jellyfin detrás), si tampoco hay complemento.

**Con «Solo la de casa»**: la emisora del complemento con `away=false`, como hasta ahora; luego lo de antes.

**Un Stremfin sin la ruta.** El `404` de una ruta que no existe y el de una canción que Deezer no tiene dicen lo mismo (`not_found`). Los separa la versión que da `/me` (`server.version`): por debajo de 1.101.0 (1.100.0 para casar) no se pide y, si contesta 404, se deja 30 minutos (como las rutas que faltan del complemento). Sin versión conocida, dos 404 seguidos de canciones distintas cuentan como «no la tiene».

**El límite de 10 por minuto** (compartido con `/music/recommendations` y `/music/radio`): una llamada por emisora y por cada vez que el ∞ añade, nunca más. La radio de cada canción se guarda una hora en la app (Stremfin la guarda un día). Tras un `429` no se pide hasta pasado su `Retry-After` (y la radio de artistas tampoco, que cuenta en lo mismo); tras otro fallo, un minuto; una canción sin radio, 6 horas. Casar cuenta en los 60 por minuto, aparte.

**El ∞** siembra con la última canción que eligió la persona (3.2). Su radio ya está guardada desde que empezó la emisora, así que no cuesta llamada; cuando ya no da nada que no esté en la cola, pide **la radio de la última canción que sonó** (lo que aconseja la API), con su única llamada de esa vez. Si la de la semilla hubo que pedirla y no dio nada nuevo, no se hace otra llamada: va la del complemento.

**Lo de los 75 s** (volver a pedir la emisora cuando el complemento la da a medias, `Partial`) sigue solo para la del complemento: la de Stremfin llega entera a la primera.

## Estudio


*(«Crear emisora» y la reproducción automática ∞. Solo investigación y plan: no se ha tocado nada del repositorio.)*

## En corto (para decidir)

**Qué pasa hoy.** Cuando creas una emisora desde una canción, la mitad de lo que suena
(o todo, con «Solo la de casa») lo elige **Jellyfin al azar entre todas las canciones
de casa que tienen el mismo género** que la semilla. Si la canción está etiquetada como
«Pop» o «Latino», vale cualquier canción pop o latina de cualquier época. La otra mitad
viene de la «radio de Deezer» **del artista** (no de la canción), que suele estar bien
de estilo. Las dos se intercalan una y una, así que se nota el salto cada dos canciones.
Y el ∞ vuelve a sembrar con la última canción que sonó, aunque la hubiera elegido él
mismo, así que la emisora se va desviando.

**Qué proponemos.** Que la emisora se haga con lo que **escucha la gente en general**
después o junto a esa canción, no con lo que se escucha en casa:

1. **Last.fm** (datos de millones de personas que apuntan lo que escuchan): tiene
   «canciones parecidas a esta canción» y «artistas parecidos». Es gratis para uso no
   comercial y pide una clave, que se guardaría **en el servidor de casa** (panel del
   complemento), nunca en la app ni en el repositorio.
2. Una **regla de estilo**: solo entra lo que sea del mismo estilo (artistas parecidos
   o mismas etiquetas), para que no se cuele un éxito de otro género solo por ser de
   la misma época.
3. Si Last.fm no sabe nada de esa canción (pasa con música poco conocida), lo de ahora
   pero mejor: la radio de Deezer del artista y canciones de casa de artistas parecidos,
   **ya no al azar** dentro del género.
4. Lo que se escucha en casa **no se usa** para elegir lo que viene detrás (lo de
   «si mamá pone Juanito después de Pepito»). Sí se sigue respetando «No me gusta»,
   el control de los niños y «Solo la de casa».

**Dónde:** en **nuestro complemento** (el servidor de casa), que ya guarda otras claves
(la de TMDB) y conoce la música de casa. La app le pide «la emisora de esta canción» y
él responde con las de casa y con las de fuera ya listas para sonar. A Stremfin le
podemos pedir, aparte, una mejora pequeña (texto en el apartado 7) que lo haría más
rápido, pero **no hace falta esperarla**.

**Primero se prueba antes de programar nada:** una lista de 24 canciones de prueba
(pop español y latino, reguetón, rock, flamenco, infantil…) y comparar lo que sale hoy
con lo que saldría así. Si Last.fm flojea en reguetón o flamenco, se ve ahí.

**Recomendación:** sí. Crear la clave de Last.fm (gratis, 5 minutos), hacer la prueba
(1 día) y, si convence, el complemento y la app (unas 2 semanas de trabajo en total).

### Las 3 decisiones

| # | Decisión | Recomendación |
|---|---|---|
| 1 | ¿Creamos una **clave de Last.fm** (cuenta gratis, uso no comercial, se pone en el panel del complemento)? | **Sí.** Es la mejor fuente pública de «lo que la gente escucha junto a esta canción» que queda abierta (Spotify la cerró). |
| 2 | ¿Se hace en **nuestro complemento** (sin depender de nadie) y además se le pide a Stremfin la mejora del apartado 7? | **Sí, las dos**; el complemento primero. Si Stremfin la hace, la app la usa; si no, todo funciona igual. |
| 3 | ¿Quitamos de las emisoras lo de **«Parecido en casa»** (el plan anterior iba a usar lo que suena seguido en casa para la radio y el ∞)? | **Sí, para emisoras y ∞**: va contra lo que quieres. Puede quedarse, si acaso, para los «Mix diario», que sí son de cada uno. |

---

## 1. Cómo funciona hoy, de punta a punta

### 1.1. En la app

| Pieza | Archivo | Qué hace |
|---|---|---|
| «Crear emisora» (menú de canción, ficha) | `lib/ui/widgets/music/kostv_stream_play.dart` → `playKostvStation` → `kostvStationFor` | Pone la semilla y detrás su emisora. |
| «Crear emisora» de un artista de Stremfin | mismo archivo, `playKostvArtistStation` | Solo radio de Stremfin por `artistIds`. |
| «Crear emisora» desde el «···» de Reproduciendo | `lib/ui/screens/music/kostv_now_playing_screen.dart` (`case 'radio'`) | Con «Toda la música», `kostvStationFor`; con «Solo la de casa», `KostvMusicService.mix` (InstantMix puro). |
| ∞ (reproducción automática) | `lib/ui/widgets/music/kostv_now_playing.dart` → `_maybeAutoplay` | Cuando quedan ≤ 2 en la cola, siembra con **la canción que suena ahora** (`seed = item`), añade 25. Con «Toda la música», `kostvStationFor(homeLimit: 25)`; si no, `getInstantMix(seed.id, limit: 25)` tal cual. |
| Mezcla de las dos fuentes | `lib/data/services/stremfin/kostv_stream_radio.dart` → `kostvStationOf` + `kostvInterleaveRadio` | Pide a la vez el InstantMix de Jellyfin (`homeMix`) y `/music/radio` de Stremfin de los **artistas** de la semilla (`kostvStationArtists`: por nombre, los 2 primeros de una de casa; por id de Deezer, el de una de fuera). Junta `home = [...InstantMix, ...radio que está en casa]` y `away = radio que no está`, y **las alterna una a una**, sin dos seguidas del mismo artista. Quita «No me gusta», la propia semilla y lo explícito para niños. |
| Caché | `KostvStreamRadio` | Cada conjunto de artistas, 1 hora en la app (Stremfin: 1 hora la lista y **1 día** la radio de cada artista). |

### 1.2. InstantMix de Jellyfin (verificado en el código de Jellyfin)

`MusicManager.GetInstantMixFromSong` toma **solo los géneros de la canción** y hace
`GetItemList(IncludeItemTypes=Audio, GenreIds=…, OrderBy=Random, Limit=200)`.
Es decir: **200 canciones al azar con alguno de esos géneros**. No mira artista, época,
idioma, ritmo ni nada más. Con géneros amplios («Pop», «Latin», «Rock»), o con
canciones que traen varios géneros, el resultado es casi aleatorio. Sin género, nada.

### 1.3. Stremfin `/music/radio` (de `docs/stremfin-api.md`, 8.34)

- Se siembra **por artista** (`artists` por nombre exacto, o `artist_ids` de Deezer),
  nunca por canción. Por debajo, Deezer `GET /artist/{id}/radio`.
- Mezcla las radios por turnos, como mucho 3 canciones del mismo artista; la radio de
  cada artista se guarda **un día** (el mismo artista da lo mismo todo el día).
- Límite: 10 por minuto, compartido con `/music/recommendations`.
- **Comprobado** con la API pública de Deezer: la radio del artista de Bad Bunny trae
  40 canciones de Myke Towers, J Balvin, Rauw Alejandro, Rosalía, Karol G, Ozuna…:
  **coherente de estilo**. Deezer **no** tiene radio de canción en su API pública
  (`/track/{id}/radio` y `/track/{id}/related` dan error «Unknown path»).

### 1.4. El complemento

No tiene nada de radio. Sí tiene: artistas parecidos de Jellyfin (`KostvMusicService.SimilarArtists`, que en Jellyfin 12 usa sus proveedores locales), el gusto de cada persona (`Taste`), los «No me gusta», las escuchas con `session`/`prev` (lo que suena seguido en casa) y el patrón de claves de API guardadas en el panel (`TmdbApiKey`, `TmdbApiKeys.ResolveAsync`) con `IHttpClientFactory`.

### 1.5. Por qué suena «sin sentido»

1. **El InstantMix es aleatorio dentro del género**, y va primero en la lista de casa
   (`[...mix, ...radioHome]`): manda él. Con «Solo la de casa» es lo único que hay.
2. **Intercalar una y una** dos fuentes de calidad distinta: cada dos canciones, un salto.
3. **Semilla de artista, no de canción**: una balada y un tema de discoteca del mismo
   artista dan la misma radio.
4. **El ∞ se desvía**: siembra con la canción que suena, que muchas veces la añadió
   el propio ∞ (de la parte aleatoria). Tras dos o tres vueltas ya no tiene nada que
   ver con la primera.
5. **Nombres que no casan**: la radio se pide por el nombre exacto del artista; si en
   Jellyfin está escrito distinto («Rosalia» / «ROSALÍA», «feat.»), Deezer no lo
   encuentra y solo queda el InstantMix.
6. **Repetición**: misma radio de artista todo el día, así que el ∞ con el mismo
   artista repite canciones de fuera.

---

## 2. Opciones investigadas (noviembre de 2026)

✔ = comprobado en la web o con una llamada real; ≈ = documentado por terceros; ? = suposición, hay que probarlo.

| Fuente | Qué da | Acceso y límites | Encaja | Notas |
|---|---|---|---|---|
| **Last.fm `track.getSimilar`** | Canciones parecidas a una canción, «según datos de escucha» (coocurrencia de scrobbles), con `match` ✔ | Clave gratis (`api_key`), sin login de usuario ✔. Límite ≈ 5 peticiones/s por IP de media en 5 min; error 29 al pasarse ✔. Condiciones: **solo no comercial**, citar a Last.fm con enlace, cachear según cabeceras, tope de 100 MB guardados ✔ | **Sí, la principal** | Calidad en reguetón, flamenco y pop español: **?** (Last.fm tiene más público anglosajón e indie). Por eso la prueba de la fase 0. |
| Last.fm `artist.getSimilar`, `track.getTopTags`, `artist.getTopTags`, `artist.getTopTracks` | Artistas parecidos, etiquetas de estilo («reggaeton», «flamenco», «spanish rock») | Misma clave ✔ (mismo API) | **Sí**: regla de estilo y respaldo | |
| **ListenBrainz Labs `similar-recordings`** | Grabaciones que suenan en las mismas sesiones de escucha (datos abiertos) ✔ | Sin clave; JSON en `labs.api.listenbrainz.org/similar-recordings/json?recording_mbids=…&algorithm=session_based_days_…` ✔. Sin límites documentados; servicio «labs», sin garantías | **Como apoyo** | Probado con «Tití me preguntó» (Bad Bunny): sale Rosalía, Quevedo, Manuel Turizo, Karol G… pero también Harry Styles, Taylor Swift, Sam Smith: **mezcla éxitos de la misma época, no de estilo**. Solo vale con regla de estilo. Necesita MBID (Jellyfin lo tiene si está etiquetado; si no, `labs…/recording-search/json?query=` ✔ funciona). |
| ListenBrainz LB Radio (`/1/explore/lb-radio`, troi) | Emisora por **artista**, etiqueta, lista… ✔ | Ahora pide token de usuario ≈ | No | No acepta una canción como semilla ✔. |
| MusicBrainz | Ids (MBID) para casar canciones | 1 petición/s ≈ | Solo para casar | Mejor el `recording-search` de ListenBrainz Labs. |
| **Deezer API pública** | `/artist/{id}/radio` ✔, `/artist/{id}/related` ≈, `/search/playlist` ✔ (listas públicas), `/radio/genres` ✔ (radios editoriales por género), `genre_id` en álbum | Sin clave para lectura ✔; cuota ≈ 50 peticiones/5 s (dato de terceros); Deezer no amplía límites sin acuerdo comercial ✔ | **Sí, de respaldo** (ya lo usa Stremfin) | **No hay radio por canción** ✔. |
| Spotify Web API | Antes: recomendaciones por canción y artistas relacionados | Cerrado para apps nuevas desde 27-11-2024 ✔; en febrero de 2026 además las listas ajenas ya no dan sus canciones (solo metadatos) y la búsqueda baja a 10 resultados ✔ | **No** | Ni para «minar» listas públicas. |
| YouTube Music «a continuación» / radio | Radio **por canción**, muy buena (≈) | Solo con clientes no oficiales (p. ej. `ytmusicapi`); va contra sus condiciones; puede romperse | **No** por nuestra parte | Stremfin ya usa YouTube para el audio: es decisión suya, no la proponemos. |
| Apple Music API | Catálogo y gráficas | Programa de desarrolladores de Apple (de pago, ≈ 99 $/año); sin «canciones parecidas» de catálogo pública (?) | No | |
| Minar listas públicas (Deezer) | Coocurrencia: canciones que aparecen juntas en listas de otros | Deezer no tiene «listas que contienen esta canción» ✔ (solo buscar listas por texto); habría que rastrear miles de listas | **Más adelante**, quizá | Caro y lento; Last.fm ya da esa coocurrencia hecha. |
| AcousticBrainz | Rasgos de audio | Cerrado desde 2022 (datos congelados) ≈ | No | |
| Análisis del audio propio (tempo, energía) | Parecido «sonoro» | En el servidor, con librerías tipo Essentia: mucho trabajo y CPU | No por ahora | |
| Discogs estilos | Estilos finos por disco | Clave gratis, 60/min ≈ | Opcional | Last.fm y Deezer ya dan estilo suficiente. |

**Conclusión:** la combinación con mejor relación calidad/esfuerzo es
**Last.fm (canción → canciones parecidas) + regla de estilo (artistas parecidos y etiquetas de Last.fm, género de Deezer) + respaldo con la radio de artista de Deezer y canciones de casa de artistas parecidos**. ListenBrainz, solo como desempate o si Last.fm no responde.

---

## 3. Cómo se haría la emisora nueva

### 3.1. La receta (para una semilla S = título + artista, y su id de casa o de Deezer)

1. **Candidatas por canción**: Last.fm `track.getSimilar(S, limit=100, autocorrect=1)`.
2. **Regla de estilo**: entra una candidata si su artista está en
   `artist.getSimilar(artista de S, limit=100)` **o** comparte al menos una de las 5
   primeras etiquetas de estilo del artista de S (ignorando etiquetas de época o
   genéricas: «00s», «seen live», «female vocalists», «pop» a secas…) **o** es el
   mismo artista. Lo demás fuera.
3. **Si quedan menos de 25**: completar con las «top tracks» de los artistas parecidos
   (en orden de parecido) y, si aún faltan, con la radio de Deezer del artista
   (`/music/radio` o directamente Deezer en el complemento).
4. **Casar con casa**: por MBID de grabación si Jellyfin lo tiene; si no, por título
   y artista normalizados (sin tildes, mayúsculas, «feat.», «(Remastered)», «- Live»…).
5. **Casar con fuera** (solo con «Toda la música»): las que no están en casa, a canción
   de Deezer (`deezer_id`), para que suenen con «Escuchar mientras llega». Las que no
   casan, fuera.
6. **Filtros**: «No me gusta» (canción y artista), explícito para niños, lo que
   Jellyfin no deja ver a esa persona, lo que ya está en la cola.
7. **Variedad**: nunca dos seguidas del mismo artista; como mucho 2 del mismo artista
   cada 25; nada del mismo disco seguido; la semilla y su artista vuelven cada ~8.
8. **Orden**: por parecido (`match`), con un poco de azar (para que dos emisoras de la
   misma canción no sean idénticas) y **sin** intercalar fuentes una a una: lo de casa
   y lo de fuera según su parecido, con preferencia suave a lo de casa (suena al momento).

### 3.2. El ∞ sin desviarse

- La semilla de cada tanda es la **canción que la persona eligió** (la que empezó la
  cola o la última puesta a mano), no la última que añadió el ∞. La app ya distingue
  lo que vino solo (`autoplayItems`, `noteChosen`).
- Si la persona va saltando lo que propone, la siguiente tanda pesa más hacia la
  semilla y menos hacia «parecidas de las parecidas». Esto es lo que hace **esta
  persona ahora mismo**, en esta cola: no es historial de la casa.

### 3.3. Lo que **no** se usa

- El historial de casa (`session`/`prev` del complemento) **no** decide qué viene
  detrás. Tampoco el gusto de la persona (`Taste`) para elegir candidatas: como mucho,
  para desempatar entre dos igual de parecidas (opcional, apagado al principio).
- Por eso se propone (decisión 3) que lo de «Parecido en casa» del plan
  `docs/musica-plan-fundido-y-aprender.md` (3.3) no se use para radio ni ∞.

---

## 4. Dónde se hace

### Opción A — en nuestro complemento (**recomendada**)

Ruta nueva, con la sesión de la persona:

`GET /Moonfin/Kostv/Music/Station?seed=<itemId | stremfin:<DeezerId>>&title=…&artist=…&limit=50&away=true|false`

Devuelve `{ "Seed": {…}, "Items": [ {"Card": tarjeta de casa | null, "Away": {"Title","Artist","DeezerId"?} | null, "Match": 0.73, "Why": "lastfm|style|deezer" } ], "Source": "lastfm" | "fallback" }`.

- **Clave de Last.fm** en el panel del complemento (campo nuevo junto al de TMDB, en
  `PluginConfiguration`), solo en el servidor. La app nunca la ve.
- **Caché en disco**: respuestas de Last.fm 30 días por canción/artista (unos pocos KB
  cada una; muy lejos de los 100 MB del límite de Last.fm), la emisora calculada 1 día.
- **Ritmo**: cola propia a ≤ 2 peticiones/s hacia Last.fm (una emisora nueva son unas
  4 llamadas: canción parecida, artistas parecidos, etiquetas, y quizá top tracks).
- Casa con casa usando la biblioteca (MBID `ProviderIds` o nombre normalizado),
  respeta el control parental (`InternalItemsQuery(user)`) y los «No me gusta».
- **Fuera**: si Last.fm no da id de Deezer, el complemento puede buscarlo en la API
  pública de Deezer (`/search/track?q=artist:"…" track:"…"`, sin clave) y devolver
  `DeezerId`. La app pide luego a Stremfin lo de siempre para sonar
  (`/music/songs/{id}/listen`), así que **Stremfin no cambia**. (Alternativa sin
  Deezer en el complemento: la app busca con `/music/songs?q=…`, 120/min; para 25
  canciones va justa y es lenta, por eso es mejor en el servidor.)
- Si el complemento es antiguo (404) o no hay clave: la app usa lo de hoy, con los
  arreglos de la fase 1.

**Ventajas:** no depende de otro equipo; la clave se queda en casa; sirve igual con
«Solo la de casa»; la misma emisora en tele, móvil y web.
**Inconveniente:** algo más de código en el complemento (C#), con sus pruebas.

### Opción B — en Stremfin

Pedirles una «radio de canción». Ellos ya casan Deezer ↔ Jellyfin (`in_jellyfin`,
`jellyfin_id`) y tienen la caché de Deezer, así que les sale natural. Pero: dependemos
de sus tiempos, la clave de Last.fm la pondrían ellos, solo ve lo que Deezer conoce (la
música de casa que no está en Deezer queda fuera) y con «Solo la de casa» no siempre
estaría disponible. **Se pide en paralelo** (texto en el apartado 7); si llega, el
complemento o la app pueden usarla para la parte de fuera.

### Opción C — en la app

Descartada: la clave iría dentro del APK y de la web (el repositorio es público).

---

## 5. Cómo medir que mejora

**Lista de prueba (24 semillas),** elegidas por el dueño entre lo que se escucha en
casa, por ejemplo: 4 de pop español (de los 80 a hoy), 4 de pop latino, 4 de reguetón /
urbano, 3 de rock español, 3 de flamenco y rumba, 2 de cantautor, 2 infantiles, 2 en
inglés. Que haya canciones conocidas y poco conocidas.

**Para cada semilla, antes y después**, las 15 primeras de la emisora:

| Medida | Cómo | Objetivo |
|---|---|---|
| Mismo estilo | El dueño marca ✔/✗ cada una, sin saber de qué versión es (hoja de cálculo con las dos listas desordenadas) | ≥ 80 % (hoy, a ojo, ~40–50 %: medirlo) |
| Cobertura | ¿Last.fm dio ≥ 15 candidatas? | Saber en qué estilos hace falta el respaldo |
| Se puede oír | % en casa o con `deezer_id` | ≥ 90 % con «Toda la música» |
| Variedad | Artistas distintos en 15 | ≥ 10 |
| Niños | Ninguna explícita de fuera en un perfil con límite | 0 |

**Después, en uso real** (ya se apunta en el complemento: fuente `radio`, cómo acabó
cada canción): % de canciones de emisora saltadas antes de 30 s y % enteras, 2–4
semanas antes y después. Se puede añadir al panel «Cómo va la música» que ya está
planeado.

---

## 6. Fases

| Fase | Qué | Dónde | Esfuerzo |
|---|---|---|---|
| 0 | **Prueba en frío**: script fuera del repositorio que, con la clave de Last.fm, saca la emisora nueva de las 24 semillas y la de hoy (InstantMix + radio de Deezer) para compararlas. Decidir si sigue. | Local | 1 día |
| 1 | **Arreglos rápidos en la app, sin claves** (valen aunque lo demás tarde): el ∞ siembra con la última canción **elegida**, no con la que añadió él; no intercalar una y una; el InstantMix pasa a ser último recurso y se filtra por artistas parecidos de Jellyfin o de la radio de Deezer (lo que no sea de esos artistas, fuera); con «Solo la de casa», pedir a Stremfin la radio con `only=available` también. | App | 1–2 días |
| 2 | **Ruta `Station` en el complemento** con Last.fm, regla de estilo, respaldo Deezer, caché, ritmo, casar con casa y con Deezer, filtros y variedad; campo de la clave en el panel (y un aviso si falta o no vale); pruebas con respuestas grabadas de Last.fm. Publicar como complemento `X.Y.Z.N` **cuando lo digas**. | Complemento | 3–5 días |
| 3 | **La app usa `Station`** en «Crear emisora» (menú, ficha, Reproduciendo, artista de fuera) y en el ∞, con lo de la fase 1 si no está. Línea «Las emisoras usan datos de Last.fm» con enlace en *Ajustes > Música* (lo piden sus condiciones), en `app_es.arb`/`app_en.arb`. Probado y con fotos en tele (barra de arriba y lateral), móvil (con barra de abajo) y web. | App | 2–3 días |
| 4 | Pedir a Stremfin la mejora del apartado 7; si la hacen, usarla. | Stremfin | Su tiempo |
| 5 | Medir 2–4 semanas y ajustar pesos (cuánto pesa el estilo, cuánto azar). ListenBrainz como desempate si hace falta. | Complemento | 1 día + espera |

Todo esto es igual en tele, móvil y web: no hay nada solo de la tele. La interfaz casi
no cambia (los mismos botones); lo nuevo visible es la línea de Last.fm en Ajustes y el
campo de la clave en el panel del complemento (que se llama «kOS TV», sin el nombre del
oficial).

---

## 7. Texto para pedir a Stremfin (si se decide)

> **Asunto: radio de una canción (no de un artista) en la API de música**
>
> Hola. En la app de casa usamos `GET /music/radio` para la emisora de una canción y
> para la reproducción continua. Va bien de estilo, pero se siembra por artista, así
> que una balada y un tema de baile del mismo artista dan la misma emisora, y la radio
> de cada artista es la misma todo el día.
>
> ¿Podríais añadir, con la misma forma de respuesta que `/music/radio` (canciones 7.7
> con `in_jellyfin`, `jellyfin_id`, `explicit`, `album` y `reason`)?
>
> 1. `GET /music/songs/{deezer_id}/radio?only=all|missing|available&limit=1-100`:
>    canciones parecidas a **esa canción**, según lo que la gente escucha junto a ella
>    (por ejemplo, Last.fm `track.getSimilar`, que es gratuito para uso no comercial),
>    limitadas a artistas parecidos al de la canción, y completadas con la radio de
>    Deezer del artista cuando no hay datos. Con como mucho 2 canciones por artista.
> 2. Y, si es fácil, `POST /music/songs/match` con hasta 50 `{ "title", "artist" }` →
>    la canción de Deezer de cada una (7.7) o `null`, para casar listas que vienen de
>    fuera sin gastar 50 búsquedas.
>
> No necesitamos que guardéis nada de la persona: solo mandamos la canción. Si la
> primera no os encaja, con la segunda nos basta. ¡Gracias!

---

## 8. Riesgos y cosas a vigilar

- **Last.fm y la música en español**: puede dar pocas candidatas en flamenco, reguetón
  reciente o artistas pequeños. Por eso la fase 0 y el respaldo con Deezer, que sí
  conoce bien lo latino (comprobado).
- **Condiciones de Last.fm**: uso no comercial (familia: sí), citarles con enlace,
  cachear como dicen, no más de ≈ 5 peticiones/s. Si cancelan la clave, se vuelve al
  respaldo sin romper nada.
- **Privacidad**: al servicio de fuera solo va **el título y el artista** de la
  semilla, desde el servidor de casa, sin usuario ni nada de la persona. El historial
  de casa no sale ni se usa.
- **Casar nombres**: «feat.», remezclas y versiones en directo pueden fallar; se
  normalizan y, con MBID de Jellyfin, mejor.
- **Clave**: nunca en el repositorio ni en el APK; solo en el panel del complemento.

## Fuentes

- Código de Jellyfin, `MusicManager.cs` (InstantMix aleatorio por género, 200): https://github.com/jellyfin/jellyfin/blob/master/Emby.Server.Implementations/Library/MusicManager.cs
- Last.fm `track.getSimilar`: https://www.last.fm/api/show/track.getSimilar
- Condiciones del API de Last.fm: https://www.last.fm/api/tos · Introducción y claves: https://www.last.fm/api/intro
- ListenBrainz Labs (similar-recordings, recording-search): https://labs.api.listenbrainz.org/
- LB Radio (entidades, sin semilla de canción): https://troi.readthedocs.io/en/latest/lb_radio.html
- Deezer, preguntas de desarrolladores: https://support.deezer.com/hc/en-gb/articles/360011538897-Deezer-FAQs-For-Developers
- Spotify, cierre de recomendaciones y relacionados (nov. 2024): https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api
- Spotify, cambios de febrero de 2026: https://developer.spotify.com/documentation/web-api/references/changes/february-2026
- Llamadas reales hechas para este plan (API pública, sin datos de la casa): Deezer `/artist/{id}/radio`, `/track/{id}/radio` (no existe), `/search/playlist`, `/radio/genres`; ListenBrainz Labs `similar-recordings` y `recording-search`.
