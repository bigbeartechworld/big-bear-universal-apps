#!/bin/bash
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

assert_eq() {
  if [[ "$1" != "$2" ]]; then
    echo "FAIL: $3, got '$1' want '$2'"
    fail=1
    return
  fi
  echo "ok: $3"
}

convert() {
  local app="$1"
  mkdir -p "$TMP/apps"
  if [[ ! -d "$TMP/apps/$app" ]]; then
    cp -R "$REPO/apps/$app" "$TMP/apps/$app"
    jq '.visual.icon = ""' "$TMP/apps/$app/app.json" > "$TMP/metadata.json"
    mv "$TMP/metadata.json" "$TMP/apps/$app/app.json"
  fi
  bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -a "$app" -i "$TMP/apps" -o "$TMP/out" > "$TMP/$app.log" 2>&1
  local result=$?
  assert_eq "$result" "0" "$app conversion exits cleanly"
  if [[ "$result" != "0" ]]; then
    cat "$TMP/$app.log"
    return 1
  fi
  OUT="$TMP/out/runtipi/$app/docker-compose.yml"
  assert_eq "$([[ -f "$TMP/out/runtipi/$app/docker-compose.json" ]] && echo yes || echo no)" "no" "$app has no legacy JSON"
  assert_eq "$(yq '."x-runtipi".schema_version' "$OUT")" "2" "$app native schema version"
  assert_eq "$(yq '[.services[] | select(."x-runtipi".is_main == true)] | length' "$OUT")" "1" "$app has one main service"
  assert_eq "$(jq -r '.min_tipi_version' "$TMP/out/runtipi/$app/config.json")" "4.7.0" "$app minimum version supports YAML"
}

for app in uptime-kuma authentik bookstack immich-aio-alpine libretranslate odoo domainlocker invoice-ninja adguard-home; do
  convert "$app" || continue
  main=$(jq -r '.technical.main_service' "$REPO/apps/$app/app.json")
  expected=$(main="$main" yq '.services[strenv(main)].image' "$REPO/apps/$app/docker-compose.yml")
  assert_eq "$(main="$app" yq '.services[strenv(main)].image' "$OUT")" "$expected" "$app main image and digest preserved"
  assert_eq "$(yq '.services | length' "$OUT")" "$(yq '.services | length' "$REPO/apps/$app/docker-compose.yml")" "$app sidecar count preserved"
  main="$main" app="$app" yq -o=json '.' "$REPO/apps/$app/docker-compose.yml" |
    jq -e --arg main "$main" --arg app "$app" --slurpfile generated <(yq -o=json '.' "$OUT") '
      ["container_name", "volumes", "ports", "depends_on", "environment", "command", "links", "x-runtipi"] as $transformed |
      all(.services | to_entries[]; . as $source |
        (if $source.key == $main then $app else $source.key end) as $name |
        all($source.value | keys[]; . as $key |
          ($transformed | index($key)) != null or $source.value[$key] == $generated[0].services[$name][$key]))
    ' > /dev/null
  assert_eq "$?" "0" "$app preserves all service keys outside explicit platform transformations"
done

OUT="$TMP/out/runtipi/adguard-home/docker-compose.yml"
assert_eq "$(yq '.services."adguard-home"."x-runtipi".internal_port' "$OUT")" "80" "AdGuard routing uses the web container port"
assert_eq "$(yq -o=json -I=0 '.services."adguard-home".ports' "$OUT")" '["53:53/tcp","53:53/udp"]' "AdGuard retains both DNS mappings and removes the web mapping"

OUT="$TMP/out/runtipi/libretranslate/docker-compose.yml"
assert_eq "$(yq '.services.libretranslate.user' "$OUT")" "root" "LibreTranslate user reaches installer"
assert_eq "$(yq '.services.libretranslate.environment | length' "$OUT")" "4" "LibreTranslate environment reaches installer"
assert_eq "$(yq '.services.libretranslate.volumes | length' "$OUT")" "2" "LibreTranslate volumes reach installer"
assert_eq "$(yq '.services.libretranslate.tty' "$OUT")" "true" "LibreTranslate tty preserved"
assert_eq "$(yq '.services.libretranslate.healthcheck.test[0]' "$OUT")" "CMD-SHELL" "LibreTranslate health check preserved"

