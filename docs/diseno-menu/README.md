# Menú de kOS TV · diseño

**Aprobado por el usuario el 2026-11-22.** Tele: opción **A** (pestañas con nombre), con las recomendaciones (al bajar, el menú se recoge en una píldora; «Más» con Géneros, Calendario y Aplicaciones; «Tú» en el avatar con el número de la bandeja). Móvil: **cristal líquido** con las recomendaciones (barra flotante con todas las pestañas con nombre: Inicio · Descubrir · Música · Tú; **Buscar en un botón redondo aparte**; la barra **se recoge al bajar** con el mini reproductor dentro; «Más» manteniendo pulsado «Tú»). La barra de abajo es la de serie en el móvil; quien tenga otra elegida la conserva. Maquetas JPG en esta carpeta; fuentes en `maquetas/`.

## Tele y ordenador


Solo es una propuesta: no se ha tocado la app. Las maquetas están en esta carpeta (PNG a 2x; se rehacen con `node mk.js`).

## Lo que he mirado (2025–2026)

- **Netflix (tele, mayo de 2025)** quitó la barra lateral y puso un **menú arriba con texto**: Buscar, Inicio, Series, Películas, Juegos, Mi Netflix, con el perfil a la izquierda. «Atrás» vuelve al menú.
- **Prime Video (julio de 2024)** volvió a poner arriba la barra, que llevaba dos años a la izquierda, con **pocos destinos con nombre** (Inicio, Películas, Series, Deportes, TV en directo).
- **Google TV:** pestañas de texto arriba, buscar con icono, el perfil a un lado y el reloj a la derecha. El menú se esconde al bajar.
- **Apple TV (tvOS 26):** pestañas de texto en una cápsula de cristal (Liquid Glass) y barra lateral que se abre con los nombres en las apps grandes. **Disney+** usa una lateral de iconos que se abre al ponerse encima.
- **Móvil:** todas las apps van abajo, con **3–5 pestañas con nombre**. Spotify: Inicio, Buscar y Tu biblioteca. Netflix: Inicio, Novedades y Mi Netflix. Apple Music (iOS 26): Inicio, Novedades, Radio, Biblioteca y Buscar, con el mini reproductor encima de la barra.

Lo que se repite: **palabras mejor que iconos** en la tele, **6–7 destinos como mucho**, el perfil como puerta a «lo tuyo» y, en el móvil, **la barra abajo**.

## Principios

1. **Se lee, no se adivina.** Hoy la tele tiene 10 iconos sin nombre y 3 círculos sueltos. La propuesta lleva 6 destinos con nombre, la lupa y «Más».
2. **Lo de cada persona va en «Tú»** (el avatar): peticiones, favoritos, cambiar de persona y Ajustes. El número de la bandeja va en el avatar y el anillo gira mientras hay algo en marcha.
3. **Mismo lenguaje que Música.** Títulos en Outfit y blanco sobre negro. El degradado de kOS solo marca dónde estás (la rayita de la pestaña) y lo que se pulsa o suena. Con el mando, la cápsula blanca (la de cristal de ahora) viaja al botón con el foco.
4. **El menú no estorba.** Al bajar por las filas de la tele se recoge; «Atrás» lo trae con el foco en la página en la que estás. No atrapa el foco: abajo entra en la página y arriba no hace nada.

## Destinos y grupos (los mismos en tele, móvil y web)

| Grupo | Qué lleva |
|---|---|
| A la vista | 🔍 Buscar · **Inicio · Descubrir · Música · Quiero verlo · Bibliotecas · TV en directo** (solo si el servidor la da) |
| «Más» (⋯) | Géneros · Calendario · Aplicaciones (esta, solo en la tele) |
| «Tú» (avatar) | Mis peticiones (con su número) · Mis favoritos · Cambiar de persona · Ajustes |
| Reloj | A la derecha en la tele. En la web no sale (el ordenador ya tiene el suyo). |

Descubrir y Música siguen apareciendo solo si están activos, como ahora. «Aleatorio» sigue al final de Inicio.

## Tele: A o B

