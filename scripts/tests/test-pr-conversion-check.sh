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
  if (cd "$TMP" && CHANGED_APPS="$changed_apps" bash -e -o pipefail step.sh) > "$TMP/run.log" 2>&1; then
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
