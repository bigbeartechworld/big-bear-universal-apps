# netboot.xyz Universal App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one Universal App at `apps/netboot-xyz/` that wraps the official netboot.xyz container (web UI, TFTP, local asset HTTP) and converts to all six platforms.

**Architecture:** Thin wrap of `ghcr.io/netbootxyz/netbootxyz` as a PXE app (TFTP + boot menu, not DHCP). One `app` service on compose bridge with published ports; UI is `ports[0]` so CasaOS/Umbrel/Runtipi converters that read the first port hit the web UI, not TFTP. Named volumes, digest-pinned multi-arch index. DHCP next-server and bootfile live in `ui.tips.before_install`. CasaOS store category is `compatibility.casaos.category` = `Networking` plus `scripts/casaos-category-map.json`; `metadata.category` stays `BigBearCasaOS` (validator enum; Runtipi maps that to `utilities` — do not special-case).

**Tech Stack:** Universal App Format (`app.json` + clean `docker-compose.yml`), `scripts/validate-apps.sh`, `scripts/convert-to-platforms.sh`, CasaOS / Portainer / Runtipi / Dockge / Cosmos / Umbrel converters. Tests are those scripts and `scripts/tests/test-convert-{casaos,runtipi,umbrel}.sh`, plus `bun test ./.github/scripts/update-app-version.test.js`. No app.json unit tests.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-25-netboot-xyz-design.md`. Issue: [big-bear-universal-apps#2800](https://github.com/bigbeartechworld/big-bear-universal-apps/issues/2800).
- Directory / `metadata.id`: `netboot-xyz`. Display name: `netboot.xyz`. `spec_version`: `1.0`.
- `metadata.category`: `BigBearCasaOS`. `compatibility.casaos.category`: `Networking`.
- `metadata.version` / image tag: `0.7.6-nbxyz24`. `technical.main_image`: `ghcr.io/netbootxyz/netbootxyz`.
- Image pin (multi-arch **index** digest from `docker buildx imagetools inspect ghcr.io/netbootxyz/netbootxyz:0.7.6-nbxyz24` at plan time): `ghcr.io/netbootxyz/netbootxyz:0.7.6-nbxyz24@sha256:7bd0964fd3648cd3323772ad6ad8b0a507afe797385e4c0f587a8c23972ee4e3`. Do **not** pin linux/amd64 blob `sha256:077c0c09c53043416d581406618713af81d2821d083cd6f0dc431a4448e8dfbd` or linux/arm64 blob `sha256:317e04ad4687e8a3fa63e4df6d851267643cf71f58543d0d4288b157dbdbd16b`. If that tag has moved, pin the current latest non-`latest` release tag (`N.N.N-nbxyzN`) and set `metadata.version` to match.
- Architectures: `amd64`, `arm64`. `technical.platform`: `linux`. `technical.compose_file`: `docker-compose.yml`. `technical.main_service`: `app`. `technical.default_port`: `3000`.
- Compose project name: `big-bear-netboot-xyz`. Service: `app`. `container_name`: `netboot-xyz`. `restart`: `unless-stopped`.
- No `privileged`, no `network_mode: host`, no extra compose network, no `MENU_VERSION`, no `PUID`/`PGID`, no `TFTPD_OPTS`, no authentication, no app-level README, do not commit `converted/` (gitignored; CI converts).
- iVentoy and any DHCP sidecar are out of scope.
- Ports in compose **must** be UI first: `3000:3000` (tcp), `69:69/udp` (TFTP; host 69 required), `8080:80` (tcp, nginx assets). Never publish host 80 (CasaOS owns it).
- Runtipi converter renames service `app` to `netboot-xyz` and rewrites **only** `ports[0]` to `${APP_PORT}:…`. Keeping UI first is what preserves `69:69/udp`. Runtipi `port` is `3000` (above 1000 so the converter will not remap the UI).
- Umbrel `port` is `10196` (buzz is `10195`). Umbrel `app_port` is `3000` so app_proxy hits the UI, not nginx/TFTP. Converter deletes service `ports` on Umbrel; that is existing platform behavior (same as Pi-hole), not a bug to paper over with host networking.
- `converted/` is gitignored. Use `./scripts/convert-to-platforms.sh -a netboot-xyz -o <tmpdir>` for checks. Do not add `converted/` to git.
- Follow existing app shape (`apps/arma3-server/` for a recent listing, `apps/adguard-home/` / `apps/pihole/` for Networking + privileged ports). 2-space JSON, trailing newline, no compose comments.

## File Structure

| Path | Responsibility |
|---|---|
| `apps/netboot-xyz/docker-compose.yml` | Clean compose: one `app` service, digest-pinned image, published ports, named volumes. No `x-casaos`. |
| `apps/netboot-xyz/app.json` | Source of truth: identity, deployment (env/volumes/ports), UI tips, per-platform compatibility. |
| `scripts/casaos-category-map.json` | Add `"netboot-xyz": "Networking"` so `migrate-casaos-categories.ts --apply` and `test-convert-casaos.sh` cover every app. |

README app list is generated; do not hand-edit.

---

### Task 1: netboot-xyz Universal App source

**Files:**
- Create: `apps/netboot-xyz/docker-compose.yml`
- Create: `apps/netboot-xyz/app.json`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: Universal App `netboot-xyz` with `metadata.id` `netboot-xyz`, service `app`, image `ghcr.io/netbootxyz/netbootxyz:0.7.6-nbxyz24@sha256:7bd0964fd3648cd3323772ad6ad8b0a507afe797385e4c0f587a8c23972ee4e3`, named volumes `netboot-xyz_config` (`/config`) and `netboot-xyz_assets` (`/assets`), ports `3000/tcp`, `69/udp`, `8080:80/tcp`, `compatibility.casaos.category` `Networking`.

- [ ] **Step 1: Run validate-apps.sh to verify it fails**

Run:

```bash
./scripts/validate-apps.sh -a netboot-xyz
```

Expected: exit 1. Decisive lines:

```
[INFO] Validating netboot-xyz...
[✗] App directory not found:
```

The path after `not found:` ends with `apps/netboot-xyz`. `set -e` in the validator exits before the summary block.

- [ ] **Step 2: Write docker-compose.yml**

Create `apps/netboot-xyz/docker-compose.yml` with this exact content (including the trailing newline):

```yaml
name: big-bear-netboot-xyz

