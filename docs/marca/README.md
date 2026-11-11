# Marca de kOS TV

Todo lo que define cómo se ve kOS TV, para tenerlo claro cuando se cambie algo.

## De dónde sale

La marca parte de la intro **«kOS TV — Intro Power 4K»**
([`intro-power-4k.html`](intro-power-4k.html), ábrela en el navegador): el botón
de encendido se dibuja, se pulsa y su anillo se convierte en la **O** de «kOS».

Con esa idea se hicieron tres propuestas
([`propuestas.html`](propuestas.html)):

- **A · Encendido.** El botón de encendido completo como icono.
- **B · Monograma «kO».** La k y el anillo. **Es la elegida.**
- **C · Anillo.** Solo el anillo con el cometa.

## Nombre

**kOS TV**: k minúscula, OS en mayúsculas y TV aparte. En el código y en los
archivos, donde no caben espacios, `KosTV` (por ejemplo `KosTV_AndroidTV_v1.0.0.apk`).

## Logotipo

Apilado: «kOS» en Outfit Bold, con el anillo en lugar de la O, y debajo «TV»
en Outfit Light, más pequeño (0,3 del tamaño de «kOS»), espaciado y con el
degradado. En la app es `KosLogo` (`lib/ui/widgets/kos_logo.dart`).

- **El anillo.** Ocupa el sitio de la O: su borde exterior mide lo que la altura
  de las mayúsculas más el desbordamiento de una O (0,728 del cuerpo de letra) y
  su grosor es el trazo de Outfit Bold (0,118).
- **El cometa.** Es un trazo blanco corto con brillo cian que recorre el anillo
  (`paintKosRing`).
- **La marca sola.** Donde no cabe el logotipo, va el anillo solo (`KosRingMark`):
  en la animación de carga y en el botón de salir de Administración.

## Colores

| Nombre | Hex | Uso |
|---|---|---|
| Cian | `#4FD8FF` | Inicio del degradado, brillo del cometa |
| Violeta | `#8F6BFF` | Centro del degradado (al 55 %) |
| Rosa | `#FF5CCF` | Final del degradado |
| Tinta | `#F3F5FA` | Letras sobre negro |
| Negro | `#000000` | Fondo de la intro, la web y el icono |

El degradado del anillo va en diagonal, de abajo a la izquierda (cian) a arriba
a la derecha (rosa). El de «TV» va de izquierda a derecha. En código son
`KosBrand.cyan`, `.violet`, `.pink` e `.ink`.

## Tipografía

[Outfit](https://fonts.google.com/specimen/Outfit) (SIL Open Font License),
en `assets/fonts/`: ExtraLight (200), Light (300) y Bold (700).

## Animación de apertura

Unos 3 segundos, sin sonido, en cada arranque (`KosIntro`,
`lib/ui/widgets/kos_intro.dart`):

1. **0–0,7 s.** Se dibuja el botón de encendido: el arco con un hueco arriba y la
   barra que baja.
2. **0,82 s.** Se pulsa: destello, dos ondas (cian y violeta) y un haz vertical.
   El arco se cierra y la barra se recoge.
3. **1–1,75 s.** El anillo viaja del centro a su sitio en la O mientras engorda
   hasta el grosor de las letras.
4. **1,48–2,7 s.** Entran la k (por la derecha), la S y «TV» (por la izquierda).
5. **Desde 1,9 s.** El cometa empieza a girar y sigue mientras la pantalla esté.

Con las animaciones del sistema desactivadas se muestra el logotipo final sin
animación.

Capturas en [`capturas/`](capturas/).

## Iconos

| Dónde | Qué lleva | Archivos |
|---|---|---|
| Android (adaptativo) | «kO» al 90 % dentro de la zona segura de 66 dp, sobre fondo azul noche | `android/app/src/main/res/mipmap-*/ic_launcher_{foreground,background}.png` |
| Android (clásico) | El mismo, recortado con esquinas redondeadas | `mipmap-*/ic_launcher.png` |
| Android TV (banner) | Icono y «kOS TV» en línea, 320×180 dp | `drawable-xhdpi/kostv_tv_banner.png` |
| iPhone y iPad | «kO» a sangre, sin transparencia | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` |
| Apple TV | Capa trasera con el fondo y capa delantera con el logotipo apilado, para el efecto de paralaje; y las imágenes de la estantería superior | `tvos/Runner/Assets.xcassets/AppIcon.brandassets/` |
| Web | Iconos normal y *maskable* y favicon; pantalla de carga con el anillo y el cometa | `web/icons/`, `web/favicon.png`, `web/index.html` |

Para regenerarlos, con Node y Playwright, desde esta carpeta:

```sh
cd docs/marca/iconos
node render.js render.html ../../../android/app/src/main/res
node render_apple_web.js apple_web.html ../../..
```

`render.html` y `apple_web.html` tienen el dibujo (SVG y CSS). Si cambia el
logotipo, se cambia ahí y se vuelven a generar todos.
