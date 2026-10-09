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
assert_eq "$(output_mentions "Removing orphaned app: bar")" "1" "removal names the app"

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

section "--no-clean keeps the named app that left converted"
prepare
run_sync casaos --no-clean --app bar
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(exists "$APPS/bar")" "yes" "named app survives --no-clean"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "stale" "unrequested app is untouched"

section "--app removes the named app when converted has no app directories"
prepare
rm -rf "$UNIVERSAL/converted/casaos/foo"
run_sync casaos --app bar
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(exists "$APPS/bar")" "no" "named app is removed from an empty converted directory"
assert_eq "$(exists "$APPS/foo")" "yes" "unrequested app survives"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "stale" "unrequested app is untouched"

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

section "--app maps through the umbrel folder prefix"
prepare
UMBREL="$TMP/big-bear-umbrel"
mkdir -p "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo" "$UMBREL/big-bear-umbrel-foo"
echo "umbrel-new" > "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo/docker-compose.yml"
echo "umbrel-stale" > "$UMBREL/big-bear-umbrel-foo/docker-compose.yml"
run_sync umbrel --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$UMBREL/big-bear-umbrel-foo/docker-compose.yml")" "umbrel-new" "umbrel app is synced by its source name"

section "--app maps through a folder_name override"
prepare
mkdir -p "$UNIVERSAL/apps/foo" "$UNIVERSAL/converted/casaos/custom-fixture" "$APPS/custom-fixture"
cat > "$UNIVERSAL/apps/foo/app.json" << 'EOF'
{
  "metadata": { "id": "foo" },
  "compatibility": { "casaos": { "folder_name": "custom-fixture" } }
}
EOF
echo "override-new" > "$UNIVERSAL/converted/casaos/custom-fixture/docker-compose.yml"
echo "override-stale" > "$APPS/custom-fixture/docker-compose.yml"
run_sync casaos --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$APPS/custom-fixture/docker-compose.yml")" "override-new" "override folder is synced"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "stale" "literal folder is not the override target"

section "--app uses metadata.id when it differs from the directory name"
prepare
UMBREL="$TMP/big-bear-umbrel"
mkdir -p "$UNIVERSAL/apps/Homepage" "$UNIVERSAL/converted/umbrel/homepage" "$UMBREL/homepage"
cat > "$UNIVERSAL/apps/Homepage/app.json" << 'EOF'
{
  "metadata": { "id": "homepage" }
}
EOF
echo "id-new" > "$UNIVERSAL/converted/umbrel/homepage/docker-compose.yml"
echo "id-stale" > "$UMBREL/homepage/docker-compose.yml"
echo "app: homepage" > "$UNIVERSAL/converted/umbrel/homepage/umbrel-app.yml"
echo "app: homepage" > "$UMBREL/homepage/umbrel-app.yml"
run_sync umbrel --app Homepage
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$UMBREL/homepage/docker-compose.yml")" "id-new" "metadata.id is the umbrel folder when it differs from the directory"

section "--app warns when nothing matches"
prepare
run_sync casaos --app nope
assert_eq "$?" "0" "a miss still exits cleanly"
assert_eq "$(output_mentions "No app matched 'nope' for casaos")" "1" "a miss is announced"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "stale" "unrelated app is untouched"
assert_eq "$(exists "$APPS/bar")" "yes" "unrelated app survives a miss"

section "--workspace selects the platform repositories"
prepare
REQ="$TMP/requested-workspace"
mkdir -p "$REQ/big-bear-casaos/Apps/foo"
echo "untouched" > "$REQ/big-bear-casaos/Apps/foo/docker-compose.yml"
run_sync casaos -w "$REQ" --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$REQ/big-bear-casaos/Apps/foo/docker-compose.yml")" "updated-content" "requested workspace receives the app"
assert_eq "$(cat "$APPS/foo/docker-compose.yml")" "stale" "default workspace is not written"

write_umbrel_tree() {
  local umbrel="$TMP/big-bear-umbrel"
  rm -rf "$umbrel"
  mkdir -p "$umbrel/.git" \
    "$umbrel/.github/workflows" \
    "$umbrel/scripts" \
    "$umbrel/templates" \
    "$umbrel/schemas" \
    "$umbrel/node_modules" \
    "$umbrel/__tests__" \
    "$umbrel/big-bear-umbrel-foo" \
    "$umbrel/big-bear-umbrel-orphan" \
    "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo"
  echo "keep-git" > "$umbrel/.git/HEAD"
  echo "keep-gh" > "$umbrel/.github/workflows/ci.yml"
  echo "keep-scripts" > "$umbrel/scripts/tool.sh"
  echo "keep-templates" > "$umbrel/templates/README.md"
  echo "keep-schemas" > "$umbrel/schemas/schema.json"
  echo "keep-modules" > "$umbrel/node_modules/pkg.js"
  echo "keep-tests" > "$umbrel/__tests__/apps.test.ts"
  echo "umbrel-new" > "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo/docker-compose.yml"
  echo "app: foo" > "$UNIVERSAL/converted/umbrel/big-bear-umbrel-foo/umbrel-app.yml"
  echo "previous-umbrel-content" > "$umbrel/big-bear-umbrel-foo/docker-compose.yml"
  echo "app: foo" > "$umbrel/big-bear-umbrel-foo/umbrel-app.yml"
  echo "orphan" > "$umbrel/big-bear-umbrel-orphan/docker-compose.yml"
  echo "app: orphan" > "$umbrel/big-bear-umbrel-orphan/umbrel-app.yml"
}

