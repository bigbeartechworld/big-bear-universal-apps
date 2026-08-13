#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$REPO/scripts/convert-to-platforms.sh" --source-only 2>/dev/null || true
# The sourced converter runs `set -e`, which would abort this harness on the
# first failing assertion instead of reporting every result.
set +e

fail=0
assert_eq() { # $1=actual $2=expected $3=label
  if [[ "$1" != "$2" ]]; then echo "FAIL: $3 — got '$1' want '$2'"; fail=1; else echo "ok: $3"; fi
}

assert_eq "$(map_casaos_category Media)"          "Media"      "passthrough Media"
assert_eq "$(map_casaos_category Developer)"      "Developer"  "passthrough Developer"
assert_eq "$(map_casaos_category Development)"    "Developer"  "Development->Developer"
assert_eq "$(map_casaos_category Photography)"    "Media"      "Photography->Media"
assert_eq "$(map_casaos_category Storage)"        "Others"     "Storage->Others"
assert_eq "$(map_casaos_category Utilities)"      "Others"     "Utilities->Others"
assert_eq "$(map_casaos_category BigBearCasaOS)"  "Others"     "BigBearCasaOS->Others"
assert_eq "$(map_casaos_category Nonsense)"       "Others"     "unknown->Others"

# --- end-to-end: convert one real app to casaos and inspect output ---
TMP_OUT="$(mktemp -d)"
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a uptime-kuma -o "$TMP_OUT" >/dev/null 2>&1
CF="$TMP_OUT/casaos/uptime-kuma/docker-compose.yml"
assert_eq "$([[ -f "$CF" ]] && echo yes)" "yes" "casaos compose produced"
assert_eq "$(yq eval '.x-casaos.id' "$CF")" "com.bigbeartechworld.uptime-kuma" "x-casaos.id"
assert_eq "$(yq eval '.x-casaos.title | has("en_US")' "$CF")" "true" "title en_US"
assert_eq "$(yq eval '.x-casaos.title | has("en_us")' "$CF")" "false" "no title en_us"
CAT="$(yq eval '.x-casaos.category' "$CF")"
case "$CAT" in Media|Productivity|Home|Networking|AI|Finance|Social|Developer|Others) echo "ok: category valid ($CAT)";; *) echo "FAIL: category invalid ($CAT)"; fail=1;; esac
if yq eval '.. | select(tag == "!!map") | keys' "$CF" 2>/dev/null | grep -q '\ben_us\b'; then echo "FAIL: lowercase en_us present"; fail=1; else echo "ok: no en_us keys"; fi
rm -rf "$TMP_OUT"

# --- tips + service-level envs en_US re-key (nextcloud has both) ---
TMP_NC="$(mktemp -d)"
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a nextcloud -o "$TMP_NC" >/dev/null 2>&1
NC="$TMP_NC/casaos/nextcloud/docker-compose.yml"
assert_eq "$(yq eval '.x-casaos.tips.before_install | has("en_US")' "$NC")" "true" "tips re-keyed en_US"
assert_eq "$(yq eval '.x-casaos.tips.before_install | has("en_us")' "$NC")" "false" "tips no en_us"
if yq eval '.. | select(tag == "!!map") | keys' "$NC" 2>/dev/null | grep -q '\ben_us\b'; then echo "FAIL: nextcloud lowercase en_us present"; fail=1; else echo "ok: nextcloud no en_us keys (incl service envs)"; fi
rm -rf "$TMP_NC"

# --- category metadata-fallback branch: casaos.category absent -> map(metadata.category) ---
TMP_FB="$(mktemp -d)"
cp -R "$REPO/apps/." "$TMP_FB/apps/"
FB_APP="$TMP_FB/apps/uptime-kuma/app.json"
jq 'del(.compatibility.casaos.category)' "$FB_APP" > "$FB_APP.tmp" && mv "$FB_APP.tmp" "$FB_APP"
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a uptime-kuma -i "$TMP_FB/apps" -o "$TMP_FB/out" >/dev/null 2>&1
FBC="$TMP_FB/out/casaos/uptime-kuma/docker-compose.yml"
FB_CAT="$(yq eval '.x-casaos.category' "$FBC" 2>/dev/null)"
case "$FB_CAT" in Media|Productivity|Home|Networking|AI|Finance|Social|Developer|Others) echo "ok: fallback category valid ($FB_CAT)";; *) echo "FAIL: fallback category invalid ($FB_CAT)"; fail=1;; esac
rm -rf "$TMP_FB"

