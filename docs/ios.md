# App para iPhone y iPad

## Decisión (2026-11-21)

- La app de iOS (iPhone y iPad) se hará **en local, con el Mac del usuario**, no desde Claude en la nube.
- Se reparte **solo por TestFlight** (cuenta de desarrollador de Apple). Nada de App Store, Ad Hoc ni AltStore.
- Los APK de Android también se podrán compilar en ese Mac. La clave de firma (keystore) y sus contraseñas se quedan en el Mac o en los secretos de GitHub, **nunca en el repositorio** (es público).
- Antes de empezar: fases 0 a 2 del estudio de abajo (cuenta de Apple, dejar `ios/` como nuestro y que compile).

## Estudio de viabilidad

Fecha: 21-11-2026. Solo lectura: no se ha tocado nada del repositorio.

Cómo leerlo:
- **[código]**: comprobado en el repositorio (rutas al lado) o en GitHub Actions.
- **[Apple]**: lo que sé de las normas y precios de Apple. Cambian a menudo, así
  que hay que confirmarlo en developer.apple.com antes de decidir.

---

## 0. Resumen en cuatro líneas

1. La parte de iOS sigue entera: es la de Moonfin con el nombre, los iconos y
   los permisos cambiados, nada más. Desde que nos separamos no se ha compilado
   **nunca** para iPhone, y le faltan cosas básicas: el identificador y el
   equipo de firma siguen siendo los de Moonfin, el servidor de casa no va
   dentro, no hay versión ni forma de publicarla.
2. En el iPhone el vídeo y la música van con otro reproductor (AetherEngine,
   nativo de Apple), no con Media3 ni mpv. Casi todo lo nuestro está protegido
   con comprobaciones de plataforma y no debería romper, pero algunas cosas
   funcionarían peor o no funcionarían (más abajo).
3. Lo difícil no es programar, es **repartirla**: en iPhone no se puede instalar
   un archivo de GitHub y que se actualice sola. Hace falta la cuenta de
   desarrollador de Apple (de pago cada año) y TestFlight, o algo parecido.
4. Recomendación: de momento, **la web en el iPhone como «app» en la pantalla de
   inicio**, que ya funciona y está casi preparada. Si se quiere una app de
   verdad, hacerla por fases con TestFlight. Detalle en el punto 7.

---

## 1. Cómo están las carpetas de iOS (y tvOS)

### 1.1 Qué hay [código]

- `ios/` y `tvos/` siguen enteras. No hay carpeta `ipad/`: el iPad es el mismo
  proyecto `ios/` (`TARGETED_DEVICE_FAMILY = "1,2"` en
  `ios/Runner.xcodeproj/project.pbxproj`, es decir, iPhone e iPad) con sus
  propias orientaciones en `Info.plist` (`UISupportedInterfaceOrientations~ipad`).
- Nuestros commits **apenas las han tocado**. El único commit nuestro en `ios/`
  y `tvos/` es `021b0683a` («Rebranding completo a kOS TV…»): iconos,
  `CFBundleDisplayName`/`CFBundleName` = «kOS TV», textos de permisos en
  español (`ios/Runner/Info.plist`) y la estantería superior de Apple TV. Al
  quitar escritorio, Plex, Emby, Firebase (lo apagamos, no lo quitamos) o Seerr
  no se tocó nada del código nativo de iOS.
- El reproductor nativo de iOS está repartido: `ios/Runner/Playback/`
  (`IosNativePlayerHostController.swift`, `IosPiPController.swift`) más lo que
  se comparte con tvOS desde `tvos/Runner/Playback/` y
  `tvos/Runner/Playback/Aether/`, cosido al proyecto por
  `ios/scripts/wire_ios_player.rb`. Usa el paquete Swift **AetherEngine**,
  fijado a una revisión del GitHub de un desarrollador de Moonfin
  (`repositoryURL = "https://github.com/RadicalMuffinMan/AetherEngine"`, en
  `project.pbxproj`), y `libass-build` para los subtítulos ASS.
