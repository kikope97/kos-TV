# Actualizaciones de la app por nuestro servidor

## Decisiones del usuario (2026-11-22) — mandan sobre el plan de abajo

- **La familia se actualiza solo por el complemento.** La app **no consulta GitHub** en absoluto (sin respaldo ni importación desde GitHub).
- **GitHub queda como canal beta del dueño:** sigue compilando APK que él instala a mano para probar. Misma firma, así que se instalan encima.
- **Versión «puente»:** la última publicada por GitHub como versión normal; las apps actuales la cogen solas y desde ella solo miran el complemento.
- **Panel del complemento, apartado «Actualizaciones de la app»:** crear una actualización subiendo el APK de la tele y el del móvil con unas notas; el **número de versión se lee del propio APK** (versionName/versionCode); aviso si es menor que la última o si un APK va en el hueco equivocado; **firma comprobada** (la primera fija la huella; otra firma se rechaza); subida por trozos; **«Guardar las últimas N versiones»** (10 por defecto; las viejas se borran solas; un aparato muy atrasado salta a la última); **«Retirar»** una versión (deja de ofrecerse).
- **Solo Android** (iOS irá por TestFlight; la web, por Docker Compose).
- **Aparatos nuevos:** el panel da un enlace o QR temporal para descargar el APK desde el servidor.


Fecha: 2026-11-22. Es solo un plan: no se ha tocado nada del repositorio.

---

## Contrato app ↔ complemento (2026-11-22)

Todo bajo `/Moonfin/Kostv/Update`, con la sesión de Jellyfin de la persona (cabecera de token de siempre).

- `GET /Moonfin/Kostv/Update?kind=tv|phone&versionCode=<N>` → `200` con `{ "Available": true, "VersionName": "1.21.0", "VersionCode": 102100000, "Notes": "…", "Date": "2026-11-23T10:00:00Z", "Size": 125000000, "Sha256": "<hex>", "Url": "/Moonfin/Kostv/Update/Download/<id>/<kind>.apk" }` si hay una versión publicada, no retirada y mayor que `N`; si no, `200` con `{ "Available": false }`. `400` si `kind` no vale. Un complemento sin esto responde `404`: la app entonces no ofrece nada.
- `GET <Url>` (relativa al servidor) → el APK (`application/vnd.android.package-archive`), con `Range`/`206`, `Content-Length` y `ETag`; misma cabecera de token. `404` si se retiró o borró entretanto.
- La app comprueba `Sha256` y que el APK esté firmado con el mismo certificado que la app instalada antes de abrir el instalador.
- Cuándo pregunta la app: como ahora (al abrir y al volver a primer plano, como mucho cada 6 h; nunca durante la apertura ni reproduciendo). Ninguna llamada a GitHub.
- Enlace temporal para aparatos nuevos (no lo usa la app): `GET /Moonfin/Kostv/Update/Install/<token>/<kind>.apk`, sin sesión, válido 30 min, generado en el panel.

## En pocas palabras (para leer primero)

**Qué pasa hoy.** Cada versión se compila en GitHub, que la firma con la clave de
kOS TV y la publica. Las teles y los móviles le preguntan a GitHub cada 6 horas
si hay algo nuevo, se lo bajan de allí y lo instalan. El complemento del
servidor y la web también salen de GitHub. Si GitHub desaparece mañana, las apps
se quedan sin actualizaciones y nadie nuevo puede instalarlas.

**Qué proponemos.** Que las actualizaciones lleguen por **el complemento del
servidor**, que ya está en el Jellyfin de casa y con el que todas las apps hablan
siempre. Tú compilas la versión en tu Mac con un solo comando, el comando la sube
al complemento, y las apps la ven y se la bajan **de tu servidor**. El catálogo
del complemento y la web también pasan a servirse desde tu servidor.

**Cómo, sin dejar a nadie tirado.** Por pasos, y con GitHub funcionando en
paralelo mientras tanto:

1. Una versión nueva del complemento que sabe guardar y repartir las
   actualizaciones (con una pestaña nueva, «Actualizaciones», en su página de
   ajustes).
2. Una versión «puente» de la app, publicada todavía por GitHub, que ya pregunta
   primero al complemento y, si no contesta, a GitHub como siempre.
3. Durante unas semanas cada versión sale por los dos sitios. La pestaña del
   complemento enseña qué versión tiene cada aparato de casa.
4. Cuando todos los aparatos lleven la versión puente, GitHub deja de hacer
   falta. Las versiones antiguas de GitHub **no se borran** (por si aparece una
   tele que llevaba meses apagada).

**Lo más importante antes de empezar: la clave de firma.** Las apps solo se
actualizan encima si la versión nueva va firmada con **la misma clave** de
siempre (el archivo `kostv-release.jks` y sus contraseñas). Ahora esa clave está
guardada en GitHub, y **GitHub no deja volver a leerla**. Para compilar en el Mac
necesitas el archivo original. Si no lo tienes, hay una forma de recuperarlo
(sección 6.2), pero hay que hacerla **antes de apagar nada**. Sin la clave, cada
aparato tendría que desinstalar y volver a instalar la app (y perdería sus datos).

**Lo que tienes que decidir** (detalle en la sección 8):

1. Dónde está la clave de firma y hacer dos copias seguras. *Recomendado: lo
   primero de todo.*
2. Cómo se instala la app en un aparato nuevo sin el enlace de GitHub.
   *Recomendado: un código corto o un QR que genera la pestaña del complemento y
   caduca a los 30 minutos.*
3. Quién recibe las versiones de prueba. *Recomendado: solo los usuarios que
   marques en la pestaña (por ejemplo, el tuyo).*
