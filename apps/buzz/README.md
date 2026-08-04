# Buzz

Self-hostable workspace for humans and agents from Block, built on the Nostr protocol.

## Access

- Web interface: `http://<server>:3000`
- Nostr relay (WebSocket): `ws://<server>:3000`
- REST API: `http://<server>:3000`

A single process serves all three. Health and metrics listen on ports 8080 and 9102 inside the container and are intentionally not published.

## Set RELAY_URL first

Buzz serves the web interface only for the exact address set in `RELAY_URL`. The default is `ws://localhost:3000`, which works when browsing from the server itself. Opening the app from any other device returns:

```text
relay: no community is configured for this host
```

To fix it, edit the `relay` service in `docker-compose.yml` and replace `localhost` in **both** of these with the address you browse to, then restart the relay:

```yaml
RELAY_URL: ws://192.168.1.50:3000
BUZZ_MEDIA_BASE_URL: http://192.168.1.50:3000/media
```

Change them together. `BUZZ_MEDIA_BASE_URL` is not derived from `RELAY_URL`, and it is written into the URL of every uploaded file. Leaving it on `localhost` publishes media links that only work on the server, and links already published cannot be corrected by changing it later.

Use the same value for Nostr clients: `ws://192.168.1.50:3000`.

Behind a reverse proxy serving HTTPS, use the secure schemes instead, matching the hostname and port users connect on:

```yaml
RELAY_URL: wss://buzz.example.com
BUZZ_MEDIA_BASE_URL: https://buzz.example.com/media
```

A page served over HTTPS cannot open a plaintext `ws://` connection, so `wss://` is required there rather than optional. On a plain LAN address without a proxy, traffic is unencrypted; put the relay behind a TLS proxy before exposing it outside a trusted network.

## Secrets

This app ships with fixed placeholder secrets so it starts with no configuration. **They are published in a public repository. Rotate them before real use.** In `docker-compose.yml`, replace every occurrence of:

- `7c0d0f000f4cdafc380ab93c413d97deceff42e273c97200d3fb35ad74e29231` - relay signing key
- `change-me-pg-7Kd2mQ9xR4vT` - PostgreSQL password (`relay` and `postgres`)
- `change-me-redis-3Fn8pL5wZ6yB` - Redis password (`relay` and `redis`)
- `change-me-s3-access-J4hN7qX2` - MinIO access key (`relay`, `minio`, `minio-init`)
- `change-me-s3-secret-W9cR3tY6uM8k` - MinIO secret key (`relay`, `minio`, `minio-init`)

Generate a new relay key with:

```bash
docker exec buzz-relay buzz-admin generate-key
```

Use the printed secret key as `BUZZ_RELAY_PRIVATE_KEY`. Keep it stable across restarts and back it up; changing it changes the relay's identity.

Rotate the database, Redis, and MinIO secrets **before first start**. PostgreSQL and MinIO read their credentials only when their volume is first initialised, so editing the compose file later leaves the relay presenting a password the server never accepted and it restarts in a loop. Redis is the exception and picks up the new value on restart.

To change the database password after data exists, update it in PostgreSQL first, then edit `DATABASE_URL` to match:

```bash
docker exec -it buzz-postgres psql -U buzz -c "ALTER USER buzz WITH PASSWORD 'new-password';"
```

Changing the MinIO root credentials after first start means recreating the `buzz_minio_data` volume, which deletes stored media.

## Closed relay mode

By default the relay is open: any client with its own Nostr keypair can connect. To restrict it to approved members, set both of these on the `relay` service and restart:

```yaml
BUZZ_REQUIRE_RELAY_MEMBERSHIP: "true"
RELAY_OWNER_PUBKEY: <your 64-character hex pubkey>
```

The relay will not start with membership enabled unless `RELAY_OWNER_PUBKEY` is a valid 64-character hex key. Manage members with:

```bash
docker exec buzz-relay buzz-admin add-member --pubkey <npub-or-hex>
docker exec buzz-relay buzz-admin list-members
docker exec buzz-relay buzz-admin remove-member --pubkey <npub-or-hex>
```

When adding several members, wait a second between commands to avoid timestamp collisions in the roster event.

## Architecture

| Service | Purpose |
|---|---|
| `relay` | Nostr relay, REST API, git storage, and web interface on port 3000. |
| `postgres` | Application database. |
| `redis` | Pub/sub and cache. |
| `minio` | S3-compatible object storage for media and git objects. |
| `minio-init` | One-shot job that creates the storage bucket. |

## Volumes

| Volume | Container path | Purpose |
|---|---|---|
| `buzz_postgres_data` | `/var/lib/postgresql/data` | PostgreSQL database. |
| `buzz_redis_data` | `/data` | Redis append-only file. |
| `buzz_minio_data` | `/data` | Media and git objects. |
| `buzz_git_data` | `/data/git` | Git repository data. |

Back up `buzz_postgres_data` together with `buzz_minio_data` and `buzz_git_data` from the same maintenance window, plus the secrets listed above.

## Notes

The relay verifies at every start that its object storage supports atomic conditional writes, which adds a short delay before it becomes healthy. If MinIO is misconfigured the relay refuses to start rather than risk corrupting git data.

## Links

- Guide: https://engineering.block.xyz/blog/run-your-own-buzz-relay
- Source: https://github.com/block/buzz
- Support: https://community.bigbeartechworld.com/
