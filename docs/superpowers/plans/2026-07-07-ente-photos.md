# Ente Photos App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Ente Photos self-hosted app to the Big Bear Universal Apps catalog as `apps/ente/{docker-compose.yml,app.json,README.md}`.

**Architecture:** A single clean `docker-compose.yml` with six services (museum API, web UI, postgres, minio, a socat bridge, a one-shot minio-init bucket creator), all museum config supplied inline as `ENTE_*` environment variables (no external `museum.yaml`). `app.json` carries catalog metadata + six-platform compatibility. `README.md` documents the LAN-IP edit and secret rotation.

**Tech Stack:** Docker Compose, JSON (app.json), Markdown, catalog validators (`scripts/validate-apps.sh`, `.github/scripts/check-version-mismatches.js`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-07-ente-photos-design.md`.
- App id: `ente`. Directory: `apps/ente/`.
- No comments in `docker-compose.yml` (repo CLAUDE.md: no comments in codebase; SCHEMA.md: clean standard compose).
- Museum image: `ghcr.io/ente/server:latest@sha256:c56831e83306988b2f5ee30eee20194d6b8f848a9cc4f4afa75931722ac1086b`.
- Web image: `ghcr.io/ente/web:latest@sha256:3bf4390356f57400c762dbd7ed26e5af7cc7bb2add4f627ba5481c94635f1614`.
- Infra images: `postgres:15`, `minio/minio`, `alpine/socat`, `minio/mc`.
- Named volumes prefixed `ente_`: `ente_postgres_data`, `ente_minio_data`.
- Network: `ente_network` (bridge).
- `app.json` `metadata.version` = `2026.07.07`; `metadata.category` = `BigBearCasaOS`; `metadata.id` = `ente`.
- Icon/logo URL: `https://cdn.jsdelivr.net/gh/selfhst/icons/png/ente-photos.png` (verified 200).
- Committed non-blank secret defaults (per repo convention): db password, minio root creds, and museum key/jwt secrets ship fixed random values, NOT blank / NOT `${VAR:-}`.
- Restart policy `unless-stopped` on long-running services; `minio-init` carries NO restart policy.
- Validation must show zero failed apps (baseline: 237 passed / 0 failed).

---

### Task 1: docker-compose.yml

**Files:**
- Create: `apps/ente/docker-compose.yml`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: service name `web` (the app.json `main_service`), main image `ghcr.io/ente/web`, ports 3000/3002/8080/3200, named volumes `ente_postgres_data` + `ente_minio_data`. Task 2's app.json references these exact names.

- [ ] **Step 1: Write the compose file**

Create `apps/ente/docker-compose.yml` with exactly this content:

```yaml
name: ente

services:
  museum:
    image: ghcr.io/ente/server:latest@sha256:c56831e83306988b2f5ee30eee20194d6b8f848a9cc4f4afa75931722ac1086b
    container_name: ente-museum
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      ENTE_DB_HOST: postgres
      ENTE_DB_PORT: "5432"
      ENTE_DB_NAME: ente_db
      ENTE_DB_USER: pguser
      ENTE_DB_PASSWORD: change-me-qE7Yb2sN4wR9tK1
      ENTE_DB_SSLMODE: disable
      ENTE_S3_ARE_LOCAL_BUCKETS: "true"
      ENTE_S3_USE_PATH_STYLE_URLS: "true"
      ENTE_S3_B2_EU_CEN_KEY: ente-minio-access
      ENTE_S3_B2_EU_CEN_SECRET: change-me-minio-vH3pL8xC0zN5
      ENTE_S3_B2_EU_CEN_ENDPOINT: localhost:3200
      ENTE_S3_B2_EU_CEN_REGION: eu-central-2
      ENTE_S3_B2_EU_CEN_BUCKET: b2-eu-cen
      ENTE_KEY_ENCRYPTION: yvmG/RnzKrbCb9L3mgsmoxXr9H7i2Z4qlbT0mL3ln4w=
      ENTE_KEY_HASH: KXYiG07wC7GIgvCSdg+WmyWdXDAn6XKYJtp/wkEU7x573+byBRAYtpTP0wwvi8i/4l37uicX1dVTUzwH3sLZyw==
      ENTE_JWT_SECRET: i2DecQmfGreG6q1vBj5tCokhlN41gcfS2cjOs9Po-u8=
      ENTE_APPS_PUBLIC_ALBUMS: http://localhost:3002
    restart: unless-stopped
    networks:
      - ente_network

  socat:
    image: alpine/socat
    container_name: ente-socat
    network_mode: service:museum
    depends_on:
      - museum
      - minio
    command: TCP-LISTEN:3200,fork,reuseaddr TCP:minio:3200
    restart: unless-stopped

  web:
    image: ghcr.io/ente/web:latest@sha256:3bf4390356f57400c762dbd7ed26e5af7cc7bb2add4f627ba5481c94635f1614
    container_name: ente-web
    ports:
      - "3000:3000"
      - "3002:3002"
    depends_on:
      - museum
    environment:
      ENTE_API_ORIGIN: http://localhost:8080
    restart: unless-stopped
    networks:
      - ente_network

  postgres:
    image: postgres:15
    container_name: ente-postgres
    environment:
      POSTGRES_USER: pguser
      POSTGRES_PASSWORD: change-me-qE7Yb2sN4wR9tK1
      POSTGRES_DB: ente_db
    volumes:
      - ente_postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U pguser -d ente_db"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 40s
    restart: unless-stopped
    networks:
      - ente_network

  minio:
    image: minio/minio
    container_name: ente-minio
    ports:
      - "3200:3200"
    environment:
      MINIO_ROOT_USER: ente-minio-access
      MINIO_ROOT_PASSWORD: change-me-minio-vH3pL8xC0zN5
    command: server /data --address ":3200" --console-address ":3201"
    volumes:
      - ente_minio_data:/data
    restart: unless-stopped
    networks:
      - ente_network

  minio-init:
    image: minio/mc
    container_name: ente-minio-init
    depends_on:
      - minio
    entrypoint: >
      /bin/sh -c "
      until mc alias set ente http://minio:3200 ente-minio-access change-me-minio-vH3pL8xC0zN5; do sleep 1; done;
      mc mb --ignore-existing ente/b2-eu-cen;
      mc mb --ignore-existing ente/wasabi-eu-central-2-v3;
      mc mb --ignore-existing ente/scw-eu-fr-v3;
      exit 0;
      "
    networks:
      - ente_network

networks:
  ente_network:
    driver: bridge

volumes:
  ente_postgres_data:
    name: ente_postgres_data
    driver: local
  ente_minio_data:
    name: ente_minio_data
    driver: local
```

- [ ] **Step 2: Verify YAML parses**

Run: `yq eval '.' apps/ente/docker-compose.yml > /dev/null && echo YAML_OK`
Expected: `YAML_OK`

- [ ] **Step 3: Verify compose is structurally valid**

Run: `docker compose -f apps/ente/docker-compose.yml config >/dev/null 2>&1 && echo COMPOSE_OK || echo COMPOSE_CHECK_SKIPPED`
Expected: `COMPOSE_OK` (if docker unavailable in the sandbox, `COMPOSE_CHECK_SKIPPED` is acceptable — the yq check in Step 2 is the hard gate).

- [ ] **Step 4: Verify no comments in the file**

Run: `grep -c '^\s*#' apps/ente/docker-compose.yml || true`
Expected: `0` (no comment lines).

- [ ] **Step 5: Commit**

```bash
git add apps/ente/docker-compose.yml
git commit -m "feat: add ente photos docker-compose (#2416)"
```

---

### Task 2: app.json

**Files:**
- Create: `apps/ente/app.json`

**Interfaces:**
- Consumes: from Task 1 — `main_service` is `web`, `main_image` is `ghcr.io/ente/web`, ports 3000/3002/8080/3200, volumes `ente_postgres_data`/`ente_minio_data`.
- Produces: a schema-valid app manifest that `scripts/validate-apps.sh -a ente` passes.

- [ ] **Step 1: Write the app.json**

Create `apps/ente/app.json` with exactly this content:

```json
{
  "spec_version": "1.0",
  "metadata": {
    "id": "ente",
    "name": "Ente Photos",
    "description": "Ente is a self-hosted, end-to-end encrypted platform to store, share, and rediscover your photos and videos across all your devices.",
    "tagline": "End-to-end encrypted photo storage",
    "version": "2026.07.07",
    "author": "BigBearTechWorld",
    "developer": "ente-io",
    "category": "BigBearCasaOS",
    "license": "AGPL-3.0",
    "homepage": "https://ente.io",
    "source": "big-bear-universal",
    "created": "2026-07-07T00:00:00Z",
    "updated": "2026-07-07T00:00:00Z"
  },
  "visual": {
    "icon": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/ente-photos.png",
    "thumbnail": "",
    "screenshots": [],
    "logo": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/ente-photos.png"
  },
  "resources": {
    "youtube": "",
    "documentation": "https://help.ente.io/self-hosting/",
    "repository": "https://github.com/ente-io/ente",
    "issues": "https://github.com/ente-io/ente/issues",
    "support": "https://community.bigbeartechworld.com/"
  },
  "technical": {
    "architectures": [
      "amd64",
      "arm64"
    ],
    "platform": "linux",
    "main_service": "web",
    "default_port": "3000",
    "main_image": "ghcr.io/ente/web",
    "compose_file": "docker-compose.yml"
  },
  "deployment": {
    "environment_variables": [
      {
        "name": "ENTE_S3_B2_EU_CEN_ENDPOINT",
        "default": "localhost:3200",
        "description": "MinIO S3 endpoint reachable by both museum and clients. Change localhost to the server LAN IP for multi-device access.",
        "required": true
      },
      {
        "name": "ENTE_API_ORIGIN",
        "default": "http://localhost:8080",
        "description": "URL of the museum API as reached by the web app. Change localhost to the server LAN IP for multi-device access.",
        "required": true
      },
      {
        "name": "ENTE_APPS_PUBLIC_ALBUMS",
        "default": "http://localhost:3002",
        "description": "Public albums URL. Change localhost to the server LAN IP for multi-device access.",
        "required": false
      },
      {
        "name": "ENTE_JWT_SECRET",
        "default": "",
        "description": "JWT signing secret. Rotate before real use.",
        "required": true
      }
    ],
    "volumes": [
      {
        "container": "/var/lib/postgresql/data",
        "description": "PostgreSQL database storage"
      },
      {
        "container": "/data",
        "description": "MinIO object storage (photos and videos)"
      }
    ],
    "ports": [
      {
        "container": "3000",
        "host": "3000",
        "protocol": "tcp",
        "description": "Photos web UI"
      },
      {
        "container": "3002",
        "host": "3002",
        "protocol": "tcp",
        "description": "Public albums"
      },
      {
        "container": "8080",
        "host": "8080",
        "protocol": "tcp",
        "description": "Museum API"
      },
      {
        "container": "3200",
        "host": "3200",
        "protocol": "tcp",
        "description": "MinIO object storage API"
      }
    ]
  },
  "ui": {
    "scheme": "http",
    "path": "",
    "tips": {}
  },
  "compatibility": {
    "casaos": {
      "supported": true,
      "port_map": "3000",
      "volume_mappings": {
        "ente_postgres_data": "/DATA/AppData/$AppID/postgres_data",
        "ente_minio_data": "/DATA/AppData/$AppID/minio_data"
      },
      "port": "3000"
    },
    "portainer": {
      "supported": true,
      "template_type": 2,
      "categories": [
        "BigBearCasaOS",
        "selfhosted"
      ],
      "administrator_only": false,
      "port": "3000"
    },
    "runtipi": {
      "supported": true,
      "tipi_version": 1,
      "supported_architectures": [
        "amd64",
        "arm64"
      ],
      "volume_mappings": {
        "ente_postgres_data": "postgres_data",
        "ente_minio_data": "minio_data"
      },
      "port": "3000"
    },
    "dockge": {
      "supported": true,
      "file_based": true,
      "port": "3000"
    },
    "cosmos": {
      "supported": true,
      "servapp": true,
      "routes_required": true,
      "port": "3000"
    },
    "umbrel": {
      "supported": true,
      "manifest_version": 1,
      "volume_mappings": {
        "ente_postgres_data": "postgres_data",
        "ente_minio_data": "minio_data"
      },
      "port": "10340"
    }
  },
  "tags": [
    "selfhosted",
    "docker",
    "bigbear",
    "bigbearcasaos",
    "photos",
    "encrypted",
    "storage"
  ]
}
```

- [ ] **Step 2: Verify JSON syntax**

Run: `jq empty apps/ente/app.json && echo JSON_OK`
Expected: `JSON_OK`

- [ ] **Step 3: Run the app validator for ente**

Run: `bash scripts/validate-apps.sh -a ente 2>&1 | tail -15`
Expected: output contains `[✓] ente: PASSED` and `Failed:   0 apps`.

- [ ] **Step 4: Run the version-mismatch checker**

Run: `bun .github/scripts/check-version-mismatches.js 2>&1 | grep -iE "ente|mismatch" | head`
Expected: no line reporting an `ente` mismatch (ente uses a digest-pinned `latest` tag, treated as non-semver and skipped).

- [ ] **Step 5: Commit**

```bash
git add apps/ente/app.json
git commit -m "feat: add ente photos app.json (#2416)"
```

---

### Task 3: README.md

**Files:**
- Create: `apps/ente/README.md`

**Interfaces:**
- Consumes: env var names + ports from Tasks 1-2.
- Produces: user-facing docs (no downstream consumer).

- [ ] **Step 1: Write the README**

Create `apps/ente/README.md` with exactly this content:

````markdown
# Ente Photos

Self-hosted, end-to-end encrypted photo and video storage.

## Access

- Photos web UI: `http://<server>:3000`
- Public albums: `http://<server>:3002`
- Museum API: `http://<server>:8080`
- MinIO object storage: `http://<server>:3200`

On first launch, create an account through the web UI. The verification code (OTP) is printed in the `ente-museum` container logs:

```bash
docker logs ente-museum 2>&1 | grep -i "verification code"
```

## Multi-device access (required for use beyond the host)

Ente stores object URLs and the API origin using `localhost`, which only resolves on the server itself. To use Ente from another device (phone, laptop), replace `localhost` with your server's LAN IP (e.g. `192.168.1.50`) in `docker-compose.yml`:

- `museum` service: `ENTE_S3_B2_EU_CEN_ENDPOINT` → `<LAN-IP>:3200`
- `museum` service: `ENTE_APPS_PUBLIC_ALBUMS` → `http://<LAN-IP>:3002`
- `web` service: `ENTE_API_ORIGIN` → `http://<LAN-IP>:8080`

Because the web UI and object storage sit on different ports, browsers treat cross-port requests as cross-origin. For production use, front all services with a reverse proxy on a single domain, or configure MinIO CORS for your IP. See the [Ente reverse-proxy guide](https://help.ente.io/self-hosting/).

## Secrets

This app ships with fixed placeholder secrets so it boots out of the box. **Rotate them before real use.** In `docker-compose.yml`, change every occurrence of:

- `change-me-qE7Yb2sN4wR9tK1` (database password — appears in `museum` and `postgres`)
- `change-me-minio-vH3pL8xC0zN5` (MinIO secret — appears in `museum`, `minio`, `minio-init`)
- `ENTE_KEY_ENCRYPTION`, `ENTE_KEY_HASH`, `ENTE_JWT_SECRET` (museum crypto keys)

Generate new museum keys with Ente's tool: `go run tools/gen-random-keys/main.go` from the [ente-io/ente](https://github.com/ente-io/ente) repo.

## Architecture

| Service      | Purpose                                             |
|--------------|-----------------------------------------------------|
| `museum`     | API server (port 8080).                             |
| `web`        | Photos web UI (3000) + public albums (3002).        |
| `postgres`   | Application database.                               |
| `minio`      | S3-compatible object storage (port 3200).           |
| `socat`      | Bridges museum's `localhost:3200` to `minio:3200`.  |
| `minio-init` | One-shot job that creates the storage buckets.      |

## Links

- Documentation: https://help.ente.io/self-hosting/
- Source: https://github.com/ente-io/ente
- Support: https://community.bigbeartechworld.com/
````

- [ ] **Step 2: Verify the file is non-empty Markdown**

Run: `test -s apps/ente/README.md && echo README_OK`
Expected: `README_OK`

- [ ] **Step 3: Run the full validator (all apps) to confirm no regressions**

Run: `bash scripts/validate-apps.sh 2>&1 | tail -8`
Expected: `Failed:   0 apps` (hard gate) and `Passed:` count = 238 (237 baseline + ente).

- [ ] **Step 4: Commit**

```bash
git add apps/ente/README.md
git commit -m "docs: add ente photos README (#2416)"
```

---

## Self-Review Notes

- **Spec coverage:** museum-via-env (§1) → Task 1 env block; committed secrets (§2) → Task 1 fixed values + Task 3 rotation docs; LAN-IP caveat (§3) → Task 3 multi-device section + Task 2 env descriptions; minio-init bucket bootstrap (§4) → Task 1 `minio-init` service; web frontend (§5) → Task 1 `web` service; image pinning (§6) → Global Constraints + Task 1 images. app.json structure → Task 2. compose structure → Task 1. Success criteria 1-6 → Task verify steps.
- **No placeholders:** all file bodies are complete literal content.
- **Type/name consistency:** `main_service: web` matches the `web` service in compose; volume names `ente_postgres_data`/`ente_minio_data` identical across compose + app.json volume_mappings; secret placeholder strings identical across the services that share them.