# --- category proposal script (writes to temp, not the committed map) ---
TMP_MAP="$(mktemp)"
CASAOS_MAP_OUT="$TMP_MAP" bun "$REPO/scripts/migrate-casaos-categories.ts" >/dev/null 2>&1
assert_eq "$([[ -s "$TMP_MAP" ]] && echo yes)" "yes" "map file produced"
BAD=$(jq -r '.[]' "$TMP_MAP" | grep -Evc '^(Media|Productivity|Home|Networking|AI|Finance|Social|Developer|Others)$' || true)
assert_eq "$BAD" "0" "all mapped categories valid"
NAPPS=$(ls -d "$REPO"/apps/*/ | wc -l | tr -d ' ')
NMAP=$(jq 'length' "$TMP_MAP")
assert_eq "$NMAP" "$NAPPS" "map covers every app"
rm -f "$TMP_MAP"

# --- apply writes compatibility.casaos.category, leaves metadata.category ---
# Run against a throwaway copy of apps/ so the test never mutates tracked files.
TMP_APPS="$(mktemp -d)"
cp -R "$REPO/apps/." "$TMP_APPS/"
BEFORE_META=$(jq -r '.metadata.category' "$TMP_APPS/uptime-kuma/app.json")
CASAOS_APPS_DIR="$TMP_APPS" bun "$REPO/scripts/migrate-casaos-categories.ts" --apply >/dev/null 2>&1
AFTER_CASAOS=$(jq -r '.compatibility.casaos.category' "$TMP_APPS/uptime-kuma/app.json")
AFTER_META=$(jq -r '.metadata.category' "$TMP_APPS/uptime-kuma/app.json")
case "$AFTER_CASAOS" in Media|Productivity|Home|Networking|AI|Finance|Social|Developer|Others) echo "ok: casaos.category set ($AFTER_CASAOS)";; *) echo "FAIL: casaos.category invalid ($AFTER_CASAOS)"; fail=1;; esac
assert_eq "$AFTER_META" "$BEFORE_META" "metadata.category unchanged"
MISSING=0
for d in "$TMP_APPS"/*/; do
  v=$(jq -r '.compatibility.casaos.category // "MISSING"' "$d/app.json")
  [[ "$v" == "MISSING" ]] && MISSING=$((MISSING+1)) || true
done
assert_eq "$MISSING" "0" "all apps have casaos.category"
rm -rf "$TMP_APPS"

# --- yq expression injection is inert (issue #2478) ---
# Every attacker-controlled app.json field feeding a yq expression gets the payload,
# so reintroducing interpolation at any one site fails the suite.
for INJ_FIELD in metadata.description metadata.tagline metadata.author metadata.developer metadata.name visual.icon visual.thumbnail technical.main_service; do
  TMP_INJ="$(mktemp -d)"
  cp -R "$REPO/apps/." "$TMP_INJ/apps/"
  echo "CANARY_FILE_CONTENT_2478" > "$TMP_INJ/canary.txt"
  PAYLOAD='" | .x-casaos.pwned = load_str("'"$TMP_INJ"'/canary.txt") | .x-casaos.zz = "'
  INJ_APP="$TMP_INJ/apps/uptime-kuma/app.json"
  jq --arg p "$PAYLOAD" --arg f "$INJ_FIELD" 'setpath($f | split("."); $p)' "$INJ_APP" > "$INJ_APP.tmp" && mv "$INJ_APP.tmp" "$INJ_APP"
  bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a uptime-kuma -i "$TMP_INJ/apps" -o "$TMP_INJ/out" >/dev/null 2>&1
  INJ_CF="$TMP_INJ/out/casaos/uptime-kuma/docker-compose.yml"
  assert_eq "$([[ -s "$INJ_CF" ]] && echo yes)" "yes" "injection[$INJ_FIELD]: compose still produced"
  assert_eq "$(yq eval '.x-casaos | has("pwned")' "$INJ_CF" 2>/dev/null)" "false" "injection[$INJ_FIELD]: no injected key"
  if [[ -s "$INJ_CF" ]] && ! grep -q "CANARY_FILE_CONTENT_2478" "$INJ_CF"; then echo "ok: injection[$INJ_FIELD]: no foreign file content"; else echo "FAIL: injection[$INJ_FIELD]: canary file content leaked into output"; fail=1; fi
  rm -rf "$TMP_INJ"
done

# --- payload survives verbatim (proves it is stored as data, not dropped) ---
TMP_LIT="$(mktemp -d)"
cp -R "$REPO/apps/." "$TMP_LIT/apps/"
LIT_PAYLOAD='" | .x-casaos.pwned = load_str("/etc/hostname") | .x-casaos.zz = "'
LIT_APP="$TMP_LIT/apps/uptime-kuma/app.json"
jq --arg p "$LIT_PAYLOAD" '.metadata.description = $p | .metadata.author = $p' "$LIT_APP" > "$LIT_APP.tmp" && mv "$LIT_APP.tmp" "$LIT_APP"
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a uptime-kuma -i "$TMP_LIT/apps" -o "$TMP_LIT/out" >/dev/null 2>&1
LIT_CF="$TMP_LIT/out/casaos/uptime-kuma/docker-compose.yml"
assert_eq "$(yq eval '.x-casaos.description.en_US' "$LIT_CF" 2>/dev/null)" "$LIT_PAYLOAD" "injection: payload stored as literal string"
assert_eq "$(yq eval '.x-casaos.author' "$LIT_CF" 2>/dev/null)" "$LIT_PAYLOAD" "injection: author payload stored as literal string"
rm -rf "$TMP_LIT"

# --- compose-derived values are inert too (env keys, volume paths, ports) ---
TMP_CINJ="$(mktemp -d)"
cp -R "$REPO/apps/." "$TMP_CINJ/apps/"
echo "CANARY_COMPOSE_2478" > "$TMP_CINJ/canary.txt"
CPAYLOAD='" | .x-casaos.pwned = load_str("'"$TMP_CINJ"'/canary.txt") | .x-casaos.zz = "'
CINJ_DIR="$TMP_CINJ/apps/uptime-kuma"
CINJ_SVC=$(yq eval '.services | keys | .[0]' "$CINJ_DIR/docker-compose.yml")
CINJ_SVC="$CINJ_SVC" CPAYLOAD="$CPAYLOAD" yq eval '.services[strenv(CINJ_SVC)].environment[strenv(CPAYLOAD)] = "x" | .services[strenv(CINJ_SVC)].volumes += ["/tmp/src:" + strenv(CPAYLOAD)]' -i "$CINJ_DIR/docker-compose.yml"
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a uptime-kuma -i "$TMP_CINJ/apps" -o "$TMP_CINJ/out" >/dev/null 2>&1
CINJ_CF="$TMP_CINJ/out/casaos/uptime-kuma/docker-compose.yml"
assert_eq "$([[ -s "$CINJ_CF" ]] && echo yes)" "yes" "compose injection: compose still produced"
assert_eq "$(yq eval '.x-casaos | has("pwned")' "$CINJ_CF" 2>/dev/null)" "false" "compose injection: no injected key"
if [[ -s "$CINJ_CF" ]] && ! grep -q "CANARY_COMPOSE_2478" "$CINJ_CF"; then echo "ok: compose injection: no foreign file content"; else echo "FAIL: compose injection: canary file content leaked into output"; fail=1; fi
rm -rf "$TMP_CINJ"

# --- JSON blobs keep block style (naive env() would reflow them to flow style) ---
TMP_STYLE="$(mktemp -d)"
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a adguard-home -o "$TMP_STYLE" >/dev/null 2>&1
SCF="$TMP_STYLE/casaos/adguard-home/docker-compose.yml"
assert_eq "$([[ -s "$SCF" ]] && echo yes)" "yes" "style: compose produced"
if [[ -s "$SCF" ]] && ! grep -qE '^\s+screenshot_link: \[' "$SCF"; then echo "ok: screenshot_link block style"; else echo "FAIL: screenshot_link reflowed to flow style"; fail=1; fi
assert_eq "$(yq eval '.x-casaos.screenshot_link | length' "$SCF")" "3" "screenshot_link parsed as sequence"
assert_eq "$(yq eval '.x-casaos.architectures | tag' "$SCF")" "!!seq" "architectures still a sequence"
if grep -qE '^\s+en_US: \|' "$SCF"; then echo "ok: tips literal block scalar preserved"; else echo "FAIL: tips lost literal block scalar"; fail=1; fi
if [[ -s "$SCF" ]] && ! grep -qE '^\s+"en_[a-zA-Z]+":' "$SCF"; then echo "ok: blob keys unquoted"; else echo "FAIL: blob keys became quoted"; fail=1; fi
rm -rf "$TMP_STYLE"

# --- dotted service names address correctly (bracket form, not dot form) ---
TMP_DOT="$(mktemp -d)"
cp -R "$REPO/apps/." "$TMP_DOT/apps/"
DOT_DIR="$TMP_DOT/apps/uptime-kuma"
DOT_SVC=$(yq eval '.services | keys | .[0]' "$DOT_DIR/docker-compose.yml")
DOT_SVC="$DOT_SVC" yq eval '.services["svc.v2"] = .services[strenv(DOT_SVC)] | del(.services[strenv(DOT_SVC)]) | .volumes.testvol = null | .services["svc.v2"].volumes = ["testvol:/data"]' -i "$DOT_DIR/docker-compose.yml"
jq '.deployment.main_service = "svc.v2"' "$DOT_DIR/app.json" > "$DOT_DIR/app.json.tmp" && mv "$DOT_DIR/app.json.tmp" "$DOT_DIR/app.json"
bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a uptime-kuma -i "$TMP_DOT/apps" -o "$TMP_DOT/out" >/dev/null 2>&1
DCF="$TMP_DOT/out/casaos/uptime-kuma/docker-compose.yml"
assert_eq "$(yq eval '.services | keys | length' "$DCF" 2>/dev/null)" "1" "dotted name: no bogus split key"
assert_eq "$(yq eval '.services["svc.v2"].volumes[0]' "$DCF" 2>/dev/null)" '/DATA/AppData/$AppID/testvol:/data' "dotted name: volume converted to bind mount"
rm -rf "$TMP_DOT"

exit $fail
