#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
set +e

fail=0
assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then echo "FAIL: $label — got '$actual' want '$expected'"; fail=1; else echo "ok: $label"; fi
}
section() { echo; echo "== $1 =="; }

main_networks() {
  local file="$1"
  export UMB_SVC="$2"
  yq eval '.services[strenv(UMB_SVC)].networks // [] | join(",")' "$file"
}

make_app() {
  local root="$1" name="$2" compose="$3"
  mkdir -p "$root/apps/$name"
  printf '%s' "$compose" > "$root/apps/$name/docker-compose.yml"
  cat > "$root/apps/$name/app.json" <<JSON
{
  "spec_version": "1.0",
  "metadata": {
    "id": "$name",
    "name": "$name",
    "description": "test app",
    "tagline": "test",
    "version": "1.0.0",
    "author": "test",
    "developer": "test",
    "category": "BigBearCasaOS"
  },
  "technical": { "main_service": "app", "default_port": "8080", "main_image": "nginx", "compose_file": "docker-compose.yml" },
  "deployment": { "ports": [{ "container": "8080", "host": "8080", "protocol": "tcp" }] },
  "compatibility": { "umbrel": { "supported": true, "port": "10001", "app_port": "8080" } }
}
JSON
}

section "app_proxy reachability: main service must be on Umbrel's default network"
# Umbrel's app_proxy only ever attaches to umbrel_main_network (its compose `default`).
# A main service pinned to custom networks alone never registers its container name
# there, so APP_HOST resolution fails while the app itself is healthy (issue #2301).
TMP="$(mktemp -d)"

make_app "$TMP" "customnet" 'services:
  app:
    image: nginx:alpine
    networks:
      - custom_network
  sidecar:
    image: redis:alpine
    networks:
      - custom_network
networks:
  custom_network:
    driver: bridge
'

make_app "$TMP" "defaultnet" 'services:
  app:
    image: nginx:alpine
'

make_app "$TMP" "hasdefault" 'services:
  app:
    image: nginx:alpine
    networks:
      - custom_network
      - default
networks:
  custom_network:
    driver: bridge
'

bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p umbrel -o "$TMP/out" > "$TMP/run.log" 2>&1
assert_eq "$?" "0" "converter exits 0"

CUSTOM="$TMP/out/umbrel/big-bear-umbrel-customnet/docker-compose.yml"
assert_eq "$(main_networks "$CUSTOM" app)" "custom_network,default" "custom-network-only main service gains default"
assert_eq "$(main_networks "$CUSTOM" sidecar)" "custom_network" "sibling services are left alone"

assert_eq "$(main_networks "$TMP/out/umbrel/big-bear-umbrel-defaultnet/docker-compose.yml" app)" "" "main service with no networks key is untouched"
assert_eq "$(main_networks "$TMP/out/umbrel/big-bear-umbrel-hasdefault/docker-compose.yml" app)" "custom_network,default" "existing default is not duplicated"

section "map-style networks: attached without corrupting the compose file"
make_app "$TMP" "mapnet" 'services:
  app:
    image: nginx:alpine
    networks:
      custom_network:
        aliases:
          - internal
networks:
  custom_network:
    driver: bridge
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -a mapnet -p umbrel -o "$TMP/out" > "$TMP/map.log" 2>&1
MAPNET="$TMP/out/umbrel/big-bear-umbrel-mapnet/docker-compose.yml"
assert_eq "$(yq eval '.services.app.networks | has("default")' "$MAPNET" 2>/dev/null)" "true" "map-style networks gains default"
assert_eq "$(yq eval '.services.app.networks.custom_network.aliases | join(",")' "$MAPNET" 2>/dev/null)" "internal" "map-style networks keeps existing entries"

cp "$MAPNET" "$TMP/mapnet-first.yml"
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -a mapnet -p umbrel -o "$TMP/out" > /dev/null 2>&1
assert_eq "$?" "0" "map-style rerun exits 0"
diff -q "$TMP/mapnet-first.yml" "$MAPNET" > /dev/null 2>&1
assert_eq "$?" "0" "map-style rerun is byte-identical"

make_app "$TMP" "mapdefault" 'services:
  app:
    image: nginx:alpine
    networks:
      custom_network:
        aliases:
          - internal
      default:
        aliases:
          - myapp
networks:
  custom_network:
    driver: bridge
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -a mapdefault -p umbrel -o "$TMP/out" > /dev/null 2>&1
MAPDEF="$TMP/out/umbrel/big-bear-umbrel-mapdefault/docker-compose.yml"
assert_eq "$(yq eval '.services.app.networks.default.aliases | join(",")' "$MAPDEF" 2>/dev/null)" "myapp" "map-style existing default keeps its config"

section "idempotency: re-running the converter does not append default twice"
cp "$CUSTOM" "$TMP/first-run.yml"
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p umbrel -o "$TMP/out" > /dev/null 2>&1
assert_eq "$?" "0" "second run exits 0"
assert_eq "$(main_networks "$CUSTOM" app)" "custom_network,default" "second run keeps a single default"
diff -q "$TMP/first-run.yml" "$CUSTOM" > /dev/null 2>&1
assert_eq "$?" "0" "second run output is byte-identical"

section "host networking: no app_proxy, no network rewrite"
make_app "$TMP" "hostnet" 'services:
  app:
    image: nginx:alpine
    network_mode: host
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p umbrel -o "$TMP/out" > /dev/null 2>&1
HOSTNET="$TMP/out/umbrel/big-bear-umbrel-hostnet/docker-compose.yml"
assert_eq "$(yq eval '.services.app_proxy // "ABSENT"' "$HOSTNET")" "ABSENT" "host-network app gets no app_proxy"
assert_eq "$(yq eval '.services.app.network_mode' "$HOSTNET")" "host" "host-network app keeps network_mode: host"
assert_eq "$(main_networks "$HOSTNET" app)" "" "host-network app gains no networks"

rm -rf "$TMP"

section "catalog: every app_proxy target resolves on the default network"
if [[ "${UMBREL_FULL_RUN:-0}" == "1" ]]; then
  TMP_FULL="$(mktemp -d)"
  bash "$REPO/scripts/convert-to-platforms.sh" -p umbrel -o "$TMP_FULL/out" > "$TMP_FULL/run.log" 2>&1
  UNREACHABLE=0
  for F in "$TMP_FULL"/out/umbrel/*/docker-compose.yml; do
    HOST="$(yq eval '.services.app_proxy.environment.APP_HOST // ""' "$F")"
    [[ -z "$HOST" ]] && continue
    for SVC in $(yq eval '.services | keys | .[]' "$F"); do
      [[ "$SVC" == "app_proxy" ]] && continue
      case "$HOST" in *"_${SVC}_1")
        NETS="$(main_networks "$F" "$SVC")"
        if [[ -n "$NETS" ]] && [[ ",$NETS," != *",default,"* ]]; then
          UNREACHABLE=$((UNREACHABLE+1)); echo "UNREACHABLE: $(basename "$(dirname "$F")") [$SVC] -> $NETS"
        fi
      ;; esac
    done
  done
  assert_eq "$UNREACHABLE" "0" "no app_proxy target is stranded off the default network"
  rm -rf "$TMP_FULL"
else
  echo "ok: catalog case skipped (set UMBREL_FULL_RUN=1 to enable)"
fi

exit $fail