4. Cuándo se apaga GitHub. *Recomendado: cuando todos los aparatos lleven 4
   semanas en la versión puente o una posterior; sin borrar las publicaciones
   antiguas.*

**Cuánto trabajo es.** Unos 6 a 8 días de trabajo repartidos en fases, más unas
4 a 8 semanas de calendario con las dos vías funcionando a la vez (sección 9).

**Tele, móvil y web.** Actualizarse solas solo tiene sentido en las apps de
Android (tele y móvil): la web se pone al día al recargar la página y en el
iPhone actualiza TestFlight. La pestaña nueva es parte del panel de Jellyfin,
así que se usa desde el navegador (ratón o táctil).

---

## 1. Cómo funcionan las actualizaciones hoy, de principio a fin

### 1.1 Publicar (GitHub)

- `.github/workflows/build.yml`, lanzado a mano con `release_version: X.Y.Z`
  (o `test_apk: true` para una prueba).
  - `plan` + paso `versions`: lee `GET /repos/<repo>/releases/latest` y exige que
    la versión sea la siguiente PATCH, MINOR o MAJOR (salvo
    `skip_version_check`). Para una prueba, cuenta las publicaciones
    `prueba-*` posteriores a la última versión y saca `N` (1 a 99).
  - `release-checks`: analizador + pruebas en 3 tandas. Si falla, no se publica.
  - `android` (matriz `mobile` y `tv`): monta la clave desde los secretos
    `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_TYPE`, `ANDROID_STORE_PASSWORD`,
    `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (en `android/app/release.keystore`
    + `android/keystore.properties`, ambos en `android/.gitignore`), pone
    `KOSTV_REQUIRE_RELEASE_SIGNING=true` (Gradle se para si no hay clave, ver
    `android/app/build.gradle*`), fija la versión con
    `scripts/kostv_set_version.sh`, exige el secreto `KOSTV_SERVER_URL` (el
    servidor de casa va dentro del APK con `--dart-define`), compila con
    `build-android.sh mobile|tv` (`DISTRIBUTION_CHANNEL=apk` o
    `android_tv_apk`, y `MOONFIN_FORCE_TV=true` en la tele) y comprueba la firma
    con `scripts/ci/check-apk-signature.sh` (no puede ser la clave de depuración
    y, si existe la variable `KOSTV_SIGNING_SHA256`, tiene que ser exactamente
    ese certificado).
  - `release`: borrador con `KosTV_AndroidTV_vX.Y.Z.apk`, `KosTV_Android_vX.Y.Z.apk`
    y sus copias sin versión (`KosTV_AndroidTV.apk`, `KosTV_Android.apk`); solo
    se publica como «la última» cuando están los cuatro. Así el enlace fijo
    `…/releases/latest/download/KosTV_AndroidTV.apk` nunca apunta a una
    publicación a medias.
  - `test-release`: pre-publicación `prueba-N` con `KosTV_AndroidTV_prueba.apk`
    y el del móvil.
  - `web-image`: compila la web (`--wasm --no-web-resources-cdn` + fuentes) y
    sube `ghcr.io/<dueño>/kos-tv-web:X.Y.Z` (o `prueba`, `prueba-N`) y `:latest`,
    para amd64 y arm64.

### 1.2 Versión y código de versión

- `scripts/kostv_set_version.sh X.Y.Z [N]`: escribe en `pubspec.yaml`
  `version: X.Y.Z+CODE` (y `android_tv_version` / `android_tv_build_number`).
- `CODE = (MAJOR*1000000 + MINOR*1000 + PATCH) * 100`; una prueba es
  `X.Y.Z-prueba.N` con `CODE + N` (N de 1 a 99). Límites: MAJOR < 21, el resto
  < 1000. La 1.0.0 usó el esquema viejo (1000000) y todas las nuevas son mayores.
- El `pubspec.yaml` del repositorio se queda en `0.1.0`, así que cualquier
  compilación que no sea una publicación cuenta como más antigua.
- Ojo para el Mac: el script usa `sed -i -E` sin sufijo, que **falla con el sed
  de macOS** (BSD). Hay que cambiarlo (perl, o `sed -i ''` según el sistema).
  Lo mismo en `scripts/fetch-web-fonts.sh` (`sed -i`).

### 1.3 Comprobar y descargar (la app)

- `lib/data/services/app_update_service.dart` (`AppUpdateService`):
  - Solo si `AppDistribution.supportsInAppUpdates` (`lib/util/app_distribution.dart`:
    canales `apk` y `android_tv_apk`) y si no la instaló una tienda
    (`_storeInstallerPackages`: Play, Amazon, Samsung, F-Droid…).
  - Respeta la preferencia `updateNotificationsEnabled` (se sincroniza con el
    complemento, `synced_fields.dart`) en la comprobación automática.
  - Pregunta sin autenticar a `api.github.com/repos/<repo>/releases/latest`
    (User-Agent `KosTVUpdateChecker/1.0`, 10 s de espera).
  - Cada cuánto: como mucho cada **6 horas** desde la última respuesta; tras un
    fallo (sin red al despertar la tele) se reintenta a los **5 minutos**; un
    403/429 (límite de GitHub) cuenta como respuesta. Una versión rechazada
    (Cancelar, descarga fallida) se vuelve a ofrecer a las **24 horas**.
  - Compara solo `X.Y.Z` (quita la `v` y lo que va tras `-` o `+`). Por eso una
    prueba `1.19.0-prueba.3` recibe la siguiente versión normal, y **las pruebas
    nunca se ofrecen como actualización** (además `/releases/latest` no ve
    pre-publicaciones).
  - Tele o móvil (`androidApkFor`): la tele coge el APK cuyo nombre contiene
    `androidtv`; el móvil, el otro. Comparten identificador de aplicación, así
    que cruzarlos sustituiría una por otra: nunca se cruzan. Si la publicación
    aún no tiene su APK, no se ofrece.
  - Toma de GitHub el tamaño y el SHA-256 (`digest: sha256:…`) de cada archivo.
- `lib/ui/widgets/app_update_banner.dart` (`AppUpdateBanner`, montado en
  `lib/app.dart`): comprueba al arrancar y al volver a primer plano, nunca
  durante la apertura ni con algo reproduciéndose (lo guarda para cuando se
  cierre el reproductor), y reintenta tras un fallo.
- `lib/ui/widgets/app_update_dialog.dart`:
  - `canInstallUpdateInApp`: Android, enlace **https** y ruta que acaba en
    **`.apk`**. Si no, solo abre el enlace en el navegador (en el móvil).
  - `_downloadTo`: descarga con `HttpClient` **sin cabeceras** (no manda token),
    calcula el SHA-256 mientras baja, comprueba longitud, tamaño y SHA-256; si no
    cuadra, lo borra y dice «descarga dañada». Se corta si pasan 30 s sin datos.
  - Pide el permiso de instalar apps la primera vez y abre el instalador.
  - «Notas de la versión» abre la página de GitHub (no en la tele).
  - Al arrancar, borra el APK que quedó de la vez anterior.
- `android/app/src/main/kotlin/org/moonfin/androidtv/UpdateInstaller.kt` +
  `MainActivity.kt` (canal `org.moonfin.androidtv/platform`: `updateDownloadPath`,
  `canInstallPackages`, `openInstallPermissionSettings`, `installApk`): guarda
  el APK en la caché (`updates/kostv-update.apk`) y lo pasa al instalador con un
  `FileProvider`.
- **Comprobación de la firma:** la app **no** la comprueba; lo hace Android al
  instalar (si la firma no coincide, el instalador da error y no instala). Lo
  único que protege antes es el SHA-256 que da GitHub.
- **Modo infantil / control parental:** no hay nada específico en el
  actualizador; el aviso sale con cualquier perfil (también en modo infantil).
- **Web:** no tiene actualizador (no aparece el aviso). Se pone al día al
  recargar (nginx sirve con `Cache-Control: no-cache`); la imagen se actualiza a
  mano con `docker compose pull && docker compose up -d` (`docs/web.md`).

### 1.4 El complemento hoy

- `.github/workflows/complemento.yml` (versión `X.Y.Z.N` + novedades): pruebas,
  `complemento/compilar.sh`, `Jellyfin/tools/abi-check/comprobar.sh` (10.10.0,
  10.10.7, 10.11.11, 12.4.0), `complemento/catalogo.py` (añade la versión con su
  md5 y `sourceUrl`), pre-publicación `complemento-X.Y.Z.N` con el zip, y sube
  `manifest.json` + `logo.png` a la publicación fija `complemento`.
- Jellyfin lee el catálogo de
  `https://github.com/<repo>/releases/download/complemento/manifest.json`
  (también escrito en `complemento/kostv.json`: `catalog` e `imageUrl`).

