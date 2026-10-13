#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/apps/fidelity" "$TMP/out/runtipi/fidelity"
jq '.metadata.id = "fidelity" | .technical.main_service = "app" | .visual.icon = "" | .compatibility.runtipi.volume_mappings = {data: "persist"}' \
  "$REPO/apps/uptime-kuma/app.json" > "$TMP/apps/fidelity/app.json"
cat > "$TMP/apps/fidelity/docker-compose.yml" <<'YAML'
services:
  db:
    image: postgres:14@sha256:bbbb
    user: "1000:1000"
    environment:
      POSTGRES_PASSWORD: "quoted=value"
      EMPTY: ""
      INHERITED:
    volumes:
      - type: volume
        source: data
        target: /var/lib/postgresql/data
        read_only: true
    healthcheck:
      test: [CMD, pg_isready]
  app:
    image: example/app:1@sha256:aaaa
    user: root
    environment:
      - KEY=value=with=equals
      - EMPTY=
      - INHERITED
    volumes:
      - data:/data:ro
      - ./config:/config:rw
    ports:
      - "127.0.0.1:9099:3001/tcp"
      - "9199:3101/udp"
    depends_on:
      db:
        condition: service_healthy
    command: [run, "literal $VALUE"]
    entrypoint: ["/bin/sh", "-c"]
    labels: ["example=value=with=equals"]
    networks:
      internal:
        aliases: [web]
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    read_only: true
    tmpfs: [/tmp]
    healthcheck:
      test: [CMD-SHELL, "curl -f http://localhost:3001"]
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: 512M
    restart: unless-stopped
  worker:
    image: example/app:2@sha256:cccc
    depends_on: [app]
    environment:
      APP_URL: http://app
networks:
  internal:
    internal: true
volumes:
  data: {}
YAML
printf '{"schemaVersion":2,"services":[]}' > "$TMP/out/runtipi/fidelity/docker-compose.json"
bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -a fidelity -i "$TMP/apps" -o "$TMP/out" > "$TMP/run.log" 2>&1
OUT="$TMP/out/runtipi/fidelity"
if [[ -f "$OUT/docker-compose.json" ]]; then
  echo "FAIL: legacy JSON still overrides the complete Compose YAML"
  exit 1
fi
yq -o=json '.' "$OUT/docker-compose.yml" > "$TMP/generated.json"
yq -o=json '.' "$TMP/apps/fidelity/docker-compose.yml" > "$TMP/source.json"
jq -e --slurpfile source "$TMP/source.json" '
  .["x-runtipi"].schema_version == 2 and
  (.services | keys) == ["db", "fidelity", "worker"] and
  .services.fidelity["x-runtipi"] == {is_main: true, internal_port: 3001} and
  .services.db.image == $source[0].services.db.image and
  .services.db.environment == $source[0].services.db.environment and
  .services.fidelity.environment == $source[0].services.app.environment and
  .services.worker.image == $source[0].services.worker.image and
  .services.fidelity.image == $source[0].services.app.image and
  .services.fidelity.volumes == ["${APP_DATA_DIR}/persist:/data:ro", "${APP_DATA_DIR}/config:/config:rw"] and
  .services.db.volumes[0] == {type: "bind", source: "${APP_DATA_DIR}/persist", target: "/var/lib/postgresql/data", read_only: true} and
  .services.fidelity.ports == ["9199:3101/udp"] and
  .services.worker.depends_on == ["fidelity"] and
  .services.worker.environment.APP_URL == "http://fidelity"
' "$TMP/generated.json" > /dev/null
for pair in app:fidelity db:db worker:worker; do
  jq -e --arg old "${pair%%:*}" --arg new "${pair#*:}" --slurpfile source "$TMP/source.json" '
    .services[$new] as $generated |
    ["container_name", "volumes", "ports", "depends_on", "environment", "x-runtipi"] as $transformed |
    all($source[0].services[$old] | keys[]; . as $key |
      ($transformed | index($key)) != null or $generated[$key] == $source[0].services[$old][$key])
  ' "$TMP/generated.json" > /dev/null
done
jq -e '.min_tipi_version == "4.7.0" and .tipi_version == 2' "$OUT/config.json" > /dev/null
echo "ok: native Runtipi Compose preserves all service fields and sidecars"

yq -i '.services.app.ports = ["9199:3101/udp", {"target": 8080, "published": "9099", "protocol": "tcp"}]' "$TMP/apps/fidelity/docker-compose.yml"
bash "$REPO/scripts/convert-to-platforms.sh" -p runtipi -a fidelity -i "$TMP/apps" -o "$TMP/out" > "$TMP/run.log" 2>&1
yq -o=json '.' "$OUT/docker-compose.yml" | jq -e '
  .services.fidelity["x-runtipi"].internal_port == 8080 and
  .services.fidelity.ports == ["9199:3101/udp"]
' > /dev/null
echo "ok: long-form TCP routing keeps the preceding UDP port"

mkdir -p "$TMP/workspace/big-bear-runtipi/apps/fidelity" "$TMP/workspace/big-bear-runtipi/apps/unrelated"
printf '{}' > "$TMP/workspace/big-bear-runtipi/apps/fidelity/docker-compose.json"
printf 'keep' > "$TMP/workspace/big-bear-runtipi/apps/unrelated/keep.txt"
bash "$REPO/scripts/sync-to-platforms.sh" -p runtipi -a fidelity -c "$TMP/out" -w "$TMP/workspace" --force > "$TMP/sync.log" 2>&1
test ! -f "$TMP/workspace/big-bear-runtipi/apps/fidelity/docker-compose.json"
cmp "$OUT/docker-compose.yml" "$TMP/workspace/big-bear-runtipi/apps/fidelity/docker-compose.yml"
test "$(cat "$TMP/workspace/big-bear-runtipi/apps/unrelated/keep.txt")" = "keep"
echo "ok: targeted platform sync removes legacy JSON and keeps unrelated apps"
