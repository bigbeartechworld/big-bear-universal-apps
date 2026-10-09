#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"

fail=0
SYNC_OUTPUT=""
assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label — got '$actual' want '$expected'"
    echo "--- last sync output ---"
    echo "$SYNC_OUTPUT"
    echo "------------------------"
    fail=1
  else
    echo "ok: $label"
  fi
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
  SYNC_OUTPUT="$(bash "$UNIVERSAL/scripts/sync-to-platforms.sh" -p "$platform" --force "$@" 2>&1)"
}

output_mentions() { grep -c -- "$1" <<< "$SYNC_OUTPUT"; }

section "single-app sync keeps apps outside the converted set"
prepare
run_sync casaos --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "updated-content" "requested app is synced"
assert_eq "$(exists "$APPS/bar")" "yes" "other app survives --app sync"

section "single-app sync removes only the named app that left converted"
prepare
run_sync casaos --app bar
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(exists "$APPS/bar")" "no" "named app missing from converted is removed"
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
assert_eq "$(output_mentions "Skipping Portainer templates.json update")" "1" "skipped catalog update is announced"

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
assert_eq "$(output_mentions "cannot be combined with --app")" "1" "rejection explains why"
assert_eq "$(exists "$APPS/bar")" "yes" "nothing is deleted"

section "empty --app value is rejected"
prepare
run_sync casaos --app ""
status=$?
assert_eq "$([[ $status -ne 0 ]] && echo rejected || echo accepted)" "rejected" "empty app name exits non-zero"
assert_eq "$(output_mentions "requires a non-empty app name")" "1" "rejection explains why"
assert_eq "$(exists "$APPS/bar")" "yes" "nothing is deleted"

section "--app without a value is rejected"
prepare
run_sync casaos --app
status=$?
assert_eq "$([[ $status -ne 0 ]] && echo rejected || echo accepted)" "rejected" "missing app name exits non-zero"
assert_eq "$(output_mentions "requires a non-empty app name")" "1" "rejection explains why"

section "--app matches the Umbrel converted folder"
prepare
UMBREL="$TMP/big-bear-umbrel"
mkdir -p "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo" "$UMBREL/big-bear-umbrel-foo" "$UMBREL/big-bear-umbrel-bar" "$UMBREL/scripts"
echo "updated-umbrel" > "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo/docker-compose.yml"
echo "stale-umbrel" > "$UMBREL/big-bear-umbrel-foo/docker-compose.yml"
echo "other-app" > "$UMBREL/big-bear-umbrel-bar/umbrel-app.yml"
echo "keep-scripts" > "$UMBREL/scripts/fix.sh"
run_sync umbrel --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$UMBREL/big-bear-umbrel-foo/docker-compose.yml")" "updated-umbrel" "umbrel app id maps to big-bear-umbrel-<id>"
assert_eq "$(exists "$UMBREL/big-bear-umbrel-bar/umbrel-app.yml")" "yes" "other umbrel app survives --app"
assert_eq "$(cat "$UMBREL/scripts/fix.sh")" "keep-scripts" "umbrel scripts survive --app"

section "--app matches a folder_name override"
prepare
rm -rf "$UNIVERSAL/converted/casaos/foo"
mkdir -p "$UNIVERSAL/apps/foo" "$UNIVERSAL/converted/casaos/custom-foo" "$APPS/custom-foo"
cat > "$UNIVERSAL/apps/foo/app.json" <<'JSON'
{"metadata":{"id":"foo"},"compatibility":{"casaos":{"folder_name":"custom-foo"}}}
JSON
echo "updated-custom" > "$UNIVERSAL/converted/casaos/custom-foo/docker-compose.yml"
echo "stale-custom" > "$APPS/custom-foo/docker-compose.yml"
run_sync casaos --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$APPS/custom-foo/docker-compose.yml")" "updated-custom" "folder_name override is the sync target"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "stale" "app id folder is not the override target"
assert_eq "$(exists "$APPS/bar")" "yes" "other app survives folder_name sync"

section "--replace-all on umbrel keeps repo metadata"
prepare
UMBREL="$TMP/big-bear-umbrel"
mkdir -p "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo" \
  "$UMBREL/big-bear-umbrel-foo" "$UMBREL/big-bear-umbrel-bar" \
  "$UMBREL/.git" "$UMBREL/.github" "$UMBREL/scripts" "$UMBREL/templates" \
  "$UMBREL/docs" "$UMBREL/__tests__"
echo "updated-umbrel" > "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo/docker-compose.yml"
echo "manifest" > "$UMBREL/big-bear-umbrel-foo/umbrel-app.yml"
echo "other-app" > "$UMBREL/big-bear-umbrel-bar/umbrel-app.yml"
echo "gitkeep" > "$UMBREL/.git/config"
echo "workflow" > "$UMBREL/.github/workflows.yml"
echo "keep-scripts" > "$UMBREL/scripts/fix.sh"
echo "keep-template" > "$UMBREL/templates/README.md"
echo "keep-docs" > "$UMBREL/docs/README.md"
echo "keep-tests" > "$UMBREL/__tests__/apps.test.ts"
run_sync umbrel --replace-all
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$UMBREL/big-bear-umbrel-foo/docker-compose.yml")" "updated-umbrel" "converted umbrel app is restored"
assert_eq "$(exists "$UMBREL/big-bear-umbrel-bar")" "no" "umbrel app absent from converted is removed"
assert_eq "$(cat "$UMBREL/.git/config")" "gitkeep" ".git survives umbrel replace-all"
assert_eq "$(cat "$UMBREL/.github/workflows.yml")" "workflow" ".github survives umbrel replace-all"
assert_eq "$(cat "$UMBREL/scripts/fix.sh")" "keep-scripts" "scripts survive umbrel replace-all"
assert_eq "$(cat "$UMBREL/templates/README.md")" "keep-template" "templates survive umbrel replace-all"
assert_eq "$(cat "$UMBREL/docs/README.md")" "keep-docs" "new top-level folder survives umbrel replace-all"
assert_eq "$(cat "$UMBREL/__tests__/apps.test.ts")" "keep-tests" "__tests__ survives umbrel replace-all"

