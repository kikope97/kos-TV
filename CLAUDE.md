# kOS TV — notas para Claude

- Responde siempre en español.
- kOS TV es un cliente de Jellyfin para la familia, centrado en Android TV,
  basado en Moonfin (Flutter). Lee `KOSTV.md` para saber qué se ha cambiado
  respecto a Moonfin y qué queda pendiente.
- La app va en español por defecto y solo trae español e inglés. Todo texto
  nuevo va en `lib/l10n/app_en.arb` y `lib/l10n/app_es.arb` (español de España,
  de tú), nunca escrito a mano en el código.
- Nada de "Moonfin" ni "Moonbase" a la vista de quien usa la app: se llama
  **kOS TV** y el complemento es "el complemento del servidor". Lo mismo en lo
  que el complemento enseña en el panel de Jellyfin (se llama «kOS TV»); por
  dentro sigue con nombres del oficial (rutas `/Moonfin/...`, `Moonfin.Server`),
  que no se tocan. La marca (colores, logotipo, iconos) está en
  `docs/marca/README.md`.
- **Norma: todo lo que se añade a la versión de la tele tiene que quedar igual de
  logrado en la versión móvil y en la web** (la de Docker, `docs/web.md`), y
  verse bien en todos los diseños (barra de arriba, lateral y, en el móvil, la
  barra de abajo; sobre todo el diseño por defecto). No basta con que funcione:
  adaptado a cada pantalla (táctil, ratón, mando) y probado en las tres, con
  fotos de cada una cuando se enseñe. Lo único que puede quedarse solo en la
  tele es lo que no tiene sentido fuera de ella (por ejemplo, la fila de
  aplicaciones instaladas), y hay que decirlo al terminar.

## Revisión semanal del proyecto principal y del complemento

kOS TV parte de Moonfin-Core (`upstream` en git) y tiene su propio complemento
del servidor en `complemento/`: nuestra copia de Moonbase, el oficial
(`Moonfin-Client/plugin`), traída con `git subtree` (ver
`complemento/README.md`). Una vez a la semana se revisa qué han cambiado los
dos originales. El registro está en `docs/revision-semanal.md`.

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
- **El complemento, con especial cuidado:** mira las versiones nuevas del
  oficial (su `manifest.json`, sus etiquetas y commits; de Jellyfin solo, lo de
  Emby, Plex y Silo no aplica). Compara con las rutas `/Moonfin/...` que usa la
  app y señala lo que cambia o desaparece (puede romper la app) y lo nuevo que
  se pueda aprovechar. Propón si traer esa versión a nuestra copia y no la
  traigas sin el visto bueno del usuario. Traerla es `git subtree pull` (ver
  `complemento/README.md`), conservando siempre lo nuestro: nombre «kOS TV»,
  su identificador, textos en español, imágenes y lo quitado; con sus pruebas
  pasando y una pasada a los textos nuevos que enseñen el nombre del oficial.
  Lo traído se publica como versión nueva del complemento (`X.Y.Z.1`), solo
  cuando el usuario lo diga (ver «Publicar el complemento»).
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

**«Haz una versión» y «haz el APK» quieren decir publicar una versión nueva**
(con estos pasos), no un APK de prueba. Si lo pide para cuando acabes algo,
publícala al terminarlo y probarlo.

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

## Publicar el complemento

El complemento del servidor (`complemento/`) se publica aparte de la app y con
su propia numeración: `X.Y.Z.N`, donde `X.Y.Z` es la versión oficial en la que
se basa y `N` la nuestra sobre ella (3.1.0.1, 3.1.0.2…; al traer la oficial
3.2.0, la 3.2.0.1). Tiene que ser mayor que la anterior.

**Publícalo solo cuando el usuario lo pida** («publica el complemento», «haz
una versión del complemento»). «Haz una versión» a secas es la app. Si un
cambio de la app necesita también el complemento, díselo y pregúntale.

1. Lanza el workflow con `actions_run_trigger`: `method: run_workflow`,
   `workflow_id: complemento.yml`, `ref:` la rama con el trabajo subido,
   `inputs: {"version": "X.Y.Z.N", "changelog": "qué trae, en español"}`.
2. Espera a que termine (unos minutos) y comprueba que existe la
   pre-publicación `Complemento kOS TV X.Y.Z.N` con
   `kOS-TV-complemento-X.Y.Z.N.zip`, y que el catálogo
   (`releases/download/complemento/manifest.json`) la lleva arriba.
3. Dile al usuario qué trae. Jellyfin la ofrece en **Panel > Complementos**
   (con las actualizaciones automáticas, se instala sola) y hay que reiniciar
   el servidor.

Nunca se marcan como «la última»: las apps buscan su actualización en la última
publicación normal. Sus etiquetas (`complemento-…`) no lanzan la compilación de
la app.

## APK de prueba

Solo si el usuario pide expresamente un APK **de prueba** (dicho así: «APK de
prueba», «una prueba»). «Haz el APK» a secas es publicar una versión (ver
arriba). Entonces lanza `build.yml` con `inputs: {"test_apk": "true"}`. Sale como *pre-release*
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
