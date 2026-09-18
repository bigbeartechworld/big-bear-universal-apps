# Hermes Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Hermes Agent 0.21.3 universal app definition with an authenticated dashboard and persistent data.

**Architecture:** `app.json` owns universal metadata, install settings, platform mappings, and password guidance. `docker-compose.yml` owns one portable `hermes` service and leaves authentication enforcement to Hermes.

**Named data shape:** No new organizing structure. The architect sketch skips architecture because this change adds only declarative app manifests.

**Tech Stack:** JSON, Docker Compose YAML, `jq`, `yq`, Docker CLI, Bun

## Global Constraints

- Implementation creates exactly `apps/hermes/app.json` and `apps/hermes/docker-compose.yml`.
- Use schema version `1.0`, metadata version `v2026.9.14`, image `nousresearch/hermes-agent:v2026.9.14`, and describe the application as Hermes Agent 0.21.3.
- Require `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` with an empty default. Do not add `HERMES_DASHBOARD_INSECURE` or a shared password.
- Do not add a README, local images, generated platform output, schema changes, converter changes, tests, custom networks, health checks, wrappers, extra services, or `x-casaos` Compose extensions.

---

### Task 1: Add the Hermes app definition

**Files:**

- Create: `apps/hermes/app.json`
- Create: `apps/hermes/docker-compose.yml`

**Interfaces:**

- Consumes: Universal app schema `1.0` from `schemas/app-schema-v1.json`; no code interfaces.
- Produces: App identity `hermes`, Compose project and service `hermes`, image `nousresearch/hermes-agent:v2026.9.14`, dashboard port `9119`, gateway API port `8642`, and named volume `hermes_data` mounted at `/opt/data`.

- [ ] **Step 1: Create `app.json`**

```json
{
  "spec_version": "1.0",
  "metadata": {
    "id": "hermes",
    "name": "Hermes Agent",
    "description": "Hermes Agent 0.21.3 is a self-hosted AI agent with a gateway API and an authenticated web dashboard.",
    "version": "v2026.9.14",
    "author": "BigBearCommunity",
    "developer": "Nous Research",
    "category": "BigBearCasaOS",
    "license": "MIT",
    "homepage": "https://hermes-agent.nousresearch.com/",
    "source": "big-bear-universal",
    "created": "2026-09-18T00:00:00Z",
    "updated": "2026-09-18T00:00:00Z"
  },
  "visual": {
    "icon": "https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Hermes/icon.svg",
    "thumbnail": "https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Hermes/thumbnail.png",
    "screenshots": [
      "https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Hermes/screenshot-1.png",
      "https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Hermes/screenshot-2.png",
      "https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Hermes/screenshot-3.png"
    ],
    "logo": "https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Hermes/icon.svg"
  },
  "resources": {
    "documentation": "https://hermes-agent.nousresearch.com/docs/",
    "repository": "https://github.com/NousResearch/hermes-agent",
    "issues": "https://github.com/NousResearch/hermes-agent/issues"
  },
  "technical": {
    "architectures": [
      "amd64",
      "arm64"
    ],
    "platform": "linux",
    "main_service": "hermes",
    "default_port": "9119",
    "main_image": "nousresearch/hermes-agent",
    "compose_file": "docker-compose.yml"
  },
  "deployment": {
    "environment_variables": [
      {
        "name": "HERMES_DASHBOARD",
        "default": "1",
        "description": "Enable the Hermes web dashboard.",
        "required": false
      },
      {
        "name": "HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
        "default": "zimaos",
        "description": "Username for dashboard basic authentication.",
        "required": false
      },
      {
        "name": "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD",
        "default": "",
        "description": "Provide a private password before startup. The dashboard refuses an empty password.",
        "required": true
      }
    ],
    "volumes": [
      {
        "container": "/opt/data",
        "description": "Persistent Hermes user data"
      }
    ],
    "ports": [
      {
        "container": "8642",
        "host": "8642",
        "protocol": "tcp",
        "description": "Gateway API"
      },
      {
        "container": "9119",
        "host": "9119",
        "protocol": "tcp",
        "description": "Authenticated web dashboard"
      }
    ]
  },
  "ui": {
    "scheme": "http",
    "path": "",
    "tips": {
      "before_install": {
        "en_us": "Set a private HERMES_DASHBOARD_BASIC_AUTH_PASSWORD before startup. The dashboard refuses an empty password. The default username is zimaos."
      }
    }
  },
  "compatibility": {
    "casaos": {
      "supported": true,
      "port_map": "9119",
      "category": "AI",
      "volume_mappings": {
        "hermes_data": "/DATA/AppData/$AppID/"
      }
    },
    "portainer": {
      "supported": true,
      "template_type": 2,
      "categories": [
        "BigBearCasaOS",
        "selfhosted"
      ],
      "administrator_only": false
    },
    "runtipi": {
      "supported": true,
      "tipi_version": 1,
      "supported_architectures": [
        "amd64",
        "arm64"
      ],
      "volume_mappings": {
        "hermes_data": "data"
      }
    },
    "dockge": {
      "supported": true,
      "file_based": true
    },
    "cosmos": {
      "supported": true,
      "servapp": true,
      "routes_required": true
    },
    "umbrel": {
      "supported": true,
      "manifest_version": 1,
      "volume_mappings": {
        "hermes_data": "data"
      }
    }
  },
  "tags": [
    "selfhosted",
    "docker",
    "bigbear",
    "bigbearcasaos",
    "ai",
    "agent",
    "automation"
  ]
}
```