### 1.5 Lo que depende de GitHub (y se tiene que poder quitar)

| Qué | Dónde |
|---|---|
| Comprobar si hay versión | `api.github.com …/releases/latest` en `app_update_service.dart` |
| Descargar el APK | `browser_download_url` de GitHub |
| Instalar en un aparato nuevo | enlace fijo `…/releases/latest/download/KosTV_AndroidTV.apk` |
| Compilar y firmar | `build.yml` + secretos `ANDROID_*` y `KOSTV_SERVER_URL` |
| Notas de la versión | página de la publicación en GitHub |
| Catálogo del complemento | publicación `complemento` (manifest, zip, logo) |
| Imagen web | `ghcr.io` |
| Pruebas antes de publicar | `release-checks` en GitHub |

---

## 2. El complemento como servidor de actualizaciones

Todo en una carpeta nueva `complemento/Jellyfin/backend/Kostv/` (por ejemplo
`KostvUpdates.cs`, `KostvUpdatesStore.cs`, `KostvApkSignature.cs`,
`KostvUpdatesController.cs`, `KostvInstallController.cs`), con sus pruebas en
`Jellyfin/tests/Moonfin.Server.Tests/`.

### 2.1 Canales

Cuatro canales: `tv` y `movil`, cada uno `estable` y `prueba`. Nunca se cruzan
(la tele solo recibe `tv`, el móvil solo `movil`), igual que hoy.

### 2.2 Dónde se guardan los APK

- Carpeta `kostv-actualizaciones/` dentro de `MoonfinPlugin.Instance.DataFolderPath`
  (o una ruta que se elija en la pestaña, para no meter 1-2 GB en las copias de
  seguridad de Jellyfin):

  ```
  kostv-actualizaciones/
    indice.json                 # todas las versiones y cuál es la actual de cada canal
    tv/estable/1.20.0/KosTV_AndroidTV_v1.20.0.apk
    movil/estable/1.20.0/KosTV_Android_v1.20.0.apk
    tv/prueba/1.20.0-prueba.2/KosTV_AndroidTV_v1.20.0-prueba.2.apk
    temporal/                   # subidas a medias
  ```

- `indice.json`, por versión: `Version`, `VersionCode`, `Canal`, `Pista`
  (`estable`/`prueba`), `Tamano`, `Sha256`, `FirmaSha256` (huella del
  certificado), `Notas` (texto en español), `Publicada` (UTC), `Commit`
  (opcional), `Retirada` (sí/no). Y por canal, `Actual` (la que se ofrece).
- Se conservan las **últimas N** de cada canal (5 estables y 3 pruebas por
  defecto, ajustable); al pasar de ahí se borran las más viejas, nunca la actual.
  Espacio: unos 120 MB por APK, así que 2 canales × 5 ≈ 1,2 GB.
