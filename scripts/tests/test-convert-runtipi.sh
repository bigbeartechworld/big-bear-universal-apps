#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$REPO/scripts/convert-to-platforms.sh" --source-only 2>/dev/null || true

fail=0
assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then echo "FAIL: $label — got '$actual' want '$expected'"; fail=1; else echo "ok: $label"; fi
}
section() { echo; echo "== $1 =="; }

section "unit: resolver over synthetic compose fixtures"
UNIT_DIR="$(mktemp -d)"

cat > "$UNIT_DIR/single.yml" <<'YAML'
services:
  app:
    image: louislam/uptime-kuma:2@sha256:aaaa
  db:
    image: postgres:14-alpine@sha256:bbbb
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/single.yml" "louislam/uptime-kuma" testapp "louislam/uptime-kuma:1.0")" \
  "louislam/uptime-kuma:2@sha256:aaaa" "single match verbatim"

cat > "$UNIT_DIR/multisame.yml" <<'YAML'
services:
  app:
    image: ghcr.io/goauthentik/server:2026.2.2@sha256:cccc
  worker:
    image: ghcr.io/goauthentik/server:2026.2.2@sha256:cccc
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/multisame.yml" "ghcr.io/goauthentik/server" testapp "ghcr.io/goauthentik/server:9.9")" \
  "ghcr.io/goauthentik/server:2026.2.2@sha256:cccc" "multi identical verbatim"

cat > "$UNIT_DIR/multidiff.yml" <<'YAML'
services:
  app:
    image: ghcr.io/goauthentik/server:2026.2.2@sha256:cccc
  worker:
    image: ghcr.io/goauthentik/server:2026.2.2@sha256:dddd
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/multidiff.yml" "ghcr.io/goauthentik/server" testapp "ghcr.io/goauthentik/server:9.9" 2>/dev/null)" \
  "ghcr.io/goauthentik/server:9.9" "multi differing falls back"

cat > "$UNIT_DIR/nomatch.yml" <<'YAML'
services:
  app:
    image: linuxserver/bookstack:1@sha256:eeee
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/nomatch.yml" "lscr.io/linuxserver/bookstack" bookstack "lscr.io/linuxserver/bookstack:26.05" 2>/dev/null)" \
  "lscr.io/linuxserver/bookstack:26.05" "no match falls back"

cat > "$UNIT_DIR/registryport.yml" <<'YAML'
services:
  app:
    image: registry:5000/foo@sha256:ffff
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/registryport.yml" "registry:5000/foo" testapp "registry:5000/foo:1.0")" \
  "registry:5000/foo@sha256:ffff" "registry port not mangled"

cat > "$UNIT_DIR/digestnotag.yml" <<'YAML'
services:
  app:
    image: alpine/socat@sha256:gggg
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/digestnotag.yml" "alpine/socat" testapp "alpine/socat:1.0")" \
  "alpine/socat@sha256:gggg" "digest without tag normalizes to bare repo"

cat > "$UNIT_DIR/buildonly.yml" <<'YAML'
services:
  builder:
    build: .
  app:
    image: louislam/uptime-kuma:2@sha256:aaaa
YAML
assert_eq "$(resolve_runtipi_main_image "$UNIT_DIR/buildonly.yml" "louislam/uptime-kuma" testapp "louislam/uptime-kuma:1.0")" \
  "louislam/uptime-kuma:2@sha256:aaaa" "build-only service skipped"

cat > "$UNIT_DIR/unpinned.yml" <<'YAML'
services:
  app:
    image: ghcr.io/imagegenius/immich:2.0.0-alpine
YAML
UNPINNED_OUT="$(resolve_runtipi_main_image "$UNIT_DIR/unpinned.yml" "ghcr.io/imagegenius/immich" immich-aio-alpine "ghcr.io/imagegenius/immich:2.0.0")"
assert_eq "$UNPINNED_OUT" "ghcr.io/imagegenius/immich:2.0.0-alpine" "unpinned match verbatim"

