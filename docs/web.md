# kOS TV en el navegador (Docker)

La versión web de kOS TV es la misma app que la de la tele y el móvil, para
abrirla desde cualquier navegador (ordenador, tablet, móvil, la tele de un
hotel…). Se instala en el servidor de casa como un contenedor Docker.

La imagen **no lleva ninguna dirección dentro**: se le dan en las variables
del contenedor y, al arrancar, las escribe en el `config.json` que lee la app.
Así la misma imagen sirve para cualquiera y las direcciones no salen del
servidor.

## Lo que hace falta

- **Docker** (con Docker Compose, o Portainer) en el servidor.
- **Una dirección con https** para usarla desde fuera de casa, por ejemplo un
  subdominio en el proxy inverso que ya uses para Jellyfin (Nginx Proxy
  Manager, Traefik, Caddy…). Por ella viajan el usuario, la contraseña y la
  sesión, así que fuera de casa siempre con https. Dentro de casa también se
  puede abrir por `http://IP-del-servidor:25670`, útil para probar.

## Puesta en marcha

En el repositorio hay un ejemplo listo para copiar:
[`docker/compose.example.yml`](../docker/compose.example.yml) y
[`docker/.env.example`](../docker/.env.example). En una carpeta del servidor:

1. Copia `compose.example.yml` como `compose.yml` y `.env.example` como `.env`.
2. Rellena el `.env` con tus direcciones y la contraseña del panel de
   administración. El `compose.yml` no hace falta tocarlo: lee todo del `.env`
   (solo si guardas la contraseña en un archivo, con
   `KOSTV_ADMIN_PASSWORD_FILE`, hay que quitar los `#` de su bloque `secrets`).
3. Arráncalo:

   ```bash
   docker compose up -d
   docker compose logs kostv-web   # dice qué ha configurado
   ```

4. En el proxy inverso, apunta un subdominio con https (por ejemplo
   `https://kostv.example.com`) al puerto 25670 de ese servidor.

El contenedor **no se ejecuta como root**: nginx va con un usuario sin
privilegios (el 101) y por eso escucha dentro en el puerto **8080**, no en el
80. En el servidor sigue siendo el 25670 (`"25670:8080"` en el `compose.yml`),
así que el proxy inverso y las direcciones no cambian.

### Si ya lo tenías instalado: cambia el puerto de dentro

Hasta ahora el contenedor escuchaba dentro en el 80. Con la imagen nueva
escucha en el 8080, así que en el `compose.yml` que ya tienes (o en el editor
del stack de Portainer) hay que cambiar una línea, **antes o justo al
actualizar**:

```yaml
    ports:
      - "25670:80"      # lo de antes: quítalo
      - "25670:8080"    # lo de ahora
```

Solo cambia el número de la derecha (el de dentro del contenedor); el de la
izquierda (25670, o el que pusieras) se queda igual, y en el proxy inverso no
hay que tocar nada. Luego `docker compose pull && docker compose up -d` (en
Portainer, **Update the stack** con **Re-pull image**). Si se actualiza la
imagen sin cambiar la línea, la web deja de abrir (el proxy da error 502 o el
navegador no conecta) hasta que se cambie.

Si usas `KOSTV_ADMIN_PASSWORD_FILE`, el archivo de la contraseña tiene que
poderlo leer ese usuario: `sudo chown 101 admin_password.txt && chmod 600
admin_password.txt`. Si no puede, el contenedor no arranca y lo dice en
`docker compose logs` («no se puede leer KOSTV_ADMIN_PASSWORD_FILE»).

Al abrirlo, la app va directa al usuario y la contraseña de Jellyfin, igual que
en la tele. El panel de administración está en `/admin` (por ejemplo
`https://kostv.example.com/admin`).

## En Unraid con Portainer y Nginx Proxy Manager

### 1. Crear el stack en Portainer

1. **Stacks → + Add stack**. Nombre: `kostv`.
2. **Build method: Web editor**. Pega el contenido de
   [`docker/compose.example.yml`](../docker/compose.example.yml).
3. Más abajo, en **Environment variables**, pulsa **Advanced mode** y pega
   las variables (las de [`docker/.env.example`](../docker/.env.example), con
   tus valores):

   ```
   KOSTV_SERVER_URL=https://jellyfin.example.com
   KOSTV_ADMIN_USER=admin
   KOSTV_ADMIN_PASSWORD=una-contraseña-larga
   ```

   Mejor una contraseña sin `$`: Portainer y Docker Compose lo toman por el
   principio de una variable. En un `.env`, si la lleva, ponla entre comillas
   simples (`KOSTV_ADMIN_PASSWORD='mi$clave'`): sin ellas, Docker Compose toma
   `$clave` por una variable y la contraseña cambia.