- **A · Pestañas con nombre** (`tele_A_reposo`, `tele_A_foco`, `tele_A_mas`, `tele_A_perfil`, `tele_A_compacta`). Texto siempre a la vista, como Netflix y Google TV. En reposo no hay fondo, solo una sombra arriba. La página en la que estás va en blanco y negrita, con la rayita del degradado. Con el foco en el menú se enciende la cápsula de cristal y la blanca va al botón. Al bajar, el menú queda en una píldora pequeña (avatar y nombre de la página).
- **B · Iconos que se abren** (`tele_B_reposo`, `tele_B_foco`). Se parece más a lo de hoy, pero con 9 botones en lugar de 13. El botón con el foco y el de la página actual enseñan su nombre; los demás, solo el icono.
- **Barra lateral** (`tele_lateral_cerrada`, `tele_lateral_abierta`). Tiene los mismos destinos y el mismo orden. Cerrada es una columna de iconos con el avatar arriba y el reloj abajo. Con el foco se abre con los nombres, oscurece la página y enseña «Marta · 3 novedades». Con la flecha derecha se vuelve a la página.

## Móvil: barra abajo

`movil_inicio`, `movil_tu` (`comparar_movil` frente a lo de hoy).

- **5 pestañas con nombre: Inicio · Buscar · Descubrir · Música · Tú.** La activa lleva el icono relleno, una píldora de cristal detrás, el nombre en blanco y la rayita del degradado. En «Tú» va la foto de la persona, con un punto rosa si hay novedades.
- **El mini reproductor flota justo encima de la barra.** La barra respeta la zona de gestos y el contenido tiene margen abajo para que no quede tapado.
- **Arriba de cada página**: título grande en Outfit a la izquierda y, a la derecha, el botón de enviar a la tele y la bandeja con su número (la bandeja solo si hay algo).
- **«Tú» es una página, no una hoja.** Arriba, el avatar, el nombre y «Cambiar». Debajo, la tarjeta «Mis peticiones» y tres accesos: Quiero verlo, Mis favoritos y Descargas. Luego «En casa»: Bibliotecas, Géneros, TV en directo y Calendario. Ajustes va en la rueda de arriba.
- Las tres pestañas del medio se siguen pudiendo cambiar en Ajustes > Navegación (ya existe: Inicio + 3 + Tú).

## Web (ordenador)

`ordenador`: la barra A pensada para el ratón. A la izquierda, el logotipo kOS TV; luego las pestañas de texto, con un fondo suave al pasar el ratón; «Más ▾» abre un menú. A la derecha, una caja «Buscar», la bandeja con su número y el avatar (el menú «Tú»). Al desplazarse, la barra se queda arriba sobre un fondo de cristal. En una ventana estrecha (o en el móvil por la web) se usa la barra de abajo del móvil.

## Qué cambia frente a hoy

- **Tele:** de 10 iconos sin nombre a 6 nombres más la lupa y ⋯. Desaparecen los círculos sueltos de bandeja y favoritos: su sitio es el avatar. Ajustes pasa a «Tú» y Géneros a «Más». La cápsula de cristal y el cambio de página al quedarse 0,7 s se quedan.
- **Móvil:** la barra de arriba con 8 iconos que no caben pasa a ser, por defecto, la barra de abajo con 5 pestañas con nombre. La hoja de «Tú» se convierte en una página.
- **Web:** igual que la tele A, más el logotipo, la caja de buscar y los menús al pasar el ratón.

## Para que decidas (3)

1. **Barra de arriba de la tele: A (pestañas con nombre) o B (iconos que se abren).** **Recomiendo A**: es lo que han hecho Netflix, Prime Video y Google TV, y en una familia un nombre se entiende mejor que un icono. B cambia menos lo que ya conocen.
2. **Pestañas del móvil: Inicio · Buscar · Descubrir · Música · Tú, o cambiar Descubrir por Quiero verlo** (lo que propusiste). **Recomiendo Descubrir**: es donde se piden las cosas, y «Quiero verlo» ya está en una fila de Inicio y arriba del todo en «Tú». Cada persona puede cambiarlo en Ajustes.
3. **Al bajar en la tele: recoger el menú en una píldora pequeña (como en la maqueta) o esconderlo del todo** (como Netflix y Google TV). **Recomiendo la píldora**: así siempre se sabe dónde estás y se ven las novedades.

## Cómo hacerlo (por fases)