WARN_ON_MATCH="$(resolve_runtipi_main_image "$UNIT_DIR/unpinned.yml" "ghcr.io/imagegenius/immich" immich-aio-alpine "x:1" 2>&1 | grep -c 'WARNING' || true)"
assert_eq "$WARN_ON_MATCH" "0" "no warning on successful match"

WARN_ON_FALLBACK="$(resolve_runtipi_main_image "$UNIT_DIR/nomatch.yml" "lscr.io/linuxserver/bookstack" bookstack "lscr.io/linuxserver/bookstack:26.05" 2>&1 | grep -c 'WARNING' || true)"
assert_eq "$WARN_ON_FALLBACK" "1" "one warning on fallback"

STDOUT_CLEAN="$(resolve_runtipi_main_image "$UNIT_DIR/nomatch.yml" "lscr.io/linuxserver/bookstack" bookstack "lscr.io/linuxserver/bookstack:26.05" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "$STDOUT_CLEAN" "1" "fallback stdout is exactly one line"

VERBOSE_CLEAN="$(VERBOSE=true resolve_runtipi_main_image "$UNIT_DIR/single.yml" "louislam/uptime-kuma" testapp "louislam/uptime-kuma:1.0" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "$VERBOSE_CLEAN" "1" "VERBOSE stdout is exactly one line"

MISSING_FILE="$(resolve_runtipi_main_image "$UNIT_DIR/does-not-exist.yml" "foo/bar" testapp "foo/bar:1.0" 2>/dev/null)"
assert_eq "$MISSING_FILE" "foo/bar:1.0" "missing compose file falls back"

rm -rf "$UNIT_DIR"

section "e2e: happy path, digest preserved, JSON/YAML agreement, schema shape"
TMP_UK="$(mktemp -d)"
UK_LOG="$TMP_UK/run.log"
bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -a uptime-kuma -o "$TMP_UK/out" > "$UK_LOG" 2>&1
UK_EXIT=$?
assert_eq "$UK_EXIT" "0" "uptime-kuma run exits 0"
UK_JSON="$TMP_UK/out/runtipi/uptime-kuma/docker-compose.json"
UK_SRC_IMG="$(yq eval '.services | to_entries | .[] | select(.value.image | test("^louislam/uptime-kuma")) | .value.image' "$REPO/apps/uptime-kuma/docker-compose.yml" | head -1)"
UK_JSON_IMG="$(jq -r '.services[0].image' "$UK_JSON")"
assert_eq "$UK_JSON_IMG" "$UK_SRC_IMG" "uptime-kuma json image equals source compose image"
assert_eq "$(printf '%s' "$UK_JSON_IMG" | grep -c '@sha256:' || true)" "1" "uptime-kuma digest preserved"
UK_GEN_IMG="$(yq eval '.services."uptime-kuma".image' "$TMP_UK/out/runtipi/uptime-kuma/docker-compose.yml")"
assert_eq "$UK_JSON_IMG" "$UK_GEN_IMG" "json image agrees with generated yml (by service name)"
assert_eq "$(jq -r '.schemaVersion' "$UK_JSON")" "2" "schemaVersion is 2"
assert_eq "$(jq -r '.services | length' "$UK_JSON")" "1" "single service"
assert_eq "$(jq -r '.services[0].isMain' "$UK_JSON")" "true" "isMain true"
assert_eq "$(jq -r '.services[0].internalPort | type' "$UK_JSON")" "number" "internalPort is a number"
assert_eq "$(grep -c 'WARNING' "$UK_LOG" || true)" "0" "uptime-kuma emits no warning"
rm -rf "$TMP_UK"

