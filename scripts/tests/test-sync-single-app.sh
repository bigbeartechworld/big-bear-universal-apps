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

exists() { [[ -e "$1" ]] && echo yes || echo no; }

SYNC_SCRIPT="${SYNC_SCRIPT:-$REPO/scripts/sync-to-platforms.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

UNIVERSAL="$TMP/universal"
APPS="$TMP/big-bear-casaos/Apps"

prepare() {
  rm -rf "$TMP"/*
  mkdir -p "$UNIVERSAL/scripts" "$UNIVERSAL/converted/casaos/foo" "$APPS/foo" "$APPS/bar"
  cp "$SYNC_SCRIPT" "$UNIVERSAL/scripts/sync-to-platforms.sh"
  echo "updated-content" > "$UNIVERSAL/converted/casaos/foo/docker-compose.yml"
  echo "stale" > "$APPS/foo/docker-compose.yml"
  echo "keep" > "$APPS/bar/docker-compose.yml"
}

run_sync() {
  bash "$UNIVERSAL/scripts/sync-to-platforms.sh" -p casaos --force "$@" >/dev/null 2>&1
}

section "single-app sync keeps apps outside the converted set"
prepare
run_sync --app foo
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "updated-content" "requested app is synced"
assert_eq "$(exists "$APPS/bar")" "yes" "other app survives --app sync"

section "full sync still removes orphaned apps"
prepare
run_sync
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "updated-content" "app is synced"
assert_eq "$(exists "$APPS/bar")" "no" "orphaned app is removed without --app"

section "--no-clean keeps orphaned apps on a full sync"
prepare
run_sync --no-clean
assert_eq "$(exists "$APPS/bar")" "yes" "orphaned app survives --no-clean"

echo
if [[ $fail -ne 0 ]]; then echo "FAILED"; exit 1; fi
echo "All sync single-app tests passed"
