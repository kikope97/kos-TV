# kOS TV para el navegador: la app web, servida por nginx.
#
# La imagen no lleva ninguna dirección: el contenedor las recibe en sus
# variables (KOSTV_SERVER_URL, KOSTV_REQUESTS_URL) y al arrancar escribe con
# ellas el config.json que lee la app. Ver docs/web.md.
#
# Se construye desde la raíz del repositorio, después de compilar la web:
#   flutter build web --release
#   docker build -f docker/web/Dockerfile -t kostv-web .
FROM nginx:1.29-alpine

LABEL org.opencontainers.image.title="kOS TV (web)" \
      org.opencontainers.image.description="kOS TV en el navegador: cliente de Jellyfin para la familia" \
      org.opencontainers.image.source="https://github.com/kikope97/kos-TV" \
      org.opencontainers.image.licenses="GPL-2.0-or-later"

COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 docker/web/40-kostv-config.sh /docker-entrypoint.d/40-kostv-config.sh
COPY build/web /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
