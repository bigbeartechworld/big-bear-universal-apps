# Hermes Agent App Definition Design

## Goal

Add Hermes Agent as a standard universal app definition under `apps/hermes`, based on the existing CasaOS Hermes app and CasaOS-AppStore PR [#1058](https://github.com/IceWhaleTech/CasaOS-AppStore/pull/1058). The definition must run Hermes Agent 0.21.3 from `nousresearch/hermes-agent:v2026.9.14` and require dashboard authentication without shipping insecure mode or a shared password.

## Scope

Implementation creates exactly:

- `apps/hermes/app.json`
- `apps/hermes/docker-compose.yml`

No README, local images, generated platform output, schema changes, conversion changes, or other app edits are included. Existing CasaOS-hosted icon, thumbnail, and screenshot URLs may be referenced from `app.json`; `x-casaos` sections must not appear in the universal Compose file.

## Chosen Design

Use the repository's universal two-file pattern: `app.json` owns metadata, install settings, platform mappings, and UI guidance; a clean Compose file owns the portable runtime. This preserves the upstream behavior while allowing the existing converters to generate platform-specific definitions.

Rejected alternatives:

- Copy the CasaOS Compose file unchanged: rejected because `/DATA/AppData/$AppID/` and `x-casaos` are platform-specific.
- Add a wrapper, startup script, or custom image: rejected because the upstream image already provides `gateway run` and enforces the non-empty dashboard password.

## `app.json`

Use schema version `1.0` and these resolved values:

- Identity: `id` `hermes`, name `Hermes Agent`, author `BigBearCommunity`, developer `Nous Research`, category `BigBearCasaOS`, license `MIT`, source `big-bear-universal`.
- Version: `v2026.9.14`, matching the Docker image tag and the repository's version-sync convention. The description identifies this as Hermes Agent 0.21.3. The schema's older digit-only version pattern is not enforced by `validate-apps.sh` and conflicts with existing `v`-prefixed app definitions, so this feature does not change the shared schema.
- Dates: both `created` and `updated` are `2026-09-18T00:00:00Z`.
- Homepage and documentation: `https://hermes-agent.nousresearch.com/` and `https://hermes-agent.nousresearch.com/docs/`.
- Repository and issues: `https://github.com/NousResearch/hermes-agent` and its `/issues` URL.
- Visuals: use `https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Hermes/icon.svg` for both icon and logo, the matching `thumbnail.png`, and `screenshot-1.png` through `screenshot-3.png` from the same directory. Do not copy assets into this repository.
- Architectures: `amd64` and `arm64`; platform `linux`; main service `hermes`; main image `nousresearch/hermes-agent`; compose file `docker-compose.yml`.
- Primary UI: HTTP dashboard on port `9119`, path empty. Port `8642` remains documented as the gateway API.
- Volume: `/opt/data`, described as persistent Hermes user data.
- Environment settings:
  - `HERMES_DASHBOARD`, default `1`, not required.
  - `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`, default `zimaos`, not required.
  - `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`, default empty, required. Its description must state that the user must provide a private password before startup and that the dashboard refuses an empty password.
- Installation tip: repeat the password requirement and default username. Do not mention or expose `HERMES_DASHBOARD_INSECURE` as an option.
- CasaOS compatibility: supported, category `AI`, port map `9119`, and map named volume `hermes_data` to `/DATA/AppData/$AppID/` so generated CasaOS output preserves the upstream data location.
- Portainer: supported, template type `2`, categories `BigBearCasaOS` and `selfhosted`, not administrator-only.
- Runtipi: supported, Tipi version `1`, architectures `amd64` and `arm64`, with `hermes_data` mapped to `data`.
- Dockge: supported and file-based. Cosmos: supported, servapp enabled, routes required. Umbrel: supported, manifest version `1`, with `hermes_data` mapped to `data`.
- All platforms inherit dashboard port `9119`; no platform-specific port override is needed. Tags are `selfhosted`, `docker`, `bigbear`, `bigbearcasaos`, `ai`, `agent`, and `automation`.

## `docker-compose.yml`

Define one application named `hermes` with one service named `hermes`:

- Image `nousresearch/hermes-agent:v2026.9.14`.
- Container name `hermes` and restart policy `unless-stopped`.
- Command list `gateway`, `run`.
- TCP mappings `8642:8642` and `9119:9119`.
- Named volume `hermes_data:/opt/data`, declared as a local top-level volume.
- Environment values `HERMES_DASHBOARD=1`, `HERMES_DASHBOARD_BASIC_AUTH_USERNAME=${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-zimaos}`, and `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:-}`.
- Deploy reservation of `1G` memory, matching upstream.

Do not add `HERMES_DASHBOARD_INSECURE`, `x-casaos`, custom networks, health checks, wrapper commands, or extra services. The empty Compose fallback makes the password editable across standard Compose consumers; Hermes itself must refuse dashboard startup until a non-empty value is supplied.

## Data and Startup Flow

The installer presents the three environment settings and the pre-install warning. The user supplies a private dashboard password, then Compose starts `gateway run`. Hermes persists all state under `/opt/data`, exposes its gateway API on `8642`, and serves the authenticated dashboard on `9119`. Platform conversion replaces `hermes_data` with the configured platform data path without changing the container path.

## Failure Behavior

- Empty dashboard password: Hermes refuses to start the dashboard; the install tip and required setting explain the correction.
- Occupied host port: Compose reports the bind conflict; no automatic remapping is added.
- Unsupported architecture or unavailable image: Docker reports the pull error; metadata advertises only the verified `amd64` and `arm64` variants.
- Persistent data must survive container replacement through `hermes_data` or its converted platform bind mount.

## Acceptance Criteria

- Only `apps/hermes/app.json` and `apps/hermes/docker-compose.yml` are added during implementation.
- `app.json` parses with `jq` and `./scripts/validate-apps.sh -a hermes` confirms the required metadata, technical, and deployment structure without warnings. Its `technical.main_service`, `technical.main_image`, `technical.default_port`, deployment ports and volume, and three environment settings exactly match the Compose service, image, dashboard port, mappings, and environment names. The password setting has `default` `""` and `required` `true`.
- Compose parses as YAML and `docker compose -f apps/hermes/docker-compose.yml config` succeeds when a non-empty dashboard password is supplied.
- `./scripts/validate-apps.sh -a hermes` passes without warnings.
- `bun test` passes.
- The image tag exists and provides Linux `amd64` and `arm64` manifests.
- No placeholder text, insecure dashboard flag, plaintext shared password, local asset, or platform-specific Compose extension is present.

## Sources

- [CasaOS Hermes app](https://github.com/IceWhaleTech/CasaOS-AppStore/tree/main/Apps/Hermes)
- [CasaOS-AppStore PR #1058](https://github.com/IceWhaleTech/CasaOS-AppStore/pull/1058)
- [Hermes Agent repository](https://github.com/NousResearch/hermes-agent)
- [Hermes Agent v2026.9.14 release](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.9.14)