Todo texto nuevo va en `lib/l10n/app_es.arb` y `app_en.arb`: «Más», «Tú», «Mis peticiones», «{n} novedades», «Cambiar de persona», «En casa»… Antes hay que mirar cuáles existen ya. Cada fase se prueba en la tele (arriba y lateral), el móvil (abajo y, mientras exista, arriba) y la web, con fotos de cada una.

1. **Destinos y grupos.** `lib/ui/navigation/destinations.dart`: una sola lista ordenada (principales, «Más» y «Tú») que lean las tres barras. `menu_preview.dart`: el cambio al quedarse 0,7 s sigue en los principales y en lo que se abre desde «Más» (Géneros, Calendario). Abrir «Más» o «Tú» no cambia la página.
2. **Tele, barra de arriba** (`lib/ui/widgets/top_toolbar.dart`, `nav_capsule.dart`). Pestañas de texto con la cápsula de siempre, el avatar con número y anillo (bandeja y favoritos pasan a su menú) y el estado recogido al bajar, con «Atrás» para volver. Revisar `TopMusicBar` y el reloj (`clockBehavior`).
3. **Tele, barra lateral** (`left_sidebar.dart`). Se abre con los nombres al tener el foco y lleva los mismos grupos.
4. **Móvil** (`lib/ui/widgets/bottom_nav/*`, `navigation_layout.dart`). Estilo nuevo de la barra (o rehacer «dock») con píldora y rayita, y el mini reproductor encima (`bottom_mini_player.dart`). Pestañas por defecto: Buscar, Descubrir y Música (`preference/bottom_nav_tabs.dart`). La página «Tú» sustituye a `bottom_navbar_hub_sheet.dart`. **En el móvil, `navbarPosition` pasa a «abajo» por defecto**: quien ya tenga algo elegido lo conserva (`user_preferences.dart`).
5. **Web.** La barra A con el ratón (pasar por encima, «Más ▾», caja de buscar), sin reloj, y la barra de abajo cuando la ventana es estrecha.

Lo único que se queda solo en la tele es «Aplicaciones», dentro de «Más».

