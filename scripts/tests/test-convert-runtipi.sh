#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONVERTER="${CONVERTER:-$REPO/scripts/convert-to-platforms.sh}"

fail=0
assert_eq() { # $1=actual $2=expected $3=label
  if [[ "$1" != "$2" ]]; then echo "FAIL: $3 — got '$1' want '$2'"; fail=1; else echo "ok: $3"; fi
}

TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT

bash "$CONVERTER" -p runtipi -a cinedock -o "$TMP_OUT" >/dev/null 2>&1

SOURCE_IMAGE=$(yq eval '.services.cinedock.image' "$REPO/apps/cinedock/docker-compose.yml")
RUNTIPI_IMAGE=$(jq -r '.services[] | select(.isMain == true).image' "$TMP_OUT/runtipi/cinedock/docker-compose.json")
MAIN_IMAGE=$(jq -r '.technical.main_image' "$REPO/apps/cinedock/app.json")
VERSION=$(jq -r '.metadata.version' "$REPO/apps/cinedock/app.json")
DIGEST=${SOURCE_IMAGE##*@sha256:}

if [[ "$SOURCE_IMAGE" == "$MAIN_IMAGE:$VERSION@sha256:"* ]] && [[ "$DIGEST" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ok: CineDock source image is digest-pinned"
else
  echo "FAIL: CineDock source image is not digest-pinned"
  fail=1
fi

assert_eq "$RUNTIPI_IMAGE" "$SOURCE_IMAGE" "Runtipi preserves CineDock image digest"

exit $fail
