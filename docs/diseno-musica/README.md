# Música en kOS TV · diseño

**Aprobado por el usuario el 2026-11-22**, con las tres recomendaciones: botón de reproducir con el degradado de kOS, filas sin botón propio (el número pasa a ▶ con el foco) y pestañas arriba en el inicio de Música del móvil. Todo se ve igual esté o no en casa; solo el álbum y el reproductor lo explican.

Maquetas en esta carpeta (JPG a 1x; se regeneran con `node maquetas/render.js`). Empieza por `componentes.jpg`: ahí están todas las piezas juntas.

| Pantalla | Tele (1280×720) | Móvil (393×852) | Ordenador (1440×900) |
|---|---|---|---|
| Inicio de Música | `tele_inicio.jpg` · `tele_lateral_inicio.jpg` (barra lateral + cápsula) | `movil_inicio.jpg` (+ cápsula) | `ordenador_inicio.jpg` (+ cápsula, ratón encima de una tarjeta) |
| Álbum en casa | `tele_album_casa.jpg` | `movil_album_casa.jpg` | `ordenador_album_casa.jpg` |
| Álbum fuera de casa | `tele_album_fuera.jpg` | `movil_album_fuera.jpg` | `ordenador_album_fuera.jpg` |
| Artista | `tele_artista.jpg` | `movil_artista.jpg` | `ordenador_artista.jpg` |
| Reproductor | `tele_reproductor.jpg` | `movil_reproductor.jpg` | `ordenador_reproductor_cola.jpg` (con la cola) |
| Buscador | `tele_buscador.jpg` | `movil_buscador_barra_abajo.jpg` (barra de abajo + cápsula) | `ordenador_buscador.jpg` |

En cada pantalla de la tele hay un elemento con foco (marco blanco y un poco más grande).

## Lo que he mirado (Spotify y Apple Music)

Lo que hace que se vean «caros», en tele, móvil y web:

- **La portada manda.** Portadas grandes y cuadradas, con poco texto alrededor. La pantalla toma el color del disco que suena (fondo difuminado o degradado), así cada disco se ve distinto sin añadir adornos.
- **Pocas cosas, bien jerarquizadas.** Un título grande y con peso, un subtítulo apagado y nada más. Sin etiquetas, insignias ni iconos de estado en las filas.
- **Un único botón de reproducir** con el color de la marca. Todo lo demás (aleatorio, me gusta, más) son iconos neutros.
- **Filas de canciones limpias:** número, título, artista y duración. El ▶ solo aparece al pasar el ratón o con el foco, en lugar del número.
- **Estanterías** horizontales de tarjetas cuadradas y un bloque de accesos rápidos arriba («sigue escuchando»).
- **En la tele** (Spotify rehizo su app de Apple TV en octubre de 2025; Apple Music en tvOS 26 lleva Liquid Glass): pocas columnas, letras grandes, foco muy visible y el reproductor a pantalla completa con la portada a un lado.

## Principios para kOS TV

1. **Todo se ve igual, esté o no en casa.** Mismas tarjetas, mismas filas y el mismo botón. Ni nube, ni botón gris, ni «Pedir» en las filas.
2. **Solo se explica donde importa**: una línea tranquila en el álbum y otra en el reproductor. Dicen qué pasa y ofrecen pedirlo, sin alarmar.
3. **Un solo botón de reproducir**: un círculo con el degradado de la marca (cian, violeta y rosa) y el icono en negro. Hay cuatro tamaños (reproductor 84, álbum 64, tarjeta 44 y fila o estante 32) y no existe ninguna versión «apagada».
4. **La portada pone el color.** El álbum, el artista y el reproductor toman el color del disco para el fondo. El degradado de la marca queda solo para lo que se pulsa y para lo que suena (barra de progreso y ecualizador).
5. **Letras con carácter**: Outfit Bold, la de la marca, para los títulos (página 40–44, álbum 64–68, estantes 22–24); Roboto para lo demás (16–17 en la tele, 15 en el móvil y en la web).
6. **Foco de tele claro**: marco blanco de 3 px separado 3 px, un 7 % más grande y con sombra. En las filas, el ▶ sustituye al número y aparece «⋯» para el menú. En la web, el ratón hace lo mismo.
7. **Las mismas medidas en todas partes**: márgenes de 64 en la tele, 56 en la web y 16 en el móvil, y tarjetas de 168–176, 190 y 140–150. Las piezas son las mismas en la tele, el móvil y la web.

## Qué cambia en cada pantalla