services:
  app:
    image: ghcr.io/netbootxyz/netbootxyz:0.7.6-nbxyz24@sha256:7bd0964fd3648cd3323772ad6ad8b0a507afe797385e4c0f587a8c23972ee4e3
    container_name: netboot-xyz
    ports:
      - "3000:3000"
      - "69:69/udp"
      - "8080:80"
    volumes:
      - netboot-xyz_config:/config
      - netboot-xyz_assets:/assets
    environment:
      - NGINX_PORT=80
      - WEB_APP_PORT=3000
      - TZ=UTC
    restart: unless-stopped

volumes:
  netboot-xyz_config:
    name: netboot-xyz_config
    driver: local
  netboot-xyz_assets:
    name: netboot-xyz_assets
    driver: local
```

Port order is a requirement: `3000:3000` first, then `69:69/udp`, then `8080:80`. Do not add `privileged`, `network_mode`, `networks`, `MENU_VERSION`, `PUID`, `PGID`, or `TFTPD_OPTS`.

- [ ] **Step 3: Write app.json**

Create `apps/netboot-xyz/app.json` with this exact content (including the trailing newline):

```json
{
  "spec_version": "1.0",
  "metadata": {
    "id": "netboot-xyz",
    "name": "netboot.xyz",
    "description": "netboot.xyz is a PXE app: an iPXE menu that boots OS installers and utilities over the network. This Universal App wraps the official container (web UI, TFTP, local asset HTTP). It does not run DHCP; point the LAN DHCP next-server and bootfile at this host.",
    "tagline": "Network boot menu (iPXE) with TFTP and a web UI",
    "version": "0.7.6-nbxyz24",
    "author": "BigBearTechWorld",
    "developer": "netbootxyz",
    "category": "BigBearCasaOS",
    "license": "Apache-2.0",
    "homepage": "https://netboot.xyz",
    "source": "big-bear-universal",
    "created": "2026-08-25T00:00:00Z",
    "updated": "2026-08-25T00:00:00Z"
  },
  "visual": {
    "icon": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/netboot-xyz.png",
    "thumbnail": "",
    "screenshots": [],
    "logo": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/netboot-xyz.png"
  },
  "resources": {
    "youtube": "",
    "documentation": "https://netboot.xyz/docs/docker/",
    "repository": "https://github.com/netbootxyz/docker-netbootxyz",
    "issues": "https://github.com/netbootxyz/docker-netbootxyz/issues",
    "support": "https://community.bigbeartechworld.com/"
  },
  "technical": {
    "architectures": [
      "amd64",
      "arm64"
    ],
    "platform": "linux",
    "main_service": "app",
    "default_port": "3000",
    "main_image": "ghcr.io/netbootxyz/netbootxyz",
    "compose_file": "docker-compose.yml"
  },
  "deployment": {
    "environment_variables": [
      {
        "name": "NGINX_PORT",
        "default": "80",
        "description": "nginx listen port inside the container for local assets",
        "required": false
      },
      {
        "name": "WEB_APP_PORT",
        "default": "3000",
        "description": "web UI listen port inside the container",
        "required": false
      },
      {
        "name": "TZ",
        "default": "UTC",
        "description": "container timezone",
        "required": false
      }
    ],
    "volumes": [
      {
        "container": "/config",
        "description": "Boot menus and web application config"
      },
      {
        "container": "/assets",
        "description": "Optional local mirrored boot assets"
      }
    ],
    "ports": [
      {
        "container": "3000",
        "host": "3000",
        "protocol": "tcp",
        "description": "Web UI"
      },
      {
        "container": "69",
        "host": "69",
        "protocol": "udp",
        "description": "TFTP — must stay 69; PXE firmware requires it"
      },
      {
        "container": "80",
        "host": "8080",
        "protocol": "tcp",
        "description": "nginx local assets"
      }
    ]
  },
  "ui": {
    "scheme": "http",
    "path": "/",
    "tips": {
      "before_install": {
        "en_us": "This app does not run DHCP. Point the LAN's existing DHCP server at this host:\n\n- next-server / TFTP server name (option 66): this host's LAN IP\n- bootfile (option 67): netboot.xyz.kpxe (BIOS), netboot.xyz.efi (x86_64 UEFI), or netboot.xyz-arm64.efi (ARM64 UEFI)\n\nThese boot filenames are baked into the image. Host UDP 69 must stay mapped to container 69; PXE firmware requires port 69. If another process already bound host UDP 69, TCP 3000, or TCP 8080, the container will fail to start."
      },
      "after_install": {
        "en_us": "Web UI: http://<host>:3000\nLocal assets: http://<host>:8080"
      }
    }
  },
  "compatibility": {
    "casaos": {
      "supported": true,
      "port_map": "3000",
      "port": "3000",
      "category": "Networking",
      "volume_mappings": {
        "netboot-xyz_config": "/DATA/AppData/$AppID/config",
        "netboot-xyz_assets": "/DATA/AppData/$AppID/assets"
      }
    },
    "portainer": {
      "supported": true,
      "template_type": 2,
      "categories": [
        "BigBearCasaOS",
        "selfhosted"
      ],
      "administrator_only": false,
      "port": "3000"
    },
    "runtipi": {
      "supported": true,
      "tipi_version": 1,
      "supported_architectures": [
        "amd64",
        "arm64"
      ],
      "port": "3000",
      "volume_mappings": {
        "netboot-xyz_config": "config",
        "netboot-xyz_assets": "assets"
      }
    },
    "dockge": {
      "supported": true,
      "file_based": true,
      "port": "3000"
    },
    "cosmos": {
      "supported": true,
      "servapp": true,
      "routes_required": true,
      "port": "3000"
    },
    "umbrel": {
      "supported": true,
      "manifest_version": 1,
      "port": "10196",
      "app_port": "3000",
      "volume_mappings": {
        "netboot-xyz_config": "config",
        "netboot-xyz_assets": "assets"
      }
    }
  },
  "tags": [
    "selfhosted",
    "docker",
    "bigbear",
    "bigbearcasaos",
    "pxe",
    "tftp"
  ]
}
```

`ui.tips.before_install.en_us` and `ui.tips.after_install.en_us` are spec-exact. Do not rephrase. `visual.thumbnail` is the empty string; `visual.screenshots` is `[]`; `resources.youtube` is `""`.

- [ ] **Step 4: Run validate-apps.sh to verify it passes**

Run:

```bash
./scripts/validate-apps.sh -a netboot-xyz
```

Expected: exit 0.

```
[INFO] Validating netboot-xyz...
[✓] netboot-xyz: PASSED
```

Summary block:

```
Total:    1 apps
Passed:   1 apps
Failed:   0 apps
Warnings: 0 total
```

Zero warnings matters: `metadata.category` `BigBearCasaOS` must not trip `Unknown category`.

Optional icon check (spec: icon HTTP 200):

```bash
./scripts/validate-apps.sh -a netboot-xyz --check-links
```

Expected: exit 0 and `All 2 image URL(s) resolved 200.` (icon + logo; empty thumbnail/screenshots are skipped).

- [ ] **Step 5: Assert spec fields validate-apps.sh does not cover**

Run:

```bash
APP=apps/netboot-xyz/app.json
COMPOSE=apps/netboot-xyz/docker-compose.yml

