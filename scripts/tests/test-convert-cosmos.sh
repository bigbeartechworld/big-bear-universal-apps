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
assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then echo "FAIL: $label — missing '$needle'"; fail=1; else echo "ok: $label"; fi
}
section() { echo; echo "== $1 =="; }

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
  "compatibility": { "cosmos": { "supported": true, "port": "8080" } }
}
JSON
}

cosmos_out() {
  local root="$1" name="$2"
  echo "$root/out/cosmos/$name"
}

# Cosmos CreateService unmarshals entrypoint/command as Go strings, then
# strings.Fields the value. Marketplace installs from docker-compose.yml
# (index.js compose URL), so both YAML and cosmos-compose.json must match.

section "simple exec-form entrypoint becomes a Fields-round-trippable string"
TMP="$(mktemp -d)"
make_app "$TMP" "simpleep" 'services:
  app:
    image: nginx:alpine
    container_name: simpleep
    entrypoint: ["node", "dist/index.js"]
    command: ["gateway", "--bind", "lan"]
    ports:
      - "8080:8080"
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p cosmos -o "$TMP/out" >/dev/null 2>&1
OUT="$(cosmos_out "$TMP" "simpleep")"
EP_TYPE="$(yq eval '.services.app.entrypoint | type' "$OUT/docker-compose.yml")"
CMD_TYPE="$(yq eval '.services.app.command | type' "$OUT/docker-compose.yml")"
EP_VAL="$(yq eval '.services.app.entrypoint' "$OUT/docker-compose.yml")"
CMD_VAL="$(yq eval '.services.app.command' "$OUT/docker-compose.yml")"
JSON_EP_TYPE="$(jq -r '.["cosmos-installer"].services.simpleep.entrypoint | type' "$OUT/cosmos-compose.json")"
JSON_CMD_TYPE="$(jq -r '.["cosmos-installer"].services.simpleep.command | type' "$OUT/cosmos-compose.json")"
assert_eq "$EP_TYPE" "!!str" "yml entrypoint is string"
assert_eq "$CMD_TYPE" "!!str" "yml command is string"
assert_eq "$EP_VAL" "node dist/index.js" "yml entrypoint joined"
assert_eq "$CMD_VAL" "gateway --bind lan" "yml command joined"
assert_eq "$JSON_EP_TYPE" "string" "json entrypoint is string"
assert_eq "$JSON_CMD_TYPE" "string" "json command is string"
# strings.Fields round-trip
assert_eq "$(printf '%s' "$EP_VAL" | awk '{print NF}')" "2" "entrypoint Fields token count"
rm -rf "$TMP"

section "multiline sh -c seed cannot live in entrypoint; seed moves to post_install"
TMP="$(mktemp -d)"
make_app "$TMP" "seedy" 'services:
  app:
    image: nginx:alpine
    container_name: seedy
    entrypoint:
      - /bin/sh
      - -c
      - |
        set -eu
        if [ ! -s /app/config/app.yml ]; then
          mkdir -p /app/config
          cat > /app/config/app.yml <<EOF
        pages:
          - name: Home
        EOF
        fi
        exec /app/app --config /app/config/app.yml
    ports:
      - "8080:8080"
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p cosmos -o "$TMP/out" >/dev/null 2>&1
OUT="$(cosmos_out "$TMP" "seedy")"
EP_TYPE="$(yq eval '.services.app.entrypoint | type' "$OUT/docker-compose.yml")"
EP_VAL="$(yq eval '.services.app.entrypoint' "$OUT/docker-compose.yml")"
PI="$(yq eval '.services.app.post_install[0] // ""' "$OUT/docker-compose.yml")"
JSON_EP_TYPE="$(jq -r '.["cosmos-installer"].services.seedy.entrypoint | type' "$OUT/cosmos-compose.json")"
assert_eq "$EP_TYPE" "!!str" "seed yml entrypoint is string"
assert_eq "$JSON_EP_TYPE" "string" "seed json entrypoint is string"
assert_contains "$EP_VAL" "/bin/sh -c" "entrypoint still invokes sh -c"
assert_contains "$EP_VAL" "until(cat</tmp/cosmos-ready)" "entrypoint waits for seed sentinel"
if [[ "$EP_VAL" == *"name: Home"* ]]; then echo "FAIL: seed yaml leaked into entrypoint"; fail=1; else echo "ok: seed yaml not in entrypoint"; fi
assert_contains "$PI" "name: Home" "post_install writes starter yaml"
assert_contains "$PI" "touch /tmp/cosmos-ready" "post_install writes sentinel"
if [[ "$PI" == *"exec /app/app"* ]]; then echo "FAIL: post_install still execs app (deadlocks docker exec)"; fail=1; else echo "ok: post_install does not exec app"; fi
assert_contains "$EP_VAL" "exec,/app/app,--config,/app/config/app.yml" "wait-loop execs original binary"
rm -rf "$TMP"

section "glance (issue 2532): cosmos artifacts must not emit entrypoint arrays"
TMP="$(mktemp -d)"
bash "$REPO/scripts/convert-to-platforms.sh" -p cosmos -a glance -o "$TMP" >/dev/null 2>&1
G="$TMP/cosmos/glance"
EP_TYPE="$(yq eval '.services.app.entrypoint | type' "$G/docker-compose.yml")"
JSON_EP_TYPE="$(jq -r '.["cosmos-installer"].services.glance.entrypoint | type' "$G/cosmos-compose.json")"
EP_VAL="$(yq eval '.services.app.entrypoint' "$G/docker-compose.yml")"
PI="$(yq eval '.services.app.post_install[0] // ""' "$G/docker-compose.yml")"
assert_eq "$([[ -f "$G/cosmos-compose.json" ]] && echo yes)" "yes" "glance cosmos-compose.json produced"
assert_eq "$EP_TYPE" "!!str" "glance yml entrypoint is string (DS003)"
assert_eq "$JSON_EP_TYPE" "string" "glance json entrypoint is string (DS003)"
assert_contains "$PI" "type: calendar" "glance post_install seeds starter dashboard"
assert_contains "$PI" "touch /tmp/cosmos-ready" "glance post_install writes sentinel"
if [[ "$EP_VAL" == *"type: calendar"* ]]; then echo "FAIL: glance yaml leaked into cosmos entrypoint"; fail=1; else echo "ok: glance yaml not in cosmos entrypoint"; fi
rm -rf "$TMP"

section "casaos glance keeps exec-form entrypoint (real compose)"
TMP="$(mktemp -d)"
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a glance -o "$TMP" >/dev/null 2>&1
CASA_EP_TYPE="$(yq eval '.services.app.entrypoint | type' "$TMP/casaos/glance/docker-compose.yml")"
assert_eq "$CASA_EP_TYPE" "!!seq" "casaos glance entrypoint stays a sequence"
rm -rf "$TMP"

if [[ "$fail" -ne 0 ]]; then echo; echo "FAILED"; exit 1; fi
echo; echo "All cosmos converter tests passed"
exit 0
