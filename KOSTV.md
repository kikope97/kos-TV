# Kos TV

Kos TV es un cliente de Jellyfin para la familia, centrado en Android TV, basado en
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
| Identificador Android `com.kikope.kostv` (beta: `com.kikope.kostv.beta`) y nombre visible "Kos TV" | `android/app/build.gradle.kts` | Hecho |
| La propia app no aparece como reproductor externo | `lib/playback/external_player_service.dart` | Hecho |
| Firebase y notificaciones push desactivados (eran del proyecto de Moonfin) | `android/app/build.gradle.kts`, `lib/data/services/push_messaging_service.dart` | Hecho |
| Comprobador de actualizaciones conservado pero sin consultar a Moonfin | `lib/data/services/app_update_service.dart` (`_releaseRepo`) | Hecho |
| Workflows que publican fuera (AUR, winget, Pages…) desactivados | `.github/workflows-disabled/` | Hecho |

El namespace interno de Android (`org.moonfin.androidtv`) y los nombres de los
canales nativos se mantienen a propósito: son internos y cambiarlos solo añade
riesgo.

## Pendiente

- **Clave de firma propia para el APK.** Sin ella, CI firma con una clave de
  depuración distinta en cada build y una versión nueva no se puede instalar
  encima de la anterior. Hay que crear un keystore y guardarlo como secretos del
  repositorio (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_TYPE`,
  `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`).
- **Actualizaciones desde nuestras releases.** Cuando se publique la primera
  release, poner `_releaseRepo = 'kikope97/kos-TV'`. El APK de Android TV debe
  llevar "tv" en el nombre (el script ya genera `Moonfin_AndroidTV_v*.apk`).
- **Marca.** Icono, logotipos y textos que aún dicen "Moonfin" dentro de la app,
  y el nombre de los archivos generados (`APP_NAME` en `build-android.sh`).
- **Apple TV.** Cambiar el bundle id (y los de la extensión Top Shelf y el App
  Group) cuando se aborde tvOS.