test "$(jq -r '.metadata.id' "$APP")" = "netboot-xyz"
test "$(jq -r '.metadata.category' "$APP")" = "BigBearCasaOS"
test "$(jq -r '.compatibility.casaos.category' "$APP")" = "Networking"
test "$(jq -r '.technical.default_port' "$APP")" = "3000"
test "$(jq -r '.technical.main_service' "$APP")" = "app"
test "$(jq -r '.technical.main_image' "$APP")" = "ghcr.io/netbootxyz/netbootxyz"
test "$(jq -r '.metadata.version' "$APP")" = "0.7.6-nbxyz24"
test "$(jq -r '.ui.scheme' "$APP")" = "http"
test "$(jq -r '.ui.path' "$APP")" = "/"
test "$(jq -r '.compatibility.umbrel.port' "$APP")" = "10196"
test "$(jq -r '.compatibility.umbrel.app_port' "$APP")" = "3000"
test "$(jq -r '.compatibility.runtipi.port' "$APP")" = "3000"

test "$(jq -r '.deployment.ports[] | select(.host=="69") | "\(.container)/\(.protocol)"' "$APP")" = "69/udp"
test "$(jq -r '.deployment.ports[] | select(.host=="3000") | "\(.container)/\(.protocol)"' "$APP")" = "3000/tcp"
test "$(jq -r '.deployment.ports[] | select(.host=="8080") | "\(.container)/\(.protocol)"' "$APP")" = "80/tcp"

