# Paperclip

Open-source self-hosted board for managing AI coding agents — Claude Code, Codex, OpenCode, and Gemini CLI. Assign work to agents, run them, and track cost and output from a single dashboard.

## Access

- Web interface: `http://<server>:3101`
- Health endpoint: `http://<server>:3101/api/health`

The container listens on `3100` and is published on host port `3101`, because `3100` is already used by another app in this catalog.

Some platforms publish it elsewhere: Umbrel serves Paperclip on `10201`, and Runtipi uses whatever `APP_PORT` is set to. Check the port your platform shows before setting `PAPERCLIP_PUBLIC_URL` below.

## Set PAPERCLIP_PUBLIC_URL first

Paperclip builds its sign-in callback URLs from `PAPERCLIP_PUBLIC_URL`. It ships as `http://localhost:3101`, which works only when browsing from the server itself. From any other device, sign-in fails on the callback until this matches the address you actually browse to.

Do not use the `[YOUR_CASAOS_IP]` placeholder style here. Paperclip parses this value as a URL at startup and refuses to boot on an unparseable one, so it must always be a real address.

Edit the `paperclip` service in `docker-compose.yml` and set both the host **and** the port to what you actually browse to, then restart. The port is not always `3101` — see Access above:

```yaml
PAPERCLIP_PUBLIC_URL: http://192.168.1.50:3101
```

On Umbrel that line is `http://192.168.1.50:10201` instead.

```bash
docker compose -f docker-compose.yml up -d
```

Behind a reverse proxy serving HTTPS, use the external hostname and scheme users actually connect on:

```yaml
PAPERCLIP_PUBLIC_URL: https://paperclip.example.com
```

On a plain LAN address without a proxy, traffic is unencrypted. Put Paperclip behind a TLS proxy before exposing it outside a trusted network.

## Secrets

This app ships with fixed placeholder secrets so it starts with no configuration. **They are published in a public repository. Rotate them before real use.**

In `docker-compose.yml`, replace both of:

- `8426a45b83c80f6465cf48145bb80108288fd6b5d835e5a8e0e0034d7d500bf4` — `BETTER_AUTH_SECRET`
- `4574e70d6763a4ebd9e08f6a2ef516780a70cf2d73876b99330648c95bab198c` — `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET`

Generate each replacement with:

```bash
openssl rand -hex 32
```

`BETTER_AUTH_SECRET` signs session cookies. Paperclip refuses to start if it is unset. Changing it after accounts exist invalidates every active session — users sign in again, no data is lost.

`PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` signs agent tool-action approvals. The server boots without it, but every agent approval then fails with a signing-secret error. There is no fallback.

Rotate both **before first start** if you can, and keep them stable afterwards. Back them up alongside the data volume.

## API keys

Agents need provider credentials. Paperclip itself runs without them; the agents do not. Set whichever you use on the `paperclip` service:

```yaml
ANTHROPIC_API_KEY: sk-ant-...
OPENAI_API_KEY: sk-...
GEMINI_API_KEY: ...
GITHUB_TOKEN: ghp_...
```

`GITHUB_TOKEN` is what agents use to read and write repositories.

## Database

Paperclip starts and manages an **embedded PostgreSQL** inside the container, stored under `/paperclip`, and runs its migrations automatically on first start. There is no separate database container to configure.

This happens because `DATABASE_URL` is deliberately not set. Setting it switches Paperclip to an external PostgreSQL server and the embedded one is no longer used — do not set it unless that is what you want.

Upstream `doc/DOCKER.md` describes the embedded database as SQLite. That is an upstream documentation error; the same document's body and `doc/DATABASE.md` both say PostgreSQL.

First start takes noticeably longer than later ones while the database is initialised and migrated. The healthcheck allows for this.

## Volumes

| Volume | Container path | Purpose |
|---|---|---|
| `paperclip_data` | `/paperclip` | Application data and the embedded PostgreSQL cluster. |

Back this volume up together with the two secrets above. Without `BETTER_AUTH_SECRET` the restored data is still readable, but every session is invalidated.

## Notes

The image entrypoint starts as `root` so it can `usermod` and `chown` the data directory to match the volume's ownership, then drops to the unprivileged `node` user via `gosu` before running the server. If the container is forced to run non-root, the entrypoint skips the ownership fix and continues; ensure the volume is already writable by the running user in that case.

No Docker socket is mounted and no extra capabilities are granted. Agents run in-process using CLIs baked into the image rather than by spawning sibling containers.

The image is pinned by digest to `ghcr.io/paperclipai/paperclip:latest@sha256:66056e8c...`. Upstream publishes no versioned *image* tag — GHCR carries only rolling tags (`latest`, `beta`, `canary`, `nightly`) and per-commit `sha-*` tags — so the digest pin is what keeps this deployment reproducible; Renovate is opted out of bumping it.

## Links

- Homepage: https://paperclip.ing
- Source: https://github.com/paperclipai/paperclip
- Docker docs: https://github.com/paperclipai/paperclip/blob/master/doc/DOCKER.md
- Support: https://community.bigbeartechworld.com/
