# kOS TV — notas para Claude

- Responde siempre en español.
- kOS TV es un cliente de Jellyfin para la familia, centrado en Android TV,
  basado en Moonfin (Flutter). Lee `KOSTV.md` para saber qué se ha cambiado
  respecto a Moonfin y qué queda pendiente.
- La app va en español por defecto y solo trae español e inglés. Todo texto
  nuevo va en `lib/l10n/app_en.arb` y `lib/l10n/app_es.arb` (español de España,
  de tú), nunca escrito a mano en el código.
- Nada de "Moonfin" ni "Moonbase" a la vista de quien usa la app: se llama
  **kOS TV** y el complemento es "el complemento del servidor". La marca (colores,
  logotipo, iconos) está en `docs/marca/README.md`.

## Publicar una versión

Publica tú las versiones: el usuario no entra en GitHub a hacerlo.

**Publica solo cuando el usuario diga expresamente que publiques una versión
nueva.** Nunca por tu cuenta al terminar un cambio, aunque funcione: cada versión
llega a las teles de toda la familia. Terminar algo es subirlo a la rama; publicar
es otra cosa y la decide el usuario.

1. Mira la última release (`get_latest_release` de `kikope97/kos-TV`) y elige la
   siguiente versión `X.Y.Z`: sube PATCH para arreglos y MINOR para novedades.
   Tiene que ser mayor que la anterior.
2. Lanza el workflow con la herramienta de GitHub `actions_run_trigger`:
   `method: run_workflow`, `workflow_id: build.yml`, `ref:` la rama con el
   trabajo terminado y subido, `inputs: {"release_version": "X.Y.Z"}`.
3. Espera a que termine (unos 25 minutos) y comprueba que la release
   `Kos TV X.Y.Z` existe y tiene `KosTV_AndroidTV_vX.Y.Z.apk` y
   `KosTV_Android_vX.Y.Z.apk`, y que el trabajo `web-image` subió la imagen
   web (`ghcr.io/kikope97/kos-tv-web:X.Y.Z` y `:latest`, ver `docs/web.md`).
   Si falla, lee el registro del trabajo y arréglalo.
4. Dile al usuario qué versión salió y qué trae. Las apps la ofrecen solas
   (al abrirse o al volver a primer plano, como mucho cada 6 horas).

## APK de prueba

Si el usuario pide un APK para probar (sin decir que publiques una versión),
lanza `build.yml` con `inputs: {"test_apk": "true"}`. Sale como *pre-release*
`kOS TV · prueba N` con los dos APK, y la imagen web como
`ghcr.io/kikope97/kos-tv-web:prueba-N` (y `:prueba` y `:latest`: `latest` es
siempre la última imagen compilada, también en las pruebas). Las apps no la ofrecen como actualización
(solo leen la última versión publicada). Lleva la versión de la última
publicada más `-prueba.N`, así que se instala encima de ella y la siguiente
versión publicada se instala encima de la prueba. Dale el enlace directo al APK
de la tele:
`https://github.com/kikope97/kos-TV/releases/download/prueba-N/KosTV_AndroidTV_prueba.apk`.

No cambies a mano la versión del `pubspec.yaml` (se queda en `0.1.0`): la fija
`scripts/kostv_set_version.sh` al compilar, a partir de `release_version` o, en
las pruebas, de la última versión publicada. El código de versión de Android es
`(MAJOR*1000000 + MINOR*1000 + PATCH) * 100`, más N en las pruebas; la 1.0.0 se
publicó con el esquema anterior (1000000) y todos los nuevos son mayores.

## Firma

Los APK se firman con la clave guardada en los secretos `ANDROID_*` del
repositorio. Nunca subas un keystore ni contraseñas al repositorio, que es
público. Si cambia la clave, las apps instaladas no podrán actualizarse sin
desinstalarlas.