test "$(yq eval '.services.app.ports[0]' "$COMPOSE")" = "3000:3000"
test "$(yq eval '.services.app.ports[1]' "$COMPOSE")" = "69:69/udp"
test "$(yq eval '.services.app.ports[2]' "$COMPOSE")" = "8080:80"
test "$(yq eval '.services.app.image' "$COMPOSE")" = "ghcr.io/netbootxyz/netbootxyz:0.7.6-nbxyz24@sha256:7bd0964fd3648cd3323772ad6ad8b0a507afe797385e4c0f587a8c23972ee4e3"
test "$(yq eval '.services.app.privileged // "ABSENT"' "$COMPOSE")" = "ABSENT"
test "$(yq eval '.services.app.network_mode // "ABSENT"' "$COMPOSE")" = "ABSENT"
test "$(yq eval '.networks // "ABSENT"' "$COMPOSE")" = "ABSENT"

jq -e --arg want "$(printf '%s' "This app does not run DHCP. Point the LAN's existing DHCP server at this host:

- next-server / TFTP server name (option 66): this host's LAN IP
- bootfile (option 67): netboot.xyz.kpxe (BIOS), netboot.xyz.efi (x86_64 UEFI), or netboot.xyz-arm64.efi (ARM64 UEFI)

These boot filenames are baked into the image. Host UDP 69 must stay mapped to container 69; PXE firmware requires port 69. If another process already bound host UDP 69, TCP 3000, or TCP 8080, the container will fail to start.")" '.ui.tips.before_install.en_us == $want' "$APP" >/dev/null