- Otro código nativo de iOS en `ios/Runner/`: `AppDelegate.swift` (1.329
  líneas: Chromecast, AirPlay, DLNA, refresco en segundo plano,
  almacenamiento, canales del reproductor), `CarPlayBridge.swift` y
  `CarPlaySceneDelegate.swift` (CarPlay), `AirPlayController.swift`,
  `DlnaController.swift`, `BackgroundRefreshScheduler.swift`,
  `SceneDelegate.swift`. Además `ios/game_host/` y `native/libretro_host` (los
  juegos de After Hours, con núcleos libretro que se descargan al compilar).

### 1.2 Lo que sigue siendo de Moonfin [código]

| Qué | Dónde | Valor ahora | Qué haría falta |
|---|---|---|---|
| Identificador (bundle id) | `ios/Flutter/Shared.xcconfig` | `org.moonfin.app` | El nuestro, p. ej. `com.kikope.kostv` (como en Android) |
| Equipo de firma | `ios/Flutter/Shared.xcconfig` | `MOONFIN_DEVELOPMENT_TEAM = CCBYLPUSVH` (el equipo de Moonfin) | El de nuestra cuenta, mejor desde un secreto o `Local.xcconfig` |
| Identificador de las pruebas | `project.pbxproj` | `org.moonfin.app.RunnerTests` | El nuestro |
| Firebase | `ios/Runner/GoogleService-Info.plist`, `firebase_core`/`firebase_messaging` en `pubspec.yaml` | Configuración del proyecto Firebase de Moonfin (es pública en el oficial; no es un secreto nuestro). En Dart está apagado: `PushMessagingService.enabled = false` en `lib/data/services/push_messaging_service.dart` | Quitar el plist (y si se puede los paquetes) |
| Enlaces `moonfin://` | `Info.plist` (`CFBundleURLSchemes`) | `moonfin` | Valorar `kostv://` (no se ve, pero choca si alguien tiene Moonfin instalado) |
| Textos a la vista en inglés con «Moonfin» | `ios/Runner/SceneDelegate.swift:12` («Moonfin is already open in another window»), `ios/Runner/CarPlayBridge.swift:140-142` (título y pestaña «Moonfin» en CarPlay), `ios/Runner/AppDelegate.swift:1101` (título por defecto al enviar a Chromecast) | | Pasarlos a «kOS TV» y a español |
| Búsqueda en la red | `Info.plist` `NSBonjourServices` | Incluye `_emby._tcp` y `_silo._tcp` | Quitar lo que no usamos |
| Nombre del archivo del script local | `build-ios.sh:10` | `APP_NAME="Moonfin"` | `KosTV` |

Ya está bien: nombre visible «kOS TV», iconos de la marca, permisos en español,
y el nombre que ve el servidor (`kOS TV para iOS`, en `lib/di/injection.dart:62`
y `lib/playback/device_profile_builder.dart:1169`).

### 1.3 Capacidades y permisos [código + Apple]

- `ios/Runner/Runner.entitlements` y `RunnerRelease.entitlements` piden:
  - `aps-environment` (notificaciones push): no las usamos (Firebase apagado).
    Pedirlas obliga a activar Push en el identificador; **hay que quitarlas**.
  - `com.apple.developer.carplay-audio` (CarPlay): [Apple] es una capacidad
    que **Apple tiene que concederte a mano** tras pedirla. Sin ella el perfil
    de firma no se genera y la compilación firmada falla. O se pide o se quita
    (y con ella CarPlay).
  - `com.apple.developer.networking.multicast`: [Apple] también hay que
    pedirla a Apple. Sirve para descubrir servidores y teles en la red (DLNA,
    Bonjour). Nosotros no buscamos servidor (va dentro), así que se puede
    quitar; DLNA quedaría sin descubrir aparatos.
  - Hay un `RunnerSideload.entitlements` vacío, pensado para instalar sin
    cuenta de pago.
- Modos en segundo plano (`UIBackgroundModes`): `audio` (sí, para que la música
  siga con la pantalla apagada), `fetch` (descargas automáticas,
  `BGTaskSchedulerPermittedIdentifiers`) y `remote-notification` (push: sobra).
- Permisos con texto: red local, micrófono y voz (búsqueda por voz), fotos,
  cámara y ubicación (los exige `file_picker`; el oficial los volvió a poner en
  `cac3f906c`). `NSAllowsArbitraryLoads = true` (permite `http`): [Apple] en la
  revisión de la tienda a veces piden justificarlo; para un cliente de
  servidor multimedia suele aceptarse.
