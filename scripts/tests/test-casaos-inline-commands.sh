#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$(dirname "$SCRIPT_DIR")")"
TMP_OUT=$(mktemp -d)
trap 'rm -rf "$TMP_OUT"' EXIT

for APP in ente buzz ghostfolio; do
  COMPOSE="$REPO/apps/$APP/docker-compose.yml"
  FIELD='.services.minio-init.entrypoint'
  if [[ "$APP" == ghostfolio ]]; then
    FIELD='.services.big-bear-ghostfolio-redis.command'
  fi
  [[ "$(yq eval "$FIELD | tag" "$COMPOSE")" == '!!seq' ]]
  SOURCE=$(yq eval -o=json -I=0 "$FIELD" "$COMPOSE")
  [[ "$SOURCE" != *'\n'* ]]
  if [[ "$APP" != ghostfolio ]]; then
    [[ "$(yq eval "$FIELD | length" "$COMPOSE")" == 3 ]]
    SCRIPT=$(yq eval "$FIELD[2]" "$COMPOSE")
    printf '%s\n' "${SCRIPT//\$\$/\$}" | sh -n
    if [[ "$APP" == buzz ]]; then
      [[ "$SCRIPT" == *'mc mb --ignore-existing "local/$${BUZZ_S3_BUCKET}"'* ]]
      [[ "$SCRIPT" == *'mc anonymous set none "local/$${BUZZ_S3_BUCKET}"'* ]]
    fi
    if [[ "$APP" == ente ]]; then
      for BUCKET in b2-eu-cen wasabi-eu-central-2-v3 scw-eu-fr-v3; do
        [[ "$SCRIPT" == *"mc mb --ignore-existing ente/$BUCKET;"* ]]
      done
    fi
  else
    [[ "$SOURCE" == '["--requirepass","casaosredispassword"]' ]]
  fi
  bash "$REPO/scripts/convert-to-platforms.sh" -p casaos -a "$APP" -o "$TMP_OUT" >/dev/null
  GENERATED="$TMP_OUT/casaos/$APP/docker-compose.yml"
  [[ "$(yq eval -o=json -I=0 "$FIELD" "$GENERATED")" == "$SOURCE" ]]
  echo "ok: $APP inline arguments preserved by CasaOS conversion"
done
