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
   administración. El `compose.yml` no hace falta tocarlo: lee todo del `.env`.
3. Arráncalo:

   ```bash
   docker compose up -d
   docker compose logs kostv-web   # dice qué ha configurado
   ```

4. En el proxy inverso, apunta un subdominio con https (por ejemplo
   `https://kostv.example.com`) al puerto 25670 de ese servidor.

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
   principio de una variable.
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
| `KOSTV_ADMIN_USER` | El usuario del panel de administración | `admin` |
| `KOSTV_ADMIN_PASSWORD` | Su contraseña (al menos 10 caracteres). En lugar de ella se puede usar `KOSTV_ADMIN_PASSWORD_FILE`, la ruta de un archivo que la contenga (para los *secrets* de Docker) | `/admin` queda cerrado |

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
  queda para la transición). El token de la sesión no queda en ningún
  registro.

## Panel de administración (`/admin`)

De momento es un panel en blanco que iremos llenando (módulos, dispositivos,
servicios de casa). Al entrar, el navegador pide el usuario y la contraseña de
`KOSTV_ADMIN_USER` y `KOSTV_ADMIN_PASSWORD`.

- La contraseña no se guarda tal cual: al arrancar, el contenedor guarda solo
  su huella cifrada (SHA-512), que únicamente puede leer nginx.
- Tras unos 30 intentos seguidos, responde "demasiadas peticiones" durante un
  rato, para frenar a quien intente adivinarla.
- Sin contraseña, `/admin` queda cerrado.
- Para salir, cierra el navegador (con este tipo de acceso no hay botón de
  cerrar sesión; llegará con el admin de verdad).
- **Si la contraseña lleva `$`**, ponla entre comillas simples en el `.env`
  (`KOSTV_ADMIN_PASSWORD='mi$clave'`): sin ellas, Docker Compose toma `$clave`
  por una variable y la contraseña cambia.

## Actualizar

Cada versión publicada de kOS TV, y cada prueba, sube también la imagen web:

| Etiqueta | Qué es |
|---|---|
| `latest` | Siempre la última imagen compilada, sea una versión publicada o una prueba. Es la que usa el `compose.yml` de arriba |
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
flutter build web --release
docker build -f docker/web/Dockerfile -t kostv-web .
docker run --rm -p 25670:80 \
  -e KOSTV_SERVER_URL=https://jellyfin.example.com \
  kostv-web
```

Los archivos están en [`docker/web/`](../docker/web/): el `Dockerfile`, la
configuración de nginx y `40-kostv-config.sh`, que escribe el `config.json` y la
pasarela a Stremfin al arrancar.
