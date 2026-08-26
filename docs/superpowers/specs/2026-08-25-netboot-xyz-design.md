# netboot.xyz universal app

**Issue:** [big-bear-universal-apps#2800](https://github.com/bigbeartechworld/big-bear-universal-apps/issues/2800)
**Branch:** `feat/app-request-iventoy-or-netboot-xyz`
**Date:** 2026-08-25

## Problem

Issue #2800 asks for ZimaOS/CasaOS to act as a PXE boot server via the Big Bear store, suggesting iVentoy or netboot.xyz. CasaOS can run this: the store already ships host-network apps (Homebridge, Omada) and privileged apps. This branch adds **netboot.xyz only**.

netboot.xyz is an iPXE menu that boots OS installers and utilities over the network. The official container (`ghcr.io/netbootxyz/netbootxyz`) provides the web UI, TFTP, and optional local asset HTTP. It does **not** run DHCP. The LAN's existing DHCP server must point clients at this host.

iVentoy is out of scope (unofficial images, privileged + usually host network, closed source, built-in DHCP fights the LAN).

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

## Identity

| Field | Value |
|---|---|
| Directory / `metadata.id` | `netboot-xyz` |
| Display name | netboot.xyz |
| Category | Networking (`metadata.category` and `compatibility.casaos.category`) |
| License | Apache-2.0 |
| Developer | netbootxyz |
| Architectures | amd64, arm64 |
| Icon / logo | `https://cdn.jsdelivr.net/gh/selfhst/icons/png/netboot-xyz.png` (HTTP 200) |
| Homepage | https://netboot.xyz |
| Documentation | https://netboot.xyz/docs/docker/ |
| Repository | https://github.com/netbootxyz/docker-netbootxyz |
| Issues | https://github.com/netbootxyz/docker-netbootxyz/issues |
| Support | https://community.bigbeartechworld.com/ |
| `technical.default_port` | `3000` (web UI) |
| `technical.main_service` | `app` |
| `technical.main_image` | `ghcr.io/netbootxyz/netbootxyz` |
| `metadata.version` | image tag, currently `0.7.6-nbxyz24` |

## Compose

File: `apps/netboot-xyz/docker-compose.yml`

- Compose project name: `big-bear-netboot-xyz`
- One service, name `app` (store convention)
- `container_name: netboot-xyz`
- Image: `ghcr.io/netbootxyz/netbootxyz:0.7.6-nbxyz24@sha256:<digest>` — resolve digest at implementation; Renovate tracks tag + digest
- `restart: unless-stopped`
- No `privileged`, no `network_mode: host`, no extra compose network, no `MENU_VERSION` (menus track upstream latest)
- No `PUID`/`PGID` (official example omits them)

Environment:

- `NGINX_PORT=80`
- `WEB_APP_PORT=3000`
- `TZ=UTC`

Ports (bridge):

| Host | Container | Proto | Role |
|---|---|---|---|
| 3000 | 3000 | tcp | Web UI |
| 69 | 69 | udp | TFTP — must stay 69; PXE firmware requires it |
| 8080 | 80 | tcp | nginx local assets |

Volumes (named, `driver: local`):

| Volume | Container path |
|---|---|
| `netboot-xyz_config` | `/config` |
| `netboot-xyz_assets` | `/assets` |

`app.json` `deployment` must list the same env vars, volumes, and ports.

## DHCP is required and is not in this app

netboot.xyz is TFTP + HTTP + a menu. The LAN already has a DHCP server (router, AdGuard, Pi-hole). Fighting that DHCP is a non-goal.

`ui.tips.before_install.en_us` must state:

- This app does not run DHCP.
- Set existing DHCP **next-server** (option 66) to this host's LAN IP.
- Set **bootfile** (option 67) to `netboot.xyz.kpxe` (BIOS), `netboot.xyz.efi` (x86_64 UEFI), or `netboot.xyz-arm64.efi` (ARM64 UEFI). These filenames are baked into the image.
- Host UDP 69 must remain mapped to container 69.

`ui.tips.after_install.en_us`: web UI at `http://<host>:3000`; local assets at `http://<host>:8080`.

`ui.scheme` is `http`, `ui.path` is `/`.

## Platform compatibility

All six platforms `supported: true`, same pattern as Pi-hole / AdGuard (apps that also publish privileged ports).

| Platform | Notes |
|---|---|
| CasaOS | `port` / `port_map` 3000, category Networking, volume mappings under `/DATA/AppData/$AppID/` |
| Portainer | template_type 2, categories `["BigBearCasaOS", "selfhosted"]` |
| Runtipi | `port` 3000 (above 1000 so the converter will not remap the UI). TFTP 69 may still be remapped by Runtipi; the tip covers that. amd64 + arm64 |
| Dockge | file_based, port 3000 |
| Cosmos | servapp, routes_required, port 3000 |
| Umbrel | manifest_version 1, UI `port` **10196** (next unused 101xx), `app_port` 3000 so app_proxy hits the UI not nginx/TFTP. Volume mappings: `netboot-xyz_config` → `config`, `netboot-xyz_assets` → `assets` |

Also add `"netboot-xyz": "Networking"` to `scripts/casaos-category-map.json`. The CasaOS convert test requires that map to cover every app.

## Error handling / constraints

- TFTP on a non-69 host port is a silent PXE failure. Compose host port 69 is required; the install tip repeats it.
- Port 80 on the host is CasaOS/ZimaOS. Asset HTTP is published as 8080:80, not 80:80.
- Image has no official `:latest` pin in this repo's style for versioned tags — use `0.7.6-nbxyz24` plus digest. If that tag has moved by implementation time, pin whatever Hub currently reports as the latest non-`latest` release tag and set `metadata.version` to match.
- No runtime DHCP probe. Wrong DHCP options fail at the client firmware, not in our compose.

## Testing

1. `./scripts/validate-apps.sh -a netboot-xyz` passes JSON schema + compose YAML.
2. `./scripts/convert-to-platforms.sh -a netboot-xyz` produces all six platform trees without error.
3. Existing `scripts/tests/test-convert-{casaos,runtipi,umbrel}.sh` still pass (map coverage includes `netboot-xyz`).
4. `bun test ./.github/scripts/update-app-version.test.js` still passes.
5. Converted CasaOS compose keeps `69:69/udp` and `x-casaos.category` = Networking.
6. Converted Umbrel manifest uses port 10196 and does not swallow `network_mode` (none is set).

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