- `Podfile`: iOS 18 como mínimo (`platform :ios, '18.0'`), Google Cast
  (`google-cast-sdk-no-bluetooth-xcframework`), libretro y game host.

### 1.4 Qué hace el oficial con iOS ahora [código]

Desde nuestro punto de partida (`3d87996d2`) el oficial lleva 343 commits; en
`ios/` y el reproductor compartido hay, entre otros:
- `b5e216bc2`: sube `firebase_messaging` a 16.7.1 porque **con la versión
  anterior no se resolvían los paquetes de iOS**. Nosotros tenemos `^16.4.1`
  en `pubspec.yaml`: es probable que nuestra copia tenga ese mismo fallo al
  compilar para iPhone (no comprobado: no hay Mac aquí).
- `96ec46cb1`: nueva versión de AetherEngine (Dolby Vision perfil 7).
- `12691292b`: soporte del «iPhone Duo» (plegable).
- `9a806714c`, `1efa38a9f`, `1739696c8`: Chromecast y DLNA.
- `4e44bdea3` y `cac3f906c`: permisos de cámara y ubicación (quitados y vueltos
  a poner porque Apple los exige por `file_picker`).

El iPad no tiene pantallas propias: usa las mismas que el móvil o el «modo
ordenador» según el ancho, como una tableta Android. En el iPhone y el iPad la
app usa en algunos sitios el aspecto de Apple (`PlatformDetection.isApple`,
28 usos en `lib/`: reproductor, audiolibros, lector, pestañas de la ficha
Modern…), así que en ciertos detalles se vería distinta del móvil Android.

---

## 2. Reproducción y funciones nuestras en el iPhone

### 2.1 Qué reproductor usa [código]

- En iOS **no se usa media_kit/mpv** (`lib/main.dart:989`: solo se inicia
  fuera de Apple; `pubspec.yaml` deja fuera las librerías de mpv para Apple a
  propósito) **ni Media3** (solo Android, `lib/playback/media3_player_backend.dart:38`).
- Reproduce todo con **AetherEngine** (`lib/playback/aether_backend.dart`):
  vídeo, TV en directo, música, audiolibros y lo descargado
  (`lib/di/modules/playback_module.dart:401-412` y `583-593`).
- Hay una segunda opción, el «reproductor nativo» de Apple
  (`native_apple_player_backend.dart`), que en el iPhone viene **apagada**
  (`UserPreferences.applePlayerUi`, por defecto `flutter` fuera de Apple TV).
  Ojo: esa pantalla está en Swift con **textos fijos en inglés**
  («Audio», «Cancel», «Chapters», «Quality», «LIVE», «Leave Group»… en
  `tvos/Runner/Playback/NativeApplePlayerViewController.swift`). Habría que
  traducirla o esconder la opción.
- Avances, tráilers del banner, música de tema: en Apple van con un
  reproductor propio de AVFoundation (`PlatformDetection.useApplePreviewPlayer`,
  `lib/util/platform_detection.dart:429`), no con mpv.

### 2.2 Lo nuestro que es solo de Android, y qué pasaría en el iPhone [código]