- [ ] **Step 2: Create `docker-compose.yml`**

```yaml
name: hermes

services:
  hermes:
    image: nousresearch/hermes-agent:v2026.9.14
    container_name: hermes
    restart: unless-stopped
    command:
      - gateway
      - run
    ports:
      - "8642:8642"
      - "9119:9119"
    volumes:
      - hermes_data:/opt/data
    environment:
      HERMES_DASHBOARD: "1"
      HERMES_DASHBOARD_BASIC_AUTH_USERNAME: ${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-zimaos}
      HERMES_DASHBOARD_BASIC_AUTH_PASSWORD: ${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:-}
    deploy:
      resources:
        reservations:
          memory: 1G

volumes:
  hermes_data:
    name: hermes_data
    driver: local
```

- [ ] **Step 3: Validate syntax and the repository contract**

Run:

```bash
jq empty apps/hermes/app.json
yq eval '.' apps/hermes/docker-compose.yml >/dev/null
./scripts/validate-apps.sh -a hermes
```

Expected: both parsers exit `0`; the validator prints `hermes: PASSED`, `Failed: 0 apps`, and `Warnings: 0 total`.

- [ ] **Step 4: Verify exact metadata and platform mappings**

Run:

```bash
jq -e '
  .metadata.id == "hermes" and
  .metadata.version == "v2026.9.14" and
  (.metadata.description | contains("Hermes Agent 0.21.3")) and
  .metadata.created == "2026-09-18T00:00:00Z" and
  .metadata.updated == "2026-09-18T00:00:00Z" and
  .technical == {
    "architectures": ["amd64", "arm64"],
    "platform": "linux",
    "main_service": "hermes",
    "default_port": "9119",
    "main_image": "nousresearch/hermes-agent",
    "compose_file": "docker-compose.yml"
  } and
  .deployment.ports == [
    {"container": "8642", "host": "8642", "protocol": "tcp", "description": "Gateway API"},
    {"container": "9119", "host": "9119", "protocol": "tcp", "description": "Authenticated web dashboard"}
  ] and
  .deployment.volumes == [{"container": "/opt/data", "description": "Persistent Hermes user data"}] and
  ([.deployment.environment_variables[].name] == [
    "HERMES_DASHBOARD",
    "HERMES_DASHBOARD_BASIC_AUTH_USERNAME",
    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
  ]) and
  ([.deployment.environment_variables[] | select(.name == "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD")][0] | .default == "" and .required == true) and
  .compatibility.casaos == {
    "supported": true,
    "port_map": "9119",
    "category": "AI",
    "volume_mappings": {"hermes_data": "/DATA/AppData/$AppID/"}
  } and
  .compatibility.portainer == {
    "supported": true,
    "template_type": 2,
    "categories": ["BigBearCasaOS", "selfhosted"],
    "administrator_only": false
  } and
  .compatibility.runtipi == {
    "supported": true,
    "tipi_version": 1,
    "supported_architectures": ["amd64", "arm64"],
    "volume_mappings": {"hermes_data": "data"}
  } and
  .compatibility.dockge == {"supported": true, "file_based": true} and
  .compatibility.cosmos == {"supported": true, "servapp": true, "routes_required": true} and
  .compatibility.umbrel == {
    "supported": true,
    "manifest_version": 1,
    "volume_mappings": {"hermes_data": "data"}
  } and
  .tags == ["selfhosted", "docker", "bigbear", "bigbearcasaos", "ai", "agent", "automation"]
' apps/hermes/app.json
```

