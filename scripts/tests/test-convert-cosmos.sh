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

section "multiline sh -c seed cannot live in entrypoint; original script persists on the volume"
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
    volumes:
      - seedy_config:/app/config
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
assert_contains "$EP_VAL" "until(cat</app/config/.cosmos-run)" "wait-loop keys off volume path not /tmp"
if [[ "$EP_VAL" == *"/tmp/"* ]]; then echo "FAIL: wait-loop uses ephemeral /tmp"; fail=1; else echo "ok: wait-loop not on /tmp"; fi
if [[ "$EP_VAL" == *"name: Home"* ]]; then echo "FAIL: seed yaml leaked into entrypoint"; fail=1; else echo "ok: seed yaml not in entrypoint"; fi
assert_contains "$PI" "/app/config/.cosmos-run" "post_install writes run script onto the volume"
assert_contains "$PI" "name: Home" "run script still contains starter yaml"
assert_contains "$PI" "exec /app/app --config /app/config/app.yml" "run script keeps original exec"
assert_eq "$(printf '%s' "$EP_VAL" | awk '{print NF}')" "6" "wait-loop Fields token count"
assert_eq "$(printf '%s' "$EP_VAL" | awk '{print $5}')" "sleep,1" "Fields \$1 is sleep,1"
assert_eq "$(printf '%s' "$EP_VAL" | awk '{print $6}')" "exec,/app/config/.cosmos-run" "Fields \$2 execs the run script"
rm -rf "$TMP"

section "no-volume sh -c must not wait on /tmp"
TMP="$(mktemp -d)"
make_app "$TMP" "novol" 'services:
  app:
    image: nginx:alpine
    container_name: novol
    entrypoint:
      - /bin/sh
      - -c
      - echo hello world; exec nginx
    ports:
      - "8080:8080"
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p cosmos -o "$TMP/out" >/dev/null 2>&1
OUT="$(cosmos_out "$TMP" "novol")"
EP_VAL="$(yq eval '.services.app.entrypoint' "$OUT/docker-compose.yml")"
PI="$(yq eval '.services.app.post_install[0] // ""' "$OUT/docker-compose.yml")"
VOLS="$(yq eval '.services.app.volumes[]' "$OUT/docker-compose.yml")"
assert_contains "$EP_VAL" "until(cat</var/lib/cosmos-run/.cosmos-run)" "no-volume injects persist dir"
if [[ "$EP_VAL" == *"/tmp/"* ]]; then echo "FAIL: no-volume wait-loop uses /tmp"; fail=1; else echo "ok: no-volume wait-loop not on /tmp"; fi
assert_contains "$PI" "/var/lib/cosmos-run/.cosmos-run" "no-volume post_install writes injected persist"
assert_contains "$VOLS" "cosmos-run-novol-app:/var/lib/cosmos-run" "no-volume persist volume is app+service scoped"
rm -rf "$TMP"

section "two no-volume sh -c services must not share a persist volume"
TMP="$(mktemp -d)"
make_app "$TMP" "twins" 'services:
  app:
    image: nginx:alpine
    container_name: twins-app
    entrypoint:
      - /bin/sh
      - -c
      - echo from app; exec nginx
    ports:
      - "8080:8080"
  worker:
    image: nginx:alpine
    container_name: twins-worker
    command:
      - /bin/sh
      - -c
      - echo from worker; exec nginx
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p cosmos -o "$TMP/out" >/dev/null 2>&1
OUT="$(cosmos_out "$TMP" "twins")"
APP_VOLS="$(yq eval '.services.app.volumes[]' "$OUT/docker-compose.yml")"
WORKER_VOLS="$(yq eval '.services.worker.volumes[]' "$OUT/docker-compose.yml")"
APP_PI="$(yq eval '.services.app.post_install[0] // ""' "$OUT/docker-compose.yml")"
WORKER_PI="$(yq eval '.services.worker.post_install[0] // ""' "$OUT/docker-compose.yml")"
assert_contains "$APP_VOLS" "cosmos-run-twins-app:/var/lib/cosmos-run" "app persist volume is app+service scoped"
assert_contains "$WORKER_VOLS" "cosmos-run-twins-worker:/var/lib/cosmos-run" "worker persist volume is app+service scoped"
if [[ "$APP_VOLS" == *cosmos-run-twins-worker* ]]; then echo "FAIL: app mounted worker persist volume"; fail=1; else echo "ok: app did not mount worker persist volume"; fi
if [[ "$WORKER_VOLS" == *cosmos-run-twins-app* ]]; then echo "FAIL: worker mounted app persist volume"; fail=1; else echo "ok: worker did not mount app persist volume"; fi
assert_contains "$APP_PI" "echo from app" "app post_install keeps app script"
assert_contains "$WORKER_PI" "echo from worker" "worker post_install keeps worker script"
if [[ "$APP_PI" == *"echo from worker"* ]]; then echo "FAIL: app post_install contains worker script"; fail=1; else echo "ok: app post_install is not worker script"; fi
if [[ "$WORKER_PI" == *"echo from app"* ]]; then echo "FAIL: worker post_install contains app script"; fail=1; else echo "ok: worker post_install is not app script"; fi
rm -rf "$TMP"

section "two apps with service named app must not share a host volume"
TMP="$(mktemp -d)"
make_app "$TMP" "alpha" 'services:
  app:
    image: nginx:alpine
    container_name: alpha
    entrypoint:
      - /bin/sh
      - -c
      - echo from alpha; exec nginx
    ports:
      - "8080:8080"
