#!/bin/sh
# kOS TV: before nginx starts, writes the web app's config.json and the way
# in to the requests service from the container's variables:
#
#   KOSTV_SERVER_URL    the household Jellyfin, as the browser reaches it
#                       (https://..., public). The app opens straight on its
#                       sign-in.
#   KOSTV_REQUESTS_URL  optional, for the move only: the requests service
#                       (Stremfin), as this container reaches it. The browser
#                       then talks to it through this site, at /stremfin, so
#                       the service needs no CORS. Without it the web app
#                       talks to the address the home server's plugin gives,
#                       as the other apps do (the service has to accept the
#                       web's address, CORS).
#
# Either may be left out: without the first the app asks for a server.
#
#   KOSTV_ADMIN_USER      the admin panel's user (admin if left out).
#   KOSTV_ADMIN_PASSWORD  its password (or KOSTV_ADMIN_PASSWORD_FILE, a file
#                         holding it, for Docker secrets). Without one, /admin
#                         stays closed.
set -eu

html=/usr/share/nginx/html
includes=/etc/nginx/kostv
mkdir -p "$includes"
rm -f "$includes"/*.conf

log() { echo "kostv: $*"; }

# Trims spaces, trailing slashes and a trailing /api/v1.
clean() {
  value=$(printf '%s' "$1" | tr -d ' \t\r\n')
  while [ "${value%/}" != "$value" ]; do value=${value%/}; done
  value=${value%/api/v1}
  while [ "${value%/}" != "$value" ]; do value=${value%/}; done
  printf '%s' "$value"
}

# An http(s) address made of the characters an address can hold, so it can
# go into JSON and nginx's configuration as it is.
check_url() {
  name=$1 value=$2
  [ -z "$value" ] && return 0
  if ! printf '%s' "$value" | grep -Eq '^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$'; then
    log "$name no es una dirección válida (http:// o https://, sin espacios ni comillas): $value" >&2
    exit 1
  fi
}

server=$(clean "${KOSTV_SERVER_URL:-}")
requests=$(clean "${KOSTV_REQUESTS_URL:-}")
check_url KOSTV_SERVER_URL "$server"
check_url KOSTV_REQUESTS_URL "$requests"

server_json=null
if [ -n "$server" ]; then
  server_json="\"$server\""
  log "servidor de casa configurado"
else
  log "sin KOSTV_SERVER_URL: la app pedirá la dirección del servidor"
fi

requests_json=null
if [ -n "$requests" ]; then
  # https://host:port/path -> origin and path, since nginx passes a path
  # given in a variable as it is.
  scheme=${requests%%://*}
  rest=${requests#*://}
  hostport=${rest%%/*}
  path=""
  [ "$rest" != "$hostport" ] && path="/${rest#*/}"
  host=${hostport%%:*}

  # The DNS server the container uses, looked up per request so the service
  # being down when the container starts doesn't stop nginx.
  resolver=$(awk '/^nameserver/ { print $2; exit }' /etc/resolv.conf 2>/dev/null || true)
  [ -z "$resolver" ] && resolver=127.0.0.11
  case "$resolver" in *:*) resolver="[$resolver]" ;; esac

  cat > "$includes/stremfin.conf" <<NGINX
# Written by 40-kostv-config.sh from KOSTV_REQUESTS_URL.
location /stremfin/ {
    resolver $resolver valid=60s;
    resolver_timeout 5s;
    set \$kostv_stremfin "$scheme://$hostport";
    rewrite ^/stremfin/(.*)\$ $path/\$1 break;
    proxy_pass \$kostv_stremfin;
    proxy_http_version 1.1;
    proxy_set_header Host $hostport;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_ssl_server_name on;
    proxy_ssl_name $host;
    proxy_connect_timeout 10s;
    proxy_read_timeout 60s;
    # Every call carries the person's token: keep it out of the log.
    access_log off;
}
NGINX
  requests_json='"/stremfin"'
  log "servicio de peticiones configurado (en /stremfin)"
else
  log "sin KOSTV_REQUESTS_URL: la web usará la dirección de Stremfin que da el complemento"
fi

# The admin panel at /admin, behind a user and password. The password is
# kept only as a SHA-512 hash, readable by nginx alone.
admin_user=$(printf '%s' "${KOSTV_ADMIN_USER:-admin}" | tr -d '\r\n')
admin_password=${KOSTV_ADMIN_PASSWORD:-}
if [ -z "$admin_password" ] && [ -n "${KOSTV_ADMIN_PASSWORD_FILE:-}" ]; then
  if [ ! -r "$KOSTV_ADMIN_PASSWORD_FILE" ]; then
    log "no se puede leer KOSTV_ADMIN_PASSWORD_FILE: $KOSTV_ADMIN_PASSWORD_FILE" >&2
    exit 1
  fi
  admin_password=$(head -n 1 "$KOSTV_ADMIN_PASSWORD_FILE" | tr -d '\r')
fi
admin_htpasswd=/etc/nginx/kostv-admin.htpasswd
rm -f "$admin_htpasswd"
if [ -n "$admin_password" ]; then
  if [ -z "$admin_user" ] || printf '%s' "$admin_user" | grep -q '[[:space:]:]'; then
    log "KOSTV_ADMIN_USER no puede estar vacío ni llevar espacios ni dos puntos" >&2
    exit 1
  fi
  if [ "${#admin_password}" -lt 10 ]; then
    log "aviso: la contraseña de /admin es corta; usa al menos 10 caracteres" >&2
  fi
  hash=$(printf '%s' "$admin_password" | mkpasswd -m sha512 -s)
  printf '%s:%s\n' "$admin_user" "$hash" > "$admin_htpasswd"
  chown root:nginx "$admin_htpasswd"
  chmod 640 "$admin_htpasswd"
  cat > "$includes/admin.conf" <<NGINX
# Written by 40-kostv-config.sh from KOSTV_ADMIN_USER and KOSTV_ADMIN_PASSWORD.
location = /admin {
    return 301 /admin/;
}
location /admin/ {
    auth_basic "kOS TV - Administracion";
    auth_basic_user_file $admin_htpasswd;
    limit_req zone=kostv_admin burst=30 nodelay;
    limit_req_status 429;
    alias /usr/share/nginx/admin/;
    index index.html;
    add_header Cache-Control "no-store" always;
    add_header X-Robots-Tag "noindex, nofollow" always;
    add_header X-Frame-Options "DENY" always;
}
NGINX
  log "panel de administración en /admin (usuario: $admin_user)"
else
  cat > "$includes/admin.conf" <<NGINX
# Written by 40-kostv-config.sh: no KOSTV_ADMIN_PASSWORD, so /admin is closed.
location /admin {
    default_type text/plain;
    charset utf-8;
    return 403 "El panel de administración está cerrado: falta KOSTV_ADMIN_PASSWORD.\n";
}
NGINX
  log "sin KOSTV_ADMIN_PASSWORD: /admin queda cerrado"
fi

cat > "$html/config.json" <<JSON
{
  "schemaVersion": 1,
  "brandingName": "kOS TV",
  "pluginMode": false,
  "enableWebRtcScan": false,
  "defaultServerUrl": null,
  "forcedServerUrl": null,
  "discoveryProxyUrl": null,
  "serverUrl": $server_json,
  "requestsUrl": $requests_json
}
JSON
