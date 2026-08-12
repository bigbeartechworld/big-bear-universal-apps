#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONVERTER="${CONVERTER:-$REPO/scripts/convert-to-platforms.sh}"

fail=0
assert_eq() { # $1=actual $2=expected $3=label
  if [[ "$1" != "$2" ]]; then echo "FAIL: $3 — got '$1' want '$2'"; fail=1; else echo "ok: $3"; fi
}

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

CINEDOCK_OUT="$TMP_ROOT/cinedock-out"
bash "$CONVERTER" -p runtipi -a cinedock -o "$CINEDOCK_OUT" >/dev/null 2>&1

SOURCE_IMAGE=$(yq eval '.services.cinedock.image' "$REPO/apps/cinedock/docker-compose.yml")
RUNTIPI_IMAGE=$(jq -r '.services[] | select(.isMain == true).image' "$CINEDOCK_OUT/runtipi/cinedock/docker-compose.json")
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

# A multi-service, unpinned fixture proves that technical.main_service wins
# over alphabetical service order while retaining the legacy tag fallback.
FIXTURE_APPS="$TMP_ROOT/apps"
FIXTURE_DIR="$FIXTURE_APPS/unpinned"
FIXTURE_OUT="$TMP_ROOT/unpinned-out"
mkdir -p "$FIXTURE_DIR"
jq '.metadata.id = "unpinned" |
    .metadata.name = "Unpinned Test" |
    .metadata.version = "9.8.7" |
    .visual.icon = "" |
    .visual.thumbnail = "" |
    .visual.logo = "" |
    .technical.main_image = "example/unpinned" |
    .technical.main_service = "main-service" |
    .compatibility.runtipi.folder_name = "unpinned"' \
  "$REPO/apps/cinedock/app.json" > "$FIXTURE_DIR/app.json"
cp "$REPO/apps/cinedock/docker-compose.yml" "$FIXTURE_DIR/docker-compose.yml"
yq eval '.services."main-service" = .services.cinedock |
         .services."main-service".image = "example/unpinned:9.8.7" |
         del(.services.cinedock) |
         .services."aaa-helper".image = "example/helper:1"' \
  -i "$FIXTURE_DIR/docker-compose.yml"

bash "$CONVERTER" -p runtipi -a unpinned -i "$FIXTURE_APPS" -o "$FIXTURE_OUT" >/dev/null 2>&1
UNPINNED_IMAGE=$(jq -r '.services[] | select(.isMain == true).image' "$FIXTURE_OUT/runtipi/unpinned/docker-compose.json")
assert_eq "$UNPINNED_IMAGE" "example/unpinned:9.8.7" "Unpinned main service retains tag-derived image"
assert_eq "$(yq eval '.services.unpinned.image' "$FIXTURE_OUT/runtipi/unpinned/docker-compose.yml")" \
  "example/unpinned:9.8.7" "Configured main service is renamed"
assert_eq "$(yq eval '.services."aaa-helper".image' "$FIXTURE_OUT/runtipi/unpinned/docker-compose.yml")" \
  "example/helper:1" "Helper service is preserved"

# Any digest marker must be a complete, end-anchored SHA-256 value.
assert_digest_rejected() { # $1=image $2=output slug $3=label
  yq eval ".services.\"main-service\".image = \"$1\"" -i "$FIXTURE_DIR/docker-compose.yml"
  if bash "$CONVERTER" -p runtipi -a unpinned -i "$FIXTURE_APPS" -o "$TMP_ROOT/$2-out" >/dev/null 2>&1; then
    echo "FAIL: $3 was accepted"
    fail=1
  else
    echo "ok: $3 is rejected"
  fi
}

assert_digest_rejected "example/unpinned:9.8.7@sha256:abc123" \
  "short-digest" "short SHA-256 digest"
assert_digest_rejected "example/unpinned:9.8.7@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-trailing" \
  "trailing-digest" "SHA-256 digest with trailing content"

exit $fail