- **Inicio de Música.** Arriba, «Sigue escuchando»: 8 accesos (6 en el móvil) que mezclan álbumes, listas y mezclas. Después, estanterías de tarjetas grandes: «Tus mezclas» con arte propio (fotos de los artistas y «Mezcla N»), «Para ti» con la tarjeta de «Descubrimiento» en el degradado de la marca, «Top España» en columnas de filas sin botones y con el ▶ pequeño junto al título, «Porque escuchas a…» y «Novedades». El buscador pasa a ser una caja arriba a la derecha (en el móvil, un botón), y en el móvil hay pestañas: Para ti, Tus listas, Artistas y Álbumes.
- **Álbum.** La portada grande a la izquierda (arriba en el móvil). Debajo del título, una línea con la foto del artista, el nombre y los datos. Luego el botón de reproducir y tres iconos redondos. En la tele, las canciones van en dos columnas; en la web, como una tabla.
- **Artista.** Una cabecera grande con la foto y el nombre en Outfit enorme. Botones: reproducir, «Mezcla de…» y me gusta. Debajo, «Populares» (con el ecualizador si suena alguna), «Su último disco» (en la web) y «Discografía».
- **Reproductor.** El fondo toma el color de la portada. En la tele y la web, la portada a la izquierda y los datos y controles a la derecha, con «A continuación» abajo. En el móvil, la portada arriba y los controles debajo. En la web, la cola y la letra van en un panel a la derecha.
- **Cápsula.** Mantiene la forma de píldora y la portada redonda, más opaca para que no se transparente lo de detrás. Lleva me gusta, el botón de pausa en la marca, siguiente y la barra de progreso con el degradado. No lleva ninguna marca de casa o fuera.
- **Buscador.** «Lo mejor» en una tarjeta grande con su botón, las canciones al lado y debajo artistas y álbumes. En el móvil y la web, filtros en pastillas. Los resultados de casa y de fuera salen mezclados y se ven igual.

## «No está en casa»: reglas

| Sitio | Qué se ve |
|---|---|
| Filas, tarjetas, estanterías, buscador, cápsula y listas | **Nada.** Igual que lo de casa. |
| Álbum | Debajo de los botones: «**Este disco no está en casa: suena en streaming.** Pídelo para tenerlo en casa con más calidad.» y un botón secundario (de contorno) «Pedir el álbum». Sus estados: *Pedido · te avisamos*, *De camino* y *Ya está en casa* (este último solo un momento; luego la nota desaparece). |
| Reproductor | Una línea pequeña bajo el artista: «Suena en streaming · no está en casa · **Pedir el álbum**». En la tele, «Pedir el álbum» recibe el foco al bajar desde el título, y cambia a *Pedido* o *De camino* igual que en el álbum. |
| Cola | **Sin marca** (decidido). La cola es para ordenar, no para informar; quien quiera saberlo lo ve en el reproductor al llegar la canción. |
| Notificación del móvil y pantalla de bloqueo | **Solo canción y artista**, sin «streaming» (decidido). La notificación no es el sitio para explicarlo y en la de casa no pone nada. |
| «Preparando la canción…» | Se queda, pero solo si tarda más de 1,5 s, y sin decir «no está en casa»: «Preparando la canción…» y, si tarda más, «Está tardando más de lo normal». |
| Canción que no se puede escuchar | Se mantiene el aviso actual («Ahora no se puede escuchar. Prueba más tarde»): es un fallo, no un estado. |

La sección «Para pedir» del buscador desaparece: lo de fuera sale mezclado con lo demás. «Lo más pedido en casa» se queda como estantería normal.

## Para que decidas (máximo 3)

1. **Color del botón de reproducir.** (a) Degradado de la marca, como en las maquetas. (b) Blanco liso con el icono negro, más sobrio. (c) El color de la portada. **Recomiendo (a):** es de kOS TV, se distingue de un vistazo en la tele y deja claro que todo se puede reproducir.
2. **Filas de canciones sin botón propio.** (a) Sin botón: el número se convierte en ▶ al tener el foco o el ratón encima, como en las maquetas. (b) Un ▶ pequeño, igual en todas las filas. **Recomiendo (a):** es más limpio y en la tele el foco ya dice qué se pulsa. En el móvil se toca la fila entera.
3. **Inicio de Música en el móvil.** (a) Pestañas arriba (Para ti, Tus listas, Artistas, Álbumes) y el buscador en un botón. (b) Todo en una página larga, como en la tele. **Recomiendo (a):** en el móvil reduce mucho el desplazamiento; la tele y la web siguen con una página larga.

