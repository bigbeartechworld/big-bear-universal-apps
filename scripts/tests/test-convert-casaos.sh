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

exit $fail
