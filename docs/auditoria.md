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
| 1 | arreglada y probada | revisada y arreglada |
| 2 | arreglada y probada | revisada y arreglada |
| 3 | arreglada y probada | revisada y arreglada |
| 4 | arreglada y probada | revisada y arreglada |
| 5 | arreglada y probada | revisada y arreglada |
| 6 | arreglada y probada | revisada y arreglada |
| 7 | arreglada y probada | revisada y arreglada |
| 8 | arreglada y probada | — |
| 9 | arreglada y probada | — |
| 10 | arreglada y probada | — |

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
  de más), más los de los bloques 3 y 10 (colecciones, consultas mucho más
  ligeras en bibliotecas grandes, Inicio que se rehace si TMDB falla, textos del
  panel en español, «No me interesa» en títulos sin TMDB, títulos de episodios
  en español). Se instala en el servidor de casa y hay que reiniciarlo.
  Recomendación: publicarla junto con la versión de la app.

### Bloque 3
- **«Quiero verlo» en el modo infantil.** Hoy la fila de botones de la ficha en
  el modo infantil no lo tiene, pero la página de «Quiero verlo» y el menú de
  las tarjetas sí. Recomendación: dárselo también en la ficha (es inofensivo y
  útil para que los niños apunten lo que quieren ver).
- **Ocultar de «Seguir viendo».** En Jellyfin ocultar algo de esa fila borra
  también por dónde ibas. Recomendación: avisarlo en la propia opción («Quitar
  de Seguir viendo (se olvida por dónde ibas)») y dejar deshacerlo 5 s.

### Bloque 4
- (Para saber) Con «¿Sigues viendo?» y la tarjeta del siguiente episodio
  desactivada, el reproductor pasa solo al siguiente sin preguntar. Arreglarlo
  toca el motor de reproducción; queda apuntado para la ronda de interfaz.

### Bloque 6
- **Textos de Stremfin en la app en inglés.** Los motivos de «Para ti», los
  estados del botón y los mensajes al pedir llegan en español del servicio y
  salen así también con la app en inglés. Recomendación: dejarlo (toda la
  familia usa la app en español y traducirlos haría perder el texto exacto).
- **«Tus listas»** abre la lista con la ficha general, no con la de los álbumes
  de Música. Recomendación: darle la ficha de Música más adelante, como novedad.
- **Quitar y mover canciones de «A continuación» con el mando** (hoy solo en
  táctil y ratón). Recomendación: añadirlo en la ronda de interfaz.
- **Volumen propio de la música en la web del ordenador** (hoy hereda el del
  último vídeo). Recomendación: un control de volumen en «Reproduciendo».
- **Modo infantil con música sonando.** Al activar el modo infantil en la misma
  persona, la música sigue. Recomendación: pararla.
- **Tráiler a pantalla completa con música sonando.** Hoy la para.
  Recomendación: ponerla en pausa y que siga al cerrar el tráiler.

### Bloque 7
- **Bibliotecas mixtas** (películas y series juntas) abren todavía la página
  antigua. Se pueden llevar al catálogo de kOS TV, pero los vídeos sueltos que
  tengan no saldrían. Recomendación: llevarlas al catálogo solo si en casa no
  hay vídeos sueltos en ellas.
- **Música de casa en el modo infantil** se puede abrir desde «Mis medios».
  Recomendación: dejarlo (la música respeta el límite de edad de la cuenta).
- **Descargas compartidas en el aparato.** Las descargas son del aparato, no de
  cada persona: todos ven las de todos, y lo visto o la posición de una persona
  pisan los de otra en esa descarga. Recomendación: que cada persona vea solo lo
  suyo y su progreso (lo descargado por otro, en una sección aparte).
- **Descubrir libros en el modo infantil** (Open Library, cualquier libro).
  Recomendación: quitarlo del modo infantil.
- **Juegos y «Cuenta de RomM» en el modo infantil.** Recomendación: dejar jugar
  pero esconder la cuenta de RomM.
- **Descargas desde el navegador en la web** llevan la clave de la sesión en la
  dirección y quedan en el historial de descargas del navegador.
  Recomendación: dejarlo (el navegador no deja otra forma sencilla) y avisarlo.
- (Para saber) El calendario no se puede usar: el complemento del servidor ya no
  lo da. Sigue en el código; se puede quitar más adelante.

### Bloque 8
- (Para saber) El menú «Tú» del móvil enseña el nombre del servidor de casa.
  Se deja como está.