section "umbrel cleanup keeps repository directories and removes orphan apps"
prepare
write_umbrel_tree
UMBREL="$TMP/big-bear-umbrel"
run_sync umbrel
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$UMBREL/big-bear-umbrel-foo/docker-compose.yml")" "umbrel-new" "converted umbrel app is synced"
assert_eq "$(exists "$UMBREL/big-bear-umbrel-orphan")" "no" "orphaned umbrel app is removed"
assert_eq "$(exists "$UMBREL/.git/HEAD")" "yes" ".git survives cleanup"
assert_eq "$(exists "$UMBREL/.github/workflows/ci.yml")" "yes" ".github survives cleanup"
assert_eq "$(exists "$UMBREL/scripts/tool.sh")" "yes" "scripts survives cleanup"
assert_eq "$(exists "$UMBREL/templates/README.md")" "yes" "templates survives cleanup"
assert_eq "$(exists "$UMBREL/schemas/schema.json")" "yes" "schemas survives cleanup"
assert_eq "$(exists "$UMBREL/node_modules/pkg.js")" "yes" "node_modules survives cleanup"
assert_eq "$(exists "$UMBREL/__tests__/apps.test.ts")" "yes" "__tests__ survives cleanup"

section "umbrel --replace-all keeps repository directories"
prepare
write_umbrel_tree
UMBREL="$TMP/big-bear-umbrel"
run_sync umbrel --replace-all
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(cat "$UMBREL/big-bear-umbrel-foo/docker-compose.yml")" "umbrel-new" "app is replaced from converted"
assert_eq "$(exists "$UMBREL/big-bear-umbrel-orphan")" "no" "orphan is not restored"
assert_eq "$(exists "$UMBREL/.git/HEAD")" "yes" ".git survives --replace-all"
assert_eq "$(exists "$UMBREL/.github/workflows/ci.yml")" "yes" ".github survives --replace-all"
assert_eq "$(exists "$UMBREL/scripts/tool.sh")" "yes" "scripts survives --replace-all"
assert_eq "$(exists "$UMBREL/templates/README.md")" "yes" "templates survives --replace-all"
assert_eq "$(exists "$UMBREL/schemas/schema.json")" "yes" "schemas survives --replace-all"
assert_eq "$(exists "$UMBREL/node_modules/pkg.js")" "yes" "node_modules survives --replace-all"
assert_eq "$(exists "$UMBREL/__tests__/apps.test.ts")" "yes" "__tests__ survives --replace-all"

section "umbrel --app removes the prefixed folder that left converted"
prepare
UMBREL="$TMP/big-bear-umbrel"
mkdir -p "$UMBREL/big-bear-umbrel-foo" "$UMBREL/big-bear-umbrel-bar" "$UMBREL/schemas" "$UNIVERSAL/converted/umbrel/big-bear-umbrel-bar"
echo "remove-me" > "$UMBREL/big-bear-umbrel-foo/docker-compose.yml"
echo "app: foo" > "$UMBREL/big-bear-umbrel-foo/umbrel-app.yml"
echo "keep-bar" > "$UMBREL/big-bear-umbrel-bar/docker-compose.yml"
echo "app: bar" > "$UMBREL/big-bear-umbrel-bar/umbrel-app.yml"
echo "keep-schemas" > "$UMBREL/schemas/schema.json"
echo "bar-src" > "$UNIVERSAL/converted/umbrel/big-bear-umbrel-bar/docker-compose.yml"
echo "app: bar" > "$UNIVERSAL/converted/umbrel/big-bear-umbrel-bar/umbrel-app.yml"
run_sync umbrel --app foo
assert_eq "$?" "0" "sync exits cleanly"
assert_eq "$(exists "$UMBREL/big-bear-umbrel-foo")" "no" "prefixed folder that left converted is removed"
assert_eq "$(exists "$UMBREL/big-bear-umbrel-bar")" "yes" "other umbrel app survives"
assert_eq "$(exists "$UMBREL/schemas/schema.json")" "yes" "repository directory survives a targeted removal"

echo
if [[ $fail -ne 0 ]]; then echo "FAILED"; exit 1; fi
echo "All sync single-app tests passed"