| Función | En el iPhone | Cómo está protegido |
|---|---|---|
| Música sin cortes (cola en Media3) | No: pasaría de canción como antes, con su pequeño silencio. Solo `Media3PlayerBackend` implementa `GaplessCapable` | Por la interfaz; no rompe |
| Avances de 30 s en Música (pedir canciones/álbumes) | **No sonarían**: `lib/data/services/music_preview/preview_engine_io.dart` crea un `Player()` de media_kit, que en iOS no está iniciado ni tiene mpv | El `try/catch` de `lib/data/services/kostv_music_preview.dart:49-57` lo traga: no rompe, pero no suena. Habría que hacer una versión con el reproductor de Apple |
| Actualizar desde la app (APK) | No existe en iOS. El aviso y el botón de Ajustes > Acerca de no salen (`AppDistribution.supportsInAppUpdates` es falso en iOS, `lib/util/app_distribution.dart:81`) | Bien protegido |
| Fila de aplicaciones instaladas, botón Apps, «kOS TV como inicio» | No (solo tele Android) | `InstalledAppsService.isSupported` y `kostvAppsAvailable()` (`lib/data/services/installed_apps_service.dart:55`, `257`) |
| Sonido de la animación de apertura | No (solo Android) | `lib/ui/widgets/kos_intro.dart:272` |
| Chromecast | Sí, con el SDK de Google para iOS (`AppDelegate.swift`, `Podfile`) | Nativo propio de iOS; falta probarlo |
| AirPlay | Sí, solo en iPhone (`AirPlayController.swift`) | — |
| Imagen en imagen (PiP) | Sí (`ios/Runner/Playback/IosPiPController.swift`) | — |
| Android Auto | No; en su lugar CarPlay (`CarPlayBridge.swift`), que necesita el permiso de Apple del punto 1.3 | — |
| Controles en la pantalla de bloqueo | Sí, pero no con `audio_service`: en iOS los pone AetherEngine (`tvos/Runner/Playback/Aether/NowPlayingController.swift`, compartido) | — |
| Descargas sin conexión | Sí en principio (`background_downloader` funciona en iOS; refresco en segundo plano con `BackgroundRefreshScheduler.swift`) | Falta probarlo |
| Peticiones y «Toda la música» (Stremfin) | Debería ir: es Dart y la reproducción la hace AetherEngine con direcciones http normales | Sin probar |
| Reproductor sencillo de kOS TV | Es Flutter, así que sale igual, con algunos cambios solo de iOS en `video_player_screen.dart` (PiP, giro, brillo) | Sin probar |

Los canales nativos que hemos añadido nosotros (`org.moonfin.androidtv/platform`:
lista de apps, instalar el APK, sonido de la apertura, salidas del proceso) se
llaman siempre tras comprobar que es Android o capturando
`MissingPluginException`. **No he encontrado nada que vaya a romper la app**
al abrirla en el iPhone, pero tampoco hay prueba de verdad: no se ha compilado
ni abierto nunca en iOS.

---

## 3. Dependencias [código]

- Sin iOS pero ya apartadas: `media_kit_libs_android_video`,
  `media_kit_libs_windows_video`, `media_kit_libs_linux`, `webview_win_floating`,
  `window_manager`/`screen_retriever` (escritorio), `dbus` (Linux),
  `screen_brightness_android`. Los paquetes `*_tvos` son de Apple TV.
- Que **piden algo en iOS**:
  - `firebase_core`/`firebase_messaging`: lo del punto 1.4. Mejor quitarlos del
    todo si no vamos a usar push.
  - `file_picker`: obliga a tener los textos de cámara, fotos y ubicación.
  - `speech_to_text`: micrófono y reconocimiento de voz.
  - `permission_handler`: en iOS necesita macros en el Podfile para no incluir
    permisos que no se usan; el Podfile actual no las tiene. [Apple] Si quedan
    llamadas a permisos sin texto, Apple puede rechazar la compilación.
  - `audio_session`, `background_downloader`: el modo `audio` y el refresco ya
    están en `Info.plist`.
  - `flutter_inappwebview`, `webview_flutter_wkwebview`, `youtube_player_iframe`,
    `pdfrx`, `sqlite3_flutter_libs`: tienen iOS.
- Nativas: AetherEngine y libass (paquetes Swift desde GitHub), Google Cast
  (CocoaPods), núcleos libretro (se descargan en la compilación con
  `ios/game_host/fetch_cores.sh`). Si no queremos los juegos, quitarlos
  simplifica la compilación y la revisión de Apple.

---

## 4. CI (GitHub Actions) [código]

En `.github/workflows/build.yml`:

- **`ios`** (`runs-on: macos-26`, Xcode 26.3):
  - Normal: `flutter build ipa --no-codesign` y sale un IPA **sin firmar**
    (`KosTV_iOS_v…_unsigned.ipa`, que sí lleva ya nuestro prefijo). Un IPA sin
    firmar no se puede instalar en un iPhone tal cual: hay que firmarlo
    después con alguna herramienta.
  - Con `distribution: testflight`: firma con la acción
    `.github/actions/apple-signing`, archiva con `xcodebuild` y lo sube a App
    Store Connect con `.github/actions/testflight-upload`.
