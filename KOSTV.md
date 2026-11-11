# kOS TV

kOS TV es un cliente de Jellyfin para la familia, centrado en Android TV, basado en
[Moonfin Core](https://github.com/Moonfin-Client/Moonfin-Core) (GPL-2.0 o
posterior). Este repositorio conserva el historial completo de Moonfin; a partir
de aquí evoluciona por su cuenta y Moonfin queda como referencia.

Para traer un arreglo concreto de Moonfin en el futuro:

```bash
git remote add upstream https://github.com/Moonfin-Client/Moonfin-Core.git
git fetch upstream main
git cherry-pick <commit>
```

## Cambios respecto a Moonfin

| Qué | Dónde | Estado |
|---|---|---|
| Identificador Android `com.kikope.kostv` (beta: `com.kikope.kostv.beta`) y nombre visible "kOS TV" | `android/app/build.gradle.kts` | Hecho |
| La propia app no aparece como reproductor externo | `lib/playback/external_player_service.dart` | Hecho |
| Firebase y notificaciones push desactivados (eran del proyecto de Moonfin) | `android/app/build.gradle.kts`, `lib/data/services/push_messaging_service.dart` | Hecho |
| Actualizaciones desde las releases de `kikope97/kos-TV`, con descarga e instalación dentro de la app (también en la tele) | `lib/data/services/app_update_service.dart`, `lib/ui/widgets/app_update_*.dart`, `UpdateInstaller.kt` | Hecho |
| Publicación de versiones desde GitHub (solo Android) con la versión como única fuente | `.github/workflows/build.yml`, `scripts/kostv_set_version.sh` | Hecho |
| APK firmados con la clave propia (secretos `ANDROID_*` del repositorio), comprobado en el certificado del APK | `.github/workflows/build.yml` | Hecho |
| Archivos generados con el prefijo `KosTV_` | `build-android.sh` | Hecho |
| Servidor de casa integrado: el primer arranque abre directamente el usuario y la contraseña, sin pedir dirección. La dirección viene del secreto `KOSTV_SERVER_URL` y no está en el código. No hay forma de cambiar de servidor: sin "Seleccionar servidor" en el menú de usuario ni en "¿Quién está viendo?", sin la línea del servidor bajo cada perfil, y cerrar sesión, el Atrás del inicio de sesión o cualquier otro camino a la lista de servidores llevan a los usuarios del servidor de casa (`kostv_household_server.dart`); si no se alcanza, al aviso con "Reintentar" del arranque, nunca a añadir otro servidor. En Ajustes > Cuenta tampoco está la sección "Servidores" (ordenar servidores, certificados autofirmados y de cliente) | `lib/util/kostv_server.dart`, `startup_screen.dart`, `build-android.sh`, `build.yml` | Hecho |
| Workflows que publican fuera (AUR, winget, Pages…) desactivados | `.github/workflows-disabled/` | Hecho |
| Sin versiones de escritorio (Windows, Linux, macOS): carpetas, scripts y trabajos de CI | — | Hecho |
| Sin Plex ni Emby: paquetes `server_/playback_` de ambos, `ServerType.emby/plex`, inicio de sesión con Plex y Emby Connect, búsqueda de Plex en la red, Moonbase para Plex, pantallas de administración solo de Emby y avisos de Emby Premiere | `packages/server_core`, `lib/`, `test/` | Hecho |
| Marca kOS TV (propuesta B, monograma "kO"): logotipo vectorial con fuente Outfit, animación de apertura de unos 3 s, icono adaptativo, banner de Android TV. Guía, propuestas y generador de iconos en [`docs/marca/`](docs/marca/README.md) | `lib/ui/widgets/kos_logo.dart`, `kos_intro.dart`, `startup_screen.dart`, `android/app/src/main/res/` | Hecho |
| Solo español e inglés, y en español aunque la tele esté en otro idioma (se puede cambiar en Ajustes > General). Traducción española completa y revisada (de tú, español de España) | `lib/l10n/`, `current_app_localizations.dart`, `UserPreferences.languageOverride` | Hecho |
| Sin Moonfin a la vista: textos, nombre que ve el servidor ("kOS TV para Android TV"…), perfiles de dispositivo, carpetas (`Descargas/KosTV`), animación de carga (el anillo), temas y paletas con los colores de la marca, web (título, carga, iconos, manifiesto), iOS y Apple TV (nombre, permisos en español, iconos y estantería superior). "Moonbase" se llama "complemento del servidor" | `lib/`, `android/`, `web/`, `ios/`, `tvos/` | Hecho |
| "Acerca de" apunta a este repositorio (código, licencia y [política de privacidad](PRIVACY_POLICY.md) propia); fuera las fichas de incidencias, Discord y donativos de Moonfin, su `CONTRIBUTING.md` y sus plantillas de incidencias | `about_category_screen.dart`, `PRIVACY_POLICY.md` | Hecho |
| Aplicaciones de la tele: fila "Aplicaciones" en Inicio (debajo del banner; mantener OK o tecla de menú para abrir, mover o quitar) y pantalla "Todas las aplicaciones" (botón en la barra y al final de la fila; añadir a Inicio, ajustes de la tele). La app Ajustes del sistema no sale en la lista (ya está la tarjeta "Ajustes de la tele"). Al moverse por "Todas las aplicaciones", el fondo toma el color de la app enfocada (sacado de su banner: Jellyfin azul, Netflix rojo…) y la luz sigue a su columna; la tarjeta brilla en ese color y las tarjetas entran en cascada al abrir. Solo en tele; interruptores en Ajustes > Inicio y Ajustes > Navegación | `InstalledApps.kt`, `installed_apps_service.dart`, `home_screen.dart`, `all_apps_screen.dart`, `app_tile.dart`, `app_accent_color.dart`, `apps_ambient_background.dart` | Hecho |
| APK de prueba encima de la última versión publicada (`X.Y.Z-prueba.N`) y código de versión ×100 para dejar sitio a las pruebas | `scripts/kostv_set_version.sh`, `build.yml` | Hecho |
| Sin asistente inicial: al iniciar sesión se entra directo a Inicio con el aspecto por defecto. El asistente queda en Ajustes > Apariencia > Personalización > "Personalizar el aspecto", solo con los pasos de diseño (sin el resumen final ni la oferta del complemento del servidor). Reloj de 24 horas por defecto | `setup_wizard_gate.dart` (`runAfterSignIn`, `includeTour`), `appearance_screen.dart` | Hecho |
| Descubrir (servicio de peticiones, Stremfin): botón en la barra con lo más visto y lo nuevo de Netflix, Disney+, Prime Video y de todas juntas, en cuatro filas (series y películas). Lo que hay en el servidor sale en color y abre su ficha; lo demás, en gris, con insignias de temporada nueva, "Falta la T3", "Llega pronto" y "Pedida". Solo aparece si la compilación lleva el secreto `KOSTV_REQUESTS_URL` y el servicio deja entrar a esa persona (`/me`); nunca cierra la sesión. Pedir llegará en la siguiente parte. En la tele (barra de arriba o lateral), en el móvil (barra de arriba, o pestaña de la barra de abajo y menú "Tú") y en la web | `lib/data/services/stremfin/`, `lib/ui/screens/discover/`, `lib/preference/bottom_nav_tabs.dart` | Hecho |
| Versión web en Docker (`ghcr.io/kikope97/kos-tv-web`), publicada con cada versión y cada prueba; `latest` es siempre la última imagen compilada. La imagen no lleva direcciones: el contenedor las recibe en `KOSTV_SERVER_URL` y `KOSTV_REQUESTS_URL`, escribe con ellas el `config.json` de la app y hace de pasarela a Stremfin en `/stremfin` (sin CORS). Panel de administración en `/admin` (de momento en blanco) con usuario y contraseña de `KOSTV_ADMIN_USER` y `KOSTV_ADMIN_PASSWORD`. Compose de ejemplo en `docker/compose.example.yml` y `docker/.env.example`. Guía en [`docs/web.md`](docs/web.md) | `docker/`, `lib/util/kostv_server.dart`, `web_runtime_config_model.dart`, `build.yml` | Hecho |
| Sin "Integraciones" en Ajustes: la configuración de Seerr, los ajustes del calendario y la entrada a los logros (lo técnico es cosa del administrador, que lo llevará el panel de admin). Fuera también sus textos y el código que solo usaban (64 textos, `checkMoonfinStatus`, `setBlockNsfw`). Los logros se abren desde su aviso | `settings_side_panel.dart`, `settings_search_index.dart` | Hecho |
| Sin Seerr (peticiones de Jellyseerr/Overseerr): fuera sus pantallas, filas y carruseles de Inicio, la pestaña de la barra inferior, los botones de pedir y lista de seguimiento, las insignias de estado, las fichas de títulos que no están en el servidor, las notificaciones y sus ajustes, con sus textos (más de 130) y tests. Lo de fuera de la biblioteca (listas de TMDB, calendario de Radarr/Sonarr) abre la ficha si el servidor lo tiene y si no avisa de que aún no está. Las peticiones son cosa de Descubrir (Stremfin) | `lib/ui/util/outside_library_title.dart` y lo que tocaba Seerr | Hecho |
| Intro en vídeo: el vídeo de apertura tal cual (4K, con sonido; en el móvil solo suena si el teléfono tiene el sonido de llamadas y avisos activado, en la web sin sonido). Mientras dura se cargan Inicio y lo primero de Descubrir, y Inicio aprovecha esa carga sin repetirla. Sale solo al abrir la app de verdad: la primera vez, después de salir a propósito (Atrás en Inicio y Salir, o el salvapantallas) o tras más de 6 horas sin verla; no al volver del segundo plano, aunque la tele la haya cerrado para hacer sitio a otra app, ni al cambiar de usuario (entonces, el logotipo un momento). Cualquier tecla o toque la salta; si el aparato no puede reproducirlo, sale la animación dibujada | `assets/intro/kostv_intro.mp4`, `kos_intro_video.dart`, `startup_screen.dart`, `kostv_intro_policy.dart`, `MainActivity.kt` (`introSoundAllowed`) | Hecho |
| Sin Silo | — | Pendiente (ver abajo) |

