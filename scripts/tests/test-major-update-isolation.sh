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
  legacy_config="$(docker compose -f "$REPO/apps/$legacy/docker-compose.yml" config --format json)"
  app_config="$(N8N_PUBLIC_URL=https://n8n.example.invalid AGENT_SECRET=TEST_ONLY_NOT_A_DEPLOYMENT_SECRET docker compose -f "$REPO/apps/$app/docker-compose.yml" config --format json)"
  shared_storage="$(jq -n --argjson legacy "$legacy_config" --argjson app "$app_config" '
    def storage_sources:
      . as $compose |
      [
        (.volumes // {} | .[] | "volume:" + .name),
        (.services[] | .volumes // [] | .[] |
          if .type == "volume" then
            "volume:" + ($compose.volumes[.source].name // .source)
          elif .type == "bind" then
            select(
              (.source == "/var/run/docker.sock" and .target == "/var/run/docker.sock") or
              (.source == "/var/lib/docker/volumes" and .target == "/var/lib/docker/volumes") | not
            ) | "bind:" + .source
          else empty end)
      ] | unique;
    ($legacy | storage_sources) as $old |
    ($app | storage_sources) | map(select(. as $source | $old | index($source)))
  ')"
  if [[ "$(jq length <<< "$shared_storage")" != "0" ]]; then
    printf 'FAIL: %s reuses legacy storage %s\n' "$app" "$(jq -c . <<< "$shared_storage")"
    exit 1
  fi
  printf 'ok: %s has separate identity, storage, and scoped legacy pin\n' "$app"
done
yq -e '.services["big-bear-stalwart-mail-v1"].volumes | contains(["stalwart-mail-v1_config:/etc/stalwart", "stalwart-mail-v1_data:/var/lib/stalwart"])' "$REPO/apps/stalwart-mail-v1/docker-compose.yml" >/dev/null
yq -e '.services["big-bear-stalwart-mail-v1"].ports | contains(["443:443/tcp", "995:995/tcp"])' "$REPO/apps/stalwart-mail-v1/docker-compose.yml" >/dev/null

N8N_PUBLIC_URL=https://n8n.example.invalid
AGENT_SECRET=TEST_ONLY_NOT_A_DEPLOYMENT_SECRET
n8n="$(N8N_PUBLIC_URL="$N8N_PUBLIC_URL" docker compose -f "$REPO/apps/n8n-v3/docker-compose.yml" config --format json)"
jq -e '.services["app-v3"].environment | .N8N_EDITOR_BASE_URL == "https://n8n.example.invalid" and .N8N_WEBHOOK_URL == "https://n8n.example.invalid" and .N8N_SECURE_COOKIE == "true"' <<< "$n8n" >/dev/null
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '#!/bin/sh\nprintf "n8n-entrypoint-reached\\n"\n' > "$TMP/docker-entrypoint.sh"
chmod +x "$TMP/docker-entrypoint.sh"
guard="$(jq -r '.services["app-v3"].entrypoint[2] | gsub("\\$\\$"; "$")' <<< "$n8n" | sed "s|/docker-entrypoint.sh|$TMP/docker-entrypoint.sh|")"
if rejection="$(N8N_EDITOR_BASE_URL=http://n8n.example.invalid /bin/sh -ec "$guard" 2>&1)"; then exit 1; fi
[[ "$rejection" == "N8N_PUBLIC_URL must be an HTTPS URL" ]]
handoff="$(N8N_EDITOR_BASE_URL=https://n8n.example.invalid /bin/sh -ec "$guard")"
[[ "$handoff" == "n8n-entrypoint-reached" ]]
agent="$(AGENT_SECRET="$AGENT_SECRET" docker compose -f "$REPO/apps/portainer-agent-v3/docker-compose.yml" config --format json)"
jq -e '.services["app-v3"].environment.AGENT_SECRET == "TEST_ONLY_NOT_A_DEPLOYMENT_SECRET"' <<< "$agent" >/dev/null
if env -u N8N_PUBLIC_URL docker compose -f "$REPO/apps/n8n-v3/docker-compose.yml" config -q >/dev/null 2>&1; then exit 1; fi
if env -u AGENT_SECRET docker compose -f "$REPO/apps/portainer-agent-v3/docker-compose.yml" config -q >/dev/null 2>&1; then exit 1; fi
jq -e '.ui.scheme == "https" and .ui.path == "/admin" and .compatibility.casaos.port == "443"' "$REPO/apps/stalwart-mail-v1/app.json" >/dev/null
printf 'ok: approved URL, secret, and launcher requirements\n'
