#!/usr/bin/env bash

# Exit the script as soon as something fails.
set -e

LOCATIONS=()
UPSTREAMS=()

LOCATIONS_FILE=$NGINX_INSTALL_PATH/conf.d/locations.conf
UPSTREAMS_FILE=$NGINX_INSTALL_PATH/conf.d/upstreams.conf

# Update placeholder vars to be taken from ENV vars

PLACEHOLDER_SERVER_NAME="${SERVER_NAME:-_}"
PLACEHOLDER_SERVER_TYPE="${SERVER_TYPE:-http}"
PLACEHOLDER_CLIENT_MAX_BODY_SIZE="${CLIENT_MAX_BODY_SIZE:-1m}"

upstream_exists () {
  for i in "${UPSTREAMS[@]}"; do
    if [[ "$1" == "$i" ]]; then
      return 0
    fi
  done

  return 1
}

location_exists () {
  for i in "${LOCATIONS[@]}"; do
    if [[ "$1" == "$i" ]]; then
      return 0
    fi
  done

  return 1
}

function create_upstream() {
cat <<EOF
upstream $1 {
  server $2:$3;
}
EOF
}

function create_location() {
cat <<EOF
location ~ ^$1 {
  rewrite $1(.*) $3\$1 break;
  proxy_set_header Host \$http_host;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
  proxy_redirect off;
  proxy_pass http://$2;
}
EOF
}

function create_assets_location() {
cat <<EOF
location ~ ^${1}/?assets/ {
  root /${2}/public;
  gzip_static on;
  expires max;
  add_header Cache-Control public;
  add_header Last-Modified "";
  add_header ETag "";
}
EOF
}

if [[ "$SERVER_BACKENDS" == "" ]]; then
  echo "No backends defined!"
else
  echo "" > $UPSTREAMS_FILE
  echo "" > $LOCATIONS_FILE

  IFS=',' read -ra PROVIDED_BACKENDS <<< "$SERVER_BACKENDS"
  IFS=$'\n' SORTED_BACKENDS=($(sort -r <<<"${PROVIDED_BACKENDS[*]}"))

  for backend in "${SORTED_BACKENDS[@]}"; do
    IFS=':' read -ra SETTINGS <<< "$backend"

    if (( ${#SETTINGS[@]} >= 3 )); then
      path="${SETTINGS[0]}"
      cont="${SETTINGS[1]}"
      port="${SETTINGS[2]}"
      dest="${SETTINGS[3]:-$path}"
      upstream="$cont-$port"

      echo "Configuring NGINX route: '$path' => '$cont:$port$dest' (using upstream: '$upstream')"
      
      if upstream_exists $upstream; then
        echo "WARNING! Duplicate upstream: '$upstream' for backend: '$backend' :: Using existing upstream definition..."
      else
        UPSTREAMS+=("$upstream")      
        echo "$(create_upstream $upstream $cont $port)" >> $UPSTREAMS_FILE
      fi

      if [ -d /$cont/public ]; then
        echo "$(create_assets_location $path $cont)" >> $LOCATIONS_FILE
      fi

      if location_exists $path; then
        echo "ERROR! Location conflict: '$path' is already registered!"
        exit 1
      else
        LOCATIONS+=("$path")
        echo "$(create_location $path $upstream $dest)" >> $LOCATIONS_FILE
      fi
    fi
  done
fi

sed -i "s/PLACEHOLDER_SERVER_TYPE/${PLACEHOLDER_SERVER_TYPE}/g" "${NGINX_INSTALL_PATH}/nginx.conf"

for conf in $NGINX_INSTALL_PATH/conf.d/*.conf; do
  sed -i "s/PLACEHOLDER_SERVER_NAME/${PLACEHOLDER_SERVER_NAME}/g" "${conf}"
  sed -i "s/PLACEHOLDER_CLIENT_MAX_BODY_SIZE/${PLACEHOLDER_CLIENT_MAX_BODY_SIZE}/g" "${conf}"
done 

# Execute the CMD from the Dockerfile and pass in all of its arguments.
exec "$@"