- **`tvos`**: lo mismo para Apple TV (necesita además el Flutter con soporte de
  tvOS, `FLUTTER_TVOS_REF`).
- **`apple-tests`**: compila para el simulador de iPhone y pasa las pruebas
  XCTest (`ios/RunnerTests`).
- Secretos que piden (solo los nombres): `APPLE_CERTIFICATE_BASE64`,
  `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ASC_API_KEY_BASE64`,
  `APPLE_ASC_API_KEY_ID`, `APPLE_ASC_API_ISSUER_ID`, `APPLE_TEAM_ID`. No he
  comprobado si existen en el repositorio (lo más probable es que no).
- **¿Funcionan hoy?** No se sabe, y hay motivos para dudar:
  - En nuestro repositorio **nunca se han ejecutado**: las 51 ejecuciones de
    `build.yml` son manuales (versiones y pruebas); en la primera, `ios`,
    `tvos` y `apple-tests` salen como «skipped», y las versiones y las pruebas
    compilan solo Android (el `plan` deja solo `android` cuando hay
    `release_version` o `test_apk`).
  - El IPA no lleva el servidor de casa: el trabajo de iOS no pasa
    `KOSTV_SERVER_URL` (Android sí, en `build-android.sh`), así que pediría la
    dirección del servidor, cosa que nuestra app ya no deja hacer bien.
  - Tampoco pasa `DISTRIBUTION_CHANNEL` en el IPA normal ni usa
    `scripts/kostv_set_version.sh` (saldría como 0.1.0).
  - [Apple] Las pruebas usan versiones `X.Y.Z-prueba.N`: Apple no admite
    letras en la versión (`CFBundleShortVersionString`), así que en iOS las
    pruebas tendrían que numerarse de otra forma (la versión normal y el número
    de compilación por encima).
  - El fallo de Firebase del punto 1.4.
- Coste: [Apple/GitHub] en un repositorio público los minutos de macOS de
  GitHub son gratis con los ejecutores normales; una compilación de iOS tarda
  más que la de Android y falla más (firma, perfiles).

---

## 5. Cómo hacérsela llegar a la familia

Todo esto es **[Apple]**, según lo que sé; puede haber cambiado.

| Forma | Coste | Cómo es para la familia | Pegas |
|---|---|---|---|
| **TestFlight** | Cuenta de desarrollador: 99 € al año (99 USD) | Instalan la app TestFlight, abren un enlace público o una invitación por correo, y kOS TV se actualiza sola (TestFlight avisa y puede instalar las nuevas solo) | Para probadores de fuera (hasta 10.000) la primera compilación de cada versión pasa una **revisión beta** de Apple (normalmente 1-2 días). Cada compilación **caduca a los 90 días**: hay que subir algo al menos cada 3 meses. Los probadores «internos» (hasta 100) no pasan revisión, pero tienen que ser usuarios de la cuenta en App Store Connect. Apple lo pensó para pruebas, no como tienda permanente, aunque mucha gente lo usa así |
| **App Store** (pública u «oculta», solo con enlace: *Unlisted App Distribution*, que se pide a Apple) | 99 €/año | Como cualquier app; se actualiza sola | Revisión completa en cada versión. Riesgos: (a) Apple necesita una cuenta de prueba que funcione, y nuestra app solo entra en el servidor de casa, así que habría que darles un usuario de nuestro Jellyfin; (b) las **peticiones con Stremfin** (pedir pelis y música que no tienes y escucharlas «mientras llegan») pueden chocar con las normas sobre contenido sin derechos (guía 5.2); (c) los juegos con emuladores tienen normas propias. Hay clientes de Jellyfin en la tienda (Swiftfin, Streamyfin, Infuse…), así que un cliente de Jellyfin en sí se acepta; lo que preocupa es lo de pedir y escuchar lo de fuera |
| **Ad Hoc** | 99 €/año | Se instala desde un enlace (`itms-services://`) a un IPA en una página https | Hay que **apuntar el identificador (UDID) de cada iPhone/iPad** en la cuenta: hasta 100 de cada tipo al año. Si alguien cambia de móvil, hay que apuntarlo y volver a compilar. El perfil caduca al año. Es el único que se parece a lo de ahora: en teoría nuestro aviso de actualización podría abrir ese enlace (no lo he probado) |
| **Apple ID gratis** (Xcode, Sideloadly…) | 0 € | Se instala desde un Mac o un PC con cable | **Caduca a los 7 días** y hay que reinstalar; máximo 3 apps; sin CarPlay ni push. Inviable para la familia |
| **AltStore clásico / SideStore** | 0 € | Herramienta que vuelve a firmar la app cada 7 días con el Apple ID de cada uno | Hay que tenerla al día; se rompe de vez en cuando con las versiones de iOS. Para alguien muy técnico, no para la familia |
| **Tiendas alternativas de la UE** (AltStore PAL…) | 99 €/año + condiciones de Apple para la UE | España está en la UE, así que la familia podría instalar desde una de ellas | Hay que aceptar las condiciones alternativas de Apple, pasar su «notarización» (una revisión más ligera, pero revisión), y publicarla en esa tienda. Mucho papeleo para unas pocas personas. La distribución desde una web propia en la UE pide requisitos (años en el programa, muchas instalaciones) que no cumplimos |

