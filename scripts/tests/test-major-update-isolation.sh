#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for pair in n8n:3 stalwart-mail:1 portainer-agent:3; do
  legacy="${pair%:*}"
  version="${pair#*:}"
  app="$legacy-v$version"
  jq -e --arg id "$app" '.metadata.id == $id' "$REPO/apps/$app/app.json" >/dev/null
  jq -e '.metadata.name | endswith("(Legacy)")' "$REPO/apps/$legacy/app.json" >/dev/null
  image="$(jq -r '.technical.main_image' "$REPO/apps/$legacy/app.json")"
  jq -e --arg file "apps/$legacy/docker-compose.yml" --arg image "$image" '[.packageRules[] | select(.enabled == false and .matchFileNames == [$file] and (.matchPackageNames | index($image)))] | length == 1' "$REPO/renovate.json" >/dev/null
  main="$(jq -r '.technical.main_service' "$REPO/apps/$app/app.json")"
  yq -e ".services.\"$main\"" "$REPO/apps/$app/docker-compose.yml" >/dev/null
  old_volumes="$(yq -r '(.volumes // {}) | keys | .[]' "$REPO/apps/$legacy/docker-compose.yml")"
  new_volumes="$(yq -r '(.volumes // {}) | keys | .[]' "$REPO/apps/$app/docker-compose.yml")"
  while IFS= read -r volume; do
    [[ -z "$volume" ]] && continue
    if printf '%s\n' "$old_volumes" | grep -Fxq "$volume"; then
      printf 'FAIL: %s reuses legacy volume %s\n' "$app" "$volume"
      exit 1
    fi
  done <<< "$new_volumes"
  printf 'ok: %s has separate identity, storage, and scoped legacy pin\n' "$app"
done
yq -e '.services["big-bear-stalwart-mail-v1"].volumes | contains(["stalwart-mail-v1_config:/etc/stalwart", "stalwart-mail-v1_data:/var/lib/stalwart"])' "$REPO/apps/stalwart-mail-v1/docker-compose.yml" >/dev/null
yq -e '.services["big-bear-stalwart-mail-v1"].ports | contains(["443:443/tcp", "995:995/tcp"])' "$REPO/apps/stalwart-mail-v1/docker-compose.yml" >/dev/null
