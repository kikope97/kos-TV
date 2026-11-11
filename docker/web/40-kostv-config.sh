#!/bin/sh
# kOS TV: before nginx starts, writes the web app's config.json and the way
# in to the requests service from the container's variables:
#
#   KOSTV_SERVER_URL    the household Jellyfin, as the browser reaches it
#                       (https://..., public). The app opens straight on its
#                       sign-in.
#   KOSTV_REQUESTS_URL  the requests service (Stremfin), as this container
#                       reaches it. The browser talks to it through this
#                       site, at /stremfin, so the service needs no CORS and
#                       can stay out of reach from outside.
#
# Either may be left out: without the first the app asks for a server, and
# without the second Discover doesn't show.
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
  log "sin KOSTV_REQUESTS_URL: Descubrir no aparecerá"
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
