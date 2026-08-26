# netboot.xyz universal app

**Issue:** [big-bear-universal-apps#2800](https://github.com/bigbeartechworld/big-bear-universal-apps/issues/2800)
**Branch:** `feat/app-request-iventoy-or-netboot-xyz`
**Date:** 2026-08-25

## Problem

Issue #2800 asks for ZimaOS/CasaOS to act as a PXE boot server via the Big Bear store, suggesting iVentoy or netboot.xyz. CasaOS can run this: the store already ships host-network apps (Homebridge, Omada) and privileged apps. This branch adds **netboot.xyz only**, as a **PXE app** (TFTP + boot menu, not a DHCP server).

netboot.xyz is an iPXE menu that boots OS installers and utilities over the network. The official container (`ghcr.io/netbootxyz/netbootxyz`) provides the web UI, TFTP, and optional local asset HTTP. It does **not** run DHCP. The LAN's existing DHCP server must point clients at this host.

iVentoy is out of scope (unofficial images, privileged + usually host network, closed source, built-in DHCP fights the LAN).

## User stories

1. **Install from the store.** A CasaOS/ZimaOS user installs netboot.xyz from the Big Bear store. **Decision:** one Universal App at `apps/netboot-xyz/` that converts to all six platforms.
2. **Open the web UI.** After install, the user opens the netboot.xyz web UI on port 3000. **Decision:** `technical.default_port` 3000, compose `3000:3000`, Umbrel `app_port` 3000.
3. **PXE-boot clients with existing DHCP.** The user points the LAN DHCP server at this host and PXE-boots clients into the netboot.xyz menu. **Decision:** publish TFTP on host UDP 69, no DHCP sidecar, document next-server and bootfile in `before_install`.

## Goals

- Add one Universal App, `apps/netboot-xyz/`, that converts to all six platforms.
- Thin wrap of the official compose: bridge network, published ports, named volumes, digest-pinned image.
- Document DHCP setup in `before_install` so a ZimaOS/CasaOS install is actually bootable, not just listed.

## Non-goals

- iVentoy
- A DHCP sidecar (dnsmasq or otherwise)
- Custom iPXE menus beyond the upstream web UI
- `network_mode: host` (CasaOS already owns host port 80)
- App-level README
- Committing `converted/` (gitignored; CI converts)
- Adding `TFTPD_OPTS` (official compose example omits it)
- Adding authentication (upstream web UI has none; this app will not add any)

## Identity

| Field | Value |
|---|---|
| `spec_version` | `1.0` |
| Directory / `metadata.id` | `netboot-xyz` |
| Display name (`metadata.name`) | netboot.xyz |
| `metadata.description` | netboot.xyz is a PXE app: an iPXE menu that boots OS installers and utilities over the network. This Universal App wraps the official container (web UI, TFTP, local asset HTTP). It does not run DHCP; point the LAN DHCP next-server and bootfile at this host. |
| `metadata.tagline` | Network boot menu (iPXE) with TFTP and a web UI |
| `metadata.author` | BigBearTechWorld |
| `metadata.developer` | netbootxyz |
| `metadata.category` | `BigBearCasaOS` (schema enum; not CasaOS store category) |
| `compatibility.casaos.category` | `Networking` |
| `metadata.license` | Apache-2.0 (upstream netboot.xyz SPDX; docker-netbootxyz has no LICENSE file) |
| `metadata.homepage` | https://netboot.xyz |
| `metadata.source` | `big-bear-universal` |
| `metadata.created` / `metadata.updated` | set at implementation (ISO-8601) |
| Architectures | amd64, arm64 |
| `technical.platform` | `linux` |
| `technical.compose_file` | `docker-compose.yml` |
| Icon and logo | `https://cdn.jsdelivr.net/gh/selfhst/icons/png/netboot-xyz.png` (HTTP 200). `visual.thumbnail` empty string. `visual.screenshots` empty array. |
| Documentation | https://netboot.xyz/docs/docker/ |
| Repository | https://github.com/netbootxyz/docker-netbootxyz |
| Issues | https://github.com/netbootxyz/docker-netbootxyz/issues |
| Support | https://community.bigbeartechworld.com/ |
| `resources.youtube` | empty string |
| `technical.default_port` | `3000` (web UI) |
| `technical.main_service` | `app` |
| `technical.main_image` | `ghcr.io/netbootxyz/netbootxyz` |
| `metadata.version` | image tag, currently `0.7.6-nbxyz24` |
| `tags` | `selfhosted`, `docker`, `bigbear`, `bigbearcasaos`, `pxe`, `tftp` |

`metadata.category` and `compatibility.casaos.category` are different fields. Validator enum for `metadata.category` does not include `Networking`. Existing networking Universal Apps (Pi-hole, AdGuard) use `BigBearCasaOS` plus CasaOS `Networking`. Runtipi will map `BigBearCasaOS` to `utilities`; do not special-case that.

## Compose

File: `apps/netboot-xyz/docker-compose.yml`

- Compose project name: `big-bear-netboot-xyz`
- One service, name `app` (store convention)
- `container_name: netboot-xyz`
- Image: `ghcr.io/netbootxyz/netbootxyz:0.7.6-nbxyz24@sha256:<digest>` — pin the **multi-arch index** digest at implementation (not a single-arch blob). Renovate tracks tag + digest.
- `restart: unless-stopped`
- No `privileged`, no `network_mode: host`, no extra compose network, no `MENU_VERSION` (unset pulls latest menus)
- No `PUID`/`PGID` (official example omits them)
- No `TFTPD_OPTS`

Environment (all `required: false` in `app.json`):

| Name | Default | Description |
|---|---|---|
| `NGINX_PORT` | `80` | nginx listen port inside the container for local assets |
| `WEB_APP_PORT` | `3000` | web UI listen port inside the container |
| `TZ` | `UTC` | container timezone |

Ports (bridge). Order in compose **must** be UI first so converters that read `ports[0]` get the web UI:

| Host | Container | Proto | Role |
|---|---|---|---|
| 3000 | 3000 | tcp | Web UI |
| 69 | 69 | udp | TFTP — must stay 69; PXE firmware requires it |
| 8080 | 80 | tcp | nginx local assets |

Volumes (named; each volume key has `name:` equal to the key and `driver: local`):

| Volume | Container path | `app.json` description |
|---|---|---|
| `netboot-xyz_config` | `/config` | Boot menus and web application config |
| `netboot-xyz_assets` | `/assets` | Optional local mirrored boot assets |

`app.json` `deployment` must list the same env vars, volumes (container paths), and ports. TFTP in `deployment.ports` must set `"protocol": "udp"`. TCP ports must set `"protocol": "tcp"`. Host/container values must match the table.

## DHCP is required and is not in this app

This PXE app is TFTP + HTTP + a menu. The LAN already has a DHCP server (router, AdGuard, Pi-hole). Fighting that DHCP is a non-goal.

`ui.scheme` is `http`, `ui.path` is `/`.

`ui.tips.before_install.en_us` **exact copy**:

```
This app does not run DHCP. Point the LAN's existing DHCP server at this host:

- next-server / TFTP server name (option 66): this host's LAN IP
- bootfile (option 67): netboot.xyz.kpxe (BIOS), netboot.xyz.efi (x86_64 UEFI), or netboot.xyz-arm64.efi (ARM64 UEFI)

These boot filenames are baked into the image. Host UDP 69 must stay mapped to container 69; PXE firmware requires port 69. If another process already bound host UDP 69, TCP 3000, or TCP 8080, the container will fail to start.
```

`ui.tips.after_install.en_us` **exact copy**:

```
Web UI: http://<host>:3000
Local assets: http://<host>:8080
```

## Platform compatibility

All six platforms `supported: true`, same pattern as Pi-hole / AdGuard (bridge network, published privileged ports; not host network).

| Platform | Notes |
|---|---|
| CasaOS | `port` and `port_map` `3000`. `category` `Networking`. Volume mappings: `netboot-xyz_config` → `/DATA/AppData/$AppID/config`, `netboot-xyz_assets` → `/DATA/AppData/$AppID/assets`. |
| Portainer | `template_type` 2, `categories` `["BigBearCasaOS", "selfhosted"]`, `administrator_only` false, `port` `3000` |
| Runtipi | `tipi_version` 1, `port` `3000` (above 1000 so the converter will not remap the UI). `supported_architectures` amd64 + arm64. Volume mappings: `netboot-xyz_config` → `config`, `netboot-xyz_assets` → `assets`. Service name is `app`, so the converter's `$app_name` first-port rewrite does **not** run; converted compose keeps `69:69/udp`. |
| Dockge | `file_based` true, `port` `3000` |
| Cosmos | `servapp` true, `routes_required` true, `port` `3000` |
| Umbrel | `manifest_version` 1, UI `port` **10196** (unused; buzz is 10195), `app_port` `3000` so app_proxy hits the UI not nginx/TFTP. Volume mappings: `netboot-xyz_config` → `config`, `netboot-xyz_assets` → `assets` |

Also add `"netboot-xyz": "Networking"` to `scripts/casaos-category-map.json`. The CasaOS convert test requires that map to cover every app.

## Error handling / constraints

- TFTP on a non-69 host port is a silent PXE failure. Compose host port 69 is required; the install tip repeats it.
- Port 80 on the host is CasaOS/ZimaOS. Asset HTTP is published as 8080:80, not 80:80.
- Image has no official `:latest` pin in this repo's style for versioned tags — use `0.7.6-nbxyz24` plus the multi-arch index digest. If that tag has moved by implementation time, pin whatever Hub currently reports as the latest non-`latest` release tag (`N.N.N-nbxyzN`) and set `metadata.version` to match.
- No runtime DHCP probe. Wrong DHCP options fail at the client firmware, not in our compose.
- First start with empty volumes: the image seeds `/config` with default menus. `/assets` stays empty until the user mirrors files in the UI.
- Multiple PXE clients at once: allowed; no app-level concurrency limit.
- Do not set `TFTPD_OPTS` in the store compose. If TFTP data-phase transfers fail through Docker NAT, that is a runtime LAN issue, not a missing compose field.
- Upstream web UI has no login. This listing will not add one.

## Testing

1. `./scripts/validate-apps.sh -a netboot-xyz` passes (JSON syntax, required fields, compose YAML). `metadata.category` is `BigBearCasaOS` (no unknown-category warning).
2. `./scripts/convert-to-platforms.sh -a netboot-xyz` produces all six platform trees without error.
3. Existing `scripts/tests/test-convert-{casaos,runtipi,umbrel}.sh` still pass (map coverage includes `netboot-xyz`).
4. `bun test ./.github/scripts/update-app-version.test.js` still passes.
5. Converted CasaOS compose keeps `69:69/udp` and `x-casaos.category` = Networking.
6. Converted Umbrel manifest uses port 10196 and does not swallow `network_mode` (none is set).
7. Converted Runtipi compose keeps `69:69/udp`.
8. `app.json` `deployment.ports` includes host `69`, container `69`, protocol `udp`.

No live PXE boot in CI. Success is a valid Universal App that converts; DHCP is documented, not automated.

## Files to add or edit

| Path | Change |
|---|---|
| `apps/netboot-xyz/app.json` | create |
| `apps/netboot-xyz/docker-compose.yml` | create |
| `scripts/casaos-category-map.json` | add `netboot-xyz` → `Networking` |

README app list is generated; do not hand-edit.

## Success

A CasaOS/ZimaOS user can install **netboot.xyz** from the Big Bear store, open the UI on port 3000, point existing DHCP at the host, and PXE-boot clients into the netboot.xyz menu. Issue #2800 is addressed without adding iVentoy.