**La actualización desde la app no puede funcionar en iOS** como en Android:
iOS no deja instalar un IPA desde otra app. Con TestFlight o la App Store las
actualizaciones las hace Apple, y el aviso nuestro debe seguir apagado (ya lo
está). La única excepción sería Ad Hoc con su enlace especial.

### La alternativa que ya existe: la web en el iPhone [código]

- La web de Docker ya está pensada para el iPhone: en noviembre se hizo una
  ronda de rendimiento para iPhone y se decidió que el vídeo HLS lo reproduzca
  Safari (`KOSTV.md`, «Rendimiento web (iPhone)»; `web/index.html`,
  `playsHlsNatively`), lo que además permite AirPlay.
- Ya está preparada para ponerla en la pantalla de inicio como si fuera una app:
  `web/manifest.json` (`"display": "standalone"`, nombre «kOS TV», iconos,
  `"lang": "es"`) y en `web/index.html`: `apple-mobile-web-app-capable`,
  `apple-mobile-web-app-status-bar-style`, `apple-mobile-web-app-title` y
  `apple-touch-icon` (`icons/Icon-192.png`), además de `viewport-fit=cover`
  para la muesca. En Safari: Compartir > «Añadir a pantalla de inicio».
- Con una dirección https (`docs/web.md`) funciona dentro y fuera de casa, y se
  actualiza sola cada vez que se publica la imagen web.
- Lo que le falta frente a una app: música con la pantalla bloqueada y en
  segundo plano (en Safari es poco fiable, iOS la suele cortar), descargas sin
  conexión, Chromecast, CarPlay, imagen en imagen (Safari tiene la suya para
  vídeo), y el rendimiento de Flutter web en Safari, que es peor que el nativo
  (skwasm sigue apagado en Safari). Detalles pequeños: Apple recomienda un
  icono de 180×180 para `apple-touch-icon` (ahora es el de 192, que funciona).

---

## 6. Trabajo que haría falta, por fases

Tamaños orientativos, contando las vueltas de compilar en un Mac de GitHub.

**Fase 0. Decidir y preparar (sin código).** Elegir la forma de reparto
(TestFlight, seguramente), darse de alta en el programa de desarrollador
(99 €/año, puede tardar unos días en aprobarse), crear el identificador, el
certificado, la clave de la API de App Store Connect y los secretos del punto 4.
Hace falta un iPhone para probar; un Mac no es imprescindible (GitHub compila),
pero ayuda mucho para ver fallos.

**Fase 1. Dejar el proyecto de iOS como nuestro (1-2 días).** Identificador,
equipo y pruebas (punto 1.2); quitar push, Firebase y su plist; quitar CarPlay
o pedirlo a Apple; quitar multicast; `moonfin://` → `kostv://` (con cuidado);
textos «Moonfin» y en inglés de Swift a «kOS TV» y español; Bonjour sin Emby ni
Silo; decidir si se quedan los juegos.

