#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 4 ]] || exit 64
version=$1 backend=$2 web=$3 registry_user=$4
[[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 64
[[ "$backend" =~ ^ghcr\.io/vlad230596/familyapp-backend@sha256:[a-f0-9]{64}$ ]] || exit 64
[[ "$web" =~ ^ghcr\.io/vlad230596/familyapp-web@sha256:[a-f0-9]{64}$ ]] || exit 64
[[ "$registry_user" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 64
exec 9>/opt/familyapp/deploy.lock
flock -n 9 || exit 75
cd /opt/familyapp
# Keep registry credentials isolated from other applications and delete on exit.
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf -- "$DOCKER_CONFIG"' EXIT
IFS= read -r registry_token
printf '%s' "$registry_token" | docker login ghcr.io -u "$registry_user" --password-stdin >/dev/null
unset registry_token
docker pull "$backend"
docker pull "$web"
for image in "$backend" "$web"; do
    [[ "$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' "$image")" == "$version" ]] || exit 65
done
if [[ -f .release.env ]]; then
    # SQLite's backup API gives a consistent snapshot while requests continue.
    install -d -m 700 backups
    backup="backups/before-${version}-$(date -u +%Y%m%dT%H%M%SZ).sqlite3"
    docker compose --env-file .release.env -f compose.prod.yaml exec -T backend python -c \
        'import sqlite3,sys; source=sqlite3.connect("/data/familyapp.sqlite3"); target=sqlite3.connect("/tmp/backup.sqlite3"); source.backup(target); target.close(); sys.stdout.buffer.write(open("/tmp/backup.sqlite3", "rb").read())' > "$backup"
    test -s "$backup"
    cp .release.env .release.env.previous
fi
printf 'BACKEND_IMAGE=%s\nWEB_IMAGE=%s\n' "$backend" "$web" > .release.env.next
mv .release.env.next .release.env
docker compose --env-file .release.env -f compose.prod.yaml up -d --no-build --wait --wait-timeout 180
origin=https://famly-app.duckdns.org:8443
curl --fail --silent --show-error --retry 8 --retry-delay 5 "$origin/health" | grep -q '"status":"ok"'
[[ "$(curl --silent --show-error -o /dev/null -w '%{http_code}' "$origin/api/me")" == 401 ]]
curl --fail --silent --show-error "$origin/" | grep -q flutter_bootstrap.js
echo "FamilyApp $version deployed."