## Cómo hacerlo en la app (por fases)

Todo texto nuevo va en `lib/l10n/app_es.arb` y `app_en.arb`. Cada fase se prueba en la tele (los dos diseños), el móvil (los dos diseños) y la web, con fotos de cada una.

**Fase 1 · Piezas comunes y «todo igual».** Es la que más se nota y la de menos riesgo.
- `kostv_music_widgets.dart`: `KostvMusicSizes` con las medidas nuevas por plataforma. Un `KostvPlayButton` único (degradado, cuatro tamaños, foco). `KostvMusicSongRow` sin `KostvMusicRowAction`: el número se cambia por ▶ con el foco o el ratón y por el ecualizador si suena. Foco nuevo en `KostvMusicPressable` y tarjetas de `KostvMusicAlbumTile` con su ▶ al tener el foco.
- `kostv_stream_widgets.dart`: `KostvStreamMark` y `KostvStreamMarked` dejan de usarse en filas, tarjetas y buscador. `KostvStreamPill` («Pedir», «Pedido», «De camino») sale de las filas y se queda solo en el álbum y el reproductor.
- `kostv_stream_play.dart` y `kostv_now_playing_capsule.dart`: quitar la nube de la cápsula y del arranque.
- Revisar también los otros sitios que hoy pintan la marca: `lib/ui/widgets/bottom_nav/bottom_mini_player.dart` (el reproductor pequeño de la barra de abajo), `lib/ui/screens/detail/item_detail_screen.dart`, `kostv_music_actions.dart` y la lista de «No me gusta» (`kostv_music_dislikes_screen.dart`, donde sí puede quedarse el texto «No está en casa», porque es un ajuste). Comprobar que la cola y la notificación no digan nada de streaming.
- Textos: la nota nueva del álbum (sustituye a `kostvStreamAlbumNote` y `kostvMusicAskAlbumWhy`), la línea del reproductor (sustituye a `kostvStreamNotAtHome`), «Pedido · te avisamos» y «Ya está en casa».

**Fase 2 · Álbum y artista.**
- `kostv_music_album_screen.dart`: la cabecera nueva, la nota en su sitio fijo, la tabla en la web y dos columnas en la tele. El color de la portada con `palette_generator` o con el color medio que ya se calcula, guardado por álbum.
- `kostv_music_artist_screen.dart`: la cabecera con la foto, «Populares», «Su último disco» y «Discografía».

**Fase 3 · Reproductor y cola.**
- `kostv_now_playing_screen.dart`: la disposición nueva por plataforma, la línea de «Pedir» que puede recibir el foco y el panel de cola y letra en la web.
- `kostv_queue_moves.dart`: las filas nuevas.

**Fase 4 · Inicio de Música y buscador.**
- `kostv_music_screen.dart`: «Sigue escuchando», el nuevo orden de las estanterías, el arte de mezclas y Descubrimiento (`KostvMusicMixArt` y `KostvDailyMixArt`) y las pestañas en el móvil si eliges 3a. El buscador con «Lo mejor», filtros y resultados mezclados, sin la sección «Para pedir».
- `music_navigation.dart` y `music_widgets.dart`: ajustar `MusicShelf` y `MusicQuickTile` a las medidas nuevas.

Nada de esto toca el complemento del servidor ni las llamadas a Stremfin: es solo presentación.

