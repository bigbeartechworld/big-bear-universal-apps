# Ente Photos — Universal App Design

Issue: [#2416](https://github.com/bigbeartechworld/big-bear-universal-apps/issues/2416)
Branch: `feat/add-ente-photos`

## Goal

Add Ente Photos, a self-hosted end-to-end-encrypted photo storage service, to the Big Bear Universal Apps catalog as a new app (`apps/ente/`) consisting of `app.json` + `docker-compose.yml` + `README.md`, passing `scripts/validate-apps.sh` and the CI version-mismatch check.

## Background

Ente self-hosting requires five cooperating containers:

| Service   | Image                      | Purpose                                                        |
|-----------|----------------------------|---------------------------------------------------------------|
| `museum`  | `ghcr.io/ente/server`      | API server (port 8080). Reads config from env vars.           |
| `web`     | `ghcr.io/ente/web`         | Photos web UI (port 3000) + public albums (3002).             |
| `postgres`| `postgres:15`              | Application database.                                          |
| `minio`   | `minio/minio`              | S3-compatible object storage (port 3200).                     |
| `socat`   | `alpine/socat`             | TCP bridge so `museum` resolves `localhost:3200` → `minio:3200`. |
| `minio-init` | `minio/mc`              | One-shot job: creates the three S3 buckets, then exits.       |

The museum server accepts **all** configuration via environment variables using the `ENTE_` prefix with underscores replacing nesting and hyphens (e.g. `db.user` → `ENTE_DB_USER`, `s3.b2-eu-cen.key` → `ENTE_S3_B2_EU_CEN_KEY`). This lets us avoid the separate `museum.yaml` file that the official quickstart generates — the catalog format supports only `app.json` + `docker-compose.yml`, so a mounted config file is not an option.

## Design Decisions

### 1. Configuration via environment variables (no museum.yaml)

All museum config is inlined as `ENTE_*` environment variables in the compose file. This keeps the app within the catalog's two-file format. Required config surface:

- **DB:** `ENTE_DB_HOST=postgres`, `ENTE_DB_PORT=5432`, `ENTE_DB_NAME=ente_db`, `ENTE_DB_USER`, `ENTE_DB_PASSWORD`, `ENTE_DB_SSLMODE=disable`.
- **S3/MinIO** (bucket key `b2-eu-cen`, the default hot storage): `ENTE_S3_B2_EU_CEN_KEY`, `ENTE_S3_B2_EU_CEN_SECRET`, `ENTE_S3_B2_EU_CEN_ENDPOINT=localhost:3200`, `ENTE_S3_B2_EU_CEN_REGION=eu-central-2`, `ENTE_S3_B2_EU_CEN_BUCKET=b2-eu-cen`, plus the local-minio workarounds `ENTE_S3_ARE_LOCAL_BUCKETS=true` and `ENTE_S3_USE_PATH_STYLE_URLS=true`.
- **Secrets:** `ENTE_KEY_ENCRYPTION`, `ENTE_KEY_HASH`, `ENTE_JWT_SECRET`.
- **App endpoints:** `ENTE_APPS_PUBLIC_ALBUMS=http://localhost:3002`.

The `socat` bridge listens on port 3200 inside museum's network namespace and forwards to `minio:3200`, so museum's `localhost:3200` endpoint resolves. This mirrors Ente's official quickstart compose exactly.

### 2. Committed secret defaults (not blank)

`ENTE_KEY_ENCRYPTION`, `ENTE_KEY_HASH`, `ENTE_JWT_SECRET`, `ENTE_DB_PASSWORD`, and the MinIO root credentials ship with fixed committed random values (base64, generated once for this app), **not** blank and not `${VAR:-}`. Rationale: consistent with the repo's committed-password-defaults convention — CasaOS/Portainer render these as real editable fields, and the app boots working out of the box. The README instructs users to rotate them for real use.

### 3. LAN-IP caveat documented, not automated

MinIO presigned URLs and the web API origin embed `localhost`, which works on the host but **not** from other devices on the LAN. A static compose cannot know the server's LAN IP. Following the same convention as `immich` and other catalog apps, the app ships with working `localhost` defaults and the README documents the single edit needed for multi-device access: replace `localhost` with the server's LAN IP in `ENTE_S3_B2_EU_CEN_ENDPOINT`, `ENTE_APPS_PUBLIC_ALBUMS`, the web `ENTE_API_ORIGIN`, and MinIO CORS. No `${SERVER_IP}` env with a broken blank default; no bundled reverse proxy (out of scope, diverges from the single-purpose compose pattern).

### 4. MinIO bucket bootstrap

MinIO's three buckets (`b2-eu-cen`, `wasabi-eu-central-2-v3`, `scw-eu-fr-v3`) are created by a dedicated one-shot `minio-init` service running `minio/mc`. It waits for minio to be reachable, sets a `mc` alias with the root credentials, runs `mc mb --ignore-existing` for each bucket, then exits `0`. This is chosen over minio's `post_start` lifecycle hook (requires compose spec ≥ 2.30 and is stripped by some platform converters) and over `MINIO_DEFAULT_BUCKETS` (unused by any existing catalog app, no confirmed support in the pinned image). The init service uses `depends_on: minio` and does not carry a `restart` policy (it must run once and stay exited). Only `b2-eu-cen` is functionally required (replication is off by default); all three are created to match Ente's expectations and avoid museum startup warnings.

### 5. Web frontend

The `web` service exposes port 3000 (Photos) and 3002 (public albums), with `ENTE_API_ORIGIN=http://localhost:8080` pointing at museum. Additional web sub-apps (accounts 3001, cast 3004, etc.) are **out of scope** for v1 — Photos + public albums cover the issue's request. This keeps the compose focused; the README notes how to enable others.

### 6. Image pinning

`museum` and `web` pin to `latest@sha256:<digest>` (Ente publishes no semver tags — only `latest` + SHA digests):

- `ghcr.io/ente/server:latest@sha256:c56831e83306988b2f5ee30eee20194d6b8f848a9cc4f4afa75931722ac1086b`
- `ghcr.io/ente/web:latest@sha256:3bf4390356f57400c762dbd7ed26e5af7cc7bb2add4f627ba5481c94635f1614`

The `latest` tag keeps the line human-readable; the digest pins reproducibility. The CI version-mismatch checker (`:([^:]+)$` regex) extracts the digest hex, which fails the `^(v)?\d+` semver test and is skipped as a non-semver tag — no false mismatch. `postgres:15`, `minio/minio`, and `alpine/socat` follow the catalog's existing infra-image conventions (postgres pinned to major tag, renovate-disabled for db images).

`app.json` `metadata.version` = `2026.07.07` (date stamp, since upstream has no semver).

## app.json Structure

Follows the `immich` app.json as the template (closest analog — multi-service photo app):

- `metadata`: id `ente`, name `Ente Photos`, category `BigBearCasaOS`, developer `ente-io`, homepage `https://ente.io`, description of E2E-encrypted photo storage.
- `technical`: `main_service: web`, `default_port: 3000`, `main_image: ghcr.io/ente/web`, architectures `[amd64, arm64]`.
- `deployment`: document the key env vars, volumes (postgres data, minio data), and ports (3000, 3002, 8080, 3200).
- `visual`: icon/logo from `https://cdn.jsdelivr.net/gh/selfhst/icons/png/ente.png` (verify existence during implementation; fall back to Ente's official logo URL if absent).
- `compatibility`: `casaos`, `portainer`, `dockge` supported (they publish all ports to the host directly). `runtipi`, `cosmos`, `umbrel` set `supported: false` — Ente's browser client reaches the museum API (:8080) and MinIO (:3200) as separate origins, which single-port-proxy platforms cannot serve (UI loads but login/upload fails). Same precedent as host-network apps that only ship platforms where they actually work. Volume_mappings + port overrides mirror immich.
- `resources`: documentation `https://help.ente.io/self-hosting/`, repository `https://github.com/ente-io/ente`, support community URL.

## docker-compose.yml Structure

```
name: ente
services:
  museum:      # ghcr.io/ente/server, port 8080, ENTE_* env, depends_on postgres (healthy)
  socat:       # alpine/socat, network_mode: service:museum, forwards :3200 → minio:3200
  web:         # ghcr.io/ente/web, ports 3000 + 3002, ENTE_API_ORIGIN
  postgres:    # postgres:15, healthcheck, named volume
  minio:       # minio/minio, port 3200, named volume
  minio-init:  # minio/mc, one-shot bucket creation, depends_on minio, no restart
volumes:
  ente_postgres_data
  ente_minio_data
networks:
  ente_network (bridge)
```

Restart policy `unless-stopped`, explicit `container_name`, named volumes with `ente_` prefix (matches immich convention for the platform converters' volume_mappings).

## Out of Scope

- Reverse proxy / single-origin setup.
- Web sub-apps beyond Photos + public albums (accounts, cast, auth, locker).
- Object-storage replication (off by default upstream).
- SMTP/Stripe/passkey/Discord integrations (all optional upstream, blank by default).

## Success Criteria

1. `apps/ente/{app.json,docker-compose.yml,README.md}` created.
2. `scripts/validate-apps.sh` reports `ente: PASSED` with zero failed apps (baseline was 237 passed / 0 failed; ente adds one more passing app).
3. `bun .github/scripts/check-version-mismatches.js` reports no mismatch for `ente`.
4. `docker-compose.yml` is valid YAML and parses via `docker compose config`.
5. README documents the LAN-IP edit, secret rotation, and default login flow.
6. app.json validates against `schemas/app-schema-v1.json`.
