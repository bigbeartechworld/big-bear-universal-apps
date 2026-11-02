#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
COMPOSE="$REPO/apps/ente/docker-compose.yml"
IMAGE="$(yq eval '.services.minio.image' "$COMPOSE")"
[[ "$IMAGE" =~ ^bigbeartechworld/big-bear-minio:RELEASE\.[0-9T:Z-]+@sha256:[a-f0-9]{64}$ ]]
INIT_IMAGE="$(yq eval '.services.minio-init.image' "$COMPOSE")"
[[ "$INIT_IMAGE" =~ ^pgsty/silo@sha256:[a-f0-9]{64}$ ]]
[[ "$(yq eval '.services.minio-init.entrypoint' "$COMPOSE")" == /bin/sh\ -ec* ]]

OUTPUT="$(mktemp -d)"
trap 'rm -rf "$OUTPUT"' EXIT
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a ente -o "$OUTPUT" >/dev/null
CONVERTED="$OUTPUT/casaos/ente/docker-compose.yml"
[[ "$(yq eval '.services.minio.image' "$CONVERTED")" == "$IMAGE" ]]
[[ "$(yq eval '.services.minio-init.image' "$CONVERTED")" == "$INIT_IMAGE" ]]
[[ "$(yq eval '.services.minio.command' "$CONVERTED")" == 'server /data --address ":3200" --console-address ":3201"' ]]
[[ "$(yq eval '.services.minio.ports[0]' "$CONVERTED")" == 3200:3200 ]]
[[ "$(yq eval '.services.minio.volumes[0]' "$CONVERTED")" == '/DATA/AppData/$AppID/minio_data:/data' ]]
echo "ok: Ente preserves the pinned Big Bear MinIO image and storage configuration in CasaOS output"
