# kOS TV en el navegador (Docker)

La versión web de kOS TV es la misma app que la de la tele y el móvil, para
abrirla desde cualquier navegador (ordenador, tablet, móvil, la tele de un
hotel…). Se instala en el servidor de casa como un contenedor Docker.

La imagen **no lleva ninguna dirección dentro**: se le dan en las variables
del contenedor y, al arrancar, las escribe en el `config.json` que lee la app.
Así la misma imagen sirve para cualquiera y las direcciones no salen del
servidor.

## Lo que hace falta

- **Docker** (con Docker Compose) en el servidor.
- **Una dirección con https** para la web, por ejemplo un subdominio en el
  proxy inverso que ya uses para Jellyfin (Nginx Proxy Manager, Traefik,
  Caddy…). Hace falta https: el navegador solo guarda la sesión de forma segura
  en sitios https, y Jellyfin también va por https.

## Puesta en marcha

`compose.yml` (las direcciones son de ejemplo):

```yaml
services:
  kostv-web:
    image: ghcr.io/kikope97/kos-tv-web:latest
    container_name: kostv-web
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      # Jellyfin tal como lo abre el navegador: la dirección pública, con https.
      KOSTV_SERVER_URL: https://jellyfin.example.com
      # El servicio de peticiones (Stremfin) tal como lo alcanza el contenedor.
      KOSTV_REQUESTS_URL: https://peticiones.example.com
```

```bash
docker compose up -d
docker compose logs kostv-web   # dice qué servicios ha configurado
```

Después, en el proxy inverso, apunta el subdominio de la web (por ejemplo
`https://kostv.example.com`) al puerto 8080 de ese servidor. Al abrirlo, la app
va directa al usuario y la contraseña de Jellyfin, igual que en la tele.

## Variables

| Variable | Qué es | Si no se pone |
|---|---|---|
| `KOSTV_SERVER_URL` | El Jellyfin de casa **tal como lo abre el navegador** de quien entra: la dirección pública, con https. No sirve una interna como `http://jellyfin:8096`, porque es el navegador quien habla con Jellyfin | La app pide la dirección del servidor |
| `KOSTV_REQUESTS_URL` | El servicio de peticiones (Stremfin) **tal como lo alcanza el contenedor**. Puede ser la pública o una interna (`http://stremfin:8080` si están en la misma red de Docker) | Descubrir no aparece |

Da igual que lleven o no la barra final o `/api/v1`. Una dirección mal escrita
detiene el contenedor con un mensaje en `docker compose logs`.

### Cómo llega cada cosa

- **Jellyfin**: el navegador habla directamente con él. Jellyfin acepta por
  defecto peticiones de otros sitios (CORS), así que no hay que tocar nada.
- **Stremfin**: el navegador no habla con él, sino con la propia web en
  `/stremfin`, y el contenedor se lo pasa al servicio. Por eso Stremfin no
  necesita CORS ni tiene por qué estar abierto a internet. El token de la
  sesión pasa por ahí, pero no queda en ningún registro.

## Actualizar

Cada versión publicada de kOS TV sube también la imagen web:

| Etiqueta | Qué es |
|---|---|
| `latest` | La última versión publicada (la de la familia) |
| `X.Y.Z` | Una versión concreta, por ejemplo `1.1.0` |
| `prueba` / `prueba-N` | Las compilaciones de prueba (como los APK de prueba) |

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

El contenedor hace de puerta de entrada a los servicios de casa: cuando llegue
el panel de administración, irá en este mismo `compose.yml`, y la web le
pasará las peticiones igual que hace ahora con Stremfin.

## Construir la imagen a mano

Desde la raíz del repositorio:

```bash
flutter build web --release
docker build -f docker/web/Dockerfile -t kostv-web .
docker run --rm -p 8080:80 \
  -e KOSTV_SERVER_URL=https://jellyfin.example.com \
  -e KOSTV_REQUESTS_URL=https://peticiones.example.com \
  kostv-web
```

Los archivos están en [`docker/web/`](../docker/web/): el `Dockerfile`, la
configuración de nginx y `40-kostv-config.sh`, que escribe el `config.json` y la
pasarela a Stremfin al arrancar.