4. **Deploy the stack**.
5. En **Containers → kostv-web → Logs** deben salir las líneas `kostv:` con lo
   configurado (servidor, servicio de peticiones y panel en `/admin`).
6. Prueba desde casa: `http://IP-del-Unraid:25670`.

Si Portainer dice que no puede descargar la imagen (`denied` o `unauthorized`),
el paquete está privado en GitHub: ver más abajo, en «Actualizar».

La dirección de Stremfin no va aquí: se pone en el panel de Jellyfin, en el
complemento de kOS TV (pestaña «Direcciones»), y la web la recibe al iniciar
sesión, igual que las apps.

### 2. Publicarla con Nginx Proxy Manager

1. **Hosts → Proxy Hosts → Add Proxy Host**.
2. Pestaña **Details**:
   - **Domain Names**: el subdominio para kOS TV (por ejemplo
     `kostv.example.com`; en tu DNS, apuntando a casa como los demás).
   - **Scheme**: `http`.
   - **Forward Hostname / IP**: la IP del Unraid.
   - **Forward Port**: `25670`.
   - Activa **Block Common Exploits** y **Websockets Support**.
3. Pestaña **SSL**: **Request a new SSL Certificate**, y activa **Force SSL** y
   **HTTP/2 Support**.
4. **Save**.

Ya está: `https://kostv.example.com` abre kOS TV para la familia y
`https://kostv.example.com/admin` el panel de administración.

## Variables

| Variable | Qué es | Si no se pone |
|---|---|---|
| `KOSTV_SERVER_URL` | El Jellyfin de casa **tal como lo abre el navegador** de quien entra: la dirección pública, con https. No sirve una interna como `http://jellyfin:8096`, porque es el navegador quien habla con Jellyfin | La app pide la dirección del servidor |
| `KOSTV_REQUESTS_URL` | **Ya no hace falta.** Solo para pasar por el contenedor (en `/stremfin`) mientras Stremfin no acepte llamadas de la web (CORS): el servicio de peticiones tal como lo alcanza el contenedor | La web habla directamente con la dirección que da el complemento |
| `KOSTV_REQUESTS_VERIFY` | Solo con `KOSTV_REQUESTS_URL`: `off` si el servicio de peticiones usa un certificado propio de la red de casa. Por defecto (`on`) el contenedor comprueba su certificado, como hacen las apps | Se comprueba |
| `KOSTV_ADMIN_USER` | El usuario del panel de administración | `admin` |
| `KOSTV_ADMIN_PASSWORD` | Su contraseña, **de al menos 10 caracteres** (con una más corta el contenedor no arranca y lo dice en `docker compose logs`). Si lleva `$`, entre comillas simples en el `.env` (ver arriba) | `/admin` queda cerrado |
| `KOSTV_ADMIN_PASSWORD_FILE` | En vez de la anterior, la ruta de un archivo que contenga la contraseña (los *secrets* de Docker), así no queda en las variables del contenedor. En el `compose.yml` de ejemplo: quita los `#` del bloque `secrets`, guarda la contraseña en `admin_password.txt` junto al `compose.yml` (que lo pueda leer el usuario 101 del contenedor: `sudo chown 101 admin_password.txt`) y pon `KOSTV_ADMIN_PASSWORD_FILE=/run/secrets/kostv_admin_password` en el `.env`. En el editor web de Portainer no sirve un archivo junto al compose: ahí, mejor `KOSTV_ADMIN_PASSWORD` | Se usa `KOSTV_ADMIN_PASSWORD` |
| `KOSTV_TRUSTED_PROXY` | La IP del proxy inverso (Nginx Proxy Manager…) **tal como llega al contenedor**, o un rango, o varias separadas por comas. Si el proxy está en Docker en el mismo servidor, suele bastar `172.16.0.0/12` (las redes de Docker); si está en otro aparato de casa, su IP. Solo entonces se cree la dirección del visitante que manda el proxy (y solo a él), y `/admin` cuenta su límite por cada visitante | `/admin` cuenta su límite por la dirección que llega al contenedor: detrás de un proxy, uno para todos |

Da igual que lleven o no la barra final o `/api/v1`. Una dirección mal escrita
detiene el contenedor con un mensaje en `docker compose logs`.

### Cómo llega cada cosa