- Escritura segura: se escribe en `temporal/`, se comprueba y se mueve; el
  índice se escribe en un archivo nuevo y se renombra (como el resto de archivos
  `kostv-*.json` del complemento).

### 2.3 Cómo llegan los APK al complemento

Dos formas, las dos solo para administradores (`[Authorize(Policy = "RequiresElevation")]`,
que ya usa el complemento):

1. **Subirlos** (lo normal, desde el script del Mac o desde la pestaña).
   Por trozos, para que no lo corten los límites del proxy inverso (Nginx Proxy
   Manager suele limitar el tamaño de lo que se sube) ni el de Kestrel:
   - `POST /Moonfin/Kostv/Update/Upload` con `{ Canal, Pista, Version, VersionCode, Tamano, Sha256, Notas }` → `{ UploadId }`.
   - `PUT /Moonfin/Kostv/Update/Upload/{id}?offset=…` con trozos de 8 MB
     (`[RequestSizeLimit(16 MB)]`); se puede reanudar si se corta.
   - `POST /Moonfin/Kostv/Update/Upload/{id}/Finish`: comprueba tamaño y SHA-256,
     que sea un APK, su firma (2.6) y que el `VersionCode` sea mayor que el
     último del canal; si todo está bien, lo publica. Si no, lo borra y explica
     por qué (en español).
   - Las subidas a medias se borran a las 24 horas.
2. **Traerlos de una dirección** (para la transición): en la pestaña, «Traer
   las versiones de GitHub» (o de cualquier dirección). Una tarea programada del
   complemento mira cada hora la última publicación de GitHub, baja los dos APK
   con su SHA-256 y los publica igual que una subida (mismas comprobaciones). Así,
   mientras GitHub siga compilando, el complemento tiene siempre la última sin
   hacer nada. Se apaga con un interruptor cuando GitHub deje de usarse.

### 2.4 Rutas para las apps

Todas con la sesión normal de Jellyfin (`[Authorize]` y
`this.GetUserIdFromClaims()`, como `KostvHomeController`), así que valen igual
dentro de casa y desde fuera, por la misma dirección con la que la app ya habla
con Jellyfin.

- `GET /Moonfin/Kostv/Update?canal=tv&version=1.19.0&code=101900000`
  → la versión actual del canal para quien pregunta:

  ```json
  {
    "Available": true,
    "Version": "1.20.0",
    "VersionCode": 102000000,
    "Size": 125829120,
    "Sha256": "…",
    "SignerSha256": "…",
    "Notes": "Qué trae, en español",
    "Published": "2026-12-01T18:00:00Z",
    "Download": "/Moonfin/Kostv/Update/Download/tv/1.20.0/KosTV_AndroidTV_v1.20.0.apk"
  }
  ```

  - La pista de prueba solo se da a los usuarios marcados en la pestaña (decisión
    3); a los demás, solo la estable.
  - Compara por `VersionCode` (no solo `X.Y.Z`), así una prueba recibe la
    siguiente prueba o la siguiente versión, y una versión retirada no se ofrece.
  - Apunta (en memoria y en un registro pequeño) qué aparato preguntó y con qué
    versión, para la lista de la pestaña (2.7).
- `GET /Moonfin/Kostv/Update/Download/{canal}/{version}/{archivo}.apk`
  → `PhysicalFile(…, "application/vnd.android.package-archive", enableRangeProcessing: true)`
  (como ya hace `EmulatorController`), con `ETag` y `Content-Length`. Así se
  puede reanudar una descarga cortada. Acaba en `.apk`, que es lo que pide hoy
  `canInstallUpdateInApp`. Solo da archivos que estén en el índice (nada de
  rutas inventadas: se comprueba el nombre exacto, sin `..`).
- `/Moonfin/Ping` añade `kostvUpdates: true` (como `kostvHome`, `kostvMyList`…),
  para que la app sepa que este complemento ya reparte versiones.

### 2.5 Instalar en un aparato nuevo (sin sesión)

Un aparato nuevo aún no tiene la app, así que no tiene sesión de Jellyfin.

- En la pestaña, botón **«Enlace para instalar»** (tele o móvil): crea un código
  corto (6 letras y números, sin confusiones tipo 0/O) que vale **30 minutos y
  3 descargas**, y enseña:
  - la dirección corta `https://jellyfin.ejemplo.com/Moonfin/Kostv/Install/ABC123`
    (fácil de escribir en la app «Downloader» de la tele);
  - un **QR** con esa misma dirección (para el móvil). El QR se dibuja en la
    página con un generador pequeño incrustado (JavaScript sin dependencias
    externas, dentro de `configPage.html`), sin pedir nada a internet.
- `GET /Moonfin/Kostv/Install/{codigo}` (anónima, `[AllowAnonymous]`): si el
  código es válido, responde con una redirección a
  `/Moonfin/Kostv/Install/{codigo}/KosTV_AndroidTV.apk` (nombre que acaba en
  `.apk`, que algunos navegadores de tele necesitan) y sirve la versión estable
  actual de ese canal. Códigos en memoria; un código malo cuenta para un límite
  (por ejemplo 10 fallos por minuto y dirección) para que no se puedan adivinar.
- Opcional (decisión 2): un **enlace fijo** con un secreto largo
  (`/Moonfin/Kostv/Install/fijo/<32 caracteres>/KosTV_AndroidTV.apk`) que
  sustituye al de GitHub para la familia, con un botón «Cambiar enlace» que
  invalida el anterior. Ojo: el APK lleva dentro la dirección del servidor
  (ya está apuntado en `KOSTV.md`), y un enlace fijo público la deja al alcance
  de cualquiera que lo tenga.

### 2.6 La firma: nunca aceptar otra clave