Expected: `true`.

- [ ] **Step 5: Verify the exact Compose runtime and interpolation**

Run:

```bash
yq eval -o=json '.' apps/hermes/docker-compose.yml | jq -e '
  .name == "hermes" and
  (.services | keys) == ["hermes"] and
  .services.hermes.image == "nousresearch/hermes-agent:v2026.9.14" and
  .services.hermes.container_name == "hermes" and
  .services.hermes.restart == "unless-stopped" and
  .services.hermes.command == ["gateway", "run"] and
  .services.hermes.ports == ["8642:8642", "9119:9119"] and
  .services.hermes.volumes == ["hermes_data:/opt/data"] and
  .services.hermes.environment.HERMES_DASHBOARD == "1" and
  .services.hermes.environment.HERMES_DASHBOARD_BASIC_AUTH_USERNAME == "${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-zimaos}" and
  .services.hermes.environment.HERMES_DASHBOARD_BASIC_AUTH_PASSWORD == "${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:-}" and
  .services.hermes.deploy.resources.reservations.memory == "1G" and
  .volumes.hermes_data == {"name": "hermes_data", "driver": "local"}
'
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=private-test-password docker compose -f apps/hermes/docker-compose.yml config --quiet
```

Expected: `jq` prints `true`; Compose exits `0` without output.

- [ ] **Step 6: Verify the published image architectures without pulling it**

Run:

```bash
docker manifest inspect nousresearch/hermes-agent:v2026.9.14 | jq -e '
  any(.manifests[]; .platform.os == "linux" and .platform.architecture == "amd64") and
  any(.manifests[]; .platform.os == "linux" and .platform.architecture == "arm64")
'
```

Expected: `true`.

- [ ] **Step 7: Run the existing regression test**

Run:

```bash
bun run test
```

Expected: exit `0` with all 7 tests passing from `./.github/scripts/update-app-version.test.js`.

- [ ] **Step 8: Check scope and forbidden content**

Run:

```bash
git status --short --untracked-files=all -- apps
! rg -n 'HERMES_DASHBOARD_INSECURE|x-casaos|TO[D]O|TB[D]' apps/hermes
git add -N apps/hermes/app.json apps/hermes/docker-compose.yml
git diff --check
```

Expected: status lists only `apps/hermes/app.json` and `apps/hermes/docker-compose.yml`; `rg` prints nothing; `git diff --check` prints nothing.

- [ ] **Step 9: Commit the app definition**

```bash
git add apps/hermes/app.json apps/hermes/docker-compose.yml
git commit -m "feat: add Hermes Agent"
```
