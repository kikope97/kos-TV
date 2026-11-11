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
| Servidor de casa integrado: el primer arranque abre directamente el usuario y la contraseña, sin pedir dirección. La dirección viene del secreto `KOSTV_SERVER_URL` y no está en el código | `lib/util/kostv_server.dart`, `startup_screen.dart`, `build-android.sh`, `build.yml` | Hecho |
| Workflows que publican fuera (AUR, winget, Pages…) desactivados | `.github/workflows-disabled/` | Hecho |
| Sin versiones de escritorio (Windows, Linux, macOS): carpetas, scripts y trabajos de CI | — | Hecho |
| Sin Plex ni Emby: paquetes `server_/playback_` de ambos, `ServerType.emby/plex`, inicio de sesión con Plex y Emby Connect, búsqueda de Plex en la red, Moonbase para Plex, pantallas de administración solo de Emby y avisos de Emby Premiere | `packages/server_core`, `lib/`, `test/` | Hecho |
| Marca kOS TV (propuesta B, monograma "kO"): logotipo vectorial con fuente Outfit, animación de apertura de unos 3 s, icono adaptativo, banner de Android TV. Guía, propuestas y generador de iconos en [`docs/marca/`](docs/marca/README.md) | `lib/ui/widgets/kos_logo.dart`, `kos_intro.dart`, `startup_screen.dart`, `android/app/src/main/res/` | Hecho |
| Solo español e inglés, y en español aunque la tele esté en otro idioma (se puede cambiar en Ajustes > General). Traducción española completa y revisada (de tú, español de España) | `lib/l10n/`, `current_app_localizations.dart`, `UserPreferences.languageOverride` | Hecho |
| Sin Moonfin a la vista: textos, nombre que ve el servidor ("kOS TV para Android TV"…), perfiles de dispositivo, carpetas (`Descargas/KosTV`), animación de carga (el anillo), temas y paletas con los colores de la marca, web (título, carga, iconos, manifiesto), iOS y Apple TV (nombre, permisos en español, iconos y estantería superior). "Moonbase" se llama "complemento del servidor" | `lib/`, `android/`, `web/`, `ios/`, `tvos/` | Hecho |
| "Acerca de" apunta a este repositorio (código, licencia y [política de privacidad](PRIVACY_POLICY.md) propia); fuera las fichas de incidencias, Discord y donativos de Moonfin, su `CONTRIBUTING.md` y sus plantillas de incidencias | `about_category_screen.dart`, `PRIVACY_POLICY.md` | Hecho |
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
- **Apple TV.** Cambiar el bundle id (y los de la extensión Top Shelf y el App
  Group) cuando se aborde tvOS.