Un servidor Emby ya no se reconoce: la búsqueda de servidores lo descarta y al
escribir su dirección se informa de que no hay un servidor compatible.

Lo que aún se llama Moonfin es interno y nadie lo ve, y se mantiene a propósito:
el nombre del paquete Dart (`moonfin`, en los `import`), el namespace de Android
(`org.moonfin.androidtv`), los canales nativos, el esquema de enlaces
`moonfin://` (lo usan las invitaciones de Ver juntos que genera el complemento) y
las rutas `/Moonfin/...` del complemento del servidor, que son las suyas y no se
pueden cambiar desde la app. El reconocimiento a Moonfin queda en este archivo,
el README y la licencia.

## Publicar una versión

1. GitHub → **Actions** → **Build All Platforms** → **Run workflow**.
2. En **release_version** escribe la versión nueva, por ejemplo `1.0.1` (siempre
   mayor que la anterior, con la forma `X.Y.Z`). El resto de opciones da igual:
   una publicación compila solo Android.
3. **Run workflow**. Unos 25 minutos después aparece la release `Kos TV 1.0.1`
   con `KosTV_AndroidTV_v1.0.1.apk` y `KosTV_Android_v1.0.1.apk`.

Desde ahí, cada app lo ve al abrirse o al volver a primer plano (como mucho cada
6 horas) y ofrece **Actualizar ahora**: descarga el APK y abre el instalador del
sistema. La primera vez pide permiso para instalar apps. La tele usa el APK
`*AndroidTV*` y el móvil el otro; nunca se cruzan.

