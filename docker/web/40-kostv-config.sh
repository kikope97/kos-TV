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
#   KOSTV_REQUESTS_VERIFY on (by default) checks the requests service's
#                       certificate; off only for one with a certificate of
#                       its own on the home network.
#
#   KOSTV_ADMIN_USER      the admin panel's user (admin if left out).
#   KOSTV_ADMIN_PASSWORD  its password (or KOSTV_ADMIN_PASSWORD_FILE, a file
#                         holding it, for Docker secrets). Without one, /admin
#                         stays closed.
#
#   KOSTV_TRUSTED_PROXY   optional: the address (or addresses, or CIDR
#                         ranges, separated by commas or spaces) of the
#                         reverse proxy in front, as it reaches this
#                         container. Only then is X-Forwarded-For believed,
#                         and only from it, and /admin counts its limit per
#                         visitor instead of one for everyone coming through
#                         the proxy. Without it, as before: the visitor's
#                         address in the logs comes from X-Forwarded-For sent
#                         by any address on the home network, and /admin
#                         counts by the address that reached the container.
set -eu

html=/usr/share/nginx/html
includes=/etc/nginx/kostv
http_includes=/etc/nginx/kostv-http
mkdir -p "$includes" "$http_includes"
rm -f "$includes"/*.conf "$http_includes"/*.conf

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

  verify=on
  case "${KOSTV_REQUESTS_VERIFY:-on}" in
    off|false|0|no)
      verify=off
      log "aviso: no se comprueba el certificado del servicio de peticiones (KOSTV_REQUESTS_VERIFY=off)" >&2
      ;;
  esac

  cat > "$includes/stremfin.conf" <<NGINX
# Written by 40-kostv-config.sh from KOSTV_REQUESTS_URL. Only the service's
# API (what the app uses), not the rest of it (its own web, its admin).
location ^~ /stremfin/api/v1/ {
    resolver $resolver valid=60s;
    resolver_timeout 5s;
    set \$kostv_stremfin "$scheme://$hostport";
    rewrite ^/stremfin/api/v1/(.*)\$ $path/api/v1/\$1 break;
    proxy_pass \$kostv_stremfin;
    proxy_http_version 1.1;
    proxy_set_header Host $hostport;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_ssl_server_name on;
    proxy_ssl_name $host;
    # The service's certificate is checked, as the apps do (unless
    # KOSTV_REQUESTS_VERIFY=off, for one of its own on the home network).
    proxy_ssl_verify $verify;
    proxy_ssl_verify_depth 3;
    proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
    proxy_connect_timeout 10s;
    proxy_read_timeout 60s;
    # Every call carries the person's token: keep it out of the log.
    access_log off;
}
location ^~ /stremfin/ {
    return 404;
}
NGINX
  requests_json='"/stremfin"'
  log "servicio de peticiones configurado (en /stremfin)"
else
  log "sin KOSTV_REQUESTS_URL: la web usará la dirección de Stremfin que da el complemento"
fi

# Who X-Forwarded-For is believed from, and what the admin panel's limit
# counts by. $realip_remote_addr is the address that reached the container,
# whatever a request says; $remote_addr is the visitor's address, taken from
# X-Forwarded-For when the request came from a trusted address.
trusted=$(printf '%s' "${KOSTV_TRUSTED_PROXY:-}" | tr ',\t\r\n' '    ' | tr -s ' ' | sed 's/^ //; s/ $//')
if [ -n "$trusted" ]; then
  realip_from=""
  for address in $trusted; do
    if ! printf '%s' "$address" | grep -Eq '^[0-9A-Fa-f:.]+(/[0-9]{1,3})?$'; then
      log "KOSTV_TRUSTED_PROXY tiene que ser la IP del proxy (o un rango como 172.16.0.0/12): $address" >&2
      exit 1
    fi
    realip_from="${realip_from}set_real_ip_from $address;
"
  done
  # shellcheck disable=SC2016 # nginx's variable, written as it is
  admin_key='$remote_addr'
  log "proxy de confianza: $trusted (/admin cuenta su límite por cada visitante)"
else
  realip_from="set_real_ip_from 10.0.0.0/8;
set_real_ip_from 172.16.0.0/12;
set_real_ip_from 192.168.0.0/16;
set_real_ip_from 127.0.0.0/8;
"
  # shellcheck disable=SC2016
  admin_key='$realip_remote_addr'
fi
cat > "$includes/realip.conf" <<NGINX
# Written by 40-kostv-config.sh (KOSTV_TRUSTED_PROXY): where the visitor's
# address is taken from X-Forwarded-For, for the logs and the limits.
${realip_from}real_ip_header X-Forwarded-For;
real_ip_recursive on;
NGINX
cat > "$http_includes/admin-limit.conf" <<NGINX
# Written by 40-kostv-config.sh: slows down guessing the admin password, 30
# requests a minute per address, with room for a page's own files. Never
# by an address a request merely claims: X-Forwarded-For counts only from
# KOSTV_TRUSTED_PROXY, so changing it on each try doesn't get past the limit.
limit_req_zone $admin_key zone=kostv_admin:1m rate=30r/m;
NGINX

# The admin panel at /admin, behind a user and password. The password is
# kept only as a SHA-512 hash, readable by nginx alone: this runs as nginx's
# user (see the Dockerfile), so the file is its own and no one else's.
admin_user=$(printf '%s' "${KOSTV_ADMIN_USER:-admin}" | tr -d '\r\n')
admin_password=${KOSTV_ADMIN_PASSWORD:-}
if [ -z "$admin_password" ] && [ -n "${KOSTV_ADMIN_PASSWORD_FILE:-}" ]; then
  if [ ! -r "$KOSTV_ADMIN_PASSWORD_FILE" ]; then
    log "no se puede leer KOSTV_ADMIN_PASSWORD_FILE: $KOSTV_ADMIN_PASSWORD_FILE" >&2
    exit 1
  fi
  admin_password=$(head -n 1 "$KOSTV_ADMIN_PASSWORD_FILE" | tr -d '\r')
fi
admin_htpasswd=/etc/nginx/kostv-auth/admin.htpasswd
rm -f "$admin_htpasswd"
if [ -n "$admin_password" ]; then
  if [ -z "$admin_user" ] || printf '%s' "$admin_user" | grep -q '[[:space:]:]'; then
    log "KOSTV_ADMIN_USER no puede estar vacío ni llevar espacios ni dos puntos" >&2
    exit 1
  fi
  if [ "${#admin_password}" -lt 10 ]; then
    log "la contraseña de /admin es demasiado corta: usa al menos 10 caracteres" >&2
    exit 1
  fi
  hash=$(printf '%s' "$admin_password" | mkpasswd -m sha512 -s)
  (umask 077 && printf '%s:%s\n' "$admin_user" "$hash" > "$admin_htpasswd")
  cat > "$includes/admin.conf" <<NGINX
# Written by 40-kostv-config.sh from KOSTV_ADMIN_USER and KOSTV_ADMIN_PASSWORD.
location = /admin {
    return 301 /admin/;
}
location ^~ /admin/ {
    auth_basic "kOS TV - Administracion";
    auth_basic_user_file $admin_htpasswd;
    limit_req zone=kostv_admin burst=30 nodelay;
    limit_req_status 429;
    alias /usr/share/nginx/admin/;
    index index.html;
    add_header Cache-Control "no-store" always;
    add_header X-Robots-Tag "noindex, nofollow" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;
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

# Written now, so never a compressed copy from the image in its place.
rm -f "$html/config.json.gz"
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
