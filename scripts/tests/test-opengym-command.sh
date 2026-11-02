#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
COMPOSE="$REPO/apps/opengym/docker-compose.yml"
MEDIA_COMMAND=$(yq eval '.services.media.command[0]' "$COMPOSE")

[[ "$(yq eval '.services.media.command | length' "$COMPOSE")" == "1" ]]
[[ "$MEDIA_COMMAND" != *$'\n'* ]]
[[ "$(yq eval '.services.media.entrypoint | join(" ")' "$COMPOSE")" == "/bin/sh -c" ]]
printf '%s\n' "${MEDIA_COMMAND//\$\$/\$}" | sh -n

TMP_OUT=$(mktemp -d)
trap 'rm -rf "$TMP_OUT"' EXIT
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a opengym -o "$TMP_OUT" >/dev/null
GENERATED="$TMP_OUT/casaos/opengym/docker-compose.yml"
[[ "$(yq eval '.services.media.command[0]' "$GENERATED")" == "$MEDIA_COMMAND" ]]
[[ "$(yq eval '.services.media.entrypoint | join(" ")' "$GENERATED")" == "/bin/sh -c" ]]
echo "ok: openGym shell command survives CasaOS conversion as a single line argument"