section "e2e: multi-match identical strings, no warning"
TMP_AK="$(mktemp -d)"
AK_LOG="$TMP_AK/run.log"
bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -a authentik -o "$TMP_AK/out" > "$AK_LOG" 2>&1
AK_EXIT=$?
assert_eq "$AK_EXIT" "0" "authentik run exits 0"
AK_SRC_IMG="$(yq eval '.services."big-bear-authentik".image' "$REPO/apps/authentik/docker-compose.yml")"
AK_JSON_IMG="$(jq -r '.services[0].image' "$TMP_AK/out/runtipi/authentik/docker-compose.json")"
assert_eq "$AK_JSON_IMG" "$AK_SRC_IMG" "authentik resolves to matched image"
assert_eq "$(printf '%s' "$AK_JSON_IMG" | grep -c '@sha256:' || true)" "1" "authentik digest preserved"
assert_eq "$(grep -c 'WARNING' "$AK_LOG" || true)" "0" "authentik multi-match emits no warning"
rm -rf "$TMP_AK"

section "e2e: linuxserver app resolves against bare registry path"
TMP_BS="$(mktemp -d)"
BS_LOG="$TMP_BS/run.log"
bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -a bookstack -o "$TMP_BS/out" > "$BS_LOG" 2>&1
BS_EXIT=$?
assert_eq "$BS_EXIT" "0" "bookstack run exits 0"
BS_JSON="$TMP_BS/out/runtipi/bookstack/docker-compose.json"
assert_eq "$([[ -f "$BS_JSON" ]] && echo yes)" "yes" "bookstack docker-compose.json produced"
BS_SRC_IMG="$(yq eval '.services.big-bear-bookstack.image' "$REPO/apps/bookstack/docker-compose.yml")"
BS_JSON_IMG="$(jq -r '.services[0].image' "$BS_JSON")"
assert_eq "$BS_JSON_IMG" "$BS_SRC_IMG" "bookstack image matches source compose verbatim"
assert_eq "$(printf '%s' "$BS_JSON_IMG" | grep -c '@sha256:' || true)" "1" "bookstack image carries a digest"
assert_eq "$(grep -c 'WARNING' "$BS_LOG" || true)" "0" "bookstack emits no warning"
rm -rf "$TMP_BS"

section "e2e: no-match fallback (set -e regression guard)"
TMP_NM="$(mktemp -d)"
NM_LOG="$TMP_NM/run.log"
mkdir -p "$TMP_NM/apps"
cp -R "$REPO/apps/bookstack" "$TMP_NM/apps/nomatch-app"
jq --indent 2 '.technical.main_image = "example/absent-from-compose" | .metadata.id = "nomatch-app"' "$TMP_NM/apps/nomatch-app/app.json" > "$TMP_NM/app.tmp"
mv "$TMP_NM/app.tmp" "$TMP_NM/apps/nomatch-app/app.json"
NM_VER="$(jq -r '.metadata.version' "$TMP_NM/apps/nomatch-app/app.json")"
bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -i "$TMP_NM/apps" -a nomatch-app -o "$TMP_NM/out" > "$NM_LOG" 2>&1
NM_EXIT=$?
assert_eq "$NM_EXIT" "0" "no-match run exits 0 (set -e guard)"
NM_JSON="$TMP_NM/out/runtipi/nomatch-app/docker-compose.json"
assert_eq "$([[ -f "$NM_JSON" ]] && echo yes)" "yes" "no-match docker-compose.json produced"
NM_JSON_IMG="$(jq -r '.services[0].image' "$NM_JSON")"
assert_eq "$NM_JSON_IMG" "example/absent-from-compose:$NM_VER" "no-match falls back to main_image:version"
assert_eq "$(printf '%s' "$NM_JSON_IMG" | grep -c '@' || true)" "0" "no-match fallback carries no digest"
assert_eq "$(printf '%s' "$NM_JSON_IMG" | wc -l | tr -d ' ')" "0" "no-match fallback image is a single line"
assert_eq "$(grep -c 'WARNING' "$NM_LOG" || true)" "1" "no-match emits exactly one warning"
rm -rf "$TMP_NM"

