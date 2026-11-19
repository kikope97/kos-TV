# Auditoría a fondo de kOS TV

La app, separada en 10 bloques. Cada bloque pasa dos rondas: primero la
**técnica** (fallos reales, errores silenciosos, datos que se pierden,
rendimiento, seguridad, código que sobra) y luego la de **interfaz** (fotos de
tele, móvil y web de cada pantalla, coherencia entre diseños, foco con mando,
textos). Cada hallazgo se comprueba antes de enseñarlo y se separa en «arreglar
seguro», «dudoso» y «decide tú». No se toca nada sin el visto bueno del
usuario. Norma de siempre: ninguna función se pierde ni va a peor.

| # | Bloque | Qué incluye | Dónde está |
|---|---|---|---|
| 1 | Arranque, sesión y cuentas | Inicio de la app, intro, conexión al servidor de casa, inicio de sesión, perfiles, PIN, modo infantil, actualizador | `main.dart`, `app.dart`, `di/`, `auth/`, `ui/screens/auth`, `ui/screens/setup`, `platform/`, `app_update_*` |
| 2 | Inicio y banner | Inicio, filas, recomendaciones, Top, banner y su tráiler, carrusel del móvil, filas guardadas | `ui/screens/home`, `widgets/media_bar*`, `widgets/mediabar/`, `media_bar_repository`, `kostv_home` |
| 3 | Fichas | Película, serie, episodio, temporadas, episodios que faltan, colecciones, tráiler de fondo, «Quiero verlo», favoritos | `ui/screens/detail`, `item_detail_view_model` |
| 4 | Reproductor de vídeo | Tele, móvil y web, subtítulos, audios, calidad, saltar intro, siguiente episodio, ver juntos | `playback/`, `packages/playback_*`, `ui/screens/playback`, `syncplay/`, `watch_party/` |
| 5 | Descubrir y peticiones | Descubrir, ficha de solicitar, bandeja, «Para solicitar», tráilers en español, límites y edad | `ui/screens/discover`, `data/services/stremfin/` |
| 6 | Música | Página de Música, álbumes, reproductor, cápsula, letras, pedir álbumes | `ui/screens/music`, `widgets/music`, `kostv_music` |
| 7 | Navegar la biblioteca | Bibliotecas, catálogo, géneros, favoritos, buscador, calendario, TV en directo, descargas, libros y juegos | `ui/screens/browse`, `search`, `calendar`, `livetv`, `downloads`, `book`, `games` |
| 8 | Menús, diseño y piezas comunes | Barras de arriba, lateral y de abajo, foco con mando, tarjetas, imágenes, temas, cristal, textos | `ui/widgets`, `ui/theme`, `ui/navigation`, `packages/design`, `l10n` |
| 9 | Ajustes y administración | Ajustes con vista previa, preferencias y su sincronización, panel de administración | `ui/screens/settings`, `ui/screens/admin`, `preference/` |
| 10 | Servidor, web y publicación | Conexión con Jellyfin, datos sin conexión, complemento, web en Docker, compilación y publicación | `data/` (resto), `packages/server_*`, `complemento/`, `docker/`, `.github/workflows` |

## Estado

| # | Técnica | Interfaz |
|---|---|---|
| 1 | revisada (43 hallazgos comprobados), esperando visto bueno | — |
| 2 | revisada, arreglando | — |
| 3–10 | — | — |

## Cómo se trabaja

Lo obvio (fallos claros, sin perder funciones ni cambiar ajustes) se arregla
directamente. Solo lo que de verdad es una elección del usuario se apunta abajo
y se le pregunta todo junto al terminar los 10 bloques, con una recomendación.

## Decisiones para el final

### Bloque 1
- **PIN propio del control parental.** Hoy «Control parental» se protege con
  el PIN de entrar al perfil, que quien usa el perfil conoce: un adolescente
  puede quitar el filtro del aparato (el límite de su cuenta de Jellyfin sigue).
  Recomendación: un PIN aparte solo para el control parental.
- **Tokens de sesión sin cifrar** en el almacenamiento normal (el seguro está
  preparado pero no se escribe). Riesgo bajo: Android no copia esos datos.
  Recomendación: dejarlo; moverlos puede cerrar la sesión a toda la familia si
  la migración falla.
- (Para saber, no hay nada que decidir) En la web el modo infantil y su PIN
  viven en el navegador y se pueden borrar con sus herramientas: en la web es
  más débil que en la tele.

### Bloque 2
- **Fila «Aleatorio» en el modo infantil.** El Inicio del modo infantil solo
  enseña las secciones permitidas, pero «Aleatorio» sale igual (lo que saca
  respeta el límite de edad de la cuenta). Recomendación: quitarla del modo
  infantil para que sea de verdad una lista cerrada.
- **Publicar una versión nueva del complemento** con los arreglos del Inicio que
  calcula el servidor (filas «Porque viste» de lo no visto, Top y «Ya está aquí»
  que llegaban tarde, lo recién llegado que no salía al actualizar, consultas
  de más). Se instala en el servidor de casa y hay que reiniciarlo.
  Recomendación: publicarla junto con la versión de la app.