Fuentes: [Spotify rediseña su app de Apple TV (MacRumors, 2025)](https://www.macrumors.com/2025/10/28/spotify-redesigned-apple-tv-app/), [Spotify en las teles (Spotify Newsroom, 2023)](https://newsroom.spotify.com/2023-11-09/find-your-favorite-audio-more-easily-with-the-redesigned-spotify-on-tv-experience/), [tvOS 26 a fondo (AppleInsider)](https://appleinsider.com/articles/25/06/18/tvos-26-hands-on-sleek-liquid-glass-redesign-new-control-center-and-more), [Apple Music en iOS 26 (AppleInsider)](https://forums.appleinsider.com/discussion/240889).

## Piezas en la app

Hechas en la fase 1. Las fases 2–4 las usan tal cual (no se hacen otras parecidas). Todas están en `lib/ui/widgets/music/design/` y se importan juntas con `kostv_music_design.dart`.

| Pieza | Dónde | Qué es |
|---|---|---|
| `KostvMusicTokens` | `kostv_music_tokens.dart` | Colores (fondo `#0B0B0F`, tinta, apagado, cian, violeta, rosa y el degradado de la marca), radios, el foco (marco 3 px separado 3 px, +7 %) y las medidas por pantalla: márgenes 64/56/16, tarjeta 172/190/150, filas, accesos y títulos. |
| `KostvMusicType` | `kostv_music_tokens.dart` | Letras: `title(tamaño)` en Outfit Bold para títulos; `body` y `muted` para lo demás. `KostvGradientText` pinta un texto con el degradado (lo que suena). |
| `KostvPlayButton` | `kostv_play_button.dart` | El único botón de reproducir: círculo con el degradado e icono negro. Tamaños `KostvPlaySize.player` (84), `album` (64), `card` (44), `row` (32), o `diameter`. `pause: true` para ⏸. Con `onTap` es una parada propia (foco con marco blanco y +10 %, ratón encima y pulsado); sin él solo se dibuja. `KostvPlayFace` es su dibujo, para meterlo en algo que se pulsa entero (la cápsula, una tarjeta). |
| `KostvSongRow` | `kostv_song_row.dart` | La fila de canción: número → ▶ con el foco o el ratón (sin número, el ▶ va sobre la portada), ecualizador con el degradado si suena (`sound` o `soundingId`, que sigue al reproductor), título, artista (`subtitle` o `subtitleBuilder` para enlaces), duración (`kostvSongLength`) y «⋯» con el foco o el ratón (abre `onMenu`). Marco blanco de 2 px y +2 % con el foco. `trailing` solo para el estado de petición con «Solo la de casa». `KostvSongRowFace` es su dibujo sin parada. |
| `KostvMusicSongRow` y `KostvMusicTrackRow` | `kostv_music_widgets.dart`, `kostv_music_album_screen.dart` | Las filas de siempre de las listas y del álbum, ahora hechas con `KostvSongRow` (mismos parámetros, más `duration` y `soundingId`). `kostvSongSoundingId(StremfinSong)` da el id de la cola. |
| `KostvMusicAlbumTile` | `kostv_music_widgets.dart` | La tarjeta cuadrada (y el círculo de artista): `KostvFocusFrame` y, en discos, mezclas y listas, el ▶ de la marca abajo a la derecha con el foco o el ratón. `onPlay` hace que ese ▶ reproduzca con ratón o toque; el resto de la tarjeta sigue abriendo. |
| `KostvFocusFrame` | `kostv_focus_frame.dart` | El foco de la tele para cualquier pieza: marco blanco de 3 px separado `gap`, sombra y `scale` (1,07 por defecto). |
| `KostvMusicQuickTile` | `kostv_music_tiles.dart` | Acceso rápido de «Sigue escuchando»: portada a la izquierda, nombre y línea, fondo de cristal; con el foco, marco y +5 %. `art` para el corazón de favoritas o el arte de una mezcla. |
| `KostvShelfHeader` | `kostv_music_tiles.dart` | Cabecera de estante: título en Outfit, línea debajo, `onPlay` (▶ pequeño junto al título), `actions` y `more` a la derecha. `KostvMusicHeading` (la de siempre) ya usa la misma letra. |
| `KostvMusicPill` y `KostvRoundIcon` | `kostv_music_pills.dart` | Pastilla secundaria (`ghost`, de contorno: «Pedir el álbum»; `quiet`: «Pedido · te avisamos», «De camino», «Ya está en casa») y botón redondo de cristal (aleatorio, me gusta, ⋯). Blancos con el foco. |
| `KostvArtworkColors` | `kostv_artwork_colors.dart` | Color de la portada, calculado una vez por imagen (a partir de una copia de 48 px, entre fotogramas) y guardado (las últimas 96). `cached(url)` al momento, `of(url)` si no; `wash(color)` da el fondo difuminado del álbum, el artista y el reproductor. El reproductor ya lo usa. |
| `KostvEqualizerBars` | `kostv_now_playing_capsule.dart` | El ecualizador de siempre, ahora con `gradient` para pintarlo con la marca. Solo se mueve si suena y está a la vista. |

Textos nuevos (al final de los `.arb`): `kostvMusicAwayNoteLead` y `kostvMusicAwayNoteRest` (la nota del álbum), `kostvMusicAwayPlayerLine` y `kostvMusicAwaySongNote` (la línea del reproductor), `kostvMusicAskTheAlbum`, `kostvMusicAskedNotify` y `kostvMusicAlreadyHome`.