'
make_app "$TMP" "beta" 'services:
  app:
    image: nginx:alpine
    container_name: beta
    entrypoint:
      - /bin/sh
      - -c
      - echo from beta; exec nginx
    ports:
      - "8080:8080"
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p cosmos -a alpha -o "$TMP/out" >/dev/null 2>&1
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p cosmos -a beta -o "$TMP/out" >/dev/null 2>&1
ALPHA_VOLS="$(yq eval '.services.app.volumes[]' "$TMP/out/cosmos/alpha/docker-compose.yml")"
BETA_VOLS="$(yq eval '.services.app.volumes[]' "$TMP/out/cosmos/beta/docker-compose.yml")"
assert_contains "$ALPHA_VOLS" "cosmos-run-alpha-app:/var/lib/cosmos-run" "alpha persist volume includes app id"
assert_contains "$BETA_VOLS" "cosmos-run-beta-app:/var/lib/cosmos-run" "beta persist volume includes app id"
if [[ "$ALPHA_VOLS" == *cosmos-run-beta-app* ]]; then echo "FAIL: alpha mounted beta persist volume"; fail=1; else echo "ok: alpha volume is not beta's"; fi
if [[ "$BETA_VOLS" == *cosmos-run-alpha-app* ]]; then echo "FAIL: beta mounted alpha persist volume"; fail=1; else echo "ok: beta volume is not alpha's"; fi
rm -rf "$TMP"

section "Compose dollar-dollar unescapes in persisted script"
TMP="$(mktemp -d)"
make_app "$TMP" "dollars" 'services:
  app:
    image: nginx:alpine
    container_name: dollars
    entrypoint:
      - /bin/sh
      - -c
      - |
        secret="$${SEARXNG_SECRET:-}"
        exec nginx
    ports:
      - "8080:8080"
    volumes:
      - dollars_data:/data
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p cosmos -o "$TMP/out" >/dev/null 2>&1
OUT="$(cosmos_out "$TMP" "dollars")"
PI="$(yq eval '.services.app.post_install[0] // ""' "$OUT/docker-compose.yml")"
assert_contains "$PI" '${SEARXNG_SECRET:-}' "Compose \$\$ becomes shell \$"
if [[ "$PI" == *'$${SEARXNG_SECRET'* ]]; then echo "FAIL: persisted script still has Compose \$\$"; fail=1; else echo "ok: no leftover Compose \$\$"; fi
rm -rf "$TMP"

section "command-form sh -c with whitespace uses the same volume run script"
TMP="$(mktemp -d)"
make_app "$TMP" "cmdsh" 'services:
  app:
    image: nginx:alpine
    container_name: cmdsh
    entrypoint: /bin/sh
    command:
      - -c
      - echo hello && exec nginx
    ports:
      - "8080:8080"
    volumes:
      - cmdsh_data:/data
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p cosmos -o "$TMP/out" >/dev/null 2>&1
OUT="$(cosmos_out "$TMP" "cmdsh")"
EP_VAL="$(yq eval '.services.app.entrypoint' "$OUT/docker-compose.yml")"
CMD_TYPE="$(yq eval '.services.app.command | type' "$OUT/docker-compose.yml")"
PI="$(yq eval '.services.app.post_install[0] // ""' "$OUT/docker-compose.yml")"
assert_contains "$EP_VAL" "until(cat</data/.cosmos-run)" "command sh -c waits on volume run script"
assert_contains "$PI" "echo hello && exec nginx" "original command script persisted"
if [[ "$CMD_TYPE" == "!!seq" ]]; then echo "FAIL: command still a sequence"; fail=1; else echo "ok: command no longer a sequence"; fi
rm -rf "$TMP"

section "sh -c without exec still persists the script (no naive join)"
TMP="$(mktemp -d)"
make_app "$TMP" "noexec" 'services:
  app:
    image: nginx:alpine
    container_name: noexec
    entrypoint:
      - /bin/sh
      - -c
      - echo hello world
    ports:
      - "8080:8080"
    volumes:
      - noexec_data:/data
'
bash "$REPO/scripts/convert-to-platforms.sh" -i "$TMP/apps" -p cosmos -o "$TMP/out" >/dev/null 2>&1
OUT="$(cosmos_out "$TMP" "noexec")"
EP_VAL="$(yq eval '.services.app.entrypoint' "$OUT/docker-compose.yml")"
PI="$(yq eval '.services.app.post_install[0] // ""' "$OUT/docker-compose.yml")"
assert_contains "$EP_VAL" "until(cat</data/.cosmos-run)" "no-exec sh -c still waits on run script"
assert_contains "$PI" "echo hello world" "no-exec script persisted"
if [[ "$EP_VAL" == *"echo hello world"* ]]; then echo "FAIL: no-exec script leaked into entrypoint string"; fail=1; else echo "ok: no-exec script not joined into entrypoint"; fi
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
assert_contains "$PI" "/app/config/.cosmos-run" "glance run script lives on the config volume"
assert_contains "$EP_VAL" "until(cat</app/config/.cosmos-run)" "glance waits on volume run script"
if [[ "$EP_VAL" == *"type: calendar"* ]]; then echo "FAIL: glance yaml leaked into cosmos entrypoint"; fail=1; else echo "ok: glance yaml not in cosmos entrypoint"; fi
if [[ "$EP_VAL" == *"/tmp/"* ]]; then echo "FAIL: glance wait-loop uses /tmp"; fail=1; else echo "ok: glance wait-loop not on /tmp"; fi
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