jq -e --arg want "$(printf '%s' "Web UI: http://<host>:3000
Local assets: http://<host>:8080")" '.ui.tips.after_install.en_us == $want' "$APP" >/dev/null

echo "ok: netboot-xyz source fields"
```

Expected: exit 0 and `ok: netboot-xyz source fields`. Any `test` failure prints nothing extra; the shell exits non-zero. Do not proceed on a failed `test`.

- [ ] **Step 6: Commit**

```bash
git add apps/netboot-xyz/app.json apps/netboot-xyz/docker-compose.yml
git commit -m "$(cat <<'EOF'
feat: add netboot-xyz Universal App

Wrap official ghcr.io/netbootxyz/netbootxyz as a PXE app (TFTP +
web UI, no DHCP) with digest-pinned multi-arch image and DHCP
setup documented in before_install.
EOF
)"
```

---

### Task 2: CasaOS category map entry

**Files:**
- Modify: `scripts/casaos-category-map.json` (insert `"netboot-xyz": "Networking"` in alphabetical position between `netalertx-v26` and `netpulse`)

**Interfaces:**
- Consumes: `metadata.id` `netboot-xyz` from Task 1 (the app directory must exist so `migrate-casaos-categories.ts --apply` can resolve the id).
- Produces: committed map key `"netboot-xyz": "Networking"` so `--apply` does not throw `No mapping for "netboot-xyz"`.

- [ ] **Step 1: Run the map lookup to verify it fails**

Run:

```bash
jq -e '.["netboot-xyz"] == "Networking"' scripts/casaos-category-map.json
```

Expected: exit 1. `jq` prints `false` or `null` (key missing).

- [ ] **Step 2: Add the map entry**

In `scripts/casaos-category-map.json`, insert one line after `"netalertx-v26": "Networking",` and before `"netpulse": "Networking",`:

```json
  "netalertx-v26": "Networking",
  "netboot-xyz": "Networking",
  "netpulse": "Networking",
