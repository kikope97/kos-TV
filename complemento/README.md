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
- **El botón Descubrir se sincroniza** como los demás (`showDiscoverButton`), con
  su valor por defecto en la página.
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
