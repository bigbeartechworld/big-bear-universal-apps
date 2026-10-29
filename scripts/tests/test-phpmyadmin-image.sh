#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
APP="$REPO/apps/phpmyadmin"

jq -e '.technical.main_image == "phpmyadmin" and .metadata.homepage == "https://hub.docker.com/_/phpmyadmin"' "$APP/app.json" >/dev/null
IMAGE="$(yq eval '.services.phpmyadmin.image' "$APP/docker-compose.yml")"
VERSION="$(jq -r '.metadata.version' "$APP/app.json")"
[[ "$IMAGE" =~ ^phpmyadmin:${VERSION}@sha256:[a-f0-9]{64}$ ]]

OUTPUT="$(mktemp -d)"
trap 'rm -rf "$OUTPUT"' EXIT
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a phpmyadmin -o "$OUTPUT" >/dev/null
CONVERTED="$OUTPUT/casaos/phpmyadmin/docker-compose.yml"
[[ "$(yq eval '.services.phpmyadmin.image' "$CONVERTED")" == "$IMAGE" ]]
echo "ok: phpMyAdmin uses the pinned official image in source and CasaOS output"