- En la pestaña se guarda la **huella SHA-256 del certificado** de kOS TV (la
  misma que `KOSTV_SIGNING_SHA256`). Si no está puesta, la toma del primer APK
  que se sube y la enseña para confirmarla; cambiarla luego pide escribir la
  huella nueva a mano y avisa en rojo de que las apps instaladas no podrán
  actualizarse con ella.
- Al terminar cada subida, el complemento lee la firma del APK (el bloque de
  firma APK v2/v3, el formato es público y se lee en unas 150 líneas de C# sin
  librerías) y compara la huella. Si no es la nuestra, o es la de depuración
  (`CN=Android Debug`), lo rechaza. Prueba con un APK pequeño firmado con una
  clave de prueba (nunca con la nuestra).
- Además se comprueba en el script del Mac (`apksigner`, como hoy) y en la app
  antes de instalar (3.3). Y al final Android también lo exige. Cuatro
  comprobaciones: si una falla, las demás lo paran.

### 2.7 La pestaña «Actualizaciones» (en español)

Nueva sección en `Pages/configPage.html` (un botón más en la barra lateral, con
el mismo estilo que «Direcciones»):

- Por canal (Tele / Móvil, Estable / Prueba): la versión actual, las guardadas,
  con fecha, tamaño, notas y botones **«Ofrecer esta»** (volver a una anterior
  como actual) y **«Retirar»** (deja de ofrecerse).
- **«Subir versión»**: elegir el APK, canal, pista, versión y notas; sube por
  trozos con la sesión del panel (`ApiClient.accessToken()`) y barra de progreso.
- **«Traer de GitHub»**: interruptor y dirección (2.3).
- **Huella de la firma** (2.6) y **cuántas guardar**.
- **Quién recibe las pruebas**: lista de usuarios de Jellyfin con casilla.
- **Aparatos de casa**: cada aparato que ha preguntado (nombre, usuario, tele o
  móvil, versión, última vez), para saber cuándo no queda nadie atrás. Se puede
  completar con la lista de aparatos de Jellyfin (que guarda el nombre y la
  versión de cada app), leída por nombre como hace `UserReflection` con lo que
  cambia entre versiones.
- **Enlace para instalar** (2.5).
- Todo con la marca kOS TV, sin «Moonfin».

### 2.8 Volver atrás (rollback)

- Android **no deja instalar un código de versión menor** encima sin
  desinstalar. Así que «volver atrás» en el complemento significa **dejar de
  ofrecer** la versión mala («Retirar», o «Ofrecer esta» con la anterior): los
  aparatos que aún no la tenían se quedan donde están.
- Para los que ya la tienen: se publica una versión nueva (`X.Y.Z+1`) compilada
  desde el commit bueno. El script del Mac lo hace igual que una versión normal.

### 2.9 Que funcione con cada Jellyfin (10.10, 10.11, 12.4)

- Solo usa ASP.NET Core (controladores, `PhysicalFile`, `RequestSizeLimit`),
  `System.IO`, `System.Security.Cryptography` y la carpeta de datos del
  complemento: nada de lo que Jellyfin cambió entre versiones.
- La lista de aparatos de Jellyfin (`IDeviceManager`) sí ha cambiado de forma
  entre versiones: se lee por nombre (reflexión) y, si no se puede, la pestaña
  enseña solo lo que el complemento ha apuntado él mismo.
- Pasa `complemento/Jellyfin/tools/abi-check/comprobar.sh` (10.10.0, 10.10.7,
  10.11.11, 12.4.0), como siempre.
- Kestrel limita por defecto lo que se sube a unos 30 MB: por eso los trozos de
  8 MB (no hace falta `DisableRequestSizeLimit` en la subida).

---

## 3. Cambios en la app

### 3.1 Preguntar primero al complemento

- `AppUpdateService` pasa a tener dos fuentes:
  - **Complemento** (primero): si hay sesión iniciada y el `Ping` dijo
    `kostvUpdates`, `GET /Moonfin/Kostv/Update` con `moonbaseEndpoint()` (base y
    cabecera `Authorization: MediaBrowser … Token=…`, como
    `kostv_collections.dart`). Manda canal (`tv`/`movil` según
    `AppDistribution.channel`), versión y código (`PackageInfo.buildNumber`).
  - **GitHub** (respaldo, durante la transición): lo de hoy, sin cambios, si el
    complemento no contesta, contesta 404 (complemento antiguo) o no hay sesión
    (app recién instalada sin iniciar sesión). Con una constante para apagarlo
    del todo en una versión posterior.
- Si las dos contestan, manda el complemento (es lo que tú controlas). Una
  versión retirada en el complemento no se ofrece aunque GitHub la tenga.
- Comparar por **código de versión** cuando la fuente lo da (el complemento sí),
  para que funcione la pista de prueba; con GitHub, como hoy (`X.Y.Z`).
- Frecuencia: el complemento no tiene límite como GitHub, así que se puede
  bajar a **1 hora** (y mantener el reintento a 5 minutos tras un fallo). La
  regla de no molestar (no en la apertura, no mientras se ve algo) y la de
  volver a ofrecer a las 24 horas se quedan igual.
- `DesktopUpdateInfo` gana `headers` (la cabecera de la sesión), `notes` (texto)
  y `signerSha256`.

### 3.2 Descargar

- `_downloadTo` manda las cabeceras de la sesión cuando la descarga es del
  complemento (a GitHub, nada).
- `canInstallUpdateInApp`: además de https, aceptar `http` **solo** si es la
  misma dirección del servidor con la que la app ya habla (por si alguien usa
  la dirección de casa sin https). La protección real la dan el SHA-256 y la
  firma (3.3).