```

Do not reorder the rest of the file. Do not change any other key.

- [ ] **Step 3: Re-run the map lookup to verify it passes**

Run:

```bash
jq -e '.["netboot-xyz"] == "Networking"' scripts/casaos-category-map.json
```

Expected: exit 0, stdout `true`.

- [ ] **Step 4: Run test-convert-casaos.sh**

Run:

```bash
bash scripts/tests/test-convert-casaos.sh
```

Expected: exit 0. Every assertion line is `ok: …`. Required lines (among others):

```
ok: map covers every app
ok: all apps have casaos.category
ok: metadata.category unchanged
```

`--apply` copies `apps/` to a temp dir and requires every app id, including `netboot-xyz`, in the committed map. The generated-map half of the test counts `apps/*/` vs map length; adding this listing without the key still produces a generated map (from name+description, which matches `network`), but `--apply` against the committed map throws `No mapping for "netboot-xyz"`.

- [ ] **Step 5: Commit**

```bash
git add scripts/casaos-category-map.json
git commit -m "$(cat <<'EOF'
feat: map netboot-xyz to CasaOS Networking

Register the new app in casaos-category-map.json so convert-casaos
map coverage and migrate --apply include it.
EOF
)"
```

---

### Task 3: Convert all six platforms and assert PXE ports

**Files:**
- Test only (no source edits). Output under a temp dir via `-o`; do not commit `converted/`.

**Interfaces:**
- Consumes: `apps/netboot-xyz/app.json`, `apps/netboot-xyz/docker-compose.yml`, `scripts/casaos-category-map.json` from Tasks 1–2.
- Produces: six platform trees. CasaOS compose keeps `69:69/udp` and `x-casaos.category` = `Networking`. Runtipi compose keeps `69:69/udp` (UI port may become `${APP_PORT}:3000` after the first-port rewrite). Umbrel manifest `port` is `10196`, `app_proxy.environment.APP_PORT` is `3000`, no `network_mode`.

- [ ] **Step 1: Run convert assertions against missing output (fail)**

Run:

```bash
test -f /tmp/netboot-xyz-convert-does-not-exist/casaos/netboot-xyz/docker-compose.yml
```

Expected: exit 1 (`test -f` on a missing file). This is the red check before conversion.

- [ ] **Step 2: Convert netboot-xyz to all six platforms**

Run:

```bash
TMP_OUT="$(mktemp -d)"
echo "$TMP_OUT" > /tmp/netboot-xyz-convert-outdir
./scripts/convert-to-platforms.sh -a netboot-xyz -o "$TMP_OUT"
```

Expected: exit 0. Success lines include:

```
[SUCCESS] Converted netboot-xyz for CasaOS
[SUCCESS] Converted netboot-xyz for Portainer
[SUCCESS] Converted netboot-xyz for Runtipi
[SUCCESS] Converted netboot-xyz for Dockge
[SUCCESS] Converted netboot-xyz for Cosmos
[SUCCESS] Converted netboot-xyz for Umbrel
```

Summary:

```
Converted: 1 apps
Skipped:   0 apps
Errors:    0 apps
```

These files must exist:

```
$TMP_OUT/casaos/netboot-xyz/docker-compose.yml
$TMP_OUT/casaos/netboot-xyz/config.json
$TMP_OUT/portainer/netboot-xyz/docker-compose.yml
$TMP_OUT/runtipi/netboot-xyz/docker-compose.yml
$TMP_OUT/runtipi/netboot-xyz/docker-compose.json
$TMP_OUT/runtipi/netboot-xyz/config.json
$TMP_OUT/dockge/netboot-xyz/compose.yaml
$TMP_OUT/cosmos/netboot-xyz/docker-compose.yml
$TMP_OUT/umbrel/big-bear-umbrel-netboot-xyz/docker-compose.yml
$TMP_OUT/umbrel/big-bear-umbrel-netboot-xyz/umbrel-app.yml
```

- [ ] **Step 3: Assert converted CasaOS, Runtipi, and Umbrel artifacts**

Run:

```bash
TMP_OUT="$(cat /tmp/netboot-xyz-convert-outdir)"
CASA="$TMP_OUT/casaos/netboot-xyz/docker-compose.yml"
RT="$TMP_OUT/runtipi/netboot-xyz/docker-compose.yml"
RTJ="$TMP_OUT/runtipi/netboot-xyz/docker-compose.json"
UMB="$TMP_OUT/umbrel/big-bear-umbrel-netboot-xyz/docker-compose.yml"
UMBMAN="$TMP_OUT/umbrel/big-bear-umbrel-netboot-xyz/umbrel-app.yml"

test "$(yq eval '.x-casaos.category' "$CASA")" = "Networking"
test "$(yq eval '.x-casaos.port_map' "$CASA")" = "3000"
test "$(yq eval '.x-casaos.main' "$CASA")" = "app"
test "$(yq eval '.services.app.ports[0]' "$CASA")" = "3000:3000"
test "$(yq eval '.services.app.ports[1]' "$CASA")" = "69:69/udp"
test "$(yq eval '.services.app.ports[2]' "$CASA")" = "8080:80"
grep -Fq '/DATA/AppData/$AppID/config:/config' "$CASA"
grep -Fq '/DATA/AppData/$AppID/assets:/assets' "$CASA"
test "$(yq eval '.x-casaos.tips.before_install | has("en_US")' "$CASA")" = "true"
test "$(yq eval '.x-casaos.tips.before_install | has("en_us")' "$CASA")" = "false"

grep -Fq '69:69/udp' "$RT"
test "$(yq eval '.services["netboot-xyz"].ports[0]' "$RT")" = '${APP_PORT}:3000'
test "$(yq eval '.services["netboot-xyz"].ports[1]' "$RT")" = "69:69/udp"
test "$(yq eval '.services["netboot-xyz"].ports[2]' "$RT")" = "8080:80"
grep -Fq '${APP_DATA_DIR}/config:/config' "$RT"
grep -Fq '${APP_DATA_DIR}/assets:/assets' "$RT"
test "$(jq -r '.services[0].image' "$RTJ")" = "ghcr.io/netbootxyz/netbootxyz:0.7.6-nbxyz24@sha256:7bd0964fd3648cd3323772ad6ad8b0a507afe797385e4c0f587a8c23972ee4e3"
test "$(jq -r '.services[0].internalPort' "$RTJ")" = "3000"

test "$(yq eval '.port' "$UMBMAN")" = "10196"
test "$(yq eval '.services.app_proxy.environment.APP_PORT' "$UMB")" = "3000"
test "$(yq eval '.services.app.network_mode // "ABSENT"' "$UMB")" = "ABSENT"
test "$(yq eval '.services.app_proxy // "ABSENT"' "$UMB")" != "ABSENT"
grep -Fq '${APP_DATA_DIR}/config:/config' "$UMB"
grep -Fq '${APP_DATA_DIR}/assets:/assets' "$UMB"

echo "ok: converted netboot-xyz platforms"
```

Expected: exit 0 and `ok: converted netboot-xyz platforms`.

If Runtipi `ports[0]` is still `3000:3000` instead of `${APP_PORT}:3000`, that is acceptable **only if** `69:69/udp` is still present (the rewrite no-op'd). Fail the task if `69:69/udp` is missing or was rewritten to `${APP_PORT}:69/udp`.

- [ ] **Step 4: Run remaining convert tests and version extractor tests**

Run:

```bash
bash scripts/tests/test-convert-runtipi.sh
bash scripts/tests/test-convert-umbrel.sh
bun test ./.github/scripts/update-app-version.test.js
```

Expected: all three exit 0.

`test-convert-runtipi.sh` ends with either a full-run skip (`ok: full-run case skipped (set RUNTIPI_FULL_RUN=1 to enable)`) or `ok: full run emits no warnings`. Default skip is correct; do not set `RUNTIPI_FULL_RUN=1`.

`test-convert-umbrel.sh` ends with `ok: catalog case skipped (set UMBREL_FULL_RUN=1 to enable)` unless `UMBREL_FULL_RUN=1`. Default skip is correct.

`bun test` prints passing extractor cases (`extracts version from a plain tagged image`, `strips digest pin before extracting version`, …). Adding this app does not change that file; the run is a regression guard.

- [ ] **Step 5: Re-run CasaOS convert tests after conversion (no source drift)**

Run:

```bash
bash scripts/tests/test-convert-casaos.sh
```

Expected: exit 0, same `ok:` lines as Task 2 Step 4.

- [ ] **Step 6: Commit only if Step 3 required a source fix**

If Steps 3–5 passed with no further edits, there is nothing to commit (converted trees are gitignored). If a source fix was required (port order, `app_port`, map, digest), commit that fix:

```bash
git add apps/netboot-xyz/app.json apps/netboot-xyz/docker-compose.yml scripts/casaos-category-map.json
git commit -m "$(cat <<'EOF'
fix: keep netboot-xyz TFTP on host UDP 69 through converters
EOF
)"
```

Only stage files that actually changed. Do not `git add converted/`.

---

## Self-review (plan author)

1. **Spec coverage:** Identity, compose, env/volumes/ports, exact DHCP tips, all six `compatibility.*` blocks, category map, validate-apps, convert-to-platforms, convert tests, bun test, CasaOS `69:69/udp` + Networking, Umbrel 10196 + no swallowed `network_mode`, Runtipi `69:69/udp`, `deployment.ports` UDP 69 — each has a task/step. Non-goals (iVentoy, DHCP sidecar, host network, README, TFTPD_OPTS, auth, committing `converted/`) have no implement steps.
2. **Placeholder scan:** Full compose YAML and full `app.json` are in Task 1. Map snippet is exact. No TBD / similar-to-Task-N.
3. **Type consistency:** Volume keys `netboot-xyz_config` / `netboot-xyz_assets`, service `app`, ports `3000`/`69/udp`/`8080:80`, Umbrel `10196`/`app_port` `3000` match across tasks.