### Bloque 9
- **Panel de administración en la tele.** El panel, y editar los datos de un
  título desde su ficha, no existen en la tele, solo en el móvil y la web.
  Recomendación: dejarlo así y apuntarlo como excepción a la norma de las tres
  versiones (administrar con el mando es incómodo y se hace mejor desde el
  móvil).

### Bloque 10
- **Pasar las pruebas antes de publicar.** Hoy publicar una versión no pasa el
  analizador ni las pruebas automáticas. Recomendación: pasarlas (la
  publicación tardaría unos minutos más, pero no saldría nada roto a las teles).
- **Política de seguridad de la web (CSP).** No hay ninguna vía de ataque a la
  vista. Recomendación: añadirla más adelante, con calma, porque una mal puesta
  deja la web en blanco.
- **El contenedor de la web arranca como administrador del sistema.**
  Recomendación: cambiarlo; obliga a cambiar el puerto interno del compose.
- **Los AAB** (el formato de la tienda de Google) se compilan en cada
  publicación y no se usan, pero son lo único que comprueba un requisito de
  Android 15 (páginas de 16 KB). Recomendación: dejarlos.
- (Para saber) Por `http://IP:25670` la contraseña de `/admin` viaja sin cifrar;
  desde fuera de casa se entra siempre por el proxy con https.
- (Para saber) Hay borradas en local 17 etiquetas de la app original que no
  estaban en GitHub, para que nunca se suban por error.

## Lo que decidió el usuario

Todo como se recomendaba (19 de noviembre de 2026). Se hacen: 1 (PIN propio
del control parental), 3, 5, 6, 7, 10, 11, 12, 13, 14, 16, 17, 18, 19, 21 y 23.
Se quedan como están: 2, 8, 15, 22 (más adelante) y 24. «Tus listas» con la
ficha de Música (9), más adelante como novedad. El complemento (4) se publica
junto con la próxima versión de la app. El panel de administración (20) queda
como excepción: solo móvil y web.

## Ronda de interfaz

### Bloques 1, 2 y 3 (arranque, Inicio y fichas)
Fotos de tele (web con la tele forzada), móvil (393×852) y ordenador
(1440×900) contra el servidor falso. Arreglado:
- En la web, el tráiler de fondo de las fichas se quedaba el teclado: las
  flechas y OK dejaban de funcionar (ordenador y tele simulada).
- Notas y duraciones en español en toda la app («7,1», «1 h 35 min»,
  «44 min»); antes la mitad salía como en inglés («7.1», «1h 35m»).
- Filas de la ficha con el mando: en la web, izquierda y derecha movían la
  fila en vez del foco y la tarjeta enfocada quedaba cortada. La pestaña
  «Temporada 1» enfocada perdía las esquinas.
- Barra de arriba en el móvil: los iconos ocultos se difuminan en el borde
  (antes el último salía cortado sin aviso). En el ordenador y el móvil, al
  bajar aparece una sombra suave detrás de la barra.
- «Seguir viendo» en todos los textos (algunos decían «Continuar viendo»).
- Lista de episodios del móvil: la línea «EPISODIO 2 · 44 MIN» ya no se corta.

Para más adelante (bloque 8): la barra de arriba no marca en qué página
estás; el orden de los botones del menú del perfil cambia entre tele, móvil y
ordenador.

### Bloques 4, 5, 6 y 7 (reproductor, Descubrir, Música y biblioteca)
Arreglado:
- Reproductor: «Termina a las…» entero en el móvil; en el ordenador los
  botones van juntos a la derecha, como en la tele; en la tele la etiqueta del
  botón enfocado ya no tapa la duración.
- Ficha de solicitar que no carga: aviso y «Reintentar» centrados y en el
  mismo orden en las tres; en la tele «Reintentar» se ve enfocado.
- Fichas de álbum en la tele: abren arriba, con la portada entera. La ficha de
  un álbum de casa tiene la barra de arriba, como las demás.
- «Reproduciendo» (móvil y web): sin el recuadro claro bajo la portada.
- Bandeja de peticiones en el móvil: los títulos ya no se cortan.
- TV en directo en el móvil: el título se lee entero. «Grabaciones» con el
  aspecto de kOS TV y un aviso útil cuando está vacía.
- Una dirección de biblioteca guardada abre el catálogo nuevo.
- En el ordenador, las flechas de las filas solo salen si hay más que ver.
