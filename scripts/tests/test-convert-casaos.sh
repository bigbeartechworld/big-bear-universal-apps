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

exit $fail
