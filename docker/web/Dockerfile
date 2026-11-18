# kOS TV para el navegador: la app web, servida por nginx.
#
# La imagen no lleva ninguna dirección ni contraseña: el contenedor las recibe
# en sus variables (KOSTV_SERVER_URL, KOSTV_REQUESTS_URL, KOSTV_ADMIN_USER,
# KOSTV_ADMIN_PASSWORD) y al arrancar escribe con ellas el config.json que lee
# la app y la entrada a /admin. Ver docs/web.md.
#
# Se construye desde la raíz del repositorio, después de compilar la web:
#   flutter build web --wasm --release
#   docker build -f docker/web/Dockerfile -t kostv-web .
FROM nginx:1.29-alpine

LABEL org.opencontainers.image.title="kOS TV (web)" \
      org.opencontainers.image.description="kOS TV en el navegador: cliente de Jellyfin para la familia" \
      org.opencontainers.image.source="https://github.com/kikope97/kos-TV" \
      org.opencontainers.image.licenses="GPL-2.0-or-later"

# The certificates the requests service's is checked against.
RUN apk add --no-cache ca-certificates

COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 docker/web/40-kostv-config.sh /docker-entrypoint.d/40-kostv-config.sh
COPY build/web /usr/share/nginx/html

# Kos TV: what takes long to arrive on a phone, compressed once and at the
# most (nginx sends the .gz as it is, gzip_static) instead of on each
# request at its lightest; and each file's date taken from its content, so
# the ETag only changes when the file does and a new version doesn't make
# the browser fetch again what is the same. config.json is written when the
# container starts, so it is left out.
RUN cd /usr/share/nginx/html \
 && find . -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.wasm' -o -name '*.json' \
      -o -name '*.ttf' -o -name '*.otf' -o -name '*.css' -o -name '*.svg' -o -name '*.html' \) \
      ! -name config.json -size +1k \
      -exec sh -c 'gzip -9 -n -c "$1" > "$1.gz"' _ {} \; \
 && find . -type f ! -name config.json | while read -r f; do \
      h=$(sha256sum "$f" | cut -c1-7); touch -d "@$((0x$h + 1000000000))" "$f"; \
    done
COPY docker/web/admin /usr/share/nginx/admin

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
