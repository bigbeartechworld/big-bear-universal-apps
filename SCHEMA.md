# Universal App Format Schema

This document describes the canonical Universal App Format used in Big Bear Universal Apps.

## Directory Structure

```
big-bear-universal-apps/
├── apps/
│   ├── jellyseerr/
│   │   ├── app.json              # Main metadata and configuration
│   │   ├── docker-compose.yml    # Standard Docker Compose file
│   │   └── README.md             # App-specific documentation (optional)
│   ├── plex/
│   │   ├── app.json
│   │   ├── docker-compose.yml
│   │   └── README.md
│   └── ...
├── schemas/
│   └── app-schema-v1.json        # JSON Schema for validation
├── scripts/
│   ├── convert-to-platforms.sh   # Convert universal → all platforms
│   ├── migrate-from-casaos.sh    # Migrate CasaOS → universal
│   └── validate-apps.sh          # Validate app.json files
└── README.md
```

## app.json Format

The `app.json` file is the source of truth for all app metadata and configuration.

### Example app.json

```json
{
  "spec_version": "1.0",
  "metadata": {
    "id": "jellyseerr",
    "name": "Jellyseerr",
    "description": "Jellyseerr is a free and open source software application for managing requests for your media library. It is a fork of Overseerr built to bring support for Jellyfin & Emby media servers!",
    "tagline": "Media request management for Jellyfin & Emby",
    "version": "2.7.3",
    "author": "BigBearCommunity",
    "developer": "Fallenbagel",
    "category": "Media",
    "license": "MIT",
    "homepage": "https://github.com/Fallenbagel/jellyseerr",
    "source": "big-bear-universal",
    "created": "2024-01-01T00:00:00Z",
    "updated": "2024-10-26T00:00:00Z"
  },
  "visual": {
    "icon": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/jellyseerr.png",
    "thumbnail": "https://cdn.jsdelivr.net/gh/IceWhaleTech/CasaOS-AppStore@main/Apps/Jellyseerr/thumbnail.jpg",
    "screenshots": [],
    "logo": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/jellyseerr.png"
  },
  "resources": {
    "youtube": "",
    "documentation": "https://docs.jellyseerr.dev/",
    "repository": "https://github.com/Fallenbagel/jellyseerr",
    "issues": "https://github.com/Fallenbagel/jellyseerr/issues",
    "support": "https://community.bigbeartechworld.com/"
  },
  "technical": {
    "architectures": ["amd64", "arm64"],
    "platform": "linux",
    "main_service": "app",
    "default_port": "5055",
    "main_image": "fallenbagel/jellyseerr",
    "compose_file": "docker-compose.yml"
  },
  "deployment": {
    "environment_variables": [
      {
        "name": "LOG_LEVEL",
        "default": "debug",
        "description": "Log level for the application",
        "required": false
      },
      {
        "name": "TZ",
        "default": "UTC",
        "description": "Timezone for the application",
        "required": false
      }
    ],
    "volumes": [
      {
        "container": "/app/config",
        "description": "Configuration directory"
      }
    ],
    "ports": [
      {
        "container": "5055",
        "host": "5055",
        "protocol": "tcp",
        "description": "Web UI"
      }
    ]
  },
  "ui": {
    "scheme": "http",
    "path": "",
    "tips": {}
  },
  "compatibility": {
    "casaos": {
      "supported": true,
      "port_map": "5055"
    },
    "portainer": {
      "supported": true,
      "template_type": 2,
      "categories": ["Media", "selfhosted"],
      "administrator_only": false
    },
    "runtipi": {
      "supported": true,
      "tipi_version": 1,
      "supported_architectures": ["amd64", "arm64"]
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
      "manifest_version": 1
    }
  },
  "tags": [
    "selfhosted",
    "docker",
    "bigbear",
    "media",
    "jellyfin",
    "emby",
    "requests"
  ]
}
```

## docker-compose.yml Format

The `docker-compose.yml` file should be a **clean, standard Docker Compose file** without any platform-specific extensions (no x-casaos, no custom labels, etc.).

### Example docker-compose.yml

```yaml
name: jellyseerr

services:
  app:
    image: fallenbagel/jellyseerr:2.7.3
    container_name: jellyseerr
    ports:
      - "5055:5055"
    volumes:
      - ./config:/app/config
    environment:
      - LOG_LEVEL=debug
      - TZ=UTC
    restart: unless-stopped
    network_mode: bridge
```

### Key Principles

1. **Clean and Standard**: No platform-specific extensions
2. **Portable**: Works with standard Docker Compose
3. **Relative Paths**: Use relative paths for volumes (e.g., `./config`)
4. **Explicit Versions**: Always specify image versions
5. **Container Names**: Include container names for clarity

## Conversion Process

The universal format is converted to platform-specific formats:

### CasaOS
- Adds `x-casaos` extensions to docker-compose.yml
- Creates config.json with version info
- Adjusts volume paths to `/DATA/AppData/$AppID/`

### Portainer
- Creates templates.json with all app metadata
- Converts environment variables to Portainer format
- Adds categories and descriptions

### Runtipi
- Creates config.json with app metadata
- Creates docker-compose.json with dynamic configuration
- Converts volumes to named volumes with app prefix
- Downloads/converts icon to logo.jpg

### Dockge
- Uses clean docker-compose.yml
- Creates metadata.json with app info

### Cosmos
- Creates cosmos-compose.json with routes
- Creates description.json with metadata

### Umbrel
- Creates umbrel-app.yml manifest
- Uses clean docker-compose.yml
- Adds gallery images and icon

## Validation

Apps can be validated using JSON Schema validation against `schemas/app-schema-v1.json`.

Required validations:
- ✅ Valid JSON syntax
- ✅ Required fields present
- ✅ Version format matches semver
- ✅ URLs are valid
- ✅ Architectures are valid values
- ✅ docker-compose.yml exists and is valid YAML
