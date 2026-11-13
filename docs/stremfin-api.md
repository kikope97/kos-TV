# API de Stremfin para la app de Jellyfin de casa

> Versión de la API: **v1** · Stremfin 1.90.2 · documento generado el 13/11/2026
>
> Dirección base: **`https://stremfin.ejemplo.com/api/v1`**

Este documento es todo lo que necesita quien programe un cliente de Jellyfin (por ejemplo, una app Android basada en uno de código abierto) para integrarse con Stremfin: cómo se identifica cada persona, qué direcciones hay, qué devuelve cada una con ejemplos, qué significan todos los estados y cómo montar cada pantalla.

---

## Índice

1. [Qué hace la API](#1-qué-hace-la-api)
2. [Lo básico](#2-lo-básico)
3. [Autenticación: el token de Jellyfin](#3-autenticación-el-token-de-jellyfin)
4. [Quién eres: administrador, alguien de casa o nadie](#4-quién-eres-administrador-alguien-de-casa-o-nadie)
5. [Errores](#5-errores)
6. [Límites](#6-límites)
7. [Objetos comunes](#7-objetos-comunes)
8. [Direcciones](#8-direcciones)
9. [Estados, uno a uno](#9-estados-uno-a-uno)
10. [Cómo montar la app, pantalla a pantalla](#10-cómo-montar-la-app-pantalla-a-pantalla)
11. [Ejemplo en Kotlin (Retrofit + kotlinx.serialization)](#11-ejemplo-en-kotlin-retrofit--kotlinxserialization)
12. [Probar sin servidor real](#12-probar-sin-servidor-real)
13. [Seguridad: lo que la app debe cuidar](#13-seguridad-lo-que-la-app-debe-cuidar)
14. [Historial de la API](#14-historial-de-la-api)

---

## 1. Qué hace la API

Stremfin es el panel que mantiene la biblioteca de Jellyfin de casa: busca, descarga y coloca películas, series y música. La API deja que la app de Jellyfin que usa la familia haga, con el usuario con el que ha entrado en Jellyfin:

- **Ver los tops**: lo más visto y lo nuevo de **Netflix, Disney+ y Prime Video**, y el top **global** (todas las plataformas), de películas y de series.
- **Buscar** películas, series y música (álbumes, artistas y canciones), solo lo que tienes, solo lo que no o todo, y pedir los siguientes resultados.
- **Ver las listas de éxitos** de música (lo más escuchado en España y por género), los discos nuevos de los artistas que sigue la casa y lo más pedido en casa; cada canción lleva al álbum que pedir.
- **Ver un artista** con todos sus discos (cuáles tienes y cuáles no) y **un álbum** con sus canciones (cuáles tienes ya y en qué álbum).
- **Saber si una película se puede descargar ya y si será rápida** (sin ver enlaces: los elige Stremfin).
- **Ver los tráilers** de una película o una serie, el doblado al español de España primero, sin buscar en YouTube.
- **Ver la ficha completa**: tráiler, reparto, quién la dirige o la creó, en qué plataforma se puede ver ya, su edad recomendada y su saga.
- **Abrir la ficha de una persona** (un actor, una directora…) desde el reparto o desde el buscador: quién es y sus películas y series, con cuáles tienes.
- **Descubrir**: títulos parecidos a uno, las películas de una saga (cuáles tienes) y explorar por género, año y plataforma.
- **Saber si algo ya está en Jellyfin** (y su id de Jellyfin, para abrirlo y reproducirlo), si se está descargando o si alguien ya lo ha pedido.
- **Pedir** una película, una temporada, todo lo que falta de una serie o un álbum.
- **Ver sus peticiones** y cómo van: esperando respuesta, aceptada, en cola, esperando al archivo, descargándose (porcentaje, velocidad y tiempo restante, episodio a episodio; en música: pedido a la descarga, en su cola, descargando, importándose), rechazada (con motivo) o ya en Jellyfin. También las de los demás.
- **Retirar** una petición que aún espera respuesta.
- **Enterarse** de lo que pasa con sus peticiones (aceptada, rechazada, ya en Jellyfin…) sin tener Telegram, y ver **Próximamente**: lo que está al llegar.
- **Avisar de un problema** con algo de Jellyfin («no está en castellano», «se corta»…): le llega al administrador y, cuando haya una versión nueva, a quien avisó.

Cada persona pide **con revisión** (al administrador le llega para aceptarla o no) o **directo** (se acepta sola y se descarga sin preguntar). Lo decide el administrador en la página *Usuarios* del panel; la app solo lo muestra.

Lo que la API **nunca** da: enlaces de descarga, addons, el servicio debrid, rutas de disco, ajustes ni nada del panel. La app no necesita nada de eso.

---

## 2. Lo básico

| | |
|---|---|
| Dirección base | `https://stremfin.ejemplo.com/api/v1` |
| Formato | JSON en UTF-8, en las peticiones y en las respuestas (`Content-Type: application/json`) |
| Autenticación | El token de acceso de Jellyfin del usuario, en `Authorization: Bearer <token>` |
| Fechas | ISO 8601 con zona (`2026-11-11T18:30:00+01:00`); las fechas sin hora, `AAAA-MM-DD` |
| Textos | Los `message` y `*_label` vienen en español de España, listos para enseñar al usuario |
| Imágenes | Direcciones `https` públicas (TMDB y Deezer): se cargan directamente, sin token |
| Ids | `tmdb_id` (número) para películas y series; `deezer_id` (texto con dígitos) para álbumes, artistas y canciones (solo el de un álbum, EP o sencillo sirve para pedir); `jellyfin_id` (texto) para abrir algo en Jellyfin |
| Versión | `v1` va en la ruta. Se añadirán campos nuevos sin aviso: **ignora los campos que no conozcas**. Quitar o cambiar un campo exigiría una `v2` |
| Texto | UTF-8 válido en todos los parámetros (si no, `422 invalid`) |
| Desde un navegador (CORS) | Solo las webs que el administrador ponga en *Ajustes → Acceso desde fuera* («Webs que pueden usar la API desde el navegador»), por su origen exacto (esquema, dominio y puerto). A esas se les responde `Access-Control-Allow-Origin: <su origen>`, `Vary: Origin` y `Access-Control-Expose-Headers: Retry-After`, también en los errores; la consulta previa (`OPTIONS`, sin token) recibe `204` con `Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS`, `Access-Control-Allow-Headers: Authorization, Content-Type` y `Access-Control-Max-Age: 600`, y no cuenta para ningún límite. Nunca `*` ni credenciales: la sesión va en `Authorization`. Las apps nativas (sin `Origin`) no necesitan nada |
| Caché | Cada `GET` correcto (200) lleva `ETag`. `/requests`, `/notifications` y la disponibilidad llevan la hora en la respuesta, así que cambian siempre: ahí usa `since`. Si lo mandas en `If-None-Match` y la respuesta no ha cambiado, llega `304 Not Modified` **sin cuerpo**: usa la que ya tenías. Va por usuario (`Cache-Control: private, no-cache`). Opcional: sin `If-None-Match`, todo como siempre |

La API está **apagada por defecto**: se enciende en el panel, *Ajustes → Acceso desde fuera*. Apagada, todo responde `503 api_disabled`.

---

## 3. Autenticación: el token de Jellyfin

No hay usuarios ni contraseñas propios de Stremfin. La app ya entra en Jellyfin con usuario y contraseña; **ese mismo token** sirve para Stremfin.

### 3.1 El flujo

1. La app entra en Jellyfin como siempre (con el SDK de Jellyfin o `POST /Users/AuthenticateByName` del servidor de Jellyfin). Jellyfin devuelve un `AccessToken` y el `User.Id`.
2. En **cada** llamada a Stremfin, la app manda ese token:

   ```http
   GET https://stremfin.ejemplo.com/api/v1/me
   Authorization: Bearer <AccessToken de Jellyfin>
   Accept: application/json
   ```

3. Stremfin le pregunta a **su** Jellyfin (el de casa, el que tiene configurado; nunca otro) de quién es ese token (`GET /Users/Me`, mandando solo el token: tu dispositivo en Jellyfin no cambia de nombre). Si Jellyfin dice que no vale, la respuesta es `401 invalid_token`.
4. Stremfin recuerda la respuesta **5 minutos**, guardada bajo una huella (SHA-256) del token, nunca el token. Un token rechazado se recuerda 1 minuto.

También se aceptan, por comodidad, las cabeceras que usan los clientes de Jellyfin (se mira la primera que traiga un token con buena forma):

- `Authorization: MediaBrowser Client="…", Device="…", DeviceId="…", Version="…", Token="<token>"` (con o sin comillas en `Token`)
- `X-Emby-Token: <token>` o `X-MediaBrowser-Token: <token>`. Útil si `Authorization` ya la usa otra cosa (por ejemplo, un proxy con contraseña)

Un token tiene entre 8 y 200 caracteres de letras, números, `.`, `_` o `-` (los de Jellyfin son 32 caracteres hexadecimales).

**Nunca** pongas el token en la URL (`?api_key=`): no se acepta.

### 3.2 Cuándo deja de valer

- Si el usuario **cierra sesión** en la app (o se le revoca el dispositivo en Jellyfin), el token deja de valer en Jellyfin, y en Stremfin como mucho 5 minutos después.
- Si el usuario está **desactivado en Jellyfin**, Stremfin lo trata como token no válido.
- Con `401` (`unauthenticated` o `invalid_token`), la app debe volver a pedir usuario y contraseña de Jellyfin. **No reintentes en bucle**: 20 tokens nuevos por minuto desde la misma dirección (IPv6: desde el mismo bloque /64) bloquean un minuto (`429 too_many_attempts`). Un token que ya funcionó no se ve afectado por los fallos de otros.

### 3.3 Si Jellyfin no responde

Stremfin no puede comprobar el token y responde `503 jellyfin_unavailable` con `Retry-After`. Durante 30 s no vuelve a preguntar a Jellyfin por tokens nuevos (los ya comprobados siguen funcionando). No es culpa del usuario: enseña «Ahora mismo no se puede comprobar tu sesión» y reintenta más tarde. **No borres la sesión** por un 503.

---

## 4. Quién eres: administrador, alguien de casa o nadie

En la página *Usuarios* del panel, el administrador dice quién es cada usuario de Jellyfin:

| `role` | Quién | Qué puede hacer |
|---|---|---|
| `admin` | El administrador de Stremfin (el que ha elegido «Tú (administrador)» en su usuario de Jellyfin) | Todo. Lo que pide se acepta y se pone en marcha al momento, sin límites |
| `member` | Alguien de casa | Si tiene acceso: todo, con su modo de peticiones (`review` o `direct`) y sus límites. Sin acceso: solo `/me` |
| `none` | Un usuario de Jellyfin que el administrador aún no ha dado de alta | Solo `/me`. El resto responde `403 not_linked` |

`GET /me` responde siempre (si el token vale) para que la app sepa qué enseñar. El resto de direcciones exige acceso: `admin`, o `member` con acceso; si no, `403 not_linked` o `403 no_access`.

**Modo de peticiones** (`access.mode` en `/me`):

| `mode` | Qué pasa al pedir |
|---|---|
| `review` | La petición queda **esperando respuesta** (`pending`). Al administrador le llega a Telegram con «Aceptar / Rechazar». |
| `direct` | Se **acepta sola** (`approved`, `direct: true`) y se pone en marcha: película, la mejor versión disponible (o espera a que haya una buena y entonces se descarga sola); serie, se buscan los enlaces y se descarga; álbum, se pide a la descarga de música. Al administrador no le llega nada. |
| `admin` | Como `direct`, sin límites. |
| `null` | No puede pedir. |

Si alguien con modo `direct` pide algo que otra persona ya había pedido y esperaba respuesta, esa petición queda aceptada para todos.

Quien además tiene **Telegram** (`access.telegram: true`) recibe en el bot los avisos de sus peticiones (aceptada, rechazada, ya en Jellyfin). Quien no tiene, se entera solo por la app: ver [10.6](#106-avisos).

---

## 5. Errores

Todos los errores tienen la misma forma:

```json
{
  "error": {
    "code": "invalid_token",
    "message": "Tu sesión de Jellyfin no es válida o ha caducado. Vuelve a entrar en la app."
  }
}
```

Los de validación añaden `fields` con el detalle de cada campo:

```json
{
  "error": {
    "code": "invalid",
    "message": "El campo type es obligatorio.",
    "fields": { "type": ["El campo type es obligatorio."] }
  }
}
```

`message` está pensado para enseñarlo tal cual. La app decide por `code`:

| HTTP | `code` | Qué significa | Qué hacer |
|---|---|---|---|
| 401 | `unauthenticated` | Falta el token o no tiene buena forma | Volver a entrar en Jellyfin |
| 401 | `invalid_token` | Jellyfin dice que el token no vale (sesión cerrada, caducada, usuario desactivado) | Volver a entrar en Jellyfin |
| 403 | `not_linked` | Tu usuario de Jellyfin no está dado de alta en Stremfin | Enseñar el mensaje; esconder pedir y los tops |
| 403 | `no_access` | Estás dado de alta pero sin acceso ahora mismo | Igual |
| 403 | `not_yours` | Intentas retirar una petición que no es tuya | Enseñar el mensaje |
| 404 | `not_found` | No existe (película, serie, petición o dirección de la API) | Enseñar el mensaje |
| 405 | `method_not_allowed` | Método equivocado para esa dirección | Error de programación |
| 409 | `already_answered` | Retirar una petición que ya tiene respuesta | Refrescar la petición |
| 422 | `invalid` | Parámetros que faltan o no valen (`fields` dice cuáles) | Error de programación (o texto vacío del usuario) |
| 429 | `too_many_requests` | Más de 300 llamadas por minuto de ese usuario | Esperar los segundos de `Retry-After` |
| 429 | `too_many_requests` | Más de 120 búsquedas (también explorar, fichas de persona y búsqueda de canciones), o de 60 fichas de serie, disponibilidades, Próximamente, artistas, álbumes, canciones o listas de éxitos, por minuto (ver [6](#6-límites)) | Esperar `Retry-After` |
| 429 | `too_many_requests` | Más de 30 veces por minuto pidiendo, retirando o avisando de problemas | Esperar `Retry-After` |
| 429 | `too_many_attempts` | Más de 20 tokens nuevos por minuto desde esa dirección, o demasiadas sesiones nuevas a la vez en todo el servidor | Esperar `Retry-After`; no reintentar en bucle |
| 500 | `server_error` | Fallo inesperado del servidor (queda en sus registros) | Reintentar más tarde |
| 503 | `api_disabled` | La API está apagada en *Ajustes → Acceso desde fuera* | Enseñar el mensaje; reintentar más tarde |
| 503 | `jellyfin_not_configured` | Stremfin aún no está conectado a Jellyfin | Enseñar el mensaje |
| 503 | `jellyfin_unavailable` | Stremfin no puede preguntar a Jellyfin por el token | Reintentar tras `Retry-After`; **no** cerrar sesión |
| 503 | `source_unavailable` | Una fuente externa (TMDB, JustWatch, Deezer) no responde | Reintentar más tarde |
| 503 | `busy` | Solo en `POST /requests` y `POST /problems`: otra petición o aviso se está guardando en ese mismo instante (van de uno en uno) | Reintentar al momento (una o dos veces) |
| otro | `http_<código>` | Cualquier otro error HTTP | Enseñar el mensaje |

`POST /requests` y `POST /problems` tienen además sus propios resultados (no son errores): ver [8.15](#815-post-requests) y [8.23](#823-get-problems-y-post-problems). **Cómo distinguirlos**: si el cuerpo tiene `outcome`, es un resultado (aunque el código sea 409, 422 o 429); si tiene `error`, es un error.

---

## 6. Límites

- **300 llamadas por minuto** por usuario de Jellyfin. Pasado eso, `429 too_many_requests` con `Retry-After` (segundos).
- **120 búsquedas por minuto** (`/search`, `/discover`, `/people/{id}`, `/music/search`, `/music/songs`, `/music/artists`), dentro de las 300, con su propia cuenta: buscar mientras se escribe no gasta las demás.
- **60 por minuto** de las que más cuestan (`/series/{id}`, `/movies/{id}/availability`, `/upcoming`, `/music/artists/{id}`, `/music/albums/{id}`, `/music/songs/{id}`, `/music/charts/{id}`), también dentro de las 300 y con su propia cuenta.
- **30 por minuto** para pedir, retirar y avisar de problemas (`POST /requests`, `DELETE /requests/{id}`, `POST /problems`), con su propia cuenta.
- Los límites son **por minuto**: no se acumulan. Si llegas a uno, en menos de un minuto (lo dice `Retry-After`) vuelves a tener todo.
- Para buscar mientras se escribe, espera ~400 ms sin teclear antes de llamar y descarta la respuesta de una búsqueda vieja si llega después de la nueva: menos llamadas y resultados que no saltan.
- **20 tokens nuevos por minuto** por dirección (IPv6: por bloque /64) y **60 por minuto en todo el servidor** → `429 too_many_attempts`.
- **Peticiones** (no aplican al administrador):
  - Como mucho `access.limit` peticiones **esperando respuesta** a la vez por persona (0 = sin límite). Las aceptadas, rechazadas o terminadas no cuentan.
  - Como mucho `access.daily_limit` (20) peticiones nuevas **en 24 horas** por persona (contadas desde la primera), aunque se retiren.
  - Al pasarse, `POST /requests` responde `429` con `outcome: "limit"`, el motivo en `message` y `limit`: `pending` (esperando respuesta: se libera cuando el administrador conteste o retires una) o `daily` (con `Retry-After`: cuándo se libera).

Las listas de tops y las búsquedas (también las de música) se guardan en caché en el servidor (de minutos a una hora), y la disponibilidad de una película 10 minutos: llamar más a menudo no da datos más frescos.

---

## 7. Objetos comunes

### 7.1 Título (película o serie)

Lo devuelven `/top`, `/search`, `/discover`, los parecidos, `/collections/{id}`, `/people/{id}`, las películas de `/upcoming` y las dos fichas (`/movies/{id}` y `/series/{id}`).

```json
{
  "type": "movie",
  "tmdb_id": 438631,
  "title": "Dune",
  "original_title": "Dune",
  "year": 2021,
  "date": "2021-09-15",
  "overview": "Arrakis, también llamado Dune…",
  "poster": "https://image.tmdb.org/t/p/w342/abc.jpg",
  "backdrop": "https://image.tmdb.org/t/p/w780/def.jpg",
  "rating": 7.8,
  "rank": 3,
  "age": 12,
  "age_rating": { "label": "12", "country": "ES" },
  "library": { "…": "ver 7.2 y 7.3" },
  "request": { "…": "ver 7.4, o null" }
}
```

| Campo | Tipo | Notas |
|---|---|---|
| `type` | `"movie"` \| `"series"` | |
| `tmdb_id` | número | El id para todo lo demás (ficha, pedir) |
| `title` | texto | En español si TMDB lo tiene |
| `original_title` | texto \| null | |
| `year` | número \| null | |
| `date` | texto \| null | Estreno (película) o primer episodio (serie). En «Nuevo» de una plataforma, la fecha de lo que se anuncia |
| `overview` | texto \| null | En los tops de JustWatch y en «Nuevo» viene `null`: está en la ficha |
| `poster` | URL \| null | Ancho 342 px |
| `backdrop` | URL \| null | `null` en los tops de una plataforma, en «Nuevo» y en `/upcoming`; en lo demás, 780 px de ancho (1280 en las fichas) |
| `rating` | número \| null | Nota media de TMDB (0–10), solo cuando TMDB la da |
| `rank` | número \| null | Posición en el top (1 = primero); `null` fuera de los tops |
| `age` | número \| null | **Edad mínima recomendada**, en años (0 = para todos los públicos, 7, 12, 16, 18…). Sale de la calificación de España en TMDB; si no tiene, de la de Estados Unidos y luego de la de Reino Unido, traducida a años. `null` = sin calificación conocida |
| `age_rating` | objeto \| null | La calificación tal cual, `label` (`"A"`, `"12"`, `"16"`, `"PG-13"`, `"TV-MA"`…) y `country` (`"ES"`, `"US"` o `"GB"`). `null` si no hay |
| `season` | número \| null | Solo series de «Nuevo»: la temporada que se estrena (1 = serie nueva) |
| `season_episodes` | número \| null | Episodios de esa temporada según TMDB |
| `platform` | texto | Solo en «Nuevo» de `all`: de qué plataforma viene (`netflix`, `disney`, `prime`) |
| `library` | objeto | Qué hay en Jellyfin: 7.2 (película) o 7.3 (serie) |
| `request` | objeto \| null | La petición abierta de ese título (7.4), o `null` si no hay ninguna |

Todos los campos de la tabla vienen siempre (con `null` cuando no aplica), salvo `platform`. Desde 1.81.0, `age` y `age_rating` vienen **en todos los títulos**, de películas y de series: `/top`, `/search`, `/discover`, `/movies/{id}/similar`, `/series/{id}/similar`, `/collections/{id}`, `/people/{id}`, las películas de `/upcoming` y las dos fichas. Si el campo no viene, ese Stremfin es anterior a 1.81.0; si viene `null`, el título no tiene calificación conocida.

**La edad es solo información**: Stremfin no oculta nada por ella. Si la app tiene perfiles (por ejemplo, uno infantil), el filtro lo hace la app con `age`. Ojo con `age: null` (sin calificación): en un perfil infantil, lo prudente es no enseñarlo. Equivalencias usadas: `A`/`TP`/`G`/`U`/`TV-Y`/`TV-G` = 0; `PG`/`TV-Y7`/`TV-PG` = 7; `PG-13` = 13; `TV-14` = 14; `R`/`TV-MA` = 17; `NC-17`/`X` = 18; las que son un número (`12`, `16`, `12A`, `15`…), ese número.

**En las listas** (tops y búsqueda), Stremfin reconoce lo que hay en Jellyfin por el id de TMDB que Jellyfin guarda de cada título. Si en Jellyfin algún título no tiene ese id (raro), en la lista saldrá como que no está; la **ficha** (`/movies/{id}`, `/series/{id}`) lo encuentra también por su id de IMDb y siempre dice la verdad. Antes de enseñar «Pedir» con seguridad, usa la ficha.

### 7.2 `library` de una película

```json
{ "status": "available", "in_jellyfin": true, "jellyfin_id": "f27caa37e5142225cceded48f6553502", "downloading": false }
```

| Campo | Notas |
|---|---|
| `status` | `available` (está en Jellyfin), `downloading` (se está descargando) o `missing` (no está) |
| `in_jellyfin` | `true` si se puede ver ya. Incluye lo recién descargado que Jellyfin aún está añadiendo: en ese caso `jellyfin_id` puede ser `null` unos minutos |
| `jellyfin_id` | El `Id` del elemento en Jellyfin, para abrir su ficha o reproducirlo. `null` si aún no está indexado |
| `downloading` | `true` si está en descargas y aún no en Jellyfin |

### 7.3 `library` de una serie

```json
{
  "status": "partial",
  "in_jellyfin": true,
  "jellyfin_id": "a1b2c3…",
  "downloading": false,
  "episodes": 23,
  "season": 3,
  "season_episodes_have": 4,
  "season_episodes": 8
}
```

| Campo | Notas |
|---|---|
| `status` | `available` (la serie está en Jellyfin), `partial` (está, pero falta la temporada que anuncia la tarjeta), `downloading` (no está y se están descargando episodios) o `missing` |
| `in_jellyfin` | La serie existe en Jellyfin (aunque falten episodios) |
| `jellyfin_id` | El `Id` de la serie en Jellyfin |
| `downloading` | Hay episodios en descargas |
| `episodes` | Episodios que hay en Jellyfin (sin especiales) |
| `season`, `season_episodes_have`, `season_episodes` | Solo si la tarjeta anuncia una temporada («Nuevo»): cuántos de esa temporada hay y cuántos tiene |

En las listas no se sabe si una serie está **completa** (haría falta leer todos sus episodios). Para eso, la ficha: `GET /series/{id}` ([8.7](#87-get-seriestmdb_id)).

### 7.4 `request` en un título (referencia corta)

```json
{
  "id": 57,
  "status": "pending",
  "status_label": "Esperando respuesta",
  "season": null,
  "episode": null,
  "direct": false,
  "mine": false,
  "requesters": ["Luis", "Ana"]
}
```

| Campo | Notas |
|---|---|
| `id` | Para `GET /requests/{id}` y `DELETE /requests/{id}` |
| `status` | `pending` o `approved` (en un título solo salen las abiertas). Ver [9.1](#91-status-de-una-petición) |
| `status_label` | Texto para enseñar |
| `season` | Series: la temporada pedida, o `null` = todo lo que falta |
| `episode` | Series: el episodio pedido (de `season`), o `null` = la temporada entera |
| `direct` | `true` si se aceptó sola |
| `mine` | `true` si la has pedido tú (también si te apuntaste) |
| `requesters` | Nombres de quien la pidió. Si la pidió el administrador desde la app, aparece «el administrador» |

En una serie con petición de «todo lo que falta» y además de alguna temporada, `request` es la de todo lo que falta. En una tarjeta que anuncia una temporada («Nuevo · T3»), `request` es la que cubre esa temporada (todo lo que falta, o esa temporada), o `null` si solo se pidieron otras o episodios sueltos.

### 7.5 Petición completa

Lo devuelven `/requests`, `/requests/{id}` y `POST /requests`.

```json
{
  "id": 57,
  "type": "series",
  "tmdb_id": 1396,
  "deezer_id": null,
  "title": "Breaking Bad",
  "display_title": "Breaking Bad (2008) · Temporada 2",
  "artist": null,
  "year": 2008,
  "season": 2,
  "episode": null,
  "whole_series": false,
  "episodes_missing": 13,
  "poster": "https://image.tmdb.org/t/p/w342/bb.jpg",
  "status": "approved",
  "status_label": "Aceptada",
  "cancelled": false,
  "reason": null,
  "reason_label": null,
  "direct": false,
  "mine": true,
  "requesters": ["Luis"],
  "can_withdraw": false,
  "progress": {
    "state": "downloading",
    "label": "Descargando",
    "episodes_done": 5,
    "episodes_total": 13,
    "episodes_attention": 0,
    "recheck": null
  },
  "requested_at": "2026-11-10T21:14:03+01:00",
  "decided_at": "2026-11-10T21:20:41+01:00",
  "completed_at": null,
  "updated_at": "2026-11-11T09:02:10+01:00"
}
```

| Campo | Notas |
|---|---|
| `type` | `movie`, `series` o `music` |
| `tmdb_id` / `deezer_id` | Uno u otro según el tipo |
| `display_title` | Listo para enseñar: «Dune (2021)», «Severance · Temporada 2», «Severance · Temporada 2, episodio 3», «Severance · todo lo que falta», «Daft Punk — Discovery» |
| `artist` | Solo música |
| `season`, `episode`, `whole_series` | Series: temporada pedida (y el episodio, si se pidió uno solo), o `whole_series: true` (todo lo que falta) |
| `episodes_missing` | Series: episodios que faltaban al pedirla (`null` en un episodio suelto) |
| `poster` | Portada (TMDB o Deezer) |
| `status`, `status_label` | Ver [9.1](#91-status-de-una-petición) |
| `cancelled` | Desde 1.88.0, siempre presente. `true` si el administrador la canceló **después de aceptarla**: `status` sigue siendo `rejected` y `status_label` dice «Cancelada». `false` en todas las demás |
| `reason`, `reason_label` | Si se rechazó con motivo: `quality` («aún no hay una versión buena») o `later` («mejor más adelante») |
| `direct` | Se aceptó sola (persona con peticiones directas, o el administrador) |
| `mine` | La has pedido tú |
| `requesters` | Todos los que la pidieron |
| `can_withdraw` | `true` si puedes retirarla ahora (es tuya y espera respuesta) |
| `progress` | Solo en las aceptadas: por dónde va ([9.2](#92-progressstate-de-una-petición-aceptada)). `null` en las demás |
| `requested_at`, `decided_at`, `completed_at`, `updated_at` | Fechas. `updated_at` cambia cuando cambia su estado o quién la pidió; sirve para pedir solo lo que ha cambiado (`since`). El avance de la descarga (`progress`) **no** cambia `updated_at`: para seguirlo, vuelve a leer las abiertas |

### 7.6 Álbum

Lo devuelven `/music/search`, `/music/new`, `/music/artists/{id}`, `/music/albums/{id}`, las listas de álbumes de `/music/charts/{id}`, `/music/releases`, `/music/requested` y, dentro de una canción, `/music/songs/{id}` y las listas de canciones.

```json
{
  "type": "music",
  "deezer_id": "302127",
  "title": "Discovery",
  "artist": "Daft Punk",
  "cover": "https://e-cdns-images.dzcdn.net/images/cover/…/500x500.jpg",
  "tracks": 14,
  "kind": "album",
  "release_date": "2001-03-07",
  "rank": null,
  "library": { "in_jellyfin": false, "song_in_album": null, "requested_recently": true },
  "download": {
    "phase": "downloading",
    "label": "Descargando",
    "percent": 42,
    "track_errors": false,
    "sent_at": "2026-11-11T10:02:00+01:00",
    "arrived_at": null
  },
  "contains": null,
  "request": { "…": "ver 7.4, o null" },
  "can_request": true
}
```

| Campo | Notas |
|---|---|
| `deezer_id` | Para pedirlo y abrir su ficha. Puede ser `null` en novedades que Deezer no tiene: entonces no se puede pedir |
| `kind` | `album` (también recopilatorios), `ep` o `single` |
| `tracks` | Canciones, si se sabe (en discografías viene `null`: está en la ficha) |
| `release_date` | `AAAA-MM-DD`, si se sabe |
| `rank` | Su puesto en novedades y en una lista de álbumes ([8.29](#829-get-musicchartsid)); `null` en lo demás (también en el `album` de una canción de una lista: el puesto es el de la canción) |
| `library.in_jellyfin` | Ya está en Jellyfin (un sencillo cuya canción tienes en un álbum también cuenta) |
| `library.song_in_album` | Un sencillo cuya canción ya tienes en un álbum: el nombre de ese álbum |
| `library.requested_recently` | Se mandó a la descarga hace poco (lo pida quien lo pida) |
| `download` | Si va de camino a Jellyfin (se mandó a la descarga y aún no está), dónde va: ver [9.5](#95-download-de-un-álbum-de-camino-a-jellyfin). `null` si no |
| `contains` | La canción por la que sale este álbum: la que nombra la búsqueda, la del sencillo en `album_instead`, o la canción de la lista en su `album`. `null` en lo demás |
| `request` | Petición abierta (7.4) o `null` |
| `can_request` | Tiene `deezer_id`, no está en Jellyfin y no lo has pedido ya tú |

---

### 7.7 Canción

Desde 1.84.0. Lo devuelven `/music/search` (`songs`), `/music/songs`, `/music/songs/{id}` y `top_songs` de un artista.

```json
{
  "deezer_id": "3135556",
  "title": "Harder, Better, Faster, Stronger",
  "artist": "Daft Punk",
  "artist_deezer_id": "27",
  "duration": 224,
  "preview": "https://cdnt-preview.dzcdn.net/…/….mp3",
  "explicit": false,
  "album": { "deezer_id": "302127", "title": "Discovery", "cover": "https://…/500x500.jpg" },
  "in_jellyfin": false,
  "in_album": null
}
```

| Campo | Notas |
|---|---|
| `deezer_id` | El id de la canción (texto), para su ficha ([8.27](#827-get-musicsongsdeezer_id)). **No sirve para pedir**: se pide un disco |
| `artist_deezer_id` | Para abrir el artista; puede ser `null` |
| `duration` | Segundos, o `null` |
| `preview` | Un fragmento de 30 segundos en MP3 para escuchar antes de pedir, o `null`. La dirección caduca: úsala al momento, no la guardes |
| `explicit` | Letra explícita, según Deezer |
| `album` | El disco en el que Deezer la sitúa (`deezer_id`, `title`, `cover`), o `null`. Puede ser un sencillo: la ficha de la canción dice qué álbum pedir |
| `in_jellyfin`, `in_album` | Si ya tienes esa canción en Jellyfin y en qué álbum |

## 8. Direcciones

Todas empiezan por `https://stremfin.ejemplo.com/api/v1` y llevan el token. Las marcadas con 🔒 exigen acceso (sección 4).

| Método | Ruta | Para qué |
|---|---|---|
| GET | `/me` | Quién eres y qué puedes hacer |
| GET 🔒 | `/platforms` | Las plataformas y sus listas |
| GET 🔒 | `/top` | El top de una plataforma (o global) |
| GET 🔒 | `/search` | Buscar películas y series (y las personas que coinciden) |
| GET 🔒 | `/movies/{tmdb_id}` | Ficha de una película |
| GET 🔒 | `/movies/{tmdb_id}/availability` | Si se puede descargar ya y si será rápido |
| GET 🔒 | `/series/{tmdb_id}` | Ficha de una serie, por temporadas y episodios |
| GET 🔒 | `/music/search` | Buscar música: álbumes, y con ellos artistas y canciones |
| GET 🔒 | `/music/songs` | Buscar canciones |
| GET 🔒 | `/music/songs/{deezer_id}` | Una canción, su disco y el álbum que pedir |
| GET 🔒 | `/music/new` | Novedades de música |
| GET 🔒 | `/music/charts` | Las listas de lo más escuchado que hay |
| GET 🔒 | `/music/charts/{id}` | Una lista: canciones (con su álbum) o álbumes |
| GET 🔒 | `/music/releases` | Los discos de los artistas que sigue la casa, también los anunciados |
| GET 🔒 | `/music/requested` | Lo más pedido en casa |
| GET 🔒 | `/music/artists` | Buscar artistas |
| GET 🔒 | `/music/artists/{deezer_id}` | Un artista: sus discos, sus canciones más escuchadas y artistas parecidos |
| GET 🔒 | `/music/albums/{deezer_id}` | Un álbum con sus canciones |
| GET 🔒 | `/movies/{tmdb_id}/similar`, `/series/{tmdb_id}/similar` | Títulos parecidos |
| GET 🔒 | `/collections/{id}` | Una saga |
| GET 🔒 | `/movies/{tmdb_id}/trailers`, `/series/{tmdb_id}/trailers` | Los tráilers de un título, el mejor primero |
| GET 🔒 | `/people/{id}` | Ficha de una persona con sus películas y series |
| GET 🔒 | `/genres`, `/discover` | Explorar por género, año y plataforma |
| GET 🔒 | `/upcoming` | Próximamente |
| GET 🔒 | `/notifications` | Lo que ha pasado con lo tuyo |
| GET, POST 🔒 | `/problems` | Avisar de un problema con algo de Jellyfin |
| GET 🔒 | `/requests` | Peticiones (tuyas o de todos) |
| GET 🔒 | `/requests/{id}` | Una petición |
| POST 🔒 | `/requests` | Pedir algo |
| DELETE 🔒 | `/requests/{id}` | Retirar una petición que espera respuesta |

### 8.1 `GET /me`

Siempre responde si el token vale, también a quien no tiene acceso. Llámala al entrar y al volver a la app.

```http
GET https://stremfin.ejemplo.com/api/v1/me
Authorization: Bearer <token>
```

```json
{
  "user": {
    "jellyfin_id": "4f3e2d1c…",
    "jellyfin_name": "mama",
    "name": "Mamá",
    "role": "member"
  },
  "access": {
    "can_request": true,
    "mode": "direct",
    "telegram": false,
    "limit": 10,
    "pending": 0,
    "daily_limit": 20,
    "daily_left": 18,
    "at_limit": false,
    "open_requests": 3
  },
  "features": {
    "music": true,
    "platforms": ["netflix", "disney", "prime"]
  },
  "server": { "name": "Stremfin", "version": "1.90.2", "api_version": 1 }
}
```

| Campo | Notas |
|---|---|
| `user.name` | El nombre que le ha puesto el administrador (o el de Jellyfin) |
| `user.role` | `admin`, `member` o `none` |
| `access.can_request` | Si es `false`, esconde pedir, tops y búsqueda, y enseña «Pídele acceso al administrador» |
| `access.mode` | `admin`, `direct`, `review` o `null` (sección 4) |
| `access.telegram` | Tiene Telegram (recibe los avisos allí) |
| `access.limit` | Peticiones esperando respuesta a la vez (0 = sin límite) |
| `access.pending` | Las suyas que esperan respuesta ahora |
| `access.daily_limit`, `access.daily_left` | Peticiones nuevas en 24 horas y las que le quedan (`null` para el administrador) |
| `access.at_limit` | `true` si ahora mismo no puede pedir más: enseña el aviso antes de que lo intente |
| `access.open_requests` | Sus peticiones abiertas (esperando o aceptadas) |
| `server.version` | Versión de Stremfin (`null` para quien no tiene acceso) |
| `features.music` | Hay descarga de música configurada. Si es `false`, se puede pedir música igualmente, pero la conseguirá el administrador a mano |

### 8.2 `GET /platforms`

```json
{
  "region": "ES",
  "platforms": [
    { "id": "all", "name": "Todas", "color": null, "lists": ["popular", "new"] },
    { "id": "netflix", "name": "Netflix", "color": "#e50914", "lists": ["popular", "new"] },
    { "id": "disney", "name": "Disney+", "color": "#113ccf", "lists": ["popular", "new"] },
    { "id": "prime", "name": "Prime Video", "color": "#00a8e1", "lists": ["popular", "new"] }
  ]
}
```

Úsala para pintar los botones (el `color` sirve de color de marca; los logos los pone la app). `region` es el país configurado en Stremfin.

### 8.3 `GET /top`

| Parámetro | Obligatorio | Valores | Por defecto |
|---|---|---|---|
| `platform` | sí | `all`, `netflix`, `disney`, `prime` | |
| `type` | sí | `movie`, `series` | |
| `list` | no | `popular` (lo más visto), `new` (lo nuevo) | `popular` |
| `only` | no | `all`, `missing` (solo lo que no está en Jellyfin), `available` (solo lo que está) | `all` |
| `limit` | no | 1–40 (en `popular` de una plataforma, como mucho 20) | 20 |

```http
GET https://stremfin.ejemplo.com/api/v1/top?platform=netflix&type=movie&list=popular
```

```json
{
  "platform": "netflix",
  "type": "movie",
  "list": "popular",
  "region": "ES",
  "source": "justwatch",
  "items": [
    {
      "type": "movie", "tmdb_id": 945961, "title": "Alien: Romulus", "original_title": null,
      "year": 2024, "date": null, "overview": null,
      "poster": "https://images.justwatch.com/poster/…/s332/….webp", "backdrop": null,
      "rating": null, "rank": 1, "season": null, "season_episodes": null,
      "age": 16, "age_rating": { "label": "16", "country": "ES" },
      "library": { "status": "missing", "in_jellyfin": false, "jellyfin_id": null, "downloading": false },
      "request": null
    }
  ]
}
```

De dónde sale cada lista (`source`):

| `platform` | `list` | `source` | Qué es |
|---|---|---|---|
| una plataforma | `popular` | `justwatch` | Ranking de popularidad de JustWatch para esa plataforma y país (no es el top oficial de la plataforma) |
| una plataforma | `new` | `tmdb` | Estrenos recientes que TMDB ya da en esa plataforma: películas del último año; series con una temporada estrenada hace poco (`season`) |
| `all` | `popular` | `tmdb_trending` | Lo más visto de la semana en todo el mundo (TMDB) |
| `all` | `new` | `tmdb` | Lo nuevo de las tres plataformas juntas, lo más reciente primero, cada título una vez (`platform` dice de cuál) |

El filtro `only` se aplica después de cruzar con Jellyfin, así que puede devolver menos de `limit`. Si la app quiere filtrar sin volver a llamar, que pida `only=all` y filtre por `library.in_jellyfin`.

### 8.4 `GET /search`

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `q` | sí | Texto, 1–100 caracteres |
| `type` | no | `all` (por defecto), `movie`, `series` |
| `only` | no | `all` (por defecto: todo), `missing` (solo lo que **no** está en Jellyfin), `available` (solo lo que **sí** está) |
| `limit` | no | Cuántos resultados, 1–40 (por defecto 20) |
| `cursor` | no | Para los siguientes: el `next_cursor` de la respuesta anterior, tal cual |

```json
{
  "query": "montaña",
  "type": "all",
  "only": "missing",
  "items": [ Título… ],
  "people": [
    { "id": 887, "name": "Owen Wilson", "photo": "https://image.tmdb.org/t/p/w185/o.jpg", "department": "acting", "known_for": ["Cars", "Loki", "Zoolander"] }
  ],
  "next_cursor": "2.19"
}
```

- `items`: títulos (7.1), con `age` y `age_rating`, en el orden de relevancia de TMDB, ya filtrados por `type` y `only`. Con `only=missing` solo vienen los que tienen `library.in_jellyfin: false` (también lo que se está descargando: aún no se puede ver).
- `next_cursor`: si hay más, el valor para pedir los siguientes; `null` si no hay más. Para «los 20 siguientes», repite **la misma** llamada (mismos `q`, `type`, `only` y `limit`) añadiendo `cursor=<next_cursor>`. Es un texto opaco: no lo construyas tú.
- Cada llamada lee como mucho 5 páginas de TMDB (100 resultados). Con `only=missing` u `only=available` puede volver **con menos de `limit`, o incluso vacía, y con `next_cursor`**: aún quedan resultados por mirar. En una lista con scroll infinito, pide la siguiente al llegar al final mientras `next_cursor` no sea `null`.
- Para el buscador de la app: arriba lo que ya tienes (lo resuelve el propio cliente con Jellyfin) y debajo `GET /search?q=…&only=missing` con lo que se puede pedir.
- `people` (desde 1.82.0): las personas que coinciden con lo buscado (al escribir «owen wilson»), hasta 6, para abrir su ficha con [8.24](#824-get-peopleid). Cada una con `id`, `name`, `photo` (185 px, puede ser `null`), `department` (a qué se dedica sobre todo: `acting`, `directing`, `writing`, `production`, `other` o `null`) y `known_for` (hasta 3 títulos por los que se la conoce, solo el nombre). Viene **solo con los primeros resultados** (sin `cursor`); en las páginas siguientes es una lista vacía. No depende de `type` ni de `only`, y nunca hay personas dentro de `items`. Si el campo no viene, ese Stremfin es anterior a 1.82.0.
- Un `cursor` mal formado da `422 invalid`.

### 8.5 `GET /movies/{tmdb_id}`

La ficha de una película: el título (7.1) con estos campos más.

```json
{
  "type": "movie",
  "tmdb_id": 920,
  "imdb_id": "tt0317219",
  "title": "Cars",
  "original_title": "Cars",
  "year": 2006,
  "date": "2006-06-08",
  "overview": "…",
  "poster": "https://image.tmdb.org/t/p/w342/c.jpg",
  "backdrop": "https://image.tmdb.org/t/p/w1280/c2.jpg",
  "rating": null,
  "age": 0,
  "age_rating": { "label": "A", "country": "ES" },
  "runtime": 117,
  "genres": ["Animación", "Comedia"],
  "trailer": { "name": "Tráiler oficial en español", "key": "abc123XYZ00", "url": "https://www.youtube.com/watch?v=abc123XYZ00", "type": "trailer", "language": "es", "country": "ES", "subtitled": false, "official": true, "published_at": "2006-03-01" },
  "cast": [ { "id": 887, "name": "Owen Wilson", "character": "Rayo McQueen (voz)", "photo": "https://image.tmdb.org/t/p/w185/o.jpg" } ],
  "directors": ["John Lasseter"],
  "crew": [ { "id": 7879, "name": "John Lasseter", "job": "director", "photo": "https://image.tmdb.org/t/p/w185/j.jpg" } ],
  "providers": [ { "name": "Disney Plus", "logo": "https://image.tmdb.org/t/p/w92/d.jpg", "key": "disney" } ],
  "collection": { "id": 87118, "name": "Cars" },
  "library": { "status": "missing", "in_jellyfin": false, "jellyfin_id": null, "downloading": false },
  "request": null,
  "download": null,
  "release": null,
  "can_request": { "allowed": true, "action": "request", "reason": null }
}
```

| Campo | Notas |
|---|---|
| `runtime` | Minutos |
| `rating` | Nota media de TMDB, si la tiene |
| `age`, `age_rating` | Edad mínima recomendada y su calificación, como en [7.1](#71-título-película-o-serie) |
| `trailer` | El mejor tráiler de YouTube para una casa en España: el primero de la lista de [8.25](#825-get-moviestmdb_idtrailers-y-get-seriestmdb_idtrailers), con los mismos campos y el mismo orden (doblado al español de España antes que nada). `key` es el id del vídeo (para incrustarlo), `url` la dirección para abrirlo. `null` si no hay ninguno. Hasta 1.82 traía solo `name`, `key`, `url` y `language` |
| `cast` | Hasta 12 personas del reparto, en orden: `id` (desde 1.82.0; el de su ficha, [8.24](#824-get-peopleid); puede ser `null`), `name`, `character` (puede ser `null`) y `photo` (185 px, puede ser `null`) |
| `directors` | Quién la dirige (lista de nombres; vacía si no se sabe) |
| `crew` | Desde 1.82.0: las mismas personas de `directors`, cada una con `id` (para abrir su ficha), `name`, `job` (`director`; en una serie, `creator`) y `photo` (185 px, puede ser `null`). `directors` sigue igual, para las apps que ya lo usan |
| `providers` | Dónde se puede ver **sin pagar aparte** en el país de Novedades (suscripción, gratis o con anuncios), según TMDB/JustWatch: `name`, `logo` (92 px) y `key` (`netflix`, `disney`, `prime` si es una de [8.2](#82-get-platforms), si no `null`). Vacía si no está en ninguna. Útil para no pedir lo que ya se puede ver |
| `collection` | La saga a la que pertenece (`id`, `name`), para abrirla con [8.20](#820-get-collectionsid); `null` si no es de ninguna |
| `library` | Aquí se busca también por el id de IMDb: es la respuesta fiable de si está en Jellyfin |
| `download` | Si se está descargando: `status` (`downloading`, o `attention` = el administrador tiene que revisarla) y los campos de una descarga de [9.2](#92-progressstate-de-una-petición-aceptada) (`phase`, `label`, `percent`, `downloaded_bytes`, `total_bytes`, `speed`, `eta_seconds`, `waiting_since`, `paused`, `recheck`). `null` si no |
| `release` | Si aún no ha salido en digital: `{ "date": "2026-12-04" \| null, "text": "Se estrena el 04/12/2026" }`. Se puede pedir igualmente: espera a que salga |
| `can_request.allowed` | Si enseñar el botón |
| `can_request.action` | Qué botón: `request` («Pedir») o `notify` («Avísame cuando esté»: ya se está descargando; pedirla te apunta al aviso, `outcome: "watching"` o `"joined"`, sin descargar nada nuevo). `null` si no se puede |
| `can_request.reason` | Por qué no: `have` (ya está), `already` (ya la pediste o ya estás apuntado), `busy` (solo para el administrador: ya se está descargando), `unavailable` (no se puede conseguir) |

Si TMDB no responde al leer el tráiler, el reparto o las plataformas, la ficha llega igual, con `trailer: null` y las listas vacías.

### 8.6 `GET /movies/{tmdb_id}/availability`

Si Stremfin puede descargar esta película **ahora** y si será **rápido**. Stremfin pregunta a sus fuentes y elige el enlace exactamente como cuando descarga una petición aceptada: el primero de su ranking, si hay alguno con el idioma y la calidad de casa. **La app nunca elige ni ve enlaces**: solo recibe qué versión sería.

Llámala al abrir la ficha de una película que no está en Jellyfin (a la vez que `/movies/{id}`, no después). Tarda **de 2 a 10 segundos** (pregunta a las fuentes): enseña la ficha en seguida y el botón cuando llegue. La respuesta se guarda 10 minutos.

```json
{
  "tmdb_id": 920,
  "status": "ready",
  "reason": null,
  "downloadable": true,
  "cached": true,
  "fast": true,
  "version": {
    "resolution": "1080p",
    "height": 1080,
    "hdr": null,
    "edition": null,
    "language": "Castellano",
    "languages": ["Castellano"],
    "codec": "x265",
    "source": "BluRay",
    "size": 9663676416,
    "summary": "1080p · Castellano · 9,0 GB"
  },
  "candidates": 4,
  "cached_candidates": 2,
  "release": null,
  "criterion": "en castellano de 1080p o más",
  "on_request": "download",
  "checked_at": "2026-11-11T10:00:00+01:00"
}
```

| Campo | Notas |
|---|---|
| `status` | `ready`: se puede descargar ya. `waiting_version`: aún no (ver `reason`); pedirla la deja esperando y se descarga sola cuando haya una buena. `downloading`: ya se está descargando. `have`: ya está en Jellyfin. `unavailable`: no se puede conseguir (le falta el id de IMDb) |
| `reason` | Con `waiting_version`: `not_released` (no ha salido en digital: ver `release`), `quality` (hay versiones, pero ninguna con el idioma y la calidad de casa: ver `criterion`) o `no_links` (no hay ninguna) |
| `downloadable` | `true` solo con `status: "ready"` |
| `cached` | La versión elegida está **lista al instante** en el servicio de descargas (`true`), hay que esperar a que la prepare, de minutos a bastante más (`false`), o la fuente no lo dice (`null`). `null` también si no es `ready` |
| `fast` | `true` si `ready` y `cached: true`: la descarga empieza en seguida |
| `version` | Qué se descargaría: resolución (`resolution`, `height`), `hdr`, `edition` («Extendida»…), idioma principal (`language`) y todos los que menciona (`languages`), `codec`, `source` (BluRay, WEB-DL…), `size` en bytes (o `null`) y `summary` listo para enseñar. `null` si no es `ready` |
| `candidates` | Cuántas versiones probaría por orden si la primera falla (la primera incluida) |
| `cached_candidates` | De esas, cuántas están listas al instante |
| `release` | Con `reason: "not_released"`: igual que en la ficha ([8.5](#85-get-moviestmdb_id)) |
| `criterion` | Qué se considera una versión buena en casa, para el texto de espera: «Aún no hay una versión {criterion}» |
| `on_request` | Qué hace pedirla: `download` (administrador o peticiones directas: empieza en seguida) o `review` (le llega al administrador, que decide) |
| `checked_at` | Cuándo se respondió (la parte de enlaces puede venir de una caché de hasta 10 minutos) |

**Botones** (los dos hacen lo mismo: `POST /requests` con `type: "movie"`):
- `fast: true` → «Descarga rápida».
- `ready` sin `fast` → «Añadir a la cola» (tardará más en empezar).
- `waiting_version` → «Pedir y avisarme» con el texto de `release.text` o «Aún no hay una versión {criterion}».
- `downloading` / `have` → como en la ficha (`can_request`).
- Con `on_request: "review"`, avisa debajo: «El administrador tiene que aceptarla». Cuando la acepte, Stremfin vuelve a mirar los enlaces en ese momento: puede salir otra versión.

Es una foto del momento: si al descargar la primera versión falla, Stremfin prueba la siguiente sola; lo que pase lo cuenta la petición (`progress`, [9.2](#92-progressstate-de-una-petición-aceptada)).

### 8.7 `GET /series/{tmdb_id}`

La ficha de una serie, con cada temporada y sus episodios.

```json
{
  "type": "series",
  "tmdb_id": 1396,
  "imdb_id": "tt0903747",
  "title": "Breaking Bad",
  "original_title": "Breaking Bad",
  "year": 2008,
  "years": "2008–2013",
  "date": "2008-01-20",
  "overview": "…",
  "poster": "https://image.tmdb.org/t/p/w342/bb.jpg",
  "backdrop": "https://image.tmdb.org/t/p/w1280/bb2.jpg",
  "rating": 8.9,
  "age": 16,
  "age_rating": { "label": "16", "country": "ES" },
  "genres": ["Drama", "Crimen"],
  "trailer": { "name": "Tráiler oficial en español", "key": "xyz789ABC00", "url": "https://www.youtube.com/watch?v=xyz789ABC00", "type": "trailer", "language": "es", "country": "ES", "subtitled": false, "official": true, "published_at": "2008-01-05" },
  "cast": [ { "id": 17419, "name": "Bryan Cranston", "character": "Walter White", "photo": "https://image.tmdb.org/t/p/w185/b.jpg" } ],
  "creators": ["Vince Gilligan"],
  "crew": [ { "id": 66633, "name": "Vince Gilligan", "job": "creator", "photo": null } ],
  "providers": [ { "name": "Netflix", "logo": "https://image.tmdb.org/t/p/w92/n.jpg", "key": "netflix" } ],
  "library": { "status": "available", "in_jellyfin": true, "jellyfin_id": "a1b2…", "downloading": false, "episodes": 20, "season": null, "season_episodes_have": null, "season_episodes": null },
  "request": null,
  "summary": { "aired": 62, "have": 20, "missing": 42, "missing_requestable": 42 },
  "can_request_all": true,
  "seasons": [
    {
      "season": 1,
      "aired": 7,
      "have": 7,
      "missing": 0,
      "downloading": 0,
      "status": "complete",
      "request": null,
      "can_request": false,
      "episodes": [
        { "episode": 1, "title": "Piloto", "air_date": "2008-01-20", "aired": true, "in_jellyfin": true, "downloading": false, "request": null, "can_request": false }
      ]
    }
  ]
}
```

| Campo | Notas |
|---|---|
| `age`, `age_rating` | Edad mínima recomendada de la serie y su calificación, como en [7.1](#71-título-película-o-serie) |
| `trailer`, `cast`, `providers` | Como en la ficha de película ([8.5](#85-get-moviestmdb_id)) |
| `creators` | Quién la creó (lista de nombres; vacía si no se sabe) |
| `crew` | Desde 1.82.0: las mismas personas de `creators` con `id`, `name`, `job` (`creator`) y `photo`, como en la ficha de película |
| `summary.aired` | Episodios ya emitidos (sin especiales) |
| `summary.have` | De esos, los que hay en Jellyfin |
| `summary.missing` | Los que faltan |
| `summary.missing_requestable` | Los que faltan y se pueden pedir (ni descargándose ni esperando revisión, ni en temporadas que el administrador no quiere) |
| `can_request_all` | Enseñar «Pedir todo lo que falta» |
| `request` | La petición abierta de «todo lo que falta», si la hay |
| `seasons[].status` | Ver [9.4](#94-status-de-una-temporada) |
| `seasons[].request` | La petición que cubre esa temporada (la suya o la de todo lo que falta) |
| `seasons[].can_request` | Enseñar «Pedir la T{n}», o «Yo también» si ya hay una `request` de otra persona (pedirla te apunta a ella) |
| `seasons[].episodes[]` | Cada episodio: número, título, fecha, si se ha emitido, si está en Jellyfin y si se está descargando |
| `seasons[].episodes[].request` | La petición que lo cubre: la de ese episodio, si no la de su temporada, si no la de todo lo que falta (7.4), o `null` |
| `seasons[].episodes[].can_request` | Enseñar «Pedir este episodio» (o «Yo también» si `request` es de otra persona): emitido, no está en Jellyfin ni se está descargando, y no lo has pedido ya |

Si alguien con peticiones directas (o el administrador) pide una temporada o todo lo que falta mientras otra persona tenía pedido «todo lo que falta» esperando respuesta, esa petición entera queda aceptada y en marcha.

Los especiales (temporada 0) no salen y no se pueden pedir. Esta ficha tarda algo más que las otras (lee TMDB y la lista de episodios): enseña un indicador de carga.

### 8.8 `GET /music/search`

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `q` | sí | Texto, 1–100 caracteres: artista, álbum o canción, o varias cosas («daft punk discovery», «taylor swift cruel summer») |
| `only` | no | `all` (por defecto), `missing` (solo lo que **no** está en Jellyfin), `available` (solo lo que **sí**) |
| `kind` | no | `all` (por defecto), `album`, `ep` o `single` |
| `limit` | no | 1–40 (por defecto 20) |
| `cursor` | no | Para los siguientes: el `next_cursor` de la respuesta anterior, tal cual |

```json
{
  "query": "daft punk",
  "only": "missing",
  "kind": "all",
  "artists": [
    { "deezer_id": "27", "name": "Daft Punk", "picture": "https://…/250x250.jpg", "albums": 34 }
  ],
  "songs": [ Canción… ],
  "items": [ Álbum… ],
  "next_cursor": "20"
}
```

- **Orden**: primero el álbum o EP cuyo título escribes; después, si nombras una canción, el álbum que la lleva (con `contains`) y su sencillo; después el resto (álbumes, luego EP, luego sencillos), en el orden de Deezer (relevancia y popularidad).
- `artists`: hasta 3 artistas que encajan con la búsqueda, para enseñar arriba («Artistas») y abrir su ficha ([8.11](#811-get-musicartistsdeezer_id)). Solo en la primera página (sin `cursor`); vacío en las siguientes o si Deezer no los da.
- `next_cursor`: igual que en `/search` ([8.4](#84-get-search)): repite la llamada con `cursor=<next_cursor>` mientras no sea `null`. Cada búsqueda lee como mucho unos 75 álbumes de Deezer; las páginas siguientes salen de lo ya leído (rápidas).
- `songs` (desde 1.84.0): hasta 8 canciones que encajan (7.7), para una fila «Canciones» en el buscador; al pulsar una, su ficha ([8.27](#827-get-musicsongsdeezer_id)), que dice qué álbum pedir. Solo en la primera página; vacío en las siguientes o si Deezer no responde. Para más canciones, [8.26](#826-get-musicsongs).
- La búsqueda se guarda una hora en el servidor.

### 8.9 `GET /music/new`

Las novedades de música (la lista de éxitos de álbumes que usa el panel), sin ruido de fondo («sonidos para dormir» y parecidos). Devuelve `{ "items": [ Álbum… ] }` con `rank`.

### 8.10 `GET /music/artists`

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `q` | sí | Texto, 1–100 caracteres |

Devuelve `{ "query": "…", "items": [ Artista… ] }`, hasta 6, en el orden de Deezer. Cada artista: `deezer_id`, `name`, `picture` (URL o `null`) y `albums` (cuántos discos tiene en Deezer).

### 8.11 `GET /music/artists/{deezer_id}`

Un artista y sus discos, del más nuevo al más antiguo, cada uno con si lo tienes.

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `kind` | no | `album` (por defecto: solo álbumes), `ep`, `single` (solo sencillos) o `all` (todo junto) |
| `only` | no | `all` (por defecto), `missing`, `available` |

```json
{
  "artist": { "deezer_id": "27", "name": "Daft Punk", "picture": "https://…", "albums": 34, "fans": 4200000 },
  "kind": "album",
  "only": "all",
  "summary": { "total": 9, "have": 4, "missing": 5 },
  "top_songs": [ Canción… ],
  "related": [ { "deezer_id": "2114", "name": "Justice", "picture": "https://…", "albums": 12, "fans": 900000 } ],
  "items": [ Álbum… ]
}
```

- `summary` cuenta todo lo del `kind` pedido, sin mirar `only`: «Tienes 4 de 9 álbumes».
- Con `kind` distinto de `album`, `summary` trae además el desglose: `albums`, `eps` y `singles`, cada uno `{ "total", "have" }`, para pestañas «Álbumes (9) · EP (2) · Sencillos (14)».
- `top_songs` (desde 1.84.0): sus 10 canciones más escuchadas (7.7). `related`: hasta 12 artistas parecidos, para abrir su ficha. Si Deezer falla al leerlos, vienen vacíos y la ficha llega igual.
- Los sencillos: muchos son canciones que también están en un álbum. La ficha del sencillo ([8.12](#812-get-musicalbumsdeezer_id)) dice cuál en `album_instead`, y pedir el sencillo pide ese álbum ([8.15](#815-post-requests)). Un sencillo que no está en ningún álbum se pide tal cual.
- Si un disco sale dos veces (normal y «Deluxe», o una reedición), viene solo el más nuevo.
- `404 not_found` si Deezer no tiene ese artista. Se guarda 6 horas.

### 8.12 `GET /music/albums/{deezer_id}`

La ficha de un álbum: el álbum (7.6) con sus canciones.

```json
{
  "type": "music",
  "deezer_id": "302127",
  "title": "Discovery",
  "artist": "Daft Punk",
  "…": "el resto de 7.6",
  "artist_deezer_id": "27",
  "label": "Parlophone",
  "genres": ["Electro"],
  "duration": 3660,
  "songs_have": 1,
  "songs": [
    { "position": 1, "disc": 1, "title": "One More Time", "artist": "Daft Punk", "duration": 320, "in_jellyfin": true, "in_album": "Grandes éxitos" },
    { "position": 2, "disc": 1, "title": "Aerodynamic", "artist": "Daft Punk", "duration": 207, "in_jellyfin": false, "in_album": null }
  ],
  "album_instead": null
}
```

| Campo | Notas |
|---|---|
| `artist_deezer_id` | Para abrir el artista ([8.11](#811-get-musicartistsdeezer_id)) |
| `label`, `genres`, `duration` | Sello, géneros y duración total en segundos, si Deezer los da |
| `songs[].position`, `disc` | Número de pista y de disco (`disc` puede ser `null`) |
| `songs[].duration` | Segundos |
| `songs[].in_jellyfin` | Esa canción ya está en Jellyfin, **en este álbum o en otro** |
| `songs[].in_album` | En qué álbum de Jellyfin la tienes |
| `songs_have` | Cuántas canciones del álbum tienes ya (en el álbum que sea) |
| `album_instead` | Desde 1.84.0. Solo si esto es un sencillo (`kind: "single"`) y su canción está en un álbum: ese álbum (7.6, con `contains` = la canción), **el que hay que ofrecer para pedir**. `null` en un álbum, un EP, o un sencillo que no está en ningún álbum |

Se pide el disco entero (`POST /requests` con su `deezer_id`): no se piden canciones sueltas. La norma de la casa es **el álbum completo siempre que exista**: si pides un sencillo cuya canción está en un álbum, Stremfin pide el álbum ([8.15](#815-post-requests)). `404 not_found` si Deezer no lo tiene. Se guarda 6 horas.

### 8.13 `GET /requests`

| Parámetro | Valores | Por defecto |
|---|---|---|
| `scope` | `mine` (las tuyas), `all` (las de toda la casa) | `mine` |
| `status` | `open` (esperando o aceptadas), `closed` (rechazadas o terminadas), `all` | `open` |
| `type` | `movie`, `series`, `music` | todas |
| `since` | Fecha ISO 8601 con zona (cualquiera): solo las que han cambiado desde entonces, y `removed_ids` | |
| `limit` | 1–200 | 100 |

```json
{
  "now": "2026-11-11T10:00:00+01:00",
  "items": [ Petición… ],
  "removed_ids": [41, 52]
}
```

Orden: la que cambió más recientemente primero. Para el administrador, `mine` son las que pidió desde la app.

**Para saber qué ha cambiado sin descargarlo todo**: guarda `now` y, la próxima vez, llama con `since=<ese now>` (codificado en la URL: `since=2026-11-11T10%3A00%3A00%2B01%3A00`).
- `items`: las que han cambiado (estado, o quién la pidió) desde entonces.
- `removed_ids`: las que **ya no existen** desde entonces (retiradas, juntadas con otra, de alguien que ya no está): bórralas de tu lista. Solo con `since`; se recuerdan 30 días.
- `now` va unos segundos por detrás del momento de la respuesta, para que no se pierda nada que cambie mientras se lee. Alguna petición puede venir repetida en la siguiente llamada: no pasa nada.
- Las peticiones cerradas se borran del todo tras unos meses, sin aparecer en `removed_ids`.

### 8.14 `GET /requests/{id}`

Una petición (7.5). `404 not_found` si ya no existe (se retiró o se juntó con otra: por ejemplo, varias temporadas pedidas que pasan a ser «todo lo que falta»).

### 8.15 `POST /requests`

Pedir algo. Cuerpo JSON:

| Tipo | Cuerpo |
|---|---|
| Película | `{ "type": "movie", "tmdb_id": 920 }` |
| Temporada | `{ "type": "series", "tmdb_id": 1396, "season": 2 }` |
| Un episodio | `{ "type": "series", "tmdb_id": 1396, "season": 2, "episode": 3 }` (ya emitido) |
| Todo lo que falta de una serie | `{ "type": "series", "tmdb_id": 1396 }` (sin `season`, o `"season": null`) |
| Álbum, EP o sencillo | `{ "type": "music", "deezer_id": "302127" }` |
| Un sencillo tal cual, aunque su canción esté en un álbum | `{ "type": "music", "deezer_id": "31", "as_single": true }` |

```http
POST https://stremfin.ejemplo.com/api/v1/requests
Authorization: Bearer <token>
Content-Type: application/json

{ "type": "series", "tmdb_id": 1396, "season": 2 }
```

Respuesta:

```json
{
  "outcome": "created",
  "message": "Petición enviada. Te avisamos cuando el administrador conteste.",
  "instead_of": null,
  "request": { "…": "Petición completa (7.5)" }
}
```

`outcome` dice qué ha pasado. Enseña `message` y actualiza la pantalla con `request`:

| HTTP | `outcome` | Qué ha pasado | `request` |
|---|---|---|---|
| 201 | `created` | Petición nueva, esperando la respuesta del administrador (modo `review`) | La nueva |
| 201 | `started` | Aceptada sola y en marcha (modo `direct` o administrador) | La nueva (o la que esperaba y ya está aceptada) |
| 200 | `joined` | Alguien ya lo había pedido: te apuntas a esa petición (te llegan sus avisos) | La existente |
| 200 | `watching` | Película (o, desde 1.87.0, álbum) que ya se está descargando y nadie había pedido: te apuntas al aviso de «ya está en Jellyfin» | La nueva (ya aceptada) |
| 200 | `included` | Pediste una temporada (o un episodio) y ya estaba pedido «todo lo que falta» (o esa temporada): te apuntas a esa | La que lo cubre |
| 200 | `already` | Ya lo habías pedido tú | La existente |
| 409 | `have` | Ya está en Jellyfin | `null` |
| 409 | `busy` | Se está descargando ya (serie: todo lo que falta está en descargas) | `null` |
| 422 | `unavailable` | No se puede pedir (no se puede conseguir, temporada o episodio que no existe, episodio aún no emitido o especiales, álbum que Deezer no conoce) | `null` |
| 429 | `limit` | Has llegado a tu límite; `message` dice cuál y `limit` es `pending` o `daily` (este, con `Retry-After`) | `null` |

**Música: el álbum completo siempre que exista** (desde 1.84.0). Si el `deezer_id` es de un sencillo y su canción está en un álbum, Stremfin pide **ese álbum** en su lugar: `request` es la petición del álbum, `message` lo dice («Esa canción está en el álbum «…»: se descargará todo el álbum.» desde 1.87.0, o «…: ya lo tienes en Jellyfin.», o el mensaje de siempre detrás del nombre del álbum) e `instead_of` trae el sencillo que mandaste (`{ "deezer_id", "title", "kind": "single" }`). El `outcome` es el del álbum (por ejemplo `have` si ya lo tienes, o `joined` si alguien ya lo pidió). `instead_of` es `null` en todo lo demás (con `outcome: "limit"` no viene: trátalo como `null`). Para que la persona no se sorprenda, enseña antes el álbum (`album_instead` de [8.12](#812-get-musicalbumsdeezer_id) o `ask` de [8.27](#827-get-musicsongsdeezer_id)). Un sencillo que no está en ningún álbum se pide como sencillo. Con `"as_single": true` se pide el sencillo aunque haya álbum: solo si la persona insiste. Desde 1.86.0 la regla es la misma en el bot de Telegram y en el panel (se puede pedir una canción; lo que se descarga es su álbum), y el álbum es siempre un álbum o EP **del mismo artista**, nunca un recopilatorio de varios.

Si pides **todo lo que falta** de una serie de la que había temporadas o episodios sueltos pedidos esperando respuesta, se juntan en una sola petición con todos los que las pidieron.

Un **episodio suelto** sigue el camino de una temporada (con revisión o directo, y un plan de ese único episodio al aceptarlo), y se da por cumplido en cuanto ese episodio llega a Jellyfin por cualquier camino (también si llega con su temporada entera o porque la serie está seguida). Pedir un episodio sin su `season` es `422 invalid`.

Errores posibles además (con la forma `{"error": …}`): `422 invalid` (cuerpo mal formado), `404 not_found` (el `tmdb_id` no existe), `503 source_unavailable`. Ojo: `422` puede ser un resultado (`outcome: "unavailable"`) o un error (`error.code: "invalid"`): distingue por el cuerpo.

### 8.16 `DELETE /requests/{id}`

Retira una petición **tuya** que **aún espera respuesta**. Si la pidió más gente, solo te quitas tú; si eras la única persona, la petición desaparece.

```json
{ "outcome": "withdrawn", "message": "Petición retirada." }
```

Errores: `404 not_found`, `403 not_yours`, `409 already_answered`. Retirar y volver a pedir lo mismo el mismo día no vuelve a avisar al administrador.

### 8.17 `GET /movies/{tmdb_id}/similar` y `GET /series/{tmdb_id}/similar`

Títulos parecidos («Si te gustó…»): los que TMDB recomienda después de este (y, si no recomienda ninguno, sus parecidos).

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `only` | no | `all` (por defecto), `missing`, `available` (como en [8.4](#84-get-search)) |
| `limit` | no | 1–40 (por defecto 20) |

```json
{ "type": "movie", "tmdb_id": 920, "items": [ Título… ] }
```

- `items`: títulos (7.1) del mismo tipo, con `library`, `request` y `age`.
- `404 not_found` si el título no existe.

### 8.18 `GET /genres`

Los géneros para explorar, en español.

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `type` | sí | `movie`, `series` |

```json
{ "type": "movie", "genres": [ { "id": 16, "name": "Animación" }, { "id": 35, "name": "Comedia" } ] }
```

Los de películas y los de series no son los mismos: pide los del tipo que vas a explorar. Cambian muy poco: guárdalos un día.

### 8.19 `GET /discover`

Explorar sin buscar: por género, año y plataforma.

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `type` | sí | `movie`, `series` |
| `genre` | no | Un `id` de [8.18](#818-get-genres) |
| `year` | no | Año de estreno (película) o del primer episodio (serie), de 1900 a dentro de dos años |
| `platform` | no | `netflix`, `disney`, `prime`: lo que está en esa plataforma en el país de Novedades |
| `sort` | no | `popular` (por defecto), `new` (lo último que ya ha salido, lo más nuevo primero) o `rating` (mejor valoradas, solo con bastantes votos) |
| `only` | no | `all` (por defecto), `missing`, `available` |
| `limit` | no | 1–40 (por defecto 20) |
| `cursor` | no | El `next_cursor` de la respuesta anterior, tal cual |

```json
{
  "type": "movie", "sort": "popular", "genre": 16, "year": null, "platform": "netflix", "region": "ES", "only": "all",
  "items": [ Título… ],
  "next_cursor": "2.0"
}
```

- `items`: títulos (7.1), con `library`, `request` y `age`.
- Las páginas siguientes, como en la búsqueda: repite la misma llamada con `cursor=<next_cursor>` mientras no sea `null`. Con `only` puede volver con menos de `limit` (o vacía) y con `next_cursor`.
- Cuenta como búsqueda en los límites (120 por minuto).

### 8.20 `GET /collections/{id}`

Una saga (el `collection.id` de una ficha de película) con sus películas en orden de estreno.

```json
{
  "id": 87118,
  "name": "Cars",
  "overview": "…",
  "poster": "https://image.tmdb.org/t/p/w342/c.jpg",
  "backdrop": "https://image.tmdb.org/t/p/w1280/c2.jpg",
  "summary": { "total": 4, "have": 2, "downloading": 0, "missing": 1, "upcoming": 1 },
  "items": [ Título… con "released": true ]
}
```

| Campo | Notas |
|---|---|
| `items` | Las películas (7.1, con `library`, `request` y `age`), de la más antigua a la más nueva; las que aún no tienen fecha, al final. Cada una con `released`: si ya ha salido |
| `summary.have` | Las que ya están en Jellyfin |
| `summary.missing` | Las que ya han salido y no están ni se están descargando: lo que pediría «Pedir lo que falta» |
| `summary.upcoming` | Las que aún no han salido (se pueden pedir: esperan a que salgan) |

Para «Pedir lo que falta», la app pide cada una de las que faltan con `POST /requests` (una petición por película). `404 not_found` si la saga no existe.

### 8.21 `GET /upcoming`

Próximamente: lo que está al llegar a Jellyfin, igual que la página del panel.

```json
{
  "days": 60,
  "movies": [ Título… con "upcoming": "dated" ],
  "episodes": [
    { "tmdb_id": 1396, "title": "Breaking Bad", "poster": "https://…", "season": 2, "episode": 2, "episode_title": "Grilled", "date": "2026-11-13" }
  ]
}
```

| Campo | Notas |
|---|---|
| `movies` | Las películas que se esperan (de una petición aceptada que aún no ha salido o no tiene buena versión, o que espera el administrador), como títulos (7.1) con `library`, `request` y `age`, y `upcoming`: `dated` (con fecha de estreno digital, en `date`), `released_waiting` (ya ha salido en digital: se busca una buena versión cada día) o `undated` (sin fecha todavía). En ese orden, las `dated` por fecha |
| `episodes` | Los próximos episodios de las series que sigue el administrador (se descargan solos), de hoy a `days` días, hasta 5 por serie, por fecha. Sin especiales. `tmdb_id` y `episode_title` pueden ser `null` |

Para que te avisen de una película que aún no ha salido, **pídela** (`POST /requests`): su ficha dice cuándo sale en `release`, y la petición te avisa cuando esté en Jellyfin.

Cuenta en el límite de las que más cuestan (60 por minuto): no hace falta pedirla más de una vez al abrir la pantalla.

### 8.22 `GET /notifications`

Lo que ha pasado con tus peticiones y tus avisos de problemas, lo más nuevo primero. Son los mismos avisos que manda el bot de Telegram, aquí también para quien solo usa la app. Se guardan 30 días.

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `since` | no | Fecha ISO 8601: solo lo que ha llegado desde entonces (usa el `now` de la llamada anterior) |
| `limit` | no | 1–100 (por defecto 50) |

```json
{
  "now": "2026-11-12T18:30:00+01:00",
  "items": [
    { "id": 41, "kind": "available", "message": "🎬 Coche (2006) ya está en Jellyfin, ¡a disfrutarla!", "request_id": 12, "problem_id": null, "created_at": "2026-11-12T18:29:10+01:00" }
  ]
}
```

| `kind` | Qué ha pasado |
|---|---|
| `approved` | El administrador ha aceptado tu petición |
| `started` | Tu petición está en marcha (alguien con peticiones directas la pidió o se unió a la tuya) |
| `rejected` | No la ha aceptado, o (desde 1.87.0) ha cancelado una que ya estaba aceptada: `message` dice cuál («…no ha aceptado tu petición de…» / «…ha cancelado tu petición de…») y el motivo |
| `waiting` | Aceptada, pero aún no ha salido o no hay una buena versión: te avisa cuando esté |
| `progress` | Una serie a medias: unos episodios ya están y otros en revisión |
| `available` | Ya está en Jellyfin |
| `problem_fixed` | Ya hay una versión nueva de algo de lo que avisaste |

- `message`: texto listo para enseñar (sin HTML). `request_id` o `problem_id` dicen de qué es: con ellos puedes abrir la petición (`GET /requests/{id}`) o tu aviso.
- Para notificaciones en el móvil: cada poco (por ejemplo, al abrir la app y cada 15 minutos en segundo plano) pide `GET /notifications?since=<now anterior>` y enseña una notificación local por cada `item`. Lo que tú mismo acabas de pedir no se avisa (ya tienes la respuesta del `POST`).
- Del administrador solo salen las de sus propias peticiones hechas desde la app.

### 8.23 `GET /problems` y `POST /problems`

Avisar de que algo de Jellyfin está mal. Al administrador le llega por Telegram con la página del título, donde puede descargar otra versión; cuando termina de descargarse una nueva, el aviso queda arreglado (`status: "fixed"`) y a quien avisó le llega `problem_fixed` en [8.22](#822-get-notifications).

**`POST /problems`**

```json
{ "type": "series", "tmdb_id": 1396, "season": 2, "episode": 3, "kind": "language", "note": "Se oye en inglés" }
```

| Campo | Obligatorio | Valores |
|---|---|---|
| `type` | sí | `movie`, `series` |
| `tmdb_id` | sí | El título (tiene que estar en Jellyfin) |
| `season`, `episode` | no | Solo series: una temporada, o un episodio (con su temporada) |
| `kind` | sí | `language` (no está en castellano), `quality` (se ve mal), `playback` (no se reproduce o se corta), `subtitles`, `missing` (faltan episodios), `other` |
| `note` | no | Lo que quiera contar, hasta 500 caracteres |

| HTTP | `outcome` | Qué pasa |
|---|---|---|
| 201 | `created` | Avisado |
| 200 | `already` | Ya había avisado lo mismo y sigue sin arreglar |
| 422 | `not_in_jellyfin` | Eso no está en Jellyfin |
| 429 | `limit` | Más de 10 avisos en un día |

La respuesta lleva `message` (para enseñar) y `problem` (el aviso, como en la lista; `null` si no se creó). Errores posibles además: `422 invalid` (por ejemplo, `episode` sin `season`), `404 not_found`, `503 source_unavailable` y `503 busy`.

**`GET /problems?status=open|fixed|all`** (`status` por defecto `all`): tus avisos, los más nuevos primero (100 como mucho).

```json
{
  "items": [
    { "id": 7, "type": "series", "tmdb_id": 1396, "title": "Breaking Bad", "season": 2, "episode": 3, "kind": "language", "kind_label": "No está en castellano",
      "note": "Se oye en inglés", "status": "open", "created_at": "2026-11-12T18:00:00+01:00", "fixed_at": null }
  ]
}
```

Un aviso de una película se arregla con la siguiente descarga de esa película; uno de una serie, con la siguiente descarga de un episodio de esa serie (de esa temporada, o de ese episodio, si lo dijiste). Si el administrador decide que está bien, el aviso se queda `open`.

### 8.24 `GET /people/{id}`

Desde 1.82.0. La ficha de una persona (un actor, una directora, un guionista…): quién es y las películas y series en las que ha trabajado, cada una con lo que hay en Jellyfin y quién la ha pedido. El `id` es el de `cast[].id` o `crew[].id` de una ficha ([8.5](#85-get-moviestmdb_id), [8.7](#87-get-seriestmdb_id)) o el de `people[].id` de la búsqueda ([8.4](#84-get-search)).

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `type` | no | `all` (por defecto), `movie`, `series` |
| `credit` | no | `all` (por defecto), `cast` (solo donde actúa), `crew` (solo lo que ha dirigido, escrito o creado) |
| `sort` | no | `popular` (por defecto: lo más conocido primero), `new` (lo más reciente primero; lo que no tiene fecha, al final) |
| `only` | no | `all` (por defecto), `missing`, `available`, como en la búsqueda |
| `limit` | no | 1–40 (por defecto 20) |
| `cursor` | no | Para los siguientes: el `next_cursor` de la respuesta anterior, tal cual |

```json
{
  "id": 887,
  "name": "Owen Wilson",
  "photo": "https://image.tmdb.org/t/p/h632/o.jpg",
  "department": "acting",
  "biography": "Owen Cunningham Wilson es un actor…",
  "biography_language": "es",
  "birthday": "1968-11-18",
  "deathday": null,
  "birthplace": "Dallas, Texas, USA",
  "summary": { "total": 74, "have": 9, "movies": 68, "movies_have": 8, "series": 6, "series_have": 1 },
  "type": "all", "credit": "all", "sort": "popular", "only": "all",
  "items": [
    { Título…, "acted": true, "character": "Rayo McQueen (voz)", "jobs": [] },
    { Título…, "acted": true, "character": "Eli Cash", "jobs": ["writer"] }
  ],
  "next_cursor": "20"
}
```

| Campo | Notas |
|---|---|
| `photo` | Su foto en grande (632 px de alto), puede ser `null` |
| `department` | A qué se dedica sobre todo: `acting`, `directing`, `writing`, `production`, `other` o `null` |
| `biography`, `biography_language` | La biografía entera (recórtala en la app con un «ver más»). En español si TMDB la tiene (`es`); si no, en inglés (`en`); si no hay ninguna, los dos `null` |
| `birthday`, `deathday` | `AAAA-MM-DD` o `null` |
| `birthplace` | Dónde nació, como lo escribe TMDB (suele venir en inglés), o `null` |
| `summary` | De **todo** su trabajo, sin mirar los filtros de la llamada: cuántos títulos (`total`), cuántos tienes en Jellyfin (`have`) y lo mismo por películas y por series. Para «Tienes 9 de 74» |
| `items` | Títulos (7.1) con `library`, `request` y `age`, más lo que hizo en cada uno: `acted` (si actúa), `character` (su personaje, puede ser `null`) y `jobs` (lo que hizo detrás de la cámara: `director`, `writer`, `creator`; vacía si solo actúa). Un título sale **una vez** aunque actúe y dirija |
| `next_cursor` | Como en la búsqueda: repite la misma llamada con `cursor=<next_cursor>` mientras no sea `null` |

- No salen las entrevistas ni los programas de noticias, las apariciones «como sí mismo», los agradecimientos ni lo que no tiene cartel: solo su trabajo.
- Si la persona no existe, `404 not_found`. Si TMDB no responde, `503 source_unavailable`.
- Cuenta como búsqueda en los límites (120 por minuto). Se guarda un día en el servidor: abrir la misma persona otra vez es rápido.

### 8.25 `GET /movies/{tmdb_id}/trailers` y `GET /series/{tmdb_id}/trailers`

Desde 1.83.0. Todos los tráilers de un título, **el mejor primero**, sin leer su ficha entera: para un botón «Tráiler» en una lista, una vista previa o una fila de tráilers. Sin parámetros.

```json
{
  "type": "movie",
  "tmdb_id": 597,
  "trailer": { "name": "Tráiler Oficial 25º aniversario", "key": "1EMkCJWQIDY", "url": "https://www.youtube.com/watch?v=1EMkCJWQIDY", "type": "trailer", "language": "es", "country": "ES", "subtitled": false, "official": true, "published_at": "2023-01-10" },
  "items": [
    { "name": "Tráiler Oficial 25º aniversario", "key": "1EMkCJWQIDY", "url": "https://www.youtube.com/watch?v=1EMkCJWQIDY", "type": "trailer", "language": "es", "country": "ES", "subtitled": false, "official": true, "published_at": "2023-01-10" },
    { "name": "Tráiler Oficial 25º aniversario [VOSE]", "key": "6FKmt1RcLug", "url": "https://www.youtube.com/watch?v=6FKmt1RcLug", "type": "trailer", "language": "es", "country": "ES", "subtitled": true, "official": true, "published_at": "2023-01-10" },
    { "name": "Official Trailer", "key": "kVrqfYjkTdQ", "url": "https://www.youtube.com/watch?v=kVrqfYjkTdQ", "type": "trailer", "language": "en", "country": "US", "subtitled": false, "official": true, "published_at": "2012-02-01" }
  ]
}
```

| Campo | Notas |
|---|---|
| `trailer` | El primero de `items` (el mismo que da la ficha en su campo `trailer`); `null` si no hay ninguno |
| `items` | Hasta 10, del mejor al peor. Vacía si el título no tiene tráilers |
| `key`, `url` | El id del vídeo de YouTube (para incrustarlo) y su dirección (para abrirlo). Siempre es YouTube: Stremfin no aloja ni descarga el vídeo |
| `type` | `trailer` o `teaser` (un avance corto) |
| `language`, `country` | El idioma (`es`, `en`…) y el país (`ES`, `MX`, `US`…) con que está etiquetado en TMDB; cualquiera puede ser `null`. `es` + `ES` = español de España |
| `subtitled` | `true` si el nombre dice que es la versión original con subtítulos (VOSE, «subtitulado»): las voces no están dobladas |
| `official` | Si TMDB lo marca como oficial (de la distribuidora o la plataforma) |
| `published_at` | Cuándo se publicó (`AAAA-MM-DD`) o `null` |

**El orden**, que la app no tiene que rehacer:

1. Doblado al español de España (`es` + `ES`, sin `subtitled`).
2. En español sin país indicado.
3. Doblado al español de otro país (latino).
4. En español pero subtitulado (versión original).
5. En inglés.
6. El resto (sin idioma indicado: Stremfin solo pide a TMDB los vídeos en español, en inglés o sin idioma).

Dentro de cada grupo: un tráiler antes que un teaser, uno oficial antes que los demás y el más reciente primero. Un teaser en español va **antes** que un tráiler en inglés.

- **Cómo de seguro es el idioma**: es la etiqueta que le pusieron en TMDB, no una comprobación del audio. En la práctica acierta casi siempre; para enseñar «Tráiler en español» con seguridad, pide `language == "es"` y `subtitled == false`, y si quieres solo el de España, además `country == "ES"`.
- Si el primero no está en español, es que TMDB no tiene ninguno en español de ese título: Stremfin no busca en otros sitios.
- Si el título no existe, `404 not_found`. Si TMDB no responde, `503 source_unavailable` (la ficha, en cambio, llega igual con `trailer: null`).
- Es ligera: sale de lo mismo que la ficha y se guarda un día en el servidor. Cuenta solo en el límite general (300 por minuto).

### 8.26 `GET /music/songs`

Desde 1.84.0. Buscar canciones.

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `q` | sí | Texto, 1–100 caracteres |
| `limit` | no | 1–50 (por defecto 20) |
| `cursor` | no | El `next_cursor` de la respuesta anterior |

Devuelve `{ "query": "…", "items": [ Canción… ], "next_cursor": "20" }` (7.7), en el orden de Deezer. Cada búsqueda lee como mucho 50 canciones y se guarda una hora. Cuenta como búsqueda en los límites.

### 8.27 `GET /music/songs/{deezer_id}`

Desde 1.84.0. Una canción y **qué disco pedir** para tenerla.

```json
{
  "deezer_id": "3135556",
  "title": "One More Time",
  "…": "el resto de 7.7",
  "position": 1,
  "disc": 1,
  "release_date": "2000-11-13",
  "album": { Álbum… },
  "album_instead": { Álbum… },
  "ask": "302127"
}
```

| Campo | Notas |
|---|---|
| `position`, `disc`, `release_date` | Su pista y disco dentro de `album`, y su fecha; cualquiera puede ser `null` |
| `album` | Aquí, el álbum **entero** (7.6) en el que Deezer la sitúa, con `library`, `request`, `download` y `can_request`. `null` si no se sabe |
| `album_instead` | Si `album` es solo su sencillo y la canción está en un álbum: ese álbum (7.6). `null` si `album` ya es un álbum o no hay otro |
| `ask` | El `deezer_id` que mandar a `POST /requests`: el de `album_instead` si lo hay; si no, el de `album`. `null` si no se puede pedir nada |

El botón de una canción es siempre «Pedir el álbum» con `ask` (mira `can_request` de ese álbum). `404 not_found` si Deezer no tiene esa canción. Cuenta en el límite de 60 por minuto. Se guarda 6 horas.

### 8.28 `GET /music/charts`

Desde 1.85.0. Las listas de éxitos que hay, de las listas públicas de Apple para España (sin clave). Cuenta solo en el límite general.

```json
{
  "country": "ES",
  "charts": [
    { "id": "top-songs", "name": "Top España · Canciones", "kind": "songs", "measure": "played", "genre": null },
    { "id": "top-albums", "name": "Top España · Álbumes", "kind": "albums", "measure": "played", "genre": null },
    { "id": "latino-songs", "name": "Top Latino · Canciones", "kind": "songs", "measure": "sold", "genre": "latino" },
    { "id": "latino-albums", "name": "Top Latino · Álbumes", "kind": "albums", "measure": "sold", "genre": "latino" }
  ]
}
```

| Campo | Notas |
|---|---|
| `id` | Para pedir la lista ([8.29](#829-get-musicchartsid)) |
| `kind` | `songs` (canciones, cada una con su álbum) o `albums` |
| `measure` | `played`: lo más **escuchado** en Apple Music España (las dos listas generales). `sold`: lo más **comprado** en la tienda de Apple en España (las listas por género: Apple no publica lo más escuchado por género) |
| `genre` | `null` en las generales; en las demás: `latino`, `pop`, `hiphop`, `rock`, `dance`, `electronica`, `alternativa`, `rnb`, `reggae`, `bandas-sonoras` |

Cada género tiene su lista de canciones (`{genre}-songs`) y de álbumes (`{genre}-albums`). La lista de listas no cambia: guárdala.

### 8.29 `GET /music/charts/{id}`

Desde 1.85.0. Una lista, hasta 50 puestos.

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `limit` | no | 1–50 (por defecto 50) |
| `only` | no | `all` (por defecto), `missing`, `available` |

Una lista de **álbumes** (`kind: "albums"`) devuelve Álbumes (7.6) con `rank`:

```json
{ "id": "top-albums", "name": "Top España · Álbumes", "kind": "albums", "measure": "played", "genre": null, "country": "ES", "only": "all", "items": [ Álbum… ] }
```

Una lista de **canciones** (`kind: "songs"`) devuelve cada canción con **el disco que pedir**:

```json
{
  "id": "top-songs", "name": "Top España · Canciones", "kind": "songs", "measure": "played", "genre": null, "country": "ES", "only": "all",
  "items": [
    {
      "rank": 1,
      "title": "BbY WOW",
      "artist": "KAROL G, Judeline & rusowsky",
      "cover": "https://…/600x600bb.jpg",
      "preview": "https://audio-ssl.itunes.apple.com/…/….m4a",
      "release_date": "2026-08-05",
      "in_jellyfin": false,
      "in_album": null,
      "album": { Álbum… }
    }
  ]
}
```

| Campo | Notas |
|---|---|
| `rank` | Su puesto en la lista. Con `only`, los puestos se saltan (son los de la lista entera) |
| `cover`, `preview`, `release_date` | Portada (600 px), fragmento de 30 segundos (AAC; puede ser `null`) y fecha, de Apple; cualquiera puede ser `null` |
| `in_jellyfin`, `in_album` | Si ya tienes la canción (o su disco) y en qué álbum de Jellyfin está la canción |
| `album` | El disco de la canción como Álbum (7.6), con `library`, `request`, `download` y `can_request`. `null` si no se sabe de qué disco es o no se encontró en Deezer (no se puede pedir). Trae `contains` (la canción) y `rank: null`. Varias canciones del mismo disco traen el mismo `album` |

- **Al pulsar una canción, lleva al álbum**, no a la canción: abre `GET /music/albums/{album.deezer_id}` ([8.12](#812-get-musicalbumsdeezer_id)). Si `album.kind` es `single`, esa ficha dice en `album_instead` el álbum entero, y pedir el sencillo pide ese álbum ([8.15](#815-post-requests)).
- Estas canciones no llevan `deezer_id`: vienen de Apple, no de Deezer. No valen para [8.27](#827-get-musicsongsdeezer_id).
- En una lista de álbumes, lo que no está en Deezer viene con `deezer_id: null` y `can_request: false`. Como en `/music/new`, no salen los discos de ruido de fondo: los puestos pueden saltarse.
- `GET /music/charts/top-albums` trae lo mismo que `/music/new` ([8.9](#89-get-musicnew)), que sigue igual.
- `404 not_found` si la lista no existe; `503 source_unavailable` si Apple (o Deezer, al emparejar) no responde; tras un fallo de Apple no se reintenta hasta pasados 10 minutos. La primera vez que se pide una lista tarda (hay que emparejar cada disco con Deezer); después se guarda 6 horas. Cuenta en el límite de 60 por minuto.

### 8.30 `GET /music/releases`

Desde 1.85.0. Los discos de **los artistas que sigue la casa** (los elige el administrador en *Música → Artistas seguidos*), del más nuevo al más antiguo: lo que acaba de salir y lo anunciado.

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `days` | no | Cuántos días atrás mirar, 1–365 (por defecto 90) |
| `only` | no | `all` (por defecto), `missing`, `available` |

```json
{ "days": 90, "only": "all", "artists": 12, "items": [ { Álbum…, "upcoming": true } ] }
```

- `upcoming`: `true` si su fecha (`release_date`) aún no ha llegado: anunciado, a punto de salir. Se puede pedir igualmente.
- `artists`: cuántos artistas sigue la casa. Con `0`, la lista viene vacía: enseña «El administrador aún no sigue a ningún artista».
- Stremfin mira los discos de cada artista una vez al día; no es instantáneo.
- Como mucho 100 discos. `tracks` viene `null` (está en la ficha). Cuenta solo en el límite general.

### 8.31 `GET /music/requested`

Desde 1.85.0. Lo más pedido en casa: los álbumes con más gente en su petición, sin los rechazados.

| Parámetro | Obligatorio | Valores |
|---|---|---|
| `days` | no | Peticiones de los últimos días, 1–365 (por defecto 90) |
| `limit` | no | 1–50 (por defecto 20) |

Devuelve `{ "days": 90, "items": [ { Álbum…, "people": 3 } ] }`: `people` es cuánta gente lo pidió (el administrador cuenta como uno). Entre iguales, el más reciente primero. En esta lista `tracks` y `release_date` vienen `null` y `kind` es siempre `album` (sale de la petición, no de Deezer): para el tipo y las canciones, abre la ficha ([8.12](#812-get-musicalbumsdeezer_id)). Lo que ya llegó a Jellyfin sigue saliendo, con `library.in_jellyfin: true`. Cuenta solo en el límite general.

---

## 9. Estados, uno a uno

### 9.1 `status` de una petición

| `status` | `status_label` | Qué es | Abierta |
|---|---|---|---|
| `pending` | Esperando respuesta | Le ha llegado al administrador y aún no ha contestado | sí |
| `approved` | Aceptada · Aceptada sola | Aceptada; `progress` dice por dónde va. «Aceptada sola» si `direct` | sí |
| `rejected` | No aceptada (· motivo) · Cancelada (· motivo) | Rechazada. `reason`: `quality` (aún no hay una versión buena), `later` (mejor más adelante) o `null`. Con `cancelled: true` (desde 1.88.0) ya estaba aceptada y el administrador la canceló: la etiqueta es «Cancelada» | no |
| `completed` | Ya en Jellyfin | Ya se puede ver | no |

Una serie aceptada puede llegar por partes: la petición sigue `approved` mientras falte algún episodio y pasa a `completed` cuando está todo.

### 9.2 `progress.state` de una petición aceptada

| `state` | `label` (ejemplos) | Qué es |
|---|---|---|
| `accepted` | Aceptada | Aceptada, aún sin descarga en marcha |
| `preparing` | Buscando los enlaces | Serie: se están buscando los enlaces de los episodios |
| `waiting_version` | Esperando una versión buena | Película: aún no hay una versión con la calidad e idioma de casa (o no ha salido). Se descarga en cuanto la haya |
| `downloading` | En cola · Descargando · Comprobando… | En descargas: `phase` dice en qué punto |
| `attention` | En revisión, o «En revisión · se sigue intentando solo» | La descarga necesita que el administrador elija otro enlace. Si fue porque el archivo no estaba listo en el servicio de descargas, Stremfin lo sigue intentando solo: lo dice `label` (desde 1.90.2, «En revisión · se sigue intentando solo») y lo detalla `recheck`. En una serie, `label` lo dice cuando todos sus episodios en revisión están así |

En música, `state` es `accepted` (aceptada, aún sin mandar a la descarga), `downloading` (mandada a la descarga: en su cola o bajando), `importing` (descargada: entrando en la biblioteca) o `attention` (falló la descarga: el administrador lo verá). Los campos de `progress` de un álbum son `state`, `label`, `phase`, `percent`, `track_errors` y `sent_at`, como en [9.5](#95-download-de-un-álbum-de-camino-a-jellyfin).

**Campos de `progress`** (película y serie; vienen siempre, `null` cuando no aplican):

| Campo | Notas |
|---|---|
| `state`, `label` | Arriba |
| `phase` | En qué punto está la descarga (tabla de abajo). `null` sin descarga en marcha. En una serie, lo más avanzado que está pasando (si un episodio baja y otro espera, `downloading`) |
| `percent` | 0–100. Película: lo descargado; `100` al comprobar y colocar; `null` antes de empezar a bajar. Serie: la media de sus episodios (cada uno cuenta igual; los terminados, 100) |
| `downloaded_bytes`, `total_bytes` | Bytes bajados y tamaño. Serie: la suma; `total_bytes` es `null` si algún episodio aún no tiene tamaño |
| `speed` | Bytes por segundo mientras baja; `null` si no baja o está en pausa. Serie: la suma |
| `eta_seconds` | Segundos que faltan, a la velocidad de ahora; `null` si no se sabe. En una serie es orientativo (los episodios en cola aún no bajan) |
| `waiting_since` | Solo película, con `phase: "waiting_file"`: desde cuándo espera |
| `paused` | `true` si el administrador ha pausado todas las descargas |
| `recheck` | Desde 1.90.1. Solo con `state: "attention"` (o un episodio en revisión): el archivo no estaba listo en el servicio de descargas y **Stremfin lo vuelve a mirar solo** cada pocas horas durante unos días; en cuanto esté, la descarga arranca sola y `state` pasa a `downloading`. Objeto `{ "until", "next_at", "every_hours", "text" }`: hasta cuándo lo intenta, cuándo es la siguiente mirada (fechas ISO 8601), cada cuántas horas y el texto listo para enseñar («Se sigue intentando solo cada 2 h · quedan 2 días»; «queda 1 día», «quedan 5 h»; con las descargas en pausa, «En pausa: se sigue intentando solo al reanudar · quedan 2 días»). `null` en lo demás. En una serie va en cada episodio de `episodes`; el `recheck` de la serie entera es siempre `null`. Si el campo no viene, ese Stremfin es anterior a 1.90.1 |
| `episodes_done`, `episodes_total`, `episodes_attention` | Solo serie: terminados, en total (sin cancelados) y en revisión |
| `episodes` | Solo serie: cada episodio, en orden: `season`, `episode`, `episode_end` (episodio doble: el último; si no, `null`) y los campos de una descarga: `phase`, `label`, `percent`, `downloaded_bytes`, `total_bytes`, `speed`, `eta_seconds`, `waiting_since`, `paused`, `recheck` |

**`phase` de una descarga:**

| `phase` | `label` | Qué es |
|---|---|---|
| `queued` | En cola | Esperando turno: se descargan unas pocas a la vez |
| `preparing` | Preparando | Pidiendo el archivo al servicio de descargas |
| `waiting_file` | Esperando a que el archivo esté listo | El servicio aún no lo tenía listo (no era «rápida») y lo está preparando. Puede tardar; si tarda demasiado, Stremfin prueba otra versión sola o se lo pasa al administrador |
| `downloading` | Descargando | Bajando: `percent`, `speed`, `eta_seconds` |
| `verifying` | Comprobando | Comprobando que el vídeo está bien |
| `moving` | Colocando | Poniéndolo en su carpeta de Jellyfin |
| `attention` | En revisión (o «En revisión · se sigue intentando solo») | Ha fallado y el administrador tiene que decidir; con el segundo texto, Stremfin lo sigue intentando solo (ver `recheck`) |
| `completed` | En descargas | Solo en `episodes`: ese episodio ya está |

El avance se actualiza en el servidor cada pocos segundos (hasta 10) y no cambia `updated_at`: para una pantalla de cola, vuelve a pedir las abiertas (`GET /requests` o `GET /requests/{id}`) cada 5–10 segundos **mientras esté a la vista**, y para en segundo plano.

### 9.3 `library.status` de un título

| Película | Serie |
|---|---|
| `available`: está en Jellyfin | `available`: la serie está en Jellyfin |
| `downloading`: se está descargando | `partial`: está, pero falta la temporada que anuncia la tarjeta |
| `missing`: no está | `downloading`: no está y se descargan episodios |
| | `missing`: no está |

### 9.4 `status` de una temporada

| `status` | Qué es |
|---|---|
| `upcoming` | Aún no se ha emitido ningún episodio |
| `complete` | Está entera (todo lo emitido) |
| `downloading` | Lo que falta ya está en descargas o esperando revisión |
| `partial` | Hay algunos episodios y faltan otros |
| `missing` | No hay ninguno |

### 9.5 `download` de un álbum de camino a Jellyfin

El camino de un álbum: se pide → el administrador lo acepta (o se acepta solo) → Stremfin lo manda al **servicio de descarga de música** de casa → ese servicio lo pone en su cola y lo baja → llega a la carpeta de entrada y Stremfin lo **importa** a la biblioteca (lo ordena y le pone etiquetas) → Jellyfin lo lee → la petición pasa a `completed`.

| `phase` | `label` | Qué es | `percent` |
|---|---|---|---|
| `sent` | Pedido a la descarga: esperando a que llegue | Mandado, pero el servicio aún no lo enseña en su cola (o no responde) | `null` |
| `queued` | En cola para descargar | En la cola del servicio, esperando turno | 0 |
| `downloading` | Descargando | Bajando | 0–100 |
| `importing` | Descargado: importándose a la biblioteca (o «Ya en la biblioteca: terminando», o «Descargado con fallos en alguna canción: importándose») | Bajado (aunque el servicio ya lo haya quitado de su cola). Stremfin lo mete en la biblioteca en cuanto el servicio termina con todo (unos minutos) y Jellyfin lo lee | 100 |
| `failed` | Falló la descarga | El servicio no pudo bajarlo. El administrador puede volver a pedirlo | `null` |

| Campo | Notas |
|---|---|
| `track_errors` | `true` si el servicio lo bajó pero falló alguna canción: llegará incompleto |
| `sent_at` | Cuándo se mandó a la descarga |
| `arrived_at` | Solo en `download` de un álbum (7.6): cuándo se vio en la biblioteca, si ya está (la petición se cierra en unos minutos) |

Las fases salen de lo que el servicio dice de su cola (se mira como mucho cada pocos segundos). Si el servicio no responde, se ve `sent` hasta que el álbum llega. Un álbum que lleva mucho en `sent` puede haberse quedado atascado: es cosa del administrador.

---

## 10. Cómo montar la app, pantalla a pantalla

### 10.1 Al entrar

1. Entra en Jellyfin (usuario y contraseña) y guarda el token como guardas el de Jellyfin.
2. `GET /me`.
   - `401` → token no válido: vuelve al login.
   - `503 api_disabled` → esconde lo de Stremfin; vuelve a probar al rato.
   - `role: "none"` o `access.can_request: false` → esconde tops, búsqueda de Stremfin y pedir; puedes enseñar `user.name` y «Pídele acceso al administrador».
   - Si no, enseña los botones de plataformas y «Mis peticiones».

### 10.2 Botones de plataformas

- `GET /platforms` una vez (o fíjalos en la app: son `all`, `netflix`, `disney`, `prime`).
- Al pulsar uno: dos pestañas (Películas / Series) y dos listas (Lo más visto / Nuevo) → `GET /top?platform=…&type=…&list=…`.
- Cada tarjeta:
  - `library.in_jellyfin` → insignia «En Jellyfin» y, al pulsar, abre la ficha de Jellyfin con `library.jellyfin_id` (si es `null`, «Recién añadida: aparecerá en unos minutos»).
  - `library.status = "partial"` → insignia «Falta la T{season}».
  - `library.downloading` → «Descargándose».
  - `request` → «Pedida» (o «Pedida por ti» si `request.mine`); `request.requesters` dice por quién.
  - Si no, botón «Pedir».
- Un filtro «Solo lo que no tengo» = `only=missing` (o filtra en la app por `library.in_jellyfin`).

### 10.3 Ficha y pedir

- Buscador: arriba lo que el cliente ya encuentra en Jellyfin y, debajo, «Para pedir»: `GET /search?q=…&only=missing`; al llegar al final de la lista, la misma llamada con `cursor=<next_cursor>` mientras no sea `null`.
- Película: `GET /movies/{id}` y, si `library.in_jellyfin` es `false`, a la vez `GET /movies/{id}/availability` ([8.6](#86-get-moviestmdb_idavailability)) para el botón: «Descarga rápida» (`fast`), «Añadir a la cola» (`ready`) o «Pedir y avisarme» (`waiting_version`). Si `can_request.action` es `notify`, «Avísame cuando esté». Si hay `release`, enseña `release.text`.
- Serie: `GET /series/{id}`. Una fila por temporada con su `status`, «Pedir la T{n}» si `can_request` y, arriba, «Pedir todo lo que falta» si `can_request_all`. Al desplegar una temporada, cada episodio con «Pedir» si su `can_request` (`POST /requests` con `season` y `episode`).
- En las dos fichas: el `trailer` (un botón que abre `trailer.url`, o el reproductor de YouTube con `trailer.key`; ya es el mejor en español que hay, no hace falta buscarlo en YouTube; para más de uno o para un tráiler fuera de la ficha, [8.25](#825-get-moviestmdb_idtrailers-y-get-seriestmdb_idtrailers)), el reparto (`cast`) y, si `providers` no está vacía, «Ya está en Netflix…» para que no se pida lo que ya se puede ver. Debajo, «Parecidas» con `GET /movies/{id}/similar` (o `/series/{id}/similar`) y, si hay `collection`, «Saga» con `GET /collections/{collection.id}`.
- Al pulsar a alguien del reparto (o al director o creador, en `crew`): su ficha con `GET /people/{id}` ([8.24](#824-get-peopleid)): foto, biografía y una rejilla con sus títulos, con las mismas insignias que cualquier lista; pestañas «Películas» / «Series» = `type`, y «Tienes 9 de 74» de `summary`. En el buscador, si `people` no está vacía, una fila de círculos con foto encima de los títulos.
- «Explorar»: los géneros de `GET /genres?type=…` (guárdalos) y, al elegir, `GET /discover` con el género, el año o la plataforma; scroll infinito con `next_cursor`.
- Al pedir: `POST /requests` y enseña `message`. Según `outcome`:
  - `started` → «Ya se está preparando» (modo directo).
  - `created` → «Enviada, te avisamos».
  - `joined` / `included` / `already` → «Ya estaba pedida».
  - `watching` → «Te avisamos cuando esté».
  - `limit` → enseña `message` tal cual.
- Antes de enseñar «Pedir» puedes mirar `access.at_limit` de `/me` y avisar sin llegar a pedir.

- En el reproductor (o en la ficha de algo que ya está en Jellyfin), «Avisar de un problema»: elige el `kind` y, si quiere, una nota → `POST /problems`.

### 10.4 Mis peticiones

- `GET /requests` (abiertas) y `GET /requests?status=closed&limit=50` (historial).
- Cada fila: póster, `display_title`, `status_label` y, si está aceptada, `progress.label` con barra (`progress.percent`), velocidad y tiempo restante (`speed`, `eta_seconds`) y, en series, «5 de 13 episodios». Con `phase: "waiting_file"`, «Esperando a que el archivo esté listo · desde hace 6 min» (`waiting_since`). Con `paused`, «En pausa».
- Al abrir una serie aceptada, `progress.episodes` da cada episodio con su barra.
- Mientras la pantalla esté a la vista, vuelve a pedir las abiertas cada 5–10 s; las cerradas no cambian.
- «Retirar» solo si `can_withdraw` → `DELETE /requests/{id}`.
- Una pestaña «De toda la casa» con `scope=all`.

### 10.5 Música

- Buscador → `GET /music/search?q=…`: arriba `artists` (círculos con foto; al pulsar, la ficha del artista) y debajo los álbumes. Pestañas o filtro «Lo que me falta» = `only=missing`; «Solo álbumes» = `kind=album`. Al final de la lista, la siguiente página con `cursor`.
- Canciones: en el buscador, la fila `songs`; «Ver todas» = `GET /music/songs?q=…`. Al pulsar una, `GET /music/songs/{id}`: un botón de escucha con `preview` y «Pedir el álbum» con `ask`. Nunca se pide una canción suelta.
- Un sencillo (`kind: "single"`): abre su ficha y, si trae `album_instead`, ofrece ese álbum («Esta canción está en el álbum …») en vez del sencillo.
- Artista → `GET /music/artists/{id}?kind=all`: «Tienes {summary.albums.have} de {summary.albums.total} álbumes», pestañas «Álbumes · EP · Sencillos» con los totales de `summary.albums`, `summary.eps` y `summary.singles` (filtra `items` por su `kind` en la app, o pide cada pestaña con `kind=album|ep|single`), «Populares» con `top_songs` y «Artistas parecidos» con `related`.
- Álbum → `GET /music/albums/{id}`: portada, datos y canciones con una marca en las que ya tienes (`in_jellyfin`, y debajo «En {in_album}» si es otro álbum).
- Novedades → `GET /music/new`.
- Portada de música: pestañas con `GET /music/charts` («Top España», «Latino», «Pop»…) y, al elegir una, `GET /music/charts/{id}`. En una lista de canciones, cada fila: puesto, portada, título, artista, un botón de escucha (`preview`) y, al pulsar, **la ficha de su álbum** (`album.deezer_id`), no la canción. Las insignias («Ya lo tienes», «Pedido», «Descargando 40 %») salen de `album`.
- «De tus artistas» → `GET /music/releases` (con una etiqueta «Próximamente» si `upcoming`). «Lo más pedido en casa» → `GET /music/requested`.
- Cada álbum: `library.in_jellyfin` → «En Jellyfin»; `library.song_in_album` → «Ya la tienes en {álbum}»; `download` → su `label` con barra si hay `percent`; `request` → «Pedido» (o «Pedido por ti»).
- «Pedir» si `can_request` → `POST /requests` con `deezer_id`.
- En «Mis peticiones», un álbum aceptado enseña `progress.label` y, en `downloading`, la barra con `progress.percent`. Vuelve a pedirlas cada 5–10 s mientras se vean.

### 10.6 Avisos

La API no empuja nada: la app pregunta. Quien tiene Telegram ya recibe los avisos allí; para el resto (y para avisar también en el móvil):

- Cada 15–30 minutos (WorkManager, con red), `GET /requests?scope=mine&status=all&since=<último now>`.
- Quita de tu lista las de `removed_ids`.
- Para cada petición devuelta, compara con lo que tenías guardado:
  - pasa a `approved` → «Te han aceptado {display_title}» (o, si `direct`, nada: ya lo sabía).
  - pasa a `rejected` → «No se ha aceptado {display_title}: {reason_label}» (o, si `cancelled`, «Se ha cancelado {display_title}»).
  - pasa a `completed` → «{display_title} ya está en Jellyfin» (al pulsar, busca el título y ábrelo).
- Guarda el `now` de la respuesta para la siguiente vez.
- Ese sondeo cuesta una llamada; no bajes de 5 minutos.

### 10.7 Abrir algo en Jellyfin

`library.jellyfin_id` es el `Id` del elemento en **el mismo** Jellyfin en el que ha entrado la app: úsalo con el SDK (`/Users/{userId}/Items/{id}`, o la pantalla de detalle del cliente). Para una serie es el id de la serie; para ir a un episodio, navega desde ahí.

---

## 11. Ejemplo en Kotlin (Retrofit + kotlinx.serialization)

Orientativo: adáptalo a la arquitectura del cliente. Los nombres de campo van en `snake_case` (`@SerialName`) y el `Json` ignora lo desconocido para que los campos nuevos de la API no rompan nada.

```kotlin
// build.gradle: retrofit2, okhttp3, kotlinx-serialization-json, retrofit2-kotlinx-serialization-converter

val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

class StremfinAuth(private val token: () -> String?) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val t = token() ?: return chain.proceed(chain.request())
        return chain.proceed(
            chain.request().newBuilder()
                .header("Authorization", "Bearer $t")
                .header("Accept", "application/json")
                .build()
        )
    }
}

fun stremfinApi(token: () -> String?): StremfinApi = Retrofit.Builder()
    .baseUrl("https://stremfin.ejemplo.com/api/v1/")
    .client(OkHttpClient.Builder().addInterceptor(StremfinAuth(token)).build())
    .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
    .build()
    .create(StremfinApi::class.java)

interface StremfinApi {
    @GET("me") suspend fun me(): Me
    @GET("platforms") suspend fun platforms(): Platforms
    @GET("top") suspend fun top(
        @Query("platform") platform: String,
        @Query("type") type: String,               // "movie" | "series"
        @Query("list") list: String = "popular",  // "popular" | "new"
        @Query("only") only: String? = null,      // "missing" | "available"
        @Query("limit") limit: Int? = null,
    ): TopList
    @GET("search") suspend fun search(
        @Query("q") q: String,
        @Query("type") type: String? = null,      // "movie" | "series"
        @Query("only") only: String? = null,      // "missing" | "available"
        @Query("cursor") cursor: String? = null,  // next_cursor de la anterior
        @Query("limit") limit: Int? = null,
    ): SearchResult
    @GET("movies/{id}") suspend fun movie(@Path("id") tmdbId: Int): MovieDetail
    @GET("movies/{id}/availability") suspend fun availability(@Path("id") tmdbId: Int): Availability
    @GET("series/{id}") suspend fun series(@Path("id") tmdbId: Int): SeriesDetail
    @GET("music/search") suspend fun musicSearch(
        @Query("q") q: String,
        @Query("only") only: String? = null,      // "missing" | "available"
        @Query("kind") kind: String? = null,      // "album" | "ep" | "single"
        @Query("cursor") cursor: String? = null,
    ): MusicSearch
    @GET("music/songs") suspend fun musicSongs(@Query("q") q: String, @Query("cursor") cursor: String? = null, @Query("limit") limit: Int? = null): SongList
    @GET("music/songs/{id}") suspend fun musicSong(@Path("id") deezerId: String): SongPage
    @GET("music/new") suspend fun musicNew(): AlbumList
    @GET("music/charts") suspend fun musicCharts(): ChartList
    // kind "albums": items son Album; kind "songs": items son ChartSong. Decodifica según `kind`.
    @GET("music/charts/{id}") suspend fun musicChartSongs(@Path("id") id: String, @Query("only") only: String? = null, @Query("limit") limit: Int? = null): ChartSongs
    @GET("music/charts/{id}") suspend fun musicChartAlbums(@Path("id") id: String, @Query("only") only: String? = null, @Query("limit") limit: Int? = null): AlbumList
    @GET("music/releases") suspend fun musicReleases(@Query("days") days: Int? = null, @Query("only") only: String? = null): AlbumList   // Album.upcoming
    @GET("music/requested") suspend fun musicRequested(@Query("days") days: Int? = null, @Query("limit") limit: Int? = null): AlbumList  // Album.people
    @GET("music/artists") suspend fun musicArtists(@Query("q") q: String): ArtistList
    @GET("music/artists/{id}") suspend fun musicArtist(@Path("id") deezerId: String, @Query("kind") kind: String? = null, @Query("only") only: String? = null): ArtistPage
    @GET("music/albums/{id}") suspend fun musicAlbum(@Path("id") deezerId: String): AlbumPage
    @GET("requests") suspend fun requests(
        @Query("scope") scope: String = "mine",
        @Query("status") status: String = "open",
        @Query("since") since: String? = null,
        @Query("limit") limit: Int? = null,
    ): RequestList
    @GET("requests/{id}") suspend fun request(@Path("id") id: Int): MediaRequest
    @POST("requests") suspend fun ask(@Body body: AskBody): retrofit2.Response<AskResult>
    @DELETE("requests/{id}") suspend fun withdraw(@Path("id") id: Int): retrofit2.Response<AskResult>

    // Descubrir (1.77.0), personas (1.82.0) y tráilers (1.83.0)
    @GET("movies/{id}/trailers") suspend fun movieTrailers(@Path("id") tmdbId: Int): Trailers
    @GET("series/{id}/trailers") suspend fun seriesTrailers(@Path("id") tmdbId: Int): Trailers
    @GET("movies/{id}/similar") suspend fun similarMovies(@Path("id") tmdbId: Int, @Query("only") only: String? = null): TitleList
    @GET("series/{id}/similar") suspend fun similarSeries(@Path("id") tmdbId: Int, @Query("only") only: String? = null): TitleList
    @GET("collections/{id}") suspend fun collection(@Path("id") id: Int): Saga
    @GET("people/{id}") suspend fun person(
        @Path("id") id: Int,
        @Query("type") type: String? = null,       // "movie" | "series"
        @Query("credit") credit: String? = null,   // "cast" | "crew"
        @Query("sort") sort: String? = null,       // "popular" | "new"
        @Query("only") only: String? = null,
        @Query("cursor") cursor: String? = null,
        @Query("limit") limit: Int? = null,
    ): Person
    @GET("genres") suspend fun genres(@Query("type") type: String): Genres
    @GET("discover") suspend fun discover(
        @Query("type") type: String,               // "movie" | "series"
        @Query("genre") genre: Int? = null,
        @Query("year") year: Int? = null,
        @Query("platform") platform: String? = null,
        @Query("sort") sort: String? = null,       // "popular" | "new" | "rating"
        @Query("only") only: String? = null,
        @Query("cursor") cursor: String? = null,
    ): SearchResult

    // Próximamente, avisos y problemas (1.78.0)
    @GET("upcoming") suspend fun upcoming(): Upcoming
    @GET("notifications") suspend fun notifications(@Query("since") since: String? = null): Notices
    @GET("problems") suspend fun problems(@Query("status") status: String? = null): ProblemList
    @POST("problems") suspend fun reportProblem(@Body body: ProblemBody): retrofit2.Response<ProblemResult>
}

@Serializable data class Me(val user: MeUser, val access: Access, val features: Features)
@Serializable data class MeUser(
    @SerialName("jellyfin_id") val jellyfinId: String,
    val name: String,
    val role: String,                          // "admin" | "member" | "none"
)
@Serializable data class Access(
    @SerialName("can_request") val canRequest: Boolean,
    val mode: String? = null,                  // "admin" | "direct" | "review"
    val telegram: Boolean = false,
    @SerialName("at_limit") val atLimit: Boolean = false,
    @SerialName("daily_left") val dailyLeft: Int? = null,
)
@Serializable data class Features(val music: Boolean = false)

// Música: canciones (1.84.0). MusicSong es la canción de 7.7 (la `Song` de más abajo es la pista de un álbum, 8.12).
@Serializable data class AlbumRef(@SerialName("deezer_id") val deezerId: String, val title: String, val cover: String? = null)
@Serializable data class MusicSong(
    @SerialName("deezer_id") val deezerId: String,
    val title: String, val artist: String,
    @SerialName("artist_deezer_id") val artistDeezerId: String? = null,
    val duration: Int? = null,
    val preview: String? = null,               // 30 s en MP3; caduca
    val explicit: Boolean = false,
    val album: AlbumRef? = null,
    @SerialName("in_jellyfin") val inJellyfin: Boolean = false,
    @SerialName("in_album") val inAlbum: String? = null,
)
@Serializable data class SongList(val items: List<MusicSong>, @SerialName("next_cursor") val nextCursor: String? = null)
@Serializable data class SongPage(
    @SerialName("deezer_id") val deezerId: String,
    val title: String, val artist: String,
    @SerialName("artist_deezer_id") val artistDeezerId: String? = null,
    val duration: Int? = null, val explicit: Boolean = false,
    val preview: String? = null,
    @SerialName("in_jellyfin") val inJellyfin: Boolean = false,
    @SerialName("in_album") val inAlbum: String? = null,
    val position: Int? = null, val disc: Int? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    val album: Album? = null,                                          // el disco entero (7.6)
    @SerialName("album_instead") val albumInstead: Album? = null,     // el álbum que pedir si `album` es un sencillo
    val ask: String? = null,                                           // deezer_id para POST /requests
)
// Listas (1.85.0)
@Serializable data class ChartList(val country: String, val charts: List<Chart>)
@Serializable data class Chart(val id: String, val name: String, val kind: String, val measure: String, val genre: String? = null)   // kind: songs | albums; measure: played | sold
@Serializable data class ChartSongs(val id: String, val name: String, val kind: String, val measure: String, val genre: String? = null, val items: List<ChartSong>)
@Serializable data class ChartSong(
    val rank: Int, val title: String, val artist: String,
    val cover: String? = null, val preview: String? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("in_jellyfin") val inJellyfin: Boolean = false,
    @SerialName("in_album") val inAlbum: String? = null,
    val album: Album? = null,                  // el disco que pedir; null = no está en Deezer
)
@Serializable data class InsteadOf(@SerialName("deezer_id") val deezerId: String, val title: String, val kind: String)

@Serializable data class TopList(val items: List<Title>, val source: String? = null)
@Serializable data class SearchResult(
    val items: List<Title>,
    val people: List<PersonRef> = emptyList(),   // solo con los primeros resultados (1.82.0)
    @SerialName("next_cursor") val nextCursor: String? = null,
)
@Serializable data class Availability(
    val status: String,                        // ready | waiting_version | downloading | have | unavailable
    val reason: String? = null,                // not_released | quality | no_links
    val downloadable: Boolean = false,
    val cached: Boolean? = null,
    val fast: Boolean = false,
    val version: Version? = null,
    val criterion: String? = null,
    @SerialName("on_request") val onRequest: String,   // "download" | "review"
)
@Serializable data class Version(
    val resolution: String? = null,
    val language: String? = null,
    val size: Long? = null,
    val summary: String,
)
@Serializable data class Title(
    val type: String,                          // "movie" | "series"
    @SerialName("tmdb_id") val tmdbId: Int,
    val title: String,
    val year: Int? = null,
    val poster: String? = null,
    val rank: Int? = null,
    val season: Int? = null,
    // Edad mínima recomendada (1.81.0 en todos los títulos). null = sin calificación.
    val age: Int? = null,
    @SerialName("age_rating") val ageRating: AgeRating? = null,
    // Solo en la ficha de una persona (/people/{id}): lo que hizo en este título.
    val acted: Boolean? = null,
    val character: String? = null,
    val jobs: List<String> = emptyList(),      // director | writer | creator
    val released: Boolean? = null,             // solo en una saga
    val upcoming: String? = null,              // solo en /upcoming: dated | released_waiting | undated
    val date: String? = null,
    val library: Library,
    val request: RequestRef? = null,
)
@Serializable data class AgeRating(val label: String, val country: String)   // "12", "ES"

// Lo que añaden las fichas (MovieDetail y SeriesDetail llevan además estos campos)
@Serializable data class Trailer(
    val name: String, val key: String, val url: String,
    val type: String = "trailer",              // "trailer" | "teaser"
    val language: String? = null,              // "es", "en"…
    val country: String? = null,               // "ES", "MX", "US"…
    val subtitled: Boolean = false,            // versión original con subtítulos
    val official: Boolean = false,
    @SerialName("published_at") val publishedAt: String? = null,
) {
    val dubbedInSpanish get() = language == "es" && !subtitled
}
@Serializable data class Trailers(val trailer: Trailer? = null, val items: List<Trailer> = emptyList())
@Serializable data class CastMember(val id: Int? = null, val name: String, val character: String? = null, val photo: String? = null)
@Serializable data class CrewMember(val id: Int, val name: String, val job: String, val photo: String? = null)   // job: director | creator

// Personas: en la búsqueda (SearchResult.people) y su ficha
@Serializable data class PersonRef(
    val id: Int, val name: String, val photo: String? = null, val department: String? = null,
    @SerialName("known_for") val knownFor: List<String> = emptyList(),
)
@Serializable data class Person(
    val id: Int, val name: String, val photo: String? = null, val department: String? = null,
    val biography: String? = null,
    @SerialName("biography_language") val biographyLanguage: String? = null,
    val birthday: String? = null, val deathday: String? = null, val birthplace: String? = null,
    val summary: PersonSummary,
    val items: List<Title>,
    @SerialName("next_cursor") val nextCursor: String? = null,
)
@Serializable data class PersonSummary(
    val total: Int, val have: Int, val movies: Int,
    @SerialName("movies_have") val moviesHave: Int,
    val series: Int,
    @SerialName("series_have") val seriesHave: Int,
)
@Serializable data class Provider(val name: String, val logo: String? = null, val key: String? = null)   // key: netflix | disney | prime
@Serializable data class CollectionRef(val id: Int, val name: String)

@Serializable data class TitleList(val items: List<Title>)
@Serializable data class Saga(val id: Int, val name: String, val summary: SagaSummary, val items: List<Title>)
@Serializable data class SagaSummary(val total: Int, val have: Int, val downloading: Int, val missing: Int, val upcoming: Int)
@Serializable data class Genres(val genres: List<Genre>)
@Serializable data class Genre(val id: Int, val name: String)

@Serializable data class Upcoming(val movies: List<Title>, val episodes: List<UpcomingEpisode>)
@Serializable data class UpcomingEpisode(
    @SerialName("tmdb_id") val tmdbId: Int? = null,
    val title: String,
    val poster: String? = null,
    val season: Int,
    val episode: Int,
    @SerialName("episode_title") val episodeTitle: String? = null,
    val date: String,
)

@Serializable data class Notices(val now: String, val items: List<Notice>)
@Serializable data class Notice(
    val id: Int,
    val kind: String,                          // approved | started | rejected | waiting | progress | available | problem_fixed
    val message: String,
    @SerialName("request_id") val requestId: Int? = null,
    @SerialName("problem_id") val problemId: Int? = null,
    @SerialName("created_at") val createdAt: String,
)

@Serializable data class ProblemBody(
    val type: String,                          // "movie" | "series"
    @SerialName("tmdb_id") val tmdbId: Int,
    val kind: String,                          // language | quality | playback | subtitles | missing | other
    val season: Int? = null,
    val episode: Int? = null,
    val note: String? = null,
)
@Serializable data class ProblemResult(val outcome: String, val message: String, val problem: Problem? = null)   // created | already | not_in_jellyfin | limit
@Serializable data class ProblemList(val items: List<Problem>)
@Serializable data class Problem(
    val id: Int,
    val title: String,
    val kind: String,
    @SerialName("kind_label") val kindLabel: String,
    val status: String,                        // open | fixed
    val season: Int? = null,
    val episode: Int? = null,
    val note: String? = null,
)
@Serializable data class Library(
    val status: String,                        // available | partial | downloading | missing
    @SerialName("in_jellyfin") val inJellyfin: Boolean,
    @SerialName("jellyfin_id") val jellyfinId: String? = null,
    val downloading: Boolean = false,
)
@Serializable data class RequestRef(
    val id: Int,
    val status: String,
    @SerialName("status_label") val statusLabel: String,
    val mine: Boolean,
    val season: Int? = null,
    val episode: Int? = null,                  // petición de un episodio suelto (1.79.0)
    val requesters: List<String> = emptyList(),
)

@Serializable data class AskBody(
    val type: String,
    @SerialName("tmdb_id") val tmdbId: Int? = null,
    @SerialName("deezer_id") val deezerId: String? = null,
    val season: Int? = null,
    val episode: Int? = null,                  // con season: un episodio suelto
    @SerialName("as_single") val asSingle: Boolean? = null,   // música: el sencillo tal cual aunque su canción esté en un álbum
)
@Serializable data class AskResult(
    val outcome: String,                       // created | started | joined | watching | included | already | have | busy | unavailable | limit
    val message: String,
    val limit: String? = null,                 // con outcome "limit": "pending" | "daily"
    @SerialName("instead_of") val insteadOf: InsteadOf? = null,   // música: el sencillo, si se pidió su álbum
    val request: MediaRequest? = null,
)

@Serializable data class RequestList(
    val now: String,
    val items: List<MediaRequest>,
    @SerialName("removed_ids") val removedIds: List<Int> = emptyList(),
)
@Serializable data class MediaRequest(
    val id: Int,
    val type: String,
    @SerialName("display_title") val displayTitle: String,
    val poster: String? = null,
    val status: String,
    @SerialName("status_label") val statusLabel: String,
    val cancelled: Boolean = false,            // rejected tras haber sido aceptada: «Cancelada» (1.88.0)
    @SerialName("reason_label") val reasonLabel: String? = null,
    val direct: Boolean = false,
    val mine: Boolean = false,
    @SerialName("can_withdraw") val canWithdraw: Boolean = false,
    val progress: Progress? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
)
@Serializable data class Progress(
    val state: String,
    val label: String,
    val phase: String? = null,                 // queued | preparing | waiting_file | downloading | verifying | moving | attention
    val percent: Double? = null,
    @SerialName("downloaded_bytes") val downloadedBytes: Long? = null,
    @SerialName("total_bytes") val totalBytes: Long? = null,
    val speed: Long? = null,                   // bytes/s
    @SerialName("eta_seconds") val etaSeconds: Long? = null,
    @SerialName("waiting_since") val waitingSince: String? = null,
    val paused: Boolean = false,
    val recheck: Recheck? = null,              // 1.90.1: en revisión, pero Stremfin lo sigue intentando solo
    @SerialName("episodes_done") val episodesDone: Int? = null,
    @SerialName("episodes_total") val episodesTotal: Int? = null,
    val episodes: List<EpisodeProgress> = emptyList(),
)
@Serializable data class Recheck(
    val until: String,
    @SerialName("next_at") val nextAt: String,
    @SerialName("every_hours") val everyHours: Int,
    val text: String,
)
@Serializable data class EpisodeProgress(
    val season: Int,
    val episode: Int,
    @SerialName("episode_end") val episodeEnd: Int? = null,
    val phase: String,
    val label: String,
    val percent: Double? = null,
    val speed: Long? = null,
    @SerialName("eta_seconds") val etaSeconds: Long? = null,
    val recheck: Recheck? = null,              // 1.90.1: ese episodio se sigue intentando solo
)

@Serializable data class MusicSearch(
    val artists: List<Artist> = emptyList(),
    val songs: List<MusicSong> = emptyList(),  // solo en la primera página (1.84.0)
    val items: List<Album>,
    @SerialName("next_cursor") val nextCursor: String? = null,
)
@Serializable data class AlbumList(val items: List<Album>)
@Serializable data class ArtistList(val items: List<Artist>)
@Serializable data class Artist(
    @SerialName("deezer_id") val deezerId: String,
    val name: String,
    val picture: String? = null,
    val albums: Int = 0,
    val fans: Int? = null,                     // en la ficha y en related
)
@Serializable data class ArtistPage(
    val artist: Artist, val summary: Summary, val items: List<Album>,
    @SerialName("top_songs") val topSongs: List<MusicSong> = emptyList(),
    val related: List<Artist> = emptyList(),
)
@Serializable data class Summary(
    val total: Int, val have: Int, val missing: Int,
    val albums: KindCount? = null, val eps: KindCount? = null, val singles: KindCount? = null,   // solo con kind distinto de "album"
)
@Serializable data class KindCount(val total: Int, val have: Int)
@Serializable data class Album(
    @SerialName("deezer_id") val deezerId: String? = null,
    val title: String,
    val artist: String,
    val cover: String? = null,
    val kind: String,                          // album | ep | single
    val tracks: Int? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    val library: AlbumLibrary,
    val download: MusicDownload? = null,
    val request: RequestRef? = null,
    @SerialName("can_request") val canRequest: Boolean = false,
    val rank: Int? = null,                     // su puesto en una lista
    val contains: String? = null,              // la canción buscada (o de la lista) que lleva
    val upcoming: Boolean? = null,             // solo en /music/releases
    val people: Int? = null,                   // solo en /music/requested
)
@Serializable data class AlbumLibrary(
    @SerialName("in_jellyfin") val inJellyfin: Boolean,
    @SerialName("song_in_album") val songInAlbum: String? = null,
)
@Serializable data class MusicDownload(
    val phase: String,                         // sent | queued | downloading | importing | failed
    val label: String,
    val percent: Int? = null,
    @SerialName("track_errors") val trackErrors: Boolean = false,
)
@Serializable data class AlbumPage(
    @SerialName("deezer_id") val deezerId: String,
    val title: String,
    val artist: String,
    val cover: String? = null,
    @SerialName("artist_deezer_id") val artistDeezerId: String? = null,
    val library: AlbumLibrary,
    val download: MusicDownload? = null,
    val request: RequestRef? = null,
    @SerialName("can_request") val canRequest: Boolean = false,
    @SerialName("songs_have") val songsHave: Int = 0,
    val songs: List<Song> = emptyList(),
    @SerialName("album_instead") val albumInstead: Album? = null,   // sencillo cuya canción está en un álbum
)
@Serializable data class Song(
    val position: Int,
    val title: String,
    val duration: Int? = null,
    @SerialName("in_jellyfin") val inJellyfin: Boolean = false,
    @SerialName("in_album") val inAlbum: String? = null,
)

// MovieDetail, SeriesDetail, Platforms: los campos de las secciones 7 y 8.
```

Errores: `POST /requests` (409/422/429) y `POST /problems` (422/429) pueden devolver un cuerpo con `outcome` válido (no es un fallo): lee el cuerpo de error y, si trae `outcome`, trátalo como resultado; si trae `error`, como error. Para el resto de direcciones, el cuerpo de error es siempre `{"error": {"code", "message"}}`:

```kotlin
suspend fun ask(body: AskBody): Result<AskResult> {
    val r = api.ask(body)
    val text = if (r.isSuccessful) null else r.errorBody()?.string()
    return when {
        r.isSuccessful -> Result.success(r.body()!!)
        text != null && "\"outcome\"" in text -> Result.success(json.decodeFromString<AskResult>(text))
        else -> Result.failure(StremfinException(
            text?.let { runCatching { json.decodeFromString<ApiError>(it).error.code }.getOrNull() } ?: "http_${r.code()}",
            text?.let { runCatching { json.decodeFromString<ApiError>(it).error.message }.getOrNull() } ?: "Error de conexión",
        ))
    }
}
```

Para el resto:

```kotlin
@Serializable data class ApiError(val error: ErrorBody)
@Serializable data class ErrorBody(val code: String, val message: String)

suspend fun <T> stremfin(call: suspend () -> T): Result<T> = try {
    Result.success(call())
} catch (e: HttpException) {
    val body = e.response()?.errorBody()?.string()
    val err = body?.let { runCatching { json.decodeFromString<ApiError>(it).error }.getOrNull() }
    when (err?.code) {
        "unauthenticated", "invalid_token" -> { /* volver al login de Jellyfin */ }
        "jellyfin_unavailable", "api_disabled", "source_unavailable", "server_error" -> { /* reintentar más tarde */ }
    }
    Result.failure(StremfinException(err?.code ?: "http_${e.code()}", err?.message ?: "Error de conexión"))
}
```

---

## 12. Probar sin servidor real

El repositorio de Stremfin trae un servidor falso con Jellyfin, TMDB y lo demás (`tests/Fakes/server`). Con el panel arrancado en local contra él (`README` del repositorio) y la API encendida:

- Jellyfin: `http://127.0.0.1:8765/jellyfin` con la clave `jf-test-key` (en *Ajustes → Jellyfin*).
- Tokens de app que el Jellyfin falso acepta en `/Users/Me`: **`jf-user-1`** (usuario `admin`) y **`jf-user-2`** (usuario `mama`).
- En la página *Usuarios* del panel, elige «Tú» en `admin` y un modo de peticiones en `mama`.
- Música: el panel arrancado con `STREMFIN_DEEZER_URL=http://127.0.0.1:8765/deezer` y, en *Ajustes → Música*, el servicio de descarga en `http://127.0.0.1:8765/musicdl`. El Deezer falso tiene un artista, «Los Picos» (id `27`), con doce discos («Montaña 1»…, ids `701`–`712`); un álbum pedido pasa 10 s en cola, 30 s descargando y luego se queda en `importing` (el falso no deja archivos que importar).

```bash
TOKEN=jf-user-2   # el token de prueba de «mama» en el Jellyfin falso
AUTH="Authorization: Bearer $TOKEN"
curl -s -H "$AUTH" http://localhost:8000/api/v1/me
curl -s -H "$AUTH" "http://localhost:8000/api/v1/top?platform=netflix&type=movie"
curl -s -H "$AUTH" "http://localhost:8000/api/v1/search?q=the&only=missing"
curl -s -H "$AUTH" http://localhost:8000/api/v1/movies/920/availability
curl -s -G -H "$AUTH" --data-urlencode "q=los picos" "http://localhost:8000/api/v1/music/search?only=missing"
curl -s -H "$AUTH" http://localhost:8000/api/v1/music/artists/27?kind=all
curl -s -G -H "$AUTH" --data-urlencode "q=montaña" http://localhost:8000/api/v1/music/songs
curl -s -H "$AUTH" http://localhost:8000/api/v1/music/charts
curl -s -H "$AUTH" http://localhost:8000/api/v1/music/releases
curl -s -H "$AUTH" http://localhost:8000/api/v1/music/requested
curl -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
     -d '{"type":"movie","tmdb_id":920}' http://localhost:8000/api/v1/requests

# Descubrir, Próximamente, avisos y problemas
curl -s -H "$AUTH" http://localhost:8000/api/v1/movies/920/similar
curl -s -H "$AUTH" http://localhost:8000/api/v1/movies/920/trailers
curl -s -H "$AUTH" http://localhost:8000/api/v1/people/1
curl -s -H "$AUTH" "http://localhost:8000/api/v1/genres?type=movie"
curl -s -H "$AUTH" "http://localhost:8000/api/v1/discover?type=movie&sort=new"
curl -s -H "$AUTH" http://localhost:8000/api/v1/upcoming
curl -s -H "$AUTH" http://localhost:8000/api/v1/notifications
curl -s -X POST -H "$AUTH" -H "Content-Type: application/json" \
     -d '{"type":"movie","tmdb_id":920,"kind":"language","note":"Se oye en inglés"}' http://localhost:8000/api/v1/problems

# Desde una web (CORS): con su origen en Ajustes → Acceso desde fuera
curl -i -X OPTIONS http://localhost:8000/api/v1/requests -H "Origin: https://tv.ejemplo.com" -H "Access-Control-Request-Method: POST"
```

El servidor falso no tiene las listas de Apple: `/music/charts/{id}` las lee de Apple de verdad (hace falta Internet; sin ella, `503 source_unavailable`). Tampoco tiene canciones de Deezer: `/music/songs` y `songs` vienen vacíos, y `top_songs` y `related` de un artista también. Tampoco tiene todo lo de TMDB (parecidos, géneros, explorar, tráiler o calificaciones pueden venir vacíos o dar `503 source_unavailable`): para eso, prueba contra un Stremfin real.

---

## 13. Seguridad: lo que la app debe cuidar

- **Solo HTTPS** hacia `https://stremfin.ejemplo.com/api/v1` desde fuera de casa. Nada de aceptar certificados no válidos.
- El token es el de la sesión de Jellyfin: guárdalo donde guardes ese (almacenamiento cifrado de Android) y **nunca** lo escribas en logs, analíticas ni informes de fallos.
- No hace falta ninguna clave de Stremfin dentro de la APK: no la pongas.
- Ante `401`, vuelve al login de Jellyfin; no reintentes con el mismo token.
- Respeta `Retry-After` en los `429`.
- La API no da enlaces de descarga ni datos del servidor; si algún día ves algo así en una respuesta, es un fallo: avisa al administrador.
- Desde un navegador, la API solo responde a las webs que el administrador haya puesto en *Ajustes → Acceso desde fuera* (CORS, ver [2](#2-lo-básico)); a cualquier otra página no le da permiso. Las apps nativas no lo necesitan.
- Una versión web de la app guarda el token en el navegador: mejor en memoria o `sessionStorage` que en `localStorage`, y nunca en la URL.

---

## 14. Historial de la API

| Stremfin | API | Cambios |
|---|---|---|
| 1.67.1 | v1 | Primera versión: `/me`, plataformas y tops, búsqueda, fichas de película y serie, música, peticiones (ver, pedir, retirar). |
| 1.68.0 | v1 | Tras la auditoría. **Nuevo**: `removed_ids` en `/requests` con `since`; `outcome: "watching"`; `limit` (`pending`/`daily`) y `Retry-After` en el `429` de pedir; `can_request.action` en la ficha de película; errores `server_error` (500) y `jellyfin_not_configured`; límite de 30/min para búsquedas y fichas de serie. **Cambia**: un token ya comprobado no se frena por los fallos de otros; `since` acepta cualquier zona horaria; `updated_at` cambia al apuntarse o quitarse alguien y ya no cambia por la revisión diaria; la ficha de película busca también por IMDb; `rank`, `season` y `season_episodes` vienen siempre; `rating` y `date` en las fichas; `daily_limit` es `null` para el administrador; las etiquetas de descarga no nombran servicios; `request` de una tarjeta con temporada es la que la cubre; `seasons[].can_request` también con peticiones ya aceptadas de otros; música: `can_request` es `false` si ya lo pediste. |
| 1.69.0 | v1 | **Nuevo**: `GET /movies/{id}/availability` (si se puede descargar ya, si será rápida y qué versión sería); en `/search`, `only` (`missing`/`available`), `limit` y `cursor` con `next_cursor` para los siguientes; en `progress` y en `download` de la ficha: `phase`, `downloaded_bytes`, `total_bytes`, `speed`, `eta_seconds`, `waiting_since` y `paused`; en series, `percent` y `episodes` (cada episodio con su avance). **Cambia**: `percent` de una película vale 100 al comprobar y colocar; la etiqueta de esperar al servicio de descargas es «Esperando a que el archivo esté listo» (antes «Preparando»). |
| 1.70.0 | v1 | **Nuevo**: `GET /music/artists` (buscar artistas), `GET /music/artists/{id}` (un artista con sus discos y `summary`), `GET /music/albums/{id}` (un álbum con sus canciones y cuáles tienes); en `/music/search`, `only`, `kind`, `limit`, `cursor`/`next_cursor` y `artists`; `download` en cada álbum (de camino a Jellyfin: `sent`, `queued`, `downloading`, `importing`, `failed`); `progress` de las peticiones de música con `phase`, `percent`, `track_errors` y `sent_at`, y el estado nuevo `importing`. **Cambia**: `kind` de un álbum es `album`, `ep` o `single` (los recopilatorios cuentan como `album`); la búsqueda de música da más resultados (por páginas). |
| 1.75.0 | v1 | Sin cambios en las llamadas. En el panel, la API se enciende ahora en *Ajustes → Acceso desde fuera* (antes *Ajustes → API*) y el mensaje de `api_disabled` lo dice así; la dirección de la API sale de la «Dirección del panel» de esa misma página. |
| 1.76.0 | v1 | **Nuevo**: `age` (edad mínima recomendada, en años) y `age_rating` (`label`, `country`) en cada resultado de `/search` y en `/movies/{id}`; solo información, no se filtra nada. **Cambia**: límites más altos, 300 llamadas por minuto, 120 búsquedas (con su propia cuenta) y 60 de las que más cuestan. |
| 1.77.0 | v1 | **Nuevo**: en la ficha de película `trailer`, `cast`, `directors`, `providers` y `collection`; en la de serie `trailer`, `cast`, `creators` y `providers`. `GET /movies/{id}/similar` y `/series/{id}/similar` (parecidos), `GET /collections/{id}` (sagas), `GET /genres` y `GET /discover` (explorar por género, año y plataforma). `ETag` en cada `GET` y `304` con `If-None-Match`. |
| 1.78.0 | v1 | **Nuevo**: `GET /upcoming` (Próximamente: películas esperadas y próximos episodios de las series seguidas), `GET /notifications` (lo que pasa con tus peticiones y avisos, para notificaciones en el móvil) y `GET`/`POST /problems` (avisar de un problema con algo de Jellyfin). |
| 1.79.0 | v1 | **Nuevo**: pedir un episodio suelto (`POST /requests` con `season` y `episode`); `episode` en las peticiones (7.4 y 7.5); en la ficha de serie, `request` y `can_request` de cada episodio. |
| 1.79.1 | v1 | Tras la segunda auditoría. **Cambia**: pedir, retirar y avisar tienen su límite (30 por minuto); pedir y avisar van de uno en uno (si coincide con otra, `503 busy`: reintenta); texto que no es UTF-8, cursores inventados e ids enormes dan `422 invalid`; el administrador ya no recibe aviso de lo que acaba de pedir. Una sesión que ya funcionó no se queda fuera aunque alguien mande tokens falsos. |
| 1.80.0 | v1 | **Nuevo**: CORS para las webs permitidas en *Ajustes → Acceso desde fuera* (origen exacto, consulta previa `OPTIONS` sin token, cabeceras también en los errores, `Retry-After` legible). Sin cambios para las apps nativas. |
| 1.80.1 | v1 | Solo el documento: `503 busy` y el límite de 30 por minuto en la tabla de errores; la nota de seguridad sobre CORS, al día. |
| 1.81.0 | v1 | **Nuevo**: `age` y `age_rating` en todos los títulos: `/top`, `/discover`, los parecidos, `/collections/{id}`, las películas de `/upcoming` y la ficha `/series/{id}` (antes solo en `/search` y `/movies/{id}`). Siempre presentes, `null` si no hay calificación. Sigue siendo solo información: Stremfin no oculta nada por edad. |
| 1.81.1 | v1 | Solo el documento: el ejemplo en Kotlin (sección 11) y los comandos de prueba (sección 12) incluyen lo añadido desde la 1.76 (edad, descubrir, Próximamente, avisos, problemas, episodio suelto, CORS). |
| 1.82.0 | v1 | **Nuevo**: `GET /people/{id}` (la ficha de una persona: quién es y sus películas y series, con cuáles tienes y lo que hizo en cada una); `people` en `/search` (las personas que coinciden, con los primeros resultados); `id` en cada persona de `cast` y la lista `crew` (director o creador con `id` y foto) en las dos fichas. Nada de lo anterior cambia: `directors`, `creators` e `items` siguen igual. |
| 1.83.0 | v1 | **Nuevo**: `GET /movies/{id}/trailers` y `GET /series/{id}/trailers` (todos los tráilers de un título, el mejor primero); cada tráiler lleva además `type`, `country`, `subtitled`, `official` y `published_at`. **Cambia**: qué tráiler es el primero (también el `trailer` de las fichas): el doblado al español de España antes que el de otro país, este antes que el subtitulado, y cualquiera en español (aunque sea un teaser) antes que uno en inglés. |
| 1.84.0 | v1 | **Nuevo**: canciones: `songs` en `/music/search`, `GET /music/songs` (buscar canciones) y `GET /music/songs/{id}` (una canción, su disco y el álbum que pedir), cada una con `preview` (30 s para escuchar); en la ficha de artista, `top_songs`, `related`, `kind=ep` y `kind=single` y el desglose por tipo en `summary`; `album_instead` en la ficha de un sencillo; `as_single` e `instead_of` en `POST /requests`. **Cambia**: pedir un sencillo cuya canción está en un álbum pide el álbum entero (antes pedía el sencillo). |
| 1.85.0 | v1 | **Nuevo**: listas de éxitos de Apple para España: `GET /music/charts` (las que hay) y `GET /music/charts/{id}` (lo más escuchado en canciones y álbumes, y lo más comprado por género; cada canción con el disco que pedir); `GET /music/releases` (los discos de los artistas que sigue la casa, con `upcoming` para lo anunciado); `GET /music/requested` (lo más pedido en casa, con `people`). |
| 1.86.0 | v1 | **Cambia**: el álbum que sustituye a un sencillo (`album_instead`, `ask`, `instead_of`) es siempre un álbum o EP del mismo artista, nunca un recopilatorio de varios artistas ni el disco de otro; si no hay ninguno así, el sencillo se pide tal cual. Una petición de un sencillo se da por cumplida también cuando su canción llega dentro de un álbum. Sin campos nuevos. |
| 1.87.0 | v1 | **Cambia** (solo textos y casos, sin campos nuevos): `message` al pedir un sencillo que va como álbum dice «…: se descargará todo el álbum.»; el `429` del tope diario dice «Hoy ya has hecho 20 peticiones. Mañana podrás pedir más.» (igual que el bot); el aviso `rejected` de una petición ya aceptada dice «ha cancelado tu petición»; `outcome: "watching"` también en música (álbum que el administrador ya está descargando: petición ya aceptada, fuera del límite); pedir un álbum que ya está pedido con otro `deezer_id` (otra edición del mismo disco) te apunta a esa petición (`joined`, y `request.deezer_id` es el de la existente); pedir una temporada con episodios sueltos de ella esperando respuesta los convierte en esa temporada (los demás llegan en `removed_ids`). El bot y la app comparten el turno al pedir (`503 busy` si otro pide en ese momento). |
| 1.88.0 | v1 | **Nuevo**: `cancelled` en cada petición (siempre presente): `true` si el administrador la canceló después de aceptarla. **Cambia**: en ese caso `status_label` dice «Cancelada» en vez de «No aceptada»; `status` sigue siendo `rejected`, así que una app anterior no nota nada más que el texto. |
| 1.90.1 | v1 | **Nuevo**: `recheck` en el avance de una descarga (en `progress`, en cada episodio de `episodes` y en `download` de la ficha de película): cuando está «En revisión» porque el archivo no estaba listo en el servicio de descargas, Stremfin lo sigue intentando solo; dice hasta cuándo, la siguiente mirada y un texto para enseñar. `null` en lo demás. Nada de lo anterior cambia. |
| 1.90.2 | v1 | Solo textos, sin campos nuevos. **Cambia**: `recheck.text` ya no nombra el servicio de descargas («Se sigue intentando solo cada 2 h · quedan 2 días») y cuenta días enteros (con 47 h, «queda 1 día»; antes redondeaba hacia arriba); con las descargas en pausa dice «En pausa: se sigue intentando solo al reanudar…». `label` de una descarga en revisión que Stremfin sigue intentando sola es «En revisión · se sigue intentando solo» (`state` y `phase` siguen siendo `attention`), también en el `progress` de una serie cuando todos sus episodios en revisión están así. |