La versión sale de lo que se escribe al publicar (`scripts/kostv_set_version.sh`):
el número interno que compara Android es `MAJOR*1000000 + MINOR*1000 + PATCH`.
El `pubspec.yaml` del repositorio se queda en `0.1.0`, así que cualquier APK que
no sea una release cuenta como más antiguo y también se actualiza.

Una publicación necesita el secreto `KOSTV_SERVER_URL` (la dirección del
servidor de casa, con `https://`): sin él, la compilación falla a propósito. Se
inyecta en la app al compilar con `--dart-define`, así que no aparece en el
repositorio y en los registros de GitHub sale tapada. Ojo: quien descargue el
APK y lo desmonte sí podría leerla, porque la app la necesita para conectarse.

Si se pierde la clave de firma (`kostv-release.jks` y su contraseña), los APK
nuevos ya no se podrán instalar encima: habría que desinstalar en cada aparato.

## Pendiente

- **Quitar Silo.** Está muy entrelazado con "Ver juntos" (Watch Party): la
  pantalla y el gestor de salas, que también usa Moonbase con Jellyfin, viven en
  archivos `silo_*` y usan los modelos de sala de `packages/server_silo`
  (`SiloRoom`, `SiloRoomAccess`, `SiloRoomSuggestion`…). Hay que sacar esos
  modelos a la app antes de borrar los paquetes `server_silo` y `playback_silo`.
- **Restos de Emby en el panel de administración.** `library_options_form.dart`
  y `admin_user_edit_screen.dart` conservan filas solo de Emby tras un
  `_emby => false`; se pueden borrar con calma.
- **Color de acento.** El tema por defecto ("kOS TV") sigue usando el azul de
  Jellyfin (`#00A4DC`) para el foco, las barras y las insignias. Pasarlo al
  cian/violeta de la marca pide revisar el contraste del texto blanco encima
  (el cian `#4FD8FF` es muy claro) y verlo en la tele antes de decidir.
- **Textos escritos en inglés dentro del código.** Algunas pantallas (sobre todo
  de ajustes avanzados y administración) llevan textos fijos en inglés en vez de
  usar `lib/l10n`, así que salen en inglés aunque la app esté en español. Los
  del inicio ya están; quedan sobre todo en listas externas
  (`external_lists_screen.dart`), filas del inicio en Ajustes, diagnóstico,
  juegos, reproductores de audio y edición de metadatos. Hay que pasarlos a
  `app_en.arb`/`app_es.arb` poco a poco.
- **kOS TV como inicio de la tele.** Declararla como pantalla de inicio
  (HOME) y una guía en Ajustes que detecte si la tele es Google TV (allí hace
  falta un servicio de accesibilidad que intercepte el botón de inicio) o
  Android TV clásico (basta con elegirla como predeterminada). Al hacer de
  inicio: la animación solo al encender y que Atrás en Inicio no pregunte si
  salir.
- **Fila de aplicaciones como sección de Inicio.** Ahora es una fila fija
  debajo del banner; pasarla a `HomeSectionType` permitiría moverla entre las
  demás filas (ver el mapa en el historial: sincronización con el complemento,
  modo infantil y los `switch` sobre `HomeSectionType`).
- **Apple TV.** Cambiar el bundle id (y los de la extensión Top Shelf y el App
  Group) cuando se aborde tvOS.
