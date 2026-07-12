# Changelog

All notable changes to Big Bear Universal Apps are documented here.
Format: [CalVer](https://calver.org/) — `YYYY.MM.N` (N = release number within the month)

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