- **Jellyfin**: el navegador habla directamente con él. Jellyfin acepta por
  defecto peticiones de otros sitios (CORS), así que no hay que tocar nada.
- **Stremfin**: la web le pide la dirección al complemento de Jellyfin al
  iniciar sesión (como las apps) y habla directamente con él. Para eso
  Stremfin tiene que aceptar llamadas de la dirección de la web (CORS), igual
  que hace Jellyfin. Si el contenedor tiene `KOSTV_REQUESTS_URL`, la web pasa en
  cambio por `/stremfin` y el contenedor se lo pasa al servicio (así era antes;
  queda para la transición): solo su API (`/stremfin/api/v1/…`), nada más del
  servicio, y comprobando su certificado. El token de la sesión no queda en
  ningún registro.

## Panel de administración (`/admin`)

De momento es un panel en blanco que iremos llenando (módulos, dispositivos,
servicios de casa). Al entrar, el navegador pide el usuario y la contraseña de
`KOSTV_ADMIN_USER` y `KOSTV_ADMIN_PASSWORD`.

- Para nginx, la contraseña no se guarda tal cual: al arrancar, el contenedor
  guarda solo su huella cifrada (SHA-512), que únicamente puede leer el
  usuario de nginx.
  Pero si se da en `KOSTV_ADMIN_PASSWORD`, sigue en las variables del
  contenedor (las ve quien pueda hacer `docker inspect`); con
  `KOSTV_ADMIN_PASSWORD_FILE` no.
- Admite unas 30 peticiones por minuto; pasado eso responde "demasiadas
  peticiones" hasta que baja el ritmo, para frenar a quien intente adivinarla.
  Detrás de un proxy, el límite es para todos los que entran por él (y
  alguien de fuera podría dejar el panel bloqueado un rato a la familia),
  salvo que el contenedor tenga `KOSTV_TRUSTED_PROXY`: entonces cuenta por
  cada visitante. La dirección que dice traer una petición solo se cree si
  viene de ese proxy, así que cambiarla en cada intento no salta el límite.
- Por `http://IP-del-servidor:25670` el usuario y la contraseña viajan sin
  cifrar por la red de casa: para el panel, mejor la dirección con https.
- Sin contraseña, `/admin` queda cerrado.
- Para salir, cierra el navegador (con este tipo de acceso no hay botón de
  cerrar sesión; llegará con el admin de verdad).

## En un ordenador que no es tuyo

La web recuerda la sesión, como las apps: al volver a abrirla sigues dentro.
En un aparato compartido (el ordenador de otra persona, la tele de un hotel),
**cierra la sesión al terminar** desde el menú de tu perfil >
«Cerrar sesión», o abre la web en una ventana privada.

## Actualizar

Cada versión publicada de kOS TV, y cada prueba, sube también la imagen web:

| Etiqueta | Qué es |
|---|---|
| `latest` | Siempre la última imagen compilada, sea una versión publicada o una prueba. Es la que usa el `compose.yml` de arriba. La imagen (y con ella `latest`) solo se sube cuando la publicación de esa versión o prueba ha salido bien |
| `X.Y.Z` | Una versión publicada concreta, por ejemplo `1.1.0` |
| `prueba` / `prueba-N` | Las compilaciones de prueba (como los APK de prueba) |

Ojo: como `latest` también recibe las pruebas, al actualizar el contenedor
después de una prueba la familia verá esa prueba en la web. Para quedarte en
una versión concreta, pon `:X.Y.Z` en lugar de `:latest`.

```bash
docker compose pull && docker compose up -d
```

El navegador coge la versión nueva la próxima vez que se abre o se recarga la
página; no hay que instalar nada.

Si `docker compose pull` pide usuario y contraseña, es que el paquete está
privado en GitHub: en el repositorio, **Packages → kos-tv-web → Package
settings → Change visibility → Public**. Se puede hacer público sin miedo
porque la imagen no lleva ninguna dirección ni contraseña.

## Qué tiene y qué no

Tiene lo mismo que la app del móvil: Inicio, bibliotecas, búsqueda,
reproducción, Descubrir, personalización… Lo que no tiene sentido en un
navegador no aparece:

- La fila de **aplicaciones** de la tele y "Todas las aplicaciones" (son de la
  tele: abren las apps instaladas en ella).
- El aviso de **actualizaciones** (la web se actualiza sola al recargar).

## Más adelante

El contenedor hace de puerta de entrada a los servicios de casa. Cuando el
admin tenga su propio servicio, irá en este mismo `compose.yml` y `/admin` le
pasará las peticiones igual que hace ahora `/stremfin` con Stremfin.