**Fase 2. Que compile (1-3 días, impredecible).** Primera compilación desde que
nos separamos: arreglar los paquetes (Firebase, punto 1.4), lo que haya roto lo
que quitamos de Dart, y pasar el servidor de casa, el canal de distribución y
la versión al IPA.

**Fase 3. Publicación automática (1-2 días).** Que una versión
(`release_version`) suba también a TestFlight además de los APK, con un número
de compilación que siempre suba y otra forma de numerar las pruebas. Añadirlo
a CLAUDE.md («Publicar una versión»). Opcional: que la nota de la versión llegue
a TestFlight.

**Fase 4. Igualar lo nuestro (1-2 semanas).** Avances de Música con el
reproductor de Apple; decidir qué hacer con la música sin cortes en
AetherEngine (aceptarlo o hacerlo); traducir o esconder el reproductor nativo;
repasar en iPhone e iPad todo lo que hemos hecho (inicio, banner, fichas kOS,
música, peticiones, Stremfin, Ver juntos, niños, descargas) en los tres
diseños: barra de arriba, lateral y barra de abajo; muesca, isla dinámica y
gestos de iOS (volver deslizando desde el borde frente a nuestro «Atrás»).

**Fase 5. Pruebas en un iPhone de verdad (continuo).** Solo se puede probar en
un aparato real: AetherEngine (HDR, Dolby Vision, subtítulos ASS), música con
la pantalla bloqueada y los controles, AirPlay, Chromecast, PiP, CarPlay,
descargas en segundo plano, rendimiento y batería, la revisión de TestFlight.
El simulador no sirve para la mayoría.

**Total:** unas 3-4 semanas hasta una primera versión decente en TestFlight,
y después un coste fijo: 99 €/año, subir algo al menos cada 90 días y probar
cada novedad también en iPhone.

**Riesgos.**
- Dependemos de AetherEngine, del GitHub de un desarrollador de Moonfin, para
  reproducir: si cambia o desaparece, el iPhone se queda sin reproductor.
- La revisión de Apple (beta o tienda) puede rechazar por lo de pedir o
  escuchar lo de fuera.
- El servidor de casa iría dentro del IPA: con TestFlight público, quien tenga
  el enlace puede sacarlo de la app (como pasa ya con el APK).
- Más trabajo en cada revisión semanal: lo que ahora es «no aplica» (iOS,
  Apple) pasaría a contar.

**La norma de CLAUDE.md.** Ahora dice «tele, móvil y web». Si hay app de iPhone,
lo lógico es ampliarla: «móvil» pasaría a ser Android **e** iPhone (y el iPad),
con sus fotos. Eso multiplica las pruebas de cada cambio. Habría que decidirlo y
escribirlo en CLAUDE.md, junto con lo que se puede quedar solo en Android (la
fila de apps, el instalador del APK) y lo que solo tiene el iPhone (AirPlay,
CarPlay).

---

## 7. Recomendación

1. **Ahora: la web como app del iPhone.** Ya existe, se actualiza sola, no
   cuesta nada y no pasa por Apple. Bastaría con una guía corta para la familia
   («Añadir a pantalla de inicio»), un icono de 180×180 y probar en un iPhone
   que se abre a pantalla completa y que la sesión se mantiene. Es lo que
   recomiendo si en casa hay pocos iPhone y se usan sobre todo para ver cosas.
2. **Si echan de menos música en segundo plano, descargas o Chromecast: app con
   TestFlight.** Es la forma más parecida a lo de ahora (enlace y se actualiza
   sola). Hacerla por fases (punto 6), empezando por la 1-2 para saber si
   compila antes de comprometerse. Requiere los 99 €/año y aceptar la revisión
   beta de Apple.
3. **Ad Hoc** solo si la revisión de TestFlight rechaza la app: funciona sin
   revisión, pero hay que apuntar cada aparato.
4. **No recomiendo:** App Store pública (revisión y riesgo con Stremfin),
   Apple ID gratis o AltStore/SideStore (caduca a los 7 días), ni tienda
   alternativa de la UE (demasiado papeleo para unas pocas personas).
5. **Apple TV** es otro proyecto (`tvos/`, con su Flutter especial); no entra
   aquí. En KOSTV.md ya está apuntado que antes hay que cambiarle el identificador.
