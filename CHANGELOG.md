# Changelog

All notable changes to Big Bear Universal Apps are documented here.
Format: [CalVer](https://calver.org/) — `YYYY.MM.N` (N = release number within the month)

## [2026.04.1]

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

### Updated (via squash merge)
- `apps/zotero/` — v7 → v9 (linuxserver/zotero:9.0.20260410)
- `apps/firefox/` — v1148.0.2 → v1149.0.2 (linuxserver/firefox:1149.0.2)
- `apps/homer/` — v25.11.1 → v26.4.1 (b4bz/homer:v26.4.1)
- `apps/authentik/` — v2025.12.4 → v2026.2.2 (ghcr.io/goauthentik/server:2026.2.2)
