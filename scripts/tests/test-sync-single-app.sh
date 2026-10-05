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
TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "${TMP:?}"' EXIT

UNIVERSAL="$TMP/universal"
APPS="$TMP/big-bear-casaos/Apps"
PORTAINER="$TMP/big-bear-portainer"

prepare() {
  rm -rf "${TMP:?}"/*
  mkdir -p "$UNIVERSAL/scripts" "$UNIVERSAL/converted/casaos/foo" "$APPS/foo" "$APPS/bar"
  mkdir -p "$UNIVERSAL/converted/portainer/foo" "$PORTAINER/Apps/foo"
  cp "$SYNC_SCRIPT" "$UNIVERSAL/scripts/sync-to-platforms.sh"
  echo "updated-content" > "$UNIVERSAL/converted/casaos/foo/docker-compose.yml"
  echo "stale" > "$APPS/foo/docker-compose.yml"
  echo "keep" > "$APPS/bar/docker-compose.yml"
  echo "single-app-catalog" > "$UNIVERSAL/converted/portainer/templates.json"
  echo "full-catalog" > "$PORTAINER/templates.json"
}

run_sync() {
  local platform="$1"
  shift
  bash "$UNIVERSAL/scripts/sync-to-platforms.sh" -p "$platform" --force "$@" >/dev/null 2>&1
}

section "single-app sync keeps apps outside the converted set"
prepare
run_sync casaos --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "updated-content" "requested app is synced"
assert_eq "$(exists "$APPS/bar")" "yes" "other app survives --app sync"

section "single-app sync of an app missing from converted keeps it"
prepare
run_sync casaos --app bar
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(exists "$APPS/bar")" "yes" "requested app missing from converted is not removed"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "stale" "unrequested app is untouched"

section "full sync still removes orphaned apps"
prepare
run_sync casaos
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "updated-content" "app is synced"
assert_eq "$(exists "$APPS/bar")" "no" "orphaned app is removed without --app"

section "--no-clean keeps orphaned apps on a full sync"
prepare
run_sync casaos --no-clean
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "updated-content" "app is synced"
assert_eq "$(exists "$APPS/bar")" "yes" "orphaned app survives --no-clean"

section "single-app portainer sync keeps the full catalog"
prepare
run_sync portainer --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$PORTAINER/templates.json")" "full-catalog" "templates.json is not overwritten by a one-app catalog"

section "full portainer sync publishes the catalog"
prepare
run_sync portainer
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$PORTAINER/templates.json")" "single-app-catalog" "templates.json is copied on a full sync"

section "--replace-all with --app is rejected"
prepare
run_sync casaos --replace-all --app foo
status=$?
assert_eq "$([[ $status -ne 0 ]] && echo rejected || echo accepted)" "rejected" "combination exits non-zero"
assert_eq "$(exists "$APPS/bar")" "yes" "nothing is deleted"

echo
if [[ $fail -ne 0 ]]; then echo "FAILED"; exit 1; fi
echo "All sync single-app tests passed"