Fuentes: [Netflix · nuevo diseño en la tele (Tudum)](https://www.netflix.com/tudum/articles/netflix-new-tv-layout), [Netflix · ayuda del nuevo diseño](https://help.netflix.com/node/321880164349028), [Netflix rediseña su app de tele (MacRumors)](https://www.macrumors.com/2025/05/07/netflix-redesigned-tv-experience/), [Prime Video · barra de navegación arriba (Neowin)](https://www.neowin.net/news/the-amazon-prime-video-tv-app-is-getting-a-ui-refresh-with-a-new-top-navigation-bar-and-more/), [Prime Video · nuevo diseño (TheWrap)](https://thewrap.com/prime-video-new-user-interface-changes-whats-different).

## Móvil (cristal líquido) — manda sobre la parte del móvil de arriba


Es solo una propuesta y la app no se ha tocado. La tele se queda como se aprobó (opción A). Las maquetas están en esta carpeta; se rehacen con `node mk.js` (a 3x, 393×852).

## Qué hace Apple (iOS 26, 2025)

- **La barra de pestañas flota.** Es una cápsula de cristal separada de los bordes y el contenido pasa por debajo. El cristal desenfoca y refracta lo que tiene detrás, tiene un brillo en el borde y cambia de tono según el fondo: se oscurece sobre contenido claro para que se siga leyendo.
- **Buscar va aparte.** Es una pestaña con su propio botón redondo a la derecha de la barra (`Tab(role: .search)`).
- **Al bajar, la barra se recoge** (`tabBarMinimizeBehavior(.onScrollDown)`) y queda en un círculo con la pestaña activa. Al subir vuelve a abrirse.
- **El accesorio de abajo** (`tabViewBottomAccessory`) es el mini reproductor de Música y Podcasts. Va encima de la barra y, cuando la barra se recoge, pasa a ir **dentro de la fila**, entre la pestaña y Buscar.
- **Los títulos grandes** se quedan pequeños al bajar. No hay barra opaca: el contenido se desenfoca poco a poco por debajo y los botones son de cristal. **Las hojas** son de cristal, flotan separadas de los bordes y siguen las esquinas del teléfono.

## Qué cambia respecto a la propuesta anterior del móvil

La **distribución es la misma**, la que te gustó: 5 destinos (Inicio · Buscar · Descubrir · Música · Tú), el mini reproductor encima, «Tú» como página y, arriba, el título con los botones de enviar a la tele y de la bandeja. Cambia **el aspecto**:

| Antes | Ahora |
|---|---|
| Barra pegada abajo, opaca, de borde a borde | Cápsula de cristal flotante, separada de los bordes; las filas se ven por debajo |
| Buscar era una pestaña más | Buscar es un botón redondo de cristal a la derecha (recomendado) |
| Mini reproductor oscuro y opaco | Mini reproductor de cristal (accesorio) que, al bajar, se mete en la barra recogida |
| La barra siempre igual | Al bajar se recoge (pestaña · mini reproductor · Buscar); al subir o al tocarla se abre |
| Píldora gris y rayita degradada | Píldora de cristal más clara con un **borde fino en degradado**: el degradado solo marca la pestaña activa y lo que suena (la barrita del mini reproductor) |
| Título fijo | Título grande que, al bajar, se queda pequeño y centrado sobre un desenfoque suave |
| Tarjetas y hojas planas | Tarjetas de «Tú» y hoja «Más» de cristal |

Las letras siguen en Outfit, la interfaz sigue oscura y los iconos son los nuestros (Material), no los de Apple.

## Maquetas

1. `movil_cristal_inicio.jpg`: Inicio con la barra abierta y el mini reproductor encima.
2. `movil_cristal_bajando.jpg`: lo mismo tras bajar. El título queda pequeño, la barra recogida y el mini reproductor dentro.
3. `movil_cristal_musica.jpg`: la pestaña Música activa.
4. `movil_cristal_tu.jpg`: la página «Tú».
5. `movil_cristal_hoja.jpg`: la hoja de cristal «Más», que se abre manteniendo pulsado «Tú». La misma pieza sirve para las demás hojas.
6. `movil_cristal_B.jpg`: la variante B (pestañas sin nombre salvo la activa).
7. `movil_cristal_barras.jpg`: las 4 barras (A o B, con Buscar aparte o dentro), abierta y recogida, y la versión **sin desenfoque**.
8. `comparar_cristal.jpg`: la propuesta anterior al lado de la nueva.
9. `ordenador_cristal.jpg`: nota para la web en el ordenador.

## Las dos barras

- **A · todas con nombre.** Cada pestaña lleva el icono y el nombre pequeño debajo; la activa, además, va en la píldora de cristal. **La recomiendo**: en la familia nadie tiene que adivinar qué es cada icono, y es lo que hacen Música, Podcasts y TV de Apple.
- **B · solo icono.** La activa es una píldora con el icono y su nombre, y las demás solo el icono. Queda más limpia y más «Apple», pero obliga a recordar los iconos (Descubrir no se entiende por el icono).

## Para que decidas (3)

1. **Barra A o B.** Recomiendo **A**.
2. **Buscar aparte (botón redondo) o dentro de la barra.** Recomiendo **aparte**: queda a mano del pulgar, la barra solo tiene 4 pestañas y Buscar sigue visible cuando la barra se recoge.
3. **Recoger la barra al bajar o dejarla siempre abierta.** Recomiendo **recogerla**: se ve más contenido y es lo que pide el mini reproductor dentro de la barra. Si a alguien le molesta, se podría añadir un ajuste para dejarla abierta.

## Cómo hacerlo

**La base ya existe.** `GlassCapability` (`lib/util/idiom/glass_capability.dart`) elige el nivel de cristal (`liquid`, `frost`, `sheen` o `solid`) según el aparato y la opción **Calidad del cristal** (auto, completa o reducida). El paquete de diseño (`packages/design`: `GlassSurface`, `glass_recipe.dart`) ya usa `liquid_glass_widgets` 1.6.0 con un ajuste automático que baja la calidad si el aparato va justo. No hace falta inventar el cristal; hay que usarlo en la barra.

- **Archivos:** `lib/ui/widgets/bottom_nav/*` y `navigation_layout.dart`.
  - Un estilo nuevo para la barra, o rehacer `dock_bar.dart`: cápsula flotante, píldora activa con el borde degradado y el botón de Buscar aparte.
  - `bottom_mini_player.dart` pasa a ser el accesorio, con dos estados: encima de la barra o dentro de ella.
  - `bottom_nav_controller.dart` escucha el desplazamiento (`ScrollNotification` de la página activa) para recoger o abrir la barra.
  - `bottom_nav_metrics.dart` calcula el margen de abajo del contenido según el estado de la barra.
  - La hoja nueva sale de `bottom_nav_sheet.dart`, y la página «Tú» sustituye a `bottom_navbar_hub_sheet.dart`, como ya estaba previsto.
  - Los textos nuevos («Más», «Tú», «Cambiar de persona»…) van en `app_es.arb` y `app_en.arb`.
- **Receta del cristal**, la de las maquetas:
  - un `BackdropFilter` con desenfoque de sigma 10–12 y saturación (más vivo que el gris de ahora);
  - un relleno blanco del 4–14 % de arriba abajo;
  - un borde de 1 px con degradado de blanco (más fuerte arriba a la izquierda y abajo a la derecha);
  - un brillo radial arriba a la izquierda;
  - una textura de grano muy suave (una imagen pequeña repetida, no un shader);
  - en la pestaña activa, el borde en el degradado de kOS.
  - El efecto de refracción y la deformación de los bordes de Apple solo los daría `liquid_glass_widgets` en el nivel `liquid`. No compensan en Android: se imitan con el borde y el brillo.
- **Rendimiento:** lo que cuesta es **cada capa de desenfoque**, no el dibujo.
  - Abiertas hay 3 piezas (barra, Buscar y mini reproductor) y recogidas otras 3. Tienen que ir **en un solo grupo** (`BackdropGroup`/`BackdropFilter.grouped`, o el render del paquete), con un único paso de desenfoque y en cápsulas pequeñas.
  - En un Android de gama media con Impeller (Vulkan) esto debería quedar holgado a 60 fps. Hay que medirlo en un móvil de la familia con el modo de perfil, desplazando Inicio y Música.
  - El desenfoque de la cabecera al bajar es una capa más y la más grande. Si va justa, se cambia por un degradado oscuro sin desenfoque.
- **Sin desenfoque (alternativa):** es el nivel `sheen`, que ya existe. Lleva el mismo borde, brillo y grano sobre un fondo casi opaco (~90 %) y **cuesta lo mismo que la barra de hoy**. Se usa:
  - en la **web**: `GlassCapability` ya pone `sheen` en web porque el desenfoque de CanvasKit da tirones. **En el iPhone, por la web, se verá así**, salvo que se pruebe a activar el desenfoque solo en la barra;
  - con la Calidad del cristal en «reducida»;
  - si el ajuste automático detecta que el aparato va justo.

  Se ve en `movil_cristal_barras.jpg`, abajo.
- **Legibilidad:** igual que hace Apple, la capa de tinte se oscurece un poco cuando lo que pasa por debajo es muy claro, y los nombres inactivos van al 78 % de blanco, no más tenues.
- **La tele no cambia:** sigue la barra A aprobada, con el cristal que ya tiene (`sheen` por defecto en las teles; con el mando no hay desplazamiento que recoja nada).
- **Web en el ordenador** (`ordenador_cristal.jpg`): se aprovechan dos cosas, con desenfoque o sin él según cómo vaya:
  - la barra de pestañas de arriba (tele A) metida en **la misma cápsula de cristal flotante**, con la píldora activa y el borde degradado;
  - el **mini reproductor** como cápsula de cristal abajo a la derecha.

  En una ventana estrecha o en el iPhone se usa la barra de abajo del móvil.

Fuentes: [Apple WWDC25 · Novedades en UIKit/SwiftUI: barras de pestañas](https://developer.apple.com/videos/play/wwdc2025/284/), [Donny Wals · barras de pestañas en iOS 26](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/), [Create with Swift · accesorio de la barra](https://www.createwithswift.com/enhancing-the-tab-bar-with-a-bottom-accessory/), [Create with Swift · recoger la barra al desplazarse](https://www.createwithswift.com/making-the-tab-bar-collapse-while-scrolling/), [Flutter · coste del desenfoque en Impeller (#148493)](https://github.com/flutter/flutter/issues/148493).