- Reanudar con `Range` si se corta (lo permite la ruta de descarga). Opcional,
  pero útil en la tele por wifi.

### 3.3 Comprobar la firma en la app antes de instalar

Nuevo método en `UpdateInstaller.kt`, `checkApk(path)`:
`packageManager.getPackageArchiveInfo(path, GET_SIGNING_CERTIFICATES)` (y
`GET_SIGNATURES` en Android anterior a 9), y comparar con la app instalada:

- el mismo nombre de paquete;
- **el mismo certificado** (huella SHA-256 igual a la de la app instalada y, si
  el complemento la dio, a `SignerSha256`);
- código de versión mayor que el instalado.

Si algo no cuadra, no se abre el instalador y sale un mensaje («Esta
actualización no es de kOS TV» / «ya tienes esta versión»). Esto mejora también
las descargas de GitHub.

### 3.4 Notas de la versión

El diálogo enseña las notas del complemento dentro de la app (en la tele
también: hoy no hay forma de leerlas allí). Con GitHub, como hoy. Textos nuevos
en `lib/l10n/app_en.arb` y `lib/l10n/app_es.arb`.

### 3.5 Modo infantil

Hoy el aviso sale también en modo infantil. Propuesta: en modo infantil no se
ofrece (el niño no debería decidir ni ver el instalador); se ofrece al salir del
modo infantil o en otro perfil. Instalar sin que nadie pulse nada no es posible
con una app que se instala a mano (Android pide confirmar), así que no se
plantea.

### 3.6 Primer arranque y aparatos nuevos

- Un aparato nuevo se instala con el código o el QR (2.5). El enlace fijo de
  GitHub sigue funcionando mientras GitHub exista; cuando se apague, se cambia
  en las instrucciones de la familia por el código/QR (o el enlace fijo propio,
  decisión 2).
- Una app recién instalada y sin sesión pregunta a GitHub mientras exista; sin
  GitHub, se actualiza en cuanto se inicia sesión (que es lo primero que se hace).

### 3.7 Tele, móvil y web

- Tele y móvil: el mismo cambio para los dos; el diálogo ya se maneja con mando
  y con el dedo. Probar en los dos (y fotos de cada uno al enseñarlo).
- Web: no lleva actualizador (se actualiza sola al recargar). Es lo que «no
  tiene sentido fuera» de Android, y hay que decirlo al terminar.
- iPhone: lo actualiza TestFlight; el actualizador ya no se activa en
  `ios_signed`.

---

## 4. El catálogo del complemento sin GitHub

El problema: Jellyfin necesita un catálogo (`manifest.json`) para instalar y
actualizar el complemento, y el complemento **no puede instalarse a sí mismo la
primera vez**.

### Opciones

| Opción | Cómo | A favor | En contra |
|---|---|---|---|
| A. El contenedor de la web | Carpeta del servidor montada en el contenedor (`./complemento:/usr/share/nginx/html/complemento:ro`) y una `location /complemento/` en `docker/web/nginx.conf`. Catálogo en `https://kostv.ejemplo.com/complemento/manifest.json` | Independiente del complemento: si una versión del complemento falla, el catálogo sigue ahí para arreglarlo. Ya tienes el contenedor | Depende de que el contenedor esté arrancado |
| B. Una carpeta estática del servidor | Cualquier servidor web que ya tengas (o el propio Nginx Proxy Manager con una ubicación estática) | Lo más simple | Una cosa más que mantener |
| C. El propio complemento | `GET /Moonfin/Kostv/Catalog/manifest.json` anónima; Jellyfin se lo lee a sí mismo (`http://localhost:8096/…`) | Nada aparte | Si una versión rompe el complemento, se pierde el catálogo justo cuando hace falta |

**Recomendación: A**, y C como posible extra más adelante. La primera
instalación en un servidor nuevo: añadir el catálogo A en **Panel >
Complementos > Repositorios** (o, a mano, descomprimir el zip en la carpeta de
complementos de Jellyfin y reiniciar).

Durante la transición, los dos catálogos a la vez (el de GitHub y el nuestro):
Jellyfin admite varios repositorios y, con el mismo identificador, se queda con
la versión más alta. Cuando todo funcione, se quita el de GitHub.

### Publicar el complemento en local

Script nuevo `complemento/publicar_local.sh X.Y.Z.N "novedades"`:

1. Comprueba que la versión es mayor que la última del catálogo.
2. `dotnet test` del complemento y `salvage-tests` (como `complemento.yml`).
3. `bash complemento/compilar.sh X.Y.Z.N` (zip y md5 en `complemento/salida/`).
4. `abi-check/comprobar.sh` con las cuatro versiones de Jellyfin (necesita el
   SDK de .NET 10 en el Mac).
5. `catalogo.py`, con un cambio: recibir la dirección base del catálogo
   (`--base https://kostv.ejemplo.com/complemento`) para `sourceUrl` e
   `imageUrl`, en vez de la de GitHub escrita en `kostv.json`.
6. Copia zip, `manifest.json` y `logo.png` a la carpeta del servidor (`rsync`
   por SSH) y comprueba con `curl` que el catálogo nuevo se lee y que el md5 del
   zip servido coincide.
7. Si sigue el espejo en GitHub, además lo sube allí con `gh release`.

La dirección del servidor y la carpeta van en un archivo de configuración del
Mac fuera del repositorio (por ejemplo `~/.kostv/publicar.env`), nunca en el
repositorio.

---

## 5. La imagen web sin GitHub

Hoy: `ghcr.io/<dueño>/kos-tv-web:latest`, que el servidor baja a mano.

Opciones:

