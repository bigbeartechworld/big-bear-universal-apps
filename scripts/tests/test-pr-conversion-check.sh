#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Execute the actual workflow step so its output checks cannot drift from CI.
yq -r '.jobs.test-conversion.steps[] | select(.name == "Test conversion for changed apps") | .run' \
  "$REPO/.github/workflows/validate-pr.yml" > "$TMP/step.sh"

mkdir -p "$TMP/scripts" "$TMP/apps/fixture" "$TMP/apps/_example"
cat > "$TMP/scripts/convert-to-platforms.sh" <<'SH'
#!/bin/bash
exit "${CONVERTER_EXIT_CODE:-0}"
SH
chmod +x "$TMP/scripts/convert-to-platforms.sh"
cat > "$TMP/apps/fixture/app.json" <<'JSON'
{"metadata":{"id":"fixture"},"compatibility":{}}
JSON

check() {
  local expected="$1" changed_apps="$2" label="$3" actual
  if (cd "$TMP" && CHANGED_APPS="$changed_apps" bash -e step.sh) > "$TMP/run.log" 2>&1; then
    actual=0
  else
    actual=$?
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label (exit $actual, expected $expected)"
    cat "$TMP/run.log"
    exit 1
  fi
  echo "ok: $label"
}

for platform in casaos portainer runtipi dockge cosmos; do
  mkdir -p "$TMP/converted/$platform/fixture"
done
mkdir -p "$TMP/converted/umbrel/big-bear-umbrel-fixture"
check 0 fixture "default Umbrel prefix is accepted"
check 0 '' "no changed apps is successful"
check 0 _example "example template does not require converted output"

jq '.compatibility.casaos.folder_name = "custom-fixture" | .compatibility.umbrel.folder_name = "big-bear-umbrel-custom-fixture"' \
  "$TMP/apps/fixture/app.json" > "$TMP/app.json"
mv "$TMP/app.json" "$TMP/apps/fixture/app.json"
mv "$TMP/converted/casaos/fixture" "$TMP/converted/casaos/custom-fixture"
mv "$TMP/converted/umbrel/big-bear-umbrel-fixture" "$TMP/converted/umbrel/big-bear-umbrel-custom-fixture"
check 0 fixture "custom platform folder names are accepted"

jq '.compatibility.runtipi.supported = false' "$TMP/apps/fixture/app.json" > "$TMP/app.json"
mv "$TMP/app.json" "$TMP/apps/fixture/app.json"
rmdir "$TMP/converted/runtipi/fixture"
check 0 fixture "unsupported platforms do not require output"

rmdir "$TMP/converted/umbrel/big-bear-umbrel-custom-fixture"
check 1 fixture "missing supported output still fails"
mkdir -p "$TMP/converted/umbrel/big-bear-umbrel-custom-fixture"
export CONVERTER_EXIT_CODE=1
check 1 fixture "converter failure still fails"

# Build real commit history for both changed-app discovery steps. Use a base
# other than main so accidentally hard-coding the branch cannot pass the test.
HISTORY="$TMP/history"
git init -q "$HISTORY"
git -C "$HISTORY" config user.name "Workflow Test"
git -C "$HISTORY" config user.email "workflow-test@example.invalid"
git -C "$HISTORY" read-tree --empty
base=$(git -C "$HISTORY" -c commit.gpgsign=false commit-tree "$(git -C "$HISTORY" write-tree)" -m base)
git -C "$HISTORY" update-ref refs/remotes/origin/fixture-base "$base"

printf 'Documentation only\n' > "$HISTORY/README.md"
git -C "$HISTORY" add README.md
docs=$(git -C "$HISTORY" -c commit.gpgsign=false commit-tree "$(git -C "$HISTORY" write-tree)" -p "$base" -m docs)
git -C "$HISTORY" update-ref --no-deref HEAD "$docs"

for job in validate-apps test-conversion; do
  CHECK_JOB="$job" yq -r '.jobs[strenv(CHECK_JOB)].steps[] | select(.id == "changed-apps") | .run' \
    "$REPO/.github/workflows/validate-pr.yml" > "$TMP/detect-$job.sh"
done

run_detection() {
  local job="$1" base_ref="$2" step_shell
  local -a command
  step_shell=$(CHECK_JOB="$job" yq -r '.jobs[strenv(CHECK_JOB)].steps[] | select(.id == "changed-apps") | .shell // ""' \
    "$REPO/.github/workflows/validate-pr.yml")
  # Match GitHub's Linux runner: an explicit bash shell enables pipefail,
  # while the implicit bash shell does not. Removing it must fail this suite.
  case "$step_shell" in
    bash) command=(bash --noprofile --norc -eo pipefail) ;;
    '') command=(bash -e) ;;
    *) echo "Unsupported workflow shell: $step_shell" >&2; return 1 ;;
  esac
  (cd "$HISTORY" && BASE_REF="$base_ref" GITHUB_OUTPUT="$TMP/detected" \
    "${command[@]}" "$TMP/detect-$job.sh")
}

check_detection() {
  local expected="$1" label="$2" job actual
  for job in validate-apps test-conversion; do
    : > "$TMP/detected"
    if ! run_detection "$job" fixture-base > "$TMP/run.log" 2>&1; then
      echo "FAIL: $job $label"
      cat "$TMP/run.log"
      exit 1
    fi
    actual=$(cat "$TMP/detected")
    if [[ "$actual" != $'changed_apps<<EOF\n'"$expected"$'\nEOF' ]]; then
      echo "FAIL: $job $label (unexpected output: $actual)"
      exit 1
    fi
    echo "ok: $job $label"
  done
}

check_detection '' "documentation-only history produces no changed apps"
mkdir -p "$HISTORY/apps/alpha" "$HISTORY/apps/zeta"
printf '{}\n' > "$HISTORY/apps/alpha/app.json"
printf 'services: {}\n' > "$HISTORY/apps/alpha/docker-compose.yml"
printf '{}\n' > "$HISTORY/apps/zeta/app.json"
git -C "$HISTORY" add apps
apps=$(git -C "$HISTORY" -c commit.gpgsign=false commit-tree "$(git -C "$HISTORY" write-tree)" -p "$docs" -m apps)
git -C "$HISTORY" update-ref --no-deref HEAD "$apps"
check_detection $'alpha\nzeta' "finds and deduplicates changed app directories"

for job in validate-apps test-conversion; do
  if run_detection "$job" missing > "$TMP/run.log" 2>&1; then
    echo "FAIL: $job must reject a missing base ref"
    exit 1
  fi
  echo "ok: $job missing base ref fails instead of reporting no changed apps"
done
