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
   `KosTV_Android_vX.Y.Z.apk`. Si falla, lee el registro del trabajo y arréglalo.
4. Dile al usuario qué versión salió y qué trae. Las apps la ofrecen solas
   (al abrirse o al volver a primer plano, como mucho cada 6 horas).

No cambies a mano la versión del `pubspec.yaml` (se queda en `0.1.0`): la fija
`scripts/kostv_set_version.sh` a partir de `release_version` al compilar.

## Firma

Los APK se firman con la clave guardada en los secretos `ANDROID_*` del
repositorio. Nunca subas un keystore ni contraseñas al repositorio, que es
público. Si cambia la clave, las apps instaladas no podrán actualizarse sin
desinstalarlas.
