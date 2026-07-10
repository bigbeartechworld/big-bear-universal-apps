# SnapOtter

Self-hosted file toolkit with 200+ tools across images, video, audio, PDFs, and files.

## Access

- Web UI and API: `http://<server>:1349`
- Default username: `admin`
- Default password: `admin`

SnapOtter asks you to change the default password after first login.

## Runtime

This package uses SnapOtter's single-container embedded mode. Leave `DATABASE_URL` and `REDIS_URL` unset so the container starts its embedded PostgreSQL 17 and Redis 8 services.

For larger or production deployments, use the upstream multi-container Compose stack with external PostgreSQL and Redis.

## Volumes

| Volume | Container path | Purpose |
| --- | --- | --- |
| `snapotter_data` | `/data` | User files, AI models, logs, embedded PostgreSQL, and embedded Redis. |
| `snapotter_workspace` | `/tmp/workspace` | Temporary processing workspace. |

Back up `snapotter_data` before upgrades. The workspace volume is temporary and can be recreated.

## Links

- Website: https://snapotter.com
- Documentation: https://docs.snapotter.com/guide/getting-started
- Source: https://github.com/snapotter-hq/SnapOtter
- Support: https://discord.gg/hr3s7HPUsr