section "--workspace selects the platform repositories"
prepare
ELSEWHERE="$TMP/elsewhere"
mkdir -p "$ELSEWHERE/big-bear-casaos/Apps/foo"
echo "alt-stale" > "$ELSEWHERE/big-bear-casaos/Apps/foo/docker-compose.yml"
run_sync casaos --app foo -w "$ELSEWHERE"
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$ELSEWHERE/big-bear-casaos/Apps/foo/docker-compose.yml")" "updated-content" "--workspace receives the sync"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "stale" "default workspace is not used when --workspace is set"

section "umbrel full sync removes orphan apps and keeps other top-level folders"
prepare
UMBREL="$TMP/big-bear-umbrel"
mkdir -p "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo" \
  "$UMBREL/big-bear-umbrel-foo" "$UMBREL/big-bear-umbrel-bar" "$UMBREL/docs"
echo "updated-umbrel" > "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo/docker-compose.yml"
echo "stale-umbrel" > "$UMBREL/big-bear-umbrel-foo/docker-compose.yml"
echo "orphan" > "$UMBREL/big-bear-umbrel-bar/umbrel-app.yml"
echo "keep-docs" > "$UMBREL/docs/README.md"
run_sync umbrel
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$UMBREL/big-bear-umbrel-foo/docker-compose.yml")" "updated-umbrel" "umbrel app is synced"
assert_eq "$(exists "$UMBREL/big-bear-umbrel-bar")" "no" "orphaned umbrel app is removed"
assert_eq "$(cat "$UMBREL/docs/README.md")" "keep-docs" "non-app folder survives umbrel cleanup"

section "--app removes an umbrel app that left converted"
prepare
UMBREL="$TMP/big-bear-umbrel"
mkdir -p "$UNIVERSAL/converted/umbrel/big-bear-umbrel-bar" \
  "$UMBREL/big-bear-umbrel-foo" "$UMBREL/big-bear-umbrel-bar" "$UMBREL/scripts"
echo "stay" > "$UNIVERSAL/converted/umbrel/big-bear-umbrel-bar/docker-compose.yml"
echo "gone-app" > "$UMBREL/big-bear-umbrel-foo/umbrel-app.yml"
echo "stay-dest" > "$UMBREL/big-bear-umbrel-bar/docker-compose.yml"
echo "keep-scripts" > "$UMBREL/scripts/fix.sh"
run_sync umbrel --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(exists "$UMBREL/big-bear-umbrel-foo")" "no" "umbrel app that left converted is removed"
assert_eq "$(cat "$UMBREL/big-bear-umbrel-bar/docker-compose.yml")" "stay-dest" "other umbrel app is untouched"
assert_eq "$(cat "$UMBREL/scripts/fix.sh")" "keep-scripts" "umbrel scripts survive targeted removal"

section "--app removes an unsupported umbrel app when that platform produced no output"
prepare
UMBREL="$TMP/big-bear-umbrel"
mkdir -p "$UNIVERSAL/apps/foo" "$UMBREL/custom-umbrel-name" "$UMBREL/scripts" "$UMBREL/.git"
cat > "$UNIVERSAL/apps/foo/app.json" <<'JSON'
{"metadata":{"id":"foo"},"compatibility":{"umbrel":{"supported":false,"folder_name":"custom-umbrel-name"}}}
JSON
echo "gone-app" > "$UMBREL/custom-umbrel-name/umbrel-app.yml"
echo "keep-scripts" > "$UMBREL/scripts/fix.sh"
echo "gitkeep" > "$UMBREL/.git/config"
run_sync umbrel --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(exists "$UMBREL/custom-umbrel-name")" "no" "unsupported umbrel folder_name is removed"
assert_eq "$(cat "$UMBREL/scripts/fix.sh")" "keep-scripts" "scripts survive unsupported-app removal"
assert_eq "$(cat "$UMBREL/.git/config")" "gitkeep" ".git survives unsupported-app removal"

section "--app that matches nothing warns and changes nothing"
prepare
run_sync casaos --app nope
status=$?
assert_eq "$([[ $status -ne 0 ]] && echo rejected || echo accepted)" "rejected" "unmatched app exits non-zero"
assert_eq "$(output_mentions "No app matched --app nope")" "1" "unmatched app is announced"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "stale" "unrelated app is untouched"
assert_eq "$(exists "$APPS/bar")" "yes" "other app survives an unmatched --app"

echo
if [[ $fail -ne 0 ]]; then echo "FAILED"; exit 1; fi
echo "All sync single-app tests passed"