1. **Compilarla en el Mac y llevarla al servidor**: `flutter build web --wasm
   --release --no-web-resources-cdn`, las fuentes, `docker buildx build
   --platform linux/amd64 -f docker/web/Dockerfile -t kostv-web:X.Y.Z --load .`
   (el Mac es ARM; como el Dockerfile solo copia archivos sobre nginx, no hace
   falta emular nada pesado) y `docker save kostv-web:X.Y.Z | ssh servidor
   docker load`. En el `compose.yml`, `image: kostv-web:latest` con
   `pull_policy: never`. En Portainer, «Update the stack» **sin** «Re-pull».
2. **Los archivos de la web en una carpeta del servidor**: el contenedor sigue
   siendo el mismo, pero la carpeta de la app (`/usr/share/nginx/html`) se
   monta desde el servidor. Publicar es copiar los archivos con `rsync`; no hay
   que reiniciar nada (nginx ya sirve con `no-cache`). Hay que cuidar los
   permisos (nginx va con el usuario 101) y los `.gz` precomprimidos que usa
   `gzip_static`.
3. Compilar en el servidor: haría falta Flutter en el servidor. No compensa.

**Recomendación:** seguir con `ghcr.io` hasta el final de la migración (es lo
último que depende de GitHub y lo menos crítico: la web no se queda
«atascada»); luego la opción 1, que no cambia cómo funciona el contenedor.

**`/admin`:** que enseñe la versión de la web que está sirviendo (un
`version.json` al compilar) y, si se quiere, un enlace a la pestaña
«Actualizaciones» del complemento. **No** recomiendo que `/admin` pueda lanzar
actualizaciones: el contenedor necesitaría acceso a Docker en el servidor, que
equivale a ser administrador de todo el servidor.

---

## 6. Compilar en el Mac

### 6.1 Un solo comando por versión

Script nuevo `scripts/kostv_publicar.sh X.Y.Z` (o `--prueba`):

1. Comprueba que el árbol está limpio y que la versión es la siguiente (pregunta
   al complemento cuál es la última; con `--saltar-comprobacion` como hoy).
2. Analizador y pruebas, con los mismos comandos que `release-checks`.
3. `scripts/kostv_set_version.sh X.Y.Z` (arreglado para el `sed` del Mac).
4. Monta la firma desde fuera del repositorio: el keystore en
   `~/.kostv/kostv-release.jks` y las contraseñas en el **Llavero** de macOS
   (`security find-generic-password …`), escribiendo
   `android/app/release.keystore` y `android/keystore.properties` solo durante
   la compilación (están en `android/.gitignore`) y borrándolos al terminar
   (también si falla). Con `KOSTV_REQUIRE_RELEASE_SIGNING=true`.
5. `KOSTV_SERVER_URL` desde `~/.kostv/publicar.env`.
6. `./build-android.sh mobile` y `./build-android.sh tv`.
7. `EXPECTED_SHA256=<huella> scripts/ci/check-apk-signature.sh KosTV_*.apk`.
8. SHA-256 de cada APK y subida por trozos al complemento (2.3), con una
   **clave de API de Jellyfin** de administrador (Panel > Claves de API)
   guardada en el Llavero.
9. Comprueba que `GET /Moonfin/Kostv/Update` devuelve la versión nueva para tele
   y móvil, y que lo descargado coincide con el SHA-256.
10. Deja `pubspec.yaml` como estaba (`git checkout pubspec.yaml`), crea la
    etiqueta local `X.Y.Z` y, mientras dure el espejo, sube la publicación a
    GitHub (`gh release create`, con los cuatro APK y como «la última»).
11. Opcional: la imagen web (sección 5).

Antes, una vez: comprobar que `build-android.sh` y `scripts/fetch-web-fonts.sh`
funcionan en macOS (bash 3.2 de serie, `sed` BSD); si hace falta, instalar
`bash` y `gnu-sed` con Homebrew o adaptar los scripts.

### 6.2 La clave de firma: el mayor riesgo

- Los secretos de GitHub **no se pueden volver a leer** desde la web ni con la
  API. Para firmar en el Mac hace falta **el archivo original**
  (`kostv-release.jks`), su tipo, el alias y las dos contraseñas.
- **Si lo tienes:** comprobar que es el bueno comparando su huella
  (`keytool -list -v -keystore kostv-release.jks -alias <alias>`, línea
  `SHA256:`) con la de un APK publicado (`apksigner verify --print-certs
  KosTV_AndroidTV.apk`). Guardar **dos copias** fuera del Mac (por ejemplo, un
  USB guardado en casa y un gestor de contraseñas con adjuntos) y las
  contraseñas en el gestor. Poner la huella en la variable `KOSTV_SIGNING_SHA256`
  y en la pestaña del complemento.
- **Si no lo tienes:** se puede recuperar **una sola vez** desde GitHub con un
  workflow de un solo uso que **cifra** el secreto con una clave pública tuya
  (por ejemplo con `age`) y lo deja como artefacto; lo descargas, lo descifras en
  el Mac y se borran el artefacto y el workflow. Cifrarlo es obligatorio: el
  repositorio es público y los artefactos los puede descargar cualquiera con
  cuenta de GitHub. Esto hay que hacerlo **antes** de desactivar nada en GitHub.
- **Si se pierde del todo:** no hay arreglo. Cada aparato tendría que
  desinstalar e instalar de nuevo (perdiendo descargas y ajustes que no estén en
  el complemento).

---

## 7. Orden de la migración (sin dejar a nadie tirado)