section "e2e: legitimately unpinned upstream, no warning, no error"
TMP_IM="$(mktemp -d)"
IM_LOG="$TMP_IM/run.log"
bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -a immich-aio-alpine -o "$TMP_IM/out" > "$IM_LOG" 2>&1
IM_EXIT=$?
assert_eq "$IM_EXIT" "0" "immich-aio-alpine run exits 0"
assert_eq "$(jq -r '.services[0].image' "$TMP_IM/out/runtipi/immich-aio-alpine/docker-compose.json")" \
  "ghcr.io/imagegenius/immich:2.0.0-alpine" "immich-aio-alpine unpinned image copied verbatim"
assert_eq "$(grep -c 'WARNING' "$IM_LOG" || true)" "0" "immich-aio-alpine emits no warning"
rm -rf "$TMP_IM"

section "e2e: synthetic multi-match with differing strings falls back"
TMP_SYN="$(mktemp -d)"
cp -R "$REPO/apps/." "$TMP_SYN/apps/"
yq eval -i '.services."big-bear-authentik-worker".image = "ghcr.io/goauthentik/server:2026.2.2@sha256:0000000000000000000000000000000000000000000000000000000000000000"' \
  "$TMP_SYN/apps/authentik/docker-compose.yml"
SYN_LOG="$TMP_SYN/run.log"
bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -a authentik -i "$TMP_SYN/apps" -o "$TMP_SYN/out" > "$SYN_LOG" 2>&1
SYN_EXIT=$?
assert_eq "$SYN_EXIT" "0" "synthetic multi-diff run exits 0"
SYN_VER="$(jq -r '.metadata.version' "$TMP_SYN/apps/authentik/app.json")"
SYN_IMG="$(jq -r '.services[0].image' "$TMP_SYN/out/runtipi/authentik/docker-compose.json")"
assert_eq "$SYN_IMG" "ghcr.io/goauthentik/server:$SYN_VER" "multi-diff falls back to main_image:version"
assert_eq "$(printf '%s' "$SYN_IMG" | grep -c '@' || true)" "0" "multi-diff fallback carries no digest"
assert_eq "$(grep -c 'WARNING' "$SYN_LOG" || true)" "1" "multi-diff emits exactly one warning"
rm -rf "$TMP_SYN"

section "e2e: full-run neutrality (opt in with RUNTIPI_FULL_RUN=1)"
if [[ "${RUNTIPI_FULL_RUN:-0}" == "1" ]]; then
  TMP_FULL="$(mktemp -d)"
  FULL_LOG="$TMP_FULL/run.log"
  bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -o "$TMP_FULL/out" > "$FULL_LOG" 2>&1
  FULL_EXIT=$?
  assert_eq "$FULL_EXIT" "0" "full runtipi run exits 0"
  assert_eq "$(grep -c 'WARNING' "$FULL_LOG" || true)" "4" "full run emits exactly 4 warnings"
  FULL_ERRS="$(grep 'Errors:' "$FULL_LOG" | tail -1 | grep -Eo '[0-9]+ apps' | grep -Eo '^[0-9]+' || true)"
  assert_eq "$FULL_ERRS" "0" "full run reports Errors: 0"
  DIRTY=0
  for J in "$TMP_FULL"/out/runtipi/*/docker-compose.json; do
    IMG="$(jq -r '.services[0].image' "$J")"
    LINES="$(printf '%s\n' "$IMG" | wc -l | tr -d ' ')"
    if [[ "$LINES" != "1" || "$IMG" == *"WARNING"* ]]; then DIRTY=$((DIRTY+1)); echo "DIRTY: $J -> $IMG"; fi
  done
  assert_eq "$DIRTY" "0" "no docker-compose.json image is multiline or contains WARNING"
  rm -rf "$TMP_FULL"
else
  echo "ok: full-run case skipped (set RUNTIPI_FULL_RUN=1 to enable)"
fi

exit $fail
