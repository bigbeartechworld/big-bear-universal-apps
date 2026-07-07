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

- `museum` service: `ENTE_S3_B2_EU_CEN_ENDPOINT` -> `<LAN-IP>:3200`
- `museum` service: `ENTE_APPS_PUBLIC_ALBUMS` -> `http://<LAN-IP>:3002`
- `web` service: `ENTE_API_ORIGIN` -> `http://<LAN-IP>:8080`

Because the web UI and object storage sit on different ports, browsers treat cross-port requests as cross-origin. For production use, front all services with a reverse proxy on a single domain, or configure MinIO CORS for your IP. See the [Ente reverse-proxy guide](https://help.ente.io/self-hosting/).

## Supported platforms

This app works on CasaOS, Portainer, and Dockge, which publish all container ports to the host directly. It is not supported on Umbrel, Cosmos, or Runtipi: those route a single port through a proxy, but Ente's browser client must reach the museum API (8080) and MinIO (3200) directly.

## Secrets

This app ships with fixed placeholder secrets so it boots out of the box. **Rotate them before real use.** In `docker-compose.yml`, change every occurrence of:

- `change-me-qE7Yb2sN4wR9tK1` (database password - appears in `museum` and `postgres`)
- `change-me-minio-vH3pL8xC0zN5` (MinIO secret - appears in `museum`, `minio`, `minio-init`)
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
