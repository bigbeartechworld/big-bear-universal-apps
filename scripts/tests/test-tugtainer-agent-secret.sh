#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
COMPOSE="$REPO/apps/tugtainer/docker-compose.yml"
APP="$REPO/apps/tugtainer/app.json"
fail=0

secret="$(yq eval '.services["big-bear-tugtainer"].environment.AGENT_SECRET' "$COMPOSE")"
if [[ -z "$secret" || "$secret" == "null" ]]; then
  echo "FAIL: AGENT_SECRET missing from tugtainer compose"
  fail=1
else
  echo "ok: AGENT_SECRET set"
fi

if jq -e '.deployment.environment_variables[] | select(.name=="AGENT_SECRET")' "$APP" >/dev/null; then
  echo "ok: AGENT_SECRET in app.json"
else
  echo "FAIL: AGENT_SECRET missing from app.json"
  fail=1
fi

exit "$fail"
