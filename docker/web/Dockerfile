# kOS TV para el navegador: la app web, servida por nginx.
#
# La imagen no lleva ninguna dirección ni contraseña: el contenedor las recibe
# en sus variables (KOSTV_SERVER_URL, KOSTV_REQUESTS_URL, KOSTV_ADMIN_USER,
# KOSTV_ADMIN_PASSWORD…) y al arrancar escribe con ellas el config.json que
# lee la app y la entrada a /admin. Ver docs/web.md.
#
# Se construye desde la raíz del repositorio, después de compilar la web:
#   flutter build web --wasm --release --no-web-resources-cdn
#   bash scripts/fetch-web-fonts.sh build/web
#   docker build -f docker/web/Dockerfile -t kostv-web .

# Kos TV: the web prepared in a stage of its own, so the final image gets it
# in a single layer. Changing a file's date in a layer after the one that
# copied it stores the whole file again; here the copy, the compression and
# the dates all happen before, and COPY --from keeps the dates. It runs on
# the machine that builds (the files are the same for every platform), so
# no emulation is needed for ARM.
FROM --platform=$BUILDPLATFORM nginx:1.29-alpine AS web
COPY build/web /web
# Left out of the image, as the web never asks for them: the theme editor
# (it only opens from the server plugin's web, pluginMode) and the CJK font
# the apps' subtitles use (the web's own copy is in vendor/fonts).
#
# Then what takes long to arrive on a phone, compressed once and at the
# most (nginx sends the .gz as it is, gzip_static) instead of on each
# request at its lightest; and each file's date taken from its content, so
# the ETag only changes when the file does and a new version doesn't make
# the browser fetch again what is the same. config.json is written when the
# container starts, so it is left out.
RUN cd /web \
 && rm -rf theme assets/assets/fonts/NotoSansCJK-Regular.otf \
 && find . -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.wasm' -o -name '*.json' \
      -o -name '*.ttf' -o -name '*.otf' -o -name '*.css' -o -name '*.svg' -o -name '*.html' \) \
      ! -name config.json -size +1k \
      -exec sh -c 'gzip -9 -n -c "$1" > "$1.gz"' _ {} \; \
 && find . -type f ! -name config.json | while read -r f; do \
      h=$(sha256sum "$f" | cut -c1-7); touch -d "@$((0x$h + 1000000000))" "$f"; \
    done

# Kos TV: nginx's own image made to run without root (nginxinc's
# nginx-unprivileged, the same nginx and Alpine): it listens on 8080, as a
# port under 1024 needs root, and keeps its pid and temporary files in /tmp.
FROM nginxinc/nginx-unprivileged:1.29-alpine

LABEL org.opencontainers.image.title="kOS TV (web)" \
      org.opencontainers.image.description="kOS TV en el navegador: cliente de Jellyfin para la familia" \
      org.opencontainers.image.source="https://github.com/kikope97/kos-TV" \
      org.opencontainers.image.licenses="GPL-2.0-or-later"

# Root only while the image is built.
USER root

COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --chmod=755 docker/web/40-kostv-config.sh /docker-entrypoint.d/40-kostv-config.sh
COPY --from=web /web /usr/share/nginx/html
COPY docker/web/admin /usr/share/nginx/admin

# The certificates the requests service's is checked against.
#
# Then nginx's configuration is made root's again (the base image leaves it
# to nginx's user), so the server can't change its own; the app's files
# already are. What 40-kostv-config.sh writes at start are the only places
# nginx's user can write to: the includes, the admin password's hash and
# config.json. Group 0 too, as the base image does, so it also starts under
# another user given with --user.
RUN apk add --no-cache ca-certificates \
 && chown -R 0:0 /etc/nginx \
 && chmod -R go-w /etc/nginx \
 && mkdir -p /etc/nginx/kostv /etc/nginx/kostv-http /etc/nginx/kostv-auth \
 && chown 101:0 /etc/nginx/kostv /etc/nginx/kostv-http /etc/nginx/kostv-auth \
 && chmod 770 /etc/nginx/kostv /etc/nginx/kostv-http /etc/nginx/kostv-auth \
 && touch /usr/share/nginx/html/config.json \
 && chown 101:0 /usr/share/nginx/html/config.json \
 && chmod 664 /usr/share/nginx/html/config.json

USER 101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