## Construir la imagen a mano

Desde la raíz del repositorio:

```bash
flutter build web --wasm --release --no-web-resources-cdn
bash scripts/fetch-web-fonts.sh build/web
docker build -f docker/web/Dockerfile -t kostv-web .
docker run --rm -p 25670:8080 \
  -e KOSTV_SERVER_URL=https://jellyfin.example.com \
  kostv-web
```

La web va compilada en WebAssembly, que es bastante más fluida que la versión
en JavaScript. Los navegadores que aún no lo admiten (Safari antiguo, el
navegador de algunas teles) cargan solos la versión en JavaScript, que viene
en la misma imagen. No hace falta configurar nada en el proxy.

El motor de dibujo de la web (la carpeta `canvaskit/`) va en la imagen y se
carga desde el propio servidor (`--no-web-resources-cdn`), no desde los
servidores de Google: así la web abre en casa aunque se caiga internet. Las
fuentes también van dentro, en `fonts/` (unos 26 MiB), y las baja
`scripts/fetch-web-fonts.sh` al compilar:

- las de reserva para lo que no traen las fuentes de la app (emojis, chino,
  japonés, símbolos…), unos 21 MiB;
- las 10 fuentes de subtítulos que se pueden elegir en Ajustes (normal y
  negrita de cada una), unos 5 MiB.

Con ellas dentro, la web no le pide ninguna fuente a `fonts.gstatic.com`. Si
se compila sin ese paso, o si en la compilación de GitHub no se han podido
bajar ni reintentándolo (entonces la imagen sale igual, con un aviso en el
registro del trabajo, y basta con relanzar ese trabajo), la web funciona igual,
pero esas fuentes las sigue pidiendo a Google. Las de `fonts/` llevan la versión en la ruta y nginx
deja que el navegador las guarde un año sin volver a preguntar.

En las apps de la tele y del móvil, la fuente de subtítulos que elijas se baja
de Google Fonts la primera vez y se queda guardada en el aparato.

Un archivo que no existe (`.js`, `.wasm`, `.json`, imágenes…) da un 404; solo
las rutas de la app vuelven a su página.

Los archivos están en [`docker/web/`](../docker/web/): el `Dockerfile`, la
configuración de nginx y `40-kostv-config.sh`, que escribe el `config.json` y la
pasarela a Stremfin al arrancar.

La imagen parte de `nginxinc/nginx-unprivileged` (el mismo nginx, preparado
para ir sin root): nginx y `40-kostv-config.sh` se ejecutan con el usuario 101,
que solo puede escribir lo que escribe ese script al arrancar (`config.json`,
`/etc/nginx/kostv*`) y lo temporal de nginx (`/tmp`, `/var/cache/nginx`); los
archivos de la app y la configuración de nginx son de root y no los puede
cambiar. También arranca con otro usuario (`--user`) mientras su grupo sea el
0.

## Al publicar: las pruebas antes de compilar

Cada versión y cada prueba pasan antes el analizador y las pruebas de la app
(el trabajo `release-checks` de `build.yml`, con los mismos comandos que
`checks.yml`). Si el analizador encuentra un error, o un aviso (*warning*) en
`lib/`, o falla alguna prueba, no se compilan los APK ni se publica nada. Las
pruebas que fallan se repiten una vez solas (algunas dependen del tiempo y
fallan de vez en cuando en GitHub); si vuelven a fallar, la versión no sale.

## Al publicar: la firma de los APK

Cada versión y cada prueba comprueban, antes de publicar, que los APK van
firmados con la clave de kOS TV: si faltan los secretos `ANDROID_KEYSTORE_BASE64`
o `ANDROID_KEY_ALIAS`, o el APK sale firmado con la clave de depuración de
Android, la compilación falla en lugar de publicar algo que no se instalaría
encima de la app de la familia.

Para que además compruebe que es **exactamente** nuestra clave, se puede crear
la variable del repositorio `KOSTV_SIGNING_SHA256` (en GitHub: **Settings →
Secrets and variables → Actions → Variables → New repository variable**; no es
un secreto) con la huella SHA-256 del certificado, con o sin los dos puntos.
Sale de `keytool -list -v -keystore kostv-release.jks -alias <alias>` (la línea
`SHA256:`) o de un APK ya publicado, con
`apksigner verify --print-certs KosTV_AndroidTV.apk` (la línea
`certificate SHA-256 digest`). Sin la variable, solo se comprueba que no sea la
clave de depuración.