OUT="$TMP/out/runtipi/domainlocker/docker-compose.yml"
assert_eq "$(yq '.services.domainlocker."x-runtipi".internal_port' "$OUT")" "3000" "routing uses container port"
assert_eq "$(yq '.services.postgres.ports // "none"' "$OUT")" "none" "sidecar ports remain absent"
assert_eq "$(yq '.services.updater.depends_on.domainlocker.condition' "$OUT")" "service_healthy" "renamed health dependency preserved"
assert_eq "$(yq '.services.updater.depends_on | has("app")' "$OUT")" "false" "old main dependency removed"
assert_eq "$(yq '.services.updater.command[-1]' "$OUT" | grep -c 'http://domainlocker:3000' || true)" "4" "updater command follows renamed main"

OUT="$TMP/out/runtipi/invoice-ninja/docker-compose.yml"
assert_eq "$(grep -c 'APP_URL=http://invoice-ninja$' "$OUT" || true)" "1" "portless URL follows renamed main"
assert_eq "$(grep -c 'APP_URL=http://big-bear-invoice-ninja-web' "$OUT" || true)" "0" "old URL removed"

jq '.technical.main_image = "example/absent-from-compose"' "$TMP/apps/bookstack/app.json" > "$TMP/metadata.json"
mv "$TMP/metadata.json" "$TMP/apps/bookstack/app.json"
convert bookstack
assert_eq "$(yq '.services.bookstack.image' "$OUT")" "$(yq '.services."big-bear-bookstack".image' "$REPO/apps/bookstack/docker-compose.yml")" "mismatched metadata does not fabricate an image"

yq -i '.services."big-bear-authentik-worker".image = "ghcr.io/goauthentik/server:2026.2.2@sha256:dddd"' "$TMP/apps/authentik/docker-compose.yml"
convert authentik
assert_eq "$(yq '.services."big-bear-authentik-worker".image' "$OUT")" "ghcr.io/goauthentik/server:2026.2.2@sha256:dddd" "differing worker digest stays distinct"
assert_eq "$(yq '.services.authentik.image' "$OUT")" "$(yq '.services."big-bear-authentik".image' "$REPO/apps/authentik/docker-compose.yml")" "differing worker digest does not change main image"

for app in libredesk jellyseerr pocketid openvpn-as lancache claude-code odysseus; do
  convert "$app" || continue
  yq -o=json '.' "$OUT" | jq -e --slurpfile metadata "$REPO/apps/$app/app.json" '
    ($metadata[0].compatibility.runtipi.published_services // []) as $allowed |
    all(.services | to_entries[];
      . as $service |
      $service.value.network_mode != "bridge" and
      ($service.value["x-runtipi"].is_main == true or
       ($allowed | index($service.key)) != null or
       ($service.value.ports // [] | length) == 0))
  ' > /dev/null
  assert_eq "$?" "0" "$app only publishes audited sidecars and normalizes bridge networking"
  for service in $(jq -r '.compatibility.runtipi.published_services[]?' "$REPO/apps/$app/app.json"); do
    assert_eq "$(service="$service" yq -o=json -I=0 '.services[strenv(service)].ports' "$OUT")" "$(service="$service" yq -o=json -I=0 '.services[strenv(service)].ports' "$REPO/apps/$app/docker-compose.yml")" "$app/$service retains required ports and host binding"
  done
done

for app in reactive-resume stoat coolify; do
  mkdir -p "$TMP/out/runtipi/$app"
  printf '{}' > "$TMP/out/runtipi/$app/docker-compose.yml"
  bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -a "$app" -o "$TMP/out" > "$TMP/$app.log" 2>&1
  assert_eq "$?" "0" "$app unsupported conversion exits cleanly"
  assert_eq "$([[ -d "$TMP/out/runtipi/$app" ]] && echo yes || echo no)" "no" "$app unsafe or incomplete Runtipi template is unavailable"
done

jq 'del(.technical.main_service)' "$TMP/apps/uptime-kuma/app.json" > "$TMP/metadata.json"
mv "$TMP/metadata.json" "$TMP/apps/uptime-kuma/app.json"
convert uptime-kuma
assert_eq "$(yq '.services."uptime-kuma".image' "$OUT")" "$(yq '.services | to_entries | .[0].value.image' "$REPO/apps/uptime-kuma/docker-compose.yml")" "absent main_service uses first service"

bash "$REPO/scripts/tests/test-runtipi-compose-fidelity.sh"
assert_eq "$?" "0" "native Compose fidelity regression"
exit "$fail"
