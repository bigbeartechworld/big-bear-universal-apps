#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$REPO/scripts/convert-to-platforms.sh" --source-only 2>/dev/null || true

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
  [[ "$v" == "MISSING" ]] && MISSING=$((MISSING+1))
done
assert_eq "$MISSING" "0" "all apps have casaos.category"
rm -rf "$TMP_APPS"

exit $fail
