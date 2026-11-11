# Política de privacidad de kOS TV

kOS TV es un cliente de Jellyfin para uso familiar (ver el [README](README.md)).
No tiene servidores propios, no muestra publicidad y no usa servicios de
analítica ni de seguimiento.

## Qué guarda en el dispositivo

Solo en el propio dispositivo, en el almacenamiento privado de la app:

- La dirección del servidor Jellyfin y la sesión iniciada (el token de acceso).
- Los ajustes y preferencias.
- Imágenes en caché, para que las portadas carguen más rápido.

## Con quién se comunica

- **El servidor Jellyfin** en el que has iniciado sesión: para ver el
  contenido, iniciar sesión y guardar los ajustes que se sincronizan.
- **GitHub** (`api.github.com` y `github.com`): para comprobar si hay una
  versión nueva de kOS TV y descargarla. Como cualquier web, GitHub ve la
  dirección IP desde la que se pregunta.
- Solo si usas la función correspondiente: Seerr, para pedir contenido; TMDB y
  MDBList, para listas y recomendaciones; YouTube y SponsorBlock, para los
  tráileres; Open Library y Google Books, para descubrir libros; y el catálogo de libretro,
  para descargar los núcleos de los juegos.

## Informes de errores

Cuando la app falla puede enviar un informe técnico (traza del error, versión
de la app, modelo del dispositivo y versión del sistema) **solo al servidor
Jellyfin en el que has iniciado sesión**, nunca a terceros. Se quitan antes las
direcciones de servidores, las IP y los tokens. Viene activado y se puede
desactivar en Ajustes > Acerca de > Diagnostics & Logging.

## Búsqueda por voz

Si usas la búsqueda por voz, el audio lo procesa el reconocedor de voz del
propio dispositivo; kOS TV no lo graba ni lo envía.

## Código abierto

El código está en este repositorio para quien quiera comprobar lo que hace.
kOS TV parte de [Moonfin](https://github.com/Moonfin-Client/Moonfin-Core).