| Paso | Qué se hace | Qué se comprueba | Si sale mal |
|---|---|---|---|
| 0 | Localizar la clave (6.2), copias, huella en `KOSTV_SIGNING_SHA256` | La huella del archivo = la de un APK publicado | Recuperarla desde GitHub antes de seguir |
| 1 | Complemento nuevo (por ejemplo 3.1.1.2) con las rutas y la pestaña, **publicado aún por GitHub**. Activar «Traer de GitHub» | La pestaña enseña la última versión de GitHub en los dos canales; `GET /Moonfin/Kostv/Update` y la descarga funcionan desde casa y desde fuera; abi-check pasa | Instalar la versión anterior del complemento desde el catálogo; las apps no notan nada (aún no lo usan) |
| 2 | **Versión puente** de la app (por ejemplo 1.20.0) publicada por GitHub: pregunta al complemento, respaldo en GitHub, firma comprobada en la app, notas dentro | En tele y móvil: con el complemento apagado se actualiza por GitHub; encendido, por el complemento. Una prueba de prueba (APK firmado con otra clave) se rechaza | Retirar la 1.20.0 del complemento y publicar 1.20.1 por GitHub |
| 3 | Esperar a que **todos** los aparatos de la lista de la pestaña lleven ≥ 1.20.0 | Lista «Aparatos de casa» | Aparato rezagado: abrir la app en él, o reinstalar con el código/QR |
| 4 | Primera versión **compilada en el Mac** (`scripts/kostv_publicar.sh`), subida al complemento y **también** a GitHub como espejo | Las apps la reciben del complemento (registro de descargas); en GitHub queda igual que siempre | Retirarla en el complemento; GitHub sigue ofreciendo la anterior o la misma |
| 5 | Catálogo propio (sección 4) añadido en Jellyfin junto al de GitHub; la siguiente versión del complemento por los dos | Jellyfin ve la versión en los dos repositorios e instala la nuestra | Quitar el catálogo propio; sigue el de GitHub |
| 6 | Instalación de aparatos nuevos con el código/QR; cambiar las instrucciones de la familia | Instalar en un móvil y en una tele de prueba | Sigue valiendo el enlace de GitHub |
| 7 | Web en local (sección 5) | La web abre y `/admin` enseña la versión | Volver a `ghcr.io/…:latest` en el `compose.yml` |
| 8 | Tras **4 semanas** con todos ≥ puente: dejar de publicar en GitHub, quitar «Traer de GitHub», quitar el catálogo de GitHub de Jellyfin. Una versión posterior de la app apaga el respaldo de GitHub | Una versión entera publicada solo en local llega a todos | Volver a subir a GitHub con `gh release create` desde el Mac |
| 9 | Actualizar la documentación: `CLAUDE.md` («Publicar una versión», «Publicar el complemento», «APK de prueba»), `KOSTV.md`, `docs/web.md`, `complemento/README.md` | — | — |

Importante:

- **No borrar** las publicaciones de GitHub ni la última «latest»: una tele que
  lleve meses apagada aún preguntará a GitHub, subirá a la puente y desde ahí
  seguirá por el complemento.
- Mientras exista el espejo, la «latest» de GitHub tiene que ser siempre la
  misma versión (o una menor) que la estable del complemento, para que los dos
  caminos no ofrezcan cosas distintas.

---

## 8. Riesgos y decisiones

1. **La clave de firma.** Es lo único que no tiene arreglo si se pierde.
   *Recomendación:* paso 0 antes que nada; si no tienes el archivo original,
   recuperarlo cifrado desde GitHub (6.2); dos copias fuera del Mac.
2. **Cómo se instala en un aparato nuevo.** Código corto/QR que caduca, o enlace
   fijo propio. *Recomendación:* el código de 30 minutos y 3 descargas desde la
   pestaña (con QR para el móvil). Un enlace fijo solo si de verdad hace falta,
   con secreto largo y botón para cambiarlo, porque el APK lleva dentro la
   dirección del servidor.
3. **Quién recibe las pruebas.** Hoy nadie las recibe como actualización (se
   instalan a mano). *Recomendación:* por usuario, desde la pestaña (por ejemplo
   solo el tuyo); el resto de la familia, solo versiones estables.
4. **Cuándo se apaga GitHub (y qué queda allí).** *Recomendación:* cuando la
   lista de aparatos diga que todos llevan 4 semanas en la puente o posterior; la
   imagen web la última en salir; las publicaciones antiguas se quedan. (El
   código puede seguir en GitHub aunque la distribución salga de él.)

Otros riesgos a vigilar: el proxy inverso puede limitar subidas o descargas
grandes (por eso subida por trozos y descarga con `Range`); los APK ocupan
1-2 GB en el servidor (ruta configurable, fuera de las copias de seguridad de
Jellyfin si se quiere); una tele fuera de casa baja 120 MB por la subida de tu
conexión (normal en fibra).

---

## 9. Trabajo estimado por fase

| Fase | Qué | Esfuerzo |
|---|---|---|
| 0 | Clave: localizar, comprobar, copias (o recuperación cifrada) | 1-2 horas tuyas |
| 1 | Complemento: almacén, subida por trozos, firma APK v2/v3, rutas, código/QR, «Traer de GitHub», pestaña, pruebas, abi-check | 2,5-3 días |
| 2 | App: dos fuentes, cabeceras, comprobación de firma en Kotlin, notas, modo infantil, textos, pruebas; probar en tele y móvil | 1,5-2 días |
| 3 | Script del Mac (versión, firma desde el Llavero, compilar, comprobar, subir, espejo en GitHub) + arreglos de `sed` para macOS | 1 día, más ½ día tuyo preparando el Mac (Flutter, Android SDK, JDK 17, .NET 8 y 10) |
| 4 | Catálogo propio y `publicar_local.sh` del complemento | ½ día |
| 5 | Web en local y versión en `/admin` | ½-1 día |
| 6 | Convivencia con GitHub y apagado | 4-8 semanas de calendario, poco trabajo |
| 7 | Documentación | ½ día |

Total: unos **6 a 8 días de trabajo**, más el periodo de convivencia.
