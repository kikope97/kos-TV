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
- **Norma: todo lo que se añade a la versión de la tele tiene que quedar igual de
  logrado en la versión móvil y en la web** (la de Docker, `docs/web.md`), y
  verse bien en todos los diseños (barra de arriba, lateral y, en el móvil, la
  barra de abajo; sobre todo el diseño por defecto). No basta con que funcione:
  adaptado a cada pantalla (táctil, ratón, mando) y probado en las tres, con
  fotos de cada una cuando se enseñe. Lo único que puede quedarse solo en la
  tele es lo que no tiene sentido fuera de ella (por ejemplo, la fila de
  aplicaciones instaladas), y hay que decirlo al terminar.

## Revisión semanal del proyecto principal y del complemento

kOS TV parte de Moonfin-Core (`upstream` en git) y usa el complemento oficial
del servidor (Moonbase, `Moonfin-Client/Plugin`), que mantienen ellos. Una vez
a la semana se revisa qué han cambiado. El registro está en
`docs/revision-semanal.md`.

- **Cuándo:** al empezar a hablar con el usuario, mira la fecha de la última
  revisión en ese registro. Si han pasado 7 días o más (o no hay ninguna),
  pregúntale si la hacemos ahora. No la hagas sin preguntar, y no lo repitas
  más de una vez por conversación si dice que no.
- **La app:** `git fetch upstream` y repasa los commits de `upstream/main`
  desde el último revisado. Sepáralos en: merece la pena traer (arreglos del
  reproductor, fallos, rendimiento, seguridad, mejoras que encajen con la
  familia), no aplica (Plex, Emby, Silo, escritorio, Seerr, Firebase y todo lo
  que ya quitamos) y dudoso. Propón qué integrar y no integres nada sin el
  visto bueno del usuario. Lo que se integre cumple todas las normas de este
  archivo (español, nada de Moonfin a la vista, tele, móvil y web).
- **El complemento, con especial cuidado:** mira las versiones nuevas de su
  `manifest.json` y sus commits. Compara con las rutas `/Moonfin/...` que usa
  la app y señala lo que cambia o desaparece (puede romper la app), lo nuevo
  que se pueda aprovechar y si conviene actualizarlo en el servidor o esperar.
  Si una versión rompe algo sin arreglo fácil, se vuelve a la anterior o, como
  último recurso, se copia el complemento y lo mantenemos nosotros.
- **Desde dónde:** empieza siempre justo donde terminó la anterior (la tabla
  «Dónde estamos ahora» del registro: último commit de upstream y versión del
  complemento revisados). Nunca des por revisado algo que no esté apuntado.
- **Al terminar, apúntalo siempre** en el registro con el bloque que hay allí:
  qué rango de upstream y qué versiones del complemento se revisaron, qué se
  integró (con nuestro commit), qué se descartó y por qué, lo pendiente y la
  decisión sobre el complemento; y actualiza «Dónde estamos ahora». También si
  no se integra nada o el usuario la pospone. Es el historial de dónde venimos:
  solo se añade, no se borra ni se reescribe lo anterior.

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
