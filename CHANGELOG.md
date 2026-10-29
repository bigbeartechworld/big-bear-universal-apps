# Changelog

All notable changes to Big Bear Universal Apps are documented here.
Format: [CalVer](https://calver.org/) — `YYYY.MM.N` (N = release number within the month)

## [2026.10.5]

### Added
- `apps/n8n-v3/` provides n8n 3.0.1 on host port 5679 with separate PostgreSQL and application volumes. v3 removes legacy nodes and expression helpers, changes security defaults, and renames binary data storage. Review Settings > Migration Report on v2 and migrate tested copies or exported workflows and credentials. Migration: https://docs.n8n.io/changelog/v30-breaking-changes
- `apps/stalwart-mail-v1/` provides Stalwart 1.0.1 with persistent `/etc/stalwart` and `/var/lib/stalwart` volumes. Setup is loopback-only on port 8081; after setup and restart, use HTTPS on port 443. Standard mail ports require stopping the legacy server on the same host. Runtipi, Umbrel and Cosmos are unsupported because their proxies cannot preserve the private bootstrap listener. Migration from 0.16.27 requires `stalwart-migrate` into a new store: https://stalw.art/docs/migration/upgrade-0-16/
- `apps/portainer-agent-v3/` provides Agent 3.0.0 on host port 9002 for a matching Portainer Server v3. Upgrade both ends together and preserve any server `AGENT_SECRET`. Upgrade guide: https://docs.portainer.io/start/upgrade

### Changed
- Renamed n8n, Stalwart Mail and Portainer Agent to "(Legacy)" and disabled Renovate only for their legacy Compose files, preserving updates for the new entries. Replaces image-only upgrades #4811, #4769 and #4877.

### Updated
- OneDev 16.9.8 to 17.0.0 (#4844). No new incompatibilities are listed after 16.9.0. Same PostgreSQL dependency, environment, volumes and ports. Back up data before the normal container upgrade.
- 2FAuth 8.0.3 to 9.0.0 (#4790). New UI and import features with the existing deployment contract.
- Opera 138.0.6044 to 139.0.6053 (#4768), Ungoogled Chromium 155.0.8059 to 156.0.8078 (#4621), Edge 155.0.4283 to 156.0.4314 (#4591), and Firefox 1155.0.1 to 1158.0.1 (#4532). Browser image tags only; existing ports, environment and `/config` storage remain the same.

## [2026.10.4]

### Added
- `apps/seafile-v14/` — Seafile 14.0.9 on host port 8146. 12 and 13 replaced the 11.x setup variables with `SEAFILE_MYSQL_DB_*`, `INIT_SEAFILE_*` and a mandatory `JWT_PRIVATE_KEY`, made Redis the default cache, and the database upgrade cannot be undone. Majors must be upgraded one at a time (11 → 12 → 13 → 14). SeaDoc, the notification server and Seafile AI are off. Not offered on Runtipi or Umbrel, which cannot set `SEAFILE_SERVER_HOSTNAME`. Do not attach the 11.0.13 volumes. Migration: https://manual.seafile.com/latest/upgrade/upgrade_docker/

### Changed
- `apps/seafile/` — renamed to "Seafile (Legacy)" and pinned in `renovate.json` at 11.0.13. Closed #4132.

### Updated
- `apps/ffmpeg/` — 8.1.2 → 9.0.2 (#4150). Tag bump only. FFmpeg 9 verifies TLS certificates by default, so commands that read from self-signed or expired HTTPS sources need `-tls_verify 0` or `-ca_file`.

## [2026.10.3]

### Added
- `apps/filebrowser-quantum-v2/` — FileBrowser Quantum 2.0.0-stable on host port 8701. v2 replaces BoltDB with SQLite and refuses to start while `database.db` is still in the data directory. A fresh install prints a one-time admin password in the logs. Do not attach the 1.5.8 data volume. Migration: https://filebrowserquantum.com/en/docs/getting-started/v2/migration/

### Changed
- `apps/filebrowser-quantum/` — renamed to "FileBrowser Quantum (Legacy)" and pinned in `renovate.json` at 1.5.8-stable. Closed #3996.

### Updated
- `apps/skysend/` — v2.12.2 → v3.0.1 (#4115). Same port 23001 and `/data` plus `/uploads` volumes. The catalog does not set `DEFAULT_THEME`. An install that still sets it to `dark`, `light`, or `system` will refuse to start until that value moves to `DEFAULT_COLOR_SCHEME`. Update the SkySend CLI with the server.
- `apps/ungoogled-chromium/` — 154.0.8037 → 155.0.8059 (#4034). Browser tag only. Same ports 3000 and 3001, environment, and `/config` volume.
- `apps/msedge/` — 154.0.4258 → 155.0.4283 (#3972). Browser tag only. Same ports 3000 and 3001, environment, and `/config` volume.

## [2026.10.2]

### Fixed
- `apps/homarr-v2/` — ship `SECRET_ENCRYPTION_KEY`, `DB_DIALECT=sqlite`, and `DB_URL=/appdata/db/db.sqlite` as Compose literals. CasaOS writes the install form onto those lines and does not substitute `${SECRET_ENCRYPTION_KEY}`. ZimaOS turned `${DB_DIALECT:-sqlite}` into an empty value, and Homarr then failed startup looking for `/app/db/migrations/migrate.cjs`. Portainer no longer lists those names as stack variables, because the Compose file does not interpolate them.

### Added
- `apps/reactive-resume-v6/` — Reactive Resume v6.0.0 on host port 3028, with PostgreSQL 18 and uploads at `/app/data`. v6 drops MinIO, Redis, and Browserless. The v5 database migration is one-way, and PostgreSQL 18 cannot open the v5 data directory.

### Changed
- `apps/reactive-resume/` — renamed to "Reactive Resume (Legacy)" and pinned in `renovate.json` at v5.3.2.

### Updated
- `apps/librewolf/` — 156.0.1 → 157.0.1 (#3950). Browser tag only. Same ports, environment, and `/config` volume.
- `apps/cantinarr/` — 0.16.0 → 1.0.0 (#3949). Upstream 0.17.0 through 1.0.0 require no service configuration changes. Same port 8585 and `/config` volume.

## [2026.10.1]

### Added
- `apps/odoo-v20/` — Odoo 20 paired with PostgreSQL 16, on host port 8070. Odoo 20 raises the database minimum from PostgreSQL 13 to 16, and a major upgrade is not an image swap.
- `apps/homarr-v2/` — Homarr 2.0.0 on host port 7576. The default SQLite database moves by copying `/appdata` and setting the same `SECRET_ENCRYPTION_KEY`. An external PostgreSQL database stays where it is. Stop v1, back up that database, then set `DB_DIALECT` and `DB_URL` and leave v1 stopped while v2 migrates it. MySQL must be converted to SQLite first.

### Changed
- `apps/odoo/` — renamed to "Odoo (Legacy)" and pinned in `renovate.json` at Odoo 19 with PostgreSQL 15.
- `apps/homarr-v1/` — restored to v1.63.0, renamed to "Homarr v1 (Legacy)", and pinned in `renovate.json`. The v2 image from #3769 now lives in `homarr-v2` so the v1 app id does not change major versions.

### Updated
- `apps/drawio/` — 31.5.3 → 32.0.1 (#3776)
- `apps/ungoogled-chromium/` — 153.0.8010 → 154.0.8037 (#3772)
- `apps/apprise-api/` — 1.5.4 → 2.0.0 (#3771). Password protection stays off unless `APPRISE_AUTH_REQUIRED=yes`.
- `apps/gitea/` — 1.27.3 → 28.0.0 (#3770). The 1.x prefix is gone. Review egress allow and block lists before upgrading; new installs have self-registration off; Actions runs expire after 400 days unless `RUN_RETENTION_DAYS` is changed.
- `apps/umbrel-os/` — 1.7.4 → 2.0.0 (#3768). Same `/data` volume. The first start rewrites app configs, so going back to 1.x needs a backup.
- `apps/msedge/` — 153.0.4234 → 154.0.4258 (#3579)
- `apps/stirling-pdf/` — 2.14.3 → 3.0.2 (#3543)
- `apps/librewolf/` — 155.0.1 → 156.0.1 (#3541)
- `apps/azahar/` — 12125.1.3 → 12126.1.2 (#3540)
- `apps/bookorbit/` — 2.7.0 → 3.2.0 (#3539). Database migrations run on startup.
- `apps/nextcloud/` and `apps/nextcloud-with-smbclient/` — 34.0.3 → 35.0.1 (#3538). PostgreSQL 14 remains supported.

## [2026.07.1]

### Added
- `apps/wordpress-v7/` — new WordPress 7.0.1 app paired with MySQL 8.0. WordPress 7 raises the minimum database to MySQL 8.0, which the legacy app's bundled MySQL 5.7 cannot satisfy.

### Changed
- `apps/wordpress/` — renamed to "WordPress (Legacy)", reverted to `wordpress:6.9.4` (still paired with MySQL 5.7), and pinned in `renovate.json` so it no longer auto-updates.

## [2026.06.3]

### Updated
- `apps/nexterm/` — v1.0.9-OPEN-PREVIEW → v1.2.1-BETA. Docker image moved from `germannewsmaker/nexterm` to `nexterm/aio` per upstream release.

## [2026.06.2]

### Added
- `apps/celestory/` — Celestory & Voltask (10-service stack: gateway, frontend, hub, api, generator, auth, voltask, plugins-bun, plugins-deno, orchestrator + Postgres). Port 1500 via gateway.

## [2026.06.1]

### Added
- `apps/discopanel/` — DiscoPanel v2.0.12 (nickheyer/discopanel:v2.0.12). Game server panel for Minecraft that manages servers as Docker containers and installs modpacks. Mounts the Docker socket and runs with host networking to expose dynamic server ports (25565+). Port 8080.

## [2026.06.0]

### Added
- `apps/odysseus/` — Odysseus (bigbeartechworld/big-bear-odysseus:2026.06.02). Self-hosted AI workspace bundling chat, SearXNG web search, and a ChromaDB vector store. Ships four services (odysseus, chromadb, searxng, ntfy) with SearXNG settings seeded into a named volume. Port 7000. Not fully tested.

## [2026.05.6]

### Added
- `apps/rackpeek/` — RackPeek v1.4.0 (aptacode/rackpeek:v1.4.0). Webui and CLI tool to discover, manage, and document home lab and small-scale IT infrastructure using open YAML. Port 8095.

## [2026.05.5]

### Added
- `apps/nova-dso-tracker/` — Nova DSO Tracker (mrantonsg/nova-dso-tracker). Astrophotography Deep Space Object tracker and imaging session planner. Port 5001. Community verified on CasaOS by j900.

## [2026.05.4]

### Added
- `apps/dashy-v4/` — Dashy v4.0.8 (lissy93/dashy:4.0.8). Breaking changes: config path moved from `/app/public` to `/app/user-data`, healthcheck requires `.js` extension, runs as non-root uid 1000. Port 4001 to coexist with legacy app.

### Changed
- `apps/dashy/app.json` — Renamed to "Dashy (Legacy)". Pinned at v3.3.1. Use `dashy-v4` for v4+.
- `renovate.json` — Added `enabled: false` rule scoped via `matchFileNames` for legacy dashy docker-compose.

## [2026.05.3]

### Updated
- `apps/onedev/` — v14.1.9 → v15.0.7 (1dev/server:15.0.7)

## [2026.05.2]

### Updated
- `apps/ghostfolio/` — v2.255.0 → v3.2.0 (ghostfolio/ghostfolio:3.2.0)

  **⚠️ Breaking change (v3.0.0):** `sslmode=prefer` removed from `DATABASE_URL`. If you have a custom `DATABASE_URL` env var with `?sslmode=prefer`, remove that parameter before upgrading. The default compose file has been updated automatically.

## [2026.05.1]

### Changed
- `renovate.json` — Added `minimumReleaseAge: "3 days"` to patch and minor automerge rule. Docker image updates now wait 3 days after release before auto-merging, reducing supply chain attack exposure.

## [2026.05.0]

### Added
- `apps/gitea/` — Gitea v1.26.1. Self-hosted Git service with SSH (port 2222), web UI (port 3000), and platform compatibility for CasaOS, Portainer, RunTipi, Dockge, Cosmos, and Umbrel.

## [2026.04.1]

[Blog post](https://community.bigbeartechworld.com/t/2026-04-1-major-version-app-updates-in-big-bear-universal-apps/5262?u=dragonfire1119)

### Added
- `apps/vikunja-v2/` — Vikunja v2.3.0. Major rewrite with rebuilt session-based authentication, changed API routes, and Typesense removed. Uses MariaDB 11, port 8082.
- `apps/farmos-v4/` — FarmOS v4.0.0. Requires PHP 8.4 (Drupal 11) and MariaDB 10.6+. Uses port 8081 to coexist with legacy app.
- `apps/passwordpusher-v2/` — Password Pusher v2.2.2. MySQL/MariaDB dropped; now uses PostgreSQL 16. Uses port 5101 to coexist with legacy app.

### Changed
- `apps/rocket-chat/app.json` — Renamed to "Rocket.Chat (Legacy)". Pinned at v6.13.1. Use `rocket-chat-v8` for v8+.
- `apps/planka/app.json` — Already "Planka (Legacy)". Pinned at v1.26.3. Use `planka-v2` for v2+.
- `apps/vikunja/app.json` — Renamed to "Vikunja (Legacy)". Pinned at v1.1.0. Use `vikunja-v2` for v2+.
- `apps/farmos/app.json` — Renamed to "FarmOS (Legacy)". Pinned at v3.5.1. Use `farmos-v4` for v4+.
- `apps/passwordpusher/app.json` — Renamed to "Password Pusher (Legacy)". Pinned at v1.69.3. Use `passwordpusher-v2` for v2+.
- `renovate.json` — Added `enabled: false` rules scoped via `matchFileNames` for all legacy app docker-compose files. New versioned app directories continue to receive Renovate updates.

### Updated
- `apps/zotero/` — v7 → v9 (linuxserver/zotero:9.0.20260410)
- `apps/firefox/` — v1148.0.2 → v1149.0.2 (linuxserver/firefox:1149.0.2)
- `apps/homer/` — v25.11.1 → v26.4.1 (b4bz/homer:v26.4.1)
- `apps/authentik/` — v2025.12.4 → v2026.2.2 (ghcr.io/goauthentik/server:2026.2.2)
